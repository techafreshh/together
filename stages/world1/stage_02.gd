extends "res://stages/common/stage_base.gd"
## World 1 stage 2: cooperation gate that is impossible solo (issue #13).
## Reuses the prop-kit-A scaffold plus two hold-button instances (HoldA,
## HoldB) flanking a gated platform. The gate opens only while at least
## HOLD_REQUIRED buttons report is_down, so one player can never hold both
## at once. Party-size scaling tunes hold timing and platform width only;
## the required headcount stays 2 for party sizes 2/3/4.

## Simultaneous presences required to open the gate. Never lowered by
## scaling: solo is structurally blocked at every party size.
const HOLD_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True while enough buttons are held to open the gate.
static func gate_open(holders: int) -> bool:
	return holders >= HOLD_REQUIRED


## Per-party-size tuning for 2/3/4 players: hold timing and platform width
## only. hold_required stays HOLD_REQUIRED at every size so solo blocking
## survives scaling.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var hold_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "hold_ms": int(hold_ms[n]), "hold_required": HOLD_REQUIRED}


## Synchronous self-test: proves the solo-blocked/duo-pass gate predicates,
## the scaling table, then instantiates stage_02.tscn, checks both buttons
## start up, drives duplicate-press and two-dummy goal paths. Returns
## [passed, failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if HOLD_REQUIRED == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: HOLD_REQUIRED must be 2")
	if not gate_open(0) and not gate_open(1) and gate_open(2) and gate_open(4):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: gate must block 0/1 holders and open for 2+")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and int(sc.get("hold_required", 0)) == HOLD_REQUIRED and int(sc.get("hold_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_02 selftest: scaling_for(%d) must keep hold_required=2 with hold_ms>0" % n)
	var packed: PackedScene = load("res://stages/world1/stage_02.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_02 selftest: stage_02.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_02 selftest: stage_02.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: expected_players must be 2 (cooperation gate)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: expected 4 spawns, got %d" % spawns.size())
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: Goal node missing")
	var hold_a := stage.get_node_or_null("HoldA")
	var hold_b := stage.get_node_or_null("HoldB")
	if hold_a != null and hold_b != null and hold_a.has_method("is_down") and hold_b.has_method("is_down"):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: HoldA and HoldB button nodes missing")
		stage.free()
		return [passed, failed]
	if not bool(hold_a.call("is_down")) and not bool(hold_b.call("is_down")):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: both buttons must start up")
	hold_a.call("press")
	hold_a.call("press")
	if int(hold_a.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: duplicate hold must not double-count")
	var holders := (1 if bool(hold_a.call("is_down")) else 0) + (1 if bool(hold_b.call("is_down")) else 0)
	if holders == 1 and not gate_open(holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: one held button must leave the gate closed (solo blocked)")
	hold_b.call("press")
	holders = (1 if bool(hold_a.call("is_down")) else 0) + (1 if bool(hold_b.call("is_down")) else 0)
	if holders == 2 and gate_open(holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: two held buttons must open the gate (duo pass)")
	hold_a.call("release")
	hold_b.call("release")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_02 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
