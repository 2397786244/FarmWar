extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const GROUND_LAYER := 1

var failures := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_client_mode()
	GlobalVar.gameworld = self
	_add_ground()
	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene loads")
	if vehicle == null:
		_finish()
		return
	vehicle.network_id = "vehicle_local_prediction_validation"
	vehicle.global_position = Vector3(0.0, 0.55, 0.0)
	add_child(vehicle)
	await get_tree().physics_frame

	vehicle.set_local_driver_prediction_active(true)
	_check(vehicle.is_local_driver_prediction_active(), "client driver prediction activates")
	var start_position := vehicle.global_position
	vehicle.submit_local_driver_prediction_frame({
		"vehicle_id": vehicle.get_vehicle_id(),
		"input_seq": 1,
		"throttle": 1.0,
		"steering": 0.0,
		"brake": 0.0,
	})
	_check(
		vehicle.global_position.distance_to(start_position) > 0.00001,
		"sampled driver input advances the local chassis immediately"
	)

	var rendered_position := vehicle.global_position
	var camera_orbit := vehicle.get_node_or_null("CameraOrbitYaw") as Node3D
	var rendered_camera_orbit_position := camera_orbit.global_position if camera_orbit != null else Vector3.ZERO
	var correction := vehicle.get_network_state()
	correction["vehicle_id"] = vehicle.get_vehicle_id()
	correction["last_processed_input_seq"] = 1
	correction["last_input_seq"] = 1
	correction["position"] = rendered_position + Vector3(0.05, 0.0, 0.0)
	vehicle.apply_local_driver_correction(correction)
	_check(
		vehicle.global_position.distance_to(correction["position"] as Vector3) < 0.01,
		"small correction immediately restores the authoritative physical vehicle state"
	)
	_check(
		camera_orbit == null or camera_orbit.global_position.distance_to(rendered_camera_orbit_position) < 0.02,
		"small correction retains a temporary local driver camera presentation offset"
	)

	correction["last_processed_input_seq"] = 2
	correction["last_input_seq"] = 2
	correction["position"] = Vector3(4.0, 0.55, 0.0)
	vehicle.apply_local_driver_correction(correction)
	_check(
		vehicle.global_position.distance_to(correction["position"] as Vector3) < 0.01,
		"large correction hard-resets the local chassis"
	)

	var before_lights := vehicle.headlights_on
	_check(vehicle.predict_headlights_toggle(), "headlight prediction is available")
	_check(vehicle.headlights_on != before_lights, "headlight visual changes locally without a snapshot")
	vehicle.set_local_driver_prediction_active(false)
	_check(not vehicle.is_local_driver_prediction_active(), "prediction clears when the driving session ends")
	_finish()


func _add_ground() -> void:
	var ground := StaticBody3D.new()
	ground.collision_layer = GROUND_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80.0, 1.0, 80.0)
	shape.shape = box
	ground.add_child(shape)
	ground.global_position = Vector3(0.0, -0.5, 0.0)
	add_child(ground)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[VehicleLocalPredictionValidation] PASS: %s" % message)
	else:
		failures += 1
		push_error("[VehicleLocalPredictionValidation] FAIL: %s" % message)


func _finish() -> void:
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
