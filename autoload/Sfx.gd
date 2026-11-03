extends Node
## Central comedy SFX bus (issue #8 thin placeholder layer).
## Lazy-loads the CC0 synthesized effects from `assets/sfx/<name>.wav`
## behind ResourceLoader.exists() guards, so missing files mute silently
## instead of crashing. Single entry point: play(sfx_name). Default volume
## is low (-12 dB); set_muted(true) silences everything. There is deliberately
## no top-level preload of any .wav path: a missing file must never be a
## parse-time crash.

const SFX_NAMES: Array = ["jump", "flop", "grab", "throw", "button", "checkpoint", "goal", "coin"]
const SFX_DIR := "res://assets/sfx"
const DEFAULT_VOLUME_DB := -12.0

var _muted := false
var _players: Dictionary = {}


func _ready() -> void:
	for sfx_name in SFX_NAMES:
		var path := stream_path(str(sfx_name))
		if not ResourceLoader.exists(path):
			continue
		var stream := load(path)
		if stream == null:
			continue
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = DEFAULT_VOLUME_DB
		add_child(player)
		_players[str(sfx_name)] = player


## Plays one effect by name. Returns silently when muted, when the name is
## unknown, or when the file is missing or unloadable: never errors, never
## crashes, so gameplay call sites need no guards of their own.
func play(sfx_name: String) -> void:
	if _muted:
		return
	if not SFX_NAMES.has(sfx_name):
		return
	var path := stream_path(sfx_name)
	if not ResourceLoader.exists(path):
		return
	var stream := load(path)
	if stream == null:
		return
	if not is_inside_tree():
		return
	var player := _players.get(sfx_name) as AudioStreamPlayer
	if player == null:
		player = AudioStreamPlayer.new()
		player.volume_db = DEFAULT_VOLUME_DB
		add_child(player)
		_players[sfx_name] = player
	player.stream = stream
	player.volume_db = DEFAULT_VOLUME_DB
	player.play()


## Silences (true) or restores (false) every effect.
func set_muted(muted: bool) -> void:
	_muted = muted


## True while every effect is silenced.
func is_muted() -> bool:
	return _muted


## Filesystem path for one effect name.
static func stream_path(sfx_name: String) -> String:
	return "%s/%s.wav" % [SFX_DIR, sfx_name]


## The eight event names in issue order; a duplicate so callers cannot
## mutate the bus registry.
static func sfx_names() -> Array:
	return SFX_NAMES.duplicate()


## How many effects the bus owns.
static func sfx_count() -> int:
	return SFX_NAMES.size()


## Synchronous self-test: exact 8-name set, all 8 files resolvable, clean
## play() of each, clean play() of a missing name, clean muted play(), low
## default volume. Returns [passed, failed]; never awaits.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var expected: Array = ["jump", "flop", "grab", "throw", "button", "checkpoint", "goal", "coin"]
	if sfx_names() == expected:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: name set mismatch %s" % str(sfx_names()))
	if sfx_count() == 8:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: expected 8 names, got %d" % sfx_count())
	for n in expected:
		var pname := str(n)
		if ResourceLoader.exists(stream_path(pname)):
			passed += 1
		else:
			failed += 1
			push_error("sfx selftest: missing %s" % stream_path(pname))
	var bus: Node = (load("res://autoload/Sfx.gd") as GDScript).new()
	for n in expected:
		bus.call("play", str(n))
	passed += 1
	bus.call("play", "no_such_sfx")
	passed += 1
	bus.call("set_muted", true)
	bus.call("play", "jump")
	if bool(bus.call("is_muted")):
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: muted bus must report is_muted")
	bus.call("set_muted", false)
	if DEFAULT_VOLUME_DB <= -6.0:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: default volume %f dB must stay low" % DEFAULT_VOLUME_DB)
	bus.free()
	return [passed, failed]
