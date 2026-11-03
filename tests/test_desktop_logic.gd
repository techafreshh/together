extends SceneTree
## Unit runner for the Windows desktop-preset surface (issue #22,
## parse-level). Pattern mirrors tests/test_export_logic.gd: SceneTree
## runner with own counters, assert_eq-style helpers, and quit(1 if failed
## > 0 else 0). Covers the socket-free static Serve.check_desktop_preset
## shared with the `-- --selftest desktop_preset` headless branch — no
## export templates installed, so everything is ConfigFile parsing only.
## Run: godot --headless --path . --script res://tests/test_desktop_logic.gd

const Serve := preload("res://server/serve.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_preset_has_windows",
		"test_missing_preset_fails",
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


## The shipped export_presets.cfg carries a Windows Desktop preset.
func test_preset_has_windows() -> bool:
	var found := Serve.check_desktop_preset("res://export_presets.cfg")
	assert_eq(int(found.get("preset", 0)), 1, "windows preset parses")
	return true


## Missing or wrong-platform preset files must fail the check.
func test_missing_preset_fails() -> bool:
	var missing := Serve.check_desktop_preset("res://does-not-exist.cfg")
	assert_eq(int(missing.get("preset", 0)), 0, "missing preset file fails")
	var not_cfg := Serve.check_desktop_preset("res://web/_headers")
	assert_eq(int(not_cfg.get("preset", 0)), 0, "non-cfg file fails")
	return true


## The desktop preset sits beside the web preset without disturbing it.
func test_combined_ok() -> bool:
	var desktop := Serve.check_desktop_preset("res://export_presets.cfg")
	var web := Serve.check_export_preset("res://export_presets.cfg")
	assert_eq(int(desktop.get("preset", 0)), 1, "combined desktop preset=1")
	assert_eq(int(web.get("preset", 0)), 1, "combined web preset=1")
	return true
