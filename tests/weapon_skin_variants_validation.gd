extends Node

const VARIANTS := {
	"ak47_ruralcamo": {"base": "ak47", "scene": "res://character/weapons/Ak47RuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/AK47_RuralCamo.glb", "style": "乡村迷彩"},
	"ak47_snowcamo": {"base": "ak47", "scene": "res://character/weapons/Ak47SnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/AK47_SnowCamo.glb", "style": "雪地迷彩"},
	"ar15_hardenedsteel": {"base": "ar15", "scene": "res://character/weapons/AR15HardenedSteel.tscn", "model": "res://assets/tools/other_styles/HardenedSteel/AR15_HardenedSteel.glb", "style": "淬火钢"},
	"ar15_ruralcamo": {"base": "ar15", "scene": "res://character/weapons/AR15RuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/AR15_RuralCamo.glb", "style": "乡村迷彩"},
	"ar15_snowcamo": {"base": "ar15", "scene": "res://character/weapons/AR15SnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/AR15_SnowCamo.glb", "style": "雪地迷彩"},
	"crossbow_hardenedsteel": {"base": "crossbow", "scene": "res://character/weapons/CrossbowHardenedSteel.tscn", "model": "res://assets/tools/other_styles/HardenedSteel/Crossbow_HardenedSteel.glb", "style": "淬火钢"},
	"m4_hardenedsteel": {"base": "m4", "scene": "res://character/weapons/M4HardenedSteel.tscn", "model": "res://assets/tools/other_styles/HardenedSteel/M4_HardenedSteel.glb", "style": "淬火钢"},
	"m4_ruralcamo": {"base": "m4", "scene": "res://character/weapons/M4RuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/M4_RuralCamo.glb", "style": "乡村迷彩"},
	"m4_snowcamo": {"base": "m4", "scene": "res://character/weapons/M4SnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/M4_SnowCamo.glb", "style": "雪地迷彩"},
	"mpx_hardenedsteel": {"base": "mpx", "scene": "res://character/weapons/MPXHardenedSteel.tscn", "model": "res://assets/tools/other_styles/HardenedSteel/MPX_HardenedSteel.glb", "style": "淬火钢"},
	"mpx_ruralcamo": {"base": "mpx", "scene": "res://character/weapons/MPXRuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/MPX_RuralCamo.glb", "style": "乡村迷彩"},
	"mpx_snowcamo": {"base": "mpx", "scene": "res://character/weapons/MPXSnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/MPX_SnowCamo.glb", "style": "雪地迷彩"},
	"remington870_ruralcamo": {"base": "remington870", "scene": "res://character/weapons/Remington870RuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/Remington870_RuralCamo.glb", "style": "乡村迷彩"},
	"remington870_snowcamo": {"base": "remington870", "scene": "res://character/weapons/Remington870SnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/Remington870_SnowCamo.glb", "style": "雪地迷彩"},
	"shotgun_rusted": {"base": "shotgun", "scene": "res://character/weapons/ShotgunRusted.tscn", "model": "res://assets/tools/other_styles/Rusted/Shotgun_Rusted.glb", "style": "锈铁"},
	"suppressed_pistol_hardenedsteel": {"base": "suppressed_pistol", "scene": "res://character/weapons/SuppressedPistolHardenedSteel.tscn", "model": "res://assets/tools/other_styles/HardenedSteel/SuppressedPistol_HardenedSteel.glb", "style": "淬火钢"},
	"suppressed_pistol_ruralcamo": {"base": "suppressed_pistol", "scene": "res://character/weapons/SuppressedPistolRuralCamo.tscn", "model": "res://assets/tools/other_styles/RuralCamo/SuppressedPistol_RuralCamo.glb", "style": "乡村迷彩"},
	"suppressed_pistol_snowcamo": {"base": "suppressed_pistol", "scene": "res://character/weapons/SuppressedPistolSnowCamo.tscn", "model": "res://assets/tools/other_styles/SnowCamo/SuppressedPistol_SnowCamo.glb", "style": "雪地迷彩"},
}

const BASE_SKINS := {
	"ak47": ["乡村迷彩", "雪地迷彩"],
	"ar15": ["淬火钢", "乡村迷彩", "雪地迷彩"],
	"crossbow": ["淬火钢"],
	"m4": ["淬火钢", "乡村迷彩", "雪地迷彩"],
	"mpx": ["淬火钢", "乡村迷彩", "雪地迷彩"],
	"remington870": ["乡村迷彩", "雪地迷彩"],
	"shotgun": ["锈铁"],
	"suppressed_pistol": ["淬火钢", "乡村迷彩", "雪地迷彩"],
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_profiles()
	_validate_definitions_and_scenes()
	_validate_icons_catalog_and_shop()
	_validate_get_and_ammo_isolation()
	_finish()


func _validate_profiles() -> void:
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		var base_id := str(VARIANTS[tool_id].get("base", ""))
		_check(CombatBalance.is_profile(tool_id, base_id), "%s resolves to %s" % [tool_id, base_id])
		for field_value: Variant in ["damage", "range", "knockback", "visual_speed", "visual_lifetime", "spread_degrees", "camera_recoil_strength", "camera_recoil_duration", "model_recoil_y", "model_recoil_z"]:
			var field := str(field_value)
			_check(is_equal_approx(CombatBalance.get_float(tool_id, field), CombatBalance.get_float(base_id, field)), "%s matches %s" % [tool_id, field])
		_check(CombatBalance.get_int(tool_id, "bullet_count") == CombatBalance.get_int(base_id, "bullet_count"), "%s keeps projectile count" % tool_id)


func _validate_definitions_and_scenes() -> void:
	var tool_definitions := _read_json("res://data/tool_definitions.json")
	var primary_definitions := _read_json("res://data/primary_weapon_definitions.json")
	var tool_values: Variant = tool_definitions.get("tools", [])
	var primary_values: Variant = primary_definitions.get("weapons", [])
	var tools_by_id := _definitions_by_id(tool_values)
	var primary_by_id := _definitions_by_id(primary_values)
	var shared_tool_fields := ["allow_multiple", "cooldown", "magazine_size", "initial_reserve_ammo", "reload_time", "category", "two_handed", "aimable", "show_crosshair", "aim_fov", "aim_speed", "grip_position", "grip_rotation", "grip_scale"]
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		var variant: Dictionary = VARIANTS[tool_id]
		var base_id := str(variant.get("base", ""))
		_check(_count_id(tool_values, tool_id) == 1, "%s appears once in tool definitions" % tool_id)
		_check(_count_id(primary_values, tool_id) == 1, "%s appears once in primary definitions" % tool_id)
		var definition: Dictionary = tools_by_id.get(tool_id, {})
		var base_definition: Dictionary = tools_by_id.get(base_id, {})
		_check(not definition.is_empty(), "%s has a tool definition" % tool_id)
		for field_value: Variant in shared_tool_fields:
			var field := str(field_value)
			_check(_value_matches(definition.get(field), base_definition.get(field)), "%s matches base %s" % [tool_id, field])
		_check(definition.get("category", "") == "shooting", "%s is a shooting item" % tool_id)
		_check(str(definition.get("name", "")).ends_with(str(variant.get("style", ""))), "%s has a Chinese style name" % tool_id)
		var primary_definition: Dictionary = primary_by_id.get(tool_id, {})
		var base_primary: Dictionary = primary_by_id.get(base_id, {})
		_check(not primary_definition.is_empty(), "%s has a primary definition" % tool_id)
		for field_value: Variant in ["power", "fire_rate", "cooldown"]:
			var field := str(field_value)
			_check(_value_matches(primary_definition.get(field), base_primary.get(field)), "%s matches base primary %s" % [tool_id, field])
		_check(primary_definition.get("loadout_selectable", true) == false, "%s is not loadout selectable" % tool_id)
		_check(str(definition.get("path", "")) == str(variant.get("scene", "")), "%s tool path is exact" % tool_id)
		_check(str(primary_definition.get("tool_scene", "")) == str(variant.get("scene", "")), "%s primary path is exact" % tool_id)

		var scene_path := str(variant.get("scene", ""))
		var model_path := str(variant.get("model", ""))
		_check(FileAccess.file_exists(model_path), "%s GLB exists" % tool_id)
		var scene_text := _read_text(scene_path)
		_check(scene_text.contains(model_path), "%s scene references its GLB" % tool_id)
		var packed_scene := load(scene_path) as PackedScene
		_check(packed_scene != null, "%s scene loads" % tool_id)
		if packed_scene == null:
			continue
		var weapon := packed_scene.instantiate()
		_check(weapon is Node3D, "%s instantiates" % tool_id)
		if weapon is Node3D:
			_check(str(weapon.get("profile_id")) == base_id, "%s profile_id is %s" % [tool_id, base_id])
			_check(weapon.get_node_or_null("Mesh") != null, "%s has Mesh" % tool_id)
			_check(weapon.get_node_or_null("Muzzle") != null, "%s has Muzzle" % tool_id)
			if base_id == "crossbow":
				_check(weapon is CrossbowTool, "%s keeps CrossbowTool" % tool_id)
				_check(weapon.find_child("LoadedBoltTip", true, false) != null, "%s keeps loaded bolt nodes" % tool_id)
			else:
				_check(weapon is NailFirearmTool, "%s keeps NailFirearmTool" % tool_id)
				_check(weapon.get_node_or_null("Muzzle/MuzzleFlash") != null, "%s has MuzzleFlash" % tool_id)
				_check(weapon.get_node_or_null("Muzzle/MuzzleFlashVisual") != null, "%s has MuzzleFlashVisual" % tool_id)
			if bool(definition.get("two_handed", false)):
				_check(weapon.get_node_or_null("LeftHandGrip") != null, "%s has LeftHandGrip" % tool_id)
		weapon.free()


func _validate_icons_catalog_and_shop() -> void:
	var manifest := _read_json("res://assets/icons/items/icon_manifest.json")
	var manifest_by_id := {}
	for item_value: Variant in manifest.get("items", []):
		if item_value is Dictionary:
			var item := item_value as Dictionary
			manifest_by_id[str(item.get("id", ""))] = item
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		var icon_path := "res://assets/icons/items/weapons/%s.png" % tool_id
		_check(FileAccess.file_exists(icon_path), "%s icon exists" % tool_id)
		_check(ItemIconCatalog.get_tool_icon(tool_id) != null, "%s icon resolves" % tool_id)
		var entry: Dictionary = manifest_by_id.get(tool_id, {})
		_check(str(entry.get("icon", "")) == icon_path, "%s icon manifest path is exact" % tool_id)
		_check(str(entry.get("status", "")) == "rendered", "%s icon is rendered" % tool_id)

	var catalog_products: Array = RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG].get("products", [])
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(not RangeLedgerPage.PRODUCTS.has(tool_id), "%s is not a separate range ledger product" % tool_id)
		_check(not catalog_products.has(tool_id), "%s is not duplicated in range ledger" % tool_id)
	for base_value: Variant in BASE_SKINS.keys():
		var base_id := str(base_value)
		var summary := str(RangeLedgerPage.PRODUCTS[base_id].get("summary", ""))
		for style_value: Variant in BASE_SKINS[base_id]:
			_check(summary.contains(str(style_value)), "%s summary names %s" % [base_id, str(style_value)])

	var global_var := get_tree().root.get_node_or_null("GlobalVar")
	_check(global_var != null, "GlobalVar autoload exists")
	if global_var != null:
		var gun_store_ids: Array[String] = []
		for product: Dictionary in global_var.call("get_shop_products", "gun_store"):
			gun_store_ids.append(str(product.get("id", "")))
		for id_value: Variant in VARIANTS.keys():
			var tool_id := str(id_value)
			_check(global_var.call("get_shop_product", tool_id).is_empty(), "%s has no shop product" % tool_id)
			_check(not bool(global_var.call("is_shop_product_buyable", "gun_store", tool_id)), "%s is not buyable" % tool_id)
			_check(not bool(global_var.call("is_shop_product_sellable", "gun_store", tool_id)), "%s is not sellable" % tool_id)
			_check(not gun_store_ids.has(tool_id), "%s is absent from gun store" % tool_id)

	var supply_ids: Array[String] = []
	for reward: Dictionary in SupplyRelayCatalog.get_reward_pool():
		supply_ids.append(str(reward.get("item_id", "")))
	for id_value: Variant in VARIANTS.keys():
		_check(not supply_ids.has(str(id_value)), "%s is absent from supply relay" % str(id_value))


func _validate_get_and_ammo_isolation() -> void:
	var authority := get_tree().root.get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		return
	authority.call("start_local_mode")
	var ids: Array = VARIANTS.keys()
	for index in range(ids.size()):
		var tool_id := str(ids[index])
		var peer_id := 78000 + index
		authority.call("register_or_update_player", peer_id, {"display_name": "SkinValidation_%s" % tool_id, "team": "red", "primary_weapon_ids": [], "special_tool_ids": []})
		_check(bool(authority.call("_uses_finite_ammo", tool_id)), "%s uses finite-ammo handling" % tool_id)
		_check(str(authority.call("_animation_action_for_tool", tool_id)) == "shooting", "%s uses shooting animation" % tool_id)
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call("_server_debug_get_tool", peer_id, state, "[get] %s 1" % tool_id)
		_check(bool(result.get("ok", false)), "[get] accepts %s" % tool_id)
		_check(str(result.get("tool_id", "")) == tool_id, "[get] preserves exact ID: %s" % tool_id)
		state = authority.get("player_states").get(peer_id, {})
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		_check(ammo_states.has(tool_id), "%s has an independent ammo state" % tool_id)
		_check(int((ammo_states.get(tool_id, {}) as Dictionary).get("ammo_in_mag", 0)) == int(authority.call("_weapon_magazine_size", tool_id)), "%s uses the configured magazine" % tool_id)

	var isolation_peer_id := 78100
	authority.call("register_or_update_player", isolation_peer_id, {"display_name": "SkinAmmoIsolation", "team": "red", "primary_weapon_ids": [], "special_tool_ids": []})
	for tool_id in ["ak47", "ak47_ruralcamo", "ak47_snowcamo"]:
		var isolation_state: Dictionary = authority.get("player_states").get(isolation_peer_id, {})
		_check(bool(authority.call("_server_debug_get_tool", isolation_peer_id, isolation_state, "[get] %s 1" % tool_id).get("ok", false)), "isolation peer gets %s" % tool_id)
	var state: Dictionary = authority.get("player_states").get(isolation_peer_id, {})
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var rural_ammo: Dictionary = (ammo_states.get("ak47_ruralcamo", {}) as Dictionary).duplicate(true)
	var snow_ammo: Dictionary = (ammo_states.get("ak47_snowcamo", {}) as Dictionary).duplicate(true)
	rural_ammo["ammo_in_mag"] = 11
	snow_ammo["ammo_in_mag"] = 4
	ammo_states["ak47_ruralcamo"] = rural_ammo
	ammo_states["ak47_snowcamo"] = snow_ammo
	state["weapon_ammo_states"] = ammo_states
	authority.get("player_states")[isolation_peer_id] = state
	_check(int((ammo_states.get("ak47", {}) as Dictionary).get("ammo_in_mag", 0)) == 30, "base AK47 ammo is not merged")
	_check(int((ammo_states.get("ak47_ruralcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 11, "RuralCamo ammo is independent")
	_check(int((ammo_states.get("ak47_snowcamo", {}) as Dictionary).get("ammo_in_mag", 0)) == 4, "SnowCamo ammo is independent")
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
	if actual is float or actual is int or expected is float or expected is int:
		return is_equal_approx(float(actual), float(expected))
	return actual == expected


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[WeaponSkinVariantsValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[WeaponSkinVariantsValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[WeaponSkinVariantsValidation] PASS all checks (18 variants)")
		get_tree().quit(0)
	else:
		print("[WeaponSkinVariantsValidation] FAIL count=%d" % failures.size())
		get_tree().quit(1)
