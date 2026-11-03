extends SceneTree
## Unit runner for the stage-to-stage flow (issue #11): catalog shape, host
## guard, boot handoff, all-players goal gate, first-clear vs replay coins,
## and the shared self-test.
## Pattern mirrors tests/test_rooms_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_flow_logic.gd

const FlowManager := preload("res://server/flow_manager.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_stage_ids",
		"test_host_guard",
		"test_boot_shape",
		"test_goal_requires_all",
		"test_results_coins",
		"test_selftest_green",
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


func test_stage_ids() -> bool:
	assert_eq(FlowManager.STAGE_IDS.size(), 8, "catalog holds 8 stages")
	assert_eq(str(FlowManager.STAGE_IDS[0]), "w1s1", "catalog starts at w1s1")
	assert_eq(str(FlowManager.STAGE_IDS[7]), "w1s8", "catalog ends at w1s8")
	assert_true(FlowManager.is_valid_stage("w1s1"), "w1s1 validates")
	assert_true(FlowManager.is_valid_stage("w1s8"), "w1s8 validates")
	assert_true(not FlowManager.is_valid_stage("w9s9"), "unknown stage rejected")
	assert_true(not FlowManager.is_valid_stage(""), "empty stage rejected")
	assert_eq(FlowManager.checkpoints_for("w1s1"), ["cp1", "cp2"], "stage carries cp1+cp2")
	assert_eq(FlowManager.checkpoints_for("w9s9"), [], "unknown stage has no checkpoints")
	assert_eq(FlowManager.FIRST_CLEAR_COINS, 100, "first clear pays 100")
	assert_eq(FlowManager.REPLAY_COINS, 10, "replay trickle pays 10")
	assert_eq(FlowManager.SELFTEST_STAGE, "w1s1", "selftest proves w1s1")
	return true


func test_host_guard() -> bool:
	var mgr = FlowManager.new()
	mgr.bind_room("ABCD", [11, 22], 11)
	var picked: Dictionary = mgr.select_stage("ABCD", 11, 11, "w1s1")
	assert_eq(bool(picked.get("ok", false)), true, "host select ok")
	assert_eq(str(picked.get("stage_id", "")), "w1s1", "host select echoes w1s1")
	var denied: Dictionary = mgr.select_stage("ABCD", 22, 11, "w1s2")
	assert_eq(bool(denied.get("ok", false)), false, "non-host select rejected")
	assert_eq(str(denied.get("error", "")), "host_only", "non-host error names host_only")
	var unknown: Dictionary = mgr.select_stage("ABCD", 11, 11, "w9s9")
	assert_eq(bool(unknown.get("ok", false)), false, "unknown stage rejected")
	assert_eq(str(unknown.get("error", "")), "unknown_stage", "unknown error names unknown_stage")
	var lower: Dictionary = mgr.select_stage("abcd", 11, 11, "w1s3")
	assert_eq(bool(lower.get("ok", false)), true, "lowercase code normalizes")
	return true


func test_boot_shape() -> bool:
	var mgr = FlowManager.new()
	mgr.bind_room("EFGH", [31, 32], 31)
	assert_eq(bool(mgr.start_stage("EFGH").get("ok", false)), false, "start without select rejected")
	mgr.select_stage("EFGH", 31, 31, "w1s1")
	var started: Dictionary = mgr.start_stage("EFGH")
	assert_eq(bool(started.get("ok", false)), true, "start ok after host select")
	assert_true(started.has("stage_boot"), "envelope carries stage_boot")
	var boot: Dictionary = started["stage_boot"]
	assert_eq(str(boot.get("stage_id", "")), "w1s1", "boot carries the selected stage")
	assert_eq(boot.get("checkpoints", []), ["cp1", "cp2"], "boot carries 2 checkpoints")
	var spawns: Dictionary = boot.get("spawn_map", {})
	assert_eq(spawns.size(), 2, "spawn_map covers both peers")
	assert_eq(int(spawns.get(31, -1)), 0, "first peer takes slot 0")
	assert_eq(int(spawns.get(32, -1)), 1, "second peer takes slot 1")
	return true


func test_goal_requires_all() -> bool:
	var mgr = FlowManager.new()
	mgr.bind_room("JKLM", [41, 42], 41)
	mgr.select_stage("JKLM", 41, 41, "w1s1")
	mgr.start_stage("JKLM")
	var first: Dictionary = mgr.notify_goal("JKLM", 41)
	assert_eq(int(first.get("goal_count", 0)), 1, "one goal counted")
	assert_eq(bool(first.get("goal_all", true)), false, "one goal is incomplete")
	assert_true(not mgr.is_goal_all("JKLM"), "is_goal_all false with one goal")
	var dup: Dictionary = mgr.notify_goal("JKLM", 41)
	assert_eq(int(dup.get("goal_count", 0)), 1, "duplicate goal not double-counted")
	var second: Dictionary = mgr.notify_goal("JKLM", 42)
	assert_eq(int(second.get("goal_count", 0)), 2, "both goals counted")
	assert_eq(bool(second.get("goal_all", false)), true, "both goals set goal_all")
	assert_true(mgr.is_goal_all("JKLM"), "is_goal_all true with both goals")
	assert_true(mgr.goal_all("JKLM"), "goal_all accessor true with both goals")
	return true


func test_results_coins() -> bool:
	var mgr = FlowManager.new()
	mgr.bind_room("NPQR", [51, 52], 51)
	mgr.select_stage("NPQR", 51, 51, "w1s1")
	mgr.start_stage("NPQR")
	var early: Dictionary = mgr.build_results("NPQR")
	assert_eq(bool(early.get("ok", false)), false, "results before goal_all rejected")
	assert_eq(str(early.get("error", "")), "not_cleared", "early error names not_cleared")
	mgr.notify_goal("NPQR", 51)
	mgr.notify_goal("NPQR", 52)
	var built: Dictionary = mgr.build_results("NPQR")
	assert_eq(bool(built.get("ok", false)), true, "results ok after goal_all")
	assert_true(built.has("results"), "envelope carries results")
	var res: Dictionary = built["results"]
	assert_true(res.has("clears"), "results has clears")
	assert_true(res.has("bests"), "results has bests")
	assert_true(res.has("coins_awarded"), "results has coins_awarded")
	var coins: Dictionary = res["coins_awarded"]
	assert_eq(int(coins.get("51", 0)), 100, "first clear pays 100")
	assert_eq(int(coins.get("52", 0)), 100, "first clear pays 100 for peer two")
	mgr.select_stage("NPQR", 51, 51, "w1s1")
	mgr.start_stage("NPQR")
	assert_true(not mgr.goal_all("NPQR"), "new run resets goal_all")
	mgr.notify_goal("NPQR", 51)
	mgr.notify_goal("NPQR", 52)
	var again: Dictionary = mgr.build_results("NPQR")
	var res2: Dictionary = again["results"]
	var coins2: Dictionary = res2["coins_awarded"]
	assert_eq(int(coins2.get("51", 0)), 10, "replay trickle pays 10")
	assert_eq(int(coins2.get("52", 0)), 10, "replay trickle pays 10 for peer two")
	var clears2: Dictionary = (res2.get("clears", {}) as Dictionary).get("w1s1", {})
	assert_eq(int(clears2.get("51", 0)), 2, "clears count reaches 2")
	assert_true((res2.get("bests", {}) as Dictionary).has("w1s1"), "bests records the cleared stage")
	return true


func test_selftest_green() -> bool:
	var r: Array = FlowManager.run_selftest()
	assert_eq(int(r[1]), 0, "flow selftest has no failures")
	assert_true(int(r[0]) > 0, "flow selftest asserts something")
	assert_eq(FlowManager.SELFTEST_PLAYERS, 2, "selftest proves 2 players")
	return true
