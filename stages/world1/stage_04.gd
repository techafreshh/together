extends "res://stages/common/stage_base.gd"
## World 1 stage 4: boost-stand jump across an unjumpable gap (issue #14).
## Reuses the prop-kit-A scaffold plus a HoldButton instance of
## actors/props/button.tscn and a BoostPad instance of
## actors/props/boost.tscn. Two floor platforms sit 12 m apart edge to
## edge, so no solo jump clears the gap; a boosted duo does. All gap math
## is server-side tuning consts proven by predicates, not live physics.

## Edge-to-edge gap width between the two platforms (m).
const GAP_WIDTH := 12.0
## Generous solo jump range upper bound (m); the tuning-derived arc is ~4.2.
const SOLO_JUMP_RANGE := 5.0
## Boosted jump range (m): comfortably clears GAP_WIDTH, still a bound.
const BOOST_JUMP_RANGE := 16.0
## Holders required alongside a ready boost to open the crossing.
const CROSS_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True when a plain jump of `dist` metres lands across.
static func solo_crossable(dist: float) -> bool:
	return dist <= SOLO_JUMP_RANGE


## True when a boosted jump of `dist` metres lands across.
static func boost_crossable(dist: float) -> bool:
	return dist <= BOOST_JUMP_RANGE


## True while the boosted duo crossing is open: boost ready plus enough
## holders on the stand.
static func cross_open(boost_ready: bool, holders: int) -> bool:
	return boost_ready and holders >= CROSS_REQUIRED


## Live prop census: walks the subtree counting hold-buttons (is_down)
## and boost pads (get_boost). Returns {button, boost}.
func count_props() -> Dictionary:
	var counts := {"button": 0, "boost": 0}
	_count_props_into(self, counts)
	return counts


static func _count_props_into(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		if child.has_method("is_down"):
			counts["button"] = int(counts["button"]) + 1
		if child.has_method("get_boost"):
			counts["boost"] = int(counts["boost"]) + 1
		_count_props_into(child, counts)


## Per-party-size tuning for 2/3/4 players: boost timing and platform
## width only. The gap width and duo requirement never shrink.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var boost_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "boost_ms": int(boost_ms[n])}


## Probe body recording guarded boost calls, copied from the boost prop idiom.
class BoostProbe extends Node:
	var calls: int = 0
	var last_force: Vector3 = Vector3.ZERO

	func apply_boost(force: Vector3) -> void:
		calls += 1
		last_force = force


## Synchronous self-test: proves the gap predicates, the scaling table,
## then instantiates stage_04.tscn and drives the live HoldButton latch
## and the live BoostPad launch through a BoostProbe, plus both prop
## counts and the full scaffold assertions. Returns [passed, failed];
## never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if GAP_WIDTH == 12.0 and SOLO_JUMP_RANGE == 5.0 and BOOST_JUMP_RANGE == 16.0 and CROSS_REQUIRED == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: tuning consts must be 12.0/5.0/16.0/2")
	if not solo_crossable(GAP_WIDTH) and not solo_crossable(GAP_WIDTH + 1.0):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: solo jump must not clear the gap")
	if boost_crossable(GAP_WIDTH) and not boost_crossable(BOOST_JUMP_RANGE + 1.0):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: boosted jump must clear the gap within range")
	if not cross_open(false, 1) and not cross_open(false, 2) and not cross_open(true, 1):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: solo and unboosted crossings must stay blocked")
	if cross_open(true, 2) and cross_open(true, 4):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: boosted duo must open the crossing")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("boost_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_04 selftest: scaling_for(%d) must carry players, width, boost_ms" % n)
	var packed: PackedScene = load("res://stages/world1/stage_04.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_04 selftest: stage_04.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_04 selftest: stage_04.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: expected_players must be 2 (boost teamwork)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: Goal node missing")
	var hold := stage.get_node_or_null("HoldButton")
	var pad := stage.get_node_or_null("BoostPad")
	if hold != null and hold.has_method("is_down") and pad != null and pad.has_method("get_boost"):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: HoldButton and BoostPad nodes missing")
		stage.free()
		return [passed, failed]
	if not bool(hold.call("is_down")):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: hold button must start up")
	hold.call("press")
	if bool(hold.call("is_down")) and int(hold.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: hold press must latch with count 1")
	hold.call("press")
	if int(hold.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: duplicate hold must not double-count")
	hold.call("release")
	if not bool(hold.call("is_down")):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: hold release must unlatch")
	var want: Vector3 = pad.call("get_boost")
	if want.y > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: boost impulse must lift upward")
	var probe := BoostProbe.new()
	pad.call("activate", probe)
	if probe.calls == 1 and probe.last_force == want:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: live pad must launch the BoostProbe")
	probe.free()
	var counts: Dictionary = stage.call("count_props")
	if int(counts.get("button", 0)) >= 1 and int(counts.get("boost", 0)) >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: prop census must find >=1 button and >=1 boost")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_04 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
