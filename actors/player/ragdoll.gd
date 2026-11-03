extends Node
## Scripted flop visual + flop-SFX hook (issue #4 comedy core).
## Event-triggered flop only: lethal fall / kill plane / hard impact calls
## play_flop() for a goofy Tween tip-over plus a small hop, and
## play_flop_sfx() as the audio hook. Full physics ragdoll (PhysicalBone
## simulator) is a later lap per the design doc; this scripted fallback is
## deterministic headless, which keeps the <3000 ms respawn selftest stable.

const Tuning := preload("res://actors/player/tuning.gd")

## Emitted when the flop visual starts / finishes (UI can hook these later).
signal flop_started
signal flop_finished


## Goofy tip-over: rotate the target ~90 degrees with a bounce ease plus a
## small hop. Safe headless: without a scene tree it just emits the signals.
func play_flop(target: Node3D) -> void:
	flop_started.emit()
	if target == null:
		flop_finished.emit()
		return
	if not is_inside_tree():
		flop_finished.emit()
		return
	var duration := float(Tuning.flop_duration_ms) / 1000.0
	var tw := create_tween()
	tw.tween_property(target, "rotation:z", target.rotation.z + 1.55, duration).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(target, "position:y", target.position.y + 0.6, duration * 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_on_flop_tween_done)


func _on_flop_tween_done() -> void:
	flop_finished.emit()


## Flop-SFX hook: plays a child AudioStreamPlayer3D named FlopSfx only when
## present; otherwise prints a debug line so headless runs stay deterministic.
## Real audio assets arrive in a later lap.
func play_flop_sfx() -> void:
	if has_node("FlopSfx"):
		var sfx := get_node("FlopSfx")
		if sfx != null and sfx.has_method("play"):
			sfx.call("play")
			return
	print("FLOP_SFX flop sound hook (no audio asset yet)")


## Total flop-to-control-restored delay in ms; the only timing source is
## Tuning.respawn_delay_ms so the budget holds by construction.
static func flop_timeline_ms() -> int:
	return Tuning.respawn_delay_ms


## Synchronous self-test: timing budget only, never touches the scene tree.
## Returns [passed, failed].
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if Tuning.flop_duration_ms <= Tuning.respawn_delay_ms:
		passed += 1
	else:
		failed += 1
		push_error("ragdoll selftest: flop visual %d ms exceeds respawn delay %d ms" % [Tuning.flop_duration_ms, Tuning.respawn_delay_ms])
	if Tuning.respawn_delay_ms < 3000 and Tuning.respawn_delay_ms > 0:
		passed += 1
	else:
		failed += 1
		push_error("ragdoll selftest: respawn delay %d ms must be in (0, 3000)" % Tuning.respawn_delay_ms)
	if flop_timeline_ms() == Tuning.respawn_delay_ms:
		passed += 1
	else:
		failed += 1
		push_error("ragdoll selftest: flop_timeline_ms() must equal Tuning.respawn_delay_ms")
	return [passed, failed]
