extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene loads")
	if vehicle == null:
		_finish()
		return

	_check(vehicle.platform_passenger_seat_count == 0, "FarmBaseVehicle defaults to no passenger seats")
	_check(vehicle.get_seat_count() == 1, "the default vehicle exposes only the driver seat")
	var marker_one := vehicle.find_child("PlatformSeat1", true, false) as Marker3D
	var marker_two := vehicle.find_child("PlatformSeat2", true, false) as Marker3D
	_check(marker_one != null and marker_two != null, "both markers are found recursively")
	var seat_pos_one := marker_one.find_child("SeatPos", true, false) as Marker3D if marker_one != null else null
	var seat_pos_two := marker_two.find_child("SeatPos", true, false) as Marker3D if marker_two != null else null
	_check(
		seat_pos_one != null and seat_pos_two != null,
		"each PlatformSeat recursively exposes its SeatPos marker"
	)
	_check(
		marker_one != null and marker_one.find_child("PlatformSeatVisual1", true, false) != null
			and marker_two != null and marker_two.find_child("PlatformSeatVisual2", true, false) != null,
		"both PlatformSeat GLB visuals are attached below their markers"
	)
	var visual_one := marker_one.find_child("PlatformSeatVisual1", true, false) as Node3D if marker_one != null else null
	var visual_two := marker_two.find_child("PlatformSeatVisual2", true, false) as Node3D if marker_two != null else null
	_check(
		visual_one != null and not visual_one.visible and visual_two != null and not visual_two.visible,
		"the default vehicle hides both seat visuals"
	)
	_check(vehicle.add_platform_passenger_seats(1) == 1, "one platform passenger seat can be added")
	_check(vehicle.get_seat_count() == 2, "one passenger seat adds one seat after the driver")
	_check(vehicle.add_platform_passenger_seats(2) == 2, "two platform passenger seats can be added")
	_check(vehicle.get_seat_count() == 3, "driver plus two passenger seats are exposed")

	add_child(vehicle)
	await get_tree().process_frame
	_check(vehicle.get_seat_anchor(1) == seat_pos_one, "passenger seat 1 uses PlatformSeat1/SeatPos as its anchor")
	_check(vehicle.get_seat_anchor(2) == seat_pos_two, "passenger seat 2 uses PlatformSeat2/SeatPos as its anchor")
	_check(
		seat_pos_one != null
			and vehicle.get_occupant_world_transform(1).origin.distance_to(seat_pos_one.global_position) < 0.001
			and seat_pos_two != null
			and vehicle.get_occupant_world_transform(2).origin.distance_to(seat_pos_two.global_position) < 0.001,
		"passenger character position is placed exactly at each SeatPos marker"
	)
	var passenger_area := vehicle.find_child("PlatformPassengerInteractionArea", true, false) as VehiclePlatformInteractionArea
	_check(
		passenger_area != null and passenger_area.get_interaction_kind() == "passenger",
		"the rear platform creates a dedicated passenger interaction area"
	)
	var passenger_forward := -vehicle.get_occupant_world_transform(1).basis.z.normalized()
	_check(
		passenger_forward.dot(Vector3.BACK) > 0.99,
		"passenger occupants face the vehicle rear (+Z)"
	)

	_check(vehicle.enter_seat(101, 0), "driver can enter the driver seat")
	_check(vehicle.enter_seat(102, 1), "first passenger can enter platform seat 1")
	_check(vehicle.enter_seat(103, 2), "second passenger can enter platform seat 2")
	_check(vehicle.get_available_platform_passenger_seat_index() == -1, "full passenger platform reports no free seat")
	_check(not vehicle.can_enter_platform_passenger(104), "full passenger platform rejects a new passenger")
	_check(not vehicle.enter_seat(104, 1), "an occupied passenger seat cannot be double-booked")
	_check(vehicle.get_driver_seat_index() == 0 and vehicle.driver_peer_id == 101, "passengers do not become the driver")
	var network_state := vehicle.get_network_state()
	_check(
		int(network_state.get("platform_passenger_seat_count", 0)) == 2
			and (network_state.get("seat_occupants", []) as Array).size() == 3,
		"seat count and all occupants are included in the vehicle snapshot"
	)
	_check(vehicle.exit_seat(102) == 1, "passenger exits through the shared vehicle exit path")
	_check(vehicle.get_available_platform_passenger_seat_index() == 1, "the freed passenger seat becomes available")

	if is_instance_valid(vehicle):
		vehicle.queue_free()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[PlatformSeatValidation] PASS all checks")
	else:
		push_error("[PlatformSeatValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PlatformSeatValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[PlatformSeatValidation] FAIL: %s" % description)
