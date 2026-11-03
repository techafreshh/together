extends Node
## Single source of truth for server identity and CLI shape.
## Owns VERSION, the default port, and --serve/--port argument parsing
## so the health body and the boot command can never drift apart.

const VERSION: String = "0.1.0"
const DEFAULT_PORT: int = 8080


## Parses OS.get_cmdline_user_args() style args (--serve flag, --port <n>
## value or --port=<n>). Invalid or missing ports fall back to DEFAULT_PORT.
static func parse_serve_args(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {"serve": false, "port": DEFAULT_PORT}
	var want_port_value := false
	for raw: String in args:
		var arg := raw.strip_edges()
		if want_port_value:
			want_port_value = false
			var n := _parse_port(arg)
			if n > 0:
				result["port"] = n
			continue
		if arg == "--serve":
			result["serve"] = true
		elif arg == "--port":
			want_port_value = true
		elif arg.begins_with("--port="):
			var inline := _parse_port(arg.get_slice("=", 1))
			if inline > 0:
				result["port"] = inline
	return result


static func _parse_port(text: String) -> int:
	var t := text.strip_edges()
	if not t.is_valid_int():
		return -1
	var n := t.to_int()
	if n < 1 or n > 65535:
		return -1
	return n
