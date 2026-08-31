extends Node

const VARIANTS := {
	"m17": {
		"scene": "res://character/weapons/M17.tscn",
		"model": "res://assets/tools/M17.glb",
		"name": "M17 手枪",
	},
	"m17_snowcamo": {
		"scene": "res://character/weapons/M17SnowCamo.tscn",
		"model": "res://assets/tools/other_styles/SnowCamo/M17_SnowCamo.glb",
		"name": "M17 雪地迷彩",
	},
	"m17_ruralcamo": {
		"scene": "res://character/weapons/M17RuralCamo.tscn",
		"model": "res://assets/tools/other_styles/RuralCamo/M17_RuralCamo.glb",
		"name": "M17 乡村迷彩",
	},
	"m17_hardenedsteel": {
		"scene": "res://character/weapons/M17HardenedSteel.tscn",
		"model": "res://assets/tools/other_styles/HardenedSteel/M17_HardenedSteel.glb",
		"name": "M17 淬火钢",
	},
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_combat_profile()
	await _validate_definitions_and_scenes()
	_validate_icons_and_catalogs()
	_validate_get_ammo_authority_and_flashlight_sync()
	_finish()


func _validate_combat_profile() -> void:
	_check(CombatBalance.resolve_profile_id("m17") == "m17", "base ID resolves to the M17 profile")
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(CombatBalance.is_profile(tool_id, "m17"), "%s resolves to the M17 combat profile" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "damage"), 31.0), "%s damage is 31" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "range"), 80.0), "%s range is 80" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "knockback"), 18.0), "%s knockback is 18" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_speed"), 90.0), "%s visual speed is 90" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_lifetime"), 0.9), "%s visual lifetime is 0.9 seconds" % tool_id)
		_check(CombatBalance.get_int(tool_id, "bullet_count") == 1, "%s fires one bullet" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "spread_degrees"), 0.0), "%s has no spread" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "camera_recoil_strength"), 0.022), "%s camera recoil strength is 0.022" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "camera_recoil_duration"), 0.12), "%s camera recoil duration is 0.12" % tool_id)
		var recoil := CombatBalance.get_model_recoil_offset(tool_id)
		_check(is_equal_approx(recoil.y, 0.022) and is_equal_approx(recoil.z, 0.055), "%s model recoil is Y=0.022/Z=0.055" % tool_id)
	_check(CombatBalance.get_float("m17", "damage") > CombatBalance.get_float("suppressed_pistol", "damage"), "M17 is slightly stronger than the suppressed pistol")
	_check(CombatBalance.get_float("m17", "damage") < CombatBalance.get_float("p90", "damage"), "M17 is weaker than P90")


func _validate_definitions_and_scenes() -> void:
	var tool_definitions := _read_json("res://data/tool_definitions.json")
	var primary_definitions := _read_json("res://data/primary_weapon_definitions.json")
	var tool_values: Variant = tool_definitions.get("tools", [])
	var primary_values: Variant = primary_definitions.get("weapons", [])
	var tools_by_id := _definitions_by_id(tool_values)
	var primary_by_id := _definitions_by_id(primary_values)
	var expected_tool_values := {
		"allow_multiple": true,
		"cooldown": 0.22,
		"magazine_size": 17,
		"initial_reserve_ammo": 0,
		"reload_time": 1.7,
		"category": "shooting",
		"two_handed": false,
		"aimable": true,
		"show_crosshair": true,
		"aim_fov": 50.0,
		"aim_speed": 19.0,
		"hint": "[C] 打开/关闭手电筒",
	}

	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(_count_id(tool_values, tool_id) == 1, "%s appears exactly once in tool_definitions.json" % tool_id)
		_check(_count_id(primary_values, tool_id) == 1, "%s appears exactly once in primary_weapon_definitions.json" % tool_id)
		var definition: Dictionary = tools_by_id.get(tool_id, {})
		_check(not definition.is_empty(), "%s exists in tool_definitions.json" % tool_id)
		_check(str(definition.get("name", "")) == str(VARIANTS[tool_id].get("name", "")), "%s uses its Chinese display name" % tool_id)
		for field_value: Variant in expected_tool_values.keys():
			var field := str(field_value)
			_check(_value_matches(definition.get(field), expected_tool_values[field]), "%s has %s=%s" % [tool_id, field, str(expected_tool_values[field])])
		_check(definition.get("grip_position", []) == [0.0, 0.0, 0.0], "%s uses the shared pistol grip position" % tool_id)
		_check(definition.get("grip_rotation", []) == [0.0, 180.0, 180.0], "%s uses the shared pistol grip rotation" % tool_id)
		_check(definition.get("grip_scale", []) == [0.3, 0.3, 0.3], "%s uses the shared pistol grip scale" % tool_id)

		var primary_definition: Dictionary = primary_by_id.get(tool_id, {})
		_check(not primary_definition.is_empty(), "%s exists in primary_weapon_definitions.json" % tool_id)
		_check(primary_definition.get("loadout_selectable", true) == false, "%s is not loadout selectable" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("power", 0.0)), 31.0), "%s primary power is 31" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("fire_rate", 0.0)), 4.55), "%s primary fire rate is 4.55" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("cooldown", 0.0)), 0.22), "%s primary cooldown is 0.22" % tool_id)

		var scene_path := str(VARIANTS[tool_id].get("scene", ""))
		var model_path := str(VARIANTS[tool_id].get("model", ""))
		_check(FileAccess.file_exists(model_path), "%s model exists" % tool_id)
		_check(_read_text(scene_path).contains(model_path), "%s scene references its own GLB" % tool_id)
		var scene := load(scene_path) as PackedScene
		_check(scene != null, "%s scene loads" % tool_id)
		if scene == null:
			continue
		var weapon := scene.instantiate() as Node3D
		_check(weapon != null, "%s scene instantiates as Node3D" % tool_id)
		if weapon == null:
			continue
		add_child(weapon)
		await get_tree().process_frame
		_check(weapon is NailFirearmTool, "%s uses NailFirearmTool" % tool_id)
		_check(str(weapon.get("profile_id")) == "m17", "%s scene uses profile_id m17" % tool_id)
		_check(weapon.get_node_or_null("Mesh") != null, "%s has Mesh" % tool_id)
		_check(weapon.get_node_or_null("Muzzle") != null, "%s has Muzzle" % tool_id)
		_check(weapon.get_node_or_null("Muzzle/MuzzleFlash") != null, "%s has MuzzleFlash" % tool_id)
		_check(weapon.get_node_or_null("Muzzle/MuzzleFlashVisual") != null, "%s has MuzzleFlashVisual" % tool_id)
		_check(weapon.get_node_or_null("Light") != null, "%s has the flashlight marker" % tool_id)
		var flashlight_light := weapon.get_node_or_null("Light/FlashlightLight") as SpotLight3D
		_check(flashlight_light != null, "%s has FlashlightLight" % tool_id)
		if flashlight_light != null:
			_check(is_equal_approx(flashlight_light.spot_range, 15.0), "%s flashlight range is 15 meters" % tool_id)
			_check(is_equal_approx(flashlight_light.spot_angle, 35.0), "%s flashlight cone is 35 degrees" % tool_id)
			_check(not flashlight_light.shadow_enabled, "%s flashlight does not use realtime shadows" % tool_id)
		var flashlight_glow := weapon.find_child("FlashlightGlow", true, false) as Node3D
		_check(flashlight_glow != null, "%s has Mesh/FlashlightGlow" % tool_id)
		if flashlight_glow != null and flashlight_light != null:
			_check(not flashlight_glow.visible and not flashlight_light.visible, "%s flashlight starts off" % tool_id)
			weapon.call("set_flashlight_enabled", true)
			_check(flashlight_glow.visible and flashlight_light.visible, "%s turns on both glow and light" % tool_id)
			weapon.call("set_flashlight_enabled", false)
			_check(not flashlight_glow.visible and not flashlight_light.visible, "%s turns off both glow and light" % tool_id)
		remove_child(weapon)
		weapon.free()


func _validate_icons_and_catalogs() -> void:
	var manifest := _read_json("res://assets/icons/items/icon_manifest.json")
	var manifest_by_id := {}
	for item_value: Variant in manifest.get("items", []):
		if item_value is Dictionary:
			var item := item_value as Dictionary
			manifest_by_id[str(item.get("id", ""))] = item
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		var icon_path := "res://assets/icons/items/weapons/%s.png" % tool_id
		_check(FileAccess.file_exists(icon_path), "%s item icon exists" % tool_id)
		_check(ItemIconCatalog.get_tool_icon(tool_id) != null, "%s item icon resolves" % tool_id)
		var manifest_entry: Dictionary = manifest_by_id.get(tool_id, {})
		_check(str(manifest_entry.get("icon", "")) == icon_path, "%s manifest path is registered" % tool_id)
		_check(str(manifest_entry.get("status", "")) == "rendered", "%s manifest status is rendered" % tool_id)

	_check(FileAccess.file_exists("res://assets/icons/rangeledger/m17.png"), "M17 range ledger icon exists")
	_check(RangeLedgerPage.PRODUCTS.has("m17"), "base M17 is in the range ledger catalog")
	_check(RangeLedgerPage.PRODUCTS["m17"].get("power", "") == "31", "M17 range ledger power is 31")
	_check(RangeLedgerPage.PRODUCTS["m17"].get("range", "") == "80 米", "M17 range ledger range is 80 meters")
	var catalog_products: Array = RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG].get("products", [])
	_check(catalog_products.count("m17") == 1, "base M17 is listed once in the range ledger")
	_check(not catalog_products.has("m17_snowcamo") and not catalog_products.has("m17_ruralcamo") and not catalog_products.has("m17_hardenedsteel"), "M17 camouflage variants are not duplicated in the range ledger")

	var global_var := get_tree().root.get_node_or_null("GlobalVar")
	_check(global_var != null, "GlobalVar autoload exists")
	if global_var == null:
		return
	var base_product: Dictionary = global_var.call("get_shop_product", "m17")
	_check(not base_product.is_empty(), "base M17 has a shop product")
	_check(int(base_product.get("buy_price", 0)) == 1200 and int(base_product.get("sell_price", 0)) == 840, "base M17 uses the planned shop price")
	_check(bool(global_var.call("is_shop_product_buyable", "gun_store", "m17")), "base M17 is buyable")
	_check(bool(global_var.call("is_shop_product_sellable", "gun_store", "m17")), "base M17 is sellable")
	var gun_store_ids: Array[String] = []
	for product: Dictionary in global_var.call("get_shop_products", "gun_store"):
		gun_store_ids.append(str(product.get("id", "")))
	_check(gun_store_ids.has("m17"), "gun store lists base M17")
	for variant_id in ["m17_snowcamo", "m17_ruralcamo", "m17_hardenedsteel"]:
		_check(global_var.call("get_shop_product", variant_id).is_empty(), "%s has no shop product" % variant_id)
		_check(not bool(global_var.call("is_shop_product_buyable", "gun_store", variant_id)), "%s is not buyable" % variant_id)
		_check(not bool(global_var.call("is_shop_product_sellable", "gun_store", variant_id)), "%s is not sellable" % variant_id)
		_check(not gun_store_ids.has(variant_id), "%s is absent from the gun store list" % variant_id)

	var supply_ids: Array[String] = []
	for reward: Dictionary in SupplyRelayCatalog.get_reward_pool():
		supply_ids.append(str(reward.get("item_id", "")))
	for id_value: Variant in VARIANTS.keys():
		_check(not supply_ids.has(str(id_value)), "%s is not in the supply relay reward pool" % str(id_value))


func _validate_get_ammo_authority_and_flashlight_sync() -> void:
	var authority := get_tree().root.get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		return
	authority.call("start_local_mode")
	var peer_id := 5170
	authority.call("register_or_update_player", peer_id, {
		"display_name": "M17Validation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(bool(authority.call("_uses_finite_ammo", tool_id)), "%s uses finite-ammo handling" % tool_id)
		_check(str(authority.call("_animation_action_for_tool", tool_id)) == "shooting", "%s uses shooting animation handling" % tool_id)
		_check(int(authority.call("_weapon_magazine_size", tool_id)) == 17, "%s authority magazine size is 17" % tool_id)
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call("_server_debug_get_tool", peer_id, state, "[get] %s 1" % tool_id)
		_check(bool(result.get("ok", false)), "[get] accepts %s" % tool_id)
		_check(str(result.get("tool_id", "")) == tool_id, "[get] preserves exact ID %s" % tool_id)
		state = authority.get("player_states").get(peer_id, {})
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		var ammo_state: Dictionary = ammo_states.get(tool_id, {})
		_check(int(ammo_state.get("ammo_in_mag", 0)) == 17, "%s starts with a 17-round magazine" % tool_id)
		var shot_value: Variant = authority.call("_execute_tool", peer_id, tool_id, {
			"tool_id": tool_id,
			"tool_index": 0,
			"origin": Vector3.ZERO,
			"direction": Vector3.FORWARD,
		})
		var shot: Dictionary = shot_value as Dictionary if shot_value is Dictionary else {}
		_check(bool(shot.get("ok", false)) and shot.has("hit_kind") and shot.has("effect"), "%s produces one hitscan result" % tool_id)
		_check(str(shot.get("effect", "")) == "nail" and not shot.has("pellet_results"), "%s uses the single-projectile authority path" % tool_id)

	var state: Dictionary = authority.get("player_states").get(peer_id, {})
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var snow_ammo: Dictionary = ammo_states.get("m17_snowcamo", {}).duplicate(true)
	var rural_ammo: Dictionary = ammo_states.get("m17_ruralcamo", {}).duplicate(true)
	snow_ammo["ammo_in_mag"] = 9
	rural_ammo["ammo_in_mag"] = 4
	ammo_states["m17_snowcamo"] = snow_ammo
	ammo_states["m17_ruralcamo"] = rural_ammo
	state["weapon_ammo_states"] = ammo_states
	var player_states: Dictionary = authority.get("player_states")
	player_states[peer_id] = state
	_check(int((ammo_states.get("m17_snowcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 9, "SnowCamo ammo state is independent")
	_check(int((ammo_states.get("m17_ruralcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 4, "RuralCamo ammo state is independent")
	_check(int((ammo_states.get("m17", {}) as Dictionary).get("ammo_in_mag", 0)) == 17, "base M17 ammo state is not changed by skins")

	authority.call("server_select_tool", peer_id, 0, "m17")
	var flashlight_result: Dictionary = authority.call("server_tool_action", peer_id, {"action": "set_flashlight", "enabled": true})
	_check(bool(flashlight_result.get("ok", false)), "M17 flashlight toggle is accepted by authority")
	state = authority.get("player_states").get(peer_id, {})
	_check(bool(state.get("m17_flashlight_on", false)), "authority stores the flashlight state")
	var snapshot: Dictionary = authority.call("_build_world_snapshot")
	var found_snapshot := false
	for player_value: Variant in snapshot.get("players", []):
		if player_value is Dictionary and int((player_value as Dictionary).get("peer_id", 0)) == peer_id:
			found_snapshot = true
			_check(bool((player_value as Dictionary).get("m17_flashlight_on", false)), "world snapshot carries the flashlight state")
			_check(str((player_value as Dictionary).get("current_tool_id", "")) == "m17", "world snapshot keeps the exact M17 ID")
	_check(found_snapshot, "world snapshot contains the validation player")
	var variant_select_state: Dictionary = authority.get("player_states").get(peer_id, {})
	authority.call("server_select_tool", peer_id, 1, "m17_snowcamo")
	variant_select_state = authority.get("player_states").get(peer_id, {})
	_check(not bool(variant_select_state.get("m17_flashlight_on", true)), "switching to a skin resets the flashlight")
	var skin_flashlight_result: Dictionary = authority.call("server_tool_action", peer_id, {"action": "set_flashlight", "enabled": true})
	_check(bool(skin_flashlight_result.get("ok", false)), "M17 skin flashlight toggle is accepted by authority")
	authority.call("server_select_tool", peer_id, 2, "m17_ruralcamo")
	_check(not bool((authority.get("player_states").get(peer_id, {}) as Dictionary).get("m17_flashlight_on", true)), "switching to another M17 skin resets the flashlight")
	authority.call("stop_authority")

	var shop_peer_id := 5171
	authority.call("register_or_update_player", shop_peer_id, {
		"display_name": "M17ShopValidation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	GlobalVar.add_item("red", "money", 5000.0)
	var money_before := GlobalVar.check_team_item_amount("red", "money")
	var purchase: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
		"action": "trade",
		"item_id": "m17",
		"amount": 1,
		"is_buy": true,
		"shop_category": "gun_store",
	})
	_check(bool(purchase.get("ok", false)), "base M17 completes a shop purchase")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 1200.0), "base M17 purchase charges 1200")
	var sale: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
		"action": "trade",
		"item_id": "m17",
		"amount": 1,
		"is_buy": false,
		"shop_category": "gun_store",
	})
	_check(bool(sale.get("ok", false)), "base M17 completes a shop sale")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 360.0), "base M17 sale returns 840")
	for variant_id in ["m17_snowcamo", "m17_ruralcamo", "m17_hardenedsteel"]:
		var rejected_purchase: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
			"action": "trade",
			"item_id": variant_id,
			"amount": 1,
			"is_buy": true,
			"shop_category": "gun_store",
		})
		_check(not bool(rejected_purchase.get("ok", false)), "%s cannot be purchased from the gun store" % variant_id)
		var rejected_sale: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
			"action": "trade",
			"item_id": variant_id,
			"amount": 1,
			"is_buy": false,
			"shop_category": "gun_store",
		})
		_check(not bool(rejected_sale.get("ok", false)), "%s cannot be sold to the gun store" % variant_id)


func _definitions_by_id(values: Variant) -> Dictionary:
	var result := {}
	if not values is Array:
		return result
	for value: Variant in values:
		if value is Dictionary:
			var definition := value as Dictionary
			var id := str(definition.get("id", ""))
			if not id.is_empty():
				result[id] = definition
	return result


func _count_id(values: Variant, wanted_id: String) -> int:
	var count := 0
	if not values is Array:
		return count
	for value: Variant in values:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == wanted_id:
			count += 1
	return count


func _value_matches(actual: Variant, expected: Variant) -> bool:
	if expected is float or expected is int:
		return is_equal_approx(float(actual), float(expected))
	return actual == expected


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[M17WeaponValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[M17WeaponValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[M17WeaponValidation] PASS all checks")
		get_tree().quit(0)
		return
	print("[M17WeaponValidation] FAIL count=%d" % failures.size())
	get_tree().quit(1)
