extends RefCounted
## Cosmetic attach helpers (issue #18): hat instancing under HatAnchor and
## palette tinting on the body MeshInstance3D.
##
## Thin, guarded statics over the wardrobe catalog: no sockets, no state.
## All entry points tolerate null players and missing anchors (returning
## false / ""), so headless probes and unit runners never error.

const Wardrobe := preload("res://server/wardrobe.gd")


## Clears HatAnchor children and instances the hat scene for `hat_id`.
## Empty `hat_id` just clears. Returns false for null players, missing
## anchors, and unknown hats; never errors.
static func attach_hat(player: Node, hat_id: String) -> bool:
	if player == null:
		return false
	var anchor: Node = player.get_node_or_null("HatAnchor")
	if anchor == null:
		return false
	for child in anchor.get_children():
		anchor.remove_child(child)
		child.free()
	var hid := str(hat_id).strip_edges()
	if hid == "":
		return true
	if not Wardrobe.is_valid_hat(hid):
		return false
	var packed: PackedScene = load(Wardrobe.hat_scene_path(hid)) as PackedScene
	if packed == null or not packed.can_instantiate():
		return false
	var hat: Node = packed.instantiate() as Node
	if hat == null:
		return false
	anchor.add_child(hat)
	if hat is Node3D:
		(hat as Node3D).position = Vector3.ZERO
	hat.set("visible", true)
	return true


## Tints the body MeshInstance3D with `skin_id_or_hex`: either a catalog
## skin id ("charcoal") resolved through the on-disk .cfg, or a literal
## "#RRGGBB" hex. Records the resolved value in the `skin` meta for
## current_skin. Returns false for null players, missing bodies, and bad
## colors; never errors.
static func apply_skin(player: Node, skin_id_or_hex: String) -> bool:
	if player == null:
		return false
	var body: MeshInstance3D = player.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if body == null:
		return false
	var want := str(skin_id_or_hex).strip_edges()
	if want == "":
		return false
	var hex := ""
	if Wardrobe.is_valid_skin(want):
		hex = Wardrobe.skin_hex(want)
	elif want.begins_with("#"):
		hex = want
	else:
		return false
	if hex == "":
		return false
	var albedo := Color.html(hex)
	if albedo == null:
		return false
	var mat := StandardMaterial3D.new()
	mat.albedo_color = albedo
	body.material_override = mat
	player.set_meta("skin", want)
	return true


## True when HatAnchor carries at least one visible child.
static func is_hat_visible(player: Node) -> bool:
	if player == null:
		return false
	var anchor: Node = player.get_node_or_null("HatAnchor")
	if anchor == null:
		return false
	for child in anchor.get_children():
		if child is Node3D and bool(child.get("visible")):
			return true
	return false


## Last skin applied via apply_skin (id or hex); "" when none.
static func current_skin(player: Node) -> String:
	if player == null:
		return ""
	if player.has_meta("skin"):
		return str(player.get_meta("skin"))
	return ""
