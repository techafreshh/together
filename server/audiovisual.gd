extends RefCounted
## Audiovisual aggregate proof (issue #20): one looping CC0 music track plus
## the full SFX set, every material snapped to `docs/palette.md`.
##
## Tree-free static checks shared by the `--selftest audiovisual` serve
## branch and the unit runner: music_ok (the Ogg exists and runs longer
## than MUSIC_MIN_SECONDS), sfx_files_ok (at least 8 .wav files on disk and
## every SFX_NAMES entry resolvable), palette_ok (every Core swatch hex is
## listed in docs/palette.md, every assets/recolor.json mapping points at a
## palette hex with a literal assets/ reference, and every mapped material
## carries on-palette floats within FLOAT_TOLERANCE). run_selftest returns
## [passed, failed]; never awaits, touches no scene tree.

const SfxScript := preload("res://autoload/Sfx.gd")

## Core swatches from docs/palette.md `## Core swatches` (single source of
## truth for the recolor pass).
const PALETTE_HEXES: Array = [
	"#77C7D9",
	"#5FB75A",
	"#E3B76B",
	"#D95D39",
	"#22333B",
	"#F2EDE3",
	"#FFB703",
]

## Player colors (P1-P4) from docs/palette.md.
const PLAYER_HEXES: Array = ["#EF476F", "#118AB2", "#06D6A0", "#8338EC"]

## Wardrobe skin hues from docs/palette.md.
const SKIN_HEXES: Array = ["#2B2D42", "#B8F2E6", "#FF9F1C", "#FF70A6"]

const PALETTE_DOC := "res://docs/palette.md"
const RECOLOR_JSON := "res://assets/recolor.json"
const ASSETS_README := "res://assets/README.md"
## Per-channel tolerance for the on-palette float check: exact palette
## floats land at 0.0 distance, so 0.02 only forgives float formatting.
const FLOAT_TOLERANCE := 0.02
const MIN_SFX_FILES := 8


## Every known palette hex (core + player + skins).
static func all_hexes() -> Array:
	var out: Array = []
	out.append_array(PALETTE_HEXES)
	out.append_array(PLAYER_HEXES)
	out.append_array(SKIN_HEXES)
	return out


## The single music track resolves and runs past the duration floor.
static func music_ok() -> bool:
	if not ResourceLoader.exists(SfxScript.MUSIC_PATH):
		return false
	return SfxScript.music_length() > SfxScript.MUSIC_MIN_SECONDS


## At least MIN_SFX_FILES .wav files under assets/sfx, and every owned
## effect name resolves to a file.
static func sfx_files_ok() -> bool:
	if sfx_file_count() < MIN_SFX_FILES:
		return false
	for n in SfxScript.sfx_names():
		if not ResourceLoader.exists(SfxScript.stream_path(str(n))):
			return false
	return true


## How many .wav effect files (not .import stamps) sit under assets/sfx.
static func sfx_file_count() -> int:
	var dir := DirAccess.open("res://assets/sfx")
	if dir == null:
		return 0
	var count := 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".wav"):
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


## Palette contract: doc lists every hex, recolor.json maps touched
## materials to palette hexes with literal assets/ references, and every
## mapped material carries on-palette floats.
static func palette_ok() -> bool:
	if not _doc_lists_hexes():
		return false
	var mappings := _recolor_mappings()
	if mappings.is_empty():
		return false
	if not _mappings_reference_palette(mappings):
		return false
	return _mapped_floats_on_palette(mappings)


## docs/palette.md exists and names every known hex (case-insensitive).
static func _doc_lists_hexes() -> bool:
	if not FileAccess.file_exists(PALETTE_DOC):
		return false
	var text := FileAccess.get_file_as_string(PALETTE_DOC).to_upper()
	for h in all_hexes():
		if not text.contains(str(h).to_upper()):
			return false
	return true


## Parsed mapping rows from assets/recolor.json; [] when missing/unparsable.
static func _recolor_mappings() -> Array:
	if not FileAccess.file_exists(RECOLOR_JSON):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RECOLOR_JSON))
	if not (parsed is Dictionary):
		return []
	var mappings: Array = (parsed as Dictionary).get("mappings", [])
	if not (mappings is Array):
		return []
	return mappings


## Every mapping hex is a palette hex and appears literally under assets/
## (recolor.json itself plus the README hex table count as references).
static func _mappings_reference_palette(mappings: Array) -> bool:
	var known: Array = all_hexes()
	var refs := ""
	if FileAccess.file_exists(RECOLOR_JSON):
		refs += FileAccess.get_file_as_string(RECOLOR_JSON)
	if FileAccess.file_exists(ASSETS_README):
		refs += FileAccess.get_file_as_string(ASSETS_README)
	refs = refs.to_upper()
	for row in mappings:
		if not (row is Dictionary):
			return false
		var hexcode := str((row as Dictionary).get("hex", "")).to_upper()
		if not known.has(hexcode):
			return false
		if not refs.contains(hexcode):
			return false
	return true


## Every mapped file carries an albedo_color within FLOAT_TOLERANCE (per
## channel, rgb only so translucent materials keep their alpha) of the
## mapped hex.
static func _mapped_floats_on_palette(mappings: Array) -> bool:
	for row in mappings:
		if not (row is Dictionary):
			return false
		var rel := str((row as Dictionary).get("file", ""))
		var hexcode := str((row as Dictionary).get("hex", ""))
		if rel == "" or hexcode == "":
			return false
		if not FileAccess.file_exists("res://" + rel):
			return false
		var want := Color.html(hexcode)
		var text := FileAccess.get_file_as_string("res://" + rel)
		if not _file_has_palette_float(text, want):
			return false
	return true


## True when any `albedo_color = Color(r, g, b[, a])` in the file text sits
## within FLOAT_TOLERANCE of the wanted color on every rgb channel.
static func _file_has_palette_float(text: String, want: Color) -> bool:
	var cursor := 0
	while true:
		var at := text.find("albedo_color = Color(", cursor)
		if at < 0:
			return false
		var end := text.find(")", at)
		if end < 0:
			return false
		var inner := text.substr(at + len("albedo_color = Color("), end - at - len("albedo_color = Color("))
		var parts := inner.split(",")
		if parts.size() >= 3:
			var got := Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
			var target := Vector3(want.r, want.g, want.b)
			if absf(got.x - target.x) <= FLOAT_TOLERANCE and absf(got.y - target.y) <= FLOAT_TOLERANCE and absf(got.z - target.z) <= FLOAT_TOLERANCE:
				return true
		cursor = end + 1
	return true


## Synchronous aggregate self-test: music resolves long, sfx files >= 8,
## palette doc + recolor refs + on-palette floats all hold. Returns
## [passed, failed]; never awaits.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if music_ok():
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: music %s must resolve longer than %f s" % [SfxScript.MUSIC_PATH, SfxScript.MUSIC_MIN_SECONDS])
	if sfx_file_count() >= MIN_SFX_FILES:
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: expected >= %d sfx files, got %d" % [MIN_SFX_FILES, sfx_file_count()])
	if sfx_files_ok():
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: every owned sfx name must resolve")
	if _doc_lists_hexes():
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: docs/palette.md must list every hex")
	var mappings := _recolor_mappings()
	if not mappings.is_empty():
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: assets/recolor.json must carry mappings")
	if not mappings.is_empty() and _mappings_reference_palette(mappings):
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: every mapped hex must be a palette hex with an assets/ reference")
	if not mappings.is_empty() and _mapped_floats_on_palette(mappings):
		passed += 1
	else:
		failed += 1
		push_error("audiovisual selftest: every mapped material must carry on-palette floats")
	return [passed, failed]
