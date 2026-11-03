extends "res://stages/common/stage_base.gd"
## World 1 stage 8: finale remixing every taught verb (issue #16). Reuses
## the prop-kit-A scaffold plus one instance of each proven prop: HoldButton
## (hold), SeqPads (sequence), BoostPad (boost), SeeSaw (balance), and
## RelayA/RelayB (carry leg). The gate opens only while the full five-verb
## conjunction holds, so any solo or partial run stays blocked. The carry
## leg reuses the stage-06 relay-carry model: no grab RPCs live in stage
## logic, carriers arrive as plain counts. All gap math is server-side
## tuning consts proven by predicates, not live physics.

## Edge-to-edge gap width between the two platforms (m).
const GAP_WIDTH := 12.0
## Generous solo jump range upper bound (m); the tuning-derived arc is ~4.2.
const SOLO_JUMP_RANGE := 5.0
## Relay-carry/throw reach (m): comfortably clears GAP_WIDTH, still a bound.
const CARRY_RANGE := 14.0
## Holders required alongside the other verbs to open the remix.
const CROSS_REQUIRED := 2
## Carriers required alongside a carried body to open the carry leg.
const CARRY_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True when a plain jump of `dist` metres lands across.
static func solo_crossable(dist: float) -> bool:
	return dist <= SOLO_JUMP_RANGE


## True when a relay-carry/throw of `dist` metres lands across.
static func carry_crossable(dist: float) -> bool:
	return dist <= CARRY_RANGE


## True while the full five-verb remix holds: the button is held, the
## sequence run is done, the boost is ready, the see-saw is balanced, and
## a body is carried with enough carriers on the relay posts.
static func remix_open(hold_down: bool, seq_done: bool, boost_ready: bool, balanced: bool, carried: bool, carriers: int) -> bool:
	return hold_down and seq_done and boost_ready and balanced and carried and carriers >= CARRY_REQUIRED


## Live prop census: walks the subtree counting hold-buttons (is_down, but
## not the Relay* posts), sequence sets (press_step), boost pads
## (get_boost), see-saws (is_balanced), and relay posts (Relay* names).
## Returns {button, sequence, boost, seesaw, relay}.
func count_props() -> Dictionary:
	var counts := {"button": 0, "sequence": 0, "boost": 0, "seesaw": 0, "relay": 0}
	_count_props_into(self, counts)
	return counts


static func _count_props_into(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		var cname := str(child.name)
		if cname.begins_with("Relay"):
			if child.has_method("is_down"):
				counts["relay"] = int(counts["relay"]) + 1
		else:
			if child.has_method("is_down"):
				counts["button"] = int(counts["button"]) + 1
		if child.has_method("press_step"):
			counts["sequence"] = int(counts["sequence"]) + 1
		if child.has_method("get_boost"):
			counts["boost"] = int(counts["boost"]) + 1
		if child.has_method("is_balanced"):
			counts["seesaw"] = int(counts["seesaw"]) + 1
		_count_props_into(child, counts)


## Per-party-size tuning for 2/3/4 players: remix timing and platform width
## only. The gap width and carrier requirement never shrink.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var remix_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "remix_ms": int(remix_ms[n])}


## Probe body recording guarded boost calls, copied from the boost prop idiom.
class BoostProbe extends Node:
	var calls: int = 0
	var last_force: Vector3 = Vector3.ZERO

	func apply_boost(force: Vector3) -> void:
		calls += 1
		last_force = force


## Synchronous self-test: proves the gap predicates, the five-verb remix
## conjunction (any missing verb blocks, all five open), the scaling table,
## then instantiates stage_08.tscn and drives every live prop leg plus the
## full scaffold assertions. Returns [passed, failed]; never awaits, needs
## no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if GAP_WIDTH == 12.0 and SOLO_JUMP_RANGE == 5.0 and CARRY_RANGE == 14.0 and CROSS_REQUIRED == 2 and CARRY_REQUIRED == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: tuning consts must be 12.0/5.0/14.0/2/2")
	if not solo_crossable(GAP_WIDTH) and not solo_crossable(GAP_WIDTH + 1.0) and solo_crossable(SOLO_JUMP_RANGE):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: solo jump must not clear the gap")
	if carry_crossable(GAP_WIDTH) and not carry_crossable(CARRY_RANGE + 1.0):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: relay-carry must clear the gap within range")
	if not remix_open(false, true, true, true, true, 2):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: released hold must block the remix")
	if not remix_open(true, false, true, true, true, 2):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: unfinished sequence must block the remix")
	if not remix_open(true, true, false, true, true, 2):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: unready boost must block the remix")
	if not remix_open(true, true, true, false, true, 2):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: unbalanced see-saw must block the remix")
	if not remix_open(true, true, true, true, false, 2) and not remix_open(true, true, true, true, true, 1) and not remix_open(true, true, true, true, true, 0):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: uncarried and solo-carried runs must block the remix")
	if remix_open(true, true, true, true, true, 2) and remix_open(true, true, true, true, true, 4):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: all five verbs must open the remix")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("remix_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_08 selftest: scaling_for(%d) must carry players, width, remix_ms" % n)
	var packed: PackedScene = load("res://stages/world1/stage_08.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_08 selftest: stage_08.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_08 selftest: stage_08.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: expected_players must be 2 (finale remix)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: Goal node missing")
	var hold := stage.get_node_or_null("HoldButton")
	var pads := stage.get_node_or_null("SeqPads")
	var pad := stage.get_node_or_null("BoostPad")
	var saw := stage.get_node_or_null("SeeSaw")
	var relay_a := stage.get_node_or_null("RelayA")
	var relay_b := stage.get_node_or_null("RelayB")
	if hold != null and hold.has_method("is_down") and pads != null and pads.has_method("press_step") and pad != null and pad.has_method("get_boost") and saw != null and saw.has_method("is_balanced") and relay_a != null and relay_a.has_method("is_down") and relay_b != null and relay_b.has_method("is_down"):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: HoldButton/SeqPads/BoostPad/SeeSaw/RelayA/RelayB nodes missing")
		stage.free()
		return [passed, failed]
	hold.call("press")
	if bool(hold.call("is_down")):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: hold leg must latch")
	hold.call("press")
	if int(hold.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: duplicate hold must not double-count")
	pads.call("press_step", 0)
	pads.call("press_step", 1)
	pads.call("press_step", 2)
	if bool(pads.call("is_done")) and int(pads.call("get_progress")) == 3:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: sequence leg must complete the 3-step run")
	var want: Vector3 = pad.call("get_boost")
	if want.y > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: boost impulse must lift upward")
	var probe := BoostProbe.new()
	pad.call("activate", probe)
	if probe.calls == 1 and probe.last_force == want:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: live pad must launch the BoostProbe")
	probe.free()
	saw.call("press_left")
	if int(saw.call("get_tilt")) == -1 and not bool(saw.call("is_balanced")):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: left-only press must tip without balance")
	saw.call("press_right")
	if int(saw.call("get_tilt")) == 0 and bool(saw.call("is_balanced")):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: both pans down must balance")
	relay_a.call("press")
	var holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	if holders == 1 and not remix_open(true, true, true, true, true, holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: a single relay must keep the remix closed")
	relay_b.call("press")
	holders = (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	var hold_down := bool(hold.call("is_down"))
	var seq_done := bool(pads.call("is_done"))
	var boost_ready := (pad.call("get_boost") as Vector3).y > 0.0
	var balanced := bool(saw.call("is_balanced"))
	if holders == 2 and not remix_open(hold_down, seq_done, boost_ready, balanced, false, holders) and remix_open(hold_down, seq_done, boost_ready, balanced, true, holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: carried duo with all verbs must open the remix")
	relay_a.call("release")
	relay_b.call("release")
	hold.call("release")
	var counts: Dictionary = stage.call("count_props")
	if int(counts.get("button", 0)) >= 1 and int(counts.get("sequence", 0)) >= 1 and int(counts.get("boost", 0)) >= 1 and int(counts.get("seesaw", 0)) >= 1 and int(counts.get("relay", 0)) >= 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: prop census must find >=1 button/sequence/boost/seesaw and >=2 relays")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_08 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
