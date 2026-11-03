extends SceneTree
## Unit runner for the WebSocket net stack (issue #9): authoritative sim,
## clamps, join cooldown, tick stream, and the shared self-test.
## Pattern mirrors tests/test_serve_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_net_logic.gd

const NetServer := preload("res://server/net_server.gd")
const Net := preload("res://autoload/Net.gd")
const Tuning := preload("res://actors/player/tuning.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_input_snapshot_roundtrip",
		"test_speed_clamp",
		"test_teleport_clamp",
		"test_join_cooldown",
		"test_tick_monotonic",
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


func test_input_snapshot_roundtrip() -> bool:
	var state := NetServer.make_input_state(7, Vector2(1.0, 0.0), true)
	assert_eq(int(state.get("tick", 0)), 7, "input tick preserved")
	assert_eq(state.get("move", []), [1.0, 0.0], "input move preserved")
	assert_eq(bool(state.get("jump", false)), true, "input jump preserved")
	var states := {
		1: {"p": Vector3(1.0, 0.0, 2.0), "v": Vector3.ZERO},
		2: {"p": Vector3(-3.0, 0.5, 0.0), "v": Vector3.ZERO},
	}
	var snap := NetServer.make_snapshot(7, states)
	assert_eq(int(snap.get("tick", 0)), 7, "snapshot tick preserved")
	var peers: Dictionary = snap.get("peers", {})
	assert_eq(peers.size(), 2, "snapshot carries both peers")
	assert_eq((peers[1] as Dictionary).get("p", []), [1.0, 0.0, 2.0], "peer position round-trips")
	return true


func test_speed_clamp() -> bool:
	var max_h: float = Tuning.move_speed * NetServer.SPEED_FACTOR
	var fast := NetServer.clamp_velocity(Vector3(100.0, 0.0, 0.0))
	assert_true(Vector2(fast.x, fast.z).length() <= max_h + 0.001, "100 m/s input capped to move_speed * 1.25")
	var fall := NetServer.clamp_velocity(Vector3(0.0, -100.0, 0.0))
	assert_eq(fall.y, -Tuning.max_fall_speed, "fall speed capped to -max_fall_speed")
	var rise := NetServer.clamp_velocity(Vector3(0.0, 100.0, 0.0))
	assert_eq(rise.y, Tuning.max_fall_speed, "rise speed capped to max_fall_speed")
	var sane := NetServer.clamp_velocity(Vector3(3.0, 0.0, 4.0))
	assert_eq(sane, Vector3(3.0, 0.0, 4.0), "sane velocity untouched")
	return true


func test_teleport_clamp() -> bool:
	var snapped: Vector3 = NetServer.clamp_teleport(Vector3.ZERO, Vector3(50.0, 0.0, 0.0))
	assert_true(snapped.distance_to(Vector3.ZERO) <= NetServer.TELEPORT_CLAMP_M + 0.001, "50 m jump snapped to <= 5.0 m")
	var small := Vector3(1.0, 0.0, 1.0)
	assert_eq(NetServer.clamp_teleport(Vector3.ZERO, small), small, "small step untouched")
	return true


func test_join_cooldown() -> bool:
	assert_true(NetServer.is_join_allowed(-1, 0), "first join allowed")
	assert_true(not NetServer.is_join_allowed(1000, 1500), "rejoin at 500 ms rejected")
	assert_true(not NetServer.is_join_allowed(0, 1999), "rejoin at 1999 ms rejected")
	assert_true(NetServer.is_join_allowed(0, 2000), "rejoin at 2000 ms allowed")
	assert_true(NetServer.is_join_allowed(1000, 5000), "later rejoin allowed")
	return true


func test_tick_monotonic() -> bool:
	var states := {
		1: {"p": Vector3.ZERO, "v": Vector3.ZERO},
		2: {"p": Vector3.ZERO, "v": Vector3.ZERO},
	}
	var dt := 1.0 / float(NetServer.TICK_HZ)
	var ticks_ok := true
	var last_snap := {}
	for t in range(1, NetServer.SELFTEST_TICKS + 1):
		var inputs := {
			1: NetServer.make_input_state(t, Vector2(1.0, 0.0), false),
			2: NetServer.make_input_state(t, Vector2(0.0, 1.0), false),
		}
		NetServer.simulate_step(states, inputs, dt)
		last_snap = NetServer.make_snapshot(t, states)
		if int(last_snap.get("tick", 0)) != t:
			ticks_ok = false
		if (last_snap.get("peers", {}) as Dictionary).size() != 2:
			ticks_ok = false
	assert_true(ticks_ok, "60 ticks advance snapshot tick 1..60 for exactly 2 peers")
	assert_eq(int(last_snap.get("tick", 0)), NetServer.SELFTEST_TICKS, "final snapshot tick is 60")
	var p1: Vector3 = (states[1] as Dictionary).get("p", Vector3.ZERO)
	assert_true(p1.x > 0.0, "peer 1 advanced along +x input")
	return true


func test_selftest_green() -> bool:
	var r: Array = NetServer.run_selftest()
	assert_eq(int(r[1]), 0, "net selftest has no failures")
	assert_true(int(r[0]) > 0, "net selftest asserts something")
	assert_eq(NetServer.SELFTEST_TICKS, 60, "selftest simulates 60 ticks")
	assert_eq(NetServer.SELFTEST_PEERS, 2, "selftest drives 2 peers")
	var predicted := Net.predict_position(Vector3.ZERO, Vector2(1.0, 0.0), 1.0)
	assert_eq(predicted, Vector3(Tuning.move_speed, 0.0, 0.0), "prediction matches move_speed rule")
	var mid := Net.interp_position(Vector3.ZERO, Vector3(10.0, 0.0, 0.0), 0.5)
	assert_eq(mid, Vector3(5.0, 0.0, 0.0), "interpolation blends snapshots")
	assert_eq(Net.reconcile_position(Vector3(100.0, 0.0, 0.0), Vector3.ZERO), Vector3.ZERO, "far error snaps to authority")
	return true
