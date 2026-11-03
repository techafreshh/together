extends Node3D
## Root of the offline controller test stage. Normal boot is a playable
## keyboard scene (WASD/arrows run, Space jumps); `--selftest controller`
## runs the synchronous logic self-test and quits (used headless / in CI).

const Tuning := preload("res://actors/player/tuning.gd")
const Controller := preload("res://actors/player/controller.gd")

## Exponential camera smoothing rate (1/s): same feel at any frame rate.
const CAMERA_RATE: float = 8.0
## Shoulder height the follow pivot tracks above the player origin.
const PIVOT_HEIGHT: float = 1.6

@onready var _player: Node3D = $Player
@onready var _pivot: Node3D = $FollowPivot


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") and args.has("controller"):
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
	var result: Array = Controller.run_selftest()
	var failed := int(result[1])
	if failed == 0:
		print("CONTROLLER_OK jump_arc_ms=%d coyote_ms=%d" % [Tuning.jump_arc_ms(), Tuning.coyote_ms])
	else:
		push_error("CONTROLLER_FAIL failed=%d" % failed)
	get_tree().quit(1 if failed > 0 else 0)
