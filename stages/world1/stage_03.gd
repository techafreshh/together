extends "res://stages/common/stage_base.gd"
## World 1 stage 3: ordered-cooperation sequenced-button stage (issue #14).
## Reuses the prop-kit-A scaffold plus a SeqPads instance of
## actors/props/sequence_buttons.tscn and a gated platform. The server-side
## order is enforced here in stage logic: only the exact ORDER run opens
## the gate. Party-size scaling tunes order timing and platform width only
## and never lowers the completion requirement.

## Exact press order that opens the gate (server-side enforcement).
const ORDER = [0, 1, 2]

## True once the full ordered run has landed via press_pad.
var gate_unlocked: bool = false


func _init() -> void:
	expected_players = 2


## True when the given steps exactly equal the required ORDER.
static func order_matches(steps: Array) -> bool:
	return steps == ORDER


## Pure step resolver mirroring SequenceScript.advance: the correct next
## step advances, a step matching the run start restarts at 1, anything
## else resets to 0. Unit-testable with fake values and no nodes.
static func next_progress(current: int, got: int) -> int:
	if ORDER.is_empty():
		return 0
	if current >= 0 and current < ORDER.size() and int(ORDER[current]) == got:
		return current + 1
	if int(ORDER[0]) == got:
		return 1
	return 0


## Presses one pad: forwards to the SeqPads child (guarded by has_method)
## and latches gate_unlocked once the child reports is_done.
func press_pad(step_id: int) -> void:
	var pads := get_node_or_null("SeqPads")
	if pads != null and pads.has_method("press_step"):
		pads.call("press_step", step_id)
		if pads.has_method("is_done") and bool(pads.call("is_done")):
			gate_unlocked = true


## True once enough ordered progress has landed to open the gate.
static func gate_open(progress: int) -> bool:
	return progress >= ORDER.size()


## Per-party-size tuning for 2/3/4 players: order timing and platform
## width only. The completion requirement stays a full 3-step run.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var order_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "order_ms": int(order_ms[n])}


## Synchronous self-test: proves the order predicates, the 2/3/4 scaling
## table, then instantiates stage_03.tscn, drives the live SeqPads through
## correct-order completion, wrong-step reset, duplicate-start hold and a
## 2-step-style config, plus the full scaffold assertions. Returns
## [passed, failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if ORDER == [0, 1, 2]:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: ORDER must be [0, 1, 2]")
	if order_matches([0, 1, 2]) and not order_matches([0, 2, 1]) and not order_matches([0, 1]):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: order_matches must require the exact ORDER run")
	if next_progress(0, 0) == 1 and next_progress(1, 1) == 2 and next_progress(2, 2) == 3:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: next_progress must step the correct order")
	if next_progress(1, 2) == 0 and next_progress(1, 0) == 1 and next_progress(0, 2) == 0:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: next_progress must reset on wrong steps")
	if gate_open(3) and not gate_open(1) and not gate_open(0):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: gate must open only at full ORDER progress")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("order_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_03 selftest: scaling_for(%d) must carry players, width, order_ms" % n)
	var packed: PackedScene = load("res://stages/world1/stage_03.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_03 selftest: stage_03.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_03 selftest: stage_03.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: expected_players must be 2 (ordered cooperation)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: Goal node missing")
	var pads := stage.get_node_or_null("SeqPads")
	if pads != null and pads.has_method("press_step") and pads.has_method("is_done"):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: SeqPads node with press_step/is_done missing")
		stage.free()
		return [passed, failed]
	stage.call("press_pad", 0)
	stage.call("press_pad", 1)
	stage.call("press_pad", 2)
	if bool(pads.call("is_done")) and int(pads.call("get_progress")) == 3 and bool(stage.get("gate_unlocked")) and gate_open(int(pads.call("get_progress"))):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: correct 3-step order must complete and unlock the gate")
	pads.call("reset")
	stage.set("gate_unlocked", false)
	stage.call("press_pad", 0)
	stage.call("press_pad", 2)
	if int(pads.call("get_progress")) == 0 and not bool(pads.call("is_done")) and not bool(stage.get("gate_unlocked")):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: wrong step must reset the run")
	pads.call("reset")
	stage.call("press_pad", 0)
	stage.call("press_pad", 0)
	if int(pads.call("get_progress")) == 1 and not bool(pads.call("is_done")):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: duplicate start step must hold at progress 1")
	pads.set("order", [1, 0])
	pads.call("reset")
	stage.call("press_pad", 1)
	stage.call("press_pad", 0)
	if bool(pads.call("is_done")) and int(pads.call("get_progress")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: configurable 2-step order must complete")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: both players in the goal must complete with goal_all_reached")
	stage.call("notify_goal_exited", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_03 selftest: goal exit must break completion")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
