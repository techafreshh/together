extends "res://stages/common/stage_base.gd"
## World 1 stage 1: solo-friendly movement warmup (issue #13). Reuses the
## prop-kit-A scaffold (spawns, checkpoints, kill plane, goal) with a
## straight floor corridor. One player alone can clear it: expected_players
## is 1, so a single dummy in the goal completes the stage. Party-size
## scaling only widens the corridor, never gates progress.


func _init() -> void:
	expected_players = 1


## True once a solo player has touched any checkpoint volume.
static func solo_clear(checkpoints: int) -> bool:
	return checkpoints >= 1


## Per-party-size tuning for 2/3/4 players: corridor platform width only.
## There is no hold gate on the warmup, so hold_ms stays 0 for every size.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var widths := {2: 4.0, 3: 4.5, 4: 5.0}
	return {"players": n, "platform_width": float(widths[n]), "hold_ms": 0}


## Synchronous self-test: proves the solo predicates, the 2/3/4 scaling
## table, then instantiates stage_01.tscn and walks one dummy through both
## checkpoints into the goal. Returns [passed, failed]; never awaits,
## needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if solo_clear(2) and solo_clear(1) and not solo_clear(0):
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: solo_clear must pass with checkpoints, fail with none")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("hold_ms", -1)) == 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_01 selftest: scaling_for(%d) must carry players, width, hold_ms=0" % n)
	var packed: PackedScene = load("res://stages/world1/stage_01.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_01 selftest: stage_01.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_01 selftest: stage_01.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: expected_players must be 1 (solo warmup)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: Goal node missing")
	var checkpoint_hits := [0]
	stage.connect("checkpoint_reached", func(_id, _p): checkpoint_hits[0] += 1)
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var solo := Node.new()
	stage.call("notify_checkpoint", "cp1", solo)
	stage.call("notify_checkpoint", "cp2", solo)
	if checkpoint_hits[0] == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: solo dummy must emit two checkpoint hits")
	stage.call("notify_goal_entered", solo)
	if int(stage.call("goal_count")) == 1 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_01 selftest: one player in the goal must complete the warmup")
	solo.free()
	stage.free()
	return [passed, failed]
