extends Node
## Walking-skeleton headless server: single-port HTTP+WebSocket multiplexer.
##
## Boots via `godot --headless --path . -- --serve --port $PORT` and stays
## foreground. Serves plain-HTTP `GET /` health JSON, answers the RFC 6455
## WebSocket upgrade on `/ws` with `101 Switching Protocols` followed by a
## WebSocket close frame (then a TCP close, since the skeleton carries no
## game frames yet), and answers 4xx JSON for everything else. The two
## post-handshake bytes matter: plain-HTTP clients (curl) treat a bare 101
## as interim and report "empty reply" (exit 52) or hang (exit 28) unless
## response bytes complete the transfer, while WS clients see a valid
## close handshake. This responder never emits 5xx: malformed bytes get
## 400, unknown routes get 404, and every handler path is guarded.
##
## Design: parsing (_parse_request), routing (_route_request) and the accept
## computation (_compute_ws_accept) are stateless static funcs unit-testable
## without sockets; _process only accepts connections, enforces a read
## deadline, and dispatches. Each accepted stream is inspected first, so
## plain-HTTP health and the /ws upgrade share one port.

const ConfigScript := preload("res://autoload/Config.gd")
const ControllerScript := preload("res://actors/player/controller.gd")
const RagdollScript := preload("res://actors/player/ragdoll.gd")
const TuningScript := preload("res://actors/player/tuning.gd")
const StageBaseScript := preload("res://stages/common/stage_base.gd")
const ButtonScript := preload("res://actors/props/button.gd")
const SequenceScript := preload("res://actors/props/sequence_buttons.gd")
const BoostScript := preload("res://actors/props/boost.gd")
const SeesawScript := preload("res://actors/props/seesaw.gd")
const LeverScript := preload("res://actors/props/lever.gd")
const SfxScript := preload("res://autoload/Sfx.gd")
const NetServerScript := preload("res://server/net_server.gd")
const RoomManagerScript := preload("res://server/room_manager.gd")

const WS_GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
## Server-initiated WebSocket close frame (FIN + opcode 0x8, empty payload,
## unmasked as required for server-to-client frames). Sent right after the
## 101 headers so the upgrade completes with a valid close handshake.
static var WS_CLOSE_FRAME := PackedByteArray([0x88, 0x00])
const READ_DEADLINE_MSEC := 2000
const MAX_HEADER_BYTES := 16384

var _server: TCPServer
var _pending: Array = []
var _port: int = 8080
## Last accepted /ws join per client IP (msec); joins inside the
## NetServer cooldown window get 429 instead of a 101 upgrade.
var _ws_join_msec_by_ip: Dictionary = {}


func _ready() -> void:
	var cli: PackedStringArray = OS.get_cmdline_user_args()
	if cli.has("--selftest") and cli.has("controller"):
		_run_controller_selftest()
		return
	if cli.has("--selftest") and cli.has("flop"):
		_run_flop_selftest()
		return
	if cli.has("--selftest") and cli.has("scaffold"):
		_run_scaffold_selftest()
		return
	if cli.has("--selftest") and cli.has("net"):
		_run_net_selftest()
		return
	if cli.has("--selftest") and cli.has("props"):
		_run_props_selftest()
		return
	if cli.has("--selftest") and cli.has("sfx"):
		_run_sfx_selftest()
		return
	if cli.has("--selftest") and cli.has("rooms"):
		_run_rooms_selftest()
		return
	var parsed: Dictionary = ConfigScript.parse_serve_args(cli)
	if not bool(parsed.get("serve", false)):
		push_error("Usage: godot --headless --path . -- --serve --port <port>")
		get_tree().quit(1)
		return
	_port = int(parsed.get("port", ConfigScript.DEFAULT_PORT))
	_server = TCPServer.new()
	var err := _server.listen(_port, "*")
	if err != OK:
		push_error("together: failed to listen on port %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return
	print("together: serving on port %d (health GET /, socket /ws)" % _port)
	var net_port := int(parsed.get("net_port", 0))
	if net_port <= 0:
		net_port = _port + 1
	var net_server: Node = NetServerScript.new()
	net_server.name = "NetServer"
	add_child(net_server)
	var net_err: int = net_server.call("start_game_socket", net_port)
	if net_err != OK:
		push_warning("together: game socket on port %d unavailable (error %d); health only" % [net_port, net_err])
	else:
		print("together: game socket on port %d (input_state/snapshots)" % net_port)


func _process(_delta: float) -> void:
	if _server == null or not _server.is_listening():
		return
	while _server.is_connection_available():
		var stream := _server.take_connection()
		_pending.append({
			"conn": stream,
			"deadline": Time.get_ticks_msec() + READ_DEADLINE_MSEC,
			"buffer": PackedByteArray(),
		})
	var now := Time.get_ticks_msec()
	var still_pending: Array = []
	for item in _pending:
		var conn: StreamPeerTCP = item["conn"]
		var buf: PackedByteArray = item["buffer"]
		var avail := conn.get_available_bytes()
		if avail > 0:
			var chunk: Array = conn.get_data(avail)
			if chunk[0] == OK:
				buf.append_array(chunk[1])
				item["buffer"] = buf
		var end := _header_end(buf)
		if end >= 0:
			_handle_request(conn, buf.slice(0, end))
		elif buf.size() > MAX_HEADER_BYTES or now > int(item["deadline"]):
			_respond(conn, 400, JSON.stringify({"ok": false, "error": "bad_request"}))
		elif conn.get_status() == StreamPeerTCP.STATUS_NONE or conn.get_status() == StreamPeerTCP.STATUS_ERROR:
			pass # Client went away before sending headers; drop silently.
		else:
			still_pending.append(item)
	_pending = still_pending
	if _pending.is_empty():
		OS.delay_msec(1)


func _handle_request(conn: StreamPeerTCP, header_bytes: PackedByteArray) -> void:
	var req := _parse_request(header_bytes)
	if not bool(req.get("ok", false)):
		_respond(conn, 400, JSON.stringify({"ok": false, "error": "bad_request"}))
		return
	var method := str(req["method"])
	var path := str(req["path"])
	var headers: Dictionary = req["headers"]
	var status := _route_request(method, path, headers)
	if status == 200:
		_respond(conn, 200, _build_health_body())
		return
	if status == 101:
		var host := "unknown"
		if conn != null:
			host = str(conn.get_connected_host())
		var now := int(Time.get_ticks_msec())
		var last := int(_ws_join_msec_by_ip.get(host, -1))
		if not NetServerScript.is_join_allowed(last, now):
			_respond(conn, 429, JSON.stringify({"ok": false, "error": "rate_limited"}))
			return
		_ws_join_msec_by_ip[host] = now
		_handshake_ws(conn, str(headers.get("sec-websocket-key", "")).strip_edges())
		return
	if status == 400:
		_respond(conn, 400, JSON.stringify({"ok": false, "error": "bad_request"}))
		return
	_respond(conn, 404, JSON.stringify({"ok": false, "error": "not_found"}))


func _handshake_ws(conn: StreamPeerTCP, key: String) -> void:
	var head := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: %s\r\n\r\n" % _compute_ws_accept(key)
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	# One packet: valid 101 headers plus a WS close frame. Plain-HTTP
	# clients (curl -w '%{http_code}') need trailing bytes plus EOF to report
	# 101 with exit 0 instead of "empty reply" (52); WS clients observe a
	# normal 101 followed by a protocol-clean close. Game frames arrive in
	# a later lap, so the skeleton closes the TCP stream right after.
	conn.put_data(head.to_ascii_buffer() + WS_CLOSE_FRAME)
	conn.disconnect_from_host()


func _respond(conn: StreamPeerTCP, status: int, body: String) -> void:
	var reason := "Not Found"
	if status == 200:
		reason = "OK"
	elif status == 400:
		reason = "Bad Request"
	elif status == 429:
		reason = "Too Many Requests"
	var body_bytes := body.to_utf8_buffer()
	var head := "HTTP/1.1 %d %s\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n" % [status, reason, body_bytes.size()]
	if conn.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	conn.put_data(head.to_ascii_buffer())
	conn.put_data(body_bytes)
	conn.disconnect_from_host()


## --- Stateless request core (unit-tested, no sockets) ---


static func _parse_request(raw: PackedByteArray) -> Dictionary:
	var text := raw.get_string_from_ascii()
	var head: String = text.split("\r\n\r\n", true, 1)[0]
	var lines := head.split("\r\n")
	if lines.is_empty():
		return {"ok": false}
	var request_line := lines[0].split(" ", false)
	if request_line.size() != 3:
		return {"ok": false}
	var method := request_line[0].to_upper()
	var target := request_line[1]
	if method == "" or target == "" or not request_line[2].begins_with("HTTP/"):
		return {"ok": false}
	var path: String = target.split("?", true, 1)[0]
	if path == "":
		return {"ok": false}
	var headers := {}
	for i in range(1, lines.size()):
		var line := lines[i]
		if line == "":
			continue
		var colon := line.find(":")
		if colon <= 0:
			return {"ok": false}
		var header_name := line.substr(0, colon).strip_edges().to_lower()
		var header_value := line.substr(colon + 1).strip_edges()
		if header_name == "":
			return {"ok": false}
		headers[header_name] = header_value
	return {"ok": true, "method": method, "path": path, "headers": headers}


## Returns an HTTP status: 200 health, 101 upgrade, 400 malformed upgrade,
## 404 anything unknown. Never 500.
static func _route_request(method: String, path: String, headers: Dictionary) -> int:
	if path == "/" and method == "GET":
		return 200
	if path == "/ws":
		return _route_ws(method, headers)
	return 404


static func _route_ws(method: String, headers: Dictionary) -> int:
	if method != "GET":
		return 400
	if str(headers.get("upgrade", "")).to_lower() != "websocket":
		return 400
	if str(headers.get("sec-websocket-key", "")).strip_edges() == "":
		return 400
	var version := str(headers.get("sec-websocket-version", "")).strip_edges()
	if version != "" and version != "13":
		return 400
	return 101


static func _compute_ws_accept(key: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA1)
	ctx.update((key.strip_edges() + WS_GUID).to_utf8_buffer())
	return Marshalls.raw_to_base64(ctx.finish())


static func _build_health_body() -> String:
	return JSON.stringify({"ok": true, "version": ConfigScript.VERSION})


## Offline controller self-test (issue #3). The acceptance probe runs
## `godot --headless --path . -- --selftest controller`, which boots the
## main scene, so the main-scene root owns this branch: run the
## synchronous logic checks shared with the test stage and quit.
func _run_controller_selftest() -> void:
	var result: Array = ControllerScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("CONTROLLER_OK jump_arc_ms=%d coyote_ms=%d" % [TuningScript.jump_arc_ms(), TuningScript.coyote_ms])
	else:
		push_error("CONTROLLER_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Offline net self-test (issue #9). The acceptance probe runs
## `godot --headless --path . -- --selftest net`, which boots the main
## scene, so the main-scene root owns this branch: drive the two virtual
## peers through the fixed tick budget with the shared NetServer checks
## and quit. No sockets, no awaits.
func _run_net_selftest() -> void:
	var result: Array = NetServerScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("NET_OK peers=%d ticks=%d" % [NetServerScript.SELFTEST_PEERS, NetServerScript.SELFTEST_TICKS])
	else:
		push_error("NET_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Offline scaffold self-test (issue #5). The acceptance probe runs
## `godot --headless --path . -- --selftest scaffold`, so the main-scene
## root owns this branch: drive the stage scaffold checks shared with the
## stage script and quit. Both dummy avatars in the goal prints the OK line.
func _run_scaffold_selftest() -> void:
	var result: Array = StageBaseScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("GOAL_ALL_OK count=%d" % StageBaseScript.scaffold_goal_count())
	else:
		push_error("SCAFFOLD_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Offline prop-kit self-test (issue #6). The acceptance probe runs
## `godot --headless --path . -- --selftest props`, which boots the main
## scene, so the main-scene root owns this branch: aggregate the five prop
## self-tests and print the PROP_OK line shared with the kit demo stage.
func _run_props_selftest() -> void:
	var button_result: Array = ButtonScript.run_selftest()
	var sequence_result: Array = SequenceScript.run_selftest()
	var boost_result: Array = BoostScript.run_selftest()
	var seesaw_result: Array = SeesawScript.run_selftest()
	var lever_result: Array = LeverScript.run_selftest()
	var button_ok := 1 if int(button_result[1]) == 0 else 0
	var sequence_ok := 1 if int(sequence_result[1]) == 0 else 0
	var boost_ok := 1 if int(boost_result[1]) == 0 else 0
	var seesaw_ok := 1 if int(seesaw_result[1]) == 0 else 0
	var lever_ok := 1 if int(lever_result[1]) == 0 else 0
	var failed := int(button_result[1]) + int(sequence_result[1]) + int(boost_result[1]) + int(seesaw_result[1]) + int(lever_result[1])
	if failed == 0:
		print("PROP_OK button=1 sequence=1 boost=1 seesaw=1 lever=1")
	else:
		push_error("PROP_FAIL button=%d sequence=%d boost=%d seesaw=%d lever=%d" % [button_ok, sequence_ok, boost_ok, seesaw_ok, lever_ok])
	get_tree().quit(1 if failed > 0 else 0)


func _run_sfx_selftest() -> void:
	var result: Array = SfxScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("SFX_OK count=%d" % SfxScript.sfx_count())
	else:
		push_error("SFX_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


func _run_flop_selftest() -> void:
	var result: Array = ControllerScript.run_flop_selftest()
	var ragdoll_result: Array = RagdollScript.run_selftest()
	var failed := int(result[1]) + int(ragdoll_result[1])
	var respawn_ms := ControllerScript.simulate_flop_respawn_ms()
	if respawn_ms >= 3000:
		failed += 1
		push_error("flop selftest: respawn_ms=%d must be < 3000" % respawn_ms)
	if failed == 0:
		print("FLOP_OK respawn_ms=%d" % respawn_ms)
	else:
		push_error("FLOP_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Offline rooms self-test (issue #10). The acceptance probe runs
## `godot --headless --path . -- --selftest rooms`, which boots the main
## scene, so the main-scene root owns this branch: run the synchronous
## in-memory lobby checks shared with the room manager and quit.
func _run_rooms_selftest() -> void:
	var result: Array = RoomManagerScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("ROOMS_OK codes_unique=%d players=%d" % [RoomManagerScript.SELFTEST_ROOMS, RoomManagerScript.SELFTEST_PLAYERS])
	else:
		push_error("ROOMS_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


static func _header_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1

