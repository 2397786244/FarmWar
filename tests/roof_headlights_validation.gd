extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const EXPECTED_ENERGY := 24.0
const EXPECTED_RANGE := 30.0
const EXPECTED_ANGLE := 35.0

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var preview := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(preview != null, "FarmBaseVehicle scene loads")
	if preview == null:
		_finish()
		return
	var mount := preview.find_child("RoofHeadlights", true, false) as Marker3D
	_check(mount != null, "RoofHeadlights mount is found recursively")
	var preview_visual := mount.find_child("RoofHeadlights", true, false) as Node3D if mount != null else null
	_check(preview_visual != null, "authored RoofHeadlights visual is found below the mount")
	preview.set_roof_headlights_installed(true)
	_check(preview.roof_headlights_installed, "RoofHeadlights installation flag is enabled")
	_check(preview_visual != null and preview_visual.visible, "installed RoofHeadlights visual is visible")
	var preview_left_glow := preview_visual.find_child("Glow_Left", true, false) as Node3D if preview_visual != null else null
	var preview_right_glow := preview_visual.find_child("Glow_Right", true, false) as Node3D if preview_visual != null else null
	_check(preview_left_glow != null and preview_right_glow != null, "both RoofHeadlights Glow nodes are found recursively")
	var preview_left_light := preview_left_glow.find_child("RoofHeadlightLight_Left", true, false) as SpotLight3D if preview_left_glow != null else null
	var preview_right_light := preview_right_glow.find_child("RoofHeadlightLight_Right", true, false) as SpotLight3D if preview_right_glow != null else null
	_check(preview_left_light != null and preview_right_light != null, "both RoofHeadlights lights are created below their Glow nodes")
	for light: SpotLight3D in [preview_left_light, preview_right_light]:
		if light == null:
			continue
		_check(is_equal_approx(light.spot_range, EXPECTED_RANGE), "RoofHeadlights range is twice the original range")
		_check(is_equal_approx(light.spot_angle, EXPECTED_ANGLE), "RoofHeadlights uses a directional narrow cone")
		_check(is_equal_approx(light.position.z, 0.2), "RoofHeadlights light is placed in front of its Glow")
		_check(not light.visible, "RoofHeadlights lights start off")
	preview.free()

	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	add_child(vehicle)
	await get_tree().process_frame
	vehicle.set_roof_headlights_installed(true)
	_check(vehicle.get_roof_headlights() != null, "installed vehicle exposes RoofHeadlights")
	vehicle.toggle_headlights()
	_check(vehicle.headlights_on, "toggle_headlights turns the base headlights on")
	var active_visual := vehicle.get_roof_headlights()
	_check(active_visual != null and active_visual.visible, "base headlight switch keeps installed RoofHeadlights visible")
	var active_lights := [
		active_visual.find_child("RoofHeadlightLight_Left", true, false) as SpotLight3D,
		active_visual.find_child("RoofHeadlightLight_Right", true, false) as SpotLight3D,
	]
	for light: SpotLight3D in active_lights:
		_check(light != null and light.visible, "base headlight switch turns on RoofHeadlights light")
		_check(light != null and is_equal_approx(light.light_energy, EXPECTED_ENERGY), "active RoofHeadlights energy is reduced but remains above the original lamp")
		if light != null:
			var light_forward := -light.global_basis.z.normalized()
			var vehicle_front := -vehicle.global_transform.basis.z.normalized()
			_check(light_forward.dot(vehicle_front) > 0.999, "RoofHeadlights projects toward the vehicle -Z front")
	vehicle.toggle_headlights()
	_check(not vehicle.headlights_on, "second toggle turns the base headlights off")
	for light: SpotLight3D in active_lights:
		_check(light != null and not light.visible, "base headlight switch turns off RoofHeadlights light")
	var state := vehicle.get_network_state()
	_check(bool(state.get("roof_headlights_installed", false)), "RoofHeadlights installation is in the vehicle snapshot")
	vehicle.set_roof_headlights_installed(false)
	_check(not vehicle.roof_headlights_installed, "RoofHeadlights can be removed")
	_check(active_visual != null and not active_visual.visible, "removed RoofHeadlights visual is hidden")
	vehicle.queue_free()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[RoofHeadlightsValidation] PASS all checks")
	else:
		push_error("[RoofHeadlightsValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[RoofHeadlightsValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[RoofHeadlightsValidation] FAIL: %s" % description)
