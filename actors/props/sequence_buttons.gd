extends Node3D
## Ordered sequence-button set (kit B): two to three pads pressed in order.
## Uniform kit semantics: `pressed` fires per step, `released` fires when a
## wrong step breaks the run, `activated` fires when the full order lands.
## The default order is a 3-step run, configurable down to 2 via `order`.
## All state is plain ints/bools so the self-test needs no physics frames.

signal pressed
signal released
signal activated

## Step ids in the order they must be pressed (2-3 entries).
@export var order: Array = [0, 1, 2]
## How many leading steps of `order` are currently satisfied.
var progress: int = 0
## True once the full order has landed (until reset).
var is_complete: bool = false


## Pure step resolver: correct next step advances, a step matching the run
## start restarts at 1, anything else resets to 0. Unit-testable with fake
## progress values and no nodes.
static func advance(current: int, expected: Array, got: int) -> int:
	if expected.is_empty():
		return 0
	if current >= 0 and current < expected.size() and int(expected[current]) == got:
		return current + 1
	if int(expected[0]) == got:
		return 1
	return 0


## Presses one pad: emits pressed, advances or breaks the run, and emits
## activated when the final step lands. Presses after completion are a
## no-op until reset. Wrong steps emit released when a run was in flight.
func press_step(step_id: int) -> void:
	if is_complete:
		return
	pressed.emit()
	var next := advance(progress, order, step_id)
	if next != progress + 1 and progress > 0:
		released.emit()
	progress = next
	if progress >= order.size():
		is_complete = true
		activated.emit()


## Clears the run. Emits released when a run or win was in flight.
func reset() -> void:
	var had := progress > 0 or is_complete
	progress = 0
	is_complete = false
	if had:
		released.emit()


## True once the full order has landed.
func is_done() -> bool:
	return is_complete


## How many leading steps are currently satisfied.
func get_progress() -> int:
	return progress


## Synchronous self-test: pure advance checks plus direct press_step drives
## on an instantiated scene (correct order, wrong-step reset, duplicates,
## 2-step config). Returns [passed, failed]; never awaits, no physics.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if advance(0, [0, 1, 2], 0) == 1 and advance(1, [0, 1, 2], 1) == 2 and advance(2, [0, 1, 2], 2) == 3:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: advance must step the correct order")
	if advance(1, [0, 1, 2], 2) == 0 and advance(1, [0, 1, 2], 0) == 1:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: advance must reset on wrong steps")
	var packed: PackedScene = load("res://actors/props/sequence_buttons.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("sequence selftest: sequence_buttons.tscn failed to load")
		return [passed, failed]
	var seq: Node = packed.instantiate() as Node
	if seq == null:
		failed += 1
		push_error("sequence selftest: sequence_buttons.tscn failed to instantiate")
		return [passed, failed]
	var hits := {"pressed": 0, "released": 0, "activated": 0}
	seq.connect("pressed", func(): hits["pressed"] += 1)
	seq.connect("released", func(): hits["released"] += 1)
	seq.connect("activated", func(): hits["activated"] += 1)
	seq.call("press_step", 0)
	seq.call("press_step", 1)
	seq.call("press_step", 2)
	if bool(seq.call("is_done")) and int(hits["activated"]) == 1 and int(seq.call("get_progress")) == 3:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: correct 3-step order must activate")
	seq.call("press_step", 0)
	if int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: presses after completion must be a no-op")
	seq.call("reset")
	if not bool(seq.call("is_done")) and int(seq.call("get_progress")) == 0:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: reset must clear the run")
	seq.call("press_step", 0)
	var released_before: int = int(hits["released"])
	seq.call("press_step", 2)
	if int(seq.call("get_progress")) == 0 and int(hits["released"]) == released_before + 1 and not bool(seq.call("is_done")):
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: wrong step must reset and emit released")
	seq.call("reset")
	seq.call("press_step", 0)
	seq.call("press_step", 0)
	if int(seq.call("get_progress")) == 1 and not bool(seq.call("is_done")):
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: duplicate start step must hold at progress 1")
	seq.set("order", [1, 0])
	seq.call("reset")
	var act_before: int = int(hits["activated"])
	seq.call("press_step", 1)
	seq.call("press_step", 0)
	if bool(seq.call("is_done")) and int(hits["activated"]) == act_before + 1:
		passed += 1
	else:
		failed += 1
		push_error("sequence selftest: configurable 2-step order must activate")
	seq.free()
	return [passed, failed]
