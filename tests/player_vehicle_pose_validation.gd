extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")
const VEHICLE_SCENE := preload("res://vehicles/cargo_car.tscn")
const CLOSED_VEHICLE_SCENE := preload("res://vehicles/sedan.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var player := PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene creates a GamePlayer")
	if player == null:
		_finish()
		return
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame
	var player_camera := player.camera as Camera3D
	_check(player_camera != null, "player camera exists")
	if player_camera != null:
		_check(is_equal_approx(player_camera.fov, 90.0), "player first-person FOV is 90 degrees")
		player.tool_definitions[0] = player.all_tool_definitions_by_id["m4"].duplicate(true)
		player.current_tool_index = 0
		player.is_weapon_aiming = true
		player._update_weapon_aim(1.0 / 60.0)
		_check(player_camera.fov < 90.0, "aiming narrows the first-person FOV")
		player.is_weapon_aiming = false
		for _frame in range(60):
			player._update_weapon_aim(1.0 / 60.0)
		_check(absf(player_camera.fov - 90.0) < 0.01, "releasing aim restores the first-person FOV")

	_check(player.find_child("RightLegIKTarget", true, false) != null, "right leg target exists")
	_check(player.find_child("LeftLegIKTarget", true, false) != null, "left leg target exists")
	_check(player.find_child("RightKneePole", true, false) != null, "right knee pole exists")
	_check(player.find_child("LeftKneePole", true, false) != null, "left knee pole exists")
	var right_leg_ik := player.skeleton.find_child("RightLegIK", false, false) as TwoBoneIK3D if player.skeleton != null else null
	var left_leg_ik := player.skeleton.find_child("LeftLegIK", false, false) as TwoBoneIK3D if player.skeleton != null else null
	_check(right_leg_ik != null and left_leg_ik != null, "both leg IK modifiers are created for the default hero")
	if right_leg_ik == null or left_leg_ik == null:
		if is_instance_valid(player):
			player.queue_free()
		_finish()
		return
	_check(is_zero_approx(right_leg_ik.influence) and is_zero_approx(left_leg_ik.influence), "leg IK is disabled while standing")

	var vehicle := VEHICLE_SCENE.instantiate() as VehicleBase
	_check(vehicle != null, "cargo vehicle creates a VehicleBase")
	if vehicle == null:
		player.queue_free()
		_finish()
		return
	add_child(vehicle)
	await get_tree().process_frame
	_check(is_equal_approx(vehicle.vehicle_config.camera_base_fov, 85.0), "vehicle driving base FOV is 85 degrees")
	_check(is_equal_approx(vehicle.get_camera_fov_for_speed(0.0), 85.0), "vehicle FOV starts at its 85-degree base")
	_check(is_equal_approx(vehicle.get_camera_fov_for_speed(vehicle.get_max_forward_speed()), 92.5), "vehicle FOV expands dynamically with speed")
	player.active_vehicle = vehicle
	player.active_vehicle_seat_index = 0
	player.vehicle_is_active = true
	player._set_vehicle_player_runtime(true)
	player._update_vehicle_occupant_presentation()
	_check(
		is_equal_approx(right_leg_ik.influence, 1.0)
			and is_equal_approx(left_leg_ik.influence, 1.0),
		"visible vehicle seating enables both leg IK modifiers"
	)
	_check(
		is_zero_approx(player.right_arm_ik.influence)
			and is_zero_approx(player.left_arm_ik.influence),
		"vehicle seating disables both hand IK modifiers"
	)
	var expected_animation: StringName = &"Carry" \
		if player.appearance_player.has_animation(&"Carry") else &"Idle"
	_check(player.appearance_player.current_animation == expected_animation, "vehicle seating selects Carry or Idle fallback")

	player.vehicle_is_active = false
	player.active_vehicle = null
	player._set_vehicle_player_runtime(false)
	_check(
		is_zero_approx(right_leg_ik.influence) and is_zero_approx(left_leg_ik.influence),
		"exiting the vehicle disables both leg IK modifiers"
	)
	_check(
		player.right_hand_ik_target.position.is_equal_approx(player.punch_hand_camera_offset),
		"exiting with a visible tool restores the camera-space hand target"
	)

	var closed_vehicle := CLOSED_VEHICLE_SCENE.instantiate() as VehicleBase
	_check(closed_vehicle != null, "closed-cabin vehicle creates a VehicleBase")
	if closed_vehicle != null:
		closed_vehicle.network_id = "closed_vehicle_camera_validation"
		add_child(closed_vehicle)
		await get_tree().process_frame
		player.active_vehicle = closed_vehicle
		player.active_vehicle_id = closed_vehicle.get_vehicle_id()
		player.active_vehicle_seat_index = 0
		player.vehicle_is_active = true
		player._set_vehicle_player_runtime(true)
		player._ensure_vehicle_camera()
		var closed_vehicle_camera := closed_vehicle.get_driving_camera()
		_check(
			closed_vehicle_camera != null
				and get_viewport().get_camera_3d() == closed_vehicle_camera
				and not player_camera.current,
			"entering a closed vehicle switches away from the first-person camera"
		)
		player_camera.make_current()
		_check(get_viewport().get_camera_3d() == player_camera, "validation can simulate camera ownership being stolen")
		player._ensure_local_camera_ownership()
		_check(
			get_viewport().get_camera_3d() == closed_vehicle_camera,
			"seated camera ownership self-heals before gameplay UI early returns"
		)
		player.vehicle_is_active = false
		player.active_vehicle_id = ""
		player.active_vehicle_seat_index = -1
		player.active_vehicle = null
		player._set_vehicle_player_runtime(false)
		player_camera.make_current()
		closed_vehicle.queue_free()

	player.queue_free()
	vehicle.queue_free()
	await get_tree().process_frame
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[PlayerVehiclePoseValidation] PASS all checks")
	else:
		push_error("[PlayerVehiclePoseValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[PlayerVehiclePoseValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[PlayerVehiclePoseValidation] FAIL: %s" % description)
