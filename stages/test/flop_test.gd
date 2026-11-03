extends Node3D
## Root of the offline flop test stage. Normal boot is a playable keyboard
## scene (WASD/arrows run, Space jumps); `--selftest flop` runs the
## synchronous flop self-test and quits (used headless / in CI).

const Tuning := preload("res://actors/player/tuning.gd")
const Controller := preload("res://actors/player/controller.gd")
const Ragdoll := preload("res://actors/player/ragdoll.gd")

## Exponential camera smoothing rate (1/s): same feel at any frame rate.
const CAMERA_RATE: float = 8.0
## Shoulder height the follow pivot tracks above the player origin.
const PIVOT_HEIGHT: float = 1.6

@onready var _player: Node3D = $Player
@onready var _pivot: Node3D = $FollowPivot


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") and args.has("flop"):
		_finish_selftest()
		return
	if _pivot != null and _player != null:
		_pivot.global_position = _player.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)


func _physics_process(delta: float) -> void:
	if _player == null or _pivot == null:
		return
	var anchor := _player.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
	var t := 1.0 - exp(-CAMERA_RATE * delta)
	_pivot.global_position = _pivot.global_position.lerp(anchor, t)


func _finish_selftest() -> void:
	var passed := 0
	var failed := 0
	var result: Array = Controller.run_flop_selftest()
	passed += int(result[0])
	failed += int(result[1])
	var ragdoll_result: Array = Ragdoll.run_selftest()
	passed += int(ragdoll_result[0])
	failed += int(ragdoll_result[1])
	# Stage wiring: the kill-plane instance must sit at y=-10 and the
	# player must expose the respawn path the plane calls into.
	var killplane := get_node_or_null("KillPlane")
	if killplane != null and absf((killplane as Node3D).global_position.y - Tuning.kill_y) < 0.01:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: KillPlane must sit at y=%f" % Tuning.kill_y)
	if _player != null and _player.has_method("respawn") and _player.has_method("kill"):
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: Player must expose kill()/respawn()")
	var respawn_ms := Controller.simulate_flop_respawn_ms()
	if respawn_ms < 3000:
		passed += 1
	else:
		failed += 1
		push_error("flop selftest: respawn_ms=%d must be < 3000" % respawn_ms)
	if failed == 0:
		print("FLOP_OK respawn_ms=%d" % respawn_ms)
	else:
		push_error("FLOP_FAIL failed=%d passed=%d" % [failed, passed])
	get_tree().quit(1 if failed > 0 else 0)
