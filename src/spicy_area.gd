extends Node3D
class_name SpicyArea

@export var source_team := ""
@export var lifetime: float
@export var fade_time: float
@export var area_length: float
@export var area_width: float
@export var area_height: float
@export var tick_interval: float
@export var visual_only := true
@export var visual_edge_padding := 0.55
@export var surface_offset := 0.035

@onready var area_mesh: MeshInstance3D = $AreaMesh
@onready var effect_cast: ShapeCast3D = $EffectCast

var _life_left := 0.0
var _tick_left := 0.0
var _material: ShaderMaterial


func _ready() -> void:
	_apply_combat_balance()
	_life_left = lifetime
	_tick_left = 0.0
	_configure_mesh()
	_configure_effect_cast()


func _apply_combat_balance() -> void:
	lifetime = CombatBalance.get_float("spicy_blaster", "area_lifetime")
	fade_time = CombatBalance.get_float("spicy_blaster", "area_fade_time")
	area_length = CombatBalance.get_float("spicy_blaster", "area_length")
	area_width = CombatBalance.get_float("spicy_blaster", "area_width")
	area_height = CombatBalance.get_float("spicy_blaster", "area_height")
	tick_interval = CombatBalance.get_float("spicy_blaster", "area_tick_interval")


func _configure_mesh() -> void:
	if area_mesh == null:
		return
	# The visual extends just beyond the authoritative rectangle so the irregular
	# liquid edge never makes the gameplay area look smaller than it is.
	area_mesh.scale = Vector3(
		area_width + visual_edge_padding,
		1.0,
		area_length + visual_edge_padding
	)
	area_mesh.position.y = surface_offset
	_material = area_mesh.material_override as ShaderMaterial
	if _material != null:
		_material = _material.duplicate() as ShaderMaterial
		area_mesh.material_override = _material
		_material.set_shader_parameter("opacity", 1.0)


func _configure_effect_cast() -> void:
	if effect_cast == null:
		push_error("SpicyArea requires an EffectCast ShapeCast3D node.")
		return
	var source_shape := effect_cast.shape as BoxShape3D
	if source_shape == null:
		push_error("SpicyArea EffectCast requires a BoxShape3D.")
		effect_cast.enabled = false
		return
	var shape := source_shape.duplicate() as BoxShape3D
	shape.size = Vector3(area_width, area_height, area_length)
	effect_cast.shape = shape
	effect_cast.position.y = area_height * 0.5
	effect_cast.enabled = not visual_only
	effect_cast.target_position = Vector3.ZERO
	effect_cast.collision_mask = GameAuthority.COLLISION_LAYER_CHARACTER
	effect_cast.collide_with_bodies = true
	effect_cast.collide_with_areas = false


func _process(delta: float) -> void:
	_life_left = maxf(0.0, _life_left - delta)
	if _material != null:
		var fade_progress := clampf(_life_left / maxf(fade_time, 0.001), 0.0, 1.0)
		_material.set_shader_parameter("opacity", fade_progress if _life_left <= fade_time else 1.0)
	if _life_left <= 0.0:
		queue_free()


func _physics_process(delta: float) -> void:
	if visual_only or effect_cast == null:
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = tick_interval
	effect_cast.force_shapecast_update()
	var seen := {}
	for index in range(effect_cast.get_collision_count()):
		var target := _resolve_target(effect_cast.get_collider(index))
		if target == null:
			continue
		var id := target.get_instance_id()
		if seen.has(id):
			continue
		seen[id] = true
		_apply_spicy(target)


func _resolve_target(collider: Variant) -> Node:
	if not collider is Node:
		return null
	var cursor := collider as Node
	for _depth in range(5):
		if cursor == null:
			return null
		if cursor is GamePlayer or cursor is CharacterBody3D:
			return cursor
		cursor = cursor.get_parent()
	return null


func _apply_spicy(target: Node) -> void:
	var damage := CombatBalance.get_float("spicy_blaster", "spicy_dps")
	if target is GamePlayer:
		var player := target as GamePlayer
		if player.team != source_team:
			player.impact("spicy", damage, source_team)
	elif GameAuthority.is_server_authority():
		GameAuthority.apply_spicy_shape_cast_hit(target, source_team, damage)
