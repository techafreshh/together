extends Node3D
## Wardrobe showroom (issue #19 UI side): hat + skin preview stand.
##
## Node3D showroom for the menu flow: preview_hat instances an on-disk hat
## scene under HatAnchor, preview_skin tints SkinPreview. The economy
## (prices, ownership, persistence) stays owned by server/wardrobe.gd; this
## script never prices, never persists.
## Net. autoload placeholder: Net.cosmetic_for echoes equipped hat+skin into snapshots.

## Fallback hexes mirroring docs/palette.md wardrobe skins; skin_cfg hexes
## on disk stay the source of truth where present.
const SKIN_HEXES := {
	"charcoal": "#2B2D42",
	"mint": "#B8F2E6",
	"sunset": "#FF9F1C",
	"bubblegum": "#FF70A6",
}


## Contract nodes the serve selftest and the unit runner assert on.
static func required_nodes() -> Array:
	return ["HatAnchor", "SkinPreview"]


## Clears HatAnchor children and instances the hat scene for `hat_id`.
## Empty `hat_id` just clears. Returns false for missing anchors and
## unknown hats; never errors.
func preview_hat(hat_id: String) -> bool:
	var anchor: Node = get_node_or_null("HatAnchor")
	if anchor == null:
		return false
	for child in anchor.get_children():
		anchor.remove_child(child)
		child.free()
	var hid := str(hat_id).strip_edges()
	if hid == "":
		return true
	var path := "res://assets/hats/%s.tscn" % hid
	if not ResourceLoader.exists(path):
		return false
	var packed: PackedScene = load(path) as PackedScene
	if packed == null or not packed.can_instantiate():
		return false
	var hat: Node = packed.instantiate() as Node
	if hat == null:
		return false
	anchor.add_child(hat)
	if hat is Node3D:
		(hat as Node3D).position = Vector3.ZERO
	return true


## Tints SkinPreview with `skin_id_or_hex`: either a palette skin id
## ("charcoal") or a literal "#RRGGBB" hex. Returns false for missing
## preview nodes and bad colors; never errors.
func preview_skin(skin_id_or_hex: String) -> bool:
	var preview := get_node_or_null("SkinPreview") as MeshInstance3D
	if preview == null:
		return false
	var want := str(skin_id_or_hex).strip_edges()
	if want == "":
		return false
	var hex := ""
	if SKIN_HEXES.has(want):
		hex = str(SKIN_HEXES[want])
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
	preview.material_override = mat
	preview.set_meta("skin", want)
	_play_sfx("button")
	return true


## Last skin applied via preview_skin (id or hex); "" when none.
func current_skin() -> String:
	var preview := get_node_or_null("SkinPreview")
	if preview == null or not preview.has_meta("skin"):
		return ""
	return str(preview.get_meta("skin"))


## Guarded SFX hook: plays through the Sfx autoload when present, silent
## otherwise so scene instantiations without autoloads never error.
func _play_sfx(sfx_name: String) -> void:
	if not is_inside_tree():
		return
	var bus := get_node_or_null("/root/Sfx")
	if bus != null and bus.has_method("play"):
		bus.call("play", sfx_name)
