extends CharacterBody3D
## Tight third-person platformer controller: camera-relative run, jump
## with coyote time + jump buffering, variable jump height, air control.
## All feel values come from Tuning; movement integrates in _physics_process
## with fixed-dt timers so the arc is identical on every machine.
## Issue #4: lethal fall / kill plane / hard impact triggers a scripted
## flop (Ragdoll child) plus the flop-SFX hook, then auto-respawns at the
## last checkpoint with control restored within Tuning.respawn_delay_ms.

const Tuning := preload("res://actors/player/tuning.gd")
const Ragdoll := preload("res://actors/player/ragdoll.gd")

## NodePath to the camera yaw pivot the run direction is relative to.
## When unset, world axes are used (keeps headless checks deterministic).
@export var camera_yaw_path: NodePath

var coyote_timer: float = 0.0
var buffer_timer: float = 0.0
## Last safe ground position; the spawn point until set_checkpoint() runs.
var checkpoint_position: Vector3
var is_flopped: bool = false
var flop_time_left: float = 0.0
var _was_on_floor: bool = false
var _pre_slide_vy: float = 0.0
var _checkpoint_ready: bool = false


func _ready() -> void:
	checkpoint_position = global_position
	_checkpoint_ready = true
	_was_on_floor = is_on_floor()


## Records a new respawn point (checkpoint volumes call this in later laps).
func set_checkpoint(pos: Vector3) -> void:
	checkpoint_position = pos
	_checkpoint_ready = true


## Starts the flop: freezes input, plays the visual + SFX hook, and begins
## the respawn countdown. Safe to call twice (second call is a no-op).
func kill() -> void:
	if is_flopped:
		return
	is_flopped = true
	flop_time_left = float(Tuning.respawn_delay_ms) / 1000.0
	var ragdoll := get_node_or_null("Ragdoll")
	if ragdoll != null:
		if ragdoll.has_method("play_flop"):
			ragdoll.call("play_flop", self)
		if ragdoll.has_method("play_flop_sfx"):
			ragdoll.call("play_flop_sfx")


## Restores the player at the last checkpoint with control. Called by the
## flop timer and by the kill plane (guarded has_method path).
func respawn() -> void:
	global_position = checkpoint_position
	rotation = Vector3.ZERO
	velocity = Vector3.ZERO
	is_flopped = false
	flop_time_left = 0.0
	_was_on_floor = false


## True while the player can be steered; false during the flop.
func is_alive() -> bool:
	return not is_flopped


func _physics_process(delta: float) -> void:
	if not _checkpoint_ready:
		checkpoint_position = global_position
		_checkpoint_ready = true
		_was_on_floor = is_on_floor()
	if is_flopped:
		flop_time_left -= delta
		var flop_grav: float = Tuning.gravity
		if velocity.y < 0.0:
			flop_grav = Tuning.gravity * Tuning.fall_multiplier
		velocity.y = maxf(velocity.y - flop_grav * delta, -Tuning.max_fall_speed)
		velocity.x = lerpf(velocity.x, 0.0, 1.0 - exp(-Tuning.ground_response * delta))
		velocity.z = lerpf(velocity.z, 0.0, 1.0 - exp(-Tuning.ground_response * delta))
		move_and_slide()
		_was_on_floor = is_on_floor()
		if flop_time_left <= 0.0:
			respawn()
		return
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
	_pre_slide_vy = velocity.y
	move_and_slide()
	var landed := (not _was_on_floor) and is_on_floor()
	_was_on_floor = is_on_floor()
	# Kill-plane fallback: fast falls can tunnel past the Area3D in one
	# physics step (and headless runs have no guaranteed overlap events),
	# so the y-position check below the plane is authoritative.
	if global_position.y < Tuning.kill_y:
		kill()
	elif landed and should_flop_on_impact(-_pre_slide_vy):
		kill()


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


## True when a downward impact speed (m/s) must trigger the flop.
static func should_flop_on_impact(impact_speed: float) -> bool:
	return impact_speed > Tuning.hard_impact_speed


## Flop-to-control-restored delay in ms; the only source is the Tuning
## surface, so the <3000 ms budget holds by construction.
static func simulate_flop_respawn_ms() -> int:
	return Tuning.respawn_delay_ms


## Synchronous flop self-test: respawn budget, impact predicate both sides,
## kill-plane depth, and ragdoll timeline wiring. No nodes, no awaits.
## Returns [passed, failed].
static func run_flop_selftest() -> Array:
	var passed := 0
	var failed := 0
	if simulate_flop_respawn_ms() < 3000 and simulate_flop_respawn_ms() > 0:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: respawn delay %d ms must be in (0, 3000)" % simulate_flop_respawn_ms())
	if should_flop_on_impact(Tuning.hard_impact_speed + 1.0):
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: impact above threshold must flop")
	if not should_flop_on_impact(Tuning.hard_impact_speed - 1.0):
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: impact below threshold must not flop")
	if Tuning.kill_y == -10.0:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: kill_y must be -10.0, got %f" % Tuning.kill_y)
	if Tuning.hard_impact_speed < Tuning.max_fall_speed:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: hard impact threshold must sit below max fall speed")
	if Ragdoll.flop_timeline_ms() == Tuning.respawn_delay_ms:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: ragdoll timeline must equal respawn delay")
	return [passed, failed]
