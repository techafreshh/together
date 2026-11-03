extends Node3D
## Counterweighted see-saw prop (kit B): two sides pressed by players.
## Uniform kit semantics: `pressed` fires per side press, `released` fires
## per side release, `activated` fires when both sides are down at once
## (the balanced cooperation verb). The tilt resolver is a pure static so
## the timing-free logic is unit-testable with fake side states.

signal pressed
signal released
signal activated

## Left side held down.
var left_down: bool = false
## Right side held down.
var right_down: bool = false
## Current tilt: -1 left, 0 balanced/level, +1 right.
var tilt: int = 0
## True while both sides are held (the balanced win state).
var balanced: bool = false


## Pure tilt resolver: single side tips that way, both or neither is level.
static func tilt_for(left: bool, right: bool) -> int:
	if left and right:
		return 0
	if left:
		return -1
	if right:
		return 1
	return 0


## Holds the left side. Duplicate presses are a no-op.
func press_left() -> void:
	if left_down:
		return
	left_down = true
	pressed.emit()
	_refresh()


## Holds the right side. Duplicate presses are a no-op.
func press_right() -> void:
	if right_down:
		return
	right_down = true
	pressed.emit()
	_refresh()


## Releases the left side. No-op when already up.
func release_left() -> void:
	if not left_down:
		return
	left_down = false
	released.emit()
	_refresh()


## Releases the right side. No-op when already up.
func release_right() -> void:
	if not right_down:
		return
	right_down = false
	released.emit()
	_refresh()


## Clears both sides. Emits released when anything was held.
func reset() -> void:
	var had := left_down or right_down
	left_down = false
	right_down = false
	tilt = 0
	balanced = false
	_update_plank()
	if had:
		released.emit()


## True while both sides are held down.
func is_balanced() -> bool:
	return balanced


## Current tilt: -1 left, 0 level, +1 right.
func get_tilt() -> int:
	return tilt


func _refresh() -> void:
	tilt = tilt_for(left_down, right_down)
	var was := balanced
	balanced = left_down and right_down
	_update_plank()
	if balanced and not was:
		activated.emit()


func _update_plank() -> void:
	var plank := get_node_or_null("Plank")
	if plank != null and plank is Node3D:
		if balanced:
			(plank as Node3D).rotation.z = 0.0
		else:
			(plank as Node3D).rotation.z = float(tilt) * 0.18


## Synchronous self-test: pure tilt checks plus single-side vs balanced
## drives on an instantiated scene. Returns [passed, failed]; no physics.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if tilt_for(true, false) == -1 and tilt_for(false, true) == 1:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: single side must tip that way")
	if tilt_for(true, true) == 0 and tilt_for(false, false) == 0:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: both/neither sides must be level")
	var packed: PackedScene = load("res://actors/props/seesaw.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("seesaw selftest: seesaw.tscn failed to load")
		return [passed, failed]
	var saw: Node = packed.instantiate() as Node
	if saw == null:
		failed += 1
		push_error("seesaw selftest: seesaw.tscn failed to instantiate")
		return [passed, failed]
	var hits := {"pressed": 0, "released": 0, "activated": 0}
	saw.connect("pressed", func(): hits["pressed"] += 1)
	saw.connect("released", func(): hits["released"] += 1)
	saw.connect("activated", func(): hits["activated"] += 1)
	saw.call("press_left")
	if int(saw.call("get_tilt")) == -1 and not bool(saw.call("is_balanced")) and int(hits["activated"]) == 0:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: left-only press must tip left without activation")
	saw.call("press_right")
	if int(saw.call("get_tilt")) == 0 and bool(saw.call("is_balanced")) and int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: both sides down must balance and activate")
	saw.call("press_left")
	if int(hits["pressed"]) == 2 and int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: duplicate side press must be a no-op")
	saw.call("release_left")
	if int(saw.call("get_tilt")) == 1 and not bool(saw.call("is_balanced")) and int(hits["released"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: releasing left must tip right")
	saw.call("reset")
	if int(saw.call("get_tilt")) == 0 and not bool(saw.call("is_balanced")) and int(hits["released"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: reset must level the plank")
	saw.call("press_right")
	saw.call("press_left")
	if bool(saw.call("is_balanced")) and int(hits["activated"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("seesaw selftest: right-then-left must also balance")
	saw.free()
	return [passed, failed]
