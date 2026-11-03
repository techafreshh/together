extends SceneTree
## Unit runner for prop kit B (issue #6): hold-button, sequenced buttons,
## boost pad, see-saw, timed pair-lever. Pattern mirrors
## tests/test_serve_logic.gd: SceneTree runner with own counters,
## assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_props_logic.gd

const ButtonScript := preload("res://actors/props/button.gd")
const SequenceScript := preload("res://actors/props/sequence_buttons.gd")
const BoostScript := preload("res://actors/props/boost.gd")
const SeesawScript := preload("res://actors/props/seesaw.gd")
const LeverScript := preload("res://actors/props/lever.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_button_hold",
		"test_sequence_order",
		"test_boost_guarded",
		"test_seesaw_balance",
		"test_lever_pair_window",
		"test_signal_contract",
		"test_selftest_green",
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


func assert_false(value: bool, label: String) -> void:
	if not value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected false" % label)


func _make_prop(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	var node: Node = packed.instantiate() as Node
	root.add_child(node)
	return node


func _drop_prop(prop: Node) -> void:
	root.remove_child(prop)
	prop.free()


## Hold-button: press latches with pressed+activated, release unlatches
## with released, duplicates are no-ops.
func test_button_hold() -> bool:
	var btn := _make_prop("res://actors/props/button.tscn")
	var hits := [0, 0, 0]
	btn.connect("pressed", func(): hits[0] += 1)
	btn.connect("released", func(): hits[1] += 1)
	btn.connect("activated", func(): hits[2] += 1)
	assert_false(bool(btn.call("is_down")), "button starts up")
	btn.call("press")
	assert_true(bool(btn.call("is_down")), "press latches")
	assert_eq(hits[0], 1, "press emits pressed once")
	assert_eq(hits[2], 1, "press emits activated once")
	btn.call("press")
	assert_eq(hits[0], 1, "duplicate press is a no-op")
	btn.call("release")
	assert_false(bool(btn.call("is_down")), "release unlatches")
	assert_eq(hits[1], 1, "release emits released once")
	_drop_prop(btn)
	return true


## Sequence: correct order activates, wrong step resets with released,
## duplicates hold, 2-step config works.
func test_sequence_order() -> bool:
	assert_eq(SequenceScript.advance(0, [0, 1, 2], 0), 1, "advance steps correct order")
	assert_eq(SequenceScript.advance(1, [0, 1, 2], 2), 0, "advance resets on wrong step")
	var seq := _make_prop("res://actors/props/sequence_buttons.tscn")
	var fired := [0]
	seq.connect("activated", func(): fired[0] += 1)
	seq.call("press_step", 0)
	seq.call("press_step", 1)
	seq.call("press_step", 2)
	assert_true(bool(seq.call("is_done")), "correct order completes")
	assert_eq(fired[0], 1, "completion emits activated")
	seq.call("reset")
	assert_false(bool(seq.call("is_done")), "reset clears completion")
	seq.call("press_step", 0)
	seq.call("press_step", 2)
	assert_eq(int(seq.call("get_progress")), 0, "wrong step resets progress")
	assert_false(bool(seq.call("is_done")), "wrong step does not complete")
	seq.set("order", [1, 0])
	seq.call("reset")
	seq.call("press_step", 1)
	seq.call("press_step", 0)
	assert_true(bool(seq.call("is_done")), "2-step order completes")
	_drop_prop(seq)
	return true


## Boost: guarded apply_boost call fires for probes, unknown bodies only
## trigger signals without errors.
func test_boost_guarded() -> bool:
	var pad := _make_prop("res://actors/props/boost.tscn")
	assert_true((pad.call("get_boost") as Vector3).y > 0.0, "boost impulse lifts upward")
	var probe := BoostScript.BoostProbe.new()
	var hits := [0, 0]
	pad.connect("pressed", func(): hits[0] += 1)
	pad.connect("activated", func(): hits[1] += 1)
	pad.call("activate", probe)
	assert_eq(probe.calls, 1, "probe body is boosted once")
	assert_eq(probe.last_force, pad.call("get_boost"), "probe receives pad impulse")
	var plain := Node.new()
	pad.call("activate", plain)
	assert_eq(hits[0], 2, "unknown body still triggers pressed")
	assert_eq(hits[1], 2, "unknown body still triggers activated")
	plain.free()
	probe.free()
	var released := [0]
	pad.connect("released", func(): released[0] += 1)
	pad.call("deactivate")
	assert_eq(released[0], 1, "deactivate emits released")
	_drop_prop(pad)
	return true


## See-saw: single side tips without activation, both sides balance.
func test_seesaw_balance() -> bool:
	assert_eq(SeesawScript.tilt_for(true, false), -1, "left-only tips left")
	assert_eq(SeesawScript.tilt_for(false, true), 1, "right-only tips right")
	assert_eq(SeesawScript.tilt_for(true, true), 0, "both sides level")
	var saw := _make_prop("res://actors/props/seesaw.tscn")
	var fired := [0]
	saw.connect("activated", func(): fired[0] += 1)
	saw.call("press_left")
	assert_eq(int(saw.call("get_tilt")), -1, "left press tips left")
	assert_false(bool(saw.call("is_balanced")), "single side is not balanced")
	assert_eq(fired[0], 0, "single side does not activate")
	saw.call("press_right")
	assert_true(bool(saw.call("is_balanced")), "both sides balance")
	assert_eq(fired[0], 1, "balance emits activated")
	saw.call("release_left")
	assert_eq(int(saw.call("get_tilt")), 1, "releasing left tips right")
	_drop_prop(saw)
	return true


## Timed lever: pairs inside the window fire, pairs outside do not.
func test_lever_pair_window() -> bool:
	assert_true(LeverScript.pair_complete(1000, 1500, LeverScript.PAIR_WINDOW_MS), "inside window pairs")
	assert_false(LeverScript.pair_complete(0, 5000, LeverScript.PAIR_WINDOW_MS), "outside window misses")
	assert_eq(LeverScript.PAIR_WINDOW_MS, 2000, "pair window is 2000 ms")
	var levers := _make_prop("res://actors/props/lever.tscn")
	var fired := [0]
	levers.connect("activated", func(): fired[0] += 1)
	levers.call("pull_a", 1000)
	assert_false(bool(levers.call("is_paired")), "single pull does not pair")
	levers.call("pull_b", 1500)
	assert_true(bool(levers.call("is_paired")), "pair inside window fires")
	assert_eq(fired[0], 1, "pair emits activated")
	levers.call("reset")
	levers.call("pull_a", 0)
	levers.call("pull_b", 5000)
	assert_false(bool(levers.call("is_paired")), "pair outside window misses")
	_drop_prop(levers)
	return true


## Every prop script must expose the discrete pressed/released/activated
## signal contract the stages declare against.
func test_signal_contract() -> bool:
	var files := [
		"res://actors/props/button.gd",
		"res://actors/props/sequence_buttons.gd",
		"res://actors/props/boost.gd",
		"res://actors/props/seesaw.gd",
		"res://actors/props/lever.gd",
	]
	for path: String in files:
		var source := FileAccess.get_file_as_string(path)
		assert_true(source.contains("pressed"), "%s contains pressed" % path)
		assert_true(source.contains("released"), "%s contains released" % path)
		assert_true(source.contains("activated"), "%s contains activated" % path)
	return true


## Every prop self-test stays green.
func test_selftest_green() -> bool:
	var suites := [
		ButtonScript.run_selftest(),
		SequenceScript.run_selftest(),
		BoostScript.run_selftest(),
		SeesawScript.run_selftest(),
		LeverScript.run_selftest(),
	]
	for r: Array in suites:
		assert_eq(int(r[1]), 0, "prop selftest has no failures")
		assert_true(int(r[0]) > 0, "prop selftest asserts something")
	return true
