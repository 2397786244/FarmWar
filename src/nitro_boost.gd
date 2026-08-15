extends Node3D
class_name NitroBoost

## Controller for the optional FarmBaseVehicle rear nitro module. The model is
## authored in the vehicle scene; this node only owns the runtime exhaust.
const FLASH_MARKER_NAMES := ["NitroBoostFlash1", "NitroBoostFlash2"]
const BLUE_COLOR := Color(0.08, 0.42, 1.0, 1.0)
const YELLOW_COLOR := Color(1.0, 0.78, 0.08, 1.0)
const PARTICLE_DIRECTION := Vector3(0.0, 0.0, 1.0)

var boost_active := false
var _flash_markers: Array[Marker3D] = []
var _emitters: Array[GPUParticles3D] = []
var _vehicle_root: Node
var _ready_complete := false


func _ready() -> void:
	_vehicle_root = _find_vehicle_root()
	if _vehicle_root == null:
		push_warning("NitroBoost: could not find the owning VehicleBase.")
	else:
		for marker_name: String in FLASH_MARKER_NAMES:
			var marker := _vehicle_root.find_child(marker_name, true, false) as Marker3D
			if marker == null:
				push_warning("NitroBoost: missing recursive %s marker." % marker_name)
				continue
			_flash_markers.append(marker)
			_create_marker_emitters(marker)
	_ready_complete = true
	_set_emitters_active(boost_active)


func _exit_tree() -> void:
	# Emitters are parented to the authored flash markers so their local +Z
	# orientation is preserved. Remove them explicitly when the optional
	# controller is uninstalled; otherwise reinstalling would duplicate them.
	for emitter: GPUParticles3D in _emitters:
		if is_instance_valid(emitter):
			emitter.queue_free()
	_emitters.clear()
	_flash_markers.clear()


func _find_vehicle_root() -> Node:
	var current: Node = get_parent()
	while current != null:
		if current is VehicleBase:
			return current
		current = current.get_parent()
	return null


func _create_marker_emitters(marker: Marker3D) -> void:
	_create_emitter(marker, "NitroBlueParticles", BLUE_COLOR, 40, 0.38, 0.050, 0.095)
	_create_emitter(marker, "NitroYellowParticles", YELLOW_COLOR, 32, 0.46, 0.040, 0.080)


func _create_emitter(
	marker: Marker3D,
	emitter_name: String,
	color: Color,
	amount_value: int,
	lifetime_value: float,
	radius_min: float,
	radius_max: float
) -> void:
	var emitter := GPUParticles3D.new()
	emitter.name = emitter_name
	emitter.amount = amount_value
	emitter.lifetime = lifetime_value
	emitter.one_shot = false
	emitter.explosiveness = 0.0
	emitter.randomness = 0.65
	# Keeping local coordinates makes the process direction follow each
	# marker's authored orientation, including the required local +Z nozzle.
	emitter.local_coords = true
	emitter.visibility_aabb = AABB(
		Vector3(-0.8, -0.8, -0.8),
		Vector3(1.6, 1.6, 9.0)
	)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	process_material.direction = PARTICLE_DIRECTION
	process_material.spread = 14.0
	process_material.initial_velocity_min = 5.0
	process_material.initial_velocity_max = 8.8
	process_material.gravity = Vector3(0.0, 0.35, 0.0)
	process_material.damping_min = 0.15
	process_material.damping_max = 0.45
	process_material.scale_min = 0.9
	process_material.scale_max = 1.75
	process_material.color = color
	emitter.process_material = process_material

	var particle_mesh := SphereMesh.new()
	particle_mesh.radius = radius_max
	particle_mesh.height = radius_max * 2.0
	particle_mesh.radial_segments = 8
	particle_mesh.rings = 4
	var particle_material := StandardMaterial3D.new()
	particle_material.albedo_color = color
	particle_material.emission_enabled = true
	particle_material.emission = color
	particle_material.emission_energy_multiplier = 4.2
	particle_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	particle_mesh.material = particle_material
	emitter.draw_pass_1 = particle_mesh
	marker.add_child(emitter)
	_emitters.append(emitter)


func set_boost_active(active: bool) -> void:
	boost_active = active
	if _ready_complete:
		_set_emitters_active(active)


func is_boost_active() -> bool:
	return boost_active


func get_flash_markers() -> Array[Marker3D]:
	return _flash_markers.duplicate()


func get_emitters() -> Array[GPUParticles3D]:
	return _emitters.duplicate()


func _set_emitters_active(active: bool) -> void:
	for emitter: GPUParticles3D in _emitters:
		if not is_instance_valid(emitter):
			continue
		if active and not emitter.emitting:
			emitter.restart()
		emitter.emitting = active
