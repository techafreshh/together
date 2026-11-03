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
const AudiovisualScript := preload("res://server/audiovisual.gd")
const PerfScript := preload("res://server/perf.gd")
const Stage01Script := preload("res://stages/world1/stage_01.gd")
const Stage02Script := preload("res://stages/world1/stage_02.gd")
const Stage03Script := preload("res://stages/world1/stage_03.gd")
const Stage04Script := preload("res://stages/world1/stage_04.gd")
const Stage05Script := preload("res://stages/world1/stage_05.gd")
const Stage06Script := preload("res://stages/world1/stage_06.gd")
const Stage07Script := preload("res://stages/world1/stage_07.gd")
const Stage08Script := preload("res://stages/world1/stage_08.gd")
const NetServerScript := preload("res://server/net_server.gd")
const RoomManagerScript := preload("res://server/room_manager.gd")
const FlowManagerScript := preload("res://server/flow_manager.gd")
const PersistenceScript := preload("res://server/persistence.gd")
const WardrobeScript := preload("res://server/wardrobe.gd")
const CosmeticsScript := preload("res://actors/player/cosmetics.gd")
const MainMenuScript := preload("res://scenes/main_menu.gd")
const LobbyScript := preload("res://scenes/lobby.gd")
const WardrobeUiScript := preload("res://scenes/wardrobe.gd")
const HudScript := preload("res://scenes/hud.gd")
const ResultsScript := preload("res://scenes/results.gd")

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
## Effective server data dir for JSON persistence (issue #17), owned by
## _ready from ConfigScript.parse_serve_args (`--data-dir`, else default).
var _data_dir: String = "user://players"
## Effective concurrent-room cap (`--max-rooms`, else Config.MAX_ROOMS).
var _max_rooms: int = 64
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
	if cli.has("--selftest") and cli.has("audiovisual"):
		_run_audiovisual_selftest()
		return
	if cli.has("--selftest") and (cli.has("perf") or cli.has("performance")):
		_run_perf_selftest()
		return
	if cli.has("--selftest") and cli.has("rooms"):
		_run_rooms_selftest()
		return
	if cli.has("--selftest") and cli.has("flow"):
		_run_flow_selftest()
		return
	if cli.has("--selftest") and cli.has("persist"):
		_run_persist_selftest()
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
	if cli.has("--selftest") and cli.has("stages56"):
		_run_stages56_selftest()
		return
	if cli.has("--selftest") and cli.has("stages78"):
		_run_stages78_selftest()
		return
	if cli.has("--selftest") and cli.has("world14"):
		_run_world14_selftest()
		return
	if cli.has("--selftest") and cli.has("wardrobe"):
		_run_wardrobe_selftest()
		return
	var export_idx := cli.find("--export-check")
	if export_idx >= 0 and export_idx + 1 < cli.size() and cli[export_idx + 1] == "web":
		_run_export_check()
		return
	if cli.has("--selftest") and cli.has("export"):
		_run_export_check()
		return
	if cli.has("--selftest") and cli.has("ui"):
		_run_ui_selftest()
		return
	var parsed: Dictionary = ConfigScript.parse_serve_args(cli)
	if not bool(parsed.get("serve", false)):
		push_error("Usage: godot --headless --path . -- --serve --port <port>")
		get_tree().quit(1)
		return
	_port = int(parsed.get("port", ConfigScript.DEFAULT_PORT))
	_data_dir = str(parsed.get("data_dir", ConfigScript.DEFAULT_DATA_DIR))
	_max_rooms = int(parsed.get("max_rooms", ConfigScript.MAX_ROOMS))
	PersistenceScript.ensure_dir(_data_dir)
	_server = TCPServer.new()
	var err := _server.listen(_port, "*")
	if err != OK:
		push_error("together: failed to listen on port %d (error %d)" % [_port, err])
		get_tree().quit(1)
		return
	print("together: serving on port %d (health GET /, socket /ws) data_dir=%s" % [_port, _data_dir])
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


## --- Web export surface (issue #21, parse-level, no templates) ---
## Socket-free static checks shared by the headless `--export-check web`
## branch and the tests/test_export_logic.gd unit runner.

## Scans cfg_path via ConfigFile for a preset.N section whose name
## contains "Web" with platform == "Web". Returns {preset=0/1}.
static func check_export_preset(cfg_path: String) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(cfg_path) != OK:
		return {"preset": 0}
	for section in cfg.get_sections():
		if not section.begins_with("preset.") or section.ends_with(".options"):
			continue
		var pname := str(cfg.get_value(section, "name", ""))
		var platform := str(cfg.get_value(section, "platform", ""))
		if pname.contains("Web") and platform == "Web":
			return {"preset": 1}
	return {"preset": 0}


## Reads the Pages _headers file and requires both cross-origin isolation
## policies. Returns {headers=0/1}.
static func check_web_headers(headers_path: String) -> Dictionary:
	if not FileAccess.file_exists(headers_path):
		return {"headers": 0}
	var text := FileAccess.get_file_as_string(headers_path)
	if text.contains("Cross-Origin-Opener-Policy") and text.contains("Cross-Origin-Embedder-Policy"):
		return {"headers": 1}
	return {"headers": 0}


## The standalone boot indicator must exist and mention loading.
## Returns 1 on pass, 0 otherwise.
static func check_loading_indicator(loading_path: String) -> int:
	if not FileAccess.file_exists(loading_path):
		return 0
	if FileAccess.get_file_as_string(loading_path).to_lower().contains("loading"):
		return 1
	return 0


## Offline web-export self-test (issue #21). The acceptance probe runs
## `godot --headless --path . -- --export-check web`, which boots the main
## scene, so the main-scene root owns this branch: run the three
## parse-level static checks above (no export templates installed in CI)
## and print the EXPORT_WEB_OK line shared with the probe. Quits 1 on any
## failure; touches no request/route/health paths.
func _run_export_check() -> void:
	var preset := check_export_preset("res://export_presets.cfg")
	var headers := check_web_headers("res://web/_headers")
	var loading := check_loading_indicator("res://web/loading.html")
	var p := int(preset.get("preset", 0))
	var h := int(headers.get("headers", 0))
	if p == 1 and h == 1 and loading == 1:
		print("EXPORT_WEB_OK preset=%d headers=%d" % [p, h])
		get_tree().quit(0)
	else:
		push_error("EXPORT_WEB_FAIL preset=%d headers=%d loading=%d" % [p, h, loading])
		get_tree().quit(1)


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


## Offline audiovisual self-test (issue #20). The acceptance probe runs
## `godot --headless --path . -- --selftest audiovisual`, which boots the
## main scene, so the main-scene root owns this branch: prove the single
## looping music track, the full SFX set, and the palette recolor hold,
## then print the AV_OK line shared with the probe. Quits 1 on failure;
## touches no request/route/health paths.
func _run_audiovisual_selftest() -> void:
	var result: Array = AudiovisualScript.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("AV_OK music=1 sfx>=8 palette=1")
	else:
		push_error("AV_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Native perf self-test stub (issue #20). The acceptance probe runs
## `godot --headless --path . -- --selftest perf`, which boots the main
## scene, so the main-scene root owns this branch: run the budget-const
## checks, then print PERF_SKIPPED_HEADLESS=1 under headless CI (no vsync
## or GPU timing there) or FPS_OK on real hardware. Never crashes; quits
## 1 only when the const checks themselves fail.
func _run_perf_selftest() -> void:
	var result: Array = PerfScript.run_selftest()
	var failed := int(result[1])
	if failed != 0:
		push_error("PERF_FAIL failed=%d" % failed)
		get_tree().quit(1)
		return
	if PerfScript.is_headless():
		print("PERF_SKIPPED_HEADLESS=1")
	else:
		print("FPS_OK")
	get_tree().quit(0)


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


## Offline UI self-test (issue #19). The acceptance probe runs
## `godot --headless --path . -- --selftest ui`, which boots the main
## scene, so the main-scene root owns this branch: load each of the five
## menu-flow scenes, instantiate it, prove every required_nodes() path
## resolves, prove the .tscn and .gd file texts each carry the `Net.`
## autoload placeholder, then print the UI_OK line shared with the probe.
## The lobby StagePicker + BestsLabel pair feeds the picker flag. Quits 1
## on any failure; touches no request/route/health paths.
func _run_ui_selftest() -> void:
	var failed := 0
	var menu := 0
	var lobby := 0
	var picker := 0
	var hud := 0
	var results := 0
	var scenes := [
		{"key": "menu", "tscn": "res://scenes/main_menu.tscn", "gd": "res://scenes/main_menu.gd", "script": MainMenuScript},
		{"key": "lobby", "tscn": "res://scenes/lobby.tscn", "gd": "res://scenes/lobby.gd", "script": LobbyScript},
		{"key": "wardrobe", "tscn": "res://scenes/wardrobe.tscn", "gd": "res://scenes/wardrobe.gd", "script": WardrobeUiScript},
		{"key": "hud", "tscn": "res://scenes/hud.tscn", "gd": "res://scenes/hud.gd", "script": HudScript},
		{"key": "results", "tscn": "res://scenes/results.tscn", "gd": "res://scenes/results.gd", "script": ResultsScript},
	]
	for entry in scenes:
		var key := str(entry.get("key", ""))
		var tscn_path := str(entry.get("tscn", ""))
		var gd_path := str(entry.get("gd", ""))
		var packed: PackedScene = load(tscn_path) as PackedScene
		if packed == null:
			failed += 1
			push_error("ui selftest: %s failed to load" % tscn_path)
			continue
		var node: Node = packed.instantiate() as Node
		if node == null:
			failed += 1
			push_error("ui selftest: %s failed to instantiate" % tscn_path)
			continue
		var needed: Array = (entry.get("script", null) as Script).call("required_nodes")
		var paths_ok := true
		for p in needed:
			if node.get_node_or_null(str(p)) == null:
				paths_ok = false
				failed += 1
				push_error("ui selftest: %s misses node %s" % [tscn_path, str(p)])
		if paths_ok:
			if key == "menu":
				menu = 1
			elif key == "lobby":
				lobby = 1
				if node.get_node_or_null("StagePicker") != null and node.get_node_or_null("BestsLabel") != null:
					picker = 1
				else:
					failed += 1
					push_error("ui selftest: lobby misses StagePicker + BestsLabel")
			elif key == "hud":
				hud = 1
			elif key == "results":
				results = 1
		var tscn_text := FileAccess.get_file_as_string(tscn_path)
		if not tscn_text.contains("Net."):
			failed += 1
			push_error("ui selftest: %s misses Net. placeholder" % tscn_path)
		var gd_text := FileAccess.get_file_as_string(gd_path)
		if not gd_text.contains("Net."):
			failed += 1
			push_error("ui selftest: %s misses Net. placeholder" % gd_path)
		node.free()
	if failed == 0 and menu == 1 and lobby == 1 and picker == 1 and hud == 1 and results == 1:
		print("UI_OK menu=1 lobby=1 picker=1 hud=1 results=1")
	else:
		push_error("UI_FAIL failed=%d menu=%d lobby=%d picker=%d hud=%d results=%d" % [failed, menu, lobby, picker, hud, results])
	get_tree().quit(1 if failed > 0 else 0)


## Offline persist self-test (issue #17). The acceptance probe runs
## `godot --headless --path . -- --selftest persist --data-dir <tmp>`,
## which boots the main scene, so the main-scene root owns this branch:
## resolve the data dir from `--data-dir <p>` / `--data-dir=<p>` (falling
## back to OS.get_temp_dir() when the flag is absent), delegate to the
## tree-free PersistenceScript.run_selftest round-trip, and print the
## PERSIST_OK line shared with the probe. Quits 1 on any failure; touches
## no request/route/health paths.
func _run_persist_selftest() -> void:
	var cli: PackedStringArray = OS.get_cmdline_user_args()
	var dir := ""
	var has_flag := false
	for i in range(cli.size()):
		var a := cli[i].strip_edges()
		if a == "--data-dir":
			has_flag = true
			if i + 1 < cli.size():
				dir = cli[i + 1].strip_edges()
		elif a.begins_with("--data-dir="):
			has_flag = true
			dir = a.get_slice("=", 1).strip_edges()
	if not has_flag or dir == "":
		if not has_flag:
			dir = OS.get_temp_dir()
		else:
			var parsed: Dictionary = ConfigScript.parse_serve_args(cli)
			dir = str(parsed.get("data_dir", OS.get_temp_dir()))
			if dir.strip_edges() == "":
				dir = OS.get_temp_dir()
	var result: Array = PersistenceScript.run_selftest(dir)
	var failed := int(result[1])
	if failed == 0:
		print("PERSIST_OK coins=1 restart_survives=1")
	else:
		push_error("PERSIST_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)


## Persistence edge helpers (issue #17): the live join/results path rides
## the serve edge so room_manager/flow_manager stay pure. Load on join
## returns the stored profile (defaults on first sight); save on results
## records the clear, credits coins, and rewrites the JSON. Both are
## warn-only on IO failure: they never 5xx, never quit.
func _persist_load_on_join(display_name: String) -> Dictionary:
	return PersistenceScript.load_player(_data_dir, display_name)


func _persist_save_on_results(display_name: String, stage_id: String, best_ms: int, coins_awarded: int) -> bool:
	var profile: Dictionary = PersistenceScript.load_player(_data_dir, display_name)
	PersistenceScript.record_clear(profile, stage_id, best_ms)
	PersistenceScript.add_coins(profile, coins_awarded)
	if not PersistenceScript.save_player(_data_dir, display_name, profile):
		push_warning("together: persist save failed for %s" % display_name)
		return false
	return true


func _persist_save_on_purchase(display_name: String, item_id: String, price: int) -> Dictionary:
	var profile: Dictionary = PersistenceScript.load_player(_data_dir, display_name)
	var bought: Dictionary = PersistenceScript.try_purchase(profile, item_id, price)
	if bool(bought.get("ok", false)):
		if not PersistenceScript.save_player(_data_dir, display_name, profile):
			push_warning("together: persist save failed for %s" % display_name)
			return {"ok": false, "error": "save_failed"}
	return bought


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


## Offline stages78 self-test (issue #16). The acceptance probe runs
## `godot --headless --path . -- --selftest stages78`, which boots the main
## scene, so the main-scene root owns this branch: load the world-1
## manifest via ConfigFile, run both stage run_selftest suites, prove the
## timed-pair predicates (stage_07 in-window pairs complete, slow and
## unset stamps stay blocked) and the remix predicates (stage_08 opens only
## when all five verbs hold), count the live lever/remix props via
## count_props, and print the STAGES78_OK line shared with the probe.
## Quits 1 on any failure; touches no request/route/health paths.
func _run_stages78_selftest() -> void:
	var failed := 0
	var manifest := ConfigFile.new()
	if manifest.load("res://stages/world1/manifest.cfg") != OK:
		failed += 1
		push_error("stages78 selftest: manifest.cfg failed to load")
	else:
		var stages: Array = manifest.get_value("world1", "stages", [])
		var want := ["w1s1", "w1s2", "w1s3", "w1s4", "w1s5", "w1s6", "w1s7", "w1s8"]
		for wid in want:
			if not stages.has(wid):
				failed += 1
				push_error("stages78 selftest: manifest [world1] stages must list %s" % wid)
		if not manifest.has_section("w1s7") or not manifest.has_section("w1s8"):
			failed += 1
			push_error("stages78 selftest: manifest must carry [w1s7] and [w1s8] sections")
		for section in ["w1s7", "w1s8"]:
			for key in ["scaling_2", "scaling_3", "scaling_4"]:
				if str(manifest.get_value(section, key, "")) == "":
					failed += 1
					push_error("stages78 selftest: manifest [%s] missing %s" % [section, key])
		if str(manifest.get_value("w1s7", "scene", "")) != "res://stages/world1/stage_07.tscn":
			failed += 1
			push_error("stages78 selftest: manifest [w1s7] scene must be stage_07.tscn")
		if str(manifest.get_value("w1s8", "scene", "")) != "res://stages/world1/stage_08.tscn":
			failed += 1
			push_error("stages78 selftest: manifest [w1s8] scene must be stage_08.tscn")
		if int(manifest.get_value("w1s7", "pair_required", 0)) != Stage07Script.PAIR_REQUIRED:
			failed += 1
			push_error("stages78 selftest: manifest [w1s7] pair_required must be 2")
		if int(manifest.get_value("w1s7", "window_ms", 0)) != Stage07Script.PAIR_WINDOW_MS:
			failed += 1
			push_error("stages78 selftest: manifest [w1s7] window_ms must be 2000")
		if int(manifest.get_value("w1s8", "cross_required", 0)) != Stage08Script.CROSS_REQUIRED:
			failed += 1
			push_error("stages78 selftest: manifest [w1s8] cross_required must be 2")
		if int(manifest.get_value("w1s8", "carry_required", 0)) != Stage08Script.CARRY_REQUIRED:
			failed += 1
			push_error("stages78 selftest: manifest [w1s8] carry_required must be 2")
	if Stage07Script.PAIR_WINDOW_MS != LeverScript.PAIR_WINDOW_MS:
		failed += 1
		push_error("stages78 selftest: stage_07 window must equal the lever prop window")
	var r7: Array = Stage07Script.run_selftest()
	failed += int(r7[1])
	var r8: Array = Stage08Script.run_selftest()
	failed += int(r8[1])
	var s7_timed := 0
	if Stage07Script.pair_complete(1000, 1500) and Stage07Script.timed_open(1000, 1500) and Stage07Script.gate_open(true) and not Stage07Script.pair_complete(0, 5000) and not Stage07Script.pair_complete(-1, 500) and not Stage07Script.timed_open(0, 5000) and not Stage07Script.gate_open(false) and int(r7[1]) == 0:
		var lever_packed: PackedScene = load("res://stages/world1/stage_07.tscn") as PackedScene
		if lever_packed != null:
			var lever_stage: Node = lever_packed.instantiate() as Node
			if lever_stage != null:
				var levers := lever_stage.get_node_or_null("LeverPair")
				if levers != null and levers.has_method("pull_a") and levers.has_method("pull_b") and levers.has_method("is_paired"):
					levers.call("pull_a", 1000)
					var single_unpaired := not bool(levers.call("is_paired"))
					levers.call("pull_b", 1500)
					var pair_latched := bool(levers.call("is_paired"))
					levers.call("reset")
					var reset_clears := not bool(levers.call("is_paired"))
					if single_unpaired and pair_latched and reset_clears:
						s7_timed = 1
					else:
						failed += 1
						push_error("stages78 selftest: live LeverPair must block single pulls and latch in-window pairs")
				else:
					failed += 1
					push_error("stages78 selftest: stage_07 LeverPair node missing")
				lever_stage.free()
	else:
		failed += 1
		push_error("stages78 selftest: stage_07 timed pair must complete in-window and block slow runs")
	var s8_remix := 0
	var button_count := 0
	var sequence_count := 0
	var boost_count := 0
	var seesaw_count := 0
	var relay_count := 0
	var remix_packed: PackedScene = load("res://stages/world1/stage_08.tscn") as PackedScene
	if remix_packed != null:
		var remix_stage: Node = remix_packed.instantiate() as Node
		if remix_stage != null:
			var hold := remix_stage.get_node_or_null("HoldButton")
			var pads := remix_stage.get_node_or_null("SeqPads")
			var pad := remix_stage.get_node_or_null("BoostPad")
			var saw := remix_stage.get_node_or_null("SeeSaw")
			var relay_a := remix_stage.get_node_or_null("RelayA")
			var relay_b := remix_stage.get_node_or_null("RelayB")
			if hold != null and hold.has_method("press") and hold.has_method("is_down") and pads != null and pads.has_method("press_step") and pads.has_method("is_done") and pad != null and pad.has_method("activate") and pad.has_method("get_boost") and saw != null and saw.has_method("press_left") and saw.has_method("press_right") and saw.has_method("is_balanced") and relay_a != null and relay_a.has_method("is_down") and relay_b != null and relay_b.has_method("is_down"):
				hold.call("press")
				pads.call("press_step", 0)
				pads.call("press_step", 1)
				pads.call("press_step", 2)
				var probe = Stage08Script.BoostProbe.new()
				var want: Vector3 = pad.call("get_boost")
				pad.call("activate", probe)
				var launched: bool = probe.calls == 1 and probe.last_force == want
				probe.free()
				saw.call("press_left")
				var tips_alone := int(saw.call("get_tilt")) == -1 and not bool(saw.call("is_balanced"))
				saw.call("press_right")
				var balances := bool(saw.call("is_balanced"))
				relay_a.call("press")
				relay_b.call("press")
				var carriers := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
				var hold_down := bool(hold.call("is_down"))
				var seq_done := bool(pads.call("is_done"))
				var boost_ready := (pad.call("get_boost") as Vector3).y > 0.0
				var balanced := bool(saw.call("is_balanced"))
				if hold_down and seq_done and boost_ready and launched and tips_alone and balances and carriers == 2 and Stage08Script.remix_open(hold_down, seq_done, boost_ready, balanced, true, carriers) and not Stage08Script.remix_open(hold_down, seq_done, boost_ready, balanced, false, carriers) and not Stage08Script.remix_open(false, seq_done, boost_ready, balanced, true, carriers) and int(r8[1]) == 0:
					s8_remix = 1
				else:
					failed += 1
					push_error("stages78 selftest: stage_08 finale remix must open only when all five verbs hold")
			else:
				failed += 1
				push_error("stages78 selftest: stage_08 finale prop nodes missing")
			if remix_stage.has_method("count_props"):
				var counts: Dictionary = remix_stage.call("count_props")
				button_count = int(counts.get("button", 0))
				sequence_count = int(counts.get("sequence", 0))
				boost_count = int(counts.get("boost", 0))
				seesaw_count = int(counts.get("seesaw", 0))
				relay_count = int(counts.get("relay", 0))
			remix_stage.free()
	var lever_count := 0
	var probe7: PackedScene = load("res://stages/world1/stage_07.tscn") as PackedScene
	if probe7 != null:
		var count_stage7: Node = probe7.instantiate() as Node
		if count_stage7 != null and count_stage7.has_method("count_props"):
			lever_count = int((count_stage7.call("count_props") as Dictionary).get("lever", 0))
			count_stage7.free()
	if lever_count < 1:
		failed += 1
		push_error("stages78 selftest: expected >=1 lever (got lever=%d)" % lever_count)
	if button_count < 1 or sequence_count < 1 or boost_count < 1 or seesaw_count < 1 or relay_count < 2:
		failed += 1
		push_error("stages78 selftest: expected >=1 button/sequence/boost/seesaw and >=2 relays (got button=%d sequence=%d boost=%d seesaw=%d relay=%d)" % [button_count, sequence_count, boost_count, seesaw_count, relay_count])
	if failed == 0 and s7_timed == 1 and s8_remix == 1:
		print("STAGES78_OK s7_timed=1 s8_remix=1")
	else:
		push_error("STAGES78_FAIL failed=%d s7_timed=%d s8_remix=%d" % [failed, s7_timed, s8_remix])
	get_tree().quit(1 if failed > 0 else 0)


## Offline world sweep self-test (issue #16). The acceptance probe runs
## `godot --headless --path . -- --selftest world14` (world 1, 2/3/4
## players across all 8 stages), which boots the main scene, so the
## main-scene root owns this branch: load the world-1 manifest via
## ConfigFile, prove every stage beatable by full-roster goal entry with
## 2, 3, and 4 dummies, and prove stages 02-08 solo-blocked through their
## static gates (stage 01 stays the soloable control). Prints the WORLD_OK
## line shared with the probe. Quits 1 on any failure; touches no
## request/route/health paths.
func _run_world14_selftest() -> void:
	var failed := 0
	var want := ["w1s1", "w1s2", "w1s3", "w1s4", "w1s5", "w1s6", "w1s7", "w1s8"]
	var scenes := {
		"w1s1": "res://stages/world1/stage_01.tscn",
		"w1s2": "res://stages/world1/stage_02.tscn",
		"w1s3": "res://stages/world1/stage_03.tscn",
		"w1s4": "res://stages/world1/stage_04.tscn",
		"w1s5": "res://stages/world1/stage_05.tscn",
		"w1s6": "res://stages/world1/stage_06.tscn",
		"w1s7": "res://stages/world1/stage_07.tscn",
		"w1s8": "res://stages/world1/stage_08.tscn",
	}
	var manifest := ConfigFile.new()
	if manifest.load("res://stages/world1/manifest.cfg") != OK:
		failed += 1
		push_error("world14 selftest: manifest.cfg failed to load")
	else:
		var listed: Array = manifest.get_value("world1", "stages", [])
		for wid in want:
			if not listed.has(wid):
				failed += 1
				push_error("world14 selftest: manifest [world1] stages must list %s" % wid)
			if not manifest.has_section(wid):
				failed += 1
				push_error("world14 selftest: manifest must carry [%s]" % wid)
		for wid in want:
			for key in ["scaling_2", "scaling_3", "scaling_4"]:
				if str(manifest.get_value(wid, key, "")) == "":
					failed += 1
					push_error("world14 selftest: manifest [%s] missing %s" % [wid, key])
	if not Stage01Script.solo_clear(1):
		failed += 1
		push_error("world14 selftest: stage_01 warmup must stay solo-clearable (control)")
	if Stage02Script.gate_open(1):
		failed += 1
		push_error("world14 selftest: stage_02 gate must stay closed for 1 holder")
	if Stage03Script.gate_open(1):
		failed += 1
		push_error("world14 selftest: stage_03 gate must stay closed at progress 1")
	if Stage04Script.cross_open(true, 1) or Stage04Script.cross_open(false, 2) or Stage04Script.solo_crossable(Stage04Script.GAP_WIDTH):
		failed += 1
		push_error("world14 selftest: stage_04 solo crossings must stay blocked")
	if Stage05Script.gate_open(1, 0) or Stage05Script.gate_open(0, 1):
		failed += 1
		push_error("world14 selftest: stage_05 solo sides must stay blocked")
	if Stage06Script.cross_open(true, 1) or Stage06Script.cross_open(false, 2) or Stage06Script.solo_crossable(Stage06Script.GAP_WIDTH):
		failed += 1
		push_error("world14 selftest: stage_06 solo crossings must stay blocked")
	if Stage07Script.pair_complete(0, 5000) or Stage07Script.pair_complete(-1, 500) or Stage07Script.gate_open(false):
		failed += 1
		push_error("world14 selftest: stage_07 single and slow lever runs must stay blocked")
	if Stage08Script.remix_open(false, true, true, true, true, 2) or Stage08Script.remix_open(true, true, true, true, true, 1) or Stage08Script.remix_open(true, true, true, true, false, 2):
		failed += 1
		push_error("world14 selftest: stage_08 solo remix runs must stay blocked")
	var players2 := 0
	var players3 := 0
	var players4 := 0
	for n in [2, 3, 4]:
		var sweep_ok := true
		for wid in want:
			var packed: PackedScene = load(str(scenes[wid])) as PackedScene
			if packed == null:
				failed += 1
				sweep_ok = false
				push_error("world14 selftest: %s failed to load" % wid)
				continue
			var stage: Node = packed.instantiate() as Node
			if stage == null:
				failed += 1
				sweep_ok = false
				push_error("world14 selftest: %s failed to instantiate" % wid)
				continue
			var all_hits := [0]
			stage.connect("goal_all_reached", func(): all_hits[0] += 1)
			var dummies: Array = []
			for i in range(n):
				var d := Node.new()
				dummies.append(d)
				stage.call("notify_goal_entered", d)
			if int(stage.call("goal_count")) != n or not bool(stage.call("is_goal_complete")) or all_hits[0] < 1:
				failed += 1
				sweep_ok = false
				push_error("world14 selftest: %s must complete with %d in the goal" % [wid, n])
			for d in dummies:
				d.free()
			stage.free()
		if sweep_ok:
			if n == 2:
				players2 = 1
			elif n == 3:
				players3 = 1
			elif n == 4:
				players4 = 1
	var lever_solo := 0
	var lever7: PackedScene = load("res://stages/world1/stage_07.tscn") as PackedScene
	if lever7 != null:
		var solo_stage: Node = lever7.instantiate() as Node
		if solo_stage != null:
			var levers := solo_stage.get_node_or_null("LeverPair")
			if levers != null and levers.has_method("pull_a") and levers.has_method("is_paired"):
				levers.call("pull_a", 1000)
				if not bool(levers.call("is_paired")):
					lever_solo = 1
				else:
					failed += 1
					push_error("world14 selftest: stage_07 single pull must stay unpaired")
			else:
				failed += 1
				push_error("world14 selftest: stage_07 LeverPair node missing")
			solo_stage.free()
	if failed == 0 and players2 == 1 and players3 == 1 and players4 == 1 and lever_solo == 1:
		print("WORLD_OK players2=1 players3=1 players4=1")
	else:
		push_error("WORLD_FAIL failed=%d players2=%d players3=%d players4=%d lever_solo=%d" % [failed, players2, players3, players4, lever_solo])
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


## Offline stages56 self-test (issue #15). The acceptance probe runs
## `godot --headless --path . -- --selftest stages56`, which boots the main
## scene, so the main-scene root owns this branch: load the world-1
## manifest via ConfigFile, run both stage run_selftest suites, prove the
## see-saw predicates (stage_05 distributed weight balances, solo sides
## stay blocked) and the gap predicates (stage_06 solo blocked, carried
## duo crosses), count the live seesaw/relay props, and print the
## STAGES56_OK line shared with the probe. Quits 1 on any failure;
## touches no request/route/health paths.
func _run_stages56_selftest() -> void:
	var failed := 0
	var manifest := ConfigFile.new()
	if manifest.load("res://stages/world1/manifest.cfg") != OK:
		failed += 1
		push_error("stages56 selftest: manifest.cfg failed to load")
	else:
		var stages: Array = manifest.get_value("world1", "stages", [])
		if not (stages.has("w1s5") and stages.has("w1s6")):
			failed += 1
			push_error("stages56 selftest: manifest [world1] stages must list w1s5,w1s6")
		if not manifest.has_section("w1s5") or not manifest.has_section("w1s6"):
			failed += 1
			push_error("stages56 selftest: manifest must carry [w1s5] and [w1s6] sections")
		for section in ["w1s5", "w1s6"]:
			for key in ["scaling_2", "scaling_3", "scaling_4"]:
				if str(manifest.get_value(section, key, "")) == "":
					failed += 1
					push_error("stages56 selftest: manifest [%s] missing %s" % [section, key])
		if str(manifest.get_value("w1s5", "scene", "")) != "res://stages/world1/stage_05.tscn":
			failed += 1
			push_error("stages56 selftest: manifest [w1s5] scene must be stage_05.tscn")
		if str(manifest.get_value("w1s6", "scene", "")) != "res://stages/world1/stage_06.tscn":
			failed += 1
			push_error("stages56 selftest: manifest [w1s6] scene must be stage_06.tscn")
		if int(manifest.get_value("w1s5", "weight_required", 0)) != Stage05Script.WEIGHT_REQUIRED:
			failed += 1
			push_error("stages56 selftest: manifest [w1s5] weight_required must be 2")
		if float(manifest.get_value("w1s6", "gap_width", 0.0)) != Stage06Script.GAP_WIDTH:
			failed += 1
			push_error("stages56 selftest: manifest [w1s6] gap_width must be 12.0")
		if int(manifest.get_value("w1s6", "carry_required", 0)) != Stage06Script.CARRY_REQUIRED:
			failed += 1
			push_error("stages56 selftest: manifest [w1s6] carry_required must be 2")
	var r5: Array = Stage05Script.run_selftest()
	failed += int(r5[1])
	var r6: Array = Stage06Script.run_selftest()
	failed += int(r6[1])
	var s5_weight := 0
	var saw_packed: PackedScene = load("res://stages/world1/stage_05.tscn") as PackedScene
	if saw_packed != null:
		var saw_stage: Node = saw_packed.instantiate() as Node
		if saw_stage != null:
			var saw := saw_stage.get_node_or_null("SeeSaw")
			if saw != null and saw.has_method("press_left") and saw.has_method("press_right") and saw.has_method("is_balanced"):
				saw.call("press_left")
				var tips_alone := int(saw.call("get_tilt")) == -1 and not bool(saw.call("is_balanced"))
				saw.call("press_right")
				var balances := int(saw.call("get_tilt")) == 0 and bool(saw.call("is_balanced"))
				if Stage05Script.weight_ok(true, true) and not Stage05Script.weight_ok(true, false) and Stage05Script.gate_open(1, 1) and not Stage05Script.gate_open(1, 0) and tips_alone and balances and int(r5[1]) == 0:
					s5_weight = 1
				else:
					failed += 1
					push_error("stages56 selftest: stage_05 distributed weight must balance")
			else:
				failed += 1
				push_error("stages56 selftest: stage_05 SeeSaw node missing")
			saw_stage.free()
	var s6_carry := 0
	var s6_solo_blocked := 0
	var relay_packed: PackedScene = load("res://stages/world1/stage_06.tscn") as PackedScene
	if relay_packed != null:
		var relay_stage: Node = relay_packed.instantiate() as Node
		if relay_stage != null:
			var relay_a := relay_stage.get_node_or_null("RelayA")
			var relay_b := relay_stage.get_node_or_null("RelayB")
			if relay_a != null and relay_b != null and relay_a.has_method("is_down") and relay_b.has_method("is_down"):
				var starts_up := not bool(relay_a.call("is_down")) and not bool(relay_b.call("is_down"))
				relay_a.call("press")
				var single_holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
				var single_closed := single_holders == 1 and not Stage06Script.cross_open(true, single_holders)
				relay_b.call("press")
				var duo_holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
				if Stage06Script.carry_crossable(Stage06Script.GAP_WIDTH) and duo_holders == 2 and Stage06Script.cross_open(true, duo_holders) and single_closed and int(r6[1]) == 0:
					s6_carry = 1
				else:
					failed += 1
					push_error("stages56 selftest: stage_06 carried duo must open the crossing")
				if starts_up and not Stage06Script.solo_crossable(Stage06Script.GAP_WIDTH) and not Stage06Script.cross_open(false, 1) and not Stage06Script.cross_open(true, 1) and int(r6[1]) == 0:
					s6_solo_blocked = 1
				else:
					failed += 1
					push_error("stages56 selftest: stage_06 solo crossing must stay blocked")
			else:
				failed += 1
				push_error("stages56 selftest: stage_06 RelayA/RelayB nodes missing")
			relay_stage.free()
	var seesaw_count := 0
	var relay_count := 0
	var probe5: PackedScene = load("res://stages/world1/stage_05.tscn") as PackedScene
	if probe5 != null:
		var count_stage5: Node = probe5.instantiate() as Node
		if count_stage5 != null and count_stage5.has_method("count_props"):
			var counts5: Dictionary = count_stage5.call("count_props")
			seesaw_count = int(counts5.get("seesaw", 0))
			count_stage5.free()
	var probe6: PackedScene = load("res://stages/world1/stage_06.tscn") as PackedScene
	if probe6 != null:
		var count_stage6: Node = probe6.instantiate() as Node
		if count_stage6 != null and count_stage6.has_method("count_props"):
			var counts6: Dictionary = count_stage6.call("count_props")
			relay_count = int(counts6.get("relay", 0))
			count_stage6.free()
	if seesaw_count < 1 or relay_count < 2:
		failed += 1
		push_error("stages56 selftest: expected >=1 seesaw and >=2 relays (got seesaw=%d relay=%d)" % [seesaw_count, relay_count])
	if failed == 0 and s5_weight == 1 and s6_carry == 1 and s6_solo_blocked == 1:
		print("STAGES56_OK s5_weight=1 s6_carry=1 s6_solo_blocked=1")
	else:
		push_error("STAGES56_FAIL failed=%d s5_weight=%d s6_carry=%d s6_solo_blocked=%d" % [failed, s5_weight, s6_carry, s6_solo_blocked])
	get_tree().quit(1 if failed > 0 else 0)



## Offline wardrobe self-test (issue #18). The acceptance probe runs
## `godot --headless --path . -- --selftest wardrobe`, which boots the main
## scene, so the main-scene root owns this branch: count the on-disk hat
## scenes and skin cfgs, fund an in-memory profile with one full run of
## coins, purchase hat_cone plus the cheapest skin, equip both, attach the
## hat to a probe player and assert visibility, print the WARDROBE_OK line
## plus the player JSON (which must carry "owned" and hat_cone), then prove
## cosmetic replication across 2 room peers through the NetServer snapshot
## `cos` field and print COSMETIC_REPL_OK. Quits 1 on any failure; needs no
## --data-dir and touches no request/route/health paths.
func _run_wardrobe_selftest() -> void:
	var failed := 0
	var shared: Array = WardrobeScript.run_selftest()
	failed += int(shared[1])
	var hats := WardrobeScript.hats_count()
	var skins := WardrobeScript.skins_count()
	if hats < 6 or hats > 10:
		failed += 1
		push_error("wardrobe selftest: expected 6-10 hats on disk (got %d)" % hats)
	if skins != 4:
		failed += 1
		push_error("wardrobe selftest: expected 4 skins on disk (got %d)" % skins)
	var profile: Dictionary = WardrobeScript.default_profile()
	profile["coins"] = WardrobeScript.full_run_coins()
	var bought_hat: Dictionary = WardrobeScript.try_purchase(profile, "hat_cone")
	var cheapest_skin := "charcoal"
	var cheapest_price := 1 << 30
	for skin_id in WardrobeScript.SKIN_IDS:
		var price := WardrobeScript.price_for(skin_id)
		if price >= 0 and price < cheapest_price:
			cheapest_price = price
			cheapest_skin = str(skin_id)
	var bought_skin: Dictionary = WardrobeScript.try_purchase(profile, cheapest_skin)
	var purchase := 0
	if bool(bought_hat.get("ok", false)) and bool(bought_skin.get("ok", false)):
		purchase = 1
	else:
		failed += 1
		push_error("wardrobe selftest: funded profile must buy hat_cone + %s" % cheapest_skin)
	var wear_hat: Dictionary = WardrobeScript.equip(profile, "hat", "hat_cone")
	var wear_skin: Dictionary = WardrobeScript.equip(profile, "skin", cheapest_skin)
	if not (bool(wear_hat.get("ok", false)) and bool(wear_skin.get("ok", false))):
		failed += 1
		push_error("wardrobe selftest: owned hat+skin must equip")
	var equip_visible := 0
	var probe_packed: PackedScene = load("res://actors/player/player.tscn") as PackedScene
	if probe_packed == null:
		failed += 1
		push_error("wardrobe selftest: player.tscn failed to load")
	else:
		var probe: Node = probe_packed.instantiate() as Node
		if probe == null:
			failed += 1
			push_error("wardrobe selftest: player failed to instantiate")
		else:
			if probe.get_node_or_null("HatAnchor") == null:
				failed += 1
				push_error("wardrobe selftest: player misses HatAnchor")
			if not CosmeticsScript.attach_hat(probe, "hat_cone"):
				failed += 1
				push_error("wardrobe selftest: attach_hat hat_cone failed")
			if not CosmeticsScript.apply_skin(probe, cheapest_skin):
				failed += 1
				push_error("wardrobe selftest: apply_skin %s failed" % cheapest_skin)
			if CosmeticsScript.is_hat_visible(probe):
				equip_visible = 1
			else:
				failed += 1
				push_error("wardrobe selftest: equipped hat must be visible")
			probe.free()
	var showroom: PackedScene = load("res://scenes/wardrobe.tscn") as PackedScene
	if showroom == null:
		failed += 1
		push_error("wardrobe selftest: scenes/wardrobe.tscn failed to load")
	else:
		var room_node: Node = showroom.instantiate() as Node
		if room_node == null or room_node.get_node_or_null("HatAnchor") == null or room_node.get_node_or_null("SkinPreview") == null:
			failed += 1
			push_error("wardrobe selftest: wardrobe showroom must carry HatAnchor + SkinPreview")
		elif room_node != null:
			room_node.free()
	if failed == 0 and purchase == 1 and equip_visible == 1:
		print("WARDROBE_OK hats=%d skins=%d purchase=1 equip_visible=1" % [hats, skins])
	else:
		push_error("WARDROBE_FAIL failed=%d hats=%d skins=%d purchase=%d equip_visible=%d" % [failed, hats, skins, purchase, equip_visible])
	print(JSON.stringify(profile))
	var repl_ok := 0
	var rooms = RoomManagerScript.new()
	var created: Dictionary = rooms.create_room("Host", "hash-host")
	var code := str(created.get("code", ""))
	var host_id := int(created.get("player_id", 0))
	var joined: Dictionary = rooms.join_room(code, "Guest", "hash-guest")
	var guest_id := int(joined.get("player_id", 0))
	if bool(created.get("ok", false)) and bool(joined.get("ok", false)) and code != "":
		var net = NetServerScript.new()
		net.set_cosmetic(host_id, {"hat": "hat_cone", "skin": "charcoal"})
		net.set_cosmetic(guest_id, {"hat": "hat_crown", "skin": "mint"})
		if str(net.cosmetic_for(host_id).get("hat", "")) != "hat_cone":
			failed += 1
			push_error("wardrobe selftest: cosmetic_for must echo the host hat")
		var states := {
			host_id: {"p": Vector3.ZERO, "v": Vector3.ZERO},
			guest_id: {"p": Vector3(1.0, 0.0, 0.0), "v": Vector3.ZERO},
		}
		var cos := {}
		cos[host_id] = net.cosmetic_for(host_id)
		cos[guest_id] = net.cosmetic_for(guest_id)
		var snap: Dictionary = NetServerScript.make_snapshot(1, states, cos)
		var peers: Dictionary = snap.get("peers", {})
		var host_cos: Dictionary = (peers.get(host_id, {}) as Dictionary).get("cos", {})
		var guest_cos: Dictionary = (peers.get(guest_id, {}) as Dictionary).get("cos", {})
		if str(host_cos.get("hat", "")) == "hat_cone" and str(guest_cos.get("hat", "")) == "hat_crown" and str(host_cos.get("skin", "")) == "charcoal" and str(guest_cos.get("skin", "")) == "mint":
			repl_ok = 1
		else:
			failed += 1
			push_error("wardrobe selftest: snapshot must carry distinct cos per peer")
		net.free()
	else:
		failed += 1
		push_error("wardrobe selftest: 2-peer room setup failed")
	if repl_ok == 1:
		print("COSMETIC_REPL_OK=1")
	else:
		push_error("COSMETIC_REPL_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)
