extends Node3D
class_name VehicleExplosion

## A deliberately oversized vehicle destruction effect.  It is visual only:
## gameplay damage and occupant handling remain owned by VehicleBase.

@export_enum("four_wheel", "two_wheel") var vehicle_variant := "four_wheel"

const SHOCKWAVE_MESH_OUTER_RADIUS := 0.60
const COMBAT_BALANCE := preload("res://src/combat_balance.gd")

@onready var flash := $Flash as MeshInstance3D
@onready var fire_core := $FireCore as MeshInstance3D
@onready var shockwave := $Shockwave as MeshInstance3D
@onready var blast_gas_particles := $BlastGasParticles as GPUParticles3D
@onready var blast_light := $BlastLight as OmniLight3D
@onready var mushroom_cap := $MushroomCap as Node3D
@onready var mushroom_cap_particles := $MushroomCapParticles as GPUParticles3D

var _profile: Dictionary = {}
var _flash_material: StandardMaterial3D
var _fire_core_material: StandardMaterial3D
var _shockwave_material: StandardMaterial3D
var _cap_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
	add_to_group("vehicle_explosions")
	_profile = _get_profile()
	_duplicate_animated_materials()
	_configure_variant_nodes()
	_start_particles()
	_animate_fireball()
	_animate_shockwave()
	_animate_mushroom_cloud()
	var light_tween := create_tween()
	light_tween.tween_property(blast_light, "light_energy", 0.0, float(_profile["light_fade_time"]))
	get_tree().create_timer(float(_profile["lifetime"])).timeout.connect(queue_free)


func _get_profile() -> Dictionary:
	if vehicle_variant == "two_wheel":
		return {
			"cap_y": 3.70,
			"cap_start_y": 0.70,
			"cap_scale": Vector3(2.80, 0.72, 2.80),
			"cap_particle_scale": Vector3(0.92, 0.82, 0.92),
			"stem_scale": Vector3(0.82, 0.86, 0.82),
			"shockwave_radius": COMBAT_BALANCE.get_float("vehicle_explosion", "radius_two_wheel", 5.2),
			"shockwave_scale": Vector3(0.82, 0.86, 0.82),
			"flash_scale": 3.80,
			"fire_core_scale": 2.25,
			"light_energy": 36.0,
			"light_range": 16.0,
			"lifetime": 4.20,
			"light_fade_time": 0.95,
		}
	return {
		"cap_y": 6.10,
		"cap_start_y": 0.85,
		"cap_scale": Vector3(4.10, 1.00, 4.10),
		"cap_particle_scale": Vector3(1.32, 1.05, 1.32),
		"stem_scale": Vector3(1.0, 1.0, 1.0),
		"shockwave_radius": COMBAT_BALANCE.get_float("vehicle_explosion", "radius_four_wheel", 8.5),
		"shockwave_scale": Vector3.ONE,
		"flash_scale": 5.00,
		"fire_core_scale": 2.80,
		"light_energy": 52.0,
		"light_range": 24.0,
		"lifetime": 4.80,
		"light_fade_time": 1.15,
	}


func _duplicate_animated_materials() -> void:
	_flash_material = _duplicate_material(flash)
	_fire_core_material = _duplicate_material(fire_core)
	_shockwave_material = _duplicate_material(shockwave)
	for child in mushroom_cap.get_children():
		if child is MeshInstance3D:
			var material := _duplicate_material(child as MeshInstance3D)
			if material != null:
				_cap_materials.append(material)


func _duplicate_material(mesh_instance: MeshInstance3D) -> StandardMaterial3D:
	if mesh_instance == null:
		return null
	var source := mesh_instance.material_override as StandardMaterial3D
	if source == null:
		return null
	var copy := source.duplicate() as StandardMaterial3D
	mesh_instance.material_override = copy
	return copy


func _configure_variant_nodes() -> void:
	var cap_y := float(_profile["cap_y"])
	mushroom_cap.position = Vector3(0.0, float(_profile["cap_start_y"]), 0.0)
	mushroom_cap.scale = Vector3(0.06, 0.06, 0.06)
	mushroom_cap.visible = false
	mushroom_cap_particles.position = Vector3(0.0, cap_y, 0.0)
	mushroom_cap_particles.scale = _profile["cap_particle_scale"]
	var stem_particles := $MushroomStemParticles as GPUParticles3D
	stem_particles.scale = _profile["stem_scale"]
	blast_light.light_energy = float(_profile["light_energy"])
	blast_light.omni_range = float(_profile["light_range"])
	shockwave.scale = Vector3(0.16, 0.82, 0.16)


func _start_particles() -> void:
	for child in get_children():
		if child is GPUParticles3D and child != mushroom_cap_particles and child != blast_gas_particles:
			var particles := child as GPUParticles3D
			particles.restart()
			particles.emitting = true
	get_tree().create_timer(0.14).timeout.connect(_start_blast_gas)


func _start_blast_gas() -> void:
	if not is_instance_valid(blast_gas_particles):
		return
	blast_gas_particles.restart()
	blast_gas_particles.emitting = true


func _animate_fireball() -> void:
	flash.scale = Vector3.ONE * 0.18
	var flash_tween := create_tween().set_parallel(true)
	flash_tween.tween_property(flash, "scale", Vector3.ONE * float(_profile["flash_scale"]), 0.25)
	flash_tween.tween_method(_set_flash_alpha, 0.96, 0.0, 0.48)

	fire_core.scale = Vector3.ONE * 0.12
	var core_tween := create_tween().set_parallel(true)
	core_tween.tween_property(fire_core, "scale", Vector3.ONE * float(_profile["fire_core_scale"]), 0.20)
	core_tween.tween_method(_set_fire_core_alpha, 0.98, 0.0, 0.82)


func _animate_shockwave() -> void:
	var target_radius := float(_profile["shockwave_radius"])
	var target_scale: Vector3 = Vector3(
		target_radius / SHOCKWAVE_MESH_OUTER_RADIUS,
		1.0,
		target_radius / SHOCKWAVE_MESH_OUTER_RADIUS
	) * _profile["shockwave_scale"]
	_set_shockwave_alpha(0.0)
	var shockwave_tween := create_tween()
	shockwave_tween.tween_interval(0.10)
	shockwave_tween.tween_property(shockwave, "scale", target_scale, 0.58)
	shockwave_tween.parallel().tween_method(_set_shockwave_alpha, 0.88, 0.0, 0.86)


func _animate_mushroom_cloud() -> void:
	var cap_tween := create_tween()
	cap_tween.tween_interval(0.48 if vehicle_variant == "four_wheel" else 0.38)
	cap_tween.tween_callback(_start_mushroom_cap)
	cap_tween.tween_property(
		mushroom_cap,
		"position",
		Vector3(0.0, float(_profile["cap_y"]), 0.0),
		0.92 if vehicle_variant == "four_wheel" else 0.72
	)
	cap_tween.parallel().tween_property(
		mushroom_cap,
		"scale",
		_profile["cap_scale"],
		0.92 if vehicle_variant == "four_wheel" else 0.72
	)
	cap_tween.tween_interval(1.05)
	cap_tween.tween_method(_set_cap_alpha, 0.64, 0.0, 1.55 if vehicle_variant == "four_wheel" else 1.35)


func _start_mushroom_cap() -> void:
	if not is_instance_valid(mushroom_cap) or not is_instance_valid(mushroom_cap_particles):
		return
	mushroom_cap.visible = true
	mushroom_cap_particles.restart()
	mushroom_cap_particles.emitting = true


func _set_flash_alpha(alpha: float) -> void:
	if _flash_material == null:
		return
	var color := _flash_material.albedo_color
	color.a = alpha
	_flash_material.albedo_color = color


func _set_fire_core_alpha(alpha: float) -> void:
	if _fire_core_material == null:
		return
	var color := _fire_core_material.albedo_color
	color.a = alpha
	_fire_core_material.albedo_color = color


func _set_shockwave_alpha(alpha: float) -> void:
	if _shockwave_material == null:
		return
	var color := _shockwave_material.albedo_color
	color.a = alpha
	_shockwave_material.albedo_color = color


func _set_cap_alpha(alpha: float) -> void:
	for material in _cap_materials:
		if material == null:
			continue
		var color := material.albedo_color
		color.a = alpha
		material.albedo_color = color
