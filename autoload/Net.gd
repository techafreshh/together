extends Node
## Client net autoload (issue #9): prediction + interpolation + reconcile.
##
## Owns the client-side `WebSocketMultiplayerPeer` game connection,
## uplinks `input_state` dicts at 30 Hz over an unreliable RPC, and keeps
## the last two authoritative `snapshots` dicts for interpolation. The owned
## avatar is predicted locally every frame (predict_position) and snapped
## or lerped onto the server truth when it arrives (reconcile_position);
## remote avatars render between the two stored snapshots (interp_position).
## All helpers that touch no tree state are statics, unit-tested with no
## sockets. Every socket path soft-fails: disconnects reset to offline,
## sends while offline are dropped, never an error.

const NetServer := preload("res://server/net_server.gd")
const Tuning := preload("res://actors/player/tuning.gd")

const SEND_HZ := 30.0

var peer: WebSocketMultiplayerPeer
var connected_url := ""
## Last two authoritative snapshots dicts (ring for interpolation).
var last_snap: Dictionary = {}
var prev_snap: Dictionary = {}
var send_accum := 0.0
var _send_tick := 0


## --- Prediction / interpolation / reconcile (pure statics) ---


## Advances a position by one input step: the same wish-vector * move_speed
## rule the server sim applies, so local prediction tracks authority.
static func predict_position(pos: Vector3, input_move: Vector2, dt: float) -> Vector3:
	return pos + Vector3(input_move.x, 0.0, input_move.y) * Tuning.move_speed * dt


## Blends between two snapshot positions; t is clamped to [0, 1].
static func interp_position(a: Vector3, b: Vector3, t: float) -> Vector3:
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Merges prediction with server truth: snaps when the error exceeds the
## teleport clamp (impossible state), otherwise lerps halfway (soft
## correction that avoids visible pops on normal latency).
static func reconcile_position(predicted: Vector3, authoritative: Vector3) -> Vector3:
	if predicted.distance_to(authoritative) > NetServer.TELEPORT_CLAMP_M:
		return authoritative
	return predicted.lerp(authoritative, 0.5)


## --- Connection ---


## Opens the game socket to url (default loopback game port). Returns OK on
## connect-call success; the link itself completes asynchronously.
func connect_game(url: String = "") -> int:
	var target := url.strip_edges()
	if target == "":
		target = "ws://127.0.0.1:8081/ws"
	disconnect_game()
	var sock := WebSocketMultiplayerPeer.new()
	var err := sock.create_client(target)
	if err != OK:
		push_warning("net: game connect to %s failed (error %d)" % [target, err])
		return err
	peer = sock
	connected_url = target
	if is_inside_tree():
		multiplayer.multiplayer_peer = peer
	return OK


## Drops the game socket and resets to offline. Safe to call disconnected.
func disconnect_game() -> void:
	var old: WebSocketMultiplayerPeer = peer
	peer = null
	connected_url = ""
	last_snap = {}
	prev_snap = {}
	send_accum = 0.0
	if old != null:
		old.close()
	if is_inside_tree() and old != null and multiplayer.multiplayer_peer == old:
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## True while the game socket is connected.
func is_game_connected() -> bool:
	return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED


## Unreliable input_state uplink to the server (peer id 1) on this same
## node path. Dropped silently while offline.
func send_input_state(state: Dictionary) -> void:
	if not is_game_connected() or not is_inside_tree():
		return
	rpc_id(1, "submit_input_state", state)


## Interpolated position of a remote peer between the two stored snapshots
## at blend alpha; returns null while either snapshot lacks the peer.
func remote_position(peer_id: int, alpha: float) -> Variant:
	var a: Variant = _snap_pos(prev_snap, peer_id)
	var b: Variant = _snap_pos(last_snap, peer_id)
	if a == null or b == null:
		return null
	return interp_position(a, b, alpha)


static func _snap_pos(snap: Dictionary, peer_id: int) -> Variant:
	var peers: Dictionary = snap.get("peers", {})
	for key in [peer_id, str(peer_id)]:
		if peers.has(key):
			var entry: Dictionary = peers[key]
			var arr: Array = entry.get("p", [])
			if arr.size() >= 3:
				return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return null


func _process(delta: float) -> void:
	if not is_game_connected():
		return
	send_accum += delta
	var step := 1.0 / SEND_HZ
	if send_accum < step:
		return
	send_accum = 0.0
	_send_tick += 1
	var move := Vector2.ZERO
	if InputMap.has_action("move_left") and InputMap.has_action("move_right") and InputMap.has_action("move_forward") and InputMap.has_action("move_back"):
		move = Vector2(
			Input.get_axis("move_left", "move_right"),
			Input.get_axis("move_forward", "move_back")
		)
	var jump := false
	if InputMap.has_action("jump"):
		jump = Input.is_action_pressed("jump")
	send_input_state(NetServer.make_input_state(_send_tick, move, jump))


## input_state inbox on the shared autoload path: only the server acts, by
## relaying into the NetServer child of the current scene with the true
## sender id attached. Clients ignore inbound input.
@rpc("any_peer", "call_remote", "unreliable")
func submit_input_state(state: Dictionary) -> void:
	if not is_inside_tree() or not multiplayer.is_server():
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var srv := scene.get_node_or_null("NetServer")
	if srv != null and srv.has_method("store_remote_input"):
		srv.call("store_remote_input", multiplayer.get_remote_sender_id(), state)


## snapshots downlink: authority broadcast stored into the two-deep ring
## that remote_position interpolates between.
@rpc("authority", "call_local", "unreliable")
func push_snapshots(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	prev_snap = last_snap
	last_snap = snap
