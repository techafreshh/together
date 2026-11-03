extends Control
## Lobby screen (issue #19): player list with ready badges, host stage
## picker with personal bests, lobby-wait gate for late joiners.
##
## Thin Control scene fed by RoomManager.room_state ({code, players[],
## host_id, screen}) and FlowManager.build_results ({clears, bests,
## coins_awarded}). Player entries carry {id, name, color, ready}; the host
## entry gets a crown prefix. Runtime socket broadcast stays out of scope.
## Net. autoload placeholder: Net.room_state pushes refresh / Net.push_snapshots gates start.

signal ready_toggled(ready: bool)
signal start_requested(stage_id: String)

## Mid-stage join gate (issue #12): shown while the stage_boot run owns
## the room and the joiner waits for the next stage_boot.
const LOBBY_WAIT_TEXT := "lobby_wait — stage in progress, waiting for next stage_boot"

var _ready_local := false


## Contract nodes the serve selftest and the unit runner assert on.
static func required_nodes() -> Array:
	return ["PlayerList", "ReadyButton", "StartButton", "StagePicker", "BestsLabel", "StatusLabel"]


func _ready() -> void:
	var ready := get_node_or_null("ReadyButton") as Button
	if ready != null:
		ready.grab_focus()
		if not ready.is_connected("pressed", _on_ready_pressed):
			ready.connect("pressed", _on_ready_pressed)
	var start := get_node_or_null("StartButton") as Button
	if start != null and not start.is_connected("pressed", _on_start_pressed):
		start.connect("pressed", _on_start_pressed)


## Rebuilds the PlayerList rows as "<name> [READY]" / "<name>" badges from
## room_state player entries ({id, name, color, ready}), with a crown on
## the host_id entry. Unknown shapes clear the list without erroring.
func refresh(room_state: Dictionary) -> void:
	var list := get_node_or_null("PlayerList")
	if list == null:
		return
	for child in list.get_children():
		list.remove_child(child)
		child.free()
	var players: Array = room_state.get("players", []) as Array
	var host_id := int(room_state.get("host_id", 0))
	for p in players:
		if not (p is Dictionary):
			continue
		var entry: Dictionary = p
		var label := Label.new()
		var text := str(entry.get("name", ""))
		if int(entry.get("id", 0)) == host_id and host_id != 0:
			text = "[HOST] " + text
		if bool(entry.get("ready", false)):
			text += " [READY]"
		label.text = text
		var tint := str(entry.get("color", ""))
		if tint != "":
			label.modulate = Color.html(tint)
		list.add_child(label)


## Shows the lobby_wait gate text while a stage run owns the room; clears
## it otherwise. Late joiners see this until the next stage_boot.
func show_lobby_wait(active: bool) -> void:
	var status := get_node_or_null("StatusLabel") as Label
	if status == null:
		return
	status.text = LOBBY_WAIT_TEXT if bool(active) else ""


## Fills the host stage picker with catalog stage ids (w1s1..w1s8).
func set_stage_options(stages: Array) -> void:
	var picker := get_node_or_null("StagePicker") as OptionButton
	if picker == null:
		return
	picker.clear()
	for s in stages:
		picker.add_item(str(s))
	if picker.item_count > 0:
		picker.selected = 0


## Renders "w1s1: 100c" personal-best lines in BestsLabel from the
## build_results bests/clears shape; empty input clears the label.
func set_bests(bests: Dictionary) -> void:
	var label := get_node_or_null("BestsLabel") as Label
	if label == null:
		return
	if bests.is_empty():
		label.text = ""
		return
	var lines: Array = []
	var keys: Array = bests.keys()
	keys.sort()
	for k in keys:
		lines.append("%s: %sc" % [str(k), str(bests[k])])
	label.text = "\n".join(lines)


## Currently picked stage id; "" when the picker is empty.
func selected_stage() -> String:
	var picker := get_node_or_null("StagePicker") as OptionButton
	if picker == null or picker.item_count == 0:
		return ""
	return picker.get_item_text(picker.selected)


func _on_ready_pressed() -> void:
	_play_sfx("button")
	_ready_local = not _ready_local
	ready_toggled.emit(_ready_local)
	_net_set_ready(_ready_local)


func _on_start_pressed() -> void:
	_play_sfx("button")
	start_requested.emit(selected_stage())
	_net_start(selected_stage())


## Guarded Net hook: ready badge through the Net autoload when present.
func _net_set_ready(ready: bool) -> void:
	if not is_inside_tree():
		return
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("set_ready"):
		net.call("set_ready", ready)


## Guarded Net hook: stage start through the Net autoload when present.
func _net_start(stage_id: String) -> void:
	if not is_inside_tree():
		return
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("start_stage"):
		net.call("start_stage", stage_id)


## Guarded SFX hook: plays through the Sfx autoload when present, silent
## otherwise so scene instantiations without autoloads never error.
func _play_sfx(sfx_name: String) -> void:
	if not is_inside_tree():
		return
	var bus := get_node_or_null("/root/Sfx")
	if bus != null and bus.has_method("play"):
		bus.call("play", sfx_name)
