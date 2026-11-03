extends "res://stages/common/stage_base.gd"
## World 1 stage 6: relay-carry/throw across an unjumpable gap (issue #15).
## Reuses the prop-kit-A scaffold plus two hold-button relay posts (RelayA,
## RelayB). Two floor platforms sit 12 m apart edge to edge, so no solo jump
## clears the gap; only a two-carrier relay-carry/throw does. All gap math
## is server-side tuning consts proven by predicates, not live physics.
## Carry gating lives in stage-side predicates that take arbitrated holder
## counts as plain inputs; no grab RPCs live here.

## Edge-to-edge gap width between the two platforms (m).
const GAP_WIDTH := 12.0
## Generous solo jump range upper bound (m); the tuning-derived arc is ~4.2.
const SOLO_JUMP_RANGE := 5.0
## Relay-carry/throw reach (m): comfortably clears GAP_WIDTH, still a bound.
const RELAY_RANGE := 14.0
## Carriers required alongside a carried body to open the crossing.
const CARRY_REQUIRED := 2


func _init() -> void:
	expected_players = 2


## True when a plain jump of `dist` metres lands across.
static func solo_crossable(dist: float) -> bool:
	return dist <= SOLO_JUMP_RANGE


## True when a relay-carry/throw of `dist` metres lands across.
static func carry_crossable(dist: float) -> bool:
	return dist <= RELAY_RANGE


## True while the relay-carry crossing is open: a body is carried plus
## enough carriers hold the relay posts.
static func cross_open(carried: bool, carriers: int) -> bool:
	return carried and carriers >= CARRY_REQUIRED


## Live prop census: walks the subtree counting hold-buttons (is_down).
## Both RelayA and RelayB expose is_down, so both keys agree.
func count_props() -> Dictionary:
	var counts := {"button": 0, "relay": 0}
	_count_props_into(self, counts)
	return counts


static func _count_props_into(node: Node, counts: Dictionary) -> void:
	for child in node.get_children():
		if child.has_method("is_down"):
			counts["button"] = int(counts["button"]) + 1
			counts["relay"] = int(counts["relay"]) + 1
		_count_props_into(child, counts)


## Per-party-size tuning for 2/3/4 players: relay timing and platform width
## only. The gap width and carrier requirement never shrink.
static func scaling_for(player_count: int) -> Dictionary:
	var n := clampi(player_count, 2, 4)
	var relay_ms := {2: 1500, 3: 2000, 4: 2500}
	var widths := {2: 3.0, 3: 3.5, 4: 4.0}
	return {"players": n, "platform_width": float(widths[n]), "relay_ms": int(relay_ms[n])}


## Synchronous self-test: proves the solo-blocked/duo-carry predicates,
## the scaling table, then instantiates stage_06.tscn and drives the live
## RelayA/RelayB posts: a single press keeps the crossing closed, both
## presses open it for a carried body. Plus the full scaffold assertions.
## Returns [passed, failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if GAP_WIDTH == 12.0 and SOLO_JUMP_RANGE == 5.0 and RELAY_RANGE == 14.0 and CARRY_REQUIRED == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: tuning consts must be 12.0/5.0/14.0/2")
	if not solo_crossable(GAP_WIDTH) and not solo_crossable(GAP_WIDTH + 1.0) and solo_crossable(SOLO_JUMP_RANGE):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: solo jump must not clear the gap")
	if carry_crossable(GAP_WIDTH) and not carry_crossable(RELAY_RANGE + 1.0):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: relay-carry must clear the gap within range")
	if not cross_open(false, 1) and not cross_open(false, 2) and not cross_open(true, 1) and not cross_open(true, 0):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: solo and uncarried crossings must stay blocked")
	if cross_open(true, 2) and cross_open(true, 4):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: carried duo must open the crossing")
	for n in [2, 3, 4]:
		var sc: Dictionary = scaling_for(n)
		if int(sc.get("players", 0)) == n and float(sc.get("platform_width", 0.0)) > 0.0 and int(sc.get("relay_ms", 0)) > 0:
			passed += 1
		else:
			failed += 1
			push_error("stage_06 selftest: scaling_for(%d) must carry players, width, relay_ms" % n)
	var packed: PackedScene = load("res://stages/world1/stage_06.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("stage_06 selftest: stage_06.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("stage_06 selftest: stage_06.tscn failed to instantiate")
		return [passed, failed]
	if int(stage.get("expected_players")) == 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: expected_players must be 2 (relay carry)")
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y + 10.0) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: KillPlane must sit at y=-10")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: Goal node missing")
	var relay_a := stage.get_node_or_null("RelayA")
	var relay_b := stage.get_node_or_null("RelayB")
	if relay_a != null and relay_b != null and relay_a.has_method("is_down") and relay_b.has_method("is_down"):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: RelayA and RelayB hold-button nodes missing")
		stage.free()
		return [passed, failed]
	if not bool(relay_a.call("is_down")) and not bool(relay_b.call("is_down")):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: both relays must start up")
	relay_a.call("press")
	var holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	if holders == 1 and not cross_open(true, holders) and not cross_open(false, holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: single relay must keep the crossing closed")
	relay_b.call("press")
	holders = (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	if holders == 2 and not cross_open(false, holders) and cross_open(true, holders):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: both relays plus a carried body must open the crossing")
	relay_a.call("press")
	if int(relay_a.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: duplicate relay hold must not double-count")
	relay_a.call("release")
	relay_b.call("release")
	var counts: Dictionary = stage.call("count_props")
	if int(counts.get("relay", 0)) >= 2 and int(counts.get("button", 0)) >= 2:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: prop census must find >=2 relays")
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var a := Node.new()
	var b := Node.new()
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: one player in the goal must stay incomplete")
	stage.call("notify_goal_entered", a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("stage_06 selftest: both players in the goal must complete with goal_all_reached")
	a.free()
	b.free()
	stage.free()
	return [passed, failed]
