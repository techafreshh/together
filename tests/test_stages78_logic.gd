extends SceneTree
## Unit runner for world-1 stages 07-08 (issue #16): the timed pair-lever
## sprint and the finale remixing every taught verb. Pattern mirrors
## tests/test_stages56_logic.gd: SceneTree runner with own counters,
## assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_stages78_logic.gd

const Stage07 := preload("res://stages/world1/stage_07.gd")
const Stage08 := preload("res://stages/world1/stage_08.gd")
const LeverProp := preload("res://actors/props/lever.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_manifest_lists_stages78",
		"test_stage07_instantiates",
		"test_stage08_instantiates",
		"test_timed_and_remix_logic",
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


## Manifest: ConfigFile loads, [world1] lists the full 8-id run w1s1..w1s8,
## both new sections ship scene + scaling_2/3/4, w1s7 needs the timed pair,
## w1s8 needs the carried remix duo across the 12 m gap.
func test_manifest_lists_stages78() -> bool:
	var manifest := ConfigFile.new()
	assert_eq(manifest.load("res://stages/world1/manifest.cfg"), OK, "manifest loads")
	var stages: Array = manifest.get_value("world1", "stages", [])
	for wid in ["w1s1", "w1s2", "w1s3", "w1s4", "w1s5", "w1s6", "w1s7", "w1s8"]:
		assert_true(stages.has(wid), "manifest lists " + wid)
	assert_true(manifest.has_section("w1s7"), "manifest has [w1s7]")
	assert_true(manifest.has_section("w1s8"), "manifest has [w1s8]")
	assert_eq(str(manifest.get_value("w1s7", "scene", "")), "res://stages/world1/stage_07.tscn", "w1s7 scene path")
	assert_eq(str(manifest.get_value("w1s8", "scene", "")), "res://stages/world1/stage_08.tscn", "w1s8 scene path")
	for key in ["scaling_2", "scaling_3", "scaling_4"]:
		assert_true(str(manifest.get_value("w1s7", key, "")) != "", "w1s7 carries " + key)
		assert_true(str(manifest.get_value("w1s8", key, "")) != "", "w1s8 carries " + key)
	assert_false(bool(manifest.get_value("w1s7", "solo", true)), "w1s7 is not soloable")
	assert_false(bool(manifest.get_value("w1s8", "solo", true)), "w1s8 is not soloable")
	assert_eq(int(manifest.get_value("w1s7", "pair_required", 0)), 2, "w1s7 pair_required is 2")
	assert_eq(int(manifest.get_value("w1s7", "pair_required", 0)), Stage07.PAIR_REQUIRED, "manifest pair matches const")
	assert_eq(int(manifest.get_value("w1s7", "window_ms", 0)), 2000, "w1s7 window_ms is 2000")
	assert_eq(int(manifest.get_value("w1s7", "window_ms", 0)), Stage07.PAIR_WINDOW_MS, "manifest window matches const")
	assert_eq(int(manifest.get_value("w1s8", "cross_required", 0)), 2, "w1s8 cross_required is 2")
	assert_eq(int(manifest.get_value("w1s8", "carry_required", 0)), 2, "w1s8 carry_required is 2")
	assert_eq(int(manifest.get_value("w1s8", "carry_required", 0)), Stage08.CARRY_REQUIRED, "manifest carry matches const")
	return true


## Stage 07 scene: full scaffold plus the LeverPair sprint gate.
func test_stage07_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_07.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_07 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_07 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_07 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_07 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_07 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_07 Goal exists")
	var levers := stage.get_node_or_null("LeverPair")
	assert_true(levers != null, "stage_07 LeverPair exists")
	if levers != null:
		assert_true(levers.has_method("pull_a"), "LeverPair exposes pull_a")
		assert_true(levers.has_method("pull_b"), "LeverPair exposes pull_b")
		assert_true(levers.has_method("is_paired"), "LeverPair exposes is_paired")
	var counts: Dictionary = stage.call("count_props")
	assert_true(int(counts.get("lever", 0)) >= 1, "stage_07 counts >=1 lever")
	_drop_stage(stage)
	return true


## Stage 08 scene: full scaffold plus every verb prop and two relay posts.
func test_stage08_instantiates() -> bool:
	var stage := _make_stage("res://stages/world1/stage_08.tscn")
	assert_eq(int(stage.get("expected_players")), 2, "stage_08 expects 2 players")
	var spawns: Array = stage.call("get_spawn_points") as Array
	assert_eq(spawns.size(), 4, "stage_08 has Spawn1..Spawn4")
	var cps: Array = stage.call("get_checkpoints") as Array
	assert_true(cps.size() >= 1, "stage_08 registers checkpoints")
	var kill := stage.get_node_or_null("KillPlane") as Node3D
	assert_true(kill != null, "stage_08 KillPlane exists")
	if kill != null:
		assert_true(absf(kill.position.y + 10.0) < 0.01, "stage_08 KillPlane at y=-10")
	assert_true(stage.get_node_or_null("Goal") != null, "stage_08 Goal exists")
	var hold := stage.get_node_or_null("HoldButton")
	var pads := stage.get_node_or_null("SeqPads")
	var pad := stage.get_node_or_null("BoostPad")
	var saw := stage.get_node_or_null("SeeSaw")
	var relay_a := stage.get_node_or_null("RelayA")
	var relay_b := stage.get_node_or_null("RelayB")
	assert_true(hold != null, "stage_08 HoldButton exists")
	if hold != null:
		assert_true(hold.has_method("is_down"), "HoldButton exposes is_down")
	assert_true(pads != null, "stage_08 SeqPads exist")
	if pads != null:
		assert_true(pads.has_method("press_step"), "SeqPads expose press_step")
		assert_true(pads.has_method("is_done"), "SeqPads expose is_done")
	assert_true(pad != null, "stage_08 BoostPad exists")
	if pad != null:
		assert_true(pad.has_method("get_boost"), "BoostPad exposes get_boost")
	assert_true(saw != null, "stage_08 SeeSaw exists")
	if saw != null:
		assert_true(saw.has_method("is_balanced"), "SeeSaw exposes is_balanced")
	assert_true(relay_a != null, "stage_08 RelayA exists")
	assert_true(relay_b != null, "stage_08 RelayB exists")
	if relay_a != null:
		assert_true(relay_a.has_method("is_down"), "RelayA exposes is_down")
	if relay_b != null:
		assert_true(relay_b.has_method("is_down"), "RelayB exposes is_down")
	var counts: Dictionary = stage.call("count_props")
	assert_true(int(counts.get("button", 0)) >= 1, "stage_08 counts >=1 button")
	assert_true(int(counts.get("sequence", 0)) >= 1, "stage_08 counts >=1 sequence")
	assert_true(int(counts.get("boost", 0)) >= 1, "stage_08 counts >=1 boost")
	assert_true(int(counts.get("seesaw", 0)) >= 1, "stage_08 counts >=1 seesaw")
	assert_true(int(counts.get("relay", 0)) >= 2, "stage_08 counts >=2 relays")
	_drop_stage(stage)
	return true


## Timed and remix predicates: in-window pairs complete, unset and
## out-of-window stamps block, any missing finale verb blocks, all five
## verbs open the remix.
func test_timed_and_remix_logic() -> bool:
	assert_eq(Stage07.PAIR_WINDOW_MS, 2000, "PAIR_WINDOW_MS is 2000")
	assert_eq(Stage07.PAIR_WINDOW_MS, LeverProp.PAIR_WINDOW_MS, "stage window matches lever prop")
	assert_eq(Stage07.PAIR_REQUIRED, 2, "PAIR_REQUIRED is 2")
	assert_true(Stage07.pair_complete(1000, 1500), "in-window pair completes")
	assert_true(Stage07.pair_complete(0, 2000), "edge-of-window pair completes")
	assert_false(Stage07.pair_complete(0, 2001), "pair past the window stays blocked")
	assert_false(Stage07.pair_complete(-1, 500), "unset stamp stays blocked")
	assert_false(Stage07.timed_open(0, 5000), "timed gate blocks slow pairs")
	assert_false(Stage07.gate_open(false), "gate blocks unpaired runs")
	assert_true(Stage07.gate_open(true), "gate opens for a latched pair")
	for n in [2, 3, 4]:
		var sc7: Dictionary = Stage07.scaling_for(n)
		assert_true(int(sc7.get("lever_ms", 0)) > 0, "stage_07 scaling_%d tunes lever_ms" % n)
		var sc8: Dictionary = Stage08.scaling_for(n)
		assert_true(int(sc8.get("remix_ms", 0)) > 0, "stage_08 scaling_%d tunes remix_ms" % n)
	assert_false(Stage08.solo_crossable(Stage08.GAP_WIDTH), "solo cannot clear the finale gap")
	assert_true(Stage08.carry_crossable(Stage08.GAP_WIDTH), "relay-carry clears the finale gap")
	assert_false(Stage08.remix_open(false, true, true, true, true, 2), "released hold blocks the remix")
	assert_false(Stage08.remix_open(true, false, true, true, true, 2), "unfinished sequence blocks the remix")
	assert_false(Stage08.remix_open(true, true, false, true, true, 2), "unready boost blocks the remix")
	assert_false(Stage08.remix_open(true, true, true, false, true, 2), "unbalanced see-saw blocks the remix")
	assert_false(Stage08.remix_open(true, true, true, true, false, 2), "uncarried run blocks the remix")
	assert_false(Stage08.remix_open(true, true, true, true, true, 1), "solo carry blocks the remix")
	assert_true(Stage08.remix_open(true, true, true, true, true, 2), "all five verbs open the remix")
	var stage7 := _make_stage("res://stages/world1/stage_07.tscn")
	var levers := stage7.get_node_or_null("LeverPair")
	levers.call("pull_a", 1000)
	assert_false(bool(levers.call("is_paired")), "single pull stays unpaired")
	levers.call("pull_b", 1500)
	assert_true(bool(levers.call("is_paired")), "in-window pair latches")
	levers.call("reset")
	assert_false(bool(levers.call("is_paired")), "reset clears the pair")
	_drop_stage(stage7)
	var stage8 := _make_stage("res://stages/world1/stage_08.tscn")
	var hold := stage8.get_node_or_null("HoldButton")
	var pads := stage8.get_node_or_null("SeqPads")
	var pad := stage8.get_node_or_null("BoostPad")
	var saw := stage8.get_node_or_null("SeeSaw")
	var relay_a := stage8.get_node_or_null("RelayA")
	var relay_b := stage8.get_node_or_null("RelayB")
	hold.call("press")
	assert_true(bool(hold.call("is_down")), "finale hold latches")
	pads.call("press_step", 0)
	pads.call("press_step", 1)
	pads.call("press_step", 2)
	assert_true(bool(pads.call("is_done")), "finale sequence completes")
	assert_true((pad.call("get_boost") as Vector3).y > 0.0, "finale boost lifts upward")
	saw.call("press_left")
	assert_false(bool(saw.call("is_balanced")), "finale left-only press stays unbalanced")
	saw.call("press_right")
	assert_true(bool(saw.call("is_balanced")), "finale see-saw balances with both pans down")
	relay_a.call("press")
	var holders := (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	assert_eq(holders, 1, "single finale relay reads 1 holder")
	assert_false(Stage08.remix_open(true, true, true, true, true, holders), "single finale relay keeps the remix closed")
	relay_b.call("press")
	holders = (1 if bool(relay_a.call("is_down")) else 0) + (1 if bool(relay_b.call("is_down")) else 0)
	assert_eq(holders, 2, "both finale relays read 2 holders")
	assert_true(Stage08.remix_open(true, true, true, true, true, holders), "both finale relays plus carried body open the remix")
	relay_a.call("release")
	relay_b.call("release")
	hold.call("release")
	_drop_stage(stage8)
	return true


## Both stage selftests stay green and assert something.
func test_selftests_green() -> bool:
	var r7: Array = Stage07.run_selftest()
	assert_eq(int(r7[1]), 0, "stage_07 selftest has no failures")
	assert_true(int(r7[0]) > 0, "stage_07 selftest asserts something")
	var r8: Array = Stage08.run_selftest()
	assert_eq(int(r8[1]), 0, "stage_08 selftest has no failures")
	assert_true(int(r8[0]) > 0, "stage_08 selftest asserts something")
	return true
