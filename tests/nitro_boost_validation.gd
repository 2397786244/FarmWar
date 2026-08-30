extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const BASE_FORWARD_SPEED := 5.0
const BASE_REVERSE_SPEED := 4.0
const EXPECTED_FORWARD_SPEED := 8.0
const EXPECTED_REVERSE_SPEED := 8.0

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene loads")
	if vehicle == null:
		_finish()
		return

	_check(vehicle.find_child("NitroBoostPos", true, false) is Marker3D, "NitroBoostPos is found recursively")
	_check(vehicle.find_child("NitroBoostFlash1", true, false) is Marker3D, "NitroBoostFlash1 is found recursively")
	_check(vehicle.find_child("NitroBoostFlash2", true, false) is Marker3D, "NitroBoostFlash2 is found recursively")
	_check(is_equal_approx(vehicle.get_max_forward_speed(), BASE_FORWARD_SPEED), "uninstalled FarmBaseVehicle keeps 5 m/s forward speed")
	var editor_preview := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	editor_preview.set_nitro_boost_installed(true)
	var preview_visual := editor_preview.find_child("VehicleNitroBoost", true, false) as Node3D
	_check(preview_visual != null and preview_visual.visible, "editor preview shows NitroBoost immediately after enabling it")
	editor_preview.free()

	vehicle.set_nitro_boost_installed(false)
	add_child(vehicle)
	await get_tree().process_frame
	var visual := vehicle.find_child("VehicleNitroBoost", true, false) as Node3D
	_check(visual != null and not visual.visible, "uninstalled NitroBoost visual is hidden")

	vehicle.set_nitro_boost_installed(true)
	await get_tree().process_frame
	var nitro := vehicle.get_nitro_boost()
	_check(nitro != null, "installed NitroBoost controller is created")
	_check(vehicle.get_max_forward_speed() == EXPECTED_FORWARD_SPEED, "NitroBoost raises forward maximum to 8 m/s")
	_check(vehicle.get_max_reverse_speed() == EXPECTED_REVERSE_SPEED, "NitroBoost doubles reverse maximum to 8 m/s")
	_check(visual != null and visual.visible, "installed NitroBoost visual is shown")
	if nitro == null:
		_finish()
		return

	_check(nitro.get_flash_markers().size() == 2, "controller finds both exhaust markers recursively")
	var emitters := nitro.get_emitters()
	_check(emitters.size() == 4, "each exhaust marker gets blue and yellow particle emitters")
	for emitter: GPUParticles3D in emitters:
		var material := emitter.process_material as ParticleProcessMaterial
		_check(material != null, "NitroBoost emitter has a ParticleProcessMaterial")
		if material != null:
			_check(material.direction.is_equal_approx(Vector3(0.0, 0.0, 1.0)), "NitroBoost particles emit along local +Z")
			_check(material.initial_velocity_max >= 8.8, "NitroBoost flame has the extended spray velocity")
		_check(emitter.lifetime >= 0.38, "NitroBoost flame remains visible farther from the nozzle")
		_check(emitter.local_coords, "NitroBoost emitter uses marker-local orientation")
		_check(not emitter.emitting, "NitroBoost particles start disabled")

	nitro.set_boost_active(true)
	_check(nitro.is_boost_active(), "NitroBoost active state is set")
	for emitter: GPUParticles3D in emitters:
		_check(emitter.emitting, "active NitroBoost enables exhaust particles")
	nitro.set_boost_active(false)
	for emitter: GPUParticles3D in emitters:
		_check(not emitter.emitting, "inactive NitroBoost disables exhaust particles")

	var state := vehicle.get_network_state()
	_check(bool(state.get("nitro_boost_installed", false)), "NitroBoost installation is in the vehicle snapshot")
	_check(state.get("nitro_boost", {}) is Dictionary, "NitroBoost state has a persistent dictionary")

	vehicle.set_nitro_boost_installed(false)
	await get_tree().process_frame
	_check(vehicle.get_nitro_boost() == null, "removing NitroBoost frees its controller")
	_check(vehicle.get_max_forward_speed() == BASE_FORWARD_SPEED, "removing NitroBoost restores 5 m/s forward speed")
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[NitroBoostValidation] PASS all checks")
	else:
		push_error("[NitroBoostValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[NitroBoostValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[NitroBoostValidation] FAIL: %s" % description)
