extends RefCounted
## In-memory rooms lobby (issue #10): zero-friction create-by-code and
## join-by-code with display names and cosmetic colors.
##
## Pure synchronous lobby state: a Dictionary of rooms keyed by 4-char code,
## no sockets, no scene tree. The main-scene root (server/serve.gd) owns the
## `--selftest rooms` branch; live socket broadcast stays out of scope until
## the net lap wires it. Room caps come from autoload/Config.gd, never from
## literals here. Duplicate display names are allowed: player identity is an
## auto-incremented player id, never the name.

const ConfigScript := preload("res://autoload/Config.gd")

## Room codes are 4 chars from unambiguous uppercase alphanumerics
## (no lowercase, no I/O/0/1 lookalikes).
const CODE_LENGTH := 4
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
## Fixed palette fallback for player colors; cosmetic_hash picks the slot.
const PALETTE := ["#e64545", "#4da3ff", "#5fd35f", "#ffd23f", "#b07fe8", "#ff8c42"]
## Proof shape the headless selftest (and the serve.gd OK line) relies on:
## 3 collision-checked rooms holding 4 joined clients total.
const SELFTEST_ROOMS := 3
const SELFTEST_PLAYERS := 4

var _rooms: Dictionary = {}
var _next_player_id: int = 1


## True when code is a 4-char string drawn fully from CODE_ALPHABET.
static func is_valid_code(code: Variant) -> bool:
	if typeof(code) != TYPE_STRING:
		return false
	var s := str(code)
	if s.length() != CODE_LENGTH:
		return false
	for i in range(s.length()):
		if CODE_ALPHABET.find(s.substr(i, 1)) < 0:
			return false
	return true


## Uppercases and trims caller input so `join_room`/`leave_room`/`room_state`
## accept lowercase codes while stored codes stay canonical uppercase.
static func normalize_code(code: Variant) -> String:
	return str(code).strip_edges().to_upper()


## Picks a palette color deterministically from an opaque caller-supplied
## cosmetic_hash stored verbatim on the player; empty hash takes slot zero.
static func color_for(cosmetic_hash: Variant) -> String:
	var h := str(cosmetic_hash)
	if h == "":
		return PALETTE[0]
	return PALETTE[abs(hash(h)) % PALETTE.size()]


static func _make_player(player_id: int, player_name: Variant, cosmetic_hash: Variant) -> Dictionary:
	return {
		"id": player_id,
		"name": str(player_name),
		"cosmetic_hash": str(cosmetic_hash),
		"color": color_for(cosmetic_hash),
		"ready": false,
	}


func room_count() -> int:
	return _rooms.size()


func player_count() -> int:
	var n := 0
	for code in _rooms.keys():
		n += ((self._rooms[code] as Dictionary).get("players", []) as Array).size()
	return n


func list_codes() -> Array:
	return _rooms.keys()


func _generate_code() -> String:
	var code := ""
	for i in range(CODE_LENGTH):
		code += CODE_ALPHABET.substr(randi() % CODE_ALPHABET.length(), 1)
	return code


## Creates a room hosted by `host_name`, returning {ok, code, player_id}.
## Rejects when the Config.MAX_ROOMS concurrent-room cap is reached.
func create_room(host_name: Variant, cosmetic_hash: Variant) -> Dictionary:
	if _rooms.size() >= ConfigScript.MAX_ROOMS:
		return {"ok": false, "error": "rooms_full"}
	var code := _generate_code()
	while _rooms.has(code):
		code = _generate_code()
	var player_id := _next_player_id
	_next_player_id += 1
	_rooms[code] = {
		"code": code,
		"host_id": player_id,
		"screen": "lobby",
		"players": [_make_player(player_id, host_name, cosmetic_hash)],
	}
	return {"ok": true, "code": code, "player_id": player_id}


## Joins `{code, name, cosmetic_hash}`: invalid/unknown codes and full rooms
## (Config.MAX_ROOM_PLAYERS) fail closed; duplicate names stay accepted.
func join_room(code: Variant, player_name: Variant, cosmetic_hash: Variant) -> Dictionary:
	var c := normalize_code(code)
	if not is_valid_code(c):
		return {"ok": false, "error": "invalid_code"}
	if not _rooms.has(c):
		return {"ok": false, "error": "unknown_code"}
	var room: Dictionary = _rooms[c]
	var players: Array = room["players"]
	if players.size() >= ConfigScript.MAX_ROOM_PLAYERS:
		return {"ok": false, "error": "room_full"}
	var player_id := _next_player_id
	_next_player_id += 1
	players.append(_make_player(player_id, player_name, cosmetic_hash))
	return {"ok": true, "code": c, "player_id": player_id}


## Removes one player; reassigns host_id to the oldest remaining player and
## erases the room when it empties.
func leave_room(code: Variant, player_id: int) -> Dictionary:
	var c := normalize_code(code)
	if not is_valid_code(c):
		return {"ok": false, "error": "invalid_code"}
	if not _rooms.has(c):
		return {"ok": false, "error": "unknown_code"}
	var room: Dictionary = _rooms[c]
	var players: Array = room["players"]
	var idx := -1
	for i in range(players.size()):
		if int((players[i] as Dictionary).get("id", 0)) == player_id:
			idx = i
			break
	if idx < 0:
		return {"ok": false, "error": "unknown_player"}
	players.remove_at(idx)
	if players.is_empty():
		_rooms.erase(c)
		return {"ok": true, "code": c, "erased": true}
	if int(room.get("host_id", 0)) == player_id:
		room["host_id"] = int((players[0] as Dictionary).get("id", 0))
	return {"ok": true, "code": c, "erased": false}


## Toggles the ready badge persisted on the player inside the room.
func set_ready(code: Variant, player_id: int, ready: bool) -> Dictionary:
	var c := normalize_code(code)
	if not is_valid_code(c):
		return {"ok": false, "error": "invalid_code"}
	if not _rooms.has(c):
		return {"ok": false, "error": "unknown_code"}
	var room: Dictionary = _rooms[c]
	for p in (room.get("players", []) as Array):
		var entry: Dictionary = p
		if int(entry.get("id", 0)) == player_id:
			entry["ready"] = bool(ready)
			return {"ok": true, "code": c, "player_id": player_id, "ready": bool(ready)}
	return {"ok": false, "error": "unknown_player"}


## Returns {ok, room_state} where room_state carries {code, players, host_id,
## screen} and each player carries {id, name, cosmetic_hash, color, ready}.
func room_state(code: Variant) -> Dictionary:
	var c := normalize_code(code)
	if not is_valid_code(c):
		return {"ok": false, "error": "invalid_code"}
	if not _rooms.has(c):
		return {"ok": false, "error": "unknown_code"}
	var room: Dictionary = _rooms[c]
	var players_out: Array = []
	for p in (room.get("players", []) as Array):
		var entry: Dictionary = p
		players_out.append({
			"id": int(entry.get("id", 0)),
			"name": str(entry.get("name", "")),
			"cosmetic_hash": str(entry.get("cosmetic_hash", "")),
			"color": str(entry.get("color", "")),
			"ready": bool(entry.get("ready", false)),
		})
	return {"ok": true, "room_state": {
		"code": str(room.get("code", c)),
		"players": players_out,
		"host_id": int(room.get("host_id", 0)),
		"screen": str(room.get("screen", "lobby")),
	}}


## Synchronous self-test: creates exactly SELFTEST_ROOMS rooms, joins
## SELFTEST_PLAYERS total clients, and checks uniqueness, validity, the
## room_state shape, leave/rejoin, the full-room rejection, and the ready
## badge. Returns [passed, failed]; never awaits, never touches the tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	seed(12345)
	var ManagerScript = load("res://server/room_manager.gd")
	var mgr = ManagerScript.new()
	var codes: Array = []
	var host_ids: Array = []
	var creates_ok := true
	for i in range(SELFTEST_ROOMS):
		var created: Dictionary = mgr.create_room("Host%d" % (i + 1), "hash-%d" % (i + 1))
		if not bool(created.get("ok", false)):
			creates_ok = false
			break
		codes.append(str(created.get("code", "")))
		host_ids.append(int(created.get("player_id", 0)))
	if creates_ok and codes.size() == SELFTEST_ROOMS:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: expected %d room creates" % SELFTEST_ROOMS)
	var seen := {}
	for c in codes:
		seen[c] = true
	if seen.size() == SELFTEST_ROOMS:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: room codes collide: %s" % str(codes))
	var all_valid := true
	for c in codes:
		if not is_valid_code(c):
			all_valid = false
	if all_valid and codes.size() == SELFTEST_ROOMS:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: invalid room code shape: %s" % str(codes))
	var extra: Dictionary = mgr.join_room(codes[0], "Guest", "hash-guest")
	if bool(extra.get("ok", false)) and mgr.player_count() == SELFTEST_PLAYERS:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: expected %d total players" % SELFTEST_PLAYERS)
	var st: Dictionary = mgr.room_state(codes[0])
	var rs: Dictionary = st.get("room_state", {})
	if bool(st.get("ok", false)) and rs.has("players") and rs.has("host_id") and rs.has("screen"):
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: room_state misses {players, host_id, screen}")
	var shape_ok := true
	if (rs.get("players", []) as Array).size() != 2:
		shape_ok = false
	if str(rs.get("screen", "")) != "lobby":
		shape_ok = false
	if int(rs.get("host_id", 0)) != int(host_ids[0]):
		shape_ok = false
	if shape_ok:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: room_state shape mismatch %s" % str(rs))
	var guest_id := int(extra.get("player_id", 0))
	if bool(mgr.set_ready(codes[0], guest_id, true).get("ok", false)):
		var after: Dictionary = mgr.room_state(codes[0]).get("room_state", {})
		var badge := false
		for p in (after.get("players", []) as Array):
			if int((p as Dictionary).get("id", 0)) == guest_id and bool((p as Dictionary).get("ready", false)):
				badge = true
		if badge:
			passed += 1
		else:
			failed += 1
			push_error("rooms selftest: ready badge did not persist in room_state")
	else:
		failed += 1
		push_error("rooms selftest: set_ready rejected a member")
	var dup: Dictionary = mgr.join_room(codes[1], "Host2", "hash-dup-name")
	if bool(dup.get("ok", false)) and int(dup.get("player_id", 0)) != int(host_ids[1]):
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: duplicate display names must share-save accepted")
	var dup_id := int(dup.get("player_id", 0))
	if bool(mgr.leave_room(codes[1], dup_id).get("ok", false)) and mgr.player_count() == SELFTEST_PLAYERS:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: leave did not restore %d players" % SELFTEST_PLAYERS)
	if bool(mgr.leave_room(codes[0], guest_id).get("ok", false)):
		var re: Dictionary = mgr.join_room(codes[0], "Guest", "hash-guest")
		if bool(re.get("ok", false)) and mgr.player_count() == SELFTEST_PLAYERS:
			passed += 1
		else:
			failed += 1
			push_error("rooms selftest: rejoin did not restore %d players" % SELFTEST_PLAYERS)
		guest_id = int(re.get("player_id", 0))
	else:
		failed += 1
		push_error("rooms selftest: leave for rejoin failed")
	var fill_ok := true
	for i in range(ConfigScript.MAX_ROOM_PLAYERS - 1):
		var j: Dictionary = mgr.join_room(codes[2], "Filler%d" % i, "hash-f%d" % i)
		if not bool(j.get("ok", false)):
			fill_ok = false
	var overflow: Dictionary = mgr.join_room(codes[2], "Overflow", "hash-over")
	if fill_ok and not bool(overflow.get("ok", false)) and str(overflow.get("error", "")) == "room_full":
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: room past %d players must reject" % ConfigScript.MAX_ROOM_PLAYERS)
	var left: Dictionary = mgr.leave_room(codes[1], int(host_ids[1]))
	var st1: Dictionary = mgr.room_state(codes[1])
	if bool(left.get("ok", false)) and int((st1.get("room_state", {}) as Dictionary).get("host_id", 0)) != int(host_ids[1]):
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: host leave did not reassign host_id")
	var tmp: Dictionary = mgr.create_room("Temp", "hash-tmp")
	var tmp_code := str(tmp.get("code", ""))
	var tmp_gone := false
	if bool(tmp.get("ok", false)) and bool(mgr.leave_room(tmp_code, int(tmp.get("player_id", 0))).get("erased", false)):
		tmp_gone = not mgr.list_codes().has(tmp_code) and not bool(mgr.room_state(tmp_code).get("ok", false))
	if tmp_gone:
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: empty room was not erased")
	if not bool(mgr.join_room("BAD!", "X", "x").get("ok", false)) and not bool(mgr.join_room("ZZZZ", "X", "x").get("ok", false)):
		passed += 1
	else:
		failed += 1
		push_error("rooms selftest: malformed/unknown codes must fail closed")
	return [passed, failed]
