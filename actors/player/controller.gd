extends CharacterBody3D
## Tight third-person platformer controller: camera-relative run, jump
## with coyote time + jump buffering, variable jump height, air control.
## All feel values come from Tuning; movement integrates in _physics_process
## with fixed-dt timers so the arc is identical on every machine.

const Tuning := preload("res://actors/player/tuning.gd")

## NodePath to the camera yaw pivot the run direction is relative to.
## When unset, world axes are used (keeps headless checks deterministic).
@export var camera_yaw_path: NodePath

var coyote_timer: float = 0.0
var buffer_timer: float = 0.0


func _physics_process(delta: float) -> void:
	var on_floor := is_on_floor()
	if on_floor:
		coyote_timer = float(Tuning.coyote_ms) / 1000.0
	if Input.is_action_just_pressed("jump"):
		buffer_timer = float(Tuning.buffer_ms) / 1000.0
	coyote_timer -= delta
	buffer_timer -= delta

	# A jump is allowed if we pressed recently AND were grounded recently.
	# Consume both so one press can never double-jump.
	if buffer_timer > 0.0 and coyote_timer > 0.0:
		velocity.y = Tuning.jump_velocity
		buffer_timer = 0.0
		coyote_timer = 0.0

	# Variable jump height: releasing jump while still rising cuts the arc.
	if Input.is_action_just_released("jump") and velocity.y > 0.0:
		velocity.y *= Tuning.jump_cut

	# Asymmetric gravity: snappier fall than rise, clamped to terminal speed.
	var grav: float = Tuning.gravity
	if velocity.y < 0.0:
		grav = Tuning.gravity * Tuning.fall_multiplier
	velocity.y = maxf(velocity.y - grav * delta, -Tuning.max_fall_speed)

	# Camera-relative run: full response on ground, scaled by air_control.
	var input_dir := Vector2(
		Input.get_axis("move_left", "move_right"),
		Input.get_axis("move_forward", "move_back")
	)
	var wish := Vector3.ZERO
	if input_dir.length() > 0.001:
		var yaw_basis := Basis()
		var yaw_node := get_node_or_null(camera_yaw_path) as Node3D
		if yaw_node != null:
			yaw_basis = Basis(Vector3.UP, yaw_node.global_rotation.y)
		var forward := -yaw_basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := yaw_basis.x
		right.y = 0.0
		right = right.normalized()
		wish = right * input_dir.x - forward * input_dir.y
		if wish.length() > 1.0:
			wish = wish.normalized()
	var response: float = Tuning.ground_response
	if not on_floor:
		response *= Tuning.air_control
	var t := 1.0 - exp(-response * delta)
	velocity.x = lerpf(velocity.x, wish.x * Tuning.move_speed, t)
	velocity.z = lerpf(velocity.z, wish.z * Tuning.move_speed, t)
	move_and_slide()


## --- Pure-logic helpers (no nodes): exercised by the headless self-test. ---


static func jump_granted(coyote: float, buffered: float) -> bool:
	return coyote > 0.0 and buffered > 0.0


static func gravity_for(vy: float) -> float:
	if vy < 0.0:
		return Tuning.gravity * Tuning.fall_multiplier
	return Tuning.gravity


## Fixed-dt (60 Hz) stepped integration of one full jump arc; returns the
## airborne time in ms. Mirrors the gravity integration in _physics_process.
static func simulate_jump_arc_ms() -> int:
	var dt := 1.0 / 60.0
	var y := 0.0
	var vy: float = Tuning.jump_velocity
	var steps := 0
	while steps < 600:
		vy -= gravity_for(vy) * dt
		y += vy * dt
		steps += 1
		if y <= 0.0 and vy < 0.0:
			break
	return int(steps * 1000.0 / 60.0)


## Synchronous self-test: stepped arc + coyote/buffer resolver checks.
## Returns [passed, failed]; never awaits, never touches the scene tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var arc_ms := simulate_jump_arc_ms()
	if arc_ms >= 200 and arc_ms <= 2000:
		passed += 1
	else:
		failed += 1
		push_error("controller selftest: jump arc %d ms out of range" % arc_ms)
	if jump_granted(0.05, 0.05):
		passed += 1
	else:
		failed += 1
		push_error("controller selftest: fresh coyote+buffer must grant jump")
	if not jump_granted(0.0, 0.05):
		passed += 1
	else:
		failed += 1
		push_error("controller selftest: expired coyote must deny jump")
	if not jump_granted(0.05, 0.0):
		passed += 1
	else:
		failed += 1
		push_error("controller selftest: missing buffered press must deny jump")
	if Tuning.jump_arc_ms() == int(2.0 * Tuning.jump_velocity / Tuning.gravity * 1000.0):
		passed += 1
	else:
		failed += 1
		push_error("controller selftest: Tuning.jump_arc_ms() mismatch")
	return [passed, failed]
