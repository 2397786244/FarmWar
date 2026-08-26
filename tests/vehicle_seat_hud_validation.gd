extends Node3D

const SEDAN_SCENE := preload("res://vehicles/sedan.tscn")
const FARM_BASE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const VEHICLE_SEAT_HUD_SCRIPT := preload("res://src/vehicle_seat_hud.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var hud := VEHICLE_SEAT_HUD_SCRIPT.new() as Control
	hud.name = "VehicleSeatHudValidation"
	hud.size = Vector2(246.0, 112.0)
	add_child(hud)
	await get_tree().process_frame

	hud.call("configure", 1, [101], 0)
	_check(hud.visible, "single-seat HUD is visible")
	_check(int(hud.get("displayed_seat_count")) == 1, "single-seat HUD displays one dot")
	_check(hud.get("displayed_occupants") == [101], "single-seat HUD displays its occupant")
	_check(hud.get("displayed_key_hints") == [], "single-seat HUD hides seat switching hints")

	hud.call("configure", 2, [101, 0], 0)
	_check(int(hud.get("displayed_seat_count")) == 2, "two-seat HUD displays two dots")
	_check(hud.get("displayed_occupants") == [101, 0], "two-seat HUD preserves an empty passenger")
	_check(hud.get("displayed_key_hints") == ["按[2]坐到乘客位"], "two-seat driver sees only the passenger shortcut")
	hud.call("configure", 2, [101, 0], 1)
	_check(hud.get("displayed_key_hints") == ["按[1]坐到主驾驶位"], "two-seat passenger sees only the driver shortcut")

	hud.call("configure", 4, [101, 0, 103, 0], 2)
	_check(int(hud.get("displayed_seat_count")) == 4, "four-seat HUD displays front and rear seats")
	_check(int(hud.get("displayed_current_seat")) == 2, "four-seat HUD tracks the current seat")
	_check(
		hud.get("displayed_key_hints") == ["按[1]坐到主驾驶位", "按[2]/[4]坐到乘客位"],
		"four-seat HUD hides the current seat shortcut"
	)
	hud.call("clear")
	_check(not hud.visible and int(hud.get("displayed_seat_count")) == 0, "HUD clears outside a vehicle")

	var root := Node3D.new()
	root.name = "VehicleSeatHudValidationRoot"
	add_child(root)
	var sedan := SEDAN_SCENE.instantiate() as VehicleBase
	_check(sedan != null, "Sedan instantiates for seat switching")
	if sedan != null:
		root.add_child(sedan)
		await get_tree().process_frame
		_check(sedan.get_cabin_seat_count() == 4, "Sedan exposes four cabin seats")
		_check(sedan.enter_seat(1, 0), "driver occupies Sedan seat zero")
		_check(sedan.enter_seat(2, 2), "rear passenger occupies Sedan seat two")
		_check(not sedan.can_switch_seat(1, 2), "occupied target seat cannot be selected")
		_check(sedan.can_switch_seat(1, 1), "empty target seat can be selected")
		_check(sedan.switch_seat(1, 1), "seat switch changes the authoritative occupancy")
		_check(sedan.get_seat_occupants() == [0, 1, 2, 0], "seat switch updates both seat slots")
		GameAuthority.start_local_mode({
			"display_name": "VehicleSeatHudValidation",
			"team": "red",
			"position": sedan.global_position,
		})
		var authority_state: Dictionary = GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID]
		authority_state["vehicle_id"] = sedan.get_vehicle_id()
		authority_state["vehicle_seat_index"] = 1
		GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] = authority_state
		GameAuthority.server_vehicle_action(GameAuthority.LOCAL_PLAYER_ID, {
			"vehicle_id": sedan.get_vehicle_id(),
			"action": "switch_vehicle_seat",
			"seat_index": 3,
		})
		_check(sedan.get_seat_index_for_peer(GameAuthority.LOCAL_PLAYER_ID) == 3, "authority accepts a free seat switch")
		_check(
			int((GameAuthority.player_states[GameAuthority.LOCAL_PLAYER_ID] as Dictionary).get("vehicle_seat_index", -1)) == 3,
			"authority updates the player's seat state"
		)
		GameAuthority.server_vehicle_action(GameAuthority.LOCAL_PLAYER_ID, {
			"vehicle_id": sedan.get_vehicle_id(),
			"action": "switch_vehicle_seat",
			"seat_index": 2,
		})
		_check(sedan.get_seat_index_for_peer(GameAuthority.LOCAL_PLAYER_ID) == 3, "authority rejects an occupied target seat")
		GameAuthority.stop_authority()

	var farm_base := FARM_BASE_SCENE.instantiate() as FarmBaseVehicle
	_check(farm_base != null, "FarmBaseVehicle instantiates for cabin-seat filtering")
	if farm_base != null:
		farm_base.platform_passenger_seat_count = 2
		root.add_child(farm_base)
		await get_tree().process_frame
		_check(farm_base.get_seat_count() == 3, "FarmBaseVehicle still exposes its two platform seats")
		_check(farm_base.get_cabin_seat_count() == 1, "FarmBaseVehicle HUD exposes only the cabin seat")
		_check(farm_base.get_cabin_seat_occupants().size() == 1, "platform seats are excluded from HUD occupants")
		_check(not farm_base.is_cabin_seat(1), "first platform seat is outside numeric cabin switching")

	_finish(root)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[VehicleSeatHudValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[VehicleSeatHudValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
