extends RefCounted
## Server-side JSON persistence keyed by display name (issue #17).
##
## One JSON file per display name inside the server data dir, shaped as
## `{"coins": int, "owned": Array, "equipped": Dictionary,
## "stages": {stage_id: {"clears": int, "best_ms": int}}}`. Loaded on
## `join_room`, saved on results/purchase, surviving restarts and client
## cache clears. No encryption, minimal logs.
##
## Pure file helpers plus in-memory profile helpers: no sockets, no scene
## tree. The main-scene root (server/serve.gd) owns the `--selftest
## persist` branch; the unit runner is tests/test_persist_logic.gd.

const SELFTEST_PLAYER := "TestPlayer"
const SELFTEST_STAGE := "w1s1"
const SELFTEST_COINS := 1
const MAX_NAME_LENGTH := 32


## Trims the display name, replaces path separators and anything outside
## `[A-Za-z0-9_-]` with `_`, caps at 32 chars, falls back to `Player`.
static func sanitize_name(display_name: Variant) -> String:
	var s := str(display_name).strip_edges()
	if s == "":
		return "Player"
	var out := ""
	for i in range(s.length()):
		var ch := s.substr(i, 1)
		var code := ch.unicode_at(0)
		var ok := (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or ch == "_" or ch == "-"
		out += ch if ok else "_"
	if out.length() > MAX_NAME_LENGTH:
		out = out.substr(0, MAX_NAME_LENGTH)
	if out == "":
		return "Player"
	return out


## Filesystem path for one display name inside the data dir.
static func player_path(data_dir: String, display_name: String) -> String:
	var base := str(data_dir)
	while base.ends_with("/") and base.length() > 1:
		base = base.substr(0, base.length() - 1)
	if base.strip_edges() == "":
		base = "user://players"
	return base + "/" + sanitize_name(display_name) + ".json"


## Canonical fresh profile: zeros and empty collections.
static func default_profile() -> Dictionary:
	return {"coins": 0, "owned": [], "equipped": {}, "stages": {}}


## Absolute OS path for a Godot `user://` / `res://` path, else unchanged.
static func _absolute(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


## Ensures the data dir exists (recursive). Warns only, never quits.
static func ensure_dir(data_dir: String) -> bool:
	var dir := str(data_dir)
	if dir.strip_edges() == "":
		return false
	var abs := _absolute(dir)
	var err := DirAccess.make_dir_recursive_absolute(abs)
	if err == OK or DirAccess.dir_exists_absolute(abs):
		return true
	push_warning("persistence: cannot create data dir %s (error %d)" % [dir, err])
	return false


## Loads one display-name profile. Missing files and corrupt JSON return
## the default profile with a warning; never errors, never quits.
static func load_player(data_dir: String, display_name: String) -> Dictionary:
	var path := player_path(data_dir, display_name)
	if not FileAccess.file_exists(path):
		return default_profile()
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("persistence: corrupt profile for %s, using defaults" % sanitize_name(display_name))
		return default_profile()
	var raw: Dictionary = parsed
	var out := default_profile()
	var coins := int(raw.get("coins", 0))
	out["coins"] = maxi(0, coins)
	var owned: Array = []
	if raw.get("owned", []) is Array:
		for item in (raw.get("owned", []) as Array):
			owned.append(str(item))
	out["owned"] = owned
	if raw.get("equipped", {}) is Dictionary:
		out["equipped"] = (raw.get("equipped", {}) as Dictionary).duplicate(true)
	var stages := {}
	if raw.get("stages", {}) is Dictionary:
		for stage in ((raw.get("stages", {}) as Dictionary).keys()):
			var entry: Variant = (raw.get("stages", {}) as Dictionary)[stage]
			if entry is Dictionary:
				var clears := maxi(0, int((entry as Dictionary).get("clears", 0)))
				var best_ms := maxi(0, int((entry as Dictionary).get("best_ms", 0)))
				stages[str(stage)] = {"clears": clears, "best_ms": best_ms}
	out["stages"] = stages
	return out


## Saves one display-name profile, creating the data dir recursively.
## Returns true on success; warns only on IO failure.
static func save_player(data_dir: String, display_name: String, profile: Dictionary) -> bool:
	if not ensure_dir(data_dir):
		push_warning("persistence: data dir unavailable for %s" % sanitize_name(display_name))
		return false
	var path := player_path(data_dir, display_name)
	var text := JSON.stringify(profile)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("persistence: cannot write profile for %s" % sanitize_name(display_name))
		return false
	f.store_string(text)
	f.close()
	return true


## Adds (or removes, when negative) coins, clamped at zero. Returns the
## new balance; mutates the profile in place.
static func add_coins(profile: Dictionary, amount: int) -> int:
	var cur := maxi(0, int(profile.get("coins", 0)) + int(amount))
	profile["coins"] = cur
	return cur


## Records one clear for `stage_id`, bumping `clears` and keeping the best
## (lowest) `best_ms`. Returns the stage entry; mutates the profile.
static func record_clear(profile: Dictionary, stage_id: String, best_ms: int) -> Dictionary:
	if not (profile.get("stages", {}) is Dictionary):
		profile["stages"] = {}
	var stages: Dictionary = profile["stages"]
	var sid := str(stage_id)
	var entry := {"clears": 0, "best_ms": maxi(0, int(best_ms))}
	if stages.has(sid) and stages[sid] is Dictionary:
		entry = ((stages[sid] as Dictionary).duplicate(true))
		entry["clears"] = maxi(0, int(entry.get("clears", 0))) + 1
		entry["best_ms"] = mini(maxi(0, int(entry.get("best_ms", best_ms))), maxi(0, int(best_ms)))
	else:
		entry = {"clears": 1, "best_ms": maxi(0, int(best_ms))}
	stages[sid] = entry
	profile["stages"] = stages
	return entry


## Spends `price` coins on `item_id` when affordable and not yet owned.
## Returns `{ok, ...}`; mutates the profile only on success.
static func try_purchase(profile: Dictionary, item_id: String, price: int) -> Dictionary:
	var item := str(item_id)
	var cost := int(price)
	if item == "" or cost < 0:
		return {"ok": false, "error": "invalid_item"}
	if not (profile.get("owned", []) is Array):
		profile["owned"] = []
	var owned: Array = profile["owned"]
	if owned.has(item):
		return {"ok": false, "error": "already_owned"}
	var coins := int(profile.get("coins", 0))
	if coins < cost:
		return {"ok": false, "error": "insufficient_coins"}
	profile["coins"] = coins - cost
	owned.append(item)
	return {"ok": true, "coins": int(profile["coins"]), "owned": owned.duplicate(true)}


## Synchronous self-test: builds a fresh TestPlayer profile, records one
## w1s1 clear awarding exactly 1 coin, saves, re-loads from disk, and
## asserts `coins == 1` with matching stage state (restart_survives).
## Only ever writes `<dir>/TestPlayer.json`. Returns [passed, failed];
## never awaits, never touches the scene tree.
static func run_selftest(data_dir: String) -> Array:
	var passed := 0
	var failed := 0
	var dir := str(data_dir).strip_edges()
	if dir == "":
		dir = OS.get_temp_dir()
	if not ensure_dir(dir):
		failed += 1
		push_error("persist selftest: cannot create data dir %s" % dir)
		return [passed, failed]
	var profile := default_profile()
	record_clear(profile, SELFTEST_STAGE, 1000)
	add_coins(profile, SELFTEST_COINS)
	if int(profile.get("coins", 0)) != SELFTEST_COINS:
		failed += 1
		push_error("persist selftest: fresh profile must hold %d coin(s)" % SELFTEST_COINS)
	else:
		passed += 1
	if not save_player(dir, SELFTEST_PLAYER, profile):
		failed += 1
		push_error("persist selftest: save_player failed in %s" % dir)
		return [passed, failed]
	passed += 1
	var path := player_path(dir, SELFTEST_PLAYER)
	if not FileAccess.file_exists(path):
		failed += 1
		push_error("persist selftest: %s missing after save" % path)
		return [passed, failed]
	passed += 1
	var text := FileAccess.get_file_as_string(path)
	if text.contains("\"coins\"") and text.contains("\"stages\""):
		passed += 1
	else:
		failed += 1
		push_error("persist selftest: saved JSON must carry coins and stages keys")
	var reloaded := load_player(dir, SELFTEST_PLAYER)
	if int(reloaded.get("coins", -1)) == SELFTEST_COINS:
		passed += 1
	else:
		failed += 1
		push_error("persist selftest: re-loaded coins must be %d" % SELFTEST_COINS)
	var stages: Dictionary = reloaded.get("stages", {})
	var entry: Dictionary = stages.get(SELFTEST_STAGE, {})
	if int(entry.get("clears", 0)) == 1:
		passed += 1
	else:
		failed += 1
		push_error("persist selftest: re-loaded w1s1 clears must be 1 (restart_survives)")
	return [passed, failed]
