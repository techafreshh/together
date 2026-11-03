extends SceneTree
## Unit runner for the rooms lobby (issue #10): 4-char codes, uniqueness,
## join-by-code, duplicate names, 2-4 capacity, leave/rehost, ready badges,
## room_state shape, room cap, and the shared self-test.
## Pattern mirrors tests/test_serve_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_rooms_logic.gd

const RoomManager := preload("res://server/room_manager.gd")
const ConfigScript := preload("res://autoload/Config.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_code_format",
		"test_code_uniqueness",
		"test_join_shape",
		"test_duplicate_names_allowed",
		"test_capacity_cap",
		"test_leave_rehost_erase",
		"test_ready_badges",
		"test_room_state_shape",
		"test_room_cap",
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


func test_code_format() -> bool:
	var mgr = RoomManager.new()
	var r: Dictionary = mgr.create_room("Alice", "hash-a")
	assert_eq(bool(r.get("ok", false)), true, "create ok")
	var code := str(r.get("code", ""))
	assert_eq(code.length(), 4, "code is 4 chars")
	assert_eq(code.length(), RoomManager.CODE_LENGTH, "code matches CODE_LENGTH")
	assert_true(RoomManager.is_valid_code(code), "created code validates")
	assert_true(not RoomManager.is_valid_code("abc"), "3-char code rejected")
	assert_true(not RoomManager.is_valid_code("ABCDE"), "5-char code rejected")
	assert_true(not RoomManager.is_valid_code("AB12"), "lookalike digit 1 rejected")
	assert_true(not RoomManager.is_valid_code("ab12"), "lowercase code rejected")
	assert_true(not RoomManager.is_valid_code(""), "empty code rejected")
	assert_true(not RoomManager.is_valid_code(1234), "non-string code rejected")
	return true


func test_code_uniqueness() -> bool:
	var mgr = RoomManager.new()
	var seen := {}
	var all_ok := true
	for i in range(50):
		var r: Dictionary = mgr.create_room("P%d" % i, "h%d" % i)
		if not bool(r.get("ok", false)):
			all_ok = false
			break
		var code := str(r.get("code", ""))
		seen[code] = true
		if not RoomManager.is_valid_code(code):
			all_ok = false
	assert_true(all_ok, "50 creates all ok with valid codes")
	assert_eq(seen.size(), 50, "50 codes are unique")
	assert_eq(mgr.list_codes().size(), 50, "list_codes reports 50 rooms")
	return true


func test_join_shape() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Alice", "cosmetic-red")
	var code := str(host.get("code", ""))
	var joined: Dictionary = mgr.join_room(code, "Bob", "cosmetic-blue")
	assert_eq(bool(joined.get("ok", false)), true, "join-by-code ok")
	assert_eq(str(joined.get("code", "")), code, "join echoes code")
	assert_true(int(joined.get("player_id", 0)) != int(host.get("player_id", 0)), "join mints a fresh player id")
	var unknown: Dictionary = mgr.join_room("ZZZZ", "Mallory", "x")
	assert_eq(bool(unknown.get("ok", false)), false, "unknown code rejected")
	assert_eq(str(unknown.get("error", "")), "unknown_code", "unknown code error names unknown_code")
	var malformed: Dictionary = mgr.join_room("abc", "Mallory", "x")
	assert_eq(bool(malformed.get("ok", false)), false, "malformed code rejected")
	var lower: Dictionary = mgr.join_room(code.to_lower(), "Cara", "cosmetic-green")
	assert_eq(bool(lower.get("ok", false)), true, "lowercase code normalizes and joins")
	return true


func test_duplicate_names_allowed() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Sam", "hash-1")
	var code := str(host.get("code", ""))
	var again: Dictionary = mgr.join_room(code, "Sam", "hash-2")
	assert_eq(bool(again.get("ok", false)), true, "duplicate name shares-save accepted")
	assert_true(int(again.get("player_id", 0)) != int(host.get("player_id", 0)), "duplicate name gets its own id")
	var st: Dictionary = mgr.room_state(code)
	var names: Array = []
	for p in ((st.get("room_state", {}) as Dictionary).get("players", []) as Array):
		names.append(str((p as Dictionary).get("name", "")))
	assert_eq(names, ["Sam", "Sam"], "both Sams persist in the player list")
	return true


func test_capacity_cap() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Host", "h")
	var code := str(host.get("code", ""))
	for i in range(ConfigScript.MAX_ROOM_PLAYERS - 1):
		var j: Dictionary = mgr.join_room(code, "Guest%d" % i, "c%d" % i)
		assert_eq(bool(j.get("ok", false)), true, "join %d of %d accepted" % [i + 2, ConfigScript.MAX_ROOM_PLAYERS])
	var overflow: Dictionary = mgr.join_room(code, "Extra", "e")
	assert_eq(bool(overflow.get("ok", false)), false, "5th join rejected (2-4 cap)")
	assert_eq(str(overflow.get("error", "")), "room_full", "overflow error names room_full")
	var st: Dictionary = mgr.room_state(code)
	assert_eq(((st.get("room_state", {}) as Dictionary).get("players", []) as Array).size(), ConfigScript.MAX_ROOM_PLAYERS, "room holds MAX_ROOM_PLAYERS players")
	assert_eq(ConfigScript.MIN_ROOM_PLAYERS, 2, "lobby minimum is 2 players")
	assert_eq(ConfigScript.MAX_ROOM_PLAYERS, 4, "lobby maximum is 4 players")
	return true


func test_leave_rehost_erase() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Host", "h")
	var code := str(host.get("code", ""))
	var host_id := int(host.get("player_id", 0))
	var guest: Dictionary = mgr.join_room(code, "Guest", "g")
	var guest_id := int(guest.get("player_id", 0))
	assert_eq(bool(mgr.leave_room(code, guest_id).get("ok", false)), true, "guest leave ok")
	var st: Dictionary = mgr.room_state(code)
	assert_eq(((st.get("room_state", {}) as Dictionary).get("players", []) as Array).size(), 1, "guest gone from player list")
	assert_eq(int((st.get("room_state", {}) as Dictionary).get("host_id", 0)), host_id, "host unchanged while host stays")
	var guest2: Dictionary = mgr.join_room(code, "Guest2", "g2")
	var guest2_id := int(guest2.get("player_id", 0))
	assert_eq(bool(mgr.leave_room(code, host_id).get("ok", false)), true, "host leave ok")
	var st2: Dictionary = mgr.room_state(code)
	assert_eq(int((st2.get("room_state", {}) as Dictionary).get("host_id", 0)), guest2_id, "host_id reassigned to oldest remaining player")
	assert_eq(bool(mgr.leave_room(code, 999999).get("ok", false)), false, "unknown player leave rejected")
	assert_eq(bool(mgr.leave_room(code, guest2_id).get("erased", false)), true, "last leave erases the room")
	assert_true(not mgr.list_codes().has(code), "erased code leaves the lobby")
	assert_eq(bool(mgr.room_state(code).get("ok", false)), false, "erased room has no room_state")
	return true


func test_ready_badges() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Host", "h")
	var code := str(host.get("code", ""))
	var guest: Dictionary = mgr.join_room(code, "Guest", "g")
	var guest_id := int(guest.get("player_id", 0))
	assert_eq(bool(mgr.set_ready(code, guest_id, true).get("ok", false)), true, "set_ready ok")
	var st: Dictionary = mgr.room_state(code)
	var badge := false
	var host_badge := false
	for p in ((st.get("room_state", {}) as Dictionary).get("players", []) as Array):
		var entry: Dictionary = p
		if int(entry.get("id", 0)) == guest_id and bool(entry.get("ready", false)):
			badge = true
		if int(entry.get("id", 0)) == int(host.get("player_id", 0)) and bool(entry.get("ready", false)):
			host_badge = true
	assert_true(badge, "ready badge persists in room_state")
	assert_true(not host_badge, "other players stay unready")
	assert_eq(bool(mgr.set_ready(code, guest_id, false).get("ok", false)), true, "unready ok")
	var st2: Dictionary = mgr.room_state(code)
	var cleared := true
	for p in ((st2.get("room_state", {}) as Dictionary).get("players", []) as Array):
		if int((p as Dictionary).get("id", 0)) == guest_id and bool((p as Dictionary).get("ready", true)):
			cleared = false
	assert_true(cleared, "unready clears the badge")
	assert_eq(bool(mgr.set_ready(code, 999999, true).get("ok", false)), false, "unknown player ready rejected")
	return true


func test_room_state_shape() -> bool:
	var mgr = RoomManager.new()
	var host: Dictionary = mgr.create_room("Alice", "cosmetic-red")
	var code := str(host.get("code", ""))
	var joined: Dictionary = mgr.join_room(code, "Bob", "cosmetic-blue")
	assert_eq(bool(joined.get("ok", false)), true, "join ok for shape probe")
	var st: Dictionary = mgr.room_state(code)
	assert_eq(bool(st.get("ok", false)), true, "room_state ok")
	assert_true(st.has("room_state"), "envelope carries room_state")
	var rs: Dictionary = st["room_state"]
	assert_true(rs.has("players"), "room_state has players")
	assert_true(rs.has("host_id"), "room_state has host_id")
	assert_true(rs.has("screen"), "room_state has screen")
	assert_eq(str(rs.get("code", "")), code, "room_state echoes code")
	assert_eq(str(rs.get("screen", "")), "lobby", "screen starts at lobby")
	assert_eq(int(rs.get("host_id", 0)), int(host.get("player_id", 0)), "host_id is the host player")
	var players: Array = rs["players"]
	assert_eq(players.size(), 2, "two players listed")
	for p in players:
		var entry: Dictionary = p
		assert_true(entry.has("id"), "player has id")
		assert_true(entry.has("name"), "player has name")
		assert_true(entry.has("cosmetic_hash"), "player has cosmetic_hash")
		assert_true(entry.has("color"), "player has color")
		assert_true(entry.has("ready"), "player has ready")
	assert_eq(str((players[0] as Dictionary).get("cosmetic_hash", "")), "cosmetic-red", "cosmetic_hash stored verbatim")
	assert_true(str((players[1] as Dictionary).get("color", "")) != "", "joined player gets a color")
	return true


func test_room_cap() -> bool:
	var mgr = RoomManager.new()
	assert_eq(ConfigScript.MAX_ROOMS, 64, "MAX_ROOMS is 64")
	var last: Dictionary = {}
	for i in range(ConfigScript.MAX_ROOMS + 2):
		last = mgr.create_room("H%d" % i, "c")
	assert_eq(mgr.room_count(), ConfigScript.MAX_ROOMS, "rooms capped at MAX_ROOMS")
	assert_eq(bool(last.get("ok", false)), false, "overflow create rejected")
	assert_eq(str(last.get("error", "")), "rooms_full", "overflow error names rooms_full")
	return true


func test_selftest_green() -> bool:
	var r: Array = RoomManager.run_selftest()
	assert_eq(int(r[1]), 0, "rooms selftest has no failures")
	assert_true(int(r[0]) > 0, "rooms selftest asserts something")
	assert_eq(RoomManager.SELFTEST_ROOMS, 3, "selftest proves 3 rooms")
	assert_eq(RoomManager.SELFTEST_PLAYERS, 4, "selftest proves 4 players")
	return true
