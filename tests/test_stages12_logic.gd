extends SceneTree
## Unit runner for world-1 stages 01-02 (issue #13): the solo movement
## warmup and the hold-button cooperation gate that is impossible alone.
## Pattern mirrors tests/test_scaffold_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_stages12_logic.gd

const Stage01 := preload("res://stages/world1/stage_01.gd")
const Stage02 := preload("res://stages/world1/stage_02.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_manifest_lists_stages",
		"test_stage01_instantiates",
		"test_stage02_instantiates",
		"test_gate_logic",
		"test_solo_warmup",
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


## Manifest: ConfigFile loads, [world1] lists w1s1,w1s2, both sections ship
## scene + scaling_2/3/4, and the stage_02 gate needs 2 holders.
func test_manifest_lists_stages() -> bool:
	var manifest := ConfigFile.new()
	assert_eq(manifest.load("res://stages/world1/manifest.cfg"), OK, "manifest loads")
	var stages: Array = manifest.get_value("world1", "stages", [])
	assert_true(stages.has("w1s1"), "manifest lists w1s1")
	assert_true(stages.has("w1s2"), "manifest lists w1s2")
	assert_true(manifest.has_section("w1s1"), "manifest has [w1s1]")
	assert_true(manifest.has_section("w1s2"), "manifest has [w1s2]")
	assert_eq(str(manifest.get_value("w1s1", "scene", "")), "res://stages/world1/stage_01.tscn", "w1s1 scene path")
	assert_eq(str(manifest.get_value("w1s2", "scene", "")), "res://stages/world1/stage_02.tscn", "w1s2 scene path")
	for key in ["scaling_2", "scaling_3", "scaling_4"]:
		assert_true(str(manifest.get_value("w1s1", key, "")) != "", "w1s1 carries " + key)
		assert_true(str(manifest.get_value("w1s2", key, "")) != "", "w1s2 carries " + key)
	assert_eq(int(manifest.get_value("w1s2", "hold_required", 0)), 2, "w1s2 hold_required is 2")
	assert_eq(int(manifest.get_value("w1s2", "hold_required", 0)), Stage02.HOLD_REQUIRED, "manifest hold matches gate const")
	assert_true(bool(manifest.get_value("w1s1", "solo", false)), "w1s1 is soloable")
	assert_false(bool(manifest.get_value("w1s2", "solo", true)), "w1s2 is not soloable")
	return true


## Stage 01 scene: full scaffold, solo roster, goal within reach of one.
func test_stage01_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_01.tscn")
	assert_eq(int(stage.get("expected_players")), 1, "stage_01 expects 1 player")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_01 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_01 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_01 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_01 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_01 Goal exists")
	_drop_stage(stage)
	return true


## Stage 02 scene: full scaffold plus two buttons that start unpressed.
func test_stage02_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_02.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_02 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_02 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_02 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_02 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_02 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_02 Goal exists")
	var hold_a := stage.get_node_or_null("HoldA")
	var hold_b := stage.get_node_or_null("HoldB")
	assert_true(hold_a != null, "stage_02 HoldA exists")
	assert_true(hold_b != null, "stage_02 HoldB exists")
	if hold_a != null and hold_b != null:
		assert_false(bool(hold_a.call("is_down")), "HoldA starts up")
		assert_false(bool(hold_b.call("is_down")), "HoldB starts up")
	_drop_stage(stage)
	return true


## Gate logic: 1 holder stays blocked, 2+ open, scaling never lowers the
## headcount, and duplicate holds never double-count.
func test_gate_logic() -> bool:
	assert_eq(Stage02.HOLD_REQUIRED, 2, "HOLD_REQUIRED is 2")
	assert_false(Stage02.gate_open(0), "0 holders blocked")
	assert_false(Stage02.gate_open(1), "solo (1 holder) blocked")
	assert_true(Stage02.gate_open(2), "duo (2 holders) passes")
	assert_true(Stage02.gate_open(4), "full party passes")
	for n in [2, 3, 4]:
		var sc: Dictionary = Stage02.scaling_for(n)
		assert_eq(int(sc.get("hold_required", 0)), 2, "scaling_%d keeps hold_required=2" % n)
		assert_true(int(sc.get("hold_ms", 0)) > 0, "scaling_%d tunes hold_ms" % n)
	var stage := _make_stage("res://stages/world1/stage_02.tscn")
	var hold_a := stage.get_node_or_null("HoldA")
	hold_a.call("press")
	hold_a.call("press")
	assert_eq(int(hold_a.get("press_count")), 1, "duplicate hold does not double-count")
	hold_a.call("release")
	assert_false(bool(hold_a.call("is_down")), "released button reads up")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	assert_eq(int(stage.call("goal_count")), 1, "solo enter -> count 1")
	assert_false(bool(stage.call("is_goal_complete")), "solo in goal stays incomplete")
	stage.call("notify_goal_entered", b)
	assert_true(bool(stage.call("is_goal_complete")), "duo in goal completes")
	assert_eq(all_hits[0], 1, "goal_all_reached emitted once for the duo")
	a.free()
	b.free()
	_drop_stage(stage)
	return true


## Solo warmup: one dummy through checkpoints into the goal completes it.
func test_solo_warmup() -> bool:
	assert_true(Stage01.solo_clear(1), "one checkpoint clears solo")
	assert_false(Stage01.solo_clear(0), "no checkpoints do not clear")
	var stage := _make_stage("res://stages/world1/stage_01.tscn")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var solo := Node.new()
	stage.call("notify_checkpoint", "cp1", solo)
	stage.call("notify_checkpoint", "cp2", solo)
	stage.call("notify_goal_entered", solo)
	assert_eq(int(stage.call("goal_count")), 1, "solo enter -> count 1")
	assert_true(bool(stage.call("is_goal_complete")), "solo completes the warmup")
	assert_eq(all_hits[0], 1, "solo completion emits goal_all_reached")
	solo.free()
	_drop_stage(stage)
	return true


## Both stage selftests stay green and assert something.
func test_selftests_green() -> bool:
	var r1: Array = Stage01.run_selftest()
	assert_eq(int(r1[1]), 0, "stage_01 selftest has no failures")
	assert_true(int(r1[0]) > 0, "stage_01 selftest asserts something")
	var r2: Array = Stage02.run_selftest()
	assert_eq(int(r2[1]), 0, "stage_02 selftest has no failures")
	assert_true(int(r2[0]) > 0, "stage_02 selftest asserts something")
	return true
