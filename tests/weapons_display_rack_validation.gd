extends Node

const RACK_SCENE := preload("res://facilities/interior/weapons_display_rack.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var definition: Dictionary = GameAuthority.authoritative_tool_definitions.get("weapons_display_rack", {})
	_check(not definition.is_empty(), "rack backpack definition exists")
	_check(bool(definition.get("free_placement", false)), "rack uses free placement")
	_check(bool(definition.get("consumed_on_use", false)), "placement consumes backpack item")
	_check(str(definition.get("category", "")) == "utility", "rack is a utility item")
	_check(GlobalVar.get_shop_product("weapons_display_rack").is_empty(), "rack is not sold in shops")
	_check(FileAccess.file_exists("res://assets/icons/items/tools/weapons_display_rack.png"), "rack item icon exists")

	var rack := RACK_SCENE.instantiate() as Node3D
	get_tree().root.add_child(rack)
	_check(rack != null, "rack scene instantiates")
	if rack != null:
		_check((rack as CollisionObject3D).collision_layer == 128, "rack body uses tool collision layer")
		_check((rack as CollisionObject3D).collision_mask == 0, "rack body collision mask is zero")
		_check(bool(rack.get("indestructible")), "rack is marked indestructible")
		_check(rack.is_in_group("persistent_placed_storage"), "rack uses the common placed-storage group")
		_check(rack.has_method("get_persistent_storage_state"), "rack exposes the storage-state reader")
		_check(rack.has_method("apply_persistent_storage_state"), "rack exposes the storage-state applier")
		for index in range(3):
			var marker_name: String = ["Bottom", "Medium", "Top"][index]
			var area := rack.get_node_or_null("%s/InteractionArea" % marker_name) as Area3D
			_check(area != null, "%s slot interaction area exists" % marker_name)
			if area != null:
				_check(area.collision_layer == 512, "%s area uses interaction layer" % marker_name)
				_check(area.collision_mask == 8, "%s area detects players" % marker_name)
				_check(int(area.get("slot_index")) == index, "%s slot index is stable" % marker_name)

		var weapon := {
			"kind": "tool", "tool_id": "ak47_golden", "tool_bucket": "primary_weapon_ids",
			"ammo_in_mag": 17, "reserve_ammo": 0, "weight_kg": 0.0,
		}
		_check(bool(rack.call("set_rack_slot_item", 1, weapon)), "rack accepts exact weapon item state")
		var stored: Dictionary = rack.call("get_rack_slot_item", 1)
		_check(str(stored.get("tool_id", "")) == "ak47_golden", "skin ID remains exact")
		_check(int(stored.get("ammo_in_mag", -1)) == 17, "magazine state remains exact")
		var visual_state: Dictionary = rack.call("get_network_visual_state")
		rack.call("apply_network_visual_state", visual_state)
		_check(str((rack.call("get_rack_slot_item", 1) as Dictionary).get("tool_id", "")) == "ak47_golden", "network visual state round-trips")

		GameAuthority.start_local_mode()
		var rack_get_peer := 8450
		GameAuthority.register_or_update_player(rack_get_peer, {
			"display_name": "RackGetValidation", "team": "blue",
			"primary_weapon_ids": [], "special_tool_ids": [],
		})
		var rack_get_state: Dictionary = GameAuthority.player_states.get(rack_get_peer, {})
		var rack_get_result: Dictionary = GameAuthority.call(
			"_server_debug_get_tool", rack_get_peer, rack_get_state, "[get] weapons_display_rack 1"
		)
		_check(bool(rack_get_result.get("ok", false)), "[get] supplies the weapon display rack")
		_check(GameAuthority.player_states.get(rack_get_peer, {}).get("special_tool_ids", []).has("weapons_display_rack"), "[get] stores the rack in the backpack")

		var peer_id := 8451
		GameAuthority.register_or_update_player(peer_id, {
			"display_name": "RackValidation", "team": "blue",
			"primary_weapon_ids": [], "special_tool_ids": [],
		})
		var player_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
		var get_result: Dictionary = GameAuthority.call(
			"_server_debug_get_tool", peer_id, player_state, "[get] ak47_rusted 1"
		)
		_check(bool(get_result.get("ok", false)), "[get] supplies a rack-compatible exact skin ID")
		player_state = GameAuthority.player_states.get(peer_id, {})
		var weapon_slot := -1
		var slots: Array = player_state.get("backpack_slot_items", [])
		for slot_index in range(slots.size()):
			if slots[slot_index] is Dictionary and str((slots[slot_index] as Dictionary).get("tool_id", "")) == "ak47_rusted":
				weapon_slot = slot_index
				break
		_check(weapon_slot >= 0, "granted weapon has a backpack slot")
		player_state["current_tool_index"] = weapon_slot
		player_state["position"] = rack.global_position
		var ammo_states: Dictionary = player_state.get("weapon_ammo_states", {})
		var rusted_ammo: Dictionary = ammo_states.get("ak47_rusted", {})
		rusted_ammo["ammo_in_mag"] = 9
		ammo_states["ak47_rusted"] = rusted_ammo
		player_state["weapon_ammo_states"] = ammo_states
		GameAuthority.player_states[peer_id] = player_state
		rack.set_meta("map_editor_category", "facility")
		rack.add_to_group("network_map_facilities")
		GameAuthority.register_map_placed_tool(rack, "weapons_display_rack", "rack_validation_id", "red")
		var put_result := GameAuthority.server_weapon_display_rack_action(peer_id, {
			"rack_id": "rack_validation_id", "slot_index": 0, "backpack_slot": weapon_slot,
			"expected_occupied": false,
		})
		_check(bool(put_result.get("ok", false)), "server atomically puts a shooting weapon on the rack")
		_check(str((rack.call("get_rack_slot_item", 0) as Dictionary).get("tool_id", "")) == "ak47_rusted", "server preserves exact rusted skin ID")
		_check(int((rack.call("get_rack_slot_item", 0) as Dictionary).get("ammo_in_mag", -1)) == 9, "server preserves the current magazine")
		var stale_result := GameAuthority.server_weapon_display_rack_action(peer_id, {
			"rack_id": "rack_validation_id", "slot_index": 0, "backpack_slot": weapon_slot,
			"expected_occupied": false,
		})
		_check(not bool(stale_result.get("ok", false)) and str(stale_result.get("reason", "")) == "rack_slot_changed", "stale concurrent slot request cannot reverse the first action")
		var take_result := GameAuthority.server_weapon_display_rack_action(peer_id, {
			"rack_id": "rack_validation_id", "slot_index": 0, "backpack_slot": weapon_slot,
			"expected_occupied": true,
		})
		_check(bool(take_result.get("ok", false)), "server atomically takes a displayed weapon")
		_check((rack.call("get_rack_slot_item", 0) as Dictionary).is_empty(), "taken rack slot becomes empty")
		player_state = GameAuthority.player_states.get(peer_id, {})
		_check(int((player_state.get("weapon_ammo_states", {}) as Dictionary).get("ak47_rusted", {}).get("ammo_in_mag", -1)) == 9, "taken weapon restores the current magazine")

		var expanded_peer := 8452
		GameAuthority.register_or_update_player(expanded_peer, {
			"display_name": "ExpandedBagValidation", "team": "red",
			"primary_weapon_ids": [], "special_tool_ids": [],
		})
		var expanded_state: Dictionary = GameAuthority.player_states.get(expanded_peer, {})
		var backpack_get: Dictionary = GameAuthority.call(
			"_server_debug_get_tool", expanded_peer, expanded_state, "[get] backpack_military 1"
		)
		_check(bool(backpack_get.get("ok", false)), "validation can acquire a military backpack")
		expanded_state = GameAuthority.player_states.get(expanded_peer, {})
		var backpack_slot := -1
		var expanded_slots: Array = expanded_state.get("backpack_slot_items", [])
		for slot_index in range(expanded_slots.size()):
			if expanded_slots[slot_index] is Dictionary and str((expanded_slots[slot_index] as Dictionary).get("equipment_id", "")) == "backpack_military":
				backpack_slot = slot_index
				break
		var equip_result: Dictionary = GameAuthority.server_equipment_action(expanded_peer, {
			"action": "equip", "equipment_type": "backpack", "equipment_id": "backpack_military",
			"slot_index": backpack_slot, "overflow_items": [],
		})
		_check(bool(equip_result.get("ok", false)), "military backpack equips before expanded get")
		expanded_state = GameAuthority.player_states.get(expanded_peer, {})
		expanded_slots = (expanded_state.get("backpack_slot_items", []) as Array).duplicate(true)
		expanded_slots.resize(12)
		expanded_state["backpack_slot_items"] = expanded_slots
		expanded_state["backpack_layout_valid"] = true
		expanded_state["equipped_backpack_id"] = "backpack_military"
		GameAuthority.player_states[expanded_peer] = expanded_state
		var expanded_get: Dictionary = GameAuthority.call(
			"_server_debug_get_tool", expanded_peer, expanded_state, "[get] weapons_display_rack 1"
		)
		_check(bool(expanded_get.get("ok", false)), "[get] repairs stale base-only layout after backpack expansion")
		_check((GameAuthority.player_states.get(expanded_peer, {}).get("backpack_slot_items", []) as Array).size() == 24, "[get] uses all expanded backpack slots")
		expanded_state = GameAuthority.player_states.get(expanded_peer, {}).duplicate(true)
		expanded_state["backpack_layout_valid"] = false
		GameAuthority.player_states[expanded_peer] = expanded_state
		var invalid_flag_get: Dictionary = GameAuthority.call(
			"_server_debug_get_tool", expanded_peer, expanded_state, "[get] weapons_display_rack 1"
		)
		_check(bool(invalid_flag_get.get("ok", false)), "[get] repairs a stale invalid-layout flag when slots remain available")

		var persistent_world: Dictionary = WorldPersistence.capture_world_state()
		var saved_rack: Dictionary = {}
		for saved_value: Variant in persistent_world.get("placed_tools", []):
			if saved_value is Dictionary and str((saved_value as Dictionary).get("tool_id", "")) == "rack_validation_id":
				saved_rack = saved_value as Dictionary
				break
		_check(not saved_rack.is_empty(), "world save includes the placed rack")
		_check((saved_rack.get("rack_slots", []) as Array).size() == 3, "world save includes all rack slots")
		_check(str(((saved_rack.get("rack_slots", []) as Array)[1] as Dictionary).get("tool_id", "")) == "ak47_golden", "world save preserves displayed weapon ID")
		_check(not bool(saved_rack.get("free_placement", true)), "world save keeps map rack as static")
		_check((saved_rack.get("storage_state", {}) as Dictionary).has("rack_slots"), "map rack save uses the common storage state")
		rack.call("set_rack_slot_item", 1, {})
		WorldPersistence.call("_restore_persistent_tools", [saved_rack])
		_check(str((rack.call("get_rack_slot_item", 1) as Dictionary).get("tool_id", "")) == "ak47_golden", "existing map rack restores displayed weapon")

		var free_world := Node3D.new()
		free_world.name = "RackValidationWorld"
		get_tree().root.add_child(free_world)
		GlobalVar.gameworld = free_world
		var free_rack := RACK_SCENE.instantiate() as Node3D
		free_world.add_child(free_rack)
		free_rack.set_meta("network_device_id", "free_rack_validation_id")
		free_rack.global_position = Vector3(20.0, 0.0, 0.0)
		free_rack.call("set_rack_slot_item", 2, weapon)
		GameAuthority.placed_tool_states["free_rack_validation_id"] = {
			"tool_id": "free_rack_validation_id", "device_id": "free_rack_validation_id",
			"tool_name": "weapons_display_rack", "path": str(free_rack.get_path()),
			"scene_path": "res://facilities/interior/weapons_display_rack.tscn",
			"position": free_rack.global_position, "yaw": free_rack.rotation.y,
			"free_placement": true, "map_static": false, "indestructible": true,
		}
		var free_world_state: Dictionary = WorldPersistence.capture_world_state()
		var saved_free_rack: Dictionary = {}
		for saved_value: Variant in free_world_state.get("placed_tools", []):
			if saved_value is Dictionary and str((saved_value as Dictionary).get("tool_id", "")) == "free_rack_validation_id":
				saved_free_rack = saved_value as Dictionary
				break
		_check(not saved_free_rack.is_empty(), "world save includes the player-placed rack")
		_check(bool(saved_free_rack.get("free_placement", false)), "player-placed rack remains free placement")
		_check(str(((saved_free_rack.get("storage_state", {}) as Dictionary).get("rack_slots", [])[2] as Dictionary).get("tool_id", "")) == "ak47_golden", "player rack save preserves displayed weapon")
		free_rack.queue_free()
		await get_tree().process_frame
		WorldPersistence.call("_restore_persistent_tools", [saved_free_rack])
		var restored_free_rack: Node3D = null
		for rack_value: Variant in get_tree().get_nodes_in_group("weapon_display_racks"):
			if rack_value is Node3D and str((rack_value as Node3D).get_meta("network_device_id", "")) == "free_rack_validation_id":
				restored_free_rack = rack_value as Node3D
				break
		_check(restored_free_rack != null, "player-placed rack is regenerated from the world save")
		if restored_free_rack != null:
			_check(str((restored_free_rack.call("get_rack_slot_item", 2) as Dictionary).get("tool_id", "")) == "ak47_golden", "regenerated player rack restores displayed weapon")
		free_world.queue_free()
		rack.queue_free()

	for tool_value: Variant in GameAuthority.authoritative_tool_definitions.values():
		if not tool_value is Dictionary:
			continue
		var tool := tool_value as Dictionary
		if str(tool.get("category", "")) == "shooting":
			_check(not str(tool.get("path", "")).is_empty(), "%s shooting weapon has a display scene" % str(tool.get("id", "")))
	_finish()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[WeaponsDisplayRackValidation] PASS")
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[WeaponsDisplayRackValidation] " + failure)
	get_tree().quit(1)
