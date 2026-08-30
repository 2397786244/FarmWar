extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const TERMINAL_SCENE := preload("res://facilities/interior/vehicle_service/repair_terminal.tscn")
const NORMAL_DRONE_SCENE := preload("res://character/weapons/NormalDrone.tscn")
const EDITOR_SCRIPT := preload("res://src/farmwar_runtime_map_editor.gd")

const MODULE_IDS := [
	"vehicle_harvest_reel",
	"vehicle_extended_seat",
	"vehicle_roof_headlights",
	"vehicle_machine_gun",
	"vehicle_nitro_boost",
	"vehicle_signal_augment",
	"vehicle_metal_defense_net",
]

var failures := 0
var request_serial := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "FarmBaseVehicleModulesValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self
	GlobalVar.add_item("red", "money", 100000.0)

	var ground := _add_box_body(
		"FarmBaseVehicleModulesValidationGround",
		Vector3(0.0, -0.5, 0.0),
		Vector3(80.0, 1.0, 80.0),
		1
	)
	_check(ground != null, "validation ground is available")

	var terminal := TERMINAL_SCENE.instantiate() as VehicleServiceTerminal
	_check(terminal != null, "repair terminal scene instantiates")
	if terminal == null:
		_finish()
		return
	terminal.name = "FarmBaseVehicleModulesValidationTerminal"
	add_child(terminal)

	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene instantiates")
	if vehicle == null:
		_finish()
		return
	vehicle.name = "FarmBaseVehicleModulesValidationVehicle"
	vehicle.network_id = "farm_base_vehicle_modules_validation"
	vehicle.owner_team = "red"
	vehicle.position = Vector3(0.0, 0.55, 2.0)
	add_child(vehicle)
	await get_tree().process_frame
	await get_tree().process_frame

	terminal.call("_on_vehicle_body_entered", vehicle)
	var context := {
		"shop_category": "vehicle_service",
		"terminal_id": terminal.get_terminal_id(),
		"terminal_path": str(terminal.get_path()),
		"vehicle_id": vehicle.get_vehicle_id(),
	}
	var acquire_result := _service_request(terminal, vehicle, "acquire")
	_check(bool(acquire_result.get("ok", false)), "repair terminal grants the module service lock")

	# The module endpoint is intentionally unusable without a matching terminal.
	_grant_module_item("vehicle_roof_headlights")
	var no_terminal_money := GlobalVar.check_team_item_amount("red", "money")
	var no_terminal_item_count := _module_item_count("vehicle_roof_headlights")
	var no_terminal_request := {
		"shop_category": "vehicle_service",
		"action": "install_module",
		"module_id": "vehicle_roof_headlights",
		"terminal_id": "missing-repair-terminal",
		"vehicle_id": vehicle.get_vehicle_id(),
		"request_id": _next_request_id("outside-terminal"),
	}
	var no_terminal_result: Dictionary = GameAuthority.local_shop_transaction(1, no_terminal_request)
	_check(not bool(no_terminal_result.get("ok", false)), "runtime module install is rejected outside repair_terminal")
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), no_terminal_money)
			and _module_item_count("vehicle_roof_headlights") == no_terminal_item_count
			and not vehicle.roof_headlights_installed,
		"outside-terminal rejection leaves money, inventory, and vehicle unchanged"
	)
	_clear_personal_inventory()

	# Every single-count module has a complete service install/uninstall cycle.
	await _install_then_uninstall(terminal, vehicle, "vehicle_harvest_reel")
	await _install_then_uninstall(terminal, vehicle, "vehicle_roof_headlights")
	await _install_then_uninstall(terminal, vehicle, "vehicle_nitro_boost")

	# Metal-net armor is a single vehicle module backed by five material units.
	# It must coexist with ordinary attachments and leave them untouched.
	_clear_personal_inventory()
	_grant_module_item("vehicle_harvest_reel")
	var coexist_harvest := _service_request(terminal, vehicle, "install_module", "vehicle_harvest_reel")
	_grant_module_item("vehicle_roof_headlights")
	var coexist_headlights := _service_request(terminal, vehicle, "install_module", "vehicle_roof_headlights")
	var base_max_hp := vehicle.get_max_hp()
	_grant_module_item("metal_defense_net", 4)
	var armor_quote_short := _quote_module(
		GameAuthority.get_vehicle_service_quote(vehicle, 1), "vehicle_metal_defense_net"
	)
	_check(
		bool(coexist_harvest.get("ok", false))
			and bool(coexist_headlights.get("ok", false))
			and int(armor_quote_short.get("required_item_amount", 0)) == 5
			and str(armor_quote_short.get("item_id", "")) == "metal_defense_net"
			and int(armor_quote_short.get("inventory_count", 0)) == 4
			and not bool(armor_quote_short.get("can_install", true)),
		"metal-net armor advertises a five-item requirement and blocks four-item installation"
	)
	var armor_missing := _service_request(terminal, vehicle, "install_module", "vehicle_metal_defense_net")
	_check(
		str(armor_missing.get("reason", "")) == "module_item_missing"
			and not vehicle.reinforced_variant
			and _module_item_count("metal_defense_net") == 4
			and vehicle.harvest_reel_installed
			and vehicle.roof_headlights_installed,
		"insufficient metal nets leave armor and existing attachments unchanged"
	)
	_grant_module_item("metal_defense_net")
	var armor_install_money := GlobalVar.check_team_item_amount("red", "money")
	var armor_install := _service_request(terminal, vehicle, "install_module", "vehicle_metal_defense_net")
	_check(
		bool(armor_install.get("ok", false))
			and vehicle.reinforced_variant
			and _module_count(vehicle, "vehicle_metal_defense_net") == 1
			and _module_item_count("metal_defense_net") == 0
			and is_equal_approx(vehicle.get_max_hp(), base_max_hp * 1.5)
			and vehicle.harvest_reel_installed
			and vehicle.roof_headlights_installed
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), armor_install_money - 500.0),
		"five metal nets install the reinforced body without removing other modules"
	)
	var armor_uninstall := _service_request(terminal, vehicle, "uninstall_module", "vehicle_metal_defense_net")
	_check(
		bool(armor_uninstall.get("ok", false))
			and not vehicle.reinforced_variant
			and _module_count(vehicle, "vehicle_metal_defense_net") == 0
			and _module_item_count("metal_defense_net") == 5
			and is_equal_approx(vehicle.get_max_hp(), base_max_hp)
			and vehicle.harvest_reel_installed
			and vehicle.roof_headlights_installed,
		"removing metal-net armor returns all five nets and preserves other modules"
	)
	_clear_personal_inventory()
	_check(
		bool(_service_request(terminal, vehicle, "uninstall_module", "vehicle_harvest_reel").get("ok", false))
			and bool(_service_request(terminal, vehicle, "uninstall_module", "vehicle_roof_headlights").get("ok", false))
			and not vehicle.harvest_reel_installed
			and not vehicle.roof_headlights_installed,
		"armor coexistence setup can be cleaned up through the same terminal"
	)

	# Seats are counted individually and cannot be removed while a platform seat is occupied.
	_grant_module_item("vehicle_extended_seat", 2)
	var seat_money_before := GlobalVar.check_team_item_amount("red", "money")
	var seat_install_one := _service_request(terminal, vehicle, "install_module", "vehicle_extended_seat")
	var seat_quote_after_one := _quote_module(GameAuthority.get_vehicle_service_quote(vehicle, 1), "vehicle_extended_seat")
	_check(
		bool(seat_quote_after_one.get("can_install", false))
			and bool(seat_quote_after_one.get("can_uninstall", false))
			and int(seat_quote_after_one.get("installed_count", 0)) == 1,
		"service state keeps both install and one-at-a-time uninstall available for seats"
	)
	var seat_install_two := _service_request(terminal, vehicle, "install_module", "vehicle_extended_seat")
	_check(
		bool(seat_install_one.get("ok", false))
			and bool(seat_install_two.get("ok", false))
			and vehicle.platform_passenger_seat_count == 2
			and _module_item_count("vehicle_extended_seat") == 0,
		"extended seats install one item at a time up to two seats"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), seat_money_before - 1000.0),
		"each extended seat installation charges 500"
	)
	vehicle.seat_occupants[1] = 1
	var occupied_uninstall := _service_request(terminal, vehicle, "uninstall_module", "vehicle_extended_seat")
	_check(
		str(occupied_uninstall.get("reason", "")) == "module_passenger_occupied"
			and vehicle.platform_passenger_seat_count == 2
			and _module_item_count("vehicle_extended_seat") == 0
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), seat_money_before - 1000.0),
		"occupied platform seats block uninstall without changing state"
	)
	vehicle.seat_occupants.erase(1)
	var seat_uninstall_one := _service_request(terminal, vehicle, "uninstall_module", "vehicle_extended_seat")
	var seat_uninstall_two := _service_request(terminal, vehicle, "uninstall_module", "vehicle_extended_seat")
	_check(
		bool(seat_uninstall_one.get("ok", false))
			and bool(seat_uninstall_two.get("ok", false))
			and vehicle.platform_passenger_seat_count == 0
			and _module_item_count("vehicle_extended_seat") == 2,
		"extended seats uninstall one at a time and return both items"
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), seat_money_before - 1000.0),
		"seat uninstall does not charge a fee"
	)
	_clear_personal_inventory()

	# The machine gun and station have separate complete cycles. The station's
	# coverage remains an Area3D-only mechanic with no visible range sphere.
	await _install_then_uninstall(terminal, vehicle, "vehicle_machine_gun")
	_grant_module_item("vehicle_signal_augment")
	var station_install_money := GlobalVar.check_team_item_amount("red", "money")
	var station_install := _service_request(terminal, vehicle, "install_module", "vehicle_signal_augment")
	var station := vehicle.get_platform_signal_station()
	_check(
		bool(station_install.get("ok", false))
			and vehicle.platform_signal_station_installed
			and station != null
			and vehicle.get_platform_machine_gun() == null,
		"signal station installs as the machine-gun-exclusive module"
	)
	if station != null:
		await get_tree().process_frame
		var hit_area := station.get_node_or_null("Hit3D") as Area3D
		var augment_area := station.get_node_or_null("Aug3D") as Area3D
		_check(
			is_equal_approx(station.augment_dist, 50.0)
				and is_equal_approx(station.set_hp, VehicleBaseMachineGun.MAX_HP)
				and is_equal_approx(station.current_hp, VehicleBaseMachineGun.MAX_HP),
			"signal station uses a 50 metre radius and machine-gun HP"
		)
		_check(
			station.collision_layer == 0 and station.collision_mask == 0
				and hit_area != null and hit_area.collision_layer == GameAuthority.COLLISION_LAYER_TOOL
				and hit_area.collision_mask == GameAuthority.COLLISION_LAYER_BULLET
				and augment_area != null and augment_area.collision_layer == 0
				and augment_area.collision_mask == GameAuthority.COLLISION_LAYER_TOOL,
			"signal station collision layer and mask match a mounted combat attachment"
		)
		_check(
				station.get_node_or_null("SignalRangeVisual") == null
				and not station.get_network_state().has("range_visual"),
			"signal station has no visible range sphere and no range visual network state"
		)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), station_install_money - 500.0),
		"signal station installation charges 500"
	)
	var station_quote := GameAuthority.get_vehicle_service_quote(vehicle, 1)
	var station_module_quote := _quote_module(station_quote, "vehicle_signal_augment")
	_check(
		int(station_module_quote.get("installed_count", 0)) == 1
			and bool(station_module_quote.get("can_uninstall", false)),
		"service state exposes signal station count and uninstall permission"
	)
	await _validate_station_remote_coverage(station, vehicle)
	var station_uninstall_money := GlobalVar.check_team_item_amount("red", "money")
	var station_uninstall := _service_request(terminal, vehicle, "uninstall_module", "vehicle_signal_augment")
	_check(
		bool(station_uninstall.get("ok", false))
			and not vehicle.platform_signal_station_installed
			and vehicle.get_platform_signal_station() == null
			and _module_item_count("vehicle_signal_augment") == 1
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), station_uninstall_money),
		"signal station uninstall returns its item without a fee"
	)
	_clear_personal_inventory()

	# Machine-gun operation blocks both removal and the exclusive switch.
	_grant_module_item("vehicle_machine_gun")
	var gun_install := _service_request(terminal, vehicle, "install_module", "vehicle_machine_gun")
	var gun := vehicle.get_platform_machine_gun()
	_check(bool(gun_install.get("ok", false)) and gun != null, "machine gun installs through the terminal")
	if gun != null:
		gun.operator_peer_id = 7
	var blocked_switch_quote := _quote_module(
		GameAuthority.get_vehicle_service_quote(vehicle, 1), "vehicle_signal_augment"
	)
	_check(
		not bool(blocked_switch_quote.get("can_install", true))
			and not bool(blocked_switch_quote.get("can_switch", true)),
		"service state separates blocked mutual switching from direct installation"
	)
	var gun_money_before_block := GlobalVar.check_team_item_amount("red", "money")
	var gun_item_before_block := _module_item_count("vehicle_machine_gun")
	var blocked_gun_uninstall := _service_request(terminal, vehicle, "uninstall_module", "vehicle_machine_gun")
	_check(
		str(blocked_gun_uninstall.get("reason", "")) == "module_machine_gun_in_use"
			and vehicle.platform_machine_gun_installed
			and _module_item_count("vehicle_machine_gun") == gun_item_before_block
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), gun_money_before_block),
		"operated machine gun cannot be uninstalled"
	)
	_grant_module_item("vehicle_signal_augment")
	var blocked_switch := _service_request(terminal, vehicle, "install_module", "vehicle_signal_augment")
	_check(
		str(blocked_switch.get("reason", "")) == "module_machine_gun_in_use"
			and vehicle.platform_machine_gun_installed
			and not vehicle.platform_signal_station_installed,
		"operated machine gun cannot be switched to a signal station"
	)
	if gun != null:
		gun.operator_peer_id = 0

	# The exclusive switch is atomic in both directions and request retries are idempotent.
	var swap_money_before := GlobalVar.check_team_item_amount("red", "money")
	var swap_to_station := _service_request(terminal, vehicle, "install_module", "vehicle_signal_augment")
	_check(
		bool(swap_to_station.get("ok", false))
			and bool(swap_to_station.get("switched", false))
			and vehicle.platform_signal_station_installed
			and not vehicle.platform_machine_gun_installed
			and _module_item_count("vehicle_signal_augment") == 0
			and _module_item_count("vehicle_machine_gun") == 1
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), swap_money_before - 500.0),
		"machine gun to signal station switch consumes target, returns old module, and charges once"
	)
	var swap_back_money_before := GlobalVar.check_team_item_amount("red", "money")
	var swap_back_to_gun := _service_request(terminal, vehicle, "install_module", "vehicle_machine_gun")
	_check(
		bool(swap_back_to_gun.get("ok", false))
			and bool(swap_back_to_gun.get("switched", false))
			and vehicle.platform_machine_gun_installed
			and not vehicle.platform_signal_station_installed
			and _module_item_count("vehicle_machine_gun") == 0
			and _module_item_count("vehicle_signal_augment") == 1
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), swap_back_money_before - 500.0),
		"signal station to machine gun switch is also atomic"
	)
	var swap_back_retry := swap_back_to_gun.duplicate(true)
	var retry_result: Dictionary = GameAuthority.local_shop_transaction(1, swap_back_retry)
	_check(
		bool(retry_result.get("ok", false))
			and str(retry_result.get("request_id", "")) == str(swap_back_to_gun.get("request_id", ""))
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), swap_back_money_before - 500.0),
		"repeating a completed switch request is idempotent"
	)

	# A full backpack rejects the swap before any mutation, preserving every side effect.
	var gun_for_rollback := _service_request(terminal, vehicle, "uninstall_module", "vehicle_machine_gun")
	_check(bool(gun_for_rollback.get("ok", false)) and not vehicle.platform_machine_gun_installed, "machine gun can be removed after operation ends")
	_clear_personal_inventory()
	_grant_module_item("vehicle_machine_gun")
	var reinstall_gun := _service_request(terminal, vehicle, "install_module", "vehicle_machine_gun")
	_check(bool(reinstall_gun.get("ok", false)) and vehicle.platform_machine_gun_installed, "machine gun reinstalls for rollback validation")
	_grant_module_item("vehicle_signal_augment", 2)
	_grant_filler_items(11)
	var rollback_money := GlobalVar.check_team_item_amount("red", "money")
	var rollback_signal_count := _module_item_count("vehicle_signal_augment")
	var rollback_request := _service_request(terminal, vehicle, "install_module", "vehicle_signal_augment")
	_check(
		str(rollback_request.get("reason", "")) == "module_bag_full"
			and vehicle.platform_machine_gun_installed
			and not vehicle.platform_signal_station_installed
			and _module_item_count("vehicle_signal_augment") == rollback_signal_count
			and is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), rollback_money),
		"failed exclusive switch rolls back vehicle, inventory, and money atomically"
	)
	_clear_personal_inventory()
	var final_gun_uninstall := _service_request(terminal, vehicle, "uninstall_module", "vehicle_machine_gun")
	_check(bool(final_gun_uninstall.get("ok", false)) and not vehicle.platform_machine_gun_installed, "machine gun final uninstall returns control to the terminal")

	await _validate_editor_persistence(vehicle)

	# Keep the local service context valid while the test finishes, then stop the authority.
	_check(MODULE_IDS.size() == 7, "the service definition covers all seven FarmBaseVehicle modules")
	_finish()


func _install_then_uninstall(terminal: VehicleServiceTerminal, vehicle: FarmBaseVehicle, module_id: String) -> void:
	_grant_module_item(module_id)
	var money_before := GlobalVar.check_team_item_amount("red", "money")
	var install_result := _service_request(terminal, vehicle, "install_module", module_id)
	_check(
		bool(install_result.get("ok", false))
			and _module_count(vehicle, module_id) == 1
			and _module_item_count(module_id) == 0,
		"%s installs through repair_terminal" % module_id
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 500.0),
		"%s installation charges 500" % module_id
	)
	var uninstall_money := GlobalVar.check_team_item_amount("red", "money")
	var uninstall_result := _service_request(terminal, vehicle, "uninstall_module", module_id)
	_check(
		bool(uninstall_result.get("ok", false))
			and _module_count(vehicle, module_id) == 0
			and _module_item_count(module_id) == 1,
		"%s uninstalls and returns one item" % module_id
	)
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), uninstall_money),
		"%s uninstall is free" % module_id
	)


func _validate_editor_persistence(vehicle: FarmBaseVehicle) -> void:
	var editor := Node3D.new()
	editor.set_script(EDITOR_SCRIPT)
	vehicle.set_meta("map_editor_category", "vehicle")
	vehicle.set_meta("map_editor_asset_path", "res://vehicles/farm_base_vehicle.tscn")
	# A map may configure every module except the mutually exclusive pair at once.
	editor.call("_set_property_if_present", vehicle, "platform_machine_gun_installed", false)
	editor.call("_set_property_if_present", vehicle, "platform_signal_station_installed", true)
	editor.call("_set_property_if_present", vehicle, "platform_passenger_seat_count", 2)
	editor.call("_set_property_if_present", vehicle, "harvest_reel_installed", true)
	editor.call("_set_property_if_present", vehicle, "roof_headlights_installed", true)
	editor.call("_set_property_if_present", vehicle, "nitro_boost_installed", true)
	editor.call("_set_property_if_present", vehicle, "reinforced_variant", true)
	var saved_record: Dictionary = editor.call("_serialize_editor_object", vehicle)
	var saved_properties: Dictionary = saved_record.get("properties", {}) as Dictionary
	_check(
		str(saved_record.get("asset_path", "")) == "res://vehicles/farm_base_vehicle.tscn"
			and bool(saved_properties.get("platform_signal_station_installed", false))
			and int(saved_properties.get("platform_passenger_seat_count", 0)) == 2
			and bool(saved_properties.get("harvest_reel_installed", false))
				and bool(saved_properties.get("roof_headlights_installed", false))
				and bool(saved_properties.get("nitro_boost_installed", false))
				and bool(saved_properties.get("reinforced_variant", false))
				and not bool(saved_properties.get("platform_machine_gun_installed", false)),
		"map editor serialization preserves all FarmBaseVehicle module states"
	)

	var loaded_vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(loaded_vehicle != null, "map editor load target instantiates")
	if loaded_vehicle == null:
		return
	loaded_vehicle.name = "FarmBaseVehicleModulesValidationLoadedVehicle"
	loaded_vehicle.network_id = "farm_base_vehicle_modules_validation_loaded"
	loaded_vehicle.owner_team = "red"
	add_child(loaded_vehicle)
	await get_tree().process_frame
	for property_name in [
		"platform_machine_gun_installed",
		"platform_signal_station_installed",
		"platform_passenger_seat_count",
		"harvest_reel_installed",
		"roof_headlights_installed",
		"nitro_boost_installed",
		"reinforced_variant",
	]:
		if saved_properties.has(property_name):
			editor.call("_set_property_if_present", loaded_vehicle, property_name, saved_properties[property_name])
	_check(
		loaded_vehicle.platform_signal_station_installed
			and not loaded_vehicle.platform_machine_gun_installed
			and loaded_vehicle.platform_passenger_seat_count == 2
				and loaded_vehicle.harvest_reel_installed
				and loaded_vehicle.roof_headlights_installed
				and loaded_vehicle.nitro_boost_installed
				and loaded_vehicle.reinforced_variant
				and is_equal_approx(loaded_vehicle.get_max_hp(), loaded_vehicle._base_vehicle_config.max_hp * 1.5),
		"map editor load restores module states through FarmBaseVehicle setters"
	)
	editor.call("_set_property_if_present", loaded_vehicle, "platform_machine_gun_installed", true)
	_check(
		loaded_vehicle.platform_machine_gun_installed
			and not loaded_vehicle.platform_signal_station_installed,
		"map editor module setters enforce machine-gun and signal-station exclusivity"
	)
	editor.call("_set_property_if_present", loaded_vehicle, "platform_signal_station_installed", true)
	_check(
		loaded_vehicle.platform_signal_station_installed
			and not loaded_vehicle.platform_machine_gun_installed,
		"map editor can switch the mutually exclusive attachment"
	)
	loaded_vehicle.queue_free()


func _service_request(
	terminal: VehicleServiceTerminal,
	vehicle: FarmBaseVehicle,
	action: String,
	module_id := ""
) -> Dictionary:
	var transaction := {
		"shop_category": "vehicle_service",
		"action": action,
		"terminal_id": terminal.get_terminal_id(),
		"terminal_path": str(terminal.get_path()),
		"vehicle_id": vehicle.get_vehicle_id(),
		"request_id": _next_request_id(action),
	}
	if not module_id.is_empty():
		transaction["module_id"] = module_id
	return GameAuthority.local_shop_transaction(1, transaction)


func _next_request_id(prefix: String) -> String:
	request_serial += 1
	return "farm-base-vehicle-modules-%s-%d" % [prefix, request_serial]


func _grant_module_item(module_id: String, amount: int = 1) -> void:
	var state: Dictionary = GameAuthority.player_states.get(1, {})
	var item_id := _module_item_id(module_id)
	for _index in range(amount):
		GameAuthority.call("_server_add_personal_ingredient", state, item_id, 1.0, false)
	GameAuthority.player_states[1] = state


func _validate_station_remote_coverage(
	station: VehicleBaseSignalStation,
	vehicle: FarmBaseVehicle
) -> void:
	if station == null:
		return
	var drone := NORMAL_DRONE_SCENE.instantiate() as NormalDrone
	_check(drone != null, "remote device scene instantiates for signal coverage")
	if drone == null:
		return
	drone.name = "FarmBaseVehicleModulesValidationRemoteDrone"
	drone.tool_owner = "red"
	add_child(drone)
	drone.global_position = station.global_position
	drone.activate_tool()
	var device_id := str(drone.get_path())
	drone.set_meta("network_device_id", device_id)
	GameAuthority.remote_device_states[device_id] = {
		"device_id": device_id,
		"device_path": device_id,
		"path": device_id,
		"device_type": "normal_drone",
		"owner_peer_id": 1,
		"team": "red",
		"position": drone.global_position,
		"signal_range": 100.0,
		"controller_peer_id": 0,
	}
	await get_tree().physics_frame
	await get_tree().physics_frame
	station.call("_refresh_augmented_devices")
	GameAuthority.call("_update_remote_device_link_quality")
	var centered_state: Dictionary = GameAuthority.remote_device_states[device_id]
	_check(
		float(centered_state.get("aug_ratio", 1.0)) > 90.0
			and is_equal_approx(drone.aug_ratio, float(centered_state.get("aug_ratio", 1.0))),
		"installed signal station amplifies an allied remote device inside its radius"
	)
	var vehicle_owner_before_neutral_check := vehicle.owner_team
	vehicle.owner_team = ""
	station.tool_owner = ""
	station.call("_refresh_augmented_devices")
	GameAuthority.call("_update_remote_device_link_quality")
	var neutral_state: Dictionary = GameAuthority.remote_device_states[device_id]
	_check(
		float(neutral_state.get("aug_ratio", 1.0)) > 90.0,
		"an unowned map vehicle keeps its mounted signal station operational as a neutral source"
	)
	vehicle.owner_team = vehicle_owner_before_neutral_check
	station.tool_owner = vehicle_owner_before_neutral_check
	var original_vehicle_position := vehicle.global_position
	vehicle.global_position += Vector3(10.0, 0.0, 0.0)
	await get_tree().physics_frame
	station.call("_refresh_augmented_devices")
	GameAuthority.call("_update_remote_device_link_quality")
	var moved_state: Dictionary = GameAuthority.remote_device_states[device_id]
	_check(
		float(moved_state.get("aug_ratio", 1.0)) > 1.0
			and float(moved_state.get("aug_ratio", 1.0)) < 10.0,
		"signal station coverage follows the moving FarmBaseVehicle"
	)
	vehicle.global_position = original_vehicle_position
	GameAuthority.remote_device_states.erase(device_id)
	drone.queue_free()


func _grant_filler_items(amount: int) -> void:
	var state: Dictionary = GameAuthority.player_states.get(1, {})
	for index in range(amount):
		GameAuthority.call(
			"_server_add_personal_ingredient",
			state,
			"farm_base_vehicle_rollback_filler_%d" % index,
			1.0,
			false
		)
	GameAuthority.player_states[1] = state


func _clear_personal_inventory() -> void:
	var state: Dictionary = GameAuthority.player_states.get(1, {}).duplicate(true)
	state["personal_ingredients"] = {}
	state["backpack_layout_valid"] = true
	state["backpack_slot_items"] = GameAuthority.call("_build_initial_backpack_layout", state)
	GameAuthority.player_states[1] = state


func _module_item_count(module_id: String) -> int:
	var state: Dictionary = GameAuthority.player_states.get(1, {})
	var values: Variant = state.get("personal_ingredients", {})
	if not values is Dictionary:
		return 0
	return floori(float((values as Dictionary).get(_module_item_id(module_id) + "|whole", 0.0)))


func _module_item_id(module_id: String) -> String:
	return "metal_defense_net" if module_id == "vehicle_metal_defense_net" else module_id


func _module_count(vehicle: FarmBaseVehicle, module_id: String) -> int:
	match module_id:
		"vehicle_harvest_reel": return 1 if vehicle.harvest_reel_installed else 0
		"vehicle_extended_seat": return vehicle.platform_passenger_seat_count
		"vehicle_roof_headlights": return 1 if vehicle.roof_headlights_installed else 0
		"vehicle_machine_gun": return 1 if vehicle.platform_machine_gun_installed else 0
		"vehicle_nitro_boost": return 1 if vehicle.nitro_boost_installed else 0
		"vehicle_signal_augment": return 1 if vehicle.platform_signal_station_installed else 0
		"vehicle_metal_defense_net": return 1 if vehicle.reinforced_variant else 0
	return 0


func _quote_module(quote: Dictionary, module_id: String) -> Dictionary:
	var modules_value: Variant = quote.get("modules", [])
	if modules_value is Array:
		for module_value: Variant in modules_value as Array:
			if module_value is Dictionary and str((module_value as Dictionary).get("module_id", "")) == module_id:
				return module_value as Dictionary
	return {}


func _add_box_body(body_name: String, position: Vector3, size: Vector3, layer: int) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.position = position
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	return body


func _check(condition: bool, label: String) -> void:
	if condition:
		print("[FarmBaseVehicleModulesValidation] PASS " + label)
	else:
		failures += 1
		push_error("[FarmBaseVehicleModulesValidation] FAIL " + label)


func _finish() -> void:
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
