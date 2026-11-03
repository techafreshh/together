extends SceneTree
## Unit runner for the walking-skeleton request core.
## Pattern: SceneTree runner with own counters, assert_eq-style helpers, and
## quit(1 if failed > 0 else 0) — never bare assert() (it hangs CI).
## Run: godot --headless --path . --script res://tests/test_serve_logic.gd

const Serve := preload("res://server/serve.gd")
const ConfigScript := preload("res://autoload/Config.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_ws_accept_known_vector",
		"test_route_table",
		"test_health_body",
		"test_parse_serve_args",
		"test_parse_request",
		"test_never_500",
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


func assert_contains(haystack: String, needle: String, label: String) -> void:
	if haystack.contains(needle):
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: %s does not contain %s" % [label, haystack, needle])


## RFC 6455 section 1.3 known-answer vector.
func test_ws_accept_known_vector() -> bool:
	assert_eq(
		Serve._compute_ws_accept("dGhlIHNhbXBsZSBub25jZQ=="),
		"s3pPLMBiTxaQ9kYGzzhZRbK+xOo=",
		"rfc6455 accept vector"
	)
	return true


func test_route_table() -> bool:
	assert_eq(Serve._route_request("GET", "/", {}), 200, "GET / -> 200")
	var upgrade := {
		"upgrade": "websocket",
		"sec-websocket-key": "dGhlIHNhbXBsZSBub25jZQ==",
		"sec-websocket-version": "13",
	}
	assert_eq(Serve._route_request("GET", "/ws", upgrade), 101, "GET /ws upgrade -> 101")
	assert_eq(Serve._route_request("GET", "/ws", {}), 400, "/ws without upgrade -> 400")
	assert_eq(Serve._route_request("POST", "/ws", upgrade), 400, "POST /ws -> 400")
	assert_eq(Serve._route_request("GET", "/does-not-exist", {}), 404, "unknown path -> 404")
	assert_eq(Serve._route_request("POST", "/", {}), 404, "POST / -> 404")
	var bad := Serve._parse_request("garbage bytes\r\n\r\n".to_ascii_buffer())
	assert_eq(bool(bad.get("ok", true)), false, "garbage bytes do not parse")
	return true


func test_health_body() -> bool:
	var body := Serve._build_health_body()
	assert_contains(body, "\"ok\":true", "health has ok:true")
	assert_contains(body, "\"version\":", "health has version field")
	assert_contains(body, ConfigScript.VERSION, "health carries Config.VERSION")
	var parsed: Variant = JSON.parse_string(body)
	assert_eq(typeof(parsed), TYPE_DICTIONARY, "health is a JSON object")
	assert_eq(bool(parsed.get("ok", false)), true, "health ok parses true")
	return true


func test_parse_serve_args() -> bool:
	var d := ConfigScript.parse_serve_args(PackedStringArray([]))
	assert_eq(bool(d.get("serve", true)), false, "no args -> not serve")
	assert_eq(int(d.get("port", 0)), ConfigScript.DEFAULT_PORT, "no args -> default port")
	var e := ConfigScript.parse_serve_args(PackedStringArray(["--serve", "--port", "1234"]))
	assert_eq(bool(e.get("serve", false)), true, "--serve detected")
	assert_eq(int(e.get("port", 0)), 1234, "explicit port")
	var g := ConfigScript.parse_serve_args(PackedStringArray(["--serve", "--port", "banana"]))
	assert_eq(int(g.get("port", 0)), ConfigScript.DEFAULT_PORT, "garbage port -> default")
	var h := ConfigScript.parse_serve_args(PackedStringArray(["--serve", "--port", "99999"]))
	assert_eq(int(h.get("port", 0)), ConfigScript.DEFAULT_PORT, "out-of-range port -> default")
	return true


func test_parse_request() -> bool:
	var raw := "GET / HTTP/1.1\r\nHost: 127.0.0.1:8080\r\nUpgrade: WebSocket\r\nSec-WebSocket-Key: abc==\r\n\r\n".to_ascii_buffer()
	var req := Serve._parse_request(raw)
	assert_eq(bool(req.get("ok", false)), true, "valid request parses")
	assert_eq(str(req.get("method", "")), "GET", "method")
	assert_eq(str(req.get("path", "")), "/", "path")
	var headers: Dictionary = req["headers"]
	assert_eq(str(headers.get("upgrade", "")), "WebSocket", "header value preserved")
	var q := Serve._parse_request("GET /?x=1 HTTP/1.1\r\nHost: h\r\n\r\n".to_ascii_buffer())
	assert_eq(str(q.get("path", "")), "/", "query string stripped")
	var lower := Serve._parse_request("get /ws HTTP/1.1\r\nHost: h\r\nUPGRADE: websocket\r\nSec-WebSocket-Key: k\r\n\r\n".to_ascii_buffer())
	assert_eq(bool(lower.get("ok", false)), true, "lowercase method parses")
	assert_eq(Serve._route_request(str(lower["method"]), str(lower["path"]), lower["headers"]), 101, "header names case-insensitive")
	return true


func test_never_500() -> bool:
	var methods := ["GET", "POST", "PUT", "DELETE", "HEAD", "OPTIONS", "TRACE", ""]
	var paths := ["/", "/ws", "/does-not-exist", "", "/ws/", "/WS", "/?x=1", "/ws?x=1"]
	for m: String in methods:
		for p: String in paths:
			var s := Serve._route_request(m, p, {})
			if s == 500:
				failed += 1
				push_error("FAIL never-500: route(%s, %s) returned 500" % [m, p])
			else:
				passed += 1
	return true
