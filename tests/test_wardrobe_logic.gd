extends SceneTree
## Unit runner for the coins wardrobe economy (issue #18): catalog counts,
## price fit against one full run, purchase/equip semantics, snapshot
## replication, and the shared self-test.
## Pattern mirrors tests/test_flow_logic.gd: SceneTree runner with own
## counters, assert_eq-style helpers, per-test methods, quit(1 if failed > 0).
## Run: godot --headless --path . --script res://tests/test_wardrobe_logic.gd

const Wardrobe := preload("res://server/wardrobe.gd")
const Cosmetics := preload("res://actors/player/cosmetics.gd")
const NetServer := preload("res://server/net_server.gd")

var passed := 0
var failed := 0


func _initialize() -> void:
	for t: String in [
		"test_catalog_counts",
		"test_prices_fit_full_run",
		"test_purchase_equip",
		"test_snapshot_replication",
		"test_attach_helpers",
		"test_selftest_green",
	]:
		if call(t) != true:
			failed += 1
			push_error("FAIL %s: did not finish (runtime error?)" % t)
	print("Results: %d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	if actual == expected:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


func assert_true(value: bool, label: String) -> void:
	if value:
		passed += 1
	else:
		failed += 1
		push_error("FAIL %s: expected true" % label)


func test_catalog_counts() -> bool:
	assert_eq(Wardrobe.HAT_IDS.size(), 8, "catalog holds 8 hats")
	assert_eq(str(Wardrobe.HAT_IDS[0]), "hat_cone", "cheapest hat first")
	assert_eq(Wardrobe.SKIN_IDS.size(), 4, "catalog holds 4 skins")
	assert_eq(Wardrobe.hats_count(), 8, "8 hat scenes load from disk")
	assert_eq(Wardrobe.skins_count(), 4, "4 skin cfgs parse from disk")
	assert_true(Wardrobe.is_valid_hat("hat_cone"), "hat_cone validates")
	assert_true(not Wardrobe.is_valid_hat("cape-gold"), "unknown hat rejected")
	assert_true(Wardrobe.is_valid_skin("charcoal"), "charcoal validates")
	assert_true(not Wardrobe.is_valid_skin("nope"), "unknown skin rejected")
	for skin_id in Wardrobe.SKIN_IDS:
		var hex := Wardrobe.skin_hex(skin_id)
		assert_true(hex != "", "skin %s resolves a hex" % str(skin_id))
		var ok := true
		var unused := Color.html(hex) if ok else Color.WHITE
		assert_true(unused != null, "skin %s hex parses" % str(skin_id))
	assert_eq(Wardrobe.skin_hex("nope"), "", "unknown skin hex is empty")
	return true


func test_prices_fit_full_run() -> bool:
	assert_eq(Wardrobe.price_for("hat_cone"), 100, "hat_cone costs 100")
	assert_eq(Wardrobe.price_for("charcoal"), 150, "charcoal costs 150")
	assert_eq(Wardrobe.price_for("nope"), -1, "unknown item has no price")
	assert_eq(Wardrobe.full_run_coins(), 800, "full run pays 800")
	assert_true(100 + 150 <= Wardrobe.full_run_coins(), "cheapest hat+skin fits one full run")
	for hat_id in Wardrobe.HAT_IDS:
		assert_true(Wardrobe.price_for(hat_id) <= 450, "hat %s costs at most 450" % str(hat_id))
	for skin_id in Wardrobe.SKIN_IDS:
		assert_true(Wardrobe.price_for(skin_id) <= 450, "skin %s costs at most 450" % str(skin_id))
	return true


func test_purchase_equip() -> bool:
	var profile := Wardrobe.default_profile()
	profile["coins"] = Wardrobe.full_run_coins()
	var bought_hat: Dictionary = Wardrobe.try_purchase(profile, "hat_cone")
	assert_eq(bool(bought_hat.get("ok", false)), true, "hat_cone purchase ok")
	var bought_skin: Dictionary = Wardrobe.try_purchase(profile, "charcoal")
	assert_eq(bool(bought_skin.get("ok", false)), true, "charcoal purchase ok")
	assert_eq(int(profile.get("coins", -1)), 800 - 100 - 150, "purchase deducts 100 + 150")
	assert_true((profile.get("owned", []) as Array).has("hat_cone"), "hat_cone lands in owned")
	var dup: Dictionary = Wardrobe.try_purchase(profile, "hat_cone")
	assert_eq(bool(dup.get("ok", true)), false, "duplicate purchase rejected")
	assert_eq(str(dup.get("error", "")), "already_owned", "duplicate error names already_owned")
	var poor := Wardrobe.default_profile()
	var broke: Dictionary = Wardrobe.try_purchase(poor, "hat_cone")
	assert_eq(bool(broke.get("ok", true)), false, "broke purchase rejected")
	assert_eq(str(broke.get("error", "")), "insufficient_coins", "broke error names insufficient_coins")
	var strange: Dictionary = Wardrobe.try_purchase(profile, "cape-gold")
	assert_eq(bool(strange.get("ok", true)), false, "unknown purchase rejected")
	assert_eq(str(strange.get("error", "")), "unknown_item", "unknown error names unknown_item")
	assert_eq(bool(Wardrobe.equip(profile, "hat", "hat_cone").get("ok", false)), true, "owned hat equips")
	assert_eq(bool(Wardrobe.equip(profile, "skin", "charcoal").get("ok", false)), true, "owned skin equips")
	assert_eq(str(Wardrobe.equipped_for(profile).get("hat", "")), "hat_cone", "equipped carries the hat")
	assert_eq(str(Wardrobe.equipped_for(profile).get("skin", "")), "charcoal", "equipped carries the skin")
	var bare := Wardrobe.default_profile()
	(bare["owned"] as Array).append("hat_cone")
	var naked: Dictionary = Wardrobe.equip(bare, "skin", "charcoal")
	assert_eq(bool(naked.get("ok", true)), false, "unowned skin rejected")
	assert_eq(str(naked.get("error", "")), "not_owned", "unowned error names not_owned")
	return true


func test_snapshot_replication() -> bool:
	var net = NetServer.new()
	net.set_cosmetic(11, {"hat": "hat_cone", "skin": "charcoal"})
	net.set_cosmetic(22, {"hat": "hat_crown", "skin": "mint"})
	assert_eq(str(net.cosmetic_for(11).get("hat", "")), "hat_cone", "host cosmetic stored")
	var states := {
		11: {"p": Vector3.ZERO, "v": Vector3.ZERO},
		22: {"p": Vector3(1.0, 0.0, 0.0), "v": Vector3.ZERO},
	}
	var legacy: Dictionary = NetServer.make_snapshot(3, states)
	assert_true(not (legacy["peers"][11] as Dictionary).has("cos"), "legacy snapshot keeps {p, v} shape")
	var cos := {}
	cos[11] = net.cosmetic_for(11)
	cos[22] = net.cosmetic_for(22)
	var snap: Dictionary = NetServer.make_snapshot(3, states, cos)
	var peers: Dictionary = snap.get("peers", {})
	assert_eq(str((peers[11] as Dictionary).get("cos", {}).get("hat", "")), "hat_cone", "host cos replicates")
	assert_eq(str((peers[22] as Dictionary).get("cos", {}).get("hat", "")), "hat_crown", "guest cos replicates")
	assert_true(str((peers[11] as Dictionary).get("cos", {}).get("hat", "")) != str((peers[22] as Dictionary).get("cos", {}).get("hat", "")), "peers look different")
	net.free()
	return true


func test_attach_helpers() -> bool:
	var packed: PackedScene = load("res://actors/player/player.tscn") as PackedScene
	assert_true(packed != null and packed.can_instantiate(), "player loads")
	var probe: Node = packed.instantiate() as Node
	assert_true(probe.get_node_or_null("HatAnchor") != null, "player carries HatAnchor")
	assert_true(Cosmetics.attach_hat(probe, "hat_cone"), "hat_cone attaches")
	assert_true(Cosmetics.is_hat_visible(probe), "attached hat is visible")
	assert_true(Cosmetics.apply_skin(probe, "charcoal"), "charcoal skin applies")
	assert_eq(Cosmetics.current_skin(probe), "charcoal", "current skin echoes charcoal")
	assert_true(not Cosmetics.attach_hat(null, "hat_cone"), "null player fails closed")
	assert_true(not Cosmetics.attach_hat(probe, "cape-gold"), "unknown hat rejected")
	assert_true(not Cosmetics.apply_skin(null, "charcoal"), "null skin target fails closed")
	probe.free()
	var room_packed: PackedScene = load("res://scenes/wardrobe.tscn") as PackedScene
	assert_true(room_packed != null and room_packed.can_instantiate(), "wardrobe showroom loads")
	var room_node: Node = room_packed.instantiate() as Node
	assert_true(room_node.get_node_or_null("HatAnchor") != null, "showroom carries HatAnchor")
	assert_true(room_node.get_node_or_null("SkinPreview") != null, "showroom carries SkinPreview")
	room_node.free()
	return true


func test_selftest_green() -> bool:
	var r: Array = Wardrobe.run_selftest()
	assert_eq(int(r[1]), 0, "wardrobe selftest has no failures")
	assert_true(int(r[0]) > 0, "wardrobe selftest asserts something")
	return true
