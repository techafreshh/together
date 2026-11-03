extends Node3D
## Root of the offline grab/carry/throw test stage (issue #7).
## Normal boot is a playable keyboard scene (WASD/arrows run, Space jumps,
## E grabs the mannequin, Q releases, F throws); `--selftest grab` runs
## the synchronous grab state-machine checks and quits (used headless /
## in CI). player.tscn stays untouched: the Grabber holder node is wired
## onto the Carrier at runtime here.

const Tuning := preload("res://actors/player/tuning.gd")
const Grabber := preload("res://actors/player/grabber.gd")

## Exponential camera smoothing rate (1/s): same feel at any frame rate.
const CAMERA_RATE: float = 8.0
## Shoulder height the follow pivot tracks above the player origin.
const PIVOT_HEIGHT: float = 1.6

var _carrier: Node3D
var _mannequin: Node3D
var _grabber: Node
var _label: Label
@onready var _pivot: Node3D = $FollowPivot


func _ready() -> void:
	_carrier = get_node_or_null("Carrier") as Node3D
	_mannequin = get_node_or_null("Mannequin") as Node3D
	_label = get_node_or_null("CanvasLayer/CarryLabel") as Label
	# Runtime holder wiring: the carrier owns a Grabber child so the
	# controller's guarded carry-slow query finds it.
	if _carrier != null:
		_grabber = Grabber.new()
		_grabber.name = "Grabber"
		_grabber.set("carrier", _carrier)
		_carrier.add_child(_grabber)
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") and args.has("grab"):
		_finish_selftest()
		return
	if _pivot != null and _carrier != null:
		_pivot.global_position = _carrier.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)


func _physics_process(delta: float) -> void:
	if _carrier == null or _pivot == null:
		return
	var anchor := _carrier.global_position + Vector3(0.0, PIVOT_HEIGHT, 0.0)
	var t := 1.0 - exp(-CAMERA_RATE * delta)
	_pivot.global_position = _pivot.global_position.lerp(anchor, t)


func _process(_delta: float) -> void:
	if _label == null:
		return
	if _grabber != null and bool(_grabber.call("is_carrying")):
		var body: Node3D = _grabber.call("carried_body") as Node3D
		_label.text = "Carrying: %s" % body.name
	else:
		_label.text = "Carrying: none"


func _unhandled_key_input(event: InputEvent) -> void:
	if _grabber == null or _carrier == null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_E:
				_grabber.call("try_grab", _mannequin)
			KEY_Q:
				_grabber.call("release")
			KEY_F:
				_grabber.call("throw_carried", _carrier_forward())


## Flat forward of the carrier (throw direction for the F key).
func _carrier_forward() -> Vector3:
	if _carrier == null:
		return Vector3(0.0, 0.0, -1.0)
	var fwd := -_carrier.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return Vector3(0.0, 0.0, -1.0)
	return fwd.normalized()


func _finish_selftest() -> void:
	var grabbed := 0
	var carried := 0
	var thrown := 0
	var passed := 0
	var failed := 0
	if _grabber == null or _carrier == null or _mannequin == null:
		failed += 1
		push_error("grab selftest: Carrier/Mannequin/Grabber wiring missing")
	else:
		if bool(_grabber.call("try_grab", _mannequin)):
			grabbed = 1
			passed += 1
		else:
			failed += 1
			push_error("grab selftest: in-range grab of the mannequin must succeed")
		if bool(_grabber.call("is_carrying")):
			carried = 1
			passed += 1
		else:
			failed += 1
			push_error("grab selftest: carrier must report carrying after grab")
		var slowed: float = Grabber.carried_move_speed(Tuning.move_speed)
		if slowed < Tuning.move_speed and slowed > 0.0:
			passed += 1
		else:
			failed += 1
			push_error("grab selftest: carried speed must be slowed but positive")
		_grabber.call("throw_carried", Vector3(0.0, 0.0, -1.0))
		if not bool(_grabber.call("is_carrying")):
			passed += 1
			var vel: Vector3 = _mannequin.get("velocity") as Vector3
			if vel.length() >= Tuning.throw_impulse:
				thrown = 1
				passed += 1
			else:
				failed += 1
				push_error("grab selftest: thrown mannequin must carry at least the throw impulse")
		else:
			failed += 1
			push_error("grab selftest: throw must clear the slot")
	if failed == 0 and grabbed == 1 and carried == 1 and thrown == 1:
		print("GRAB_OK grabbed=%d carried=%d thrown=%d" % [grabbed, carried, thrown])
	else:
		push_error("GRAB_FAIL grabbed=%d carried=%d thrown=%d failed=%d passed=%d" % [grabbed, carried, thrown, failed, passed])
	get_tree().quit(1 if failed > 0 else 0)
