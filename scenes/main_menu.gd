extends Control
## Main menu screen (issue #19): name + room-code + color entry, host/join.
##
## Thin Control scene owned by the menu flow: validates the three fields and
## hands off to the lobby once the live net lap wires it. Runtime socket
## calls stay out of scope here; the guarded Net hooks below are the only
## contact point.
## Net. autoload placeholder: Net.connect_game / Net.is_game_connected drive host+join.

## Player colors from docs/palette.md (P1-P4 order).
const PLAYER_COLORS := ["#EF476F", "#118AB2", "#06D6A0", "#8338EC"]
const PLAYER_COLOR_NAMES := ["Coral", "Blue", "Leaf", "Grape"]

signal host_requested(player_name: String, color: String)
signal join_requested(player_name: String, code: String, color: String)


## Contract nodes the serve selftest and the unit runner assert on.
static func required_nodes() -> Array:
	return ["Title", "NameEdit", "CodeEdit", "ColorOption", "HostButton", "JoinButton"]


func _ready() -> void:
	var colors := get_node_or_null("ColorOption") as OptionButton
	if colors != null:
		if colors.item_count == 0:
			for i in range(PLAYER_COLOR_NAMES.size()):
				colors.add_item(str(PLAYER_COLOR_NAMES[i]), i)
		colors.selected = 0
	var host := get_node_or_null("HostButton") as Button
	if host != null:
		host.grab_focus()
		if not host.is_connected("pressed", _on_host_pressed):
			host.connect("pressed", _on_host_pressed)
	var join := get_node_or_null("JoinButton") as Button
	if join != null and not join.is_connected("pressed", _on_join_pressed):
		join.connect("pressed", _on_join_pressed)


func get_name_text() -> String:
	var edit := get_node_or_null("NameEdit") as LineEdit
	if edit == null:
		return ""
	return edit.text.strip_edges()


func get_code_text() -> String:
	var edit := get_node_or_null("CodeEdit") as LineEdit
	if edit == null:
		return ""
	return edit.text.strip_edges().to_upper()


func get_color_hex() -> String:
	var colors := get_node_or_null("ColorOption") as OptionButton
	if colors == null or colors.item_count == 0:
		return PLAYER_COLORS[0]
	return PLAYER_COLORS[posmod(colors.selected, PLAYER_COLORS.size())]


## Name must be non-empty; code is validated live by the rooms lobby.
func is_valid() -> bool:
	return get_name_text() != ""


func _on_host_pressed() -> void:
	_play_sfx("button")
	host_requested.emit(get_name_text(), get_color_hex())
	_net_host(get_name_text(), get_color_hex())


func _on_join_pressed() -> void:
	_play_sfx("button")
	join_requested.emit(get_name_text(), get_code_text(), get_color_hex())
	_net_join(get_name_text(), get_code_text(), get_color_hex())


## Guarded Net hook: creates a room through the Net autoload when present,
## silent otherwise so headless instantiation never errors.
func _net_host(player_name: String, color: String) -> void:
	if not is_inside_tree():
		return
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("connect_game"):
		net.call("connect_game")
		if net.has_method("create_room"):
			net.call("create_room", player_name, color)


## Guarded Net hook: joins a room through the Net autoload when present,
## silent otherwise so headless instantiation never errors.
func _net_join(player_name: String, code: String, color: String) -> void:
	if not is_inside_tree():
		return
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("connect_game"):
		net.call("connect_game")
		if net.has_method("join_room"):
			net.call("join_room", code, player_name, color)


## Guarded SFX hook: plays through the Sfx autoload when present, silent
## otherwise so scene instantiations without autoloads never error.
func _play_sfx(sfx_name: String) -> void:
	if not is_inside_tree():
		return
	var bus := get_node_or_null("/root/Sfx")
	if bus != null and bus.has_method("play"):
		bus.call("play", sfx_name)
