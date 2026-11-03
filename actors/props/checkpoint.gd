extends Area3D
## Checkpoint volume (prop kit A): detects bodies and forwards them to the
## owning stage scaffold plus the player respawn hook. All calls are guarded
## so static bodies passing through never error; the stage owns all state.


## Registry id the stage uses to match this volume (`cp1`, `cp2`, ...).
@export var checkpoint_id: String = "cp1"


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	var stage := _find_stage()
	if stage != null and stage.has_method("notify_checkpoint"):
		stage.call("notify_checkpoint", checkpoint_id, body)
	if body != null and body.has_method("set_checkpoint"):
		body.call("set_checkpoint", global_position)


## Walks ancestors to the first node that owns the stage checkpoint hook.
func _find_stage() -> Node:
	var n := get_parent()
	while n != null:
		if n.has_method("notify_checkpoint"):
			return n
		n = n.get_parent()
	return null
