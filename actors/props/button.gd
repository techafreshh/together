extends Area3D
## Hold-button prop (kit B): a stand-on button that latches while pressed.
## Uniform kit semantics: `pressed` fires when engagement starts, `released`
## when it ends, `activated` when the cooperation verb fires (here: on press).
## All body hooks are guarded so static bodies never error; the press state
## is a plain bool so the headless self-test needs no physics frames.

signal pressed
signal released
signal activated

## True while the button is held down.
var is_pressed: bool = false
## How many distinct press engagements have started.
var press_count: int = 0


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(_body: Node) -> void:
	press()


func _on_body_exited(_body: Node) -> void:
	release()


## Starts a hold: latches, counts, and fires pressed + activated.
## Duplicate presses while held are a no-op (no double signals).
func press() -> void:
	if is_pressed:
		return
	is_pressed = true
	press_count += 1
	pressed.emit()
	activated.emit()


## Ends a hold: unlatches and fires released. No-op when already up.
func release() -> void:
	if not is_pressed:
		return
	is_pressed = false
	released.emit()


## True while the button is held down.
func is_down() -> bool:
	return is_pressed


## Synchronous self-test: drives press/release paths directly on an
## instantiated scene, asserts signal counts, latch state, and duplicate
## handling. Returns [passed, failed]; never awaits, needs no physics.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var packed: PackedScene = load("res://actors/props/button.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("button selftest: button.tscn failed to load")
		return [passed, failed]
	var btn: Node = packed.instantiate() as Node
	if btn == null:
		failed += 1
		push_error("button selftest: button.tscn failed to instantiate")
		return [passed, failed]
	var hits := {"pressed": 0, "released": 0, "activated": 0}
	btn.connect("pressed", func(): hits["pressed"] += 1)
	btn.connect("released", func(): hits["released"] += 1)
	btn.connect("activated", func(): hits["activated"] += 1)
	if not bool(btn.call("is_down")) and int(btn.get("press_count")) == 0:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: fresh button must be up with count 0")
	btn.call("press")
	if bool(btn.call("is_down")) and int(hits["pressed"]) == 1 and int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: press must latch and emit pressed+activated")
	btn.call("press")
	if int(hits["pressed"]) == 1 and int(hits["activated"]) == 1 and int(btn.get("press_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: duplicate press must be a no-op")
	btn.call("release")
	if not bool(btn.call("is_down")) and int(hits["released"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: release must unlatch and emit released")
	btn.call("release")
	if int(hits["released"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: duplicate release must be a no-op")
	btn.call("press")
	btn.call("release")
	if int(hits["pressed"]) == 2 and int(hits["activated"]) == 2 and int(hits["released"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: button must be reusable after release")
	var probe := Node.new()
	btn.call("_on_body_entered", probe)
	if bool(btn.call("is_down")) and int(hits["pressed"]) == 3:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: body enter must press the button")
	btn.call("_on_body_exited", probe)
	if not bool(btn.call("is_down")) and int(hits["released"]) == 3:
		passed += 1
	else:
		failed += 1
		push_error("button selftest: body exit must release the button")
	probe.free()
	btn.free()
	return [passed, failed]
