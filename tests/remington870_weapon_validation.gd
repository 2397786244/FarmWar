extends Node

const VARIANTS := {
	"remington870": {
		"scene": "res://character/weapons/Remington870.tscn",
		"model": "res://assets/tools/Reminton870.glb",
	},
	"remington870_rusted": {
		"scene": "res://character/weapons/Remington870Rusted.tscn",
		"model": "res://assets/tools/other_styles/Rusted/Remington870_Rusted.glb",
	},
	"remington870_hardenedsteel": {
		"scene": "res://character/weapons/Remington870HardenedSteel.tscn",
		"model": "res://assets/tools/other_styles/HardenedSteel/Remington870_HardenedSteel.glb",
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
	_check(CombatBalance.resolve_profile_id("remington870") == "remington870", "base ID resolves to the Remington870 profile")
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(CombatBalance.is_profile(tool_id, "remington870"), "%s resolves to the Remington870 combat profile" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "damage"), 65.0), "%s pellet damage is 65" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "range"), 50.0), "%s range is 50" % tool_id)
		_check(CombatBalance.get_int(tool_id, "bullet_count") == 4, "%s fires four pellets" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "spread_degrees"), 3.0), "%s spread is 3 degrees" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "knockback"), 30.0), "%s knockback matches Shotgun" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_speed"), 100.0), "%s visual speed matches Shotgun" % tool_id)
		_check(is_equal_approx(CombatBalance.get_float(tool_id, "visual_lifetime"), 0.6), "%s visual lifetime matches Shotgun" % tool_id)
		var recoil := CombatBalance.get_model_recoil_offset(tool_id)
		_check(is_equal_approx(recoil.y, 0.068) and is_equal_approx(recoil.z, 0.170), "%s recoil matches Shotgun" % tool_id)
	_check(CombatBalance.get_int("shotgun", "bullet_count") == 6, "existing Shotgun still fires six pellets")
	_check(CombatBalance.get_float("remington870", "damage") > CombatBalance.get_float("shotgun", "damage"), "Remington870 pellet damage is higher than Shotgun")
	_check(CombatBalance.get_float("remington870", "range") < CombatBalance.get_float("shotgun", "range"), "Remington870 range is shorter than Shotgun")
	_check(CombatBalance.get_float("remington870", "spread_degrees") > CombatBalance.get_float("shotgun", "spread_degrees"), "Remington870 spread is wider than Shotgun")


func _validate_definitions_and_scenes() -> void:
	var tool_definitions := _read_json("res://data/tool_definitions.json")
	var primary_definitions := _read_json("res://data/primary_weapon_definitions.json")
	var tools_by_id := _definitions_by_id(tool_definitions.get("tools", []))
	var primary_by_id := _definitions_by_id(primary_definitions.get("weapons", []))
	var expected_tool_values := {
		"allow_multiple": true,
		"cooldown": 0.8,
		"magazine_size": 6,
		"initial_reserve_ammo": 0,
		"reload_time": 2.4,
		"category": "shooting",
		"two_handed": true,
		"aimable": true,
		"show_crosshair": true,
		"aim_fov": 60.0,
		"aim_speed": 12.0,
		"left_hand_grip_offset": [0.3, 0.6, -1.3],
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
		_check(is_equal_approx(float(primary_definition.get("power", 0.0)), 260.0), "%s primary power is 260" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("fire_rate", 0.0)), 1.25), "%s primary fire rate is 1.25" % tool_id)
		_check(is_equal_approx(float(primary_definition.get("cooldown", 0.0)), 0.8), "%s primary cooldown is 0.8" % tool_id)

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
			_check(str(weapon.get("profile_id")) == "remington870", "%s scene uses profile_id remington870" % tool_id)
			_check(weapon.get_node_or_null("Mesh") != null, "%s has Mesh" % tool_id)
			_check(weapon.get_node_or_null("Muzzle") != null, "%s has Muzzle" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlash") != null, "%s has MuzzleFlash" % tool_id)
			_check(weapon.get_node_or_null("Muzzle/MuzzleFlashVisual") != null, "%s has MuzzleFlashVisual" % tool_id)
			_check(weapon.get_node_or_null("LeftHandGrip") != null, "%s has LeftHandGrip" % tool_id)
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
		_check(FileAccess.file_exists("res://assets/icons/items/weapons/%s.png" % tool_id), "%s item icon exists" % tool_id)
		_check(ItemIconCatalog.get_tool_icon(tool_id) != null, "%s item icon resolves" % tool_id)
		var manifest_entry: Dictionary = manifest_by_id.get(tool_id, {})
		_check(str(manifest_entry.get("icon", "")) == "res://assets/icons/items/weapons/%s.png" % tool_id, "%s manifest path is registered" % tool_id)
		_check(str(manifest_entry.get("status", "")) == "rendered", "%s manifest status is rendered" % tool_id)
	_check(FileAccess.file_exists("res://assets/icons/rangeledger/remington870.png"), "Remington870 range ledger icon exists")
	_check(not RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG]["products"].has("remington870_rusted"), "Rusted variant is not duplicated in range ledger")
	_check(not RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG]["products"].has("remington870_hardenedsteel"), "HardenedSteel variant is not duplicated in range ledger")
	_check(RangeLedgerPage.PAGE_DEFINITIONS[RangeLedgerPage.PAGE_CATALOG]["products"].has("remington870"), "base Remington870 is in range ledger")

	var global_var := get_tree().root.get_node_or_null("GlobalVar")
	_check(global_var != null, "GlobalVar autoload exists")
	if global_var == null:
		return
	var base_product: Dictionary = global_var.call("get_shop_product", "remington870")
	_check(not base_product.is_empty(), "base Remington870 has a shop product")
	_check(int(base_product.get("buy_price", 0)) == 2200 and int(base_product.get("sell_price", 0)) == 1540, "base Remington870 uses the shared price")
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		if tool_id == "remington870":
			continue
		_check(global_var.call("get_shop_product", tool_id).is_empty(), "%s has no shop product" % tool_id)
		_check(not bool(global_var.call("is_shop_product_buyable", "gun_store", tool_id)), "%s is not buyable" % tool_id)
		_check(not bool(global_var.call("is_shop_product_sellable", "gun_store", tool_id)), "%s is not sellable" % tool_id)

	var supply_ids: Array[String] = []
	for reward: Dictionary in SupplyRelayCatalog.get_reward_pool():
		supply_ids.append(str(reward.get("item_id", "")))
	_check(not supply_ids.has("remington870") and not supply_ids.has("remington870_rusted") and not supply_ids.has("remington870_hardenedsteel"), "Remington870 variants are not in the supply relay reward pool")


func _validate_get_ammo_and_authority() -> void:
	var authority := get_tree().root.get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		return
	var peer_id := 5870
	authority.call("register_or_update_player", peer_id, {
		"display_name": "Remington870Validation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		_check(bool(authority.call("_uses_finite_ammo", tool_id)), "%s uses finite-ammo handling" % tool_id)
		_check(str(authority.call("_animation_action_for_tool", tool_id)) == "shooting", "%s uses shooting animation handling" % tool_id)
		_check(int(authority.call("_weapon_magazine_size", tool_id)) == 6, "%s authority magazine size is 6" % tool_id)
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call("_server_debug_get_tool", peer_id, state, "[get] %s 1" % tool_id)
		_check(bool(result.get("ok", false)), "[get] accepts %s" % tool_id)
		_check(str(result.get("tool_id", "")) == tool_id, "[get] preserves exact ID %s" % tool_id)
		state = authority.get("player_states").get(peer_id, {})
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		var ammo_state: Dictionary = ammo_states.get(tool_id, {})
		_check(int(ammo_state.get("ammo_in_mag", 0)) == 6, "%s starts with a six-round magazine" % tool_id)

		var shot_value: Variant = authority.call("_execute_tool", peer_id, tool_id, {
			"tool_id": tool_id,
			"tool_index": 0,
			"origin": Vector3.ZERO,
			"direction": Vector3.FORWARD,
		})
		var shot: Dictionary = shot_value as Dictionary if shot_value is Dictionary else {}
		var pellets: Variant = shot.get("pellet_results", [])
		_check(pellets is Array and (pellets as Array).size() == 4, "%s authority shot produces four pellet results" % tool_id)

	var shotgun_value: Variant = authority.call("_execute_tool", peer_id, "shotgun", {
		"tool_id": "shotgun",
		"tool_index": 0,
		"origin": Vector3.ZERO,
		"direction": Vector3.FORWARD,
	})
	var shotgun_shot: Dictionary = shotgun_value as Dictionary if shotgun_value is Dictionary else {}
	var shotgun_pellets: Variant = shotgun_shot.get("pellet_results", [])
	_check(shotgun_pellets is Array and (shotgun_pellets as Array).size() == 6, "existing Shotgun authority shot still produces six pellet results")

	var state: Dictionary = authority.get("player_states").get(peer_id, {})
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var rusted_ammo: Dictionary = ammo_states.get("remington870_rusted", {}).duplicate(true)
	var hardened_ammo: Dictionary = ammo_states.get("remington870_hardenedsteel", {}).duplicate(true)
	rusted_ammo["ammo_in_mag"] = 4
	hardened_ammo["ammo_in_mag"] = 2
	ammo_states["remington870_rusted"] = rusted_ammo
	ammo_states["remington870_hardenedsteel"] = hardened_ammo
	state["weapon_ammo_states"] = ammo_states
	var player_states: Dictionary = authority.get("player_states")
	player_states[peer_id] = state
	_check(int((ammo_states.get("remington870_rusted", {}) as Dictionary).get("ammo_in_mag", 0)) == 4, "Rusted ammo state is independent")
	_check(int((ammo_states.get("remington870_hardenedsteel", {}) as Dictionary).get("ammo_in_mag", 0)) == 2, "HardenedSteel ammo state is independent")
	_check(int((ammo_states.get("remington870", {}) as Dictionary).get("ammo_in_mag", 0)) == 6, "base Remington870 ammo state is not changed by skins")

	var shop_peer_id := 5871
	authority.call("register_or_update_player", shop_peer_id, {
		"display_name": "Remington870ShopValidation",
		"team": "red",
		"primary_weapon_ids": [],
		"special_tool_ids": [],
	})
	GlobalVar.add_item("red", "money", 10000.0)
	for id_value: Variant in VARIANTS.keys():
		var tool_id := str(id_value)
		if tool_id != "remington870":
			continue
		var purchase: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
			"action": "trade",
			"item_id": tool_id,
			"amount": 1,
			"is_buy": true,
			"shop_category": "gun_store",
		})
		_check(bool(purchase.get("ok", false)), "%s completes a shop purchase" % tool_id)
		var sale: Dictionary = authority.call("server_shop_transaction", shop_peer_id, {
			"action": "trade",
			"item_id": tool_id,
			"amount": 1,
			"is_buy": false,
			"shop_category": "gun_store",
		})
		_check(bool(sale.get("ok", false)), "%s completes a shop sale" % tool_id)


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
		print("[Remington870WeaponValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[Remington870WeaponValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[Remington870WeaponValidation] PASS all checks")
		get_tree().quit(0)
		return
	print("[Remington870WeaponValidation] FAIL count=%d" % failures.size())
	get_tree().quit(1)
