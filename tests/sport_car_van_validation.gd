extends Node3D

const VEHICLE_CASES := [
	{
		"label": "SportCar",
		"scene": "res://vehicles/sport_car.tscn",
		"max_hp": 800.0,
		"max_speed": 10.0,
		"top_speed_fov": 87.0,
	},
	{
		"label": "Van",
		"scene": "res://vehicles/van.tscn",
		"max_hp": 1200.0,
		"max_speed": 6.0,
		"top_speed_fov": 81.0,
	},
]

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var map_editor_script := load("res://src/farmwar_runtime_map_editor.gd") as Script
	_check(map_editor_script != null, "map editor script loads")

	var root := Node3D.new()
	root.name = "SportCarVanValidationRoot"
	add_child(root)
	for case_value in VEHICLE_CASES:
		await _validate_vehicle(root, case_value as Dictionary)

	_finish(root)


func _validate_vehicle(root: Node3D, case_data: Dictionary) -> void:
	var label := str(case_data.get("label", "vehicle"))
	var packed := load(str(case_data.get("scene", ""))) as PackedScene
	_check(packed != null, "%s scene loads" % label)
	if packed == null:
		return

	var vehicle := packed.instantiate() as VehicleBase
	_check(vehicle != null, "%s scene instantiates as VehicleBase" % label)
	if vehicle == null:
		return
	root.add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle is CharacterBody3D, "%s root is CharacterBody3D" % label)
	_check(vehicle.get_seat_count() == 2, "%s has one driver and one passenger seat" % label)
	_check(vehicle.get_driver_seat_index() == 0, "%s driver seat is seat zero" % label)
	_check(vehicle.seat_can_drive(0), "%s driver seat can drive" % label)
	_check(not vehicle.seat_can_drive(1), "%s passenger seat cannot drive" % label)
	_check(vehicle.get_node_or_null("DriverSeat") is Node3D, "%s has driver anchor" % label)
	_check(vehicle.get_node_or_null("PassengerSeat1") is Node3D, "%s has passenger anchor" % label)
	_check(vehicle.vehicle_config.seats[0].anchor_name == "DriverSeat", "%s config uses driver anchor" % label)
	_check(vehicle.vehicle_config.seats[1].anchor_name == "PassengerSeat1", "%s config uses passenger anchor" % label)
	_check(
		is_equal_approx(vehicle.vehicle_config.max_hp, float(case_data.get("max_hp", 0.0))),
		"%s has the configured HP" % label
	)
	_check(
		is_equal_approx(vehicle.current_hp, float(case_data.get("max_hp", 0.0))),
		"%s starts at full HP" % label
	)
	_check(
		is_equal_approx(vehicle.get_max_forward_speed(), float(case_data.get("max_speed", 0.0))),
		"%s has the configured maximum speed" % label
	)
	_check(
		is_equal_approx(
			vehicle.get_camera_fov_for_speed(vehicle.get_max_forward_speed()),
			float(case_data.get("top_speed_fov", 0.0))
		),
		"%s reaches the configured top-speed FOV" % label
	)
	_check(not vehicle.supports_cargo(), "%s does not support cargo" % label)
	_check(vehicle.is_in_group("vehicle_bases"), "%s registers as a vehicle" % label)
	_check(vehicle.get_node_or_null("GroundProbe") is RayCast3D, "%s has a ground probe" % label)
	_check(vehicle.get_node_or_null("Hit3D") is Area3D, "%s has a hit area" % label)
	_check(
		vehicle.get_node_or_null("Hit3D/CollisionPolygon3D") is CollisionPolygon3D,
		"%s keeps its hit polygon" % label
	)

	var mesh := vehicle.get_node("Mesh") as Node3D
	var headlight := vehicle.get_node("HeadLightPos/Light3D") as Light3D
	var headlight_left := mesh.find_child("HeadlightGlow_L", true, false) as Node3D
	var headlight_right := mesh.find_child("HeadlightGlow_R", true, false) as Node3D
	var tail_left := mesh.find_child("TailLightGlow_L", true, false) as Node3D
	var tail_right := mesh.find_child("TailLightGlow_R", true, false) as Node3D
	_check(mesh != null, "%s has a Mesh visual node" % label)
	_check(headlight != null and not headlight.visible, "%s headlight starts off" % label)
	_check(headlight_left != null and not headlight_left.visible, "%s left headlight glow starts off" % label)
	_check(headlight_right != null and not headlight_right.visible, "%s right headlight glow starts off" % label)
	_check(tail_left != null and not tail_left.visible, "%s left tail light starts off" % label)
	_check(tail_right != null and not tail_right.visible, "%s right tail light starts off" % label)

	vehicle.toggle_headlights()
	_check(vehicle.headlights_on, "%s records headlights as enabled" % label)
	_check(headlight != null and headlight.visible, "%s enables HeadLightPos/Light3D" % label)
	_check(headlight_left != null and headlight_left.visible, "%s enables left headlight glow" % label)
	_check(headlight_right != null and headlight_right.visible, "%s enables right headlight glow" % label)

	_check(vehicle.enter_driver(101), "%s accepts the driver" % label)
	_check(vehicle.enter_seat(102, 1), "%s accepts one passenger" % label)
	_check(not vehicle.can_enter_seat(103), "%s rejects a third occupant" % label)
	vehicle.set_drive_input(0.0, 0.0, 1.0)
	_check(vehicle.brake_lights_on, "%s enables brake lights while braking" % label)
	_check(tail_left != null and tail_left.visible, "%s enables left brake light" % label)
	_check(tail_right != null and tail_right.visible, "%s enables right brake light" % label)
	vehicle.set_drive_input(0.0, 0.0, 0.0)
	_check(not vehicle.brake_lights_on, "%s disables brake lights after braking" % label)
	_check(tail_left != null and not tail_left.visible, "%s disables left brake light" % label)
	_check(tail_right != null and not tail_right.visible, "%s disables right brake light" % label)
	_check(bool(vehicle.get_network_state().get("headlights_on", false)), "%s exposes headlight state" % label)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[SportCarVanValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[SportCarVanValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
