extends SceneTree
## Unit runner for the audiovisual aggregate (issue #20): one looping CC0
## music track, the full SFX set, the palette recolor, the loading
## indicator, and the 60fps budget stub.
## Pattern mirrors tests/test_sfx_logic.gd: SceneTree runner with own
## counters, assert_eq helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_audiovisual_logic.gd

const Sfx := preload("res://autoload/Sfx.gd")
const Audiovisual := preload("res://server/audiovisual.gd")
const Perf := preload("res://server/perf.gd")
const Loading := preload("res://scenes/loading.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_music_exists_long",
		"test_sfx_files",
		"test_palette_ok",
		"test_selftests_green",
		"test_loading_indicator",
		"test_perf_stub",
	]:
		if call(t) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % t)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


func assert_true(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected true" % label)


## The single music track resolves and runs past the duration floor.
func test_music_exists_long() -> bool:
	assert_true(ResourceLoader.exists(Sfx.MUSIC_PATH), "music track resolves")
	assert_eq(Sfx.music_count(), 1, "music count is 1")
	assert_true(Sfx.music_length() > Sfx.MUSIC_MIN_SECONDS, "music runs past 30 s")
	assert_true(Sfx.MUSIC_VOLUME_DB <= -6.0, "music volume low")
	return true


## At least 8 effect files sit on disk and every owned name resolves.
func test_sfx_files() -> bool:
	assert_true(Audiovisual.sfx_file_count() >= 8, "sfx files >= 8 on disk")
	assert_true(Audiovisual.sfx_files_ok(), "every owned sfx name resolves")
	return true


## Palette doc lists every hex; recolor refs and floats hold.
func test_palette_ok() -> bool:
	assert_true(Audiovisual.palette_ok(), "palette aggregate holds")
	return true


## Both shared selftests stay green.
func test_selftests_green() -> bool:
	var av: Array = Audiovisual.run_selftest()
	assert_eq(int(av[1]), 0, "audiovisual selftest has no failures")
	assert_true(int(av[0]) > 0, "audiovisual selftest asserts something")
	var perf: Array = Perf.run_selftest()
	assert_eq(int(perf[1]), 0, "perf selftest has no failures")
	assert_true(int(perf[0]) > 0, "perf selftest asserts something")
	return true


## The loading scene instantiates and its progress API completes.
func test_loading_indicator() -> bool:
	var packed: PackedScene = load("res://scenes/loading.tscn") as PackedScene
	assert_true(packed != null, "loading scene loads")
	var node: Node = packed.instantiate() as Node
	assert_true(node != null, "loading scene instantiates")
	for p in Loading.required_nodes():
		assert_true(node.get_node_or_null(str(p)) != null, "loading carries %s" % str(p))
	node.call("set_status", "Warming up audio")
	node.call("set_progress", 0, 2)
	assert_true(not bool(node.call("is_complete")), "half progress incomplete")
	node.call("set_progress", 1, 1)
	assert_true(bool(node.call("is_complete")), "full progress completes")
	node.call("reset")
	assert_true(not bool(node.call("is_complete")), "reset clears completion")
	node.free()
	return true


## The perf stub is budget-sane and headless here.
func test_perf_stub() -> bool:
	assert_eq(Perf.TARGET_FPS, 60, "target is 60fps")
	assert_true(Perf.FRAME_BUDGET_MS > 16.0 and Perf.FRAME_BUDGET_MS < 17.0, "budget near 16.67 ms")
	assert_true(Perf.check_budget(16.0), "in-budget frame passes")
	assert_true(not Perf.check_budget(100.0), "over-budget frame fails")
	assert_true(Perf.is_headless(), "headless runner detects headless")
	return true
