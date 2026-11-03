extends SceneTree
## Unit runner for world-1 stages 03-04 (issue #14): the ordered sequenced
## buttons and the boost-stand gap jump no solo can clear. Pattern mirrors
## tests/test_stages12_logic.gd: SceneTree runner with own counters,
## assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_stages34_logic.gd

const Stage03 := preload("res://stages/world1/stage_03.gd")
const Stage04 := preload("res://stages/world1/stage_04.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_manifest_lists_stages34",
		"test_stage03_instantiates",
		"test_stage04_instantiates",
		"test_order_and_gap_logic",
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


## Manifest: ConfigFile loads, [world1] lists w1s3,w1s4, both sections ship
## scene + scaling_2/3/4, w1s3 is ordered, w1s4 needs the duo crossing.
func test_manifest_lists_stages34() -> bool:
	var manifest := ConfigFile.new()
	assert_eq(manifest.load("res://stages/world1/manifest.cfg"), OK, "manifest loads")
	var stages: Array = manifest.get_value("world1", "stages", [])
	assert_true(stages.has("w1s3"), "manifest lists w1s3")
	assert_true(stages.has("w1s4"), "manifest lists w1s4")
	assert_true(manifest.has_section("w1s3"), "manifest has [w1s3]")
	assert_true(manifest.has_section("w1s4"), "manifest has [w1s4]")
	assert_eq(str(manifest.get_value("w1s3", "scene", "")), "res://stages/world1/stage_03.tscn", "w1s3 scene path")
	assert_eq(str(manifest.get_value("w1s4", "scene", "")), "res://stages/world1/stage_04.tscn", "w1s4 scene path")
	for key in ["scaling_2", "scaling_3", "scaling_4"]:
		assert_true(str(manifest.get_value("w1s3", key, "")) != "", "w1s3 carries " + key)
		assert_true(str(manifest.get_value("w1s4", key, "")) != "", "w1s4 carries " + key)
	assert_false(bool(manifest.get_value("w1s3", "solo", true)), "w1s3 is not soloable")
	assert_false(bool(manifest.get_value("w1s4", "solo", true)), "w1s4 is not soloable")
	assert_eq(int(manifest.get_value("w1s4", "cross_required", 0)), 2, "w1s4 cross_required is 2")
	assert_eq(int(manifest.get_value("w1s4", "cross_required", 0)), Stage04.CROSS_REQUIRED, "manifest cross matches gap const")
	return true


## Stage 03 scene: full scaffold plus the SeqPads ordered set.
func test_stage03_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_03.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_03 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_03 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_03 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_03 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_03 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_03 Goal exists")
	var pads := stage.get_node_or_null("SeqPads")
	assert_true(pads != null, "stage_03 SeqPads exists")
	if pads != null:
		assert_true(pads.has_method("press_step"), "SeqPads exposes press_step")
		assert_true(pads.has_method("is_done"), "SeqPads exposes is_done")
	_drop_stage(stage)
	return true


## Stage 04 scene: full scaffold plus one hold button and one boost pad.
func test_stage04_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_04.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_04 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_04 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_04 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_04 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_04 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_04 Goal exists")
	var hold := stage.get_node_or_null("HoldButton")
	var pad := stage.get_node_or_null("BoostPad")
	assert_true(hold != null, "stage_04 HoldButton exists")
	assert_true(pad != null, "stage_04 BoostPad exists")
	if hold != null:
		assert_true(hold.has_method("is_down"), "HoldButton exposes is_down")
	if pad != null:
		assert_true(pad.has_method("get_boost"), "BoostPad exposes get_boost")
	var counts: Dictionary = stage.call("count_props")
	assert_true(int(counts.get("button", 0)) >= 1, "stage_04 counts >=1 button")
	assert_true(int(counts.get("boost", 0)) >= 1, "stage_04 counts >=1 boost")
	_drop_stage(stage)
	return true


## Order and gap predicates: correct order opens, wrong steps reset,
## solo stays blocked, boosted duo crosses.
func test_order_and_gap_logic() -> bool:
	assert_true(Stage03.order_matches([0, 1, 2]), "correct order matches")
	assert_false(Stage03.order_matches([0, 2, 1]), "wrong order mismatches")
	assert_true(Stage03.gate_open(3), "full progress opens the gate")
	assert_false(Stage03.gate_open(1), "partial progress leaves the gate closed")
	assert_eq(Stage03.next_progress(0, 0), 1, "order steps forward")
	assert_eq(Stage03.next_progress(1, 2), 0, "wrong step resets")
	for n in [2, 3, 4]:
		var sc3: Dictionary = Stage03.scaling_for(n)
		assert_true(int(sc3.get("order_ms", 0)) > 0, "stage_03 scaling_%d tunes order_ms" % n)
		var sc4: Dictionary = Stage04.scaling_for(n)
		assert_true(int(sc4.get("boost_ms", 0)) > 0, "stage_04 scaling_%d tunes boost_ms" % n)
	assert_false(Stage04.solo_crossable(Stage04.GAP_WIDTH), "solo cannot clear the gap")
	assert_true(Stage04.boost_crossable(Stage04.GAP_WIDTH), "boost clears the gap")
	assert_false(Stage04.cross_open(false, 1), "unboosted solo stays blocked")
	assert_false(Stage04.cross_open(true, 1), "boosted solo stays blocked")
	assert_true(Stage04.cross_open(true, 2), "boosted duo crosses")
	var stage := _make_stage("res://stages/world1/stage_04.tscn")
	var hold := stage.get_node_or_null("HoldButton")
	var pad := stage.get_node_or_null("BoostPad")
	hold.call("press")
	hold.call("press")
	assert_eq(int(hold.get("press_count")), 1, "duplicate hold does not double-count")
	hold.call("release")
	assert_false(bool(hold.call("is_down")), "released button reads up")
	var probe := Stage04.BoostProbe.new()
	pad.call("activate", probe)
	assert_eq(probe.calls, 1, "live pad launches the probe")
	assert_eq(probe.last_force, pad.call("get_boost"), "probe receives pad impulse")
	probe.free()
	_drop_stage(stage)
	return true


## Both stage selftests stay green and assert something.
func test_selftests_green() -> bool:
	var r3: Array = Stage03.run_selftest()
	assert_eq(int(r3[1]), 0, "stage_03 selftest has no failures")
	assert_true(int(r3[0]) > 0, "stage_03 selftest asserts something")
	var r4: Array = Stage04.run_selftest()
	assert_eq(int(r4[1]), 0, "stage_04 selftest has no failures")
	assert_true(int(r4[0]) > 0, "stage_04 selftest asserts something")
	return true
