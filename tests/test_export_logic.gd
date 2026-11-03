extends SceneTree
## Unit runner for the web-export surface (issue #21, parse-level).
## Pattern mirrors tests/test_sfx_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, and quit(1 if failed > 0 else 0).
## Covers the three socket-free static checks in server/serve.gd shared
## with the `-- --export-check web` headless branch — no export templates
## installed, so everything is ConfigFile/FileAccess parsing only.
## Run: godot --headless --path . --script res://tests/test_export_logic.gd

const Serve := preload("res://server/serve.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_preset_has_web",
		"test_headers_have_isolation",
		"test_headers_negative",
		"test_loading_indicator_exists",
		"test_combined_ok",
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


func assert_true(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected true" % label)


## The shipped export_presets.cfg carries a Web platform preset.
func test_preset_has_web() -> bool:
	var found := Serve.check_export_preset("res://export_presets.cfg")
	assert_eq(int(found.get("preset", 0)), 1, "web preset parses")
	var missing := Serve.check_export_preset("res://does-not-exist.cfg")
	assert_eq(int(missing.get("preset", 0)), 0, "missing preset file fails")
	return true


## The real web/_headers carries both isolation policies.
func test_headers_have_isolation() -> bool:
	var found := Serve.check_web_headers("res://web/_headers")
	assert_eq(int(found.get("headers", 0)), 1, "headers carry COOP+COEP")
	var text := FileAccess.get_file_as_string("res://web/_headers")
	assert_true(text.contains("Cross-Origin-Opener-Policy"), "COOP present")
	assert_true(text.contains("Cross-Origin-Embedder-Policy"), "COEP present")
	return true


## Empty or missing header text must fail the check.
func test_headers_negative() -> bool:
	var tmp := "user://export_headers_empty"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("")
	f.close()
	var empty := Serve.check_web_headers(tmp)
	assert_eq(int(empty.get("headers", 0)), 0, "empty headers fail")
	var partial := "user://export_headers_partial"
	var g := FileAccess.open(partial, FileAccess.WRITE)
	g.store_string("Cross-Origin-Opener-Policy: same-origin\n")
	g.close()
	var half := Serve.check_web_headers(partial)
	assert_eq(int(half.get("headers", 0)), 0, "COOP alone fails")
	var gone := Serve.check_web_headers("res://web/no-such-headers")
	assert_eq(int(gone.get("headers", 0)), 0, "missing headers fail")
	return true


## The standalone boot indicator exists and mentions loading.
func test_loading_indicator_exists() -> bool:
	assert_eq(Serve.check_loading_indicator("res://web/loading.html"), 1, "loading indicator exists")
	assert_eq(Serve.check_loading_indicator("res://web/no-such-page.html"), 0, "missing page fails")
	return true


## All three checks together yield the probe line's preset=1 headers=1.
func test_combined_ok() -> bool:
	var preset := Serve.check_export_preset("res://export_presets.cfg")
	var headers := Serve.check_web_headers("res://web/_headers")
	var loading := Serve.check_loading_indicator("res://web/loading.html")
	assert_eq(int(preset.get("preset", 0)), 1, "combined preset=1")
	assert_eq(int(headers.get("headers", 0)), 1, "combined headers=1")
	assert_eq(loading, 1, "combined loading=1")
	return true
