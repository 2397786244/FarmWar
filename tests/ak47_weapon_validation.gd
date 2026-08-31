extends Node

const VARIANTS := {
	"ak47": {
		"scene": "res://character/weapons/Ak47.tscn",
		"model": "res://assets/tools/AK47.glb",
	},
	"ak47_golden": {
		"scene": "res://character/weapons/Ak47Golden.tscn",
		"model": "res://assets/tools/other_styles/Golden/AK47_Golden.glb",
	},
	"ak47_rusted": {
		"scene": "res://character/weapons/Ak47Rusted.tscn",
		"model": "res://assets/tools/other_styles/Rusted/AK47_Rusted.glb",
	},
	"ak47_hardenedsteel": {
		"scene": "res://character/weapons/Ak47HardenedSteel.tscn",
		"model": "res://assets/tools/other_styles/HardenedSteel/AK47_HardenedSteel.glb",
	},
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_combat_profile()
	_validate_definitions_and_scenes()
	_validate_icons_and_catalogs()
	_validate_get_and_ammo_isolation()
	_finish()


func _validate_combat_profile() -> void:
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(CombatBalance.is_profile(tool_id, "ak47"), "%s resolves to the AK47 combat profile" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "damage"), 50.0), "%s damage is 50" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "range"), 120.0), "%s range is 120" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_speed"), 120.0), "%s visual speed is 120" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_lifetime"), 1.0), "%s visual lifetime is 1 second" % tool_id)
		_check(CombatBalance.get_int(tool_id, "bullet_count") == 1, "%s fires one bullet" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "spread_degrees"), 0.0), "%s has no spread" % tool_id)
		var recoil := CombatBalance.get_model_recoil_offset(tool_id)
		_check(is_equal_approx(recoil.y, 0.040) and is_equal_approx(recoil.z, 0.100), "%s shares AK47 model recoil" % tool_id)


func _validate_definitions_and_scenes() -> void:
	var tool_definitions := _read_json("res://data/tool_definitions.json")
	var primary_definitions := _read_json("res://data/primary_weapon_definitions.json")
	var tools_by_id := _definitions_by_id(tool_definitions.get("tools", []))
	var primary_by_id := _definitions_by_id(primary_definitions.get("weapons", []))
	var expected_tool_values := {
		"allow_multiple": true,
		"cooldown": 0.14,
		"magazine_size": 30,
		"initial_reserve_ammo": 0,
		"reload_time": 2.1,
		"category": "shooting",
		"two_handed": true,
		"aimable": true,
		"show_crosshair": true,
		"aim_fov": 45.0,
		"aim_speed": 15.0,
	}

	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		var definition: Dictionary = tools_by_id.get(tool_id, {})
		_check(not definition.is_empty(), "%s exists in tool_definitions.json" % tool_id)
		for field_value: Variant in expected_tool_values.keys():
			var field := str(field_value)
			_check(definition.get(field) == expected_tool_values[field], "%s has %s=%s" % [tool_id, field, str(expected_tool_values[field])])

		var primary_definition: Dictionary = primary_by_id.get(tool_id, {})
		_check(not primary_definition.is_empty(), "%s exists in primary_weapon_definitions.json" % tool_id)
		_check(primary_definition.get("loadout_selectable", true) == false, "%s is not loadout selectable" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("power", 0.0)), 50.0), "%s primary power is 50" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("fire_rate", 0.0)), 7.14), "%s primary fire rate is 7.14" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("cooldown", 0.0)), 0.14), "%s primary cooldown is 0.14" % tool_id)

		var scene_path := str(VARIANTS[tool_id].get("scene", ""))
		var scene_text := _read_text(scene_path)
		_check(scene_text.contains(str(VARIANTS[tool_id].get("model", ""))), "%s scene references its own GLB" % tool_id)
		var scene := load(scene_path) as PackedScene
		_check(scene != null, "%s scene loads" % tool_id)
		if scene == null:
			continue
		var weapon := scene.instantiate()
		_check(weapon is Node3D, "%s scene instantiates as Node3D" % tool_id)
		if weapon is Node3D:
			_check(weapon is NailFirearmTool, "%s uses NailFirearmTool" % tool_id)
			_check(str(weapon.get("profile_id")) == "ak47", "%s scene uses profile_id ak47" % tool_id)
			_check(weapon.get_node_or_null("Mesh") != null, "%s has Mesh" % tool_id)
			_check(weapon.get_node_or_null("Muzzle") != null, "%s has Muzzle" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlash") != null, "%s has MuzzleFlash" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlashVisual") != null, "%s has MuzzleFlashVisual" % tool_id)
			_check(weapon.get_node_or_null("LeftHandGrip") != null, "%s has LeftHandGrip" % tool_id)
		weapon.free()


func _validate_icons_and_catalogs() -> void:
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(FileAccess.file_exists("res://assets/icons/items/weapons/%s.png" % tool_id), "%s item icon exists" % tool_id)
		_check(ItemIconCatalog.get_tool_icon(tool_id) != null, "%s item icon resolves" % tool_id)
	_check(FileAccess.file_exists("res://assets/icons/rangeledger/ak47.png"), "AK47 range ledger icon exists")
	var global_var := get_tree().root.get_node_or_null("GlobalVar")
	_check(global_var != null, "GlobalVar autoload exists")
	if global_var == null:
		return
	_check(bool(global_var.call("is_shop_product_buyable", "gun_store", "ak47")), "AK47 is buyable")
	_check(bool(global_var.call("is_shop_product_sellable", "gun_store", "ak47")), "AK47 is sellable")
	var base_product: Dictionary = global_var.call("get_shop_product", "ak47")
	_check(not base_product.is_empty(), "base AK47 has a shop product")
	_check(int(base_product.get("buy_price", 0)) == 3500 and int(base_product.get("sell_price", 0)) == 2450, "base AK47 uses the shared price")
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		if tool_id == "ak47":
			continue
		_check(global_var.call("get_shop_product", tool_id).is_empty(), "%s has no shop product" % tool_id)
		_check(not bool(global_var.call("is_shop_product_buyable", "gun_store", tool_id)), "%s is not buyable" % tool_id)
		_check(not bool(global_var.call("is_shop_product_sellable", "gun_store", tool_id)), "%s is not sellable" % tool_id)


func _validate_get_and_ammo_isolation() -> void:
	var authority := get_tree().root.get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		return
	var peer_id := 3047
	authority.call("register_or_update_player", peer_id, {
		"display_name": "AK47Validation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(bool(authority.call("_uses_finite_ammo", tool_id)), "%s uses finite-ammo handling" % tool_id)
		_check(str(authority.call("_animation_action_for_tool", tool_id)) == "shooting", "%s uses shooting animation handling" % tool_id)
		_check(int(authority.call("_weapon_magazine_size", tool_id)) == 30, "%s authority magazine size is 30" % tool_id)
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call("_server_debug_get_tool", peer_id, state, "[get] %s 1" % tool_id)
		_check(bool(result.get("ok", false)), "[get] accepts %s" % tool_id)
		_check(str(result.get("tool_id", "")) == tool_id, "[get] preserves exact ID %s" % tool_id)
		state = authority.get("player_states").get(peer_id, {})
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		var ammo_state: Dictionary = ammo_states.get(tool_id, {})
		_check(int(ammo_state.get("ammo_in_mag", 0)) == 30, "%s starts with a 30-round magazine" % tool_id)

	var state: Dictionary = authority.get("player_states").get(peer_id, {})
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var golden_ammo: Dictionary = ammo_states.get("ak47_golden", {}).duplicate(true)
	var rusted_ammo: Dictionary = ammo_states.get("ak47_rusted", {}).duplicate(true)
	golden_ammo["ammo_in_mag"] = 12
	rusted_ammo["ammo_in_mag"] = 7
	ammo_states["ak47_golden"] = golden_ammo
	ammo_states["ak47_rusted"] = rusted_ammo
	state["weapon_ammo_states"] = ammo_states
	var player_states: Dictionary = authority.get("player_states")
	player_states[peer_id] = state
	_check(int((ammo_states.get("ak47_golden", {}) as Dictionary).get("ammo_in_mag", 0)) == 12, "Golden ammo state is independent")
	_check(int((ammo_states.get("ak47_rusted", {}) as Dictionary).get("ammo_in_mag", 0)) == 7, "Rusted ammo state is independent")
	_check(int((ammo_states.get("ak47", {}) as Dictionary).get("ammo_in_mag", 0)) == 30, "base AK47 ammo state is not changed by skins")


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


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[AK47WeaponValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[AK47WeaponValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[AK47WeaponValidation] PASS all checks")
		get_tree().quit(0)
		return
	print("[AK47WeaponValidation] FAIL count=%d" % failures.size())
	get_tree().quit(1)
