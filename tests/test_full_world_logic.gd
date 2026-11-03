extends SceneTree
## Unit runner for the full-world composition surface (issue #24,
## socket-free). Pattern mirrors tests/test_export_logic.gd: SceneTree
## runner with own counters, assert_eq-style helpers, and quit(1 if failed
## > 0 else 0). Covers the composition the `-- --selftest full_world`
## headless branch drives — manifest shape, coin total, desktop parse, and
## wardrobe pricing — without instantiating scenes or touching sockets.
## Run: godot --headless --path . --script res://tests/test_full_world_logic.gd

const Serve := preload("res://server/serve.gd")
const FlowManager := preload("res://server/flow_manager.gd")
const Wardrobe := preload("res://server/wardrobe.gd")
const Persistence := preload("res://server/persistence.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_manifest_lists_eight_stages",
		"test_first_clear_total_is_full_run",
		"test_desktop_preset_parses",
		"test_hat_cone_price",
		"test_shared_selftests_pass",
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


## The world-1 manifest lists w1s1..w1s8 in order, each with a scene path
## and 2/3/4-player scaling tuning.
func test_manifest_lists_eight_stages() -> bool:
	var manifest := ConfigFile.new()
	assert_eq(manifest.load("res://stages/world1/manifest.cfg"), OK, "manifest loads")
	var stages: Array = manifest.get_value("world1", "stages", [])
	assert_eq(stages.size(), 8, "manifest lists 8 stages")
	var want := ["w1s1", "w1s2", "w1s3", "w1s4", "w1s5", "w1s6", "w1s7", "w1s8"]
	for wid in want:
		assert_true(stages.has(wid), "manifest lists %s" % wid)
		assert_true(manifest.has_section(wid), "manifest carries [%s]" % wid)
		assert_true(str(manifest.get_value(wid, "scene", "")).ends_with(".tscn"), "manifest [%s] scene" % wid)
		for key in ["scaling_2", "scaling_3", "scaling_4"]:
			assert_true(str(manifest.get_value(wid, key, "")) != "", "manifest [%s] %s" % [wid, key])
	return true


## One full 8-stage first-clear run pays FIRST_CLEAR_COINS x 8 (800), the
## same total the wardrobe catalog prices against.
func test_first_clear_total_is_full_run() -> bool:
	assert_eq(FlowManager.STAGE_IDS.size(), 8, "flow catalog has 8 stages")
	assert_eq(str(FlowManager.STAGE_IDS[0]), "w1s1", "flow catalog starts at w1s1")
	assert_eq(str(FlowManager.STAGE_IDS[7]), "w1s8", "flow catalog ends at w1s8")
	assert_eq(FlowManager.FIRST_CLEAR_COINS * FlowManager.STAGE_IDS.size(), 800, "first-clear total is 800")
	assert_eq(Wardrobe.full_run_coins(), 800, "wardrobe full-run total is 800")
	return true


## The shipped export_presets.cfg carries the Windows Desktop preset the
## full-world probe's desktop leg checks; bogus paths fail it.
func test_desktop_preset_parses() -> bool:
	var found := Serve.check_desktop_preset("res://export_presets.cfg")
	assert_eq(int(found.get("preset", 0)), 1, "windows preset parses")
	var missing := Serve.check_desktop_preset("res://does-not-exist.cfg")
	assert_eq(int(missing.get("preset", 0)), 0, "missing preset file fails")
	var web := Serve.check_export_preset("res://export_presets.cfg")
	assert_eq(int(web.get("preset", 0)), 1, "web preset undisturbed")
	return true


## The full-world run funds its wardrobe leg with hat_cone (100): the
## cheapest hat plus the cheapest skin must fit one full run (800).
func test_hat_cone_price() -> bool:
	assert_eq(Wardrobe.price_for("hat_cone"), 100, "hat_cone costs 100")
	var cheapest := 1 << 30
	for skin_id in Wardrobe.SKIN_IDS:
		var price := Wardrobe.price_for(skin_id)
		if price >= 0 and price < cheapest:
			cheapest = price
	assert_true(cheapest > 0, "cheapest skin priced")
	assert_true(100 + cheapest <= Wardrobe.full_run_coins(), "hat+skin fits one full run")
	return true


## The shared synchronous self-tests the full-world sweep reuses all pass
## with zero failures, socket-free.
func test_shared_selftests_pass() -> bool:
	var flow_result: Array = FlowManager.run_selftest()
	assert_eq(int(flow_result[1]), 0, "flow selftest has no failures")
	var wardrobe_result: Array = Wardrobe.run_selftest()
	assert_eq(int(wardrobe_result[1]), 0, "wardrobe selftest has no failures")
	var persist_result: Array = Persistence.run_selftest(OS.get_temp_dir().path_join("together_full_world_unit"))
	assert_eq(int(persist_result[1]), 0, "persist selftest has no failures")
	return true
