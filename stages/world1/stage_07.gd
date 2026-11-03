extends "res://stages/common/stage_base.gd"
## World 1 stage 7: timed pair-lever sprint (issue #16). Reuses the
## prop-kit-A scaffold plus a LeverPair instance of actors/props/lever.tscn.
## The gate opens only while both levers land inside PAIR_WINDOW_MS, so a
## single pull can never open it. All timing math is server-side tuning
## consts proven by pure predicates, not live physics. Party-size scaling
## tunes lever timing and platform width only; the pair requirement never
## drops, so solo is structurally blocked at every party size.

## Lever prop script: the window const is the single source of truth.
const LeverScript := preload("res://actors/props/lever.gd")

## Both levers must land within this window (ms) to open the gate.
## Mirrors LeverScript.PAIR_WINDOW_MS exactly.
const PAIR_WINDOW_MS := 2000
## Lever pairs required to open the gate. Never lowered by scaling.
const PAIR_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True when both lever stamps land inside the timed window.
static func pair_complete(a_ms: int, b_ms: int) -> bool:
	if a_ms < 0 or b_ms < 0:
		return false
	return abs(a_ms - b_ms) <= PAIR_WINDOW_MS


## True while the timed pair window holds the gate open.
static func timed_open(a_ms: int, b_ms: int) -> bool:
	return pair_complete(a_ms, b_ms)


## True while a latched pair holds the gate open.
static func gate_open(paired: bool) -> bool:
	return paired


## Live prop census: walks the subtree counting pair levers (pull_a).
## Returns {lever}.
func count_props() -> Dictionary:
	var counts := {"lever": 0}
	_count_props_into(self, counts)
	return counts


static func _count_props_into(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		if child.has_method("pull_a"):
			counts["lever"] = int(counts["lever"]) + 1
		_count_props_into(child, counts)


## Per-party-size tuning for 2/3/4 players: lever timing and platform width
## only. The pair requirement stays PAIR_REQUIRED at every size so solo
## blocking survives scaling.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var lever_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "lever_ms": int(lever_ms[n]), "pair_required": PAIR_REQUIRED}


## Synchronous self-test: proves the timed-pair predicates, the scaling
## table, then instantiates stage_07.tscn and drives the live LeverPair
## through single-pull blocked, in-window pair, reset reuse, and an
## out-of-window pair, plus the full scaffold assertions. Returns [passed,
## failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if PAIR_WINDOW_MS == 2000 and PAIR_REQUIRED == 2 and PAIR_WINDOW_MS == LeverScript.PAIR_WINDOW_MS:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: PAIR_WINDOW_MS must be 2000 (lever prop) and PAIR_REQUIRED 2")
	if pair_complete(1000, 1500) and pair_complete(0, 2000) and pair_complete(1000, 1000):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: pairs inside the window must complete")
	if not pair_complete(0, 2001) and not pair_complete(0, 5000):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: pairs outside the window must not complete")
	if not pair_complete(-1, 500) and not pair_complete(500, -1) and not pair_complete(-1, -1):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: unset stamps must not complete")
	if timed_open(1000, 1500) and not timed_open(0, 5000) and gate_open(true) and not gate_open(false):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: timed gate must open only for in-window pairs")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("lever_ms", 0)) > 0 and int(sc.get("pair_required", 0)) == PAIR_REQUIRED:
			passed += 1
		else:
			failed += 1
			push_error("stage_07 selftest: scaling_for(%d) must carry players, width, lever_ms, pair_required=2" % n)
	var packed: PackedScene = load("res://stages/world1/stage_07.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_07 selftest: stage_07.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_07 selftest: stage_07.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: expected_players must be 2 (timed pair sprint)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: Goal node missing")
	var levers := stage.get_node_or_null("LeverPair")
	if levers != null and levers.has_method("pull_a") and levers.has_method("pull_b") and levers.has_method("is_paired"):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: LeverPair node with pull_a/pull_b/is_paired missing")
		stage.free()
		return [passed, failed]
	if not bool(levers.call("is_paired")):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: lever pair must start unpaired")
	levers.call("pull_a", 1000)
	if not bool(levers.call("is_paired")) and not timed_open(1000, -1) and not gate_open(bool(levers.call("is_paired"))):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: a single pull must keep the gate closed (solo blocked)")
	levers.call("pull_b", 1500)
	if bool(levers.call("is_paired")) and timed_open(1000, 1500) and gate_open(bool(levers.call("is_paired"))):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: an in-window pair must open the gate")
	levers.call("reset")
	if not bool(levers.call("is_paired")):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: reset must clear the pair")
	levers.call("pull_a", 0)
	levers.call("pull_b", 5000)
	if not bool(levers.call("is_paired")) and not timed_open(0, 5000):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: an out-of-window pair must stay blocked")
	levers.call("reset")
	levers.call("pull_a")
	levers.call("pull_b")
	if bool(levers.call("is_paired")):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: live-clock pulls must pair")
	levers.call("reset")
	var counts: Dictionary = stage.call("count_props")
	if int(counts.get("lever", 0)) >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: prop census must find >=1 lever")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_07 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
