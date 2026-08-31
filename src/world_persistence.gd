extends Node
class_name WorldPersistenceService

## Shared authority-side world snapshot codec used by cooperative hosts and
## persistent single-player worlds. Transient interaction ownership is always
## cleared while capturing/restoring so a save cannot resurrect stale locks.

const FARM_RESTORE_WAIT_FRAMES := 120
const VehicleColorCatalogScript = preload("res://src/vehicle_color_catalog.gd")
const PlacedStorageState = preload("res://src/placed_storage_state.gd")
const WORLD_CLOCK_SCHEMA_VERSION := 1


func make_initial_team_storage() -> Dictionary:
	var initial_storage: Dictionary = {}
	for team_id_value: Variant in GlobalVar.team_storage.keys():
		var team := str(team_id_value)
		var current_inventory: Variant = GlobalVar.team_storage[team_id_value]
		if not current_inventory is Dictionary:
			continue
		var inventory: Dictionary = {}
		for item_id_value: Variant in (current_inventory as Dictionary).keys():
			var item_id := str(item_id_value)
			inventory[item_id] = float(GlobalVar.INITIAL_MONEY) if item_id == "money" else 0.0
		initial_storage[team] = inventory
	return initial_storage


func capture_world_clock_state() -> Dictionary:
	var clock: Dictionary = {}
	var day_night_system := get_tree().get_first_node_in_group("day_night_systems")
	if day_night_system != null and day_night_system.has_method("get_persistent_state"):
		var value: Variant = day_night_system.call("get_persistent_state")
		if value is Dictionary:
			clock = (value as Dictionary).duplicate(true)
	if not clock.has("elapsed_seconds"):
		clock["elapsed_seconds"] = GameAuthority.get_world_elapsed_seconds() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_world_elapsed_seconds") else 0.0
	var elapsed_seconds := maxf(0.0, float(clock.get("elapsed_seconds", 0.0)))
	var total_hours := float(clock.get(
		"total_hours", 8.0 + elapsed_seconds / 1440.0 * 24.0
	))
	var day_index := int(clock.get("day_index", floori(total_hours / 24.0)))
	var hour := fposmod(float(clock.get("hour", total_hours)), 24.0)
	clock["schema_version"] = WORLD_CLOCK_SCHEMA_VERSION
	clock["elapsed_seconds"] = elapsed_seconds
	clock["total_hours"] = total_hours
	clock["day_index"] = day_index
	clock["hour"] = hour
	clock["game_day"] = maxi(1, day_index + 1)
	return clock


func get_saved_world_clock_state(active_world: Dictionary) -> Dictionary:
	var world_state_value: Variant = active_world.get("world_state", {})
	var world_state: Dictionary = world_state_value as Dictionary if world_state_value is Dictionary else {}
	var state_clock_value: Variant = world_state.get("world_clock", {})
	var state_clock: Dictionary = state_clock_value as Dictionary if state_clock_value is Dictionary else {}
	var top_level_clock_value: Variant = active_world.get("world_clock", {})
	var top_level_clock: Dictionary = top_level_clock_value as Dictionary \
		if top_level_clock_value is Dictionary else {}
	# Only the new structured clock is trusted. Older saves used a similarly
	# named scalar that was accumulated from wall-clock time rather than from the
	# simulation, so treating that value as gameplay time would shift the map on
	# first load. Missing structured state intentionally falls back to the map's
	# default start time (elapsed = 0).
	var clock := state_clock if state_clock.has("elapsed_seconds") else top_level_clock
	if not clock.has("elapsed_seconds"):
		clock = {
			"schema_version": WORLD_CLOCK_SCHEMA_VERSION,
			"elapsed_seconds": 0.0,
		}
	clock["elapsed_seconds"] = maxf(0.0, float(clock.get("elapsed_seconds", 0.0)))
	return clock


func apply_world_clock_state(active_world: Dictionary) -> void:
	var clock := get_saved_world_clock_state(active_world)
	var elapsed_seconds := float(clock.get("elapsed_seconds", 0.0))
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("set_world_elapsed_seconds"):
		GameAuthority.set_world_elapsed_seconds(elapsed_seconds)
	var day_night_system := get_tree().get_first_node_in_group("day_night_systems")
	if day_night_system != null and day_night_system.has_method("apply_persistent_state"):
		day_night_system.call("apply_persistent_state", clock)


func apply_saved_weather_state(active_world: Dictionary) -> void:
	var world_state_value: Variant = active_world.get("world_state", {})
	var world_state: Dictionary = world_state_value as Dictionary \
		if world_state_value is Dictionary else {}
	_apply_saved_weather_state(world_state.get("weather", {}))


func capture_world_state() -> Dictionary:
	var world_clock := capture_world_clock_state()
	var weather_state: Dictionary = {}
	var weather_system := get_tree().get_first_node_in_group("weather_systems")
	if weather_system != null and weather_system.has_method("get_persistent_state"):
		weather_state = weather_system.call("get_persistent_state") as Dictionary
	var farm_tiles: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if not node is FarmTile:
			continue
		var tile := node as FarmTile
		var state := tile.get_authoritative_state()
		if not str(state.get("land_owner", "")).is_empty() \
				or not str(state.get("seed_record", "")).is_empty() \
				or bool(state.get("has_tool", false)):
			farm_tiles.append(state)

	var vehicles: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		if not vehicle.vehicle_deployed or vehicle.is_queued_for_deletion():
			continue
		var vehicle_id := vehicle.get_vehicle_id()
		var state := vehicle.get_network_state()
		state["vehicle_id"] = vehicle_id
		var authority_vehicle_state: Dictionary = GameAuthority.vehicle_states.get(vehicle_id, {})
		state["scene_path"] = str(authority_vehicle_state.get("scene_path", vehicle.scene_file_path))
		if str(state["scene_path"]).is_empty() and vehicle_id.contains("cargo_car"):
			state["scene_path"] = "res://vehicles/red_cargo_car.tscn"
		state["driver_peer_id"] = 0
		state["seat_occupants"] = []
		var machine_gun_value: Variant = state.get("platform_machine_gun", {})
		if machine_gun_value is Dictionary:
			var machine_gun_state := (machine_gun_value as Dictionary).duplicate(true)
			machine_gun_state["operator_peer_id"] = 0
			state["platform_machine_gun"] = machine_gun_state
		var garage_vehicle_id := str(authority_vehicle_state.get("garage_vehicle_id", ""))
		if garage_vehicle_id.is_empty() and vehicle.has_meta("garage_vehicle_id"):
			garage_vehicle_id = str(vehicle.get_meta("garage_vehicle_id", ""))
		if not garage_vehicle_id.is_empty():
			var garage_record := GameAuthority.get_team_garage_record(garage_vehicle_id) \
				if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_team_garage_record") else {}
			state["garage_vehicle_id"] = garage_vehicle_id
			state["body_color_id"] = str(authority_vehicle_state.get(
				"body_color_id", garage_record.get("body_color_id", "black")
			))
			state["wheel_color_id"] = str(authority_vehicle_state.get(
				"wheel_color_id", garage_record.get("wheel_color_id", "black")
			))
		vehicles.append(state)

	var placed_tools: Array[Dictionary] = []
	for raw_tool_id: Variant in GameAuthority.placed_tool_states.keys():
		var registry_tool_id := str(raw_tool_id)
		var state_value: Variant = GameAuthority.placed_tool_states[raw_tool_id]
		if not state_value is Dictionary:
			continue
		var state := (state_value as Dictionary).duplicate(true)
		# A map facility can be interacted with before it has a full dynamic
		# placement record. Keep the registry key as a fallback ID so a state
		# created by a rack action is not silently discarded.
		var tool_id := str(state.get("tool_id", state.get("device_id", registry_tool_id)))
		if tool_id.is_empty():
			tool_id = registry_tool_id
		state["tool_id"] = tool_id
		if str(state.get("device_id", "")).is_empty():
			state["device_id"] = tool_id
		var tool_node: Variant = GameAuthority.call(
			"_node_for_tool_ref", {"kind": "placed", "id": registry_tool_id}
		)
		if tool_node == null:
			var saved_path := str(state.get("path", tool_id))
			if not saved_path.is_empty():
				tool_node = get_tree().root.get_node_or_null(NodePath(saved_path))
		if tool_node == null:
			tool_node = _find_persistent_tool(tool_id)
		var storage_state := PlacedStorageState.capture(tool_node as Node if tool_node is Node else null)
		var visual_state: Dictionary = storage_state.duplicate(true)
		if tool_node is Node and tool_node.has_method("get_network_visual_state"):
			var visual_value: Variant = tool_node.call("get_network_visual_state")
			if visual_value is Dictionary:
				visual_state = (visual_value as Dictionary).duplicate(true)
		if not storage_state.is_empty():
			state["storage_state"] = storage_state
		if tool_node is WireMeshGate:
			state["is_open"] = (tool_node as WireMeshGate).is_open
			state["open_angle_degrees"] = (tool_node as WireMeshGate).open_angle_degrees
		if not visual_state.is_empty():
			state["visual_state"] = visual_state
			if visual_state.has("rack_slots"):
				state["rack_slots"] = visual_state.get("rack_slots", []).duplicate(true)
		# Besides free-placed objects and cargo crates, persist registered
		# facilities that implement the explicit storage protocol. The legacy
		# rack fields remain accepted so existing saves upgrade cleanly; a merely
		# present network visual state is not enough to turn a combat device into
		# a persistent container.
		var has_persistent_storage_state := not storage_state.is_empty() \
				or state.has("rack_slots") \
				or state.has("crate_data") \
				or (state.get("storage_state", {}) is Dictionary \
				and not (state.get("storage_state", {}) as Dictionary).is_empty())
		if bool(state.get("free_placement", false)) \
				or str(state.get("tool_name", "")) == "cargo_crate" \
				or has_persistent_storage_state:
			placed_tools.append(state)
	for node in get_tree().get_nodes_in_group("cargo_crates"):
		if not node is CargoCrateGround:
			continue
		var crate := node as CargoCrateGround
		var crate_id := str(crate.get_meta("network_device_id", crate.get_path()))
		for index in range(placed_tools.size()):
			if str(placed_tools[index].get("tool_id", "")) == crate_id:
				placed_tools[index]["crate_data"] = crate.get_crate_data()
				placed_tools[index]["position"] = crate.global_position
				placed_tools[index]["yaw"] = crate.rotation.y
				break

	var livestock: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if not node is FarmLivestock:
			continue
		var animal := node as FarmLivestock
		if not animal.naturally_spawned and not animal.housed_in_chop and not animal.destroyed:
			livestock.append(animal.get_persistent_state())

	return {
		"team_storage": GlobalVar.team_storage.duplicate(true),
		"team_inventory": (GlobalVar.team_storage.get("red", {}) as Dictionary).duplicate(true),
		"farm_tiles": farm_tiles,
		"vehicles": vehicles,
		"destroyed_vehicle_ids": GameAuthority.get_persistent_destroyed_vehicle_ids() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_persistent_destroyed_vehicle_ids") else [],
		"placed_tools": placed_tools,
		"livestock": livestock,
		"stations": _capture_station_states(),
		"team_garages": GameAuthority.get_persistent_team_garage_states() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_persistent_team_garage_states") else {},
		"pending_garage_repairs": GameAuthority.get_persistent_pending_garage_repairs() \
			if is_instance_valid(GameAuthority) and GameAuthority.has_method("get_persistent_pending_garage_repairs") else [],
		"embedded_lab_teams": GameAuthority.get_persistent_team_embedded_lab_states() \
			if is_instance_valid(GameAuthority) else {},
		"world_clock": world_clock,
		"weather": weather_state,
	}


func restore_world_state(
	scene: Node3D,
	active_world: Dictionary,
	restore_authority_entities := true
) -> bool:
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		return false
	var state_value: Variant = active_world.get("world_state", {})
	var world_state: Dictionary = state_value as Dictionary if state_value is Dictionary else {}
	apply_world_clock_state(active_world)
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("apply_persistent_team_garage_states"):
		GameAuthority.apply_persistent_team_garage_states(world_state.get("team_garages", {}))
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("apply_persistent_destroyed_vehicle_ids"):
		GameAuthority.apply_persistent_destroyed_vehicle_ids(world_state.get("destroyed_vehicle_ids", []))
	_restore_saved_team_storage(world_state, active_world)
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("recover_persistent_pending_garage_repairs"):
		GameAuthority.recover_persistent_pending_garage_repairs(world_state.get("pending_garage_repairs", []))
	var embedded_lab_teams: Variant = world_state.get("embedded_lab_teams", null)
	if embedded_lab_teams is Dictionary and is_instance_valid(GameAuthority) \
			and GameAuthority.has_method("apply_persistent_team_embedded_lab_states"):
		GameAuthority.apply_persistent_team_embedded_lab_states(embedded_lab_teams)
	var weather_state: Variant = world_state.get("weather", {})
	if weather_state is Dictionary and not (weather_state as Dictionary).is_empty():
		for weather_system in get_tree().get_nodes_in_group("weather_systems"):
			if weather_system != null and weather_system.has_method("apply_persistent_state"):
				weather_system.call("apply_persistent_state", weather_state as Dictionary)
	if world_state.is_empty():
		if is_instance_valid(GameAuthority) and GameAuthority.has_method("rebuild_farm_statistics"):
			GameAuthority.rebuild_farm_statistics()
		return true
	for _frame in range(FARM_RESTORE_WAIT_FRAMES):
		await get_tree().process_frame
		if _farm_generation_finished(scene):
			break
	if not is_instance_valid(scene) or scene != get_tree().current_scene:
		return false
	_restore_farm_tiles(world_state.get("farm_tiles", []))
	if restore_authority_entities:
		for existing_vehicle_value in get_tree().get_nodes_in_group("vehicle_bases"):
			if existing_vehicle_value is VehicleBase \
					and GameAuthority.is_persistently_destroyed_vehicle((existing_vehicle_value as VehicleBase).get_vehicle_id()):
				(existing_vehicle_value as VehicleBase).queue_free()
		_restore_persistent_vehicles(world_state.get("vehicles", []))
		_restore_persistent_tools(world_state.get("placed_tools", []))
		_restore_persistent_livestock(world_state.get("livestock", []))
	_restore_persistent_stations(world_state.get("stations", []))
	for generator_value: Variant in scene.get_tree().get_nodes_in_group("neutral_crop_generators"):
		if is_instance_valid(generator_value) and generator_value.has_method("refresh_after_world_restore"):
			generator_value.call("refresh_after_world_restore")
	if is_instance_valid(GameAuthority) and GameAuthority.has_method("rebuild_farm_statistics"):
		GameAuthority.rebuild_farm_statistics()
	# Weather keeps processing while the map waits for farm generation and entity
	# restoration. Reapply the saved presentation state at the end so the first
	# frame of a resumed world still matches the exact save point (including a
	# partially transitioned rain/eclipsed state).
	_apply_saved_weather_state(weather_state)
	return true


func _apply_saved_weather_state(weather_state: Variant) -> void:
	if not weather_state is Dictionary or (weather_state as Dictionary).is_empty():
		return
	for weather_system in get_tree().get_nodes_in_group("weather_systems"):
		if weather_system != null and weather_system.has_method("apply_persistent_state"):
			weather_system.call("apply_persistent_state", weather_state as Dictionary)


func capture_player_state(peer_id: int, selection: Dictionary) -> Dictionary:
	var state: Dictionary = GameAuthority.player_states.get(peer_id, {})
	var runtime := selection.duplicate(true)
	runtime["peer_id"] = peer_id
	runtime["team"] = "red"
	runtime["position"] = _vector_to_array(_as_vector3(state.get(
		"position", selection.get("position", Vector3.ZERO)
	)))
	runtime["last_position"] = runtime["position"]
	runtime["current_hp"] = float(state.get("hp", selection.get("current_hp", 200.0)))
	runtime["max_hp"] = float(state.get("max_hp", selection.get("max_hp", 200.0)))
	runtime["respawn_left"] = maxf(0.0, float(state.get("respawn_left", selection.get("respawn_left", 0.0))))
	runtime["current_tool_index"] = int(state.get("current_tool_index", selection.get("current_tool_index", 0)))
	runtime["current_tool_id"] = str(state.get("current_tool_id", selection.get("current_tool_id", "")))
	for field_name: String in [
		"backpack_slot_items", "owned_equipment_ids", "equipment_hp",
		"primary_weapon_ids", "special_tool_ids", "weapon_ammo_states",
		"personal_ingredients", "personal_dishes", "personal_dish_weights",
		"personal_cargo_crates",
	]:
		var empty_value: Variant = [] if field_name in [
			"backpack_slot_items", "owned_equipment_ids", "primary_weapon_ids",
			"special_tool_ids", "personal_cargo_crates",
		] else {}
		var field_value: Variant = state.get(field_name, selection.get(field_name, empty_value))
		runtime[field_name] = field_value.duplicate(true) \
			if field_value is Array or field_value is Dictionary else field_value
	for field_name: String in ["equipped_backpack_id", "equipped_chest_armor_id", "equipped_legwear_id"]:
		runtime[field_name] = str(state.get(field_name, selection.get(field_name, "")))
	# The authority dictionary normally trails the local CharacterBody by less
	# than one tick. A manual save should nevertheless record the exact visible
	# position and HP at the moment the player presses Save.
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is GamePlayer:
			continue
		var player := node as GamePlayer
		if player.is_remote_proxy or int(player.authority_peer_id) != peer_id:
			continue
		runtime["position"] = _vector_to_array(player.global_position)
		runtime["last_position"] = runtime["position"]
		runtime["current_hp"] = player.server_hp
		break
	return runtime


func merge_player_state(selection: Dictionary, saved_state: Dictionary) -> Dictionary:
	var merged := selection.duplicate(true)
	for key: String in [
		"position", "last_position", "current_hp", "max_hp", "backpack_slot_items",
		"owned_equipment_ids", "equipment_hp", "primary_weapon_ids", "special_tool_ids",
		"weapon_ammo_states", "personal_ingredients", "personal_dishes", "personal_dish_weights",
		"personal_cargo_crates", "equipped_backpack_id", "equipped_chest_armor_id",
		"equipped_legwear_id", "respawn_left", "current_tool_index", "current_tool_id",
	]:
		if saved_state.has(key):
			var value: Variant = saved_state.get(key)
			merged[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	if merged.get("position") is Array:
		merged["position"] = _as_vector3(merged["position"])
	return merged


func apply_player_runtime_state(player: GamePlayer, selection: Dictionary, spawn_position: Vector3) -> void:
	if not is_instance_valid(player):
		return
	player.apply_loadout_selection(selection)
	var saved_equipment := {
		"backpack": {"equipment_id": str(selection.get("equipped_backpack_id", ""))},
		"chest_armor": {"equipment_id": str(selection.get("equipped_chest_armor_id", ""))},
		"legwear": {"equipment_id": str(selection.get("equipped_legwear_id", ""))},
	}
	var equipment_hp: Variant = selection.get("equipment_hp", {})
	if equipment_hp is Dictionary:
		for equipment_type: String in saved_equipment.keys():
			var equipment_id := str((saved_equipment[equipment_type] as Dictionary).get("equipment_id", ""))
			if not equipment_id.is_empty():
				(saved_equipment[equipment_type] as Dictionary)["current_hp"] = float(
					(equipment_hp as Dictionary).get(equipment_id, 0.0)
				)
	if not str((saved_equipment["backpack"] as Dictionary).get("equipment_id", "")).is_empty() \
			or not str((saved_equipment["chest_armor"] as Dictionary).get("equipment_id", "")).is_empty() \
			or not str((saved_equipment["legwear"] as Dictionary).get("equipment_id", "")).is_empty():
		player.apply_equipped_items_snapshot(saved_equipment)
	var saved_slots: Variant = selection.get("backpack_slot_items", null)
	if saved_slots is Array and not (saved_slots as Array).is_empty():
		player.apply_cargo_backpack_slots(saved_slots as Array)
	var saved_ammo_states: Variant = selection.get("weapon_ammo_states", {})
	if saved_ammo_states is Dictionary and not (saved_ammo_states as Dictionary).is_empty():
		player.apply_weapon_ammo_states_snapshot(saved_ammo_states as Dictionary)
	if selection.has("current_hp"):
		player.server_hp = clampf(float(selection.get("current_hp", 200.0)), 0.0, 200.0)
		if player.has_method("_update_health_ui"):
			player.call("_update_health_ui")
	var saved_respawn_left := maxf(0.0, float(selection.get("respawn_left", 0.0)))
	var position_value: Variant = selection.get("position", null)
	player.global_position = position_value if saved_respawn_left <= 0.0 and position_value is Vector3 \
		else spawn_position
	if saved_respawn_left > 0.0 and player.has_method("apply_respawn_state"):
		player.call("apply_respawn_state", saved_respawn_left)


func _capture_station_states() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var groups := [
		"ingredient_pickups", "chopping_stations", "ingredient_extractors", "auto_cookers", "stand_mixers",
		"oven_stations", "smoker_stations", "freezer_stations", "griddle_stations",
		"induction_counters", "plating_stations", "livestock_chops", "computer_terminals",
		"industrial_furnaces", "comprehensive_material_processing_stations",
		"electronic_assembly_stations", "wood_processing_tables",
	]
	for group_name: String in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			var state: Dictionary = {}
			for method_name: String in [
				"get_staged_state", "get_station_state", "get_extractor_state", "get_cook_state",
				"get_mixer_state", "get_chop_state", "get_computer_state", "get_workbench_state",
			]:
				if node.has_method(method_name):
					state = node.call(method_name) as Dictionary
					break
			if not state.is_empty():
				state["facility_id"] = str(node.get_meta("network_map_facility_id", ""))
				entries.append({"group": group_name, "state": state})
	return entries


func _restore_saved_team_storage(world_state: Dictionary, active_world: Dictionary) -> void:
	var restored_any := _restore_team_storage(world_state.get("team_storage", {}))
	if not restored_any:
		restored_any = _restore_team_inventory("red", world_state.get("team_inventory", {}))
	if not restored_any:
		restored_any = _restore_team_storage(active_world.get("team_storage", {}))
	if active_world.has("team_money") and (restored_any or not world_state.is_empty()):
		_restore_team_inventory("red", {"money": active_world.get("team_money", 0.0)})


func _restore_team_storage(value: Variant) -> bool:
	if not value is Dictionary:
		return false
	var restored_any := false
	for team_id_value: Variant in (value as Dictionary).keys():
		var team := str(team_id_value)
		var inventory_value: Variant = (value as Dictionary)[team_id_value]
		if GlobalVar.team_storage.has(team) and inventory_value is Dictionary:
			restored_any = _restore_team_inventory(team, inventory_value) or restored_any
	return restored_any


func _restore_team_inventory(team: String, value: Variant) -> bool:
	if not GlobalVar.team_storage.has(team) or not value is Dictionary or (value as Dictionary).is_empty():
		return false
	var inventory: Dictionary = (GlobalVar.team_storage.get(team, {}) as Dictionary).duplicate(true)
	var restored_any := false
	for item_id_value: Variant in (value as Dictionary).keys():
		var amount_value: Variant = (value as Dictionary)[item_id_value]
		if not amount_value is float and not amount_value is int:
			continue
		var item_id := str(item_id_value)
		var previous_amount := float(inventory.get(item_id, 0.0))
		var restored_amount := float(amount_value)
		inventory[item_id] = restored_amount
		GlobalVar.storage_changed.emit(team, item_id, restored_amount)
		if item_id == "money" and not is_zero_approx(restored_amount - previous_amount):
			GlobalVar.team_money_changed.emit(team, restored_amount - previous_amount, restored_amount)
		restored_any = true
	GlobalVar.team_storage[team] = inventory
	if restored_any:
		GlobalVar.mark_team_storage_changed(team)
	return restored_any


func _farm_generation_finished(scene: Node3D) -> bool:
	var generators := scene.find_children("*", "FarmFieldGenerator", true, false)
	if generators.is_empty():
		return true
	for generator in generators:
		if generator is FarmFieldGenerator and (generator as FarmFieldGenerator).is_generating:
			return false
	return not get_tree().get_nodes_in_group("farm_tiles").is_empty()


func _restore_farm_tiles(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if state_value is Dictionary:
			var state := _decode_state_vectors(state_value as Dictionary)
			var tile := _find_farm_tile_for_restore(state)
			if tile != null:
				tile.apply_authoritative_state(state)


func _restore_persistent_vehicles(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var vehicle_id := str(state.get("vehicle_id", ""))
		if GameAuthority.is_persistently_destroyed_vehicle(vehicle_id):
			continue
		var garage_vehicle_id := str(state.get("garage_vehicle_id", ""))
		var garage_record := GameAuthority.get_team_garage_record(garage_vehicle_id) \
			if not garage_vehicle_id.is_empty() else {}
		if not garage_record.is_empty() and str(garage_record.get("status", "active")) == "destroyed":
			continue
		if not garage_record.is_empty():
			state["owner_team"] = str(garage_record.get("owner_team", state.get("owner_team", "red")))
			state["body_color_id"] = str(garage_record.get("body_color_id", "black"))
			state["wheel_color_id"] = str(garage_record.get("wheel_color_id", "black"))
			state["body_color"] = VehicleColorCatalogScript.get_color(str(state["body_color_id"]))
			state["wheel_color"] = VehicleColorCatalogScript.get_color(str(state["wheel_color_id"]))
			var installed_modules_value: Variant = garage_record.get("installed_modules", {})
			if installed_modules_value is Dictionary:
				var installed_modules := installed_modules_value as Dictionary
				state["harvest_reel_installed"] = int(installed_modules.get("vehicle_harvest_reel", 0)) > 0
				state["platform_passenger_seat_count"] = clampi(int(installed_modules.get("vehicle_extended_seat", 0)), 0, 2)
				state["roof_headlights_installed"] = int(installed_modules.get("vehicle_roof_headlights", 0)) > 0
				state["platform_machine_gun_installed"] = int(installed_modules.get("vehicle_machine_gun", 0)) > 0
				state["platform_signal_station_installed"] = int(installed_modules.get("vehicle_signal_augment", 0)) > 0
				state["nitro_boost_installed"] = int(installed_modules.get("vehicle_nitro_boost", 0)) > 0
				state["reinforced_variant"] = int(installed_modules.get("vehicle_metal_defense_net", 0)) > 0
				state["high_performance_motor_installed"] = int(installed_modules.get("high_performance_motor", 0)) > 0
				state["composite_armor_panel_installed"] = int(installed_modules.get("composite_armor_panel", 0)) > 0
		var vehicle := _find_vehicle_for_restore(vehicle_id)
		if vehicle == null:
			var scene_path := str(state.get("scene_path", ""))
			var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
			vehicle = packed.instantiate() as VehicleBase if packed != null else null
			if vehicle == null:
				continue
			vehicle.name = "Persistent_" + vehicle_id.replace(":", "_")
			vehicle.network_id = vehicle_id
			vehicle.owner_team = str(state.get("owner_team", "red"))
			GlobalVar.gameworld.add_child(vehicle)
			if vehicle.has_method("set_kitchen_team"):
				vehicle.call("set_kitchen_team", vehicle.owner_team)
		if not garage_vehicle_id.is_empty():
			vehicle.set_meta("garage_vehicle_id", garage_vehicle_id)
		state["driver_peer_id"] = 0
		state["seat_occupants"] = []
		var machine_gun_value: Variant = state.get("platform_machine_gun", {})
		if machine_gun_value is Dictionary:
			var machine_gun_state := (machine_gun_value as Dictionary).duplicate(true)
			machine_gun_state["operator_peer_id"] = 0
			state["platform_machine_gun"] = machine_gun_state
		vehicle.apply_network_state(state)
		var manifest: Variant = state.get("cargo_manifest", [])
		if manifest is Array:
			vehicle.set_cargo_manifest(manifest as Array)
		GameAuthority.vehicle_states[vehicle_id] = state.duplicate(true)
		if not garage_vehicle_id.is_empty() and GameAuthority.has_method("bind_restored_garage_vehicle"):
			GameAuthority.bind_restored_garage_vehicle(garage_vehicle_id, vehicle_id)


func _restore_persistent_tools(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var tool_id := str(state.get("tool_id", state.get("device_id", "")))
		if tool_id.is_empty():
			continue
		var existing_tool := _find_persistent_tool(tool_id)
		if existing_tool != null:
			_apply_persistent_state_to_existing_tool(existing_tool, tool_id, state)
			continue
		var scene_path := str(state.get("scene_path", ""))
		if str(state.get("tool_name", "")) == "cargo_crate":
			var crate_value: Variant = state.get("crate_data", {})
			if crate_value is Dictionary:
				scene_path = str((crate_value as Dictionary).get("model_path", scene_path))
		var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
		var node := packed.instantiate() as Node3D if packed != null else null
		if node == null:
			continue
		node.name = "Persistent_" + tool_id.get_file().replace(":", "_")
		GlobalVar.gameworld.add_child(node)
		node.global_position = _as_vector3(state.get("position", Vector3.ZERO))
		node.rotation.y = float(state.get("yaw", 0.0))
		node.set_meta("network_device_id", tool_id)
		if node is CargoCrateGround:
			var crate_data: Variant = state.get("crate_data", {})
			if crate_data is Dictionary:
				(node as CargoCrateGround).setup_crate(crate_data as Dictionary)
			GameAuthority.register_map_cargo_crate(node as CargoCrateGround)
		else:
			if GameAuthority.has_method("_node_has_property") \
					and bool(GameAuthority.call("_node_has_property", node, "tool_owner")):
				node.set("tool_owner", str(state.get("team", "red")))
			if node is KitchenAppliance:
				(node as KitchenAppliance).owner_team = str(state.get("team", "red"))
			if node.has_method("activate_tool"):
				node.call("activate_tool")
			if node is WireMeshGate:
				(node as WireMeshGate).apply_network_state(state)
			GameAuthority.register_map_placed_tool(node, str(state.get("tool_name", "")), tool_id, str(state.get("team", "red")))
		if node.has_method("apply_network_health"):
			node.call("apply_network_health", float(state.get("hp", 0.0)))
		state["path"] = str(node.get_path())
		GameAuthority.placed_tool_states[tool_id] = state
		_apply_saved_visual_state(node, state)


func _apply_persistent_state_to_existing_tool(node: Node3D, tool_id: String, state: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	var runtime_state: Dictionary = GameAuthority.placed_tool_states.get(tool_id, {})
	if runtime_state.is_empty():
		runtime_state = state.duplicate(true)
	else:
		runtime_state.merge(state, true)
	runtime_state["tool_id"] = tool_id
	if str(runtime_state.get("device_id", "")).is_empty():
		runtime_state["device_id"] = tool_id
	runtime_state["path"] = str(node.get_path())
	if str(runtime_state.get("scene_path", "")).is_empty():
		runtime_state["scene_path"] = node.scene_file_path
	GameAuthority.placed_tool_states[tool_id] = runtime_state
	_apply_saved_visual_state(node, state)


func _apply_saved_visual_state(node: Node, state: Dictionary) -> void:
	if node == null or not is_instance_valid(node):
		return
	if PlacedStorageState.apply_record(node, state):
		return
	if not node.has_method("apply_network_visual_state"):
		return
	var visual_state: Variant = state.get("visual_state", {})
	if not visual_state is Dictionary or (visual_state as Dictionary).is_empty():
		visual_state = {"rack_slots": state.get("rack_slots", [])} if state.has("rack_slots") else {}
	if visual_state is Dictionary and not (visual_state as Dictionary).is_empty():
		node.call("apply_network_visual_state", visual_state)


func _restore_persistent_livestock(value: Variant) -> void:
	if not value is Array:
		return
	for state_value: Variant in value:
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		var animal_id := str(state.get("animal_id", ""))
		if animal_id.is_empty() or _find_livestock_for_restore(animal_id) != null:
			continue
		var scene_path := str(state.get("scene_path", ""))
		var packed := load(scene_path) as PackedScene if not scene_path.is_empty() else null
		var animal := packed.instantiate() as FarmLivestock if packed != null else null
		if animal == null:
			continue
		animal.name = "Persistent_" + animal_id.replace(":", "_")
		animal.animal_id = animal_id
		animal.owner_team = str(state.get("owner_team", "red"))
		animal.initial_hp = float(state.get("current_hp", -1.0))
		animal.initial_growth_progress = float(state.get("growth_progress", 0.0))
		animal.naturally_spawned = false
		GlobalVar.gameworld.add_child(animal)
		animal.global_position = _as_vector3(state.get("position", Vector3.ZERO))
		animal.rotation.y = float(state.get("yaw", 0.0))
		animal.home_position = _as_vector3(state.get("home_position", animal.global_position))


func _restore_persistent_stations(value: Variant) -> void:
	if not value is Array:
		return
	for entry_value: Variant in value:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var state_value: Variant = entry.get("state", {})
		if not state_value is Dictionary:
			continue
		var state := _decode_state_vectors(state_value as Dictionary)
		state["active_user_peer_id"] = 0
		var station := _find_station_for_restore(str(entry.get("group", "")), state)
		if station == null:
			continue
		for method_name: String in [
			"apply_authoritative_staged_state", "apply_authoritative_station_state",
			"apply_authoritative_extractor_state", "apply_authoritative_cook_state",
			"apply_authoritative_mixer_state", "apply_authoritative_workbench_state",
			"apply_authoritative_chop_state", "apply_computer_state",
		]:
			if station.has_method(method_name):
				if method_name == "apply_computer_state" and GameAuthority.has_method(
						"import_legacy_embedded_lab_state_from_computer_state"):
					GameAuthority.import_legacy_embedded_lab_state_from_computer_state(state)
				station.call(method_name, state)
				break


func _find_farm_tile_for_restore(state: Dictionary) -> FarmTile:
	var direct := get_node_or_null(NodePath(str(state.get("tile_path", ""))))
	if direct is FarmTile:
		return direct as FarmTile
	var position := _as_vector3(state.get("tile_position", Vector3.ZERO))
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if node is FarmTile and (node as FarmTile).global_position.distance_to(position) < 0.05:
			return node as FarmTile
	return null


func _find_vehicle_for_restore(vehicle_id: String) -> VehicleBase:
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).get_vehicle_id() == vehicle_id:
			return node as VehicleBase
	return null


func _find_persistent_tool(tool_id: String) -> Node3D:
	if tool_id.is_empty():
		return null
	var direct := get_tree().root.get_node_or_null(NodePath(tool_id))
	if direct is Node3D and is_instance_valid(direct):
		return direct as Node3D
	for group_name in [
		"network_map_devices", "network_map_facilities", "weapon_display_racks",
		PlacedStorageState.STORAGE_GROUP,
	]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D and is_instance_valid(node) \
					and str(node.get_meta("network_device_id", "")) == tool_id:
				return node as Node3D
	return null


func _find_livestock_for_restore(animal_id: String) -> FarmLivestock:
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if node is FarmLivestock and (node as FarmLivestock).animal_id == animal_id:
			return node as FarmLivestock
	return null


func _find_station_for_restore(group_name: String, state: Dictionary) -> Node:
	var facility_id := str(state.get("facility_id", ""))
	if not facility_id.is_empty():
		for facility_value: Variant in get_tree().get_nodes_in_group("network_map_facilities"):
			if facility_value is Node \
					and str((facility_value as Node).get_meta("network_map_facility_id", "")) == facility_id:
				return facility_value as Node
	var direct := get_node_or_null(NodePath(str(state.get("station_path", ""))))
	if direct != null:
		return direct
	var position := _as_vector3(state.get("station_position", Vector3.ZERO))
	for node in get_tree().get_nodes_in_group(group_name):
		if node is Node3D and (node as Node3D).global_position.distance_to(position) < 0.5:
			return node
	return null


func _decode_state_vectors(source: Dictionary) -> Dictionary:
	var state := source.duplicate(true)
	for key in ["position", "tile_position", "station_position", "home_position", "spawn_drop_landing_position", "tip_axis"]:
		if state.has(key):
			state[key] = _as_vector3(state[key])
	for key in ["body_color", "wheel_color"]:
		if state.has(key) and state[key] is Array:
			var values := state[key] as Array
			if values.size() >= 3:
				state[key] = Color(float(values[0]), float(values[1]), float(values[2]), float(values[3]) if values.size() >= 4 else 1.0)
	var crop_positions: Variant = state.get("crop_positions", [])
	if crop_positions is Array:
		var restored_positions: Array = []
		for position_value in crop_positions:
			restored_positions.append(_as_vector3(position_value))
		state["crop_positions"] = restored_positions
	return state


func _as_vector3(value: Variant) -> Vector3:
	if value is Vector3:
		return value as Vector3
	if value is Array and (value as Array).size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO


func _vector_to_array(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]
