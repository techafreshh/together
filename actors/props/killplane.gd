extends Area3D
## Kill plane (issue #4): any CharacterBody that touches the volume flops
## and respawns at its last checkpoint. Calls are guarded by has_method so
## static bodies and props passing through never error.


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if body.has_method("kill"):
		body.call("kill")
	elif body.has_method("respawn"):
		body.call("respawn")
