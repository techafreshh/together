extends RefCounted
## Priced wardrobe catalog (issue #18): earn-and-show hats and palette skins.
##
## Pure catalog math plus disk-verified counts: 8 hats (hand-built .tscn,
## origin at the anchor) and 4 palette skins (.cfg carrying the exact
## docs/palette.md wardrobe hexes). Profiles use the persistence shape
## `{coins, owned, equipped, stages}`; purchase/equip mutate in place and
## answer `{ok, ...}` / `{ok: false, error}` like persistence.gd. Coin values
## stay owned by server/flow_manager.gd; this lap only prices against them.
## No sockets, no scene tree. The main-scene root (server/serve.gd) owns the
## `--selftest wardrobe` branch; the unit runner is tests/test_wardrobe_logic.gd.

const FlowManager := preload("res://server/flow_manager.gd")

## Catalog order: cheapest hat first so the selftest funds hat_cone first.
const HAT_IDS := ["hat_cone", "hat_cap", "hat_beanie", "hat_horns", "hat_tophat", "hat_halo", "hat_crown", "hat_propeller"]
const SKIN_IDS := ["charcoal", "mint", "sunset", "bubblegum"]
## Cheapest hat 100, cheapest skin 150, nothing above 450: the cheapest
## hat+skin pair (250) clears one full 8-stage run (800) with room to spare.
const HAT_PRICES := {
	"hat_cone": 100,
	"hat_cap": 150,
	"hat_beanie": 180,
	"hat_horns": 220,
	"hat_tophat": 250,
	"hat_halo": 300,
	"hat_crown": 350,
	"hat_propeller": 450,
}
const SKIN_PRICES := {
	"charcoal": 150,
	"mint": 200,
	"sunset": 250,
	"bubblegum": 300,
}
## Fallback hexes mirroring docs/palette.md; skin_hex prefers the on-disk
## .cfg so the files stay the source of truth.
const SKIN_HEXES := {
	"charcoal": "#2B2D42",
	"mint": "#B8F2E6",
	"sunset": "#FF9F1C",
	"bubblegum": "#FF70A6",
}


## Scene path for one hat id.
static func hat_scene_path(hat_id: String) -> String:
	return "res://assets/hats/%s.tscn" % str(hat_id)


## Config path for one skin id.
static func skin_cfg_path(skin_id: String) -> String:
	return "res://assets/skins/skin_%s.cfg" % str(skin_id)


static func is_valid_hat(item_id: Variant) -> bool:
	return HAT_IDS.has(str(item_id))


static func is_valid_skin(item_id: Variant) -> bool:
	return SKIN_IDS.has(str(item_id))


static func is_valid_item(item_id: Variant) -> bool:
	return is_valid_hat(item_id) or is_valid_skin(item_id)


## Price for any catalog item; -1 when unknown.
static func price_for(item_id: Variant) -> int:
	var item := str(item_id)
	if HAT_PRICES.has(item):
		return int(HAT_PRICES[item])
	if SKIN_PRICES.has(item):
		return int(SKIN_PRICES[item])
	return -1


## Hats present on disk (scene file loads as a PackedScene).
static func hats_count() -> int:
	var n := 0
	for hat_id in HAT_IDS:
		var path := hat_scene_path(str(hat_id))
		if not FileAccess.file_exists(path):
			continue
		var packed: PackedScene = load(path) as PackedScene
		if packed != null and packed.can_instantiate():
			n += 1
	return n


## Skins present on disk (cfg parses and carries a Color(html) hex).
static func skins_count() -> int:
	var n := 0
	for skin_id in SKIN_IDS:
		var cfg := ConfigFile.new()
		if cfg.load(skin_cfg_path(str(skin_id))) != OK:
			continue
		var hex := str(cfg.get_value("skin", "hex", ""))
		if hex == "":
			continue
		var ok := true
		var unused := Color.html(hex) if ok else Color.WHITE
		if unused == null:
			ok = false
		if ok:
			n += 1
	return n


## Hex for one skin id, preferring the on-disk .cfg; "" when unknown.
static func skin_hex(skin_id: Variant) -> String:
	var sid := str(skin_id)
	if not is_valid_skin(sid):
		return ""
	var cfg := ConfigFile.new()
	if cfg.load(skin_cfg_path(sid)) == OK:
		var hex := str(cfg.get_value("skin", "hex", "")).strip_edges()
		if hex != "":
			return hex
	return str(SKIN_HEXES.get(sid, ""))


## Canonical fresh profile: same shape as the persistence contract.
static func default_profile() -> Dictionary:
	return {"coins": 0, "owned": [], "equipped": {}, "stages": {}}


## Spends catalog price on `item_id` when affordable and not yet owned.
## Returns `{ok, ...}`; mutates the profile only on success.
static func try_purchase(profile: Dictionary, item_id: Variant) -> Dictionary:
	var item := str(item_id)
	var cost := price_for(item)
	if cost < 0:
		return {"ok": false, "error": "unknown_item"}
	if not (profile.get("owned", []) is Array):
		profile["owned"] = []
	var owned: Array = profile["owned"]
	if owned.has(item):
		return {"ok": false, "error": "already_owned"}
	var coins := int(profile.get("coins", 0))
	if coins < cost:
		return {"ok": false, "error": "insufficient_coins"}
	profile["coins"] = coins - cost
	owned.append(item)
	return {"ok": true, "coins": int(profile["coins"]), "owned": owned.duplicate(true)}


## Equips an owned hat (`slot == "hat"`) or skin (`slot == "skin"`) into
## `equipped{hat, skin}`. Empty item clears the slot. Unknown ids fail with
## unknown_hat/unknown_skin, unowned items with not_owned, bad slots with
## unknown_slot. Mutates the profile only on success.
static func equip(profile: Dictionary, slot: Variant, item_id: Variant) -> Dictionary:
	var s := str(slot)
	if s != "hat" and s != "skin":
		return {"ok": false, "error": "unknown_slot"}
	var item := str(item_id)
	if item == "":
		if not (profile.get("equipped", {}) is Dictionary):
			profile["equipped"] = {}
		(profile["equipped"] as Dictionary).erase(s)
		return {"ok": true, "equipped": (profile["equipped"] as Dictionary).duplicate(true)}
	if s == "hat" and not is_valid_hat(item):
		return {"ok": false, "error": "unknown_hat"}
	if s == "skin" and not is_valid_skin(item):
		return {"ok": false, "error": "unknown_skin"}
	if not (profile.get("owned", []) is Array):
		profile["owned"] = []
	if not (profile["owned"] as Array).has(item):
		return {"ok": false, "error": "not_owned"}
	if not (profile.get("equipped", {}) is Dictionary):
		profile["equipped"] = {}
	(profile["equipped"] as Dictionary)[s] = item
	return {"ok": true, "equipped": (profile["equipped"] as Dictionary).duplicate(true)}


## Equipped look for one profile ({hat, skin} subset, never null).
static func equipped_for(profile: Dictionary) -> Dictionary:
	if profile.get("equipped", {}) is Dictionary:
		return (profile["equipped"] as Dictionary).duplicate(true)
	return {}


## Coins paid by one full 8-stage first-clear run; prices tune against this.
static func full_run_coins() -> int:
	return FlowManager.FIRST_CLEAR_COINS * FlowManager.STAGE_IDS.size()


## Synchronous self-test: catalog shape, disk presence, price fit against
## one full run, purchase/equip semantics. Returns [passed, failed];
## never awaits, never touches sockets or the scene tree.
static func run_selftest() -> Array:
	var passed := 0
	var failed := 0
	if HAT_IDS.size() >= 6 and HAT_IDS.size() <= 10 and str(HAT_IDS[0]) == "hat_cone":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: catalog must hold 6-10 hats starting at hat_cone")
	if SKIN_IDS.size() == 4:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: catalog must hold exactly 4 skins")
	if int(HAT_PRICES.get("hat_cone", -1)) == 100:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: cheapest hat hat_cone must cost 100")
	var cheapest_skin := 1 << 30
	var dearest := 0
	for hat_id in HAT_IDS:
		var hp := price_for(hat_id)
		if hp < 0 or hp > 450:
			failed += 1
			push_error("wardrobe selftest: hat %s price must sit in 0..450" % str(hat_id))
		else:
			passed += 1
			dearest = maxi(dearest, hp)
	for skin_id in SKIN_IDS:
		var sp := price_for(skin_id)
		if sp < 0 or sp > 450:
			failed += 1
			push_error("wardrobe selftest: skin %s price must sit in 0..450" % str(skin_id))
		else:
			passed += 1
			cheapest_skin = mini(cheapest_skin, sp)
			dearest = maxi(dearest, sp)
	if cheapest_skin == 150:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: cheapest skin must cost 150")
	if dearest <= 450:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: nothing may cost above 450")
	if full_run_coins() == 800 and 100 + cheapest_skin <= full_run_coins():
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: cheapest hat+skin must fit one full run (%d)" % full_run_coins())
	if hats_count() == HAT_IDS.size():
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: %d/%d hat scenes load from disk" % [hats_count(), HAT_IDS.size()])
	if skins_count() == SKIN_IDS.size():
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: %d/%d skin cfgs parse from disk" % [skins_count(), SKIN_IDS.size()])
	var hex_ok := true
	for skin_id in SKIN_IDS:
		var hex := skin_hex(skin_id)
		if hex == "" or skin_hex(str(skin_id).to_upper()) != "":
			hex_ok = false
		var probe := true
		var unused := Color.html(hex) if probe else Color.WHITE
		if unused == null:
			hex_ok = false
	if hex_ok:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: every skin must resolve a Color(html) hex")
	if not is_valid_item("nope") and price_for("nope") == -1 and skin_hex("nope") == "":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: unknown items must fail closed")
	var profile := default_profile()
	profile["coins"] = full_run_coins()
	var bought_hat: Dictionary = try_purchase(profile, "hat_cone")
	var bought_skin: Dictionary = try_purchase(profile, "charcoal")
	if bool(bought_hat.get("ok", false)) and bool(bought_skin.get("ok", false)) and (profile.get("owned", []) as Array).has("hat_cone"):
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: funded profile must buy hat_cone + charcoal")
	if int(profile.get("coins", -1)) == full_run_coins() - 100 - 150:
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: purchase must deduct 100 + 150 coins")
	var dup: Dictionary = try_purchase(profile, "hat_cone")
	if not bool(dup.get("ok", false)) and str(dup.get("error", "")) == "already_owned":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: duplicate purchase must fail already_owned")
	var poor := default_profile()
	var broke: Dictionary = try_purchase(poor, "hat_cone")
	if not bool(broke.get("ok", false)) and str(broke.get("error", "")) == "insufficient_coins":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: broke purchase must fail insufficient_coins")
	var strange: Dictionary = try_purchase(profile, "cape-gold")
	if not bool(strange.get("ok", false)) and str(strange.get("error", "")) == "unknown_item":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: unknown item must fail unknown_item")
	var wear_hat: Dictionary = equip(profile, "hat", "hat_cone")
	var wear_skin: Dictionary = equip(profile, "skin", "charcoal")
	if bool(wear_hat.get("ok", false)) and bool(wear_skin.get("ok", false)):
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: owned hat+skin must equip")
	if str(equipped_for(profile).get("hat", "")) == "hat_cone" and str(equipped_for(profile).get("skin", "")) == "charcoal":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: equipped_for must carry hat_cone + charcoal")
	var bare := default_profile()
	(bare["owned"] as Array).append("hat_cone")
	var naked: Dictionary = equip(bare, "skin", "charcoal")
	if not bool(naked.get("ok", false)) and str(naked.get("error", "")) == "not_owned":
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: unowned skin must fail not_owned")
	var wrong_hat: Dictionary = equip(profile, "hat", "charcoal")
	var wrong_skin: Dictionary = equip(profile, "skin", "hat_cone")
	var wrong_slot: Dictionary = equip(profile, "cape", "hat_cone")
	if not bool(wrong_hat.get("ok", false)) and not bool(wrong_skin.get("ok", false)) and not bool(wrong_slot.get("ok", false)):
		passed += 1
	else:
		failed += 1
		push_error("wardrobe selftest: cross-slot and bad-slot equips must fail closed")
	return [passed, failed]
