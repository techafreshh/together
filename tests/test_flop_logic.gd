extends SceneTree
## Unit runner for the flop/respawn logic (issue #4 comedy core).
## Pattern mirrors tests/test_serve_logic.gd: SceneTree runner with own
## counters, assert_eq helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_flop_logic.gd

const Tuning := preload("res://actors/player/tuning.gd")
const Controller := preload("res://actors/player/controller.gd")
const Ragdoll := preload("res://actors/player/ragdoll.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_respawn_budget",
		"test_impact_predicate",
		"test_kill_depth",
		"test_timing_wiring",
		"test_respawn_wiring",
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


## Respawn must restore control in under 3 seconds by construction.
func test_respawn_budget() -> bool:
	var ms := Controller.simulate_flop_respawn_ms()
	assert_true(ms < 3000, "respawn budget < 3000")
	assert_true(ms > 0, "respawn budget positive")
	assert_eq(ms, Tuning.respawn_delay_ms, "respawn uses Tuning.respawn_delay_ms")
	assert_eq(Ragdoll.flop_timeline_ms(), Tuning.respawn_delay_ms, "ragdoll timeline matches")
	return true


## Hard-impact predicate must fire above the threshold, rest below it.
func test_impact_predicate() -> bool:
	assert_true(Controller.should_flop_on_impact(Tuning.hard_impact_speed + 5.0), "impact above threshold flops")
	assert_true(Controller.should_flop_on_impact(Tuning.hard_impact_speed + 0.01), "impact just above threshold flops")
	assert_false(Controller.should_flop_on_impact(Tuning.hard_impact_speed - 0.01), "impact just below threshold survives")
	assert_false(Controller.should_flop_on_impact(0.0), "zero impact survives")
	assert_false(Controller.should_flop_on_impact(-3.0), "upward motion never flops")
	return true


## The kill plane sits exactly at y=-10.
func test_kill_depth() -> bool:
	assert_eq(Tuning.kill_y, -10.0, "kill_y is -10.0")
	assert_true(Tuning.hard_impact_speed < Tuning.max_fall_speed, "impact threshold below terminal speed")
	return true


## Scripted visual must fit inside the respawn window.
func test_timing_wiring() -> bool:
	assert_true(Tuning.flop_duration_ms <= Tuning.respawn_delay_ms, "flop visual fits in respawn window")
	var r: Array = Controller.run_flop_selftest()
	assert_eq(int(r[1]), 0, "controller flop selftest has no failures")
	var g: Array = Ragdoll.run_selftest()
	assert_eq(int(g[1]), 0, "ragdoll selftest has no failures")
	return true


## The controller exposes the kill/respawn path the kill plane calls into.
func test_respawn_wiring() -> bool:
	var player := Controller.new()
	assert_true(player.has_method("respawn"), "controller exposes respawn")
	assert_true(player.has_method("kill"), "controller exposes kill")
	assert_true(player.has_method("is_alive"), "controller exposes is_alive")
	assert_true(player.has_method("set_checkpoint"), "controller exposes set_checkpoint")
	player.free()
	return true
