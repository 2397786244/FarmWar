extends Node3D

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "PoliceCarValidationRoot"
	add_child(root)
	var packed := load("res://vehicles/police_car.tscn") as PackedScene
	_check(packed != null, "police car scene loads")
	if packed == null:
		_finish(root)
		return
	var vehicle := packed.instantiate() as PoliceCar
	_check(vehicle != null, "police car scene instantiates as PoliceCar")
	if vehicle == null:
		_finish(root)
		return
	root.add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle is CharacterBody3D, "police car root is CharacterBody3D")
	_check(vehicle.get_seat_count() == 4, "police car has one driver and three passenger seats")
	_check(vehicle.get_driver_seat_index() == 0, "driver seat is seat zero")
	_check(is_equal_approx(vehicle.vehicle_config.max_hp, 1000.0), "police car has 1000 HP")
	_check(is_equal_approx(vehicle.get_max_forward_speed(), 9.0), "police car maximum speed is 9 m/s")
	_check(not vehicle.supports_cargo(), "police car does not support cargo")
	_check(vehicle.is_in_group("vehicle_bases"), "police car registers as a vehicle")

	var mesh := vehicle.get_node("Mesh") as Node3D
	var headlight := vehicle.get_node("HeadLightPos/Light3D") as Light3D
	var headlight_glow := mesh.find_child("HeadlightGlow_L", true, false) as Node3D
	var tail_glow := mesh.find_child("TailLightGlow_L", true, false) as Node3D
	var blue_glow := mesh.find_child("PoliceLightbarGlow_Blue", true, false) as MeshInstance3D
	var red_glow := mesh.find_child("PoliceLightbarGlow_Red", true, false) as MeshInstance3D
	var blue_material := blue_glow.get_active_material(0) as BaseMaterial3D if blue_glow != null else null
	var red_material := red_glow.get_active_material(0) as BaseMaterial3D if red_glow != null else null
	var blue_albedo := blue_material.albedo_color if blue_material != null else Color.TRANSPARENT
	var red_albedo := red_material.albedo_color if red_material != null else Color.TRANSPARENT
	_check(headlight != null and not headlight.visible, "headlight starts off")
	_check(headlight_glow != null and not headlight_glow.visible, "headlight glow starts off")
	_check(tail_glow != null and not tail_glow.visible, "tail light starts off")
	_check(blue_glow != null and blue_glow.visible, "blue police light lens stays visible")
	_check(red_glow != null and red_glow.visible, "red police light lens stays visible")
	_check(blue_material != null and blue_material.emission_enabled, "blue police light starts with Glow enabled")
	_check(red_material != null and not red_material.emission_enabled, "red police light starts with Glow disabled")

	vehicle.toggle_headlights()
	_check(headlight != null and headlight.visible, "headlight switch enables Light3D")
	_check(headlight_glow != null and headlight_glow.visible, "headlight switch enables glow")
	_check(vehicle.headlights_on, "headlight switch updates state")

	_check(vehicle.enter_driver(1), "driver can enter")
	_check(vehicle.enter_seat(2, 1), "first passenger can enter")
	_check(vehicle.enter_seat(3, 2), "second passenger can enter")
	_check(vehicle.enter_seat(4, 3), "third passenger can enter")
	_check(not vehicle.can_enter_seat(5, 4), "fifth occupant cannot enter")
	vehicle.set_drive_input(0.0, 0.0, 1.0)
	_check(tail_glow != null and tail_glow.visible, "braking enables tail light")
	vehicle.set_drive_input(0.0, 0.0, 0.0)
	_check(tail_glow != null and not tail_glow.visible, "releasing brake disables tail light")

	vehicle._process(0.35)
	_check(blue_glow != null and blue_glow.visible, "blue police light lens remains visible while inactive")
	_check(red_glow != null and red_glow.visible, "red police light lens remains visible while active")
	_check(blue_material != null and not blue_material.emission_enabled, "blue police light Glow alternates off")
	_check(red_material != null and red_material.emission_enabled, "red police light Glow alternates on")
	_check(blue_material != null and blue_material.albedo_color.is_equal_approx(blue_albedo), "blue lens keeps its base color")
	_check(red_material != null and red_material.albedo_color.is_equal_approx(red_albedo), "red lens keeps its base color")
	_check(vehicle.get_network_state().get("police_light_blue_on", true) == false, "police light state is network-visible")

	_finish(root)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[PoliceCarValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[PoliceCarValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
