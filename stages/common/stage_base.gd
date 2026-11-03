extends Node3D
## Shared stage scaffold (prop kit A): declarative composition root for every
## stage. Owns the spawn list, the checkpoint registry, the goal roster, and
## the kill-plane volume. Prop scenes only detect bodies and make guarded
## direct calls into `notify_*`; server-authoritative hooks stay stubbed as
## direct calls per the issue notes. The goal requires ALL expected players
## inside at once before the win fires.

signal checkpoint_reached(checkpoint_id, player)
signal goal_reached(player)
signal goal_all_reached

## Kill-plane depth on Y: falling below this flops + respawns the player.
const KILL_Y := -10.0
## Default roster size the goal waits for; mirrors `expected_players`.
const EXPECTED_DEFAULT := 2

## How many players must stand in the goal at once for the win to fire.
@export var expected_players: int = 2

## Instance ids of bodies currently inside the goal volume (deduped).
var _goal_inside: Array = []


func _ready() -> void:
	var kill: Node = get_node_or_null("KillPlane")
	if kill != null and kill.has_signal("body_entered"):
		if not kill.is_connected("body_entered", _on_kill_body):
			kill.connect("body_entered", _on_kill_body)


## Kill-plane forwarder: flop the body, falling back to a plain respawn.
## Guarded by has_method so static bodies passing through never error.
func _on_kill_body(body: Node) -> void:
	if body == null:
		return
	if body.has_method("kill"):
		body.call("kill")
	elif body.has_method("respawn"):
		body.call("respawn")


## Ordered spawn markers (Spawn1..Spawn4) for roster placement.
func get_spawn_points() -> Array:
	var out: Array = []
	for i in range(1, 5):
		var n := get_node_or_null("Spawn%d" % i)
		if n != null:
			out.append(n)
	return out


## Spawn marker by index, wrapped so any roster slot maps to a marker.
func get_spawn_point(index: int) -> Node3D:
	var pts := get_spawn_points()
	if pts.is_empty():
		return null
	return pts[posmod(index, pts.size())] as Node3D


## Checkpoint volumes registered under the `Checkpoints` holder.
func get_checkpoints() -> Array:
	var holder := get_node_or_null("Checkpoints")
	if holder == null:
		return []
	return holder.get_children()


## Checkpoint volumes call this (guarded direct call, no networking yet).
## Emits checkpoint_reached and stubs the respawn-point hook on the player.
func notify_checkpoint(checkpoint_id: String, player: Node) -> void:
	checkpoint_reached.emit(checkpoint_id, player)
	if player != null and player.has_method("set_checkpoint"):
		var pos := global_position
		for c in get_checkpoints():
			if c != null and c.get("checkpoint_id") == checkpoint_id and c is Node3D:
				pos = (c as Node3D).global_position
				break
		player.call("set_checkpoint", pos)


## Goal volumes call this on enter; deduped by instance id. Emits
## goal_reached per arrival and goal_all_reached once the full roster is in.
func notify_goal_entered(player: Node) -> void:
	if player == null:
		return
	var id := player.get_instance_id()
	if _goal_inside.has(id):
		return
	_goal_inside.append(id)
	goal_reached.emit(player)
	if goal_count() >= expected_players:
		goal_all_reached.emit()


## Goal volumes call this on exit; completion breaks until all return.
func notify_goal_exited(player: Node) -> void:
	if player == null:
		return
	_goal_inside.erase(player.get_instance_id())


## How many distinct bodies are currently inside the goal volume.
func goal_count() -> int:
	return _goal_inside.size()


## True while the full expected roster stands in the goal.
func is_goal_complete() -> bool:
	return goal_count() >= expected_players


## Authoritative y-position kill check: fast falls can tunnel past the
## Area3D volume in one physics step, so depth below KILL_Y always kills.
static func is_below_kill(pos: Vector3) -> bool:
	return pos.y < KILL_Y


## Roster size the pass-path selftest proves inside the goal at once.
static func scaffold_goal_count() -> int:
	return EXPECTED_DEFAULT


## Synchronous scaffold self-test: instantiates the stage scene, asserts the
## spawn list, checkpoint registry, kill-plane depth, and goal node, then
## drives two plain-Node dummies through enter/duplicate/exit/checkpoint
## paths. Returns [passed, failed]; never awaits, needs no physics frames.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	var packed: PackedScene = load("res://stages/common/stage_base.tscn") as PackedScene
	if packed == null:
		failed += 1
		push_error("scaffold selftest: stage_base.tscn failed to load")
		return [passed, failed]
	var stage: Node = packed.instantiate() as Node
	if stage == null:
		failed += 1
		push_error("scaffold selftest: stage_base.tscn failed to instantiate")
		return [passed, failed]
	var spawns: Array = stage.call("get_spawn_points") as Array
	if spawns.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: expected 4 spawns, got %d" % spawns.size())
	var first: Node = stage.call("get_spawn_point", 0) as Node
	var wrapped: Node = stage.call("get_spawn_point", 4) as Node
	if first != null and first == wrapped:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: spawn index must wrap")
	var cps: Array = stage.call("get_checkpoints") as Array
	if cps.size() >= 1:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: expected at least 1 checkpoint, got %d" % cps.size())
	var kill := (stage.get_node_or_null("KillPlane") as Node3D)
	if kill != null and absf(kill.position.y - KILL_Y) < 0.01 and KILL_Y == -10.0:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: KillPlane must sit at KILL_Y == -10.0")
	if stage.get_node_or_null("Goal") != null:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: Goal node missing")
	var checkpoint_hits := [0]
	stage.connect("checkpoint_reached", func(_id, _p): checkpoint_hits[0] += 1)
	var all_hits := [0]
	stage.connect("goal_all_reached", func(): all_hits[0] += 1)
	var dummy_a := Node.new()
	var dummy_b := Node.new()
	stage.call("notify_checkpoint", "cp1", dummy_a)
	if checkpoint_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: checkpoint must emit checkpoint_reached once")
	stage.call("notify_goal_entered", dummy_a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: one player in goal must be incomplete")
	stage.call("notify_goal_entered", dummy_a)
	if int(stage.call("goal_count")) == 1:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: duplicate goal enter must not double-count")
	stage.call("notify_goal_entered", dummy_b)
	if int(stage.call("goal_count")) == 2 and bool(stage.call("is_goal_complete")) and all_hits[0] == 1:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: both players in goal must complete with goal_all_reached")
	stage.call("notify_goal_exited", dummy_a)
	if int(stage.call("goal_count")) == 1 and not bool(stage.call("is_goal_complete")):
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: goal exit must break completion")
	if scaffold_goal_count() == EXPECTED_DEFAULT and scaffold_goal_count() == 2:
		passed += 1
	else:
		failed += 1
		push_error("scaffold selftest: scaffold_goal_count() must be 2")
	dummy_a.free()
	dummy_b.free()
	stage.free()
	return [passed, failed]
