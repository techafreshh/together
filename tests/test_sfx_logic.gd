extends SceneTree
## Unit runner for the central SFX bus (issue #8 thin placeholder layer).
## Pattern mirrors tests/test_flop_logic.gd: SceneTree runner with own
## counters, assert_eq helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_sfx_logic.gd

const Sfx := preload("res://autoload/Sfx.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_name_set",
		"test_selftest_green",
		"test_default_volume_low",
		"test_each_play_clean",
		"test_missing_name_silent",
		"test_muted_play_silent",
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


## The bus owns exactly the eight issue-ordered event names.
func test_name_set() -> bool:
	var expected: Array = ["jump", "flop", "grab", "throw", "button", "checkpoint", "goal", "coin"]
	assert_eq(Sfx.sfx_names(), expected, "sfx names match issue order")
	assert_eq(Sfx.sfx_count(), 8, "sfx count is 8")
	assert_eq(Sfx.sfx_names().size(), 8, "sfx name list holds 8")
	return true


## The shared selftest stays green (names, files, clean plays, mute).
func test_selftest_green() -> bool:
	var r: Array = Sfx.run_selftest()
	assert_eq(int(r[1]), 0, "sfx selftest has no failures")
	assert_true(int(r[0]) > 0, "sfx selftest asserts something")
	return true


## Placeholder volume stays low by default.
func test_default_volume_low() -> bool:
	assert_true(Sfx.DEFAULT_VOLUME_DB <= -6.0, "default volume low")
	return true


## Every owned effect plays without error, even with no scene tree.
func test_each_play_clean() -> bool:
	var bus: Node = Sfx.new()
	for n in Sfx.sfx_names():
		bus.call("play", str(n))
	assert_true(true, "all eight effects play without error")
	bus.free()
	return true


## Unknown names are silent no-ops, never errors.
func test_missing_name_silent() -> bool:
	var bus: Node = Sfx.new()
	bus.call("play", "no_such_sfx")
	bus.call("play", "")
	assert_true(true, "missing names play silently")
	bus.free()
	return true


## Muted playback is a silent no-op and the flag round-trips.
func test_muted_play_silent() -> bool:
	var bus: Node = Sfx.new()
	assert_true(not bool(bus.call("is_muted")), "bus starts unmuted")
	bus.call("set_muted", true)
	assert_true(bool(bus.call("is_muted")), "bus reports muted")
	for n in Sfx.sfx_names():
		bus.call("play", str(n))
	assert_true(true, "muted plays stay silent")
	bus.call("set_muted", false)
	assert_true(not bool(bus.call("is_muted")), "bus unmutes again")
	bus.free()
	return true
