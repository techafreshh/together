extends Node
## Single source of truth for server identity and CLI shape.
## Owns VERSION, the default port, and --serve/--port argument parsing
## so the health body and the boot command can never drift apart.

const VERSION: String = "0.1.0"
const DEFAULT_PORT: int = 8080
## Lobby caps for the rooms lobby (issue #10): at most MAX_ROOMS concurrent
## rooms, each staging between MIN_ROOM_PLAYERS and MAX_ROOM_PLAYERS players.
const MAX_ROOMS: int = 64
const MIN_ROOM_PLAYERS: int = 2
const MAX_ROOM_PLAYERS: int = 4
## Server-side JSON persistence (issue #17): one file per display name.
## `--data-dir` selects the directory (default `user://players`);
## `--max-rooms` caps concurrent rooms (default MAX_ROOMS, clamped 1..256).
const DEFAULT_DATA_DIR: String = "user://players"
const MIN_MAX_ROOMS: int = 1
const MAX_MAX_ROOMS: int = 256
## TLS mode for the headless server (issue #23): free-form non-empty string,
## default `"off"`; documented values `off` | `behind-proxy`. Unknown values
## are accepted verbatim and never fail boot — actual TLS termination stays
## operator work (Caddy/Cloudflare). Flag `--tls-mode` beats `TOGETHER_TLS_MODE`.
const DEFAULT_TLS_MODE: String = "off"


## Parses OS.get_cmdline_user_args() style args (--serve flag, --port <n>
## value or --port=<n>). Invalid or missing ports fall back to DEFAULT_PORT.
## Flag precedence: explicit flag > `TOGETHER_*` env > compiled default.
static func parse_serve_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"serve": false, "port": DEFAULT_PORT, "net_port": 0, "data_dir": DEFAULT_DATA_DIR, "max_rooms": MAX_ROOMS, "tls_mode": DEFAULT_TLS_MODE}
	if OS.has_environment("TOGETHER_PORT"):
		var env_port := _parse_port(OS.get_environment("TOGETHER_PORT"))
		if env_port > 0:
			result["port"] = env_port
	if OS.has_environment("TOGETHER_NET_PORT"):
		var env_net := _parse_port(OS.get_environment("TOGETHER_NET_PORT"))
		if env_net > 0:
			result["net_port"] = env_net
	if OS.has_environment("TOGETHER_DATA_DIR"):
		var env_dir := OS.get_environment("TOGETHER_DATA_DIR").strip_edges()
		if env_dir != "":
			result["data_dir"] = env_dir
	if OS.has_environment("TOGETHER_MAX_ROOMS"):
		var env_max := _parse_max_rooms(OS.get_environment("TOGETHER_MAX_ROOMS"))
		if env_max > 0:
			result["max_rooms"] = env_max
	if OS.has_environment("TOGETHER_TLS_MODE"):
		var env_tls := OS.get_environment("TOGETHER_TLS_MODE").strip_edges()
		if env_tls != "":
			result["tls_mode"] = env_tls
	var want_port_value := false
	var want_net_value := false
	var want_data_value := false
	var want_max_value := false
	var want_tls_value := false
	for raw: String in args:
		var arg := raw.strip_edges()
		if want_port_value:
			want_port_value = false
			var n := _parse_port(arg)
			if n > 0:
				result["port"] = n
			continue
		if want_net_value:
			want_net_value = false
			var m := _parse_port(arg)
			if m > 0:
				result["net_port"] = m
			continue
		if want_data_value:
			want_data_value = false
			var d := arg.strip_edges()
			if d != "":
				result["data_dir"] = d
			continue
		if want_max_value:
			want_max_value = false
			var r := _parse_max_rooms(arg)
			if r > 0:
				result["max_rooms"] = r
			continue
		if want_tls_value:
			want_tls_value = false
			var tv := arg.strip_edges()
			if tv != "":
				result["tls_mode"] = tv
			continue
		if arg == "--serve":
			result["serve"] = true
		elif arg == "--port":
			want_port_value = true
		elif arg == "--net-port":
			want_net_value = true
		elif arg == "--data-dir":
			want_data_value = true
		elif arg == "--max-rooms":
			want_max_value = true
		elif arg == "--tls-mode":
			want_tls_value = true
		elif arg.begins_with("--port="):
			var inline := _parse_port(arg.get_slice("=", 1))
			if inline > 0:
				result["port"] = inline
		elif arg.begins_with("--net-port="):
			var net_inline := _parse_port(arg.get_slice("=", 1))
			if net_inline > 0:
				result["net_port"] = net_inline
		elif arg.begins_with("--data-dir="):
			var data_inline := arg.get_slice("=", 1).strip_edges()
			if data_inline != "":
				result["data_dir"] = data_inline
		elif arg.begins_with("--max-rooms="):
			var max_inline := _parse_max_rooms(arg.get_slice("=", 1))
			if max_inline > 0:
				result["max_rooms"] = max_inline
		elif arg.begins_with("--tls-mode="):
			var tls_inline := arg.get_slice("=", 1).strip_edges()
			if tls_inline != "":
				result["tls_mode"] = tls_inline
	return result


static func _parse_max_rooms(text: String) -> int:
	var t := text.strip_edges()
	if not t.is_valid_int():
		return -1
	var n := t.to_int()
	if n < MIN_MAX_ROOMS or n > MAX_MAX_ROOMS:
		return -1
	return n


static func _parse_port(text: String) -> int:
	var t := text.strip_edges()
	if not t.is_valid_int():
		return -1
	var n := t.to_int()
	if n < 1 or n > 65535:
		return -1
	return n
