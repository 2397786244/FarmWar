extends Node3D

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "FirePickupValidationRoot"
	add_child(root)
	var packed := load("res://vehicles/fire_pickup.tscn") as PackedScene
	_check(packed != null, "fire pickup scene loads")
	if packed == null:
		_finish(root)
		return
	var vehicle = packed.instantiate()
	_check(vehicle != null and vehicle is VehicleBase, "fire pickup scene instantiates as VehicleBase")
	if vehicle == null:
		_finish(root)
		return
	root.add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle is CharacterBody3D, "fire pickup root is CharacterBody3D")
	_check(vehicle.get_seat_count() == 2, "fire pickup has one driver and one passenger seat")
	_check(vehicle.get_driver_seat_index() == 0, "driver seat is seat zero")
	_check(is_equal_approx(vehicle.vehicle_config.max_hp, 1000.0), "fire pickup has 1000 HP")
	_check(is_equal_approx(vehicle.get_max_forward_speed(), 8.0), "fire pickup maximum speed is 8 m/s")
	_check(not vehicle.supports_cargo(), "fire pickup does not support cargo")
	_check(vehicle.is_in_group("vehicle_bases"), "fire pickup registers as a vehicle")
	_check(vehicle.get_node_or_null("VehicleShape") is CollisionShape3D, "vehicle collision shape exists")
	_check(vehicle.get_node_or_null("Hit3D/CollisionShape3D") is CollisionShape3D, "vehicle hit shape exists")

	var mesh := vehicle.get_node("Mesh") as Node3D
	var headlight := vehicle.get_node("HeadLightPos/Light3D") as Light3D
	var headlight_left := mesh.find_child("HeadlightGlow_L", true, false) as Node3D
	var headlight_right := mesh.find_child("HeadlightGlow_R", true, false) as Node3D
	var tail_left := mesh.find_child("TailLightGlow_L", true, false) as Node3D
	var tail_right := mesh.find_child("TailLightGlow_R", true, false) as Node3D
	_check(headlight != null and not headlight.visible, "headlight starts off")
	_check(headlight_left != null and not headlight_left.visible, "left headlight glow starts off")
	_check(headlight_right != null and not headlight_right.visible, "right headlight glow starts off")
	_check(tail_left != null and not tail_left.visible, "left tail light starts off")
	_check(tail_right != null and not tail_right.visible, "right tail light starts off")

	vehicle.toggle_headlights()
	_check(vehicle.headlights_on and headlight != null and headlight.visible, "headlight switch enables Light3D")
	_check(headlight_left != null and headlight_left.visible, "headlight switch enables left glow")
	_check(headlight_right != null and headlight_right.visible, "headlight switch enables right glow")

	_check(vehicle.enter_driver(1), "driver can enter")
	_check(vehicle.enter_seat(2, 1), "passenger can enter")
	_check(not vehicle.can_enter_seat(3, 2), "third occupant cannot enter")
	vehicle.set_drive_input(0.0, 0.0, 1.0)
	_check(vehicle.brake_lights_on, "braking updates brake light state")
	_check(tail_left != null and tail_left.visible, "braking enables left tail light")
	_check(tail_right != null and tail_right.visible, "braking enables right tail light")
	vehicle.set_drive_input(0.0, 0.0, 0.0)
	_check(not vehicle.brake_lights_on, "releasing brake disables brake light state")
	_check(tail_left != null and not tail_left.visible, "releasing brake disables left tail light")
	_check(tail_right != null and not tail_right.visible, "releasing brake disables right tail light")
	_check(bool(vehicle.get_network_state().get("headlights_on", false)), "headlight state is network-visible")

	_finish(root)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[FirePickupValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[FirePickupValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
