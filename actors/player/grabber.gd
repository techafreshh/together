extends Node
## Offline grab/carry/throw holder state (issue #7 defining co-op verb).
## Discrete who-holds-whom state machine only: try_grab() takes an
## in-range mannequin (alive or flopped, no state gate), release() drops
## the body at the carrier's feet, throw_carried() tosses it with a fixed
## impulse. No networking: server arbitration arrives in a later lap.
## All math reads Tuning consts and is synchronous, so the headless
## `--selftest grab` probe is frame-free and CI-stable.

const Tuning := preload("res://actors/player/tuning.gd")

## Emitted when a body is grabbed / released / thrown (UI hooks later).
signal grabbed(body: Node3D)
signal released(body: Node3D)
signal thrown(body: Node3D)

## The player this Grabber belongs to (set by the owner on ready).
var carrier: Node3D
## The currently held body, or null when the slot is free.
var carried: Node3D


## True when a body is currently held.
func is_carrying() -> bool:
	return carried != null


## The held body, or null when the slot is free.
func carried_body() -> Node3D:
	return carried


## Try to grab a mannequin. Rejects null/self/occupied-slot/out-of-range;
## accepts alive and ragdolled bodies alike (range + free slot only).
func try_grab(candidate: Node3D) -> bool:
	if candidate == null:
		return false
	if carried != null:
		return false
	var holder := _holder()
	if holder == null:
		return false
	if candidate == holder:
		return false
	if not is_in_grab_range(holder, candidate):
		return false
	carried = candidate
	grabbed.emit(carried)
	return true


## Drop the held body at the carrier's feet with zeroed velocity.
func release() -> void:
	if carried == null:
		return
	var body := carried
	carried = null
	var holder := _holder()
	if holder != null:
		_write_pos(body, _read_pos(holder))
	if "velocity" in body:
		body.set("velocity", Vector3.ZERO)
	released.emit(body)


## Throw the held body with the fixed Tuning.throw_impulse toss
## (carrier forward plus half-up). Clears the slot.
func throw_carried(direction: Vector3) -> void:
	if carried == null:
		return
	var body := carried
	carried = null
	var dir := direction
	if dir.length() < 0.001:
		dir = Vector3(0.0, 0.0, -1.0)
	if "velocity" in body:
		body.set("velocity", throw_velocity(dir))
	thrown.emit(body)


## Fixed toss velocity for a throw direction: forward impulse plus half-up.
static func throw_velocity(direction: Vector3) -> Vector3:
	var dir := direction
	if dir.length() < 0.001:
		dir = Vector3(0.0, 0.0, -1.0)
	return dir.normalized() * Tuning.throw_impulse + Vector3.UP * Tuning.throw_impulse * 0.5


## Tree-safe read: global when in the scene tree, local when headless.
static func _read_pos(body: Node3D) -> Vector3:
	if body.is_inside_tree():
		return body.global_position
	return body.position


## Tree-safe write: global when in the scene tree, local when headless.
static func _write_pos(body: Node3D, pos: Vector3) -> void:
	if body.is_inside_tree():
		body.global_position = pos
	else:
		body.position = pos


## True when two bodies are within Tuning.grab_range of each other.
static func is_in_grab_range(from_body: Node3D, to_body: Node3D) -> bool:
	if from_body == null or to_body == null:
		return false
	return _read_pos(from_body).distance_to(_read_pos(to_body)) <= Tuning.grab_range


## Carrier run speed while holding a body (strictly below base speed).
static func carried_move_speed(base_speed: float) -> float:
	return base_speed * Tuning.carry_speed_factor


## Owner carrier: the explicit var, else the parent Node3D (scene wiring).
func _holder() -> Node3D:
	if carrier != null:
		return carrier
	return get_parent() as Node3D


## Synchronous self-test: CharacterBody3D dummies through
## grab -> slowed-carry -> throw. Returns [passed, failed]; never awaits,
## never touches the scene tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var script: GDScript = load("res://actors/player/grabber.gd") as GDScript
	if script == null:
		failed += 1
		push_error("grab selftest: grabber.gd failed to load")
		return [passed, failed]
	if Tuning.carry_speed_factor < 1.0 and Tuning.carry_speed_factor > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: carry_speed_factor must be in (0, 1)")
	if Tuning.throw_impulse > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: throw_impulse must be positive")
	if Tuning.grab_range > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: grab_range must be positive")
	var grabber: Node = script.new()
	var holder := CharacterBody3D.new()
	var body := CharacterBody3D.new()
	holder.position = Vector3.ZERO
	body.position = Vector3(1.0, 0.0, 0.0)
	grabber.set("carrier", holder)
	if is_in_grab_range(holder, body):
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: body 1 m away must be in grab range")
	var grabbed_ok: bool = grabber.call("try_grab", body)
	if grabbed_ok and bool(grabber.call("is_carrying")):
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: in-range grab must succeed")
	var slowed := carried_move_speed(Tuning.move_speed)
	if slowed < Tuning.move_speed and slowed > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: carried speed must be slowed but positive")
	grabber.call("throw_carried", Vector3(0.0, 0.0, -1.0))
	if not bool(grabber.call("is_carrying")):
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: throw must clear the slot")
	var vel: Vector3 = body.get("velocity") as Vector3
	if vel.length() >= Tuning.throw_impulse:
		passed += 1
	else:
		failed += 1
		push_error("grab selftest: thrown body must carry at least the throw impulse")
	grabber.free()
	holder.free()
	body.free()
	return [passed, failed]
