extends SceneTree
## Unit runner for the menu room world-select HUD results flow (issue #19).
## Pattern mirrors tests/test_scaffold_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_ui_logic.gd

const MainMenu := preload("res://scenes/main_menu.gd")
const Lobby := preload("res://scenes/lobby.gd")
const WardrobeUi := preload("res://scenes/wardrobe.gd")
const Hud := preload("res://scenes/hud.gd")
const Results := preload("res://scenes/results.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	# Mute the Sfx autoload so button-press wiring stays a silent no-op:
	# real playback would pin wav playbacks past quit() (exit warnings).
	var sfx := root.get_node_or_null("Sfx")
	if sfx != null and sfx.has_method("set_muted"):
		sfx.call("set_muted", true)
	_run_all()


## Drives each test, awaiting coroutine tests so _ready wiring flushes
## before button presses are exercised. Sync tests pass through await.
func _run_all() -> void:
	for t: String in [
		"test_scenes_load",
		"test_required_nodes",
		"test_hud_setters",
		"test_lobby_badges_and_wait",
		"test_results_coins_votes",
		"test_net_placeholder",
	]:
		var ok = await call(t)
		if ok != true:
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


## Loads one UI scene under the tree root (so _ready wiring runs) and
## returns it; pair every call with _drop_scene.
func _make_scene(path: String) -> Node:
	var packed: PackedScene = load(path) as PackedScene
	var node: Node = packed.instantiate() as Node
	root.add_child(node)
	return node


func _drop_scene(node: Node) -> void:
	root.remove_child(node)
	node.free()


func test_scenes_load() -> bool:
	for path in [
		"res://scenes/main_menu.tscn",
		"res://scenes/lobby.tscn",
		"res://scenes/wardrobe.tscn",
		"res://scenes/hud.tscn",
		"res://scenes/results.tscn",
	]:
		var packed: PackedScene = load(path) as PackedScene
		assert_true(packed != null and packed.can_instantiate(), "%s loads" % path)
		if packed != null:
			var node: Node = packed.instantiate() as Node
			assert_true(node != null, "%s instantiates" % path)
			if node != null:
				node.free()
	return true


func test_required_nodes() -> bool:
	var pairs := [
		["res://scenes/main_menu.tscn", MainMenu],
		["res://scenes/lobby.tscn", Lobby],
		["res://scenes/wardrobe.tscn", WardrobeUi],
		["res://scenes/hud.tscn", Hud],
		["res://scenes/results.tscn", Results],
	]
	for pair in pairs:
		var node := _make_scene(str(pair[0]))
		var needed: Array = (pair[1] as Script).call("required_nodes")
		assert_true(needed.size() >= 2, "%s declares contract nodes" % str(pair[0]))
		for p in needed:
			assert_true(node.get_node_or_null(str(p)) != null, "%s carries %s" % [str(pair[0]), str(p)])
		_drop_scene(node)
	return true


func test_hud_setters() -> bool:
	var hud := _make_scene("res://scenes/hud.tscn")
	hud.call("set_room_code", "abcd")
	assert_eq((hud.get_node_or_null("RoomCodeLabel") as Label).text, "ABCD", "room code uppercases")
	hud.call("set_objective", "Reach the goal together")
	assert_eq((hud.get_node_or_null("ObjectiveLabel") as Label).text, "Reach the goal together", "objective assigns")
	hud.call("set_carry_hint", "Lift and throw")
	assert_eq((hud.get_node_or_null("CarryHint") as Label).text, "Lift and throw", "carry hint assigns")
	hud.call("set_carry_hint", "")
	assert_eq((hud.get_node_or_null("CarryHint") as Label).text, Hud.DEFAULT_CARRY_HINT, "empty hint falls back")
	_drop_scene(hud)
	return true


func test_lobby_badges_and_wait() -> bool:
	var lobby := _make_scene("res://scenes/lobby.tscn")
	var state := {
		"code": "ABCD",
		"host_id": 1,
		"screen": "lobby",
		"players": [
			{"id": 1, "name": "Host", "color": "#EF476F", "ready": true},
			{"id": 2, "name": "Guest", "color": "#118AB2", "ready": false},
		],
	}
	lobby.call("refresh", state)
	var list := lobby.get_node_or_null("PlayerList")
	var texts: Array = []
	for child in list.get_children():
		texts.append(str((child as Label).text))
	assert_eq(texts.size(), 2, "refresh builds one row per player")
	assert_true(texts[0].contains("[HOST]") and texts[0].contains("[READY]"), "host row carries crown + badge")
	assert_true(not texts[1].contains("[READY]"), "unready guest carries no badge")
	lobby.call("show_lobby_wait", true)
	assert_true((lobby.get_node_or_null("StatusLabel") as Label).text.contains("lobby_wait"), "wait shows lobby_wait gate")
	lobby.call("show_lobby_wait", false)
	assert_eq((lobby.get_node_or_null("StatusLabel") as Label).text, "", "wait clears")
	lobby.call("set_stage_options", ["w1s1", "w1s2"])
	assert_eq((lobby.get_node_or_null("StagePicker") as OptionButton).item_count, 2, "picker lists stages")
	lobby.call("set_bests", {"w1s1": 100})
	assert_true((lobby.get_node_or_null("BestsLabel") as Label).text.contains("w1s1: 100c"), "bests render personal lines")
	_drop_scene(lobby)
	return true


func test_results_coins_votes() -> bool:
	var results := _make_scene("res://scenes/results.tscn")
	# Flush _ready so the VoteBox button wiring exists before presses.
	await process_frame
	await process_frame
	var votes: Array = []
	results.connect("stage_voted", func(stage_id): votes.append(str(stage_id)))
	results.call("show_results", {
		"clears": {"w1s1": {"1": 1, "2": 1}},
		"bests": {"w1s1": 1},
		"coins_awarded": {"1": 100, "2": 100},
	})
	assert_true((results.get_node_or_null("CoinsLabel") as Label).text.contains("100c"), "coins render totals")
	assert_true((results.get_node_or_null("ResultsBests") as Label).text.contains("w1s1"), "bests render stage lines")
	(results.get_node_or_null("VoteBox/VoteYes") as Button).pressed.emit()
	assert_eq(votes, ["next"], "VoteYes emits a next vote")
	(results.get_node_or_null("VoteBox/VoteNo") as Button).pressed.emit()
	assert_eq(votes, ["next", "replay"], "VoteNo emits a replay vote")
	assert_eq(str(results.call("last_vote")), "replay", "last vote echoes replay")
	_drop_scene(results)
	var room := _make_scene("res://scenes/wardrobe.tscn")
	assert_true(bool(room.call("preview_hat", "hat_cone")), "hat_cone previews")
	assert_true(bool(room.call("preview_skin", "charcoal")), "charcoal previews")
	assert_eq(str(room.call("current_skin")), "charcoal", "current skin echoes charcoal")
	assert_false(bool(room.call("preview_hat", "cape-gold")), "unknown hat fails closed")
	assert_false(bool(room.call("preview_skin", "nope")), "unknown skin fails closed")
	_drop_scene(room)
	return true


func test_net_placeholder() -> bool:
	for path in [
		"res://scenes/main_menu.tscn",
		"res://scenes/main_menu.gd",
		"res://scenes/lobby.tscn",
		"res://scenes/lobby.gd",
		"res://scenes/wardrobe.tscn",
		"res://scenes/wardrobe.gd",
		"res://scenes/hud.tscn",
		"res://scenes/hud.gd",
		"res://scenes/results.tscn",
		"res://scenes/results.gd",
	]:
		var text := FileAccess.get_file_as_string(path)
		assert_true(text.contains("Net."), "%s carries the Net. placeholder" % path)
	return true
