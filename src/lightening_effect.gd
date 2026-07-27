extends Node3D
class_name LightningBolt

@export var segment_count: int = 10
@export var bend_amount: float = 0.35
@export var lifetime: float = 0.12
@export var redraw_count: int = 3

@export var outer_radius: float = 0.055
@export var core_radius: float = 0.018

@export var outer_material: Material
@export var core_material: Material

@export var hit_particles: GPUParticles3D
@export var flash_light: OmniLight3D

var _outer_parts: Array[MeshInstance3D] = []
var _core_parts: Array[MeshInstance3D] = []


func _ready() -> void:
	_create_segment_pool()
	
func _create_segment_pool() -> void:
	for i in range(segment_count):
		var outer_part := _create_cylinder_part(outer_radius, outer_material)
		var core_part := _create_cylinder_part(core_radius, core_material)

		add_child(outer_part)
		add_child(core_part)

		_outer_parts.append(outer_part)
		_core_parts.append(core_part)


func _create_cylinder_part(radius: float, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = 1.0
	cylinder.radial_segments = 6

	part.mesh = cylinder
	part.material_override = material
	part.visible = false

	return part


func strike(from_global: Vector3, hit_global: Vector3, hit_normal: Vector3 = Vector3.UP) -> void:
	# 根节点直接放在闪电起点，后续点都使用局部坐标。
	global_transform = Transform3D(Basis.IDENTITY, from_global)
	visible = true

	if hit_particles:
		hit_particles.global_position = hit_global
		hit_particles.restart()
		hit_particles.emitting = true

	if flash_light:
		flash_light.global_position = hit_global
		flash_light.visible = true

	var local_target := hit_global - from_global
	var interval := lifetime / float(max(redraw_count, 1))

	for i in range(redraw_count):
		var points := _make_lightning_points(local_target)
		_draw_chain(points, _outer_parts)
		_draw_chain(points, _core_parts)

		await get_tree().create_timer(interval).timeout

	_hide_all_parts()

	if flash_light:
		flash_light.visible = false

	queue_free()


func _make_lightning_points(target_local: Vector3) -> PackedVector3Array:
	var points := PackedVector3Array()
	var length := target_local.length()

	if length < 0.01:
		points.append(Vector3.ZERO)
		points.append(target_local)
		return points

	var direction := target_local.normalized()

	# 找两个与闪电方向垂直的方向，用于左右、上下随机抖动。
	var side := direction.cross(Vector3.UP)

	if side.length_squared() < 0.001:
		side = direction.cross(Vector3.RIGHT)

	side = side.normalized()

	var up := direction.cross(side).normalized()

	for i in range(segment_count + 1):
		var t := float(i) / float(segment_count)
		var base_pos := target_local * t

		# 两端不偏移，中间偏移最大。
		var envelope := sin(t * PI)

		var random_offset := (
			side * randf_range(-1.0, 1.0)
			+ up * randf_range(-1.0, 1.0)
		) * bend_amount * envelope

		var point := base_pos + random_offset

		if i == 0:
			point = Vector3.ZERO
		elif i == segment_count:
			point = target_local

		points.append(point)

	return points


func _draw_chain(points: PackedVector3Array, parts: Array[MeshInstance3D]) -> void:
	var used_count := points.size() - 1

	for i in range(parts.size()):
		parts[i].visible = i < used_count

	for i in range(used_count):
		var a := points[i]
		var b := points[i + 1]

		var delta := b - a
		var length := delta.length()

		if length < 0.001:
			parts[i].visible = false
			continue

		var cylinder := parts[i].mesh as CylinderMesh
		cylinder.height = length

		parts[i].position = (a + b) * 0.5
		parts[i].basis = Basis(Quaternion(Vector3.UP, delta.normalized()))
		parts[i].visible = true


func _hide_all_parts() -> void:
	for part in _outer_parts:
		part.visible = false

	for part in _core_parts:
		part.visible = false
