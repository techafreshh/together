extends Control
## In-stage HUD (issue #19): room code, objective, carry hint.
##
## Thin Control overlay fed by the stage flow: set_room_code shows the
## 4-char room code, set_objective names the current goal, set_carry_hint
## coaches the grab-carry-throw verb. No sockets here.
## Net. autoload placeholder: Net.push_snapshots drives room/objective refresh.

## Default carry coaching shown until the stage overrides it.
const DEFAULT_CARRY_HINT := "Carry together — grab, slowed walk, throw across"


## Contract nodes the serve selftest and the unit runner assert on.
static func required_nodes() -> Array:
	return ["RoomCodeLabel", "ObjectiveLabel", "CarryHint"]


func _ready() -> void:
	var hint := get_node_or_null("CarryHint") as Label
	if hint != null and hint.text.strip_edges() == "":
		hint.text = DEFAULT_CARRY_HINT


func set_room_code(code: String) -> void:
	var label := get_node_or_null("RoomCodeLabel") as Label
	if label != null:
		label.text = str(code).strip_edges().to_upper()


func set_objective(text: String) -> void:
	var label := get_node_or_null("ObjectiveLabel") as Label
	if label != null:
		label.text = str(text)


func set_carry_hint(text: String) -> void:
	var label := get_node_or_null("CarryHint") as Label
	if label != null:
		label.text = str(text) if str(text) != "" else DEFAULT_CARRY_HINT
