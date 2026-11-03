extends Node3D
## Timed pair-lever prop (kit B): two levers pulled within a short window.
## Uniform kit semantics: `pressed` fires per lever pull, `released` fires
## on reset, `activated` fires when both levers land inside PAIR_WINDOW_MS.
## Runtime stamps come from Time.get_ticks_msec(); the window check itself
## is the pure static pair_complete() so fake timestamps stay unit-testable.

signal pressed
signal released
signal activated

## Both levers must land within this window (ms) to fire the verb.
const PAIR_WINDOW_MS := 2000

## Last pull stamps in ms since boot; -1 means that lever was never pulled.
var a_at_ms: int = -1
var b_at_ms: int = -1
## True once a pair has fired (until reset).
var paired: bool = false


## Pure window check: both stamps set and within `window_ms` of each other.
static func pair_complete(a_ms: int, b_ms: int, window_ms: int) -> bool:
	if a_ms < 0 or b_ms < 0:
		return false
	return abs(a_ms - b_ms) <= window_ms


## Pulls lever A. An explicit stamp keeps tests deterministic; omitted
## stamps use the live clock. Emits pressed, then activated on a pair.
func pull_a(at_ms: int = -1) -> void:
	var stamp := at_ms
	if stamp < 0:
		stamp = int(Time.get_ticks_msec())
	a_at_ms = stamp
	pressed.emit()
	_check_pair()


## Pulls lever B. Mirrors pull_a.
func pull_b(at_ms: int = -1) -> void:
	var stamp := at_ms
	if stamp < 0:
		stamp = int(Time.get_ticks_msec())
	b_at_ms = stamp
	pressed.emit()
	_check_pair()


## Clears both stamps. Emits released when anything was latched.
func reset() -> void:
	var had := a_at_ms >= 0 or b_at_ms >= 0 or paired
	a_at_ms = -1
	b_at_ms = -1
	paired = false
	if had:
		released.emit()


## True while a pair is latched.
func is_paired() -> bool:
	return paired


func _check_pair() -> void:
	if paired:
		return
	if pair_complete(a_at_ms, b_at_ms, PAIR_WINDOW_MS):
		paired = true
		activated.emit()


## Synchronous self-test: pure window checks plus direct pull drives with
## fake timestamps on an instantiated scene (inside/outside window, reset
## reuse, live-clock pulls). Returns [passed, failed]; no awaits.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if pair_complete(1000, 1500, PAIR_WINDOW_MS) and pair_complete(0, 2000, PAIR_WINDOW_MS):
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: pairs inside the window must complete")
	if not pair_complete(0, 2001, PAIR_WINDOW_MS) and not pair_complete(0, 5000, PAIR_WINDOW_MS):
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: pairs outside the window must not complete")
	if not pair_complete(-1, 500, PAIR_WINDOW_MS) and not pair_complete(500, -1, PAIR_WINDOW_MS):
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: unset stamps must not complete")
	var packed: PackedScene = load("res://actors/props/lever.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("lever selftest: lever.tscn failed to load")
		return [passed, failed]
	var levers: Node = packed.instantiate() as Node
	if levers == null:
		failed += 1
		push_error("lever selftest: lever.tscn failed to instantiate")
		return [passed, failed]
	var hits := {"pressed": 0, "released": 0, "activated": 0}
	levers.connect("pressed", func(): hits["pressed"] += 1)
	levers.connect("released", func(): hits["released"] += 1)
	levers.connect("activated", func(): hits["activated"] += 1)
	levers.call("pull_a", 1000)
	if not bool(levers.call("is_paired")) and int(hits["pressed"]) == 1 and int(hits["activated"]) == 0:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: single pull must not pair")
	levers.call("pull_b", 1500)
	if bool(levers.call("is_paired")) and int(hits["activated"]) == 1 and int(hits["pressed"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: pair inside window must activate")
	levers.call("pull_a", 1600)
	if int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: pulls after pairing must not re-activate")
	levers.call("reset")
	if not bool(levers.call("is_paired")) and int(hits["released"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: reset must clear the pair and emit released")
	levers.call("pull_a", 0)
	levers.call("pull_b", 5000)
	if not bool(levers.call("is_paired")) and int(hits["activated"]) == 1:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: pair outside window must not activate")
	levers.call("reset")
	levers.call("pull_a")
	levers.call("pull_b")
	if bool(levers.call("is_paired")) and int(hits["activated"]) == 2:
		passed += 1
	else:
		failed += 1
		push_error("lever selftest: live-clock pulls must pair")
	levers.free()
	return [passed, failed]
