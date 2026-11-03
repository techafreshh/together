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
const GrabberScript := preload("res://actors/player/grabber.gd")
const TuningScript := preload("res://actors/player/tuning.gd")
const StageBaseScript := preload("res://stages/common/stage_base.gd")
const ButtonScript := preload("res://actors/props/button.gd")
const SequenceScript := preload("res://actors/props/sequence_buttons.gd")
const BoostScript := preload("res://actors/props/boost.gd")
const SeesawScript := preload("res://actors/props/seesaw.gd")
const LeverScript := preload("res://actors/props/lever.gd")
const SfxScript := preload("res://autoload/Sfx.gd")
const Stage01Script := preload("res://stages/world1/stage_01.gd")
const Stage02Script := preload("res://stages/world1/stage_02.gd")
const Stage03Script := preload("res://stages/world1/stage_03.gd")
const Stage04Script := preload("res://stages/world1/stage_04.gd")
const NetServerScript := preload("res://server/net_server.gd")
const RoomManagerScript := preload("res://server/room_manager.gd")
const FlowManagerScript := preload("res://server/flow_manager.gd")

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
	if cli.has("--selftest") and cli.has("grab"):
		_run_grab_selftest()
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
	if cli.has("--selftest") and cli.has("flow"):
		_run_flow_selftest()
		return
	if cli.has("--selftest") and cli.has("resilience"):
		_run_resilience_selftest()
		return
	if cli.has("--selftest") and cli.has("stages12"):
		_run_stages12_selftest()
		return
	if cli.has("--selftest") and cli.has("stages34"):
		_run_stages34_selftest()
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


## Offline grab self-test (issue #7). The acceptance probe runs
## `godot --headless --path . -- --selftest grab`, which boots the main
## scene, so the main-scene root owns this branch: drive the grabber
## holder state machine through grab -> slowed-carry -> throw with the
## checks shared with the grab test stage and quit.
func _run_grab_selftest() -> void:
	var result: Array = GrabberScript.run_selftest()
	var passed := int(result[0])
	var failed := int(result[1])
	var grabbed := 1 if failed == 0 else 0
	var carried := 1 if failed == 0 else 0
	var thrown := 1 if failed == 0 else 0
	if failed == 0:
		print("GRAB_OK grabbed=%d carried=%d thrown=%d" % [grabbed, carried, thrown])
	else:
		push_error("GRAB_FAIL grabbed=%d carried=%d thrown=%d failed=%d passed=%d" % [grabbed, carried, thrown, failed, passed])
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


## Offline flow self-test (issue #11). The acceptance probe runs
## `godot --headless --path . -- --selftest flow`, which boots the main
## scene, so the main-scene root owns this branch: create 1 room via the
## real RoomManager, join a second peer, host-select w1s1 through the real
## FlowManager, prove the non-host select is rejected, boot the stage, walk
## both peers into the goal, and build the coin results. Prints the FLOW_OK
## and HOST_GUARD_OK lines shared with the acceptance probe and quits.
func _run_flow_selftest() -> void:
	var failed := 0
	var boot_ok := 0
	var all_ok := 0
	var res_ok := 0
	var guard_ok := 0
	var rooms = RoomManagerScript.new()
	var flow = FlowManagerScript.new()
	var shared: Array = FlowManagerScript.run_selftest()
	failed += int(shared[1])
	var created: Dictionary = rooms.create_room("Host", "hash-host")
	var code := str(created.get("code", ""))
	var host_id := int(created.get("player_id", 0))
	var joined: Dictionary = rooms.join_room(code, "Guest", "hash-guest")
	var guest_id := int(joined.get("player_id", 0))
	if bool(created.get("ok", false)) and bool(joined.get("ok", false)) and code != "":
		flow.bind_room(code, [host_id, guest_id], host_id)
		var picked: Dictionary = flow.select_stage(code, host_id, host_id, "w1s1")
		var denied: Dictionary = flow.select_stage(code, guest_id, host_id, "w1s1")
		if not bool(denied.get("ok", false)) and str(denied.get("error", "")) == "host_only":
			guard_ok = 1
		else:
			failed += 1
			push_error("flow selftest: non-host select must fail host_only")
		if bool(picked.get("ok", false)):
			var started: Dictionary = flow.start_stage(code)
			var stage_boot: Dictionary = started.get("stage_boot", {})
			if bool(started.get("ok", false)) and str(stage_boot.get("stage_id", "")) == "w1s1" and (stage_boot.get("checkpoints", []) as Array).size() == 2 and (stage_boot.get("spawn_map", {}) as Dictionary).size() == 2:
				boot_ok = 1
			else:
				failed += 1
				push_error("flow selftest: stage_boot must carry stage_id, checkpoints, spawn_map")
			flow.notify_goal(code, host_id)
			if flow.is_goal_all(code):
				failed += 1
				push_error("flow selftest: single goal must not clear the stage")
			flow.notify_goal(code, guest_id)
			if flow.is_goal_all(code) and flow.goal_all(code):
				all_ok = 1
			else:
				failed += 1
				push_error("flow selftest: both goals must set goal_all")
			var built: Dictionary = flow.build_results(code)
			var results: Dictionary = built.get("results", {})
			if bool(built.get("ok", false)) and results.has("clears") and results.has("bests") and results.has("coins_awarded"):
				res_ok = 1
			else:
				failed += 1
				push_error("flow selftest: results must carry clears, bests, coins_awarded")
		else:
			failed += 1
			push_error("flow selftest: host select_stage w1s1 rejected")
	else:
		failed += 1
		push_error("flow selftest: room create+join for 2 peers failed")
	if failed == 0 and boot_ok == 1 and all_ok == 1 and res_ok == 1 and guard_ok == 1:
		print("FLOW_OK stage_boot=1 goal_all=1 results=1")
		print("HOST_GUARD_OK=1")
	else:
		push_error("FLOW_FAIL failed=%d boot=%d all=%d res=%d guard=%d" % [failed, boot_ok, all_ok, res_ok, guard_ok])
	get_tree().quit(1 if failed > 0 else 0)


## Offline resilience self-test (issue #12). Drives 3 peers through the
## mid-stage leave (room survives, stage continues), the mid-stage join
## (lobby_wait until the next stage_boot), and the below-2 restart (fresh
## stage_boot for the survivors). Prints RESILIENCE_OK on green and quits.
func _run_resilience_selftest() -> void:
	var failed := 0
	var continued := 0
	var restarted_below2 := 0
	var latejoin_lobby := 0
	var rooms = RoomManagerScript.new()
	var flow = FlowManagerScript.new()
	var created: Dictionary = rooms.create_room("P1", "hash-p1")
	var code := str(created.get("code", ""))
	var p1 := int(created.get("player_id", 0))
	var j2: Dictionary = rooms.join_room(code, "P2", "hash-p2")
	var j3: Dictionary = rooms.join_room(code, "P3", "hash-p3")
	var p2 := int(j2.get("player_id", 0))
	var p3 := int(j3.get("player_id", 0))
	if not (bool(created.get("ok", false)) and bool(j2.get("ok", false)) and bool(j3.get("ok", false)) and code != ""):
		failed += 1
		push_error("resilience selftest: 3-peer room setup failed")
	flow.bind_room(code, [p1, p2, p3], p1)
	var picked: Dictionary = flow.select_stage(code, p1, p1, "w1s1")
	if not bool(picked.get("ok", false)):
		failed += 1
		push_error("resilience selftest: host select w1s1 rejected")
	var started: Dictionary = flow.start_stage(code)
	var boot: Dictionary = started.get("stage_boot", {})
	if not (bool(started.get("ok", false)) and str(boot.get("stage_id", "")) == "w1s1"):
		failed += 1
		push_error("resilience selftest: start_stage boot invalid")
	if not bool(rooms.set_stage_active(code, true, boot).get("ok", false)):
		failed += 1
		push_error("resilience selftest: set_stage_active(true) rejected")
	var left3: Dictionary = rooms.leave_room(code, p3)
	var rem3: Dictionary = flow.remove_player(code, p3)
	if bool(left3.get("ok", false)) and not bool(left3.get("erased", false)) and int(left3.get("players_remaining", 0)) == 2:
		pass
	else:
		failed += 1
		push_error("resilience selftest: P3 leave must keep room alive with 2")
	if bool(rem3.get("ok", false)) and bool(rem3.get("continued", false)) and not bool(rem3.get("restarted", false)) and int(rem3.get("players", 0)) == 2:
		continued = 1
	else:
		failed += 1
		push_error("resilience selftest: P3 leave must continue stage with 2")
	var j4: Dictionary = rooms.join_room(code, "P4", "hash-p4")
	if not bool(j4.get("ok", false)) and str(j4.get("error", "")) == "lobby_wait":
		latejoin_lobby = 1
	else:
		failed += 1
		push_error("resilience selftest: mid-stage join must fail lobby_wait")
	var st_mid: Dictionary = rooms.room_state(code)
	var mid_players: Array = (st_mid.get("room_state", {}) as Dictionary).get("players", [])
	if mid_players.size() != 2:
		failed += 1
		push_error("resilience selftest: gated-out joiner must stay out of room_state")
	var left2: Dictionary = rooms.leave_room(code, p2)
	var rem2: Dictionary = flow.remove_player(code, p2)
	var fresh_boot: Dictionary = rem2.get("stage_boot", {})
	if bool(left2.get("ok", false)) and not bool(left2.get("erased", false)) and int(left2.get("players_remaining", 0)) == 1:
		pass
	else:
		failed += 1
		push_error("resilience selftest: P2 leave must keep room alive with 1")
	if bool(rem2.get("ok", false)) and bool(rem2.get("restarted", false)) and fresh_boot.size() > 0:
		restarted_below2 = 1
		rooms.set_stage_active(code, true, fresh_boot, "stage_restarted")
	else:
		failed += 1
		push_error("resilience selftest: drop below 2 must restart the stage")
	rooms.set_stage_active(code, false)
	var j4b: Dictionary = rooms.join_room(code, "P4", "hash-p4")
	var p4 := int(j4b.get("player_id", 0))
	if not bool(j4b.get("ok", false)):
		failed += 1
		push_error("resilience selftest: post-stage join must succeed")
	else:
		var st2: Dictionary = rooms.room_state(code)
		var ids2: Array = []
		for p in ((st2.get("room_state", {}) as Dictionary).get("players", []) as Array):
			ids2.append(int((p as Dictionary).get("id", 0)))
		flow.bind_room(code, ids2, int((st2.get("room_state", {}) as Dictionary).get("host_id", p1)))
		flow.select_stage(code, p1, p1, "w1s1")
		var started2: Dictionary = flow.start_stage(code)
		var boot2: Dictionary = started2.get("stage_boot", {})
		var spawns2: Dictionary = boot2.get("spawn_map", {})
		if bool(started2.get("ok", false)) and spawns2.has(p4):
			rooms.set_stage_active(code, true, boot2)
		else:
			failed += 1
			push_error("resilience selftest: next stage_boot spawn_map must cover P4")
	var events: Array = rooms.drain_events()
	var saw_state := false
	var saw_event := false
	for e in events:
		if str((e as Dictionary).get("msg", "")) == "room_state":
			saw_state = true
		if str((e as Dictionary).get("msg", "")) == "game_event":
			saw_event = true
	if not (saw_state and saw_event):
		failed += 1
		push_error("resilience selftest: outbox must hold room_state and game_event")
	if failed == 0 and continued == 1 and restarted_below2 == 1 and latejoin_lobby == 1:
		print("RESILIENCE_OK continued=1 restarted_below2=1 latejoin_lobby=1")
	else:
		push_error("RESILIENCE_FAIL failed=%d continued=%d restarted=%d lobby=%d" % [failed, continued, restarted_below2, latejoin_lobby])
	get_tree().quit(1 if failed > 0 else 0)


## Offline stages34 self-test (issue #14). The acceptance probe runs
## `godot --headless --path . -- --selftest stages34`, which boots the main
## scene, so the main-scene root owns this branch: load the world-1
## manifest via ConfigFile, run both stage run_selftest suites, prove the
## order predicates (stage_03 correct run completes, wrong step resets)
## and the gap predicates (stage_04 solo blocked, boosted duo crosses),
## count the live button/boost props via count_props, and print the
## STAGES34_OK and PROPS_OK lines shared with the probe. Quits 1 on any
## failure; touches no request/route/health paths.
func _run_stages34_selftest() -> void:
	var failed := 0
	var manifest := ConfigFile.new()
	if manifest.load("res://stages/world1/manifest.cfg") != OK:
		failed += 1
		push_error("stages34 selftest: manifest.cfg failed to load")
	else:
		var stages: Array = manifest.get_value("world1", "stages", [])
		if not (stages.has("w1s3") and stages.has("w1s4")):
			failed += 1
			push_error("stages34 selftest: manifest [world1] stages must list w1s3,w1s4")
		if not manifest.has_section("w1s3") or not manifest.has_section("w1s4"):
			failed += 1
			push_error("stages34 selftest: manifest must carry [w1s3] and [w1s4] sections")
		for section in ["w1s3", "w1s4"]:
			for key in ["scaling_2", "scaling_3", "scaling_4"]:
				if str(manifest.get_value(section, key, "")) == "":
					failed += 1
					push_error("stages34 selftest: manifest [%s] missing %s" % [section, key])
		if str(manifest.get_value("w1s3", "scene", "")) != "res://stages/world1/stage_03.tscn":
			failed += 1
			push_error("stages34 selftest: manifest [w1s3] scene must be stage_03.tscn")
		if str(manifest.get_value("w1s4", "scene", "")) != "res://stages/world1/stage_04.tscn":
			failed += 1
			push_error("stages34 selftest: manifest [w1s4] scene must be stage_04.tscn")
		if int(manifest.get_value("w1s4", "cross_required", 0)) != Stage04Script.CROSS_REQUIRED:
			failed += 1
			push_error("stages34 selftest: manifest [w1s4] cross_required must be 2")
	var r3: Array = Stage03Script.run_selftest()
	failed += int(r3[1])
	var r4: Array = Stage04Script.run_selftest()
	failed += int(r4[1])
	var s3_order := 0
	if Stage03Script.order_matches([0, 1, 2]) and not Stage03Script.order_matches([0, 2, 1]) and Stage03Script.next_progress(2, 2) == 3 and Stage03Script.next_progress(1, 2) == 0 and Stage03Script.gate_open(3) and not Stage03Script.gate_open(1) and int(r3[1]) == 0:
		s3_order = 1
	else:
		failed += 1
		push_error("stages34 selftest: stage_03 ordered run must complete and reset")
	var live_launch := false
	var probe_packed: PackedScene = load("res://stages/world1/stage_04.tscn") as PackedScene
	if probe_packed != null:
		var probe_stage: Node = probe_packed.instantiate() as Node
		if probe_stage != null:
			var pad := probe_stage.get_node_or_null("BoostPad")
			if pad != null and pad.has_method("activate") and pad.has_method("get_boost"):
				var probe = Stage04Script.BoostProbe.new()
				var want: Vector3 = pad.call("get_boost")
				pad.call("activate", probe)
				if probe.calls == 1 and probe.last_force == want:
					live_launch = true
				probe.free()
			probe_stage.free()
	var s4_boost := 0
	if Stage04Script.boost_crossable(Stage04Script.GAP_WIDTH) and live_launch and int(r4[1]) == 0:
		s4_boost = 1
	else:
		failed += 1
		push_error("stages34 selftest: stage_04 boosted crossing must launch")
	var s4_solo_blocked := 0
	if not Stage04Script.solo_crossable(Stage04Script.GAP_WIDTH) and not Stage04Script.cross_open(false, 1) and int(r4[1]) == 0:
		s4_solo_blocked = 1
	else:
		failed += 1
		push_error("stages34 selftest: stage_04 solo crossing must stay blocked")
	var button_count := 0
	var boost_count := 0
	var count_packed: PackedScene = load("res://stages/world1/stage_04.tscn") as PackedScene
	if count_packed != null:
		var count_stage: Node = count_packed.instantiate() as Node
		if count_stage != null and count_stage.has_method("count_props"):
			var counts: Dictionary = count_stage.call("count_props")
			button_count = int(counts.get("button", 0))
			boost_count = int(counts.get("boost", 0))
			count_stage.free()
	if button_count >= 1 and boost_count >= 1:
		print("PROPS_OK button=%d boost=%d" % [button_count, boost_count])
	else:
		failed += 1
		push_error("stages34 selftest: stage_04 must carry >=1 button and >=1 boost (got button=%d boost=%d)" % [button_count, boost_count])
	if failed == 0 and s3_order == 1 and s4_boost == 1 and s4_solo_blocked == 1:
		print("STAGES34_OK s3_order=1 s4_boost=1 s4_solo_blocked=1")
	else:
		push_error("STAGES34_FAIL failed=%d s3_order=%d s4_boost=%d s4_solo_blocked=%d" % [failed, s3_order, s4_boost, s4_solo_blocked])
	get_tree().quit(1 if failed > 0 else 0)


static func _header_end(buf: PackedByteArray) -> int:
	for i in range(buf.size() - 3):
		if buf[i] == 13 and buf[i + 1] == 10 and buf[i + 2] == 13 and buf[i + 3] == 10:
			return i
	return -1


## Offline stages12 self-test (issue #13). The acceptance probe runs
## `godot --headless --path . -- --selftest stages12`, which boots the main
## scene, so the main-scene root owns this branch: load the world-1
## manifest via ConfigFile, run both stage run_selftest suites, prove the
## bot predicates (stage_01 solo clears, stage_02 solo is blocked, duo
## passes), and print the STAGES12_OK line shared with the probe. Quits
## 1 on any failure; touches no request/route/health paths.
func _run_stages12_selftest() -> void:
	var failed := 0
	var manifest := ConfigFile.new()
	if manifest.load("res://stages/world1/manifest.cfg") != OK:
		failed += 1
		push_error("stages12 selftest: manifest.cfg failed to load")
	else:
		var stages: Array = manifest.get_value("world1", "stages", [])
		if not (stages.has("w1s1") and stages.has("w1s2")):
			failed += 1
			push_error("stages12 selftest: manifest [world1] stages must list w1s1,w1s2")
		if not manifest.has_section("w1s1") or not manifest.has_section("w1s2"):
			failed += 1
			push_error("stages12 selftest: manifest must carry [w1s1] and [w1s2] sections")
		for section in ["w1s1", "w1s2"]:
			for key in ["scaling_2", "scaling_3", "scaling_4"]:
				if str(manifest.get_value(section, key, "")) == "":
					failed += 1
					push_error("stages12 selftest: manifest [%s] missing %s" % [section, key])
		if int(manifest.get_value("w1s2", "hold_required", 0)) != Stage02Script.HOLD_REQUIRED:
			failed += 1
			push_error("stages12 selftest: manifest [w1s2] hold_required must be 2")
	var r1: Array = Stage01Script.run_selftest()
	failed += int(r1[1])
	var r2: Array = Stage02Script.run_selftest()
	failed += int(r2[1])
	var s1_solo := "fail"
	var s2_blocked := 0
	var s2_duo := "fail"
	if Stage01Script.solo_clear(2) and int(r1[1]) == 0:
		s1_solo = "pass"
	else:
		failed += 1
		push_error("stages12 selftest: stage_01 solo warmup must clear")
	if not Stage02Script.gate_open(1):
		s2_blocked = 1
	else:
		failed += 1
		push_error("stages12 selftest: stage_02 gate must stay closed for 1 holder (solo blocked)")
	if Stage02Script.gate_open(2) and int(r2[1]) == 0:
		s2_duo = "pass"
	else:
		failed += 1
		push_error("stages12 selftest: stage_02 gate must open for 2 holders (duo pass)")
	if failed == 0:
		print("STAGES12_OK s1_solo=pass s2_solo_blocked=1 s2_duo=pass")
	else:
		push_error("STAGES12_FAIL failed=%d s1_solo=%s s2_solo_blocked=%d s2_duo=%s" % [failed, s1_solo, s2_blocked, s2_duo])
	get_tree().quit(1 if failed > 0 else 0)

