extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var root := Node3D.new()
	root.name = "AtvValidationRoot"
	add_child(root)
	var packed := load("res://vehicles/atv.tscn") as PackedScene
	_check(packed != null, "ATV scene loads")
	if packed == null:
		_finish(root)
		return
	var vehicle := packed.instantiate() as VehicleBase
	_check(vehicle != null, "ATV scene instantiates as VehicleBase")
	if vehicle == null:
		_finish(root)
		return
	root.add_child(vehicle)
	await get_tree().process_frame

	_check(vehicle is CharacterBody3D, "ATV root is CharacterBody3D")
	_check(vehicle.get_seat_count() == 1, "ATV has one seat")
	_check(vehicle.get_driver_seat_index() == 0, "ATV seat is the driver seat")
	_check(vehicle.vehicle_config.open_cabin, "ATV uses open-cabin presentation")
	_check(vehicle.should_show_occupant(0), "ATV shows its driver")
	_check(vehicle.get_seat_anchor(0) == vehicle.get_node("DriverSeat"), "ATV uses the authored DriverSeat marker")
	_check(is_equal_approx(vehicle.vehicle_config.max_hp, 500.0), "ATV has 500 HP")
	_check(is_equal_approx(vehicle.current_hp, 500.0), "ATV starts at 500 HP")
	_check(is_equal_approx(vehicle.get_max_forward_speed(), 8.0), "ATV maximum speed is 8 m/s")
	_check(is_equal_approx(vehicle.get_camera_fov_for_speed(8.0), 97.0), "ATV reaches its configured top-speed FOV")
	_check(not vehicle.supports_cargo(), "ATV does not support cargo")
	_check(vehicle.is_in_group("vehicle_bases"), "ATV registers as a vehicle")
	_check(vehicle.get_node_or_null("GroundProbe") is RayCast3D, "ground probe exists")
	_check(vehicle.get_node_or_null("Hit3D") is Area3D, "hit area exists")
	_check(vehicle.get_node_or_null("Hit3D/CollisionPolygon3D") is CollisionPolygon3D, "hit polygon exists")

	var mesh := vehicle.get_node("Mesh") as Node3D
	var headlight := vehicle.get_node("HeadLightPos/Light3D") as Light3D
	var headlight_glow := mesh.find_child("HeadlightGlow", true, false) as Node3D
	var tail_left := mesh.find_child("TailLightGlow_L", true, false) as Node3D
	var tail_right := mesh.find_child("TailLightGlow_R", true, false) as Node3D
	_check(headlight != null and not headlight.visible, "headlight starts off")
	_check(headlight_glow != null and not headlight_glow.visible, "single headlight glow starts off")
	_check(tail_left != null and not tail_left.visible, "left tail light starts off")
	_check(tail_right != null and not tail_right.visible, "right tail light starts off")

	vehicle.toggle_headlights()
	_check(vehicle.headlights_on and headlight != null and headlight.visible, "headlight switch enables Light3D")
	_check(headlight_glow != null and headlight_glow.visible, "headlight switch enables the single glow")

	_check(vehicle.enter_driver(1), "driver can enter")
	vehicle.set_drive_input(0.0, 0.0, 1.0)
	_check(vehicle.brake_lights_on, "braking updates brake light state")
	_check(tail_left != null and tail_left.visible, "braking enables left tail light")
	_check(tail_right != null and tail_right.visible, "braking enables right tail light")
	vehicle.set_drive_input(0.0, 0.0, 0.0)
	_check(not vehicle.brake_lights_on, "releasing brake disables brake light state")
	_check(tail_left != null and not tail_left.visible, "releasing brake disables left tail light")
	_check(tail_right != null and not tail_right.visible, "releasing brake disables right tail light")
	_check(bool(vehicle.get_network_state().get("headlights_on", false)), "headlight state is network-visible")

	var player := PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene instantiates for ATV pose validation")
	if player != null:
		root.add_child(player)
		await get_tree().process_frame
		await get_tree().process_frame
		player.active_vehicle = vehicle
		player.active_vehicle_seat_index = 0
		player.vehicle_is_active = true
		player._set_vehicle_player_runtime(true)
		player._update_vehicle_occupant_presentation()
		var expected_animation: StringName = &"Carry" \
			if player.appearance_player.has_animation(&"Carry") else &"Idle"
		_check(
			player.appearance_player.current_animation == expected_animation,
			"ATV driver uses the shared Carry animation"
		)
		var right_leg_ik := player.skeleton.find_child("RightLegIK", false, false) as TwoBoneIK3D
		var left_leg_ik := player.skeleton.find_child("LeftLegIK", false, false) as TwoBoneIK3D
		_check(
			right_leg_ik != null and left_leg_ik != null
				and is_equal_approx(right_leg_ik.influence, 1.0)
				and is_equal_approx(left_leg_ik.influence, 1.0),
			"ATV driver enables both leg IK modifiers"
		)


	_finish(root)


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[AtvValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[AtvValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
