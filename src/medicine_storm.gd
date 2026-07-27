extends Node3D
class_name MedicineStorm

## A healing gas cloud. It shares BugStorm's ShapeCast approach, but has its
## own large pink smoke particles and treats each team differently.

@export var source_team := ""
@export_range(0.5, 60.0, 0.5) var lifetime := 20.0
@export_range(0.1, 5.0, 0.1) var tick_interval := 1.0
@export var effect_distance := 20.0
@export var effect_strength := 1.0
@export var fade_time := 2.0
@export var visual_only := false

@export_group("Visual")
@export_range(0.0, 1.0, 0.01) var max_fog_alpha := 0.48
@export var fog_visual_height := 8.0
@export var fog_particle_amount := 90

@onready var effect_cast: ShapeCast3D = $EffectCast
@onready var storm_visual: MeshInstance3D = $StormVisual

var _life_left := 0.0
var _tick_left := 0.0
var _fade_left := 0.0
var _fading := false
var _fog_material: StandardMaterial3D
var _fog_particles: GPUParticles3D
var _base_scale := Vector3.ONE


func _ready() -> void:
	add_to_group("medicine_mist")
	_life_left = lifetime
	_tick_left = 0.0
	_base_scale = scale
	_setup_visuals()
	_setup_effect_cast()
	if _fog_particles != null:
		_fog_particles.emitting = true
	call_deferred("_neutralize_overlapping_bug_storms")


func _setup_effect_cast() -> void:
	if effect_cast == null:
		push_error("MedicineStorm requires an EffectCast ShapeCast3D node.")
		set_physics_process(false)
		return
	effect_cast.enabled = true
	effect_cast.target_position = Vector3.ZERO
	effect_cast.collide_with_bodies = true


func _setup_visuals() -> void:
	if storm_visual == null:
		push_warning("MedicineStorm has no StormVisual mesh; only the gas particles will be visible.")
	else:
		_setup_fog_material()
	_setup_fog_particles()


func _setup_fog_material() -> void:
	storm_visual.scale = Vector3(
		effect_distance,
		fog_visual_height,
		effect_distance
	)
	var source_material: Material = storm_visual.material_override
	if source_material == null and storm_visual.mesh != null and storm_visual.mesh.get_surface_count() > 0:
		source_material = storm_visual.get_active_material(0)
	if source_material is StandardMaterial3D:
		_fog_material = (source_material as StandardMaterial3D).duplicate()
	else:
		_fog_material = StandardMaterial3D.new()
	_fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fog_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	_fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_fog_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fog_material.albedo_color = Color(0.96, 0.22, 0.55, max_fog_alpha)
	storm_visual.material_override = _fog_material


func _setup_fog_particles() -> void:
	_fog_particles = GPUParticles3D.new()
	_fog_particles.name = "MedicineFogParticles"
	_fog_particles.emitting = false
	_fog_particles.one_shot = false
	_fog_particles.amount = fog_particle_amount
	_fog_particles.lifetime = 3.2
	_fog_particles.preprocess = 1.5
	_fog_particles.explosiveness = 0.0
	_fog_particles.randomness = 0.9
	_fog_particles.fixed_fps = 30
	_fog_particles.local_coords = true
	_fog_particles.visibility_aabb = AABB(
		Vector3(-effect_distance, -1.0, -effect_distance),
		Vector3(
			effect_distance * 2.0,
			fog_visual_height + 2.0,
			effect_distance * 2.0
		)
	)
	var process_material := ParticleProcessMaterial.new()
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	process_material.emission_sphere_radius = effect_distance * 0.75
	process_material.direction = Vector3(0.0, 0.35, 0.0)
	process_material.spread = 180.0
	process_material.initial_velocity_min = 0.15
	process_material.initial_velocity_max = 0.85
	process_material.gravity = Vector3(0.0, 0.08, 0.0)
	process_material.radial_accel_min = -0.2
	process_material.radial_accel_max = 0.75
	process_material.tangential_accel_min = -0.6
	process_material.tangential_accel_max = 0.6
	process_material.damping_min = 0.15
	process_material.damping_max = 0.65
	process_material.scale_min = 0.8
	process_material.scale_max = 2.4
	process_material.color = Color(1.0, 0.30, 0.62, 0.32)
	_fog_particles.process_material = process_material
	var fog_mesh := QuadMesh.new()
	fog_mesh.size = Vector2(1.0, 1.0)
	var fog_material := StandardMaterial3D.new()
	fog_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fog_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fog_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	fog_material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	fog_material.albedo_color = Color(1.0, 0.36, 0.68, 0.18)
	fog_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fog_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fog_mesh.material = fog_material
	_fog_particles.draw_passes = 1
	_fog_particles.draw_pass_1 = fog_mesh
	add_child(_fog_particles)


func _physics_process(delta: float) -> void:
	if _fading:
		_update_fade(delta)
		return
	_life_left -= delta
	_tick_left -= delta
	if _tick_left <= 0.0:
		_tick_left = tick_interval
		_apply_medicine_tick()
		_neutralize_overlapping_bug_storms()
	if _life_left <= 0.0:
		_begin_fade()


func _apply_medicine_tick() -> void:
	if visual_only or effect_cast == null:
		return
	effect_cast.force_shapecast_update()
	var seen := {}
	for index in range(effect_cast.get_collision_count()):
		var target := _resolve_impact_target(effect_cast.get_collider(index))
		if target == null:
			continue
		var id := target.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		target.call("impact", "medicine_storm", effect_strength, source_team)


func _resolve_impact_target(collider: Variant) -> Node:
	if not collider is Node:
		return null
	var cursor := collider as Node
	for _depth in range(5):
		if cursor == null:
			return null
		if cursor is GamePlayer or cursor is AIPlayerv2:
			return cursor
		cursor = cursor.get_parent()
	return null


func _neutralize_overlapping_bug_storms() -> void:
	for node in get_tree().get_nodes_in_group("bug_storm"):
		if not is_instance_valid(node) or not node is Node3D:
			continue
		var bug_storm := node as Node3D
		var bug_radius := float(bug_storm.get("effect_distance"))
		if global_position.distance_to(bug_storm.global_position) > effect_distance + bug_radius:
			continue
		if bug_storm.has_method("neutralize_by_medicine"):
			bug_storm.call("neutralize_by_medicine", self)


func _begin_fade() -> void:
	if _fading:
		return
	_fading = true
	_fade_left = fade_time
	if effect_cast != null:
		effect_cast.enabled = false
	if _fog_particles != null:
		_fog_particles.emitting = false


func _update_fade(delta: float) -> void:
	_fade_left = maxf(0.0, _fade_left - delta)
	var t := 1.0 - _fade_left / maxf(fade_time, 0.001)
	if _fog_material != null:
		var color := _fog_material.albedo_color
		color.a = lerpf(max_fog_alpha, 0.0, t)
		_fog_material.albedo_color = color
	scale = _base_scale.lerp(_base_scale * 1.15, t)
	if _fade_left <= 0.0:
		queue_free()
