extends Node3D
## Offline kit demo stage (prop kit B): lines up all five cooperation props
## in a row for manual testing. `--selftest props` runs the aggregated
## synchronous logic checks shared with the main scene and quits (used
## headless / in CI); a normal boot is a viewable stage with no player.

const ButtonScript := preload("res://actors/props/button.gd")
const SequenceScript := preload("res://actors/props/sequence_buttons.gd")
const BoostScript := preload("res://actors/props/boost.gd")
const SeesawScript := preload("res://actors/props/seesaw.gd")
const LeverScript := preload("res://actors/props/lever.gd")


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--selftest") and args.has("props"):
		_finish_selftest()


func _finish_selftest() -> void:
	var button_result: Array = ButtonScript.run_selftest()
	var sequence_result: Array = SequenceScript.run_selftest()
	var boost_result: Array = BoostScript.run_selftest()
	var seesaw_result: Array = SeesawScript.run_selftest()
	var lever_result: Array = LeverScript.run_selftest()
	var failed := int(button_result[1]) + int(sequence_result[1]) + int(boost_result[1]) + int(seesaw_result[1]) + int(lever_result[1])
	if failed == 0:
		print("PROP_OK button=1 sequence=1 boost=1 seesaw=1 lever=1")
	else:
		push_error("PROP_FAIL button=%d sequence=%d boost=%d seesaw=%d lever=%d" % [
			1 if int(button_result[1]) == 0 else 0,
			1 if int(sequence_result[1]) == 0 else 0,
			1 if int(boost_result[1]) == 0 else 0,
			1 if int(seesaw_result[1]) == 0 else 0,
			1 if int(lever_result[1]) == 0 else 0,
		])
	get_tree().quit(1 if failed > 0 else 0)
