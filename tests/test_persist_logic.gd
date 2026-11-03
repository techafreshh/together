extends SceneTree
## Unit runner for server-side JSON persistence (issue #17): name
## sanitization, default profile shape, save/load round-trip, corrupt-file
## tolerance, coins/clears/purchase semantics, and the shared self-test.
## Pattern mirrors tests/test_rooms_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_persist_logic.gd

const Persistence := preload("res://server/persistence.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_sanitize",
		"test_default_shape",
		"test_save_load_roundtrip",
		"test_corrupt_tolerant",
		"test_coins_clears_purchase",
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


func _scratch_dir(name: String) -> String:
	var dir := OS.get_temp_dir() + "/together_persist_" + name
	Persistence.ensure_dir(dir)
	return dir


func test_sanitize() -> bool:
	assert_eq(Persistence.sanitize_name("TestPlayer"), "TestPlayer", "plain name survives")
	assert_eq(Persistence.sanitize_name("  TestPlayer  "), "TestPlayer", "edges trimmed")
	assert_eq(Persistence.sanitize_name("a/b\\c"), "a_b_c", "separators become underscores")
	assert_eq(Persistence.sanitize_name("A B"), "A_B", "space becomes underscore")
	assert_eq(Persistence.sanitize_name("a!b@c"), "a_b_c", "punctuation becomes underscores")
	assert_eq(Persistence.sanitize_name("a-b_c9"), "a-b_c9", "dash/underscore/digits kept")
	assert_eq(Persistence.sanitize_name(""), "Player", "empty falls back to Player")
	assert_eq(Persistence.sanitize_name("   "), "Player", "blank falls back to Player")
	var long_name := ""
	for i in range(40):
		long_name += "a"
	assert_eq(Persistence.sanitize_name(long_name).length(), 32, "names cap at 32 chars")
	assert_true(Persistence.player_path("/tmp/data", "TestPlayer").ends_with("TestPlayer.json"), "player file is <name>.json")
	assert_eq(Persistence.player_path("/tmp/data/", "TestPlayer"), "/tmp/data/TestPlayer.json", "trailing slash tolerated")
	return true


func test_default_shape() -> bool:
	var profile := Persistence.default_profile()
	assert_eq(int(profile.get("coins", -1)), 0, "fresh coins are 0")
	assert_eq(profile.get("owned", null), [], "fresh owned is empty")
	assert_eq(profile.get("equipped", null), {}, "fresh equipped is empty")
	assert_eq(profile.get("stages", null), {}, "fresh stages is empty")
	return true


func test_save_load_roundtrip() -> bool:
	var dir := _scratch_dir("roundtrip")
	var profile := Persistence.default_profile()
	profile["coins"] = 7
	(profile["owned"] as Array).append("hat-red")
	(profile["equipped"] as Dictionary)["hat"] = "hat-red"
	Persistence.record_clear(profile, "w1s1", 1234)
	assert_eq(bool(Persistence.save_player(dir, "RoundTrip", profile)), true, "save ok")
	var reloaded := Persistence.load_player(dir, "RoundTrip")
	assert_eq(int(reloaded.get("coins", -1)), 7, "coins survive the round-trip")
	assert_true((reloaded.get("owned", []) as Array).has("hat-red"), "owned survives the round-trip")
	assert_eq(str((reloaded.get("equipped", {}) as Dictionary).get("hat", "")), "hat-red", "equipped survives the round-trip")
	var stages: Dictionary = reloaded.get("stages", {})
	assert_true(stages.has("w1s1"), "stage survives the round-trip")
	assert_eq(int((stages.get("w1s1", {}) as Dictionary).get("clears", 0)), 1, "clears survive the round-trip")
	assert_eq(int((stages.get("w1s1", {}) as Dictionary).get("best_ms", 0)), 1234, "best_ms survives the round-trip")
	var raw := FileAccess.get_file_as_string(Persistence.player_path(dir, "RoundTrip"))
	assert_true(raw.contains("\"coins\""), "saved JSON carries coins")
	assert_true(raw.contains("\"stages\""), "saved JSON carries stages")
	return true


func test_corrupt_tolerant() -> bool:
	var dir := _scratch_dir("corrupt")
	var missing := Persistence.load_player(dir, "NobodyHere")
	assert_eq(int(missing.get("coins", -1)), 0, "missing file returns defaults")
	assert_eq(missing.get("stages", null), {}, "missing file has empty stages")
	Persistence.ensure_dir(dir)
	var path := Persistence.player_path(dir, "Corrupt")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not valid json!!!")
	f.close()
	var fallback := Persistence.load_player(dir, "Corrupt")
	assert_eq(int(fallback.get("coins", -1)), 0, "corrupt file returns defaults")
	assert_eq(fallback.get("stages", null), {}, "corrupt file has empty stages")
	return true


func test_coins_clears_purchase() -> bool:
	var profile := Persistence.default_profile()
	assert_eq(Persistence.add_coins(profile, 5), 5, "add 5 coins")
	assert_eq(Persistence.add_coins(profile, -8), 0, "coins clamp at zero")
	Persistence.add_coins(profile, 10)
	var first := Persistence.record_clear(profile, "w1s1", 2000)
	assert_eq(int(first.get("clears", 0)), 1, "first clear counts 1")
	assert_eq(int(first.get("best_ms", 0)), 2000, "first best recorded")
	var second := Persistence.record_clear(profile, "w1s1", 1500)
	assert_eq(int(second.get("clears", 0)), 2, "second clear counts 2")
	assert_eq(int(second.get("best_ms", 0)), 1500, "best improves to faster time")
	var third := Persistence.record_clear(profile, "w1s1", 9000)
	assert_eq(int(third.get("best_ms", 0)), 1500, "best keeps the faster time")
	var bought := Persistence.try_purchase(profile, "hat-red", 4)
	assert_eq(bool(bought.get("ok", false)), true, "affordable purchase ok")
	assert_eq(int(profile.get("coins", -1)), 6, "purchase deducts coins")
	assert_true((profile.get("owned", []) as Array).has("hat-red"), "purchase lands in owned")
	var dup := Persistence.try_purchase(profile, "hat-red", 4)
	assert_eq(bool(dup.get("ok", true)), false, "duplicate purchase rejected")
	assert_eq(str(dup.get("error", "")), "already_owned", "duplicate error names already_owned")
	var broke := Persistence.try_purchase(profile, "cape-gold", 600)
	assert_eq(bool(broke.get("ok", true)), false, "unaffordable purchase rejected")
	assert_eq(str(broke.get("error", "")), "insufficient_coins", "broke error names insufficient_coins")
	return true


func test_selftest_green() -> bool:
	var dir := _scratch_dir("selftest")
	var r: Array = Persistence.run_selftest(dir)
	assert_eq(int(r[1]), 0, "persist selftest has no failures")
	assert_true(int(r[0]) > 0, "persist selftest asserts something")
	assert_eq(Persistence.SELFTEST_PLAYER, "TestPlayer", "selftest proves TestPlayer")
	assert_eq(Persistence.SELFTEST_COINS, 1, "selftest awards exactly 1 coin")
	return true
