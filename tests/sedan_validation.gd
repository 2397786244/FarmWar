extends Node3D

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var map_editor_script := load("res://src/farmwar_runtime_map_editor.gd") as Script
	_check(map_editor_script != null, "map editor script loads with Sedan support")

	var root := Node3D.new()
	root.name = "SedanValidationRoot"
	add_child(root)
	var packed := load("res://vehicles/sedan.tscn") as PackedScene
	_check(packed != null, "Sedan scene loads")
	if packed == null:
		_finish(root)
		return

	var vehicle := packed.instantiate() as VehicleBase
	_check(vehicle != null, "Sedan scene instantiates as VehicleBase")
	if vehicle == null:
		_finish(root)
		return
	root.add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle is CharacterBody3D, "Sedan root is CharacterBody3D")
	_check(vehicle.get_seat_count() == 4, "Sedan has four seats")
	_check(vehicle.get_driver_seat_index() == 0, "Sedan seat zero is the driver seat")
	_check(vehicle.seat_can_drive(0), "Sedan driver seat can drive")
	for seat_index in range(1, 4):
		_check(not vehicle.seat_can_drive(seat_index), "Sedan passenger seat %d cannot drive" % seat_index)
	_check(not vehicle.vehicle_config.open_cabin, "Sedan is a closed vehicle")
	_check(is_equal_approx(vehicle.vehicle_config.max_hp, 800.0), "Sedan has 800 HP")
	_check(is_equal_approx(vehicle.current_hp, 800.0), "Sedan starts at full HP")
	_check(is_equal_approx(vehicle.get_max_forward_speed(), 8.0), "Sedan maximum speed is 8 m/s")
	_check(is_equal_approx(vehicle.get_camera_fov_for_speed(8.0), 84.0), "Sedan reaches its top-speed FOV")
	_check(not vehicle.supports_cargo(), "Sedan does not support cargo")
	_check(vehicle.is_in_group("vehicle_bases"), "Sedan registers as a vehicle")
	_check(vehicle.get_node_or_null("GroundProbe") is RayCast3D, "Sedan has a ground probe")
	_check(vehicle.get_node_or_null("Hit3D") is Area3D, "Sedan has a hit area")
	_check(
		vehicle.get_node_or_null("Hit3D/CollisionPolygon3D") is CollisionPolygon3D,
		"Sedan keeps its hit polygon"
	)
	for anchor_name in ["DriverSeat", "PassengerSeat1", "PassengerSeat2", "PassengerSeat3"]:
		_check(vehicle.get_node_or_null(anchor_name) is Node3D, "Sedan has %s anchor" % anchor_name)

	var mesh := vehicle.get_node("Mesh") as Node3D
	var headlight := vehicle.get_node("HeadLightPos/Light3D") as Light3D
	var headlight_left := mesh.find_child("HeadlightGlow_L", true, false) as Node3D
	var headlight_right := mesh.find_child("HeadlightGlow_R", true, false) as Node3D
	var tail_left := mesh.find_child("TailLightGlow_L", true, false) as Node3D
	var tail_right := mesh.find_child("TailLightGlow_R", true, false) as Node3D
	_check(mesh != null, "Sedan has a Mesh visual node")
	_check(headlight != null and not headlight.visible, "Sedan headlight starts off")
	_check(headlight_left != null and not headlight_left.visible, "Sedan left headlight glow starts off")
	_check(headlight_right != null and not headlight_right.visible, "Sedan right headlight glow starts off")
	_check(tail_left != null and not tail_left.visible, "Sedan left tail light starts off")
	_check(tail_right != null and not tail_right.visible, "Sedan right tail light starts off")

	vehicle.toggle_headlights()
	_check(vehicle.headlights_on, "Sedan records headlights as enabled")
	_check(headlight != null and headlight.visible, "Sedan enables HeadLightPos/Light3D")
	_check(headlight_left != null and headlight_left.visible, "Sedan enables left headlight glow")
	_check(headlight_right != null and headlight_right.visible, "Sedan enables right headlight glow")

	_check(vehicle.enter_driver(101), "Sedan accepts the driver")
	_check(vehicle.enter_seat(102, 1), "Sedan accepts front passenger")
	_check(vehicle.enter_seat(103, 2), "Sedan accepts rear-left passenger")
	_check(vehicle.enter_seat(104, 3), "Sedan accepts rear-right passenger")
	_check(not vehicle.can_enter_seat(105), "Sedan rejects a fifth occupant")
	_check(vehicle.get_seat_occupants() == [101, 102, 103, 104], "Sedan tracks all four occupants")
	vehicle.set_drive_input(0.0, 0.0, 1.0)
	_check(vehicle.brake_lights_on, "Sedan enables brake lights while braking")
	_check(tail_left != null and tail_left.visible, "Sedan enables left brake light")
	_check(tail_right != null and tail_right.visible, "Sedan enables right brake light")
	vehicle.set_drive_input(0.0, 0.0, 0.0)
	_check(not vehicle.brake_lights_on, "Sedan disables brake lights after braking")
	_check(tail_left != null and not tail_left.visible, "Sedan disables left brake light")
	_check(tail_right != null and not tail_right.visible, "Sedan disables right brake light")
	_check(bool(vehicle.get_network_state().get("headlights_on", false)), "Sedan exposes headlight state")

	_finish(root)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[SedanValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[SedanValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
