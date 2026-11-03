extends "res://stages/common/stage_base.gd"
## World 1 stage 5: see-saw counterweight demanding distributed weight
## (issue #15). Reuses the prop-kit-A scaffold plus a SeeSaw instance of
## actors/props/seesaw.tscn and a gated platform. The gate opens only while
## weight sits on BOTH pans at once, so one player alone can never balance
## it. All weight math is server-side tuning consts proven by predicates,
## not live physics. Party-size scaling tunes weight timing and platform
## width only; the per-side requirement never drops.

## Bodies required in total, exactly one per pan. Never lowered by scaling:
## solo is structurally blocked at every party size.
const WEIGHT_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True while both pans are held down at once (the balanced win state).
static func weight_ok(left_down: bool, right_down: bool) -> bool:
	return left_down and right_down


## True while enough weight sits on each pan to open the gate: at least one
## holder per side, so a solo holder on one pan stays blocked.
static func gate_open(left_holders: int, right_holders: int) -> bool:
	return left_holders >= 1 and right_holders >= 1


## Live prop census: walks the subtree counting see-saws (is_balanced).
## Returns {seesaw}.
func count_props() -> Dictionary:
	var counts := {"seesaw": 0}
	_count_props_into(self, counts)
	return counts


static func _count_props_into(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		if child.has_method("is_balanced"):
			counts["seesaw"] = int(counts["seesaw"]) + 1
		_count_props_into(child, counts)


## Per-party-size tuning for 2/3/4 players: weight timing and platform
## width only. The per-side requirement stays 1 at every size so solo
## blocking survives scaling.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var weight_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "weight_ms": int(weight_ms[n])}


## Synchronous self-test: proves the distributed-weight predicates, the
## scaling table, then instantiates stage_05.tscn, checks the SeeSaw starts
## level, drives press_left alone (tips without balance) then press_right
## (balances), plus the full scaffold assertions. Returns [passed,
## failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if WEIGHT_REQUIRED == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: WEIGHT_REQUIRED must be 2")
	if weight_ok(true, true) and not weight_ok(true, false) and not weight_ok(false, true) and not weight_ok(false, false):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: weight_ok must require both pans down")
	if not gate_open(1, 0) and not gate_open(0, 1) and not gate_open(0, 0) and gate_open(1, 1) and gate_open(2, 1):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: gate must block solo sides and open for distributed weight")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("weight_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_05 selftest: scaling_for(%d) must carry players, width, weight_ms" % n)
	var packed: PackedScene = load("res://stages/world1/stage_05.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_05 selftest: stage_05.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_05 selftest: stage_05.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: expected_players must be 2 (counterweight cooperation)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: Goal node missing")
	var saw := stage.get_node_or_null("SeeSaw")
	if saw != null and saw.has_method("press_left") and saw.has_method("press_right") and saw.has_method("is_balanced"):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: SeeSaw node with press_left/press_right/is_balanced missing")
		stage.free()
		return [passed, failed]
	if not bool(saw.call("is_balanced")) and int(saw.call("get_tilt")) == 0:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: see-saw must start level and unbalanced")
	saw.call("press_left")
	if int(saw.call("get_tilt")) == -1 and not bool(saw.call("is_balanced")) and not weight_ok(true, false):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: left-only press must tip without balance")
	saw.call("press_right")
	if int(saw.call("get_tilt")) == 0 and bool(saw.call("is_balanced")) and weight_ok(true, true):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: both pans down must balance")
	var counts: Dictionary = stage.call("count_props")
	if int(counts.get("seesaw", 0)) >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: prop census must find >=1 seesaw")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_05 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
