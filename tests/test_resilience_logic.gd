extends SceneTree
## Unit runner for the resilience rules (issue #12): mid-stage leave keeps
## the room alive, mid-stage joiners wait in the lobby until the next
## stage_boot, the stage restarts below 2 players, and every transition
## emits room_state + game_event into the drainable outbox.
## Pattern mirrors tests/test_rooms_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_resilience_logic.gd

const RoomManager := preload("res://server/room_manager.gd")
const FlowManager := preload("res://server/flow_manager.gd")
const ConfigScript := preload("res://autoload/Config.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_leave_keeps_room_alive",
		"test_late_join_waits_in_lobby",
		"test_below_two_restarts",
		"test_transitions_emit_both_events",
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


func _three_peer_stage() -> Dictionary:
	var rooms = RoomManager.new()
	var flow = FlowManager.new()
	var created: Dictionary = rooms.create_room("P1", "hash-p1")
	var code := str(created.get("code", ""))
	var p1 := int(created.get("player_id", 0))
	var p2 := int(rooms.join_room(code, "P2", "hash-p2").get("player_id", 0))
	var p3 := int(rooms.join_room(code, "P3", "hash-p3").get("player_id", 0))
	flow.bind_room(code, [p1, p2, p3], p1)
	flow.select_stage(code, p1, p1, "w1s1")
	var boot: Dictionary = flow.start_stage(code).get("stage_boot", {})
	rooms.set_stage_active(code, true, boot)
	return {"rooms": rooms, "flow": flow, "code": code, "p1": p1, "p2": p2, "p3": p3, "boot": boot}


func test_leave_keeps_room_alive() -> bool:
	var ctx: Dictionary = _three_peer_stage()
	var rooms = ctx["rooms"]
	var flow = ctx["flow"]
	var code := str(ctx["code"])
	var p3 := int(ctx["p3"])
	var left: Dictionary = rooms.leave_room(code, p3)
	assert_eq(bool(left.get("ok", false)), true, "mid-stage leave ok")
	assert_eq(bool(left.get("erased", true)), false, "room survives one leave")
	assert_eq(int(left.get("players_remaining", 0)), 2, "two players remain")
	var st: Dictionary = rooms.room_state(code)
	assert_eq(bool(st.get("ok", false)), true, "room_state survives the leave")
	assert_eq(((st.get("room_state", {}) as Dictionary).get("players", []) as Array).size(), 2, "room_state lists 2 survivors")
	var rem: Dictionary = flow.remove_player(code, p3)
	assert_eq(bool(rem.get("ok", false)), true, "flow remove ok")
	assert_eq(bool(rem.get("continued", false)), true, "stage continues at 2")
	assert_eq(bool(rem.get("restarted", true)), false, "no restart at 2")
	assert_eq(int(rem.get("players", 0)), 2, "flow tracks 2 survivors")
	var lone = RoomManager.new()
	var host: Dictionary = lone.create_room("Host", "h")
	var hcode := str(host.get("code", ""))
	var hid := int(host.get("player_id", 0))
	var guest_id := int(lone.join_room(hcode, "Guest", "g").get("player_id", 0))
	assert_eq(bool(lone.leave_room(hcode, hid).get("ok", false)), true, "host leave ok")
	var sth: Dictionary = lone.room_state(hcode)
	assert_eq(int((sth.get("room_state", {}) as Dictionary).get("host_id", 0)), guest_id, "host_id falls to oldest remaining")
	return true


func test_late_join_waits_in_lobby() -> bool:
	var ctx: Dictionary = _three_peer_stage()
	var rooms = ctx["rooms"]
	var flow = ctx["flow"]
	var code := str(ctx["code"])
	var p1 := int(ctx["p1"])
	var gated: Dictionary = rooms.join_room(code, "Late", "hash-late")
	assert_eq(bool(gated.get("ok", false)), false, "mid-stage join rejected")
	assert_eq(str(gated.get("error", "")), "lobby_wait", "gate error names lobby_wait")
	assert_eq(str(gated.get("code", "")), code, "gate echoes code")
	var st: Dictionary = rooms.room_state(code)
	var names: Array = []
	for p in ((st.get("room_state", {}) as Dictionary).get("players", []) as Array):
		names.append(str((p as Dictionary).get("name", "")))
	assert_true(not names.has("Late"), "gated-out joiner absent from room_state")
	assert_eq(bool(rooms.set_stage_active(code, false).get("ok", false)), true, "stage end ok")
	assert_eq(str(rooms.room_state(code).get("room_state", {}).get("screen", "")), "lobby", "screen back to lobby")
	var retry: Dictionary = rooms.join_room(code, "Late", "hash-late")
	assert_eq(bool(retry.get("ok", false)), true, "join succeeds after stage end")
	var late_id := int(retry.get("player_id", 0))
	var st2: Dictionary = rooms.room_state(code)
	var ids: Array = []
	for p in ((st2.get("room_state", {}) as Dictionary).get("players", []) as Array):
		ids.append(int((p as Dictionary).get("id", 0)))
	flow.bind_room(code, ids, int((st2.get("room_state", {}) as Dictionary).get("host_id", p1)))
	flow.select_stage(code, p1, p1, "w1s1")
	var boot2: Dictionary = flow.start_stage(code).get("stage_boot", {})
	assert_true((boot2.get("spawn_map", {}) as Dictionary).has(late_id), "next stage_boot spawn_map covers the late joiner")
	return true


func test_below_two_restarts() -> bool:
	var rooms = RoomManager.new()
	var flow = FlowManager.new()
	var created: Dictionary = rooms.create_room("P1", "h1")
	var code := str(created.get("code", ""))
	var p1 := int(created.get("player_id", 0))
	var p2 := int(rooms.join_room(code, "P2", "h2").get("player_id", 0))
	flow.bind_room(code, [p1, p2], p1)
	flow.select_stage(code, p1, p1, "w1s1")
	flow.start_stage(code)
	rooms.set_stage_active(code, true, flow._flows[flow.normalize_code(code)].get("stage_boot", {}))
	var gen_before := int((flow._flows[flow.normalize_code(code)] as Dictionary).get("gen", 0))
	flow.notify_goal(code, p1)
	var rem: Dictionary = flow.remove_player(code, p2)
	assert_eq(bool(rem.get("ok", false)), true, "second leave ok")
	assert_eq(bool(rem.get("restarted", false)), true, "drop below 2 restarts")
	assert_eq(bool(rem.get("continued", true)), false, "restart is not a continue")
	assert_eq(int(rem.get("players", 0)), 1, "one survivor tracked")
	assert_true(rem.has("stage_boot"), "restart carries a fresh stage_boot")
	assert_eq(str((rem.get("stage_boot", {}) as Dictionary).get("stage_id", "")), "w1s1", "restart re-boots the same stage")
	assert_eq(((rem.get("stage_boot", {}) as Dictionary).get("spawn_map", {}) as Dictionary).size(), 1, "fresh boot covers the survivor")
	assert_eq(flow.goal_count(code), 0, "goals cleared on restart")
	assert_true(not flow.goal_all(code), "goal_all cleared on restart")
	var gen_after := int((flow._flows[flow.normalize_code(code)] as Dictionary).get("gen", 0))
	assert_eq(gen_after, gen_before + 1, "generation bumped on restart")
	assert_eq(bool(flow.remove_player(code, 999999).get("ok", false)), false, "unknown player rejected")
	assert_eq(str(flow.remove_player(code, 999999).get("error", "")), "unknown_player", "unknown player error named")
	assert_eq(str(flow.remove_player("ZZZZ", p1).get("error", "")), "unknown_code", "unknown code error named")
	return true


func test_transitions_emit_both_events() -> bool:
	var rooms = RoomManager.new()
	rooms.drain_events()
	var created: Dictionary = rooms.create_room("P1", "h1")
	var code := str(created.get("code", ""))
	var ev: Array = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "create emits room_state")
	assert_true(_has_msg(ev, "game_event"), "create emits game_event")
	rooms.join_room(code, "P2", "h2")
	ev = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "join emits room_state")
	assert_true(_has_msg(ev, "game_event"), "join emits game_event")
	rooms.set_ready(code, int(created.get("player_id", 0)), true)
	ev = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "ready emits room_state")
	assert_true(_has_msg(ev, "game_event"), "ready emits game_event")
	var flow = FlowManager.new()
	flow.bind_room(code, [int(created.get("player_id", 0))], int(created.get("player_id", 0)))
	flow.select_stage(code, int(created.get("player_id", 0)), int(created.get("player_id", 0)), "w1s1")
	rooms.set_stage_active(code, true, flow.start_stage(code).get("stage_boot", {}))
	ev = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "stage start emits room_state")
	assert_true(_has_msg(ev, "game_event"), "stage start emits game_event")
	rooms.join_room(code, "Late", "h-late")
	ev = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "lobby_wait emits room_state")
	assert_true(_has_msg(ev, "game_event"), "lobby_wait emits game_event")
	rooms.leave_room(code, int(created.get("player_id", 0)))
	ev = rooms.drain_events()
	assert_true(_has_msg(ev, "room_state"), "leave emits room_state")
	assert_true(_has_msg(ev, "game_event"), "leave emits game_event")
	assert_eq(rooms.drain_events().size(), 0, "drain clears the outbox")
	return true


func test_selftest_green() -> bool:
	var rr: Array = RoomManager.run_selftest()
	assert_eq(int(rr[1]), 0, "rooms selftest still green")
	var fr: Array = FlowManager.run_selftest()
	assert_eq(int(fr[1]), 0, "flow selftest still green")
	assert_eq(ConfigScript.MIN_ROOM_PLAYERS, 2, "below-2 threshold is 2")
	return true


func _has_msg(events: Array, msg: String) -> bool:
	for e in events:
		if str((e as Dictionary).get("msg", "")) == msg:
			return true
	return false
