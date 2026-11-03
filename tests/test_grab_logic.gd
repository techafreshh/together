extends SceneTree
## Unit runner for the grab/carry/throw holder state (issue #7).
## Pattern mirrors tests/test_flop_logic.gd: SceneTree runner with own
## counters, assert helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_grab_logic.gd

const Tuning := preload("res://actors/player/tuning.gd")
const Grabber := preload("res://actors/player/grabber.gd")
const Controller := preload("res://actors/player/controller.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_tuning_surface",
		"test_range_predicate",
		"test_grab_accepts_any_state",
		"test_double_grab_denied",
		"test_release_clears",
		"test_throw_impulse",
		"test_carry_slow",
		"test_shared_selftest",
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


## Fresh holder triple: grabber node plus carrier and body dummies.
func _holder_at(dist: float) -> Array:
	var grabber: Node = Grabber.new()
	var carrier := CharacterBody3D.new()
	var body := CharacterBody3D.new()
	carrier.position = Vector3.ZERO
	body.position = Vector3(dist, 0.0, 0.0)
	grabber.set("carrier", carrier)
	return [grabber, carrier, body]


func _free_all(parts: Array) -> void:
	for n: Node in parts:
		n.free()


## Tuning carries the three grab feel values.
func test_tuning_surface() -> bool:
	assert_eq(Tuning.carry_speed_factor, 0.55, "carry slow factor is 0.55")
	assert_eq(Tuning.throw_impulse, 9.0, "throw impulse is 9.0")
	assert_eq(Tuning.grab_range, 2.5, "grab range is 2.5")
	return true


## Range predicate: inside grabs, outside denies, null denies.
func test_range_predicate() -> bool:
	var parts := _holder_at(1.0)
	var grabber: Node = parts[0]
	var carrier: CharacterBody3D = parts[1]
	var near: CharacterBody3D = parts[2]
	assert_true(Grabber.is_in_grab_range(carrier, near), "1 m is in grab range")
	assert_true(bool(grabber.call("try_grab", near)), "in-range grab succeeds")
	assert_true(bool(grabber.call("is_carrying")), "grabber reports carrying")
	_free_all(parts)
	var far_parts := _holder_at(Tuning.grab_range + 5.0)
	var far_grabber: Node = far_parts[0]
	var far_carrier: CharacterBody3D = far_parts[1]
	var far_body: CharacterBody3D = far_parts[2]
	assert_false(Grabber.is_in_grab_range(far_carrier, far_body), "range + 5 m is out of range")
	assert_false(bool(far_grabber.call("try_grab", far_body)), "out-of-range grab denied")
	assert_false(bool(far_grabber.call("try_grab", null)), "null grab denied")
	_free_all(far_parts)
	return true


## Both alive and ragdolled mannequins are grabbable (no state gate).
func test_grab_accepts_any_state() -> bool:
	var parts := _holder_at(1.0)
	var grabber: Node = parts[0]
	var alive := Controller.new()
	alive.position = Vector3(1.0, 0.0, 0.0)
	assert_true(alive.is_alive(), "fresh mannequin is alive")
	assert_true(bool(grabber.call("try_grab", alive)), "alive mannequin grabbed")
	grabber.call("release")
	var flopped := Controller.new()
	flopped.position = Vector3(1.0, 0.0, 0.0)
	flopped.kill()
	assert_true(flopped.is_flopped, "killed mannequin is flopped")
	assert_true(bool(grabber.call("try_grab", flopped)), "flopped mannequin grabbed")
	_free_all(parts)
	alive.free()
	flopped.free()
	return true


## Occupied slot and self-grab are denied.
func test_double_grab_denied() -> bool:
	var parts := _holder_at(1.0)
	var grabber: Node = parts[0]
	var carrier: CharacterBody3D = parts[1]
	var first: CharacterBody3D = parts[2]
	var second := CharacterBody3D.new()
	second.position = Vector3(1.0, 0.0, 0.0)
	assert_true(bool(grabber.call("try_grab", first)), "first grab succeeds")
	assert_false(bool(grabber.call("try_grab", second)), "second grab while carrying denied")
	assert_false(bool(grabber.call("try_grab", carrier)), "self grab denied")
	_free_all(parts)
	second.free()
	return true


## Release drops the body at the carrier's feet and frees the slot.
func test_release_clears() -> bool:
	var parts := _holder_at(1.0)
	var grabber: Node = parts[0]
	var carrier: CharacterBody3D = parts[1]
	var body: CharacterBody3D = parts[2]
	carrier.position = Vector3(5.0, 0.0, 3.0)
	body.position = Vector3(6.0, 0.0, 3.0)
	body.velocity = Vector3(2.0, 3.0, 4.0)
	assert_true(bool(grabber.call("try_grab", body)), "grab before release succeeds")
	grabber.call("release")
	assert_false(bool(grabber.call("is_carrying")), "release clears the slot")
	assert_eq(body.position, carrier.position, "released body rests at carrier feet")
	assert_eq(body.velocity, Vector3.ZERO, "released body velocity zeroed")
	assert_true(bool(grabber.call("try_grab", body)), "re-grab after release succeeds")
	_free_all(parts)
	return true


## Throw applies the fixed impulse and clears the slot.
func test_throw_impulse() -> bool:
	var parts := _holder_at(1.0)
	var grabber: Node = parts[0]
	var body: CharacterBody3D = parts[2]
	assert_true(bool(grabber.call("try_grab", body)), "grab before throw succeeds")
	grabber.call("throw_carried", Vector3(0.0, 0.0, -1.0))
	assert_false(bool(grabber.call("is_carrying")), "throw clears the slot")
	var vel: Vector3 = body.velocity
	assert_true(vel.length() >= Tuning.throw_impulse, "thrown body carries at least the throw impulse")
	assert_true(vel.y > 0.0, "throw has an upward component")
	grabber.call("throw_carried", Vector3(0.0, 0.0, -1.0))
	assert_false(bool(grabber.call("is_carrying")), "empty throw is a no-op")
	_free_all(parts)
	return true


## Carried speed is strictly below base speed but still positive.
func test_carry_slow() -> bool:
	var slowed := Grabber.carried_move_speed(Tuning.move_speed)
	assert_eq(slowed, Tuning.move_speed * Tuning.carry_speed_factor, "carried speed scales by the factor")
	assert_true(slowed < Tuning.move_speed, "carried speed below base speed")
	assert_true(slowed > 0.0, "carried speed stays positive")
	return true


## Shared self-test is green and the holder API is exposed.
func test_shared_selftest() -> bool:
	var grabber: Node = Grabber.new()
	assert_true(grabber.has_method("try_grab"), "grabber exposes try_grab")
	assert_true(grabber.has_method("release"), "grabber exposes release")
	assert_true(grabber.has_method("throw_carried"), "grabber exposes throw_carried")
	assert_true(grabber.has_method("is_carrying"), "grabber exposes is_carrying")
	grabber.free()
	var r: Array = Grabber.run_selftest()
	assert_eq(int(r[1]), 0, "grabber selftest has no failures")
	return true
