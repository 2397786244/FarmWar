extends Node3D
class_name FarmFieldGenerator

signal field_generated(field_id: String, tiles: Array[FarmTile])
signal generation_progress(field_id: String, generated_count: int, total_count: int)

const COLLISION_CHUNK_SIZE := 16
const OWNER_TINT_SHADER := preload("res://src/farm_owner_tint.gdshader")
const TILE_VISUAL_SIZE := Vector3(2.0, 0.06, 2.0)
const OWNER_TINT_HEIGHT := 0.095
const OWNER_TINT_SIZE := Vector2(1.96, 1.96)

@export var field_label := "field"
@export_range(1, 128, 1) var length_tiles := 16
@export_range(1, 128, 1) var width_tiles := 4
@export_range(0.1, 20.0, 0.1) var tile_spacing := 2.2
@export var field_owner := ""
@export var tile_scene: PackedScene = preload("res://items/farm_tile.tscn")
@export var generate_on_ready := true
@export_range(16, 512, 16) var generation_batch_size := 128
@export_color_no_alpha var farm_tile_color := Color(0.36, 0.17, 0.065)
@export_color_no_alpha var field_background_color := Color(0.72, 0.57, 0.27)
@export var generate_visuals_on_headless := false

var generated_tiles: Array[FarmTile] = []
var collision_chunks: Dictionary = {}
var ground_multimesh_instance: MultiMeshInstance3D
var owner_multimesh_instance: MultiMeshInstance3D
var field_background_instance: MeshInstance3D
var ground_multimesh: MultiMesh
var owner_multimesh: MultiMesh
var is_generating := false

var _shared_ground_shape: BoxShape3D
var _shared_hit_shape: BoxShape3D


func _ready() -> void:
	if generate_on_ready:
		generate_field_async()


func generate_field() -> Array[FarmTile]:
	return _generate_field_immediate()


func generate_field_async(batch_size_override := -1) -> Array[FarmTile]:
	if is_generating:
		return generated_tiles
	is_generating = true
	clear_field()
	if tile_scene == null:
		push_error("FarmFieldGenerator 缺少 tile_scene")
		is_generating = false
		return generated_tiles

	var field_identifier := "%s:%s" % [str(get_path()), field_label]
	Farmlandmanager.register_field_config(field_identifier, tile_spacing)
	var total_count := length_tiles * width_tiles
	_prepare_batched_visuals(total_count)
	_prepare_collision_chunks()
	var batch_size := generation_batch_size if batch_size_override <= 0 else batch_size_override

	for column in range(length_tiles):
		for row in range(width_tiles):
			_create_tile(field_identifier, column, row)
			var generated_count := generated_tiles.size()
			_set_visible_instance_count(generated_count)
			if generated_count % batch_size == 0:
				generation_progress.emit(field_identifier, generated_count, total_count)
				await get_tree().process_frame

	_set_visible_instance_count(total_count)
	generation_progress.emit(field_identifier, total_count, total_count)
	field_generated.emit(field_identifier, generated_tiles)
	is_generating = false
	return generated_tiles


func _generate_field_immediate() -> Array[FarmTile]:
	clear_field()
	if tile_scene == null:
		push_error("FarmFieldGenerator 缺少 tile_scene")
		return generated_tiles
	var field_identifier := "%s:%s" % [str(get_path()), field_label]
	Farmlandmanager.register_field_config(field_identifier, tile_spacing)
	var total_count := length_tiles * width_tiles
	_prepare_batched_visuals(total_count)
	_prepare_collision_chunks()
	for column in range(length_tiles):
		for row in range(width_tiles):
			_create_tile(field_identifier, column, row)
	_set_visible_instance_count(total_count)
	generation_progress.emit(field_identifier, total_count, total_count)
	field_generated.emit(field_identifier, generated_tiles)
	return generated_tiles


func _create_tile(field_identifier: String, column: int, row: int) -> void:
	var tile := tile_scene.instantiate() as FarmTile
	if tile == null:
		push_error("tile_scene 的根节点必须是 FarmTile")
		return
	var instance_index := generated_tiles.size()
	var tile_position := Vector3(float(column) * tile_spacing, 0.0, float(row) * tile_spacing)
	tile.name = "%s_FarmTile_%d_%d" % [field_label, column, row]
	tile.land_owner = field_owner if field_owner in ["red", "blue"] else ""
	tile.grid_coordinate = Vector2i(column, row)
	tile.field_id = field_identifier
	tile.tile_spacing = tile_spacing
	tile.position = tile_position
	tile.prepare_for_batched_visual(self, instance_index)
	_set_visual_instance_transform(instance_index, tile_position)
	add_child(tile)
	generated_tiles.append(tile)
	_add_tile_collision(tile, column, row, tile_position)


func _prepare_batched_visuals(instance_count: int) -> void:
	_clear_batched_visuals()
	if (DisplayServer.get_name() == "headless" and not generate_visuals_on_headless) or instance_count <= 0:
		return

	var tile_material := StandardMaterial3D.new()
	tile_material.albedo_color = farm_tile_color
	tile_material.roughness = 1.0
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = TILE_VISUAL_SIZE
	tile_mesh.material = tile_material
	ground_multimesh = MultiMesh.new()
	ground_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	ground_multimesh.mesh = tile_mesh
	ground_multimesh.instance_count = instance_count
	ground_multimesh.visible_instance_count = 0
	ground_multimesh.custom_aabb = _field_visual_aabb(0.12)
	ground_multimesh_instance = MultiMeshInstance3D.new()
	ground_multimesh_instance.name = "FarmTileMultiMesh"
	ground_multimesh_instance.multimesh = ground_multimesh
	add_child(ground_multimesh_instance)

	var owner_material := ShaderMaterial.new()
	owner_material.shader = OWNER_TINT_SHADER
	owner_material.set_shader_parameter("use_instance_custom_data", true)
	owner_material.set_shader_parameter("border_width", 0.08)
	owner_material.set_shader_parameter("fill_alpha", 0.1)
	owner_material.set_shader_parameter("border_alpha", 0.78)
	var owner_mesh := PlaneMesh.new()
	owner_mesh.size = OWNER_TINT_SIZE
	owner_mesh.material = owner_material
	owner_multimesh = MultiMesh.new()
	owner_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	owner_multimesh.use_custom_data = true
	owner_multimesh.mesh = owner_mesh
	owner_multimesh.instance_count = instance_count
	owner_multimesh.visible_instance_count = 0
	owner_multimesh.custom_aabb = _field_visual_aabb(0.16)
	owner_multimesh_instance = MultiMeshInstance3D.new()
	owner_multimesh_instance.name = "OwnerTintMultiMesh"
	owner_multimesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	owner_multimesh_instance.multimesh = owner_multimesh
	add_child(owner_multimesh_instance)

	var background_material := StandardMaterial3D.new()
	background_material.albedo_color = field_background_color
	background_material.roughness = 1.0
	var background_mesh := BoxMesh.new()
	background_mesh.size = Vector3(
		float(length_tiles) * tile_spacing,
		0.04,
		float(width_tiles) * tile_spacing
	)
	background_mesh.material = background_material
	field_background_instance = MeshInstance3D.new()
	field_background_instance.name = "FieldBackground"
	field_background_instance.mesh = background_mesh
	field_background_instance.position = Vector3(
		float(length_tiles - 1) * tile_spacing * 0.5,
		0.0,
		float(width_tiles - 1) * tile_spacing * 0.5
	)
	add_child(field_background_instance)


func _prepare_collision_chunks() -> void:
	_clear_collision_chunks()
	_shared_ground_shape = BoxShape3D.new()
	_shared_ground_shape.size = Vector3(2.0, 0.15, 2.0)
	_shared_hit_shape = BoxShape3D.new()
	_shared_hit_shape.size = Vector3(2.0, 0.8, 2.0)
	_shared_hit_shape.margin = 0.05
	var chunk_columns := ceili(float(length_tiles) / float(COLLISION_CHUNK_SIZE))
	var chunk_rows := ceili(float(width_tiles) / float(COLLISION_CHUNK_SIZE))
	for chunk_x in range(chunk_columns):
		for chunk_y in range(chunk_rows):
			var coordinate := Vector2i(chunk_x, chunk_y)
			var chunk := FarmCollisionChunk.new()
			chunk.configure(coordinate, _shared_ground_shape, _shared_hit_shape)
			chunk.position = Vector3(
				float(chunk_x * COLLISION_CHUNK_SIZE) * tile_spacing,
				0.0,
				float(chunk_y * COLLISION_CHUNK_SIZE) * tile_spacing
			)
			add_child(chunk)
			collision_chunks[coordinate] = chunk


func _add_tile_collision(
	tile: FarmTile,
	column: int,
	row: int,
	tile_position: Vector3
) -> void:
	var coordinate := Vector2i(column / COLLISION_CHUNK_SIZE, row / COLLISION_CHUNK_SIZE)
	var chunk := collision_chunks.get(coordinate, null) as FarmCollisionChunk
	if chunk == null:
		push_error("FarmFieldGenerator 缺少碰撞 Chunk %s" % coordinate)
		return
	chunk.add_tile(tile, tile_position - chunk.position)


func _set_visual_instance_transform(instance_index: int, tile_position: Vector3) -> void:
	if ground_multimesh != null:
		ground_multimesh.set_instance_transform(
			instance_index,
			Transform3D(Basis.IDENTITY, tile_position + Vector3.UP * 0.05)
		)
	if owner_multimesh != null:
		owner_multimesh.set_instance_transform(
			instance_index,
			Transform3D(Basis.IDENTITY, tile_position + Vector3.UP * OWNER_TINT_HEIGHT)
		)
		owner_multimesh.set_instance_custom_data(instance_index, Color(0.0, 0.0, 0.0, 0.0))


func set_tile_owner_color(instance_index: int, color: Color) -> void:
	if owner_multimesh == null or instance_index < 0 or instance_index >= owner_multimesh.instance_count:
		return
	owner_multimesh.set_instance_custom_data(instance_index, color)


func get_collision_chunk_count() -> int:
	return collision_chunks.size()


func get_collision_shape_count() -> int:
	var count := 0
	for chunk_value: Variant in collision_chunks.values():
		count += (chunk_value as FarmCollisionChunk).get_tile_count()
	return count


func _field_visual_aabb(height: float) -> AABB:
	return AABB(
		Vector3(-1.0, -0.02, -1.0),
		Vector3(
			float(length_tiles - 1) * tile_spacing + 2.0,
			height,
			float(width_tiles - 1) * tile_spacing + 2.0
		)
	)


func _set_visible_instance_count(count: int) -> void:
	if ground_multimesh != null:
		ground_multimesh.visible_instance_count = mini(count, ground_multimesh.instance_count)
	if owner_multimesh != null:
		owner_multimesh.visible_instance_count = mini(count, owner_multimesh.instance_count)


func _clear_batched_visuals() -> void:
	ground_multimesh = null
	owner_multimesh = null
	for visual in [ground_multimesh_instance, owner_multimesh_instance, field_background_instance]:
		if is_instance_valid(visual):
			visual.queue_free()
	ground_multimesh_instance = null
	owner_multimesh_instance = null
	field_background_instance = null


func _clear_collision_chunks() -> void:
	for chunk_value: Variant in collision_chunks.values():
		var chunk := chunk_value as FarmCollisionChunk
		if is_instance_valid(chunk):
			chunk.queue_free()
	collision_chunks.clear()
	_shared_ground_shape = null
	_shared_hit_shape = null


func clear_field() -> void:
	for tile in generated_tiles:
		if is_instance_valid(tile):
			Farmlandmanager.unregister_land(tile)
			tile.queue_free()
	generated_tiles.clear()
	_clear_collision_chunks()
	_clear_batched_visuals()
