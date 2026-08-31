extends Node

const VARIANTS := {
	"p90": {
		"scene": "res://character/weapons/P90.tscn",
		"model": "res://assets/tools/P90.glb",
	},
	"p90_ruralcamo": {
		"scene": "res://character/weapons/P90RuralCamo.tscn",
		"model": "res://assets/tools/other_styles/RuralCamo/P90_RuralCamo.glb",
	},
	"p90_snowcamo": {
		"scene": "res://character/weapons/P90SnowCamo.tscn",
		"model": "res://assets/tools/other_styles/SnowCamo/P90_SnowCamo.glb",
	},
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_combat_profile()
	_validate_definitions_and_scenes()
	_validate_icons_and_catalogs()
	_validate_get_ammo_and_authority()
	_finish()


func _validate_combat_profile() -> void:
	_check(CombatBalance.resolve_profile_id("p90") == "p90", "base ID resolves to the P90 profile")
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(CombatBalance.is_profile(tool_id, "p90"), "%s resolves to the P90 combat profile" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "damage"), 32.0), "%s damage is 32" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "range"), 90.0), "%s range is 90" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "knockback"), 16.0), "%s knockback is 16" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_speed"), 120.0), "%s visual speed is 120" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_lifetime"), 0.75), "%s visual lifetime is 0.75 seconds" % tool_id)
		_check(CombatBalance.get_int(tool_id, "bullet_count") == 1, "%s fires one bullet" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "spread_degrees"), 0.0), "%s has no spread" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "camera_recoil_strength"), 0.032), "%s camera recoil strength is 0.032" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "camera_recoil_duration"), 0.11), "%s camera recoil duration is 0.11" % tool_id)
		var recoil := CombatBalance.get_model_recoil_offset(tool_id)
		_check(is_equal_approx(recoil.y, 0.028) and is_equal_approx(recoil.z, 0.070), "%s model recoil is Y=0.028/Z=0.070" % tool_id)


func _validate_definitions_and_scenes() -> void:
	var tool_definitions := _read_json("res://data/tool_definitions.json")
	var primary_definitions := _read_json("res://data/primary_weapon_definitions.json")
	var tool_values: Variant = tool_definitions.get("tools", [])
	var primary_values: Variant = primary_definitions.get("weapons", [])
	var tools_by_id := _definitions_by_id(tool_values)
	var primary_by_id := _definitions_by_id(primary_values)
	var expected_tool_values := {
		"allow_multiple": true,
		"cooldown": 0.08,
		"magazine_size": 50,
		"initial_reserve_ammo": 0,
		"reload_time": 2.3,
		"category": "shooting",
		"two_handed": true,
		"aimable": true,
		"show_crosshair": true,
		"aim_fov": 90.0,
		"aim_speed": 16.0,
	}

	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(_count_id(tool_values, tool_id) == 1, "%s appears exactly once in tool_definitions.json" % tool_id)
		_check(_count_id(primary_values, tool_id) == 1, "%s appears exactly once in primary_weapon_definitions.json" % tool_id)
		var definition: Dictionary = tools_by_id.get(tool_id, {})
		_check(not definition.is_empty(), "%s exists in tool_definitions.json" % tool_id)
		for field_value: Variant in expected_tool_values.keys():
			var field := str(field_value)
			_check(_value_matches(definition.get(field), expected_tool_values[field]), "%s has %s=%s" % [tool_id, field, str(expected_tool_values[field])])
		_check(definition.get("grip_position", []) == [0.0, 0.0, 0.0], "%s uses the shared two-handed grip position" % tool_id)
		_check(definition.get("grip_rotation", []) == [0.0, 180.0, 180.0], "%s uses the shared two-handed grip rotation" % tool_id)
		_check(definition.get("grip_scale", []) == [0.8, 0.8, 0.8], "%s uses the shared two-handed grip scale" % tool_id)
		_check(not definition.has("left_hand_grip_offset"), "%s keeps its scene LeftHandGrip marker without an override" % tool_id)

		var primary_definition: Dictionary = primary_by_id.get(tool_id, {})
		_check(not primary_definition.is_empty(), "%s exists in primary_weapon_definitions.json" % tool_id)
		_check(primary_definition.get("loadout_selectable", true) == false, "%s is not loadout selectable" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("power", 0.0)), 32.0), "%s primary power is 32" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("fire_rate", 0.0)), 12.5), "%s primary fire rate is 12.5" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("cooldown", 0.0)), 0.08), "%s primary cooldown is 0.08" % tool_id)

		var model_path := str(VARIANTS[tool_id].get("model", ""))
		var scene_path := str(VARIANTS[tool_id].get("scene", ""))
		_check(FileAccess.file_exists(model_path), "%s model exists" % tool_id)
		var scene_text := _read_text(scene_path)
		_check(scene_text.contains(model_path), "%s scene references its own GLB" % tool_id)
		var scene := load(scene_path) as PackedScene
		_check(scene != null, "%s scene loads" % tool_id)
		if scene == null:
			continue
		var weapon := scene.instantiate()
		_check(weapon is Node3D, "%s scene instantiates as Node3D" % tool_id)
		if weapon is Node3D:
			_check(weapon is NailFirearmTool, "%s uses NailFirearmTool" % tool_id)
			_check(str(weapon.get("profile_id")) == "p90", "%s scene uses profile_id p90" % tool_id)
			_check(weapon.get_node_or_null("Mesh") != null, "%s has Mesh" % tool_id)
			_check(weapon.get_node_or_null("Muzzle") != null, "%s has Muzzle" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlash") != null, "%s has MuzzleFlash" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlashVisual") != null, "%s has MuzzleFlashVisual" % tool_id)
			_check(weapon.get_node_or_null("LeftHandGrip") != null, "%s has LeftHandGrip" % tool_id)
		if weapon != null:
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

	_check(FileAccess.file_exists("res://assets/icons/rangeledger/p90.png"), "P90 range ledger icon exists")
	_check(RangeLedgerPage.PRODUCTS.has("p90"), "base P90 is in the range ledger catalog")
	_check(RangeLedgerPage.PRODUCTS["p90"].get("power", "") == "32", "P90 range ledger power is 32")
	_check(RangeLedgerPage.PRODUCTS["p90"].get("range", "") == "90 米", "P90 range ledger range is 90 meters")
	var catalog_products: Array = RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG].get("products", [])
	_check(catalog_products.has("p90"), "base P90 is listed once in the range ledger")
	_check(not catalog_products.has("p90_ruralcamo") and not catalog_products.has("p90_snowcamo"), "P90 camouflage variants are not duplicated in the range ledger")

	var global_var := get_tree().root.get_node_or_null("GlobalVar")
	_check(global_var != null, "GlobalVar autoload exists")
	if global_var == null:
		return
	var base_product: Dictionary = global_var.call("get_shop_product", "p90")
	_check(not base_product.is_empty(), "base P90 has a shop product")
	_check(int(base_product.get("buy_price", 0)) == 2800 and int(base_product.get("sell_price", 0)) == 1960, "base P90 uses the planned shop price")
	_check(bool(global_var.call("is_shop_product_buyable", "gun_store", "p90")), "base P90 is buyable")
	_check(bool(global_var.call("is_shop_product_sellable", "gun_store", "p90")), "base P90 is sellable")
	var gun_store_ids: Array[String] = []
	for product: Dictionary in global_var.call("get_shop_products", "gun_store"):
		gun_store_ids.append(str(product.get("id", "")))
	_check(gun_store_ids.has("p90"), "gun store lists base P90")
	for variant_id in ["p90_ruralcamo", "p90_snowcamo"]:
		var variant_product: Dictionary = global_var.call("get_shop_product", variant_id)
		_check(variant_product.is_empty(), "%s has no shop product" % variant_id)
		_check(not bool(global_var.call("is_shop_product_buyable", "gun_store", variant_id)), "%s is not buyable" % variant_id)
		_check(not bool(global_var.call("is_shop_product_sellable", "gun_store", variant_id)), "%s is not sellable" % variant_id)
		_check(not gun_store_ids.has(variant_id), "%s is absent from the gun store list" % variant_id)

	var supply_ids: Array[String] = []
	for reward: Dictionary in SupplyRelayCatalog.get_reward_pool():
		supply_ids.append(str(reward.get("item_id", "")))
	_check(not supply_ids.has("p90") and not supply_ids.has("p90_ruralcamo") and not supply_ids.has("p90_snowcamo"), "P90 variants are not in the supply relay reward pool")


func _validate_get_ammo_and_authority() -> void:
	var authority := get_tree().root.get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		return
	authority.call("start_local_mode")
	var peer_id := 5090
	authority.call("register_or_update_player", peer_id, {
		"display_name": "P90Validation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(bool(authority.call("_uses_finite_ammo", tool_id)), "%s uses finite-ammo handling" % tool_id)
		_check(str(authority.call("_animation_action_for_tool", tool_id)) == "shooting", "%s uses shooting animation handling" % tool_id)
		_check(int(authority.call("_weapon_magazine_size", tool_id)) == 50, "%s authority magazine size is 50" % tool_id)
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call("_server_debug_get_tool", peer_id, state, "[get] %s 1" % tool_id)
		_check(bool(result.get("ok", false)), "[get] accepts %s" % tool_id)
		_check(str(result.get("tool_id", "")) == tool_id, "[get] preserves exact ID %s" % tool_id)
		state = authority.get("player_states").get(peer_id, {})
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		var ammo_state: Dictionary = ammo_states.get(tool_id, {})
		_check(int(ammo_state.get("ammo_in_mag", 0)) == 50, "%s starts with a 50-round magazine" % tool_id)
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
	var rural_ammo: Dictionary = ammo_states.get("p90_ruralcamo", {}).duplicate(true)
	var snow_ammo: Dictionary = ammo_states.get("p90_snowcamo", {}).duplicate(true)
	rural_ammo["ammo_in_mag"] = 17
	snow_ammo["ammo_in_mag"] = 8
	ammo_states["p90_ruralcamo"] = rural_ammo
	ammo_states["p90_snowcamo"] = snow_ammo
	state["weapon_ammo_states"] = ammo_states
	var player_states: Dictionary = authority.get("player_states")
	player_states[peer_id] = state
	_check(int((ammo_states.get("p90_ruralcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 17, "RuralCamo ammo state is independent")
	_check(int((ammo_states.get("p90_snowcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 8, "SnowCamo ammo state is independent")
	_check(int((ammo_states.get("p90", {}) as Dictionary).get("ammo_in_mag", 0)) == 50, "base P90 ammo state is not changed by skins")

	var shop_peer_id := 5091
	authority.call("register_or_update_player", shop_peer_id, {
		"display_name": "P90ShopValidation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	GlobalVar.add_item("red", "money", 10000.0)
	var money_before := GlobalVar.check_team_item_amount("red", "money")
	var purchase: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
		"action": "trade",
		"item_id": "p90",
		"amount": 1,
		"is_buy": true,
		"shop_category": "gun_store",
	})
	_check(bool(purchase.get("ok", false)), "base P90 completes a shop purchase")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 2800.0), "base P90 purchase charges 2800")
	var sale: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
		"action": "trade",
		"item_id": "p90",
		"amount": 1,
		"is_buy": false,
		"shop_category": "gun_store",
	})
	_check(bool(sale.get("ok", false)), "base P90 completes a shop sale")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 840.0), "base P90 sale returns 1960")
	for variant_id in ["p90_ruralcamo", "p90_snowcamo"]:
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
	authority.call("stop_authority")


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
		print("[P90WeaponValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[P90WeaponValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[P90WeaponValidation] PASS all checks")
		get_tree().quit(0)
		return
	print("[P90WeaponValidation] FAIL count=%d" % failures.size())
	get_tree().quit(1)
