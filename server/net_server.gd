extends Node
## Authoritative WebSocket game sim (issue #9 net stack).
##
## The headless server keeps a live `WebSocketMultiplayerPeer` game socket
## (bound in start_game_socket, default serve-port + 1) next to the
## hand-rolled TCPServer front door in serve.gd, which still owns plain-HTTP
## health (`GET /`) and the raw `/ws` 101 upgrade. This node ticks the
## simulation at TICK_HZ, receives per-client `input_state` dicts over an
## unreliable any_peer RPC, and broadcasts authoritative `snapshots` dicts
## over an unreliable authority RPC. Sanity clamps are soft only: over-speed
## input is capped, impossible teleports are snapped back, join floods are
## ignored — no kicks, bans, or 5xx anywhere.
##
## input_state shape: {"tick": int, "move": [x, y], "jump": bool}
## snapshots shape:   {"tick": int, "peers": {id: {"p": [x,y,z], "v": [x,y,z]}}}
##
## Parsing-adjacent helpers (make_input_state, make_snapshot, clamps,
## is_join_allowed, simulate_step) are stateless static funcs so the
## headless `--selftest net` branch and the unit runner exercise them with
## no sockets and no awaits.

const Tuning := preload("res://actors/player/tuning.gd")

const TICK_HZ := 30
const MAX_PEERS := 4
const JOIN_COOLDOWN_MSEC := 2000
const SPEED_FACTOR := 1.25
const TELEPORT_CLAMP_M := 5.0
const SELFTEST_TICKS := 60
const SELFTEST_PEERS := 2

## Live game socket. Null until start_game_socket binds it successfully.
var peer: WebSocketMultiplayerPeer
var _states: Dictionary = {}
var _inputs: Dictionary = {}
## Equipped look per peer id ({hat, skin} subset); replicated as the
## optional `cos` field inside make_snapshot peer entries (issue #18).
var _cosmetics: Dictionary = {}
var _tick: int = 0
var _accum: float = 0.0
var _join_msec_by_key: Dictionary = {}


## --- Stateless sim core (unit-tested, no sockets) ---


## Builds one client input_state dict for the given tick.
static func make_input_state(tick: int, move: Vector2, jump: bool) -> Dictionary:
	return {"tick": tick, "move": [move.x, move.y], "jump": jump}


## Builds one authoritative snapshots dict from sim states.
## states: {id: {"p": Vector3, "v": Vector3}}.
## cosmetics: {id: {"hat": String, "skin": String}}; each peer entry gains
## an optional `cos` {hat, skin} only when set, so old two-arg callers keep
## their exact {p, v} byte-shape.
static func make_snapshot(tick: int, states: Dictionary, cosmetics: Dictionary = {}) -> Dictionary:
	var peers := {}
	for id in states.keys():
		var entry: Dictionary = states[id]
		var p: Vector3 = entry.get("p", Vector3.ZERO)
		var v: Vector3 = entry.get("v", Vector3.ZERO)
		peers[id] = {"p": [p.x, p.y, p.z], "v": [v.x, v.y, v.z]}
		if cosmetics.has(id) and cosmetics[id] is Dictionary and not (cosmetics[id] as Dictionary).is_empty():
			peers[id]["cos"] = (cosmetics[id] as Dictionary).duplicate(true)
	return {"tick": tick, "peers": peers}


## Caps horizontal speed to move_speed * SPEED_FACTOR and vertical speed to
## +-max_fall_speed. Returns the clamped vector; peers stay connected.
static func clamp_velocity(v: Vector3) -> Vector3:
	var max_h: float = Tuning.move_speed * SPEED_FACTOR
	var flat := Vector2(v.x, v.z)
	if flat.length() > max_h:
		flat = flat.normalized() * max_h
	var vy := clampf(v.y, -Tuning.max_fall_speed, Tuning.max_fall_speed)
	return Vector3(flat.x, vy, flat.y)


## Snaps an impossible per-snapshot jump back to TELEPORT_CLAMP_M metres.
static func clamp_teleport(old_p: Vector3, new_p: Vector3) -> Vector3:
	var d := new_p - old_p
	if d.length() > TELEPORT_CLAMP_M:
		return old_p + d.normalized() * TELEPORT_CLAMP_M
	return new_p


## Join flood gate: the first join (last_msec < 0) is always allowed, later
## joins need JOIN_COOLDOWN_MSEC to have passed. Never bans, just defers.
static func is_join_allowed(last_msec: int, now_msec: int) -> bool:
	if last_msec < 0:
		return true
	return (now_msec - last_msec) >= JOIN_COOLDOWN_MSEC


## Advances every avatar by its clamped input vector * move_speed for dt.
## Reads inputs (input_state dicts keyed by peer id), writes states in
## place ({id: {"p": Vector3, "v": Vector3}}) and returns them.
static func simulate_step(states: Dictionary, inputs: Dictionary, dt: float) -> Dictionary:
	var ids := {}
	for id in states.keys():
		ids[id] = true
	for id in inputs.keys():
		ids[id] = true
	for id in ids.keys():
		var entry: Dictionary = states.get(id, {"p": Vector3.ZERO, "v": Vector3.ZERO})
		var old_p: Vector3 = entry.get("p", Vector3.ZERO)
		var move := Vector2.ZERO
		if inputs.has(id):
			var st: Dictionary = inputs[id]
			var m: Variant = st.get("move", [0.0, 0.0])
			if m is Vector2:
				move = m
			elif m is Array and m.size() >= 2:
				move = Vector2(float(m[0]), float(m[1]))
		var wish := Vector3(move.x, 0.0, move.y)
		if wish.length() > 1.0:
			wish = wish.normalized()
		var vel: Vector3 = clamp_velocity(wish * Tuning.move_speed)
		var new_p: Vector3 = clamp_teleport(old_p, old_p + vel * dt)
		states[id] = {"p": new_p, "v": vel}
	return states


## Synchronous self-test: two virtual peers through SELFTEST_TICKS fixed
## ticks asserting tick monotonicity, clamp enforcement, and snapshot
## round-trip. Returns [passed, failed]; never awaits, never touches
## sockets or the scene tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var states := {
		1: {"p": Vector3.ZERO, "v": Vector3.ZERO},
		2: {"p": Vector3.ZERO, "v": Vector3.ZERO},
	}
	var snapshots_ok := true
	for t in range(1, SELFTEST_TICKS + 1):
		var inputs := {
			1: make_input_state(t, Vector2(1.0, 0.0), false),
			2: make_input_state(t, Vector2(0.0, 1.0), t % 2 == 0),
		}
		simulate_step(states, inputs, 1.0 / float(TICK_HZ))
		var snap := make_snapshot(t, states)
		if int(snap.get("tick", 0)) != t:
			snapshots_ok = false
		if (snap.get("peers", {}) as Dictionary).size() != SELFTEST_PEERS:
			snapshots_ok = false
	if snapshots_ok:
		passed += 1
	else:
		failed += 1
		push_error("net selftest: snapshot tick/peer stream broke over %d ticks" % SELFTEST_TICKS)
	var p1: Vector3 = (states[1] as Dictionary).get("p", Vector3.ZERO)
	var p2: Vector3 = (states[2] as Dictionary).get("p", Vector3.ZERO)
	if p1.x > 0.0 and p2.z > 0.0:
		passed += 1
	else:
		failed += 1
		push_error("net selftest: avatars did not advance along their inputs")
	var fast := clamp_velocity(Vector3(100.0, 0.0, 0.0))
	if Vector2(fast.x, fast.z).length() <= Tuning.move_speed * SPEED_FACTOR + 0.001:
		passed += 1
	else:
		failed += 1
		push_error("net selftest: speed clamp failed on 100 m/s input")
	var snapped := clamp_teleport(Vector3.ZERO, Vector3(50.0, 0.0, 0.0))
	if snapped.distance_to(Vector3.ZERO) <= TELEPORT_CLAMP_M + 0.001:
		passed += 1
	else:
		failed += 1
		push_error("net selftest: teleport clamp failed on 50 m jump")
	if is_join_allowed(-1, 0) and not is_join_allowed(1000, 1500) and is_join_allowed(1000, 3000):
		passed += 1
	else:
		failed += 1
		push_error("net selftest: join cooldown gate misbehaves")
	var probe := make_input_state(9, Vector2(0.5, -0.25), true)
	if int(probe.get("tick", 0)) == 9 and (probe.get("move", []) as Array) == [0.5, -0.25] and bool(probe.get("jump", false)):
		passed += 1
	else:
		failed += 1
		push_error("net selftest: input_state round-trip mismatch %s" % str(probe))
	return [passed, failed]


## --- Live socket (soft-fail: warnings only, never quit, never 500) ---


## Binds the WebSocketMultiplayerPeer game socket. Returns OK on success,
## the bind error otherwise; a bind failure only warns so health can never
## regress. WebSocket create_server takes no max-client count, so the
## MAX_PEERS table cap is enforced when avatars register.
func start_game_socket(port: int) -> int:
	stop_game_socket()
	var sock := WebSocketMultiplayerPeer.new()
	var err := sock.create_server(port)
	if err != OK:
		push_warning("net_server: game socket bind on port %d failed (error %d)" % [port, err])
		return err
	peer = sock
	if is_inside_tree():
		multiplayer.multiplayer_peer = peer
		if not peer.peer_connected.is_connected(_on_game_peer_connected):
			peer.peer_connected.connect(_on_game_peer_connected)
		if not peer.peer_disconnected.is_connected(_on_game_peer_disconnected):
			peer.peer_disconnected.connect(_on_game_peer_disconnected)
	return OK


## Closes the game socket and clears sim state. Safe to call unbound.
func stop_game_socket() -> void:
	if peer != null:
		if peer.peer_connected.is_connected(_on_game_peer_connected):
			peer.peer_connected.disconnect(_on_game_peer_connected)
		if peer.peer_disconnected.is_connected(_on_game_peer_disconnected):
			peer.peer_disconnected.disconnect(_on_game_peer_disconnected)
		peer.close()
		peer = null
	if is_inside_tree() and multiplayer.multiplayer_peer != null and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	_states.clear()
	_inputs.clear()
	_cosmetics.clear()
	_tick = 0
	_accum = 0.0


func _process(delta: float) -> void:
	if peer == null or not is_inside_tree():
		return
	if multiplayer.multiplayer_peer != peer:
		return
	_accum += delta
	var step := 1.0 / float(TICK_HZ)
	var guard := 0
	while _accum >= step and guard < 5:
		_accum -= step
		guard += 1
		step_tick(step)


## Records the equipped look replicated inside snapshots for `peer_id`.
## Empty dicts clear the entry (the peer renders the default look).
func set_cosmetic(peer_id: int, equipped: Dictionary) -> void:
	if peer_id <= 0:
		return
	if equipped.is_empty():
		_cosmetics.erase(peer_id)
	else:
		_cosmetics[peer_id] = equipped.duplicate(true)


## Equipped look stored for `peer_id`; {} when unset.
func cosmetic_for(peer_id: int) -> Dictionary:
	if _cosmetics.has(peer_id) and _cosmetics[peer_id] is Dictionary:
		return (_cosmetics[peer_id] as Dictionary).duplicate(true)
	return {}


## Advances the authoritative tick once and broadcasts snapshots.
func step_tick(dt: float) -> Dictionary:
	_tick += 1
	_states = simulate_step(_states, _inputs, dt)
	var snap := make_snapshot(_tick, _states, _cosmetics)
	_broadcast_snapshots(snap)
	return snap


## Single broadcast via the shared /root/Net autoload path, which is the
## stable node path browser clients run. The NetServer node path exists
## only on the --serve host, so a same-path rpc could never land on a
## client tree; the relay below is the only broadcast. Guarded so a
## missing bus never errors.
func _broadcast_snapshots(snap: Dictionary) -> void:
	if peer == null or not is_inside_tree():
		return
	var bus := get_node_or_null("/root/Net")
	if bus != null and bus.has_method("push_snapshots"):
		bus.rpc("push_snapshots", snap)


## Stores one remote input_state under its sender id. Shared by the RPC
## below and by the Net autoload relay. Only peers registered via
## _on_game_peer_connected (which enforces the per-IP join cooldown and
## the table cap) may uplink: unknown sender ids — including peers
## rejected for flood — are dropped, so a rejected transport cannot
## re-enter the sim in one input packet. Updates from registered peers
## are always accepted.
func store_remote_input(sender_id: int, state: Dictionary) -> void:
	if sender_id <= 0:
		return
	if not _states.has(sender_id):
		return
	_inputs[sender_id] = state


## input_state uplink: any peer may send unreliably; only the server stores.
@rpc("any_peer", "call_local", "unreliable")
func submit_input_state(state: Dictionary) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	store_remote_input(multiplayer.get_remote_sender_id(), state)


## snapshots downlink: authority broadcast, received on the client Net bus.
@rpc("authority", "call_local", "unreliable")
func push_snapshots(_snap: Dictionary) -> void:
	pass


func _on_game_peer_connected(id: int) -> void:
	var key := str(id)
	if peer != null:
		var addr: Variant = peer.call("get_peer_address", id)
		if addr != null and str(addr) != "":
			key = str(addr)
	var now := int(Time.get_ticks_msec())
	var last := int(_join_msec_by_key.get(key, -1))
	if not is_join_allowed(last, now):
		_states.erase(id)
		_inputs.erase(id)
		if peer != null:
			peer.disconnect_peer(id)
		return
	_join_msec_by_key[key] = now
	if _states.size() < MAX_PEERS and not _states.has(id):
		_states[id] = {"p": Vector3.ZERO, "v": Vector3.ZERO}


func _on_game_peer_disconnected(id: int) -> void:
	_states.erase(id)
	_inputs.erase(id)
	_cosmetics.erase(id)
