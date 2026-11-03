extends Area3D
## Boost pad prop (kit B): launches bodies that carry `apply_boost`.
## Uniform kit semantics: `pressed` fires when a body enters, `released`
## when it leaves, `activated` when the boost verb fires (on every enter).
## The body call is guarded by has_method so unknown bodies only trigger
## the signals and never error. Headless-safe: no awaits, no physics.

signal pressed
signal released
signal activated

## Impulse handed to bodies that expose `apply_boost(force)`.
@export var boost_force: Vector3 = Vector3(0.0, 12.0, 0.0)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	activate(body)


func _on_body_exited(_body: Node) -> void:
	deactivate()


## Boosts one body: always emits pressed + activated, and only calls into
## bodies that actually expose `apply_boost`.
func activate(body: Node) -> void:
	pressed.emit()
	if body != null and body.has_method("apply_boost"):
		body.call("apply_boost", boost_force)
	activated.emit()


## Ends the touch: emits released.
func deactivate() -> void:
	released.emit()


## The impulse handed to boosted bodies.
func get_boost() -> Vector3:
	return boost_force


## Probe body used by the self-test: records guarded boost calls.
class BoostProbe extends Node:
	var calls: int = 0
	var last_force: Vector3 = Vector3.ZERO

	func apply_boost(force: Vector3) -> void:
		calls += 1
		last_force = force


## Synchronous self-test: guarded boost call, unknown-body safety, and
## signal wiring on an instantiated scene. Returns [passed, failed].
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var packed: PackedScene = load("res://actors/props/boost.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("boost selftest: boost.tscn failed to load")
		return [passed, failed]
	var pad: Node = packed.instantiate() as Node
	if pad == null:
		failed += 1
		push_error("boost selftest: boost.tscn failed to instantiate")
		return [passed, failed]
	var hits := {"pressed": 0, "released": 0, "activated": 0}
	pad.connect("pressed", func(): hits["pressed"] += 1)
	pad.connect("released", func(): hits["released"] += 1)
	pad.connect("activated", func(): hits["activated"] += 1)
	var want: Vector3 = pad.call("get_boost")
	if want.y > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: boost impulse must lift upward")
	var probe := BoostProbe.new()
	pad.call("activate", probe)
	if probe.calls == 1 and probe.last_force == want and int(hits["pressed"]) == 1 and int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: guarded body must be boosted with pressed+activated")
	var plain := Node.new()
	var pressed_before: int = int(hits["pressed"])
	var activated_before: int = int(hits["activated"])
	pad.call("activate", plain)
	if int(hits["pressed"]) == pressed_before + 1 and int(hits["activated"]) == activated_before + 1:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: unknown body must still trigger pressed+activated")
	plain.free()
	pad.call("deactivate")
	if int(hits["released"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: exit must emit released")
	var probe2 := BoostProbe.new()
	pad.call("_on_body_entered", probe2)
	if probe2.calls == 1 and int(hits["pressed"]) == 3:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: body enter hook must boost guarded bodies")
	pad.call("_on_body_exited", probe2)
	if int(hits["released"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("boost selftest: body exit hook must emit released")
	probe.free()
	probe2.free()
	pad.free()
	return [passed, failed]
