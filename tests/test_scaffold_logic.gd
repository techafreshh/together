extends SceneTree
## Unit runner for the stage scaffold (issue #5 prop kit A).
## Pattern mirrors tests/test_serve_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_scaffold_logic.gd

const StageBase := preload("res://stages/common/stage_base.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_spawn_points",
		"test_checkpoint_registry",
		"test_goal_requires_all",
		"test_kill_depth",
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


## Instantiates the scaffold scene under the tree root (so _ready wiring
## runs) and returns it; pair every call with _drop_stage.
func _make_stage() -> Node:
	var packed: PackedScene = load("res://stages/common/stage_base.tscn") as PackedScene
	var stage: Node = packed.instantiate() as Node
	root.add_child(stage)
	return stage


func _drop_stage(stage: Node) -> void:
	root.remove_child(stage)
	stage.free()


## Spawn list: exactly Spawn1..Spawn4, index access wraps the roster.
func test_spawn_points() -> bool:
	var stage := _make_stage()
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage has Spawn1..Spawn4")
	for i in range(4):
		var n: Node = stage.call("get_spawn_point", i) as Node
		assert_true(n != null, "spawn %d resolves" % i)
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	assert_eq(first, wrapped, "spawn index wraps")
	_drop_stage(stage)
	return true


## Checkpoint registry: at least one volume, each notify emits once.
func test_checkpoint_registry() -> bool:
	var stage := _make_stage()
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "at least one checkpoint registered")
	var hits := [0]
	stage.connect("checkpoint_reached", func(_id, _p): hits[0] += 1)
	var dummy := Node.new()
	stage.call("notify_checkpoint", "cp1", dummy)
	assert_eq(hits[0], 1, "checkpoint notify emits once")
	stage.call("notify_checkpoint", "cp2", dummy)
	assert_eq(hits[0], 2, "second checkpoint emits again")
	dummy.free()
	_drop_stage(stage)
	return true


## Goal requires ALL expected players: one enter is incomplete, two enters
## complete, duplicates never double-count, an exit breaks completion.
func test_goal_requires_all() -> bool:
	var stage := _make_stage()
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	assert_eq(int(stage.call("goal_count")), 1, "one enter -> count 1")
	assert_false(bool(stage.call("is_goal_complete")), "one player is incomplete")
	stage.call("notify_goal_entered", a)
	assert_eq(int(stage.call("goal_count")), 1, "duplicate enter not double-counted")
	stage.call("notify_goal_entered", b)
	assert_eq(int(stage.call("goal_count")), 2, "two enters -> count 2")
	assert_true(bool(stage.call("is_goal_complete")), "full roster completes")
	assert_eq(all_hits[0], 1, "goal_all_reached emitted once")
	stage.call("notify_goal_exited", a)
	assert_eq(int(stage.call("goal_count")), 1, "exit decrements roster")
	assert_false(bool(stage.call("is_goal_complete")), "exit breaks completion")
	a.free()
	b.free()
	_drop_stage(stage)
	return true


## Kill depth: the const and the KillPlane node both sit at y=-10.
func test_kill_depth() -> bool:
	assert_eq(StageBase.KILL_Y, -10.0, "KILL_Y is -10.0")
	var stage := _make_stage()
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "KillPlane node exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "KillPlane at y=-10")
	assert_true(StageBase.is_below_kill(Vector3(0, -10.5, 0)), "below kill depth detected")
	assert_false(StageBase.is_below_kill(Vector3(0, 0.0, 0)), "stage level is safe")
	_drop_stage(stage)
	return true


## The shared selftest stays green and the win roster size is 2.
func test_selftest_green() -> bool:
	var r: Array = StageBase.run_selftest()
	assert_eq(int(r[1]), 0, "scaffold selftest has no failures")
	assert_true(int(r[0]) > 0, "scaffold selftest asserts something")
	assert_eq(StageBase.scaffold_goal_count(), 2, "scaffold goal count is 2")
	return true
