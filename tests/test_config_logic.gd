extends SceneTree
## Unit runner for the server config surface (issue #23): flag/env/default
## precedence for --port/--net-port/--data-dir/--max-rooms/--tls-mode and
## the socket-free Serve.check_config static shared with the `--selftest
## config` headless branch. Pattern mirrors tests/test_export_logic.gd:
## SceneTree runner with own counters, assert_eq-style helpers, per-test
## methods, and quit(1 if failed > 0 else 0).
## Run: godot --headless --path . --script res://tests/test_config_logic.gd

const Config := preload("res://autoload/Config.gd")
const Serve := preload("res://server/serve.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_defaults",
		"test_port_forms",
		"test_data_dir_forms",
		"test_max_rooms_forms",
		"test_tls_mode_forms",
		"test_invalid_fallback",
		"test_env_fallback",
		"test_flag_beats_env",
		"test_check_config_custom",
		"test_check_config_defaults",
		"test_check_config_env",
	]:
		if call(t) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % t)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


## Blank every TOGETHER_* var the parser reads so tests never leak into
## each other (empty reads fall back to the compiled defaults).
func _clear_env() -> void:
	for name in ["TOGETHER_PORT", "TOGETHER_NET_PORT", "TOGETHER_DATA_DIR", "TOGETHER_MAX_ROOMS", "TOGETHER_TLS_MODE"]:
		OS.set_environment(name, "")


## Bare args yield the compiled defaults.
func test_defaults() -> bool:
	_clear_env()
	var p := Config.parse_serve_args(PackedStringArray([]))
	assert_eq(bool(p.get("serve", true)), false, "serve defaults off")
	assert_eq(int(p.get("port", -1)), Config.DEFAULT_PORT, "port defaults to DEFAULT_PORT")
	assert_eq(int(p.get("net_port", -1)), 0, "net_port defaults to 0")
	assert_eq(str(p.get("data_dir", "")), Config.DEFAULT_DATA_DIR, "data_dir defaults")
	assert_eq(int(p.get("max_rooms", -1)), Config.MAX_ROOMS, "max_rooms defaults to MAX_ROOMS")
	assert_eq(str(p.get("tls_mode", "")), "off", "tls_mode defaults to off")
	assert_eq(Config.DEFAULT_TLS_MODE, "off", "DEFAULT_TLS_MODE is off")
	return true


## --port in space and = forms; --serve still detected alongside.
func test_port_forms() -> bool:
	_clear_env()
	var space := Config.parse_serve_args(PackedStringArray(["--serve", "--port", "9001"]))
	assert_eq(int(space.get("port", -1)), 9001, "space-form port wins")
	assert_eq(bool(space.get("serve", false)), true, "serve flag detected")
	var inline := Config.parse_serve_args(PackedStringArray(["--port=9002"]))
	assert_eq(int(inline.get("port", -1)), 9002, "equals-form port wins")
	var net := Config.parse_serve_args(PackedStringArray(["--net-port", "9003"]))
	assert_eq(int(net.get("net_port", -1)), 9003, "space-form net port wins")
	var net_inline := Config.parse_serve_args(PackedStringArray(["--net-port=9004"]))
	assert_eq(int(net_inline.get("net_port", -1)), 9004, "equals-form net port wins")
	return true


## --data-dir in space and = forms.
func test_data_dir_forms() -> bool:
	_clear_env()
	var space := Config.parse_serve_args(PackedStringArray(["--data-dir", "/tmp/space-dir"]))
	assert_eq(str(space.get("data_dir", "")), "/tmp/space-dir", "space-form data dir wins")
	var inline := Config.parse_serve_args(PackedStringArray(["--data-dir=/tmp/equals-dir"]))
	assert_eq(str(inline.get("data_dir", "")), "/tmp/equals-dir", "equals-form data dir wins")
	return true


## --max-rooms in space and = forms, clamped 1..256.
func test_max_rooms_forms() -> bool:
	_clear_env()
	var space := Config.parse_serve_args(PackedStringArray(["--max-rooms", "7"]))
	assert_eq(int(space.get("max_rooms", -1)), 7, "space-form max rooms wins")
	var inline := Config.parse_serve_args(PackedStringArray(["--max-rooms=12"]))
	assert_eq(int(inline.get("max_rooms", -1)), 12, "equals-form max rooms wins")
	return true


## --tls-mode in space and = forms; unknown values pass through verbatim.
func test_tls_mode_forms() -> bool:
	_clear_env()
	var space := Config.parse_serve_args(PackedStringArray(["--tls-mode", "behind-proxy"]))
	assert_eq(str(space.get("tls_mode", "")), "behind-proxy", "space-form tls mode wins")
	var inline := Config.parse_serve_args(PackedStringArray(["--tls-mode=off"]))
	assert_eq(str(inline.get("tls_mode", "")), "off", "equals-form tls mode wins")
	var odd := Config.parse_serve_args(PackedStringArray(["--tls-mode", "weird-future"]))
	assert_eq(str(odd.get("tls_mode", "")), "weird-future", "unknown tls mode accepted verbatim")
	return true


## Invalid values never fail: env/default survives the bad flag.
func test_invalid_fallback() -> bool:
	_clear_env()
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--port", "abc"])).get("port", -1)), Config.DEFAULT_PORT, "garbage port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--port", "0"])).get("port", -1)), Config.DEFAULT_PORT, "zero port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--port", "99999"])).get("port", -1)), Config.DEFAULT_PORT, "huge port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--port=abc"])).get("port", -1)), Config.DEFAULT_PORT, "garbage inline port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--port"])).get("port", -1)), Config.DEFAULT_PORT, "dangling port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--max-rooms", "0"])).get("max_rooms", -1)), Config.MAX_ROOMS, "zero rooms falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--max-rooms", "999"])).get("max_rooms", -1)), Config.MAX_ROOMS, "huge rooms falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray(["--max-rooms", "nope"])).get("max_rooms", -1)), Config.MAX_ROOMS, "garbage rooms falls back")
	assert_eq(str(Config.parse_serve_args(PackedStringArray(["--data-dir", ""])).get("data_dir", "")), Config.DEFAULT_DATA_DIR, "empty data dir falls back")
	assert_eq(str(Config.parse_serve_args(PackedStringArray(["--tls-mode", ""])).get("tls_mode", "")), "off", "empty tls mode falls back")
	OS.set_environment("TOGETHER_PORT", "bogus")
	OS.set_environment("TOGETHER_MAX_ROOMS", "bogus")
	assert_eq(int(Config.parse_serve_args(PackedStringArray([])).get("port", -1)), Config.DEFAULT_PORT, "garbage env port falls back")
	assert_eq(int(Config.parse_serve_args(PackedStringArray([])).get("max_rooms", -1)), Config.MAX_ROOMS, "garbage env rooms falls back")
	_clear_env()
	return true


## TOGETHER_* env seeds the defaults when no flag is present.
func test_env_fallback() -> bool:
	_clear_env()
	OS.set_environment("TOGETHER_PORT", "9101")
	OS.set_environment("TOGETHER_NET_PORT", "9102")
	OS.set_environment("TOGETHER_DATA_DIR", "/tmp/env-dir")
	OS.set_environment("TOGETHER_MAX_ROOMS", "9")
	OS.set_environment("TOGETHER_TLS_MODE", "behind-proxy")
	var p := Config.parse_serve_args(PackedStringArray([]))
	assert_eq(int(p.get("port", -1)), 9101, "env port seeds default")
	assert_eq(int(p.get("net_port", -1)), 9102, "env net port seeds default")
	assert_eq(str(p.get("data_dir", "")), "/tmp/env-dir", "env data dir seeds default")
	assert_eq(int(p.get("max_rooms", -1)), 9, "env max rooms seeds default")
	assert_eq(str(p.get("tls_mode", "")), "behind-proxy", "env tls mode seeds default")
	_clear_env()
	return true


## An explicit flag beats the env for every option.
func test_flag_beats_env() -> bool:
	_clear_env()
	OS.set_environment("TOGETHER_PORT", "9101")
	OS.set_environment("TOGETHER_DATA_DIR", "/tmp/env-dir")
	OS.set_environment("TOGETHER_MAX_ROOMS", "9")
	OS.set_environment("TOGETHER_TLS_MODE", "behind-proxy")
	var p := Config.parse_serve_args(PackedStringArray(["--port", "9201", "--data-dir=/tmp/flag-dir", "--max-rooms", "7", "--tls-mode=off"]))
	assert_eq(int(p.get("port", -1)), 9201, "flag port beats env")
	assert_eq(str(p.get("data_dir", "")), "/tmp/flag-dir", "flag data dir beats env")
	assert_eq(int(p.get("max_rooms", -1)), 7, "flag max rooms beats env")
	assert_eq(str(p.get("tls_mode", "")), "off", "flag tls mode beats env")
	OS.set_environment("TOGETHER_PORT", "notaport")
	var keep := Config.parse_serve_args(PackedStringArray(["--port", "9202"]))
	assert_eq(int(keep.get("port", -1)), 9202, "flag port survives garbage env")
	_clear_env()
	return true


## check_config reports all ones for custom flags (both spellings).
func test_check_config_custom() -> bool:
	_clear_env()
	var space := Serve.check_config(PackedStringArray(["--port", "9201", "--data-dir", "/tmp/cfg-space", "--max-rooms", "7"]))
	assert_eq(int(space.get("port", 0)), 1, "space flags port=1")
	assert_eq(int(space.get("data_dir", 0)), 1, "space flags data_dir=1")
	assert_eq(int(space.get("max_rooms", 0)), 1, "space flags max_rooms=1")
	var inline := Serve.check_config(PackedStringArray(["--port=9202", "--data-dir=/tmp/cfg-eq", "--max-rooms=8"]))
	assert_eq(int(inline.get("port", 0)), 1, "equals flags port=1")
	assert_eq(int(inline.get("data_dir", 0)), 1, "equals flags data_dir=1")
	assert_eq(int(inline.get("max_rooms", 0)), 1, "equals flags max_rooms=1")
	return true


## check_config reports all ones for bare defaults.
func test_check_config_defaults() -> bool:
	_clear_env()
	var r := Serve.check_config(PackedStringArray([]))
	assert_eq(int(r.get("port", 0)), 1, "defaults port=1")
	assert_eq(int(r.get("data_dir", 0)), 1, "defaults data_dir=1")
	assert_eq(int(r.get("max_rooms", 0)), 1, "defaults max_rooms=1")
	return true


## check_config reports all ones when the values arrive via env.
func test_check_config_env() -> bool:
	_clear_env()
	OS.set_environment("TOGETHER_PORT", "9301")
	OS.set_environment("TOGETHER_DATA_DIR", "/tmp/cfg-env")
	OS.set_environment("TOGETHER_MAX_ROOMS", "11")
	var r := Serve.check_config(PackedStringArray([]))
	assert_eq(int(r.get("port", 0)), 1, "env port=1")
	assert_eq(int(r.get("data_dir", 0)), 1, "env data_dir=1")
	assert_eq(int(r.get("max_rooms", 0)), 1, "env max_rooms=1")
	_clear_env()
	return true
