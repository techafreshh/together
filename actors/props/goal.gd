extends Area3D
## Goal volume (prop kit A): forwards body enter/exit to the owning stage
## scaffold. Holds no roster state itself — the stage requires ALL expected
## players inside before emitting the win. Every call is guarded so static
## bodies passing through never error.


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func _on_body_entered(body: Node) -> void:
	var stage := _find_stage("notify_goal_entered")
	if stage != null:
		stage.call("notify_goal_entered", body)


func _on_body_exited(body: Node) -> void:
	var stage := _find_stage("notify_goal_exited")
	if stage != null:
		stage.call("notify_goal_exited", body)


## Walks ancestors to the first node that owns the given stage goal hook.
func _find_stage(method: String) -> Node:
	var n := get_parent()
	while n != null:
		if n.has_method(method):
			return n
		n = n.get_parent()
	return null
