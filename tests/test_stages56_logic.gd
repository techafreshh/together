extends SceneTree
## Unit runner for world-1 stages 05-06 (issue #15): the see-saw
## counterweight and the relay-carry gap no solo can clear. Pattern mirrors
## tests/test_stages34_logic.gd: SceneTree runner with own counters,
## assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_stages56_logic.gd

const Stage05 := preload("res://stages/world1/stage_05.gd")
const Stage06 := preload("res://stages/world1/stage_06.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_manifest_lists_stages56",
		"test_stage05_instantiates",
		"test_stage06_instantiates",
		"test_weight_and_carry_logic",
		"test_selftests_green",
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


## Instantiates a world-1 stage scene under the tree root (so _ready wiring
## runs) and returns it; pair every call with _drop_stage.
func _make_stage(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	var stage: Node = packed.instantiate() as Node
	root.add_child(stage)
	return stage


func _drop_stage(stage: Node) -> void:
	root.remove_child(stage)
	stage.free()


## Manifest: ConfigFile loads, [world1] lists w1s5,w1s6, both sections ship
## scene + scaling_2/3/4, w1s5 needs the distributed pair, w1s6 needs the
## carried duo across the 12 m gap.
func test_manifest_lists_stages56() -> bool:
	var manifest := ConfigFile.new()
	assert_eq(manifest.load("res://stages/world1/manifest.cfg"), OK, "manifest loads")
	var stages: Array = manifest.get_value("world1", "stages", [])
	assert_true(stages.has("w1s5"), "manifest lists w1s5")
	assert_true(stages.has("w1s6"), "manifest lists w1s6")
	assert_true(manifest.has_section("w1s5"), "manifest has [w1s5]")
	assert_true(manifest.has_section("w1s6"), "manifest has [w1s6]")
	assert_eq(str(manifest.get_value("w1s5", "scene", "")), "res://stages/world1/stage_05.tscn", "w1s5 scene path")
	assert_eq(str(manifest.get_value("w1s6", "scene", "")), "res://stages/world1/stage_06.tscn", "w1s6 scene path")
	for key in ["scaling_2", "scaling_3", "scaling_4"]:
		assert_true(str(manifest.get_value("w1s5", key, "")) != "", "w1s5 carries " + key)
		assert_true(str(manifest.get_value("w1s6", key, "")) != "", "w1s6 carries " + key)
	assert_false(bool(manifest.get_value("w1s5", "solo", true)), "w1s5 is not soloable")
	assert_false(bool(manifest.get_value("w1s6", "solo", true)), "w1s6 is not soloable")
	assert_eq(int(manifest.get_value("w1s5", "weight_required", 0)), 2, "w1s5 weight_required is 2")
	assert_eq(int(manifest.get_value("w1s5", "weight_required", 0)), Stage05.WEIGHT_REQUIRED, "manifest weight matches const")
	assert_eq(float(manifest.get_value("w1s6", "gap_width", 0.0)), 12.0, "w1s6 gap_width is 12.0")
	assert_eq(int(manifest.get_value("w1s6", "carry_required", 0)), 2, "w1s6 carry_required is 2")
	assert_eq(int(manifest.get_value("w1s6", "carry_required", 0)), Stage06.CARRY_REQUIRED, "manifest carry matches const")
	return true


## Stage 05 scene: full scaffold plus the SeeSaw counterweight.
func test_stage05_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_05.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_05 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_05 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_05 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_05 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_05 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_05 Goal exists")
	var saw := stage.get_node_or_null("SeeSaw")
	assert_true(saw != null, "stage_05 SeeSaw exists")
	if saw != null:
		assert_true(saw.has_method("press_left"), "SeeSaw exposes press_left")
		assert_true(saw.has_method("press_right"), "SeeSaw exposes press_right")
		assert_true(saw.has_method("is_balanced"), "SeeSaw exposes is_balanced")
	var counts: Dictionary = stage.call("count_props")
	assert_true(int(counts.get("seesaw", 0)) >= 1, "stage_05 counts >=1 seesaw")
	_drop_stage(stage)
	return true


## Stage 06 scene: full scaffold plus two relay posts, no boost pad.
func test_stage06_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_06.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_06 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_06 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_06 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_06 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_06 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_06 Goal exists")
	var relay_a := stage.get_node_or_null("RelayA")
	var relay_b := stage.get_node_or_null("RelayB")
	assert_true(relay_a != null, "stage_06 RelayA exists")
	assert_true(relay_b != null, "stage_06 RelayB exists")
	if relay_a != null:
		assert_true(relay_a.has_method("is_down"), "RelayA exposes is_down")
	if relay_b != null:
		assert_true(relay_b.has_method("is_down"), "RelayB exposes is_down")
	assert_true(stage.get_node_or_null("BoostPad") == null, "stage_06 carries no boost pad")
	var counts: Dictionary = stage.call("count_props")
	assert_true(int(counts.get("relay", 0)) >= 2, "stage_06 counts >=2 relays")
	_drop_stage(stage)
	return true


## Weight and carry predicates: distributed weight balances, solo sides
## block, solo jumps fall short, carried duos cross.
func test_weight_and_carry_logic() -> bool:
	assert_eq(Stage05.WEIGHT_REQUIRED, 2, "WEIGHT_REQUIRED is 2")
	assert_true(Stage05.weight_ok(true, true), "both pans down balances")
	assert_false(Stage05.weight_ok(true, false), "left-only does not balance")
	assert_false(Stage05.weight_ok(false, false), "empty pans do not balance")
	assert_false(Stage05.gate_open(1, 0), "solo left holder blocked")
	assert_false(Stage05.gate_open(0, 1), "solo right holder blocked")
	assert_true(Stage05.gate_open(1, 1), "distributed duo passes")
	for n in [2, 3, 4]:
		var sc5: Dictionary = Stage05.scaling_for(n)
		assert_true(int(sc5.get("weight_ms", 0)) > 0, "stage_05 scaling_%d tunes weight_ms" % n)
		var sc6: Dictionary = Stage06.scaling_for(n)
		assert_true(int(sc6.get("relay_ms", 0)) > 0, "stage_06 scaling_%d tunes relay_ms" % n)
	assert_false(Stage06.solo_crossable(Stage06.GAP_WIDTH), "solo cannot clear the gap")
	assert_true(Stage06.carry_crossable(Stage06.GAP_WIDTH), "relay-carry clears the gap")
	assert_false(Stage06.cross_open(false, 2), "uncarried duo stays blocked")
	assert_false(Stage06.cross_open(true, 1), "carried solo stays blocked")
	assert_true(Stage06.cross_open(true, 2), "carried duo crosses")
	var stage5 := _make_stage("res://stages/world1/stage_05.tscn")
	var saw := stage5.get_node_or_null("SeeSaw")
	saw.call("press_left")
	assert_eq(int(saw.call("get_tilt")), -1, "left-only press tips left")
	assert_false(bool(saw.call("is_balanced")), "left-only press stays unbalanced")
	saw.call("press_right")
	assert_true(bool(saw.call("is_balanced")), "both pans down balances")
	_drop_stage(stage5)
	var stage6 := _make_stage("res://stages/world1/stage_06.tscn")
	var relay_a := stage6.get_node_or_null("RelayA")
	var relay_b := stage6.get_node_or_null("RelayB")
	relay_a.call("press")
	var holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	assert_eq(holders, 1, "single relay reads 1 holder")
	assert_false(Stage06.cross_open(true, holders), "single relay keeps the crossing closed")
	relay_b.call("press")
	holders = (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	assert_eq(holders, 2, "both relays read 2 holders")
	assert_true(Stage06.cross_open(true, holders), "both relays plus carried body opens the crossing")
	relay_a.call("release")
	relay_b.call("release")
	_drop_stage(stage6)
	return true


## Both stage selftests stay green and assert something.
func test_selftests_green() -> bool:
	var r5: Array = Stage05.run_selftest()
	assert_eq(int(r5[1]), 0, "stage_05 selftest has no failures")
	assert_true(int(r5[0]) > 0, "stage_05 selftest asserts something")
	var r6: Array = Stage06.run_selftest()
	assert_eq(int(r6[1]), 0, "stage_06 selftest has no failures")
	assert_true(int(r6[0]) > 0, "stage_06 selftest asserts something")
	return true
