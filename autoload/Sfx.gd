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
## Looping menu/stage music track (issue #20): single CC0 synth loop.
const MUSIC_PATH := "res://assets/music/loop.ogg"
const MUSIC_MIN_SECONDS := 30.0
const MUSIC_VOLUME_DB := -14.0

var _muted := false
var _players: Dictionary = {}
## Dedicated music player; created lazily behind the same
## ResourceLoader.exists guard as the effect players.
var _music_player: AudioStreamPlayer


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
	_ensure_music_player()


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


## Creates the dedicated music player behind the same lazy
## ResourceLoader.exists guard as the effect players: a missing track
## stays silent instead of crashing. The Ogg stream is set to loop so the
## menu/stage music never stops on its own.


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


## Filesystem path of the looping music track.
static func music_path() -> String:
	return MUSIC_PATH


## The bus owns exactly one looping music track.
static func music_count() -> int:
	return 1


## Length of the music track in seconds; 0.0 when the file is missing.
static func music_length() -> float:
	if not ResourceLoader.exists(MUSIC_PATH):
		return 0.0
	var stream := load(MUSIC_PATH) as AudioStream
	if stream == null:
		return 0.0
	return stream.get_length()


## Starts the looping menu/stage track. Silent no-op when muted, when the
## file is missing or unloadable, or when called outside the scene tree:
## never errors, never crashes, so stage autostart hooks need no guards.
func play_music() -> void:
	if _muted:
		return
	if not is_inside_tree():
		return
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	var stream := load(MUSIC_PATH) as AudioStream
	if stream == null:
		return
	_ensure_music_player()
	if _music_player == null:
		return
	_music_player.stream = stream
	_music_player.volume_db = MUSIC_VOLUME_DB
	_music_player.play()


## Stops the music track; silent no-op when it was never started.
func stop_music() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		_music_player.stop()


## True while the music track is playing.
func is_music_playing() -> bool:
	if _music_player == null or not is_instance_valid(_music_player):
		return false
	return _music_player.playing


## Playback position as a 0.0-1.0 fraction of the track length; 0.0 when
## the track is missing, empty, or not started.
func music_progress() -> float:
	if _music_player == null or not is_instance_valid(_music_player):
		return 0.0
	var stream := _music_player.stream as AudioStream
	if stream == null or stream.get_length() <= 0.0:
		return 0.0
	return clampf(_music_player.get_playback_position() / stream.get_length(), 0.0, 1.0)


## Lazy music-player factory shared by _ready and play_music.
func _ensure_music_player() -> void:
	if _music_player != null and is_instance_valid(_music_player):
		return
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	var stream := load(MUSIC_PATH) as AudioStream
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.volume_db = MUSIC_VOLUME_DB
	if is_inside_tree():
		add_child(player)
	_music_player = player


## Synchronous self-test: exact 8-name set, all 8 files resolvable, clean
## play() of each, clean play() of a missing name, clean muted play(), low
## default volume, plus the single looping music track (resolvable, longer
## than MUSIC_MIN_SECONDS, low music volume). Returns [passed, failed];
## never awaits.
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
	if music_count() == 1 and music_path() == MUSIC_PATH:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: bus must own exactly one music track")
	if ResourceLoader.exists(MUSIC_PATH):
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: missing %s" % MUSIC_PATH)
	if music_length() > MUSIC_MIN_SECONDS:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: music length %f s must exceed %f s" % [music_length(), MUSIC_MIN_SECONDS])
	bus.call("play_music")
	bus.call("stop_music")
	if float(bus.call("music_progress")) >= 0.0 and float(bus.call("music_progress")) <= 1.0:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: music_progress must stay in 0.0-1.0")
	bus.call("set_muted", true)
	bus.call("play_music")
	if not bool(bus.call("is_music_playing")):
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: muted bus must not start music")
	bus.call("set_muted", false)
	if MUSIC_VOLUME_DB <= -6.0:
		passed += 1
	else:
		failed += 1
		push_error("sfx selftest: music volume %f dB must stay low" % MUSIC_VOLUME_DB)
	bus.free()
	return [passed, failed]
