extends Node3D
class_name FarmCollisionChunk

const GROUND_COLLISION_LAYER := 64
const GROUND_COLLISION_MASK := 27
const HIT_COLLISION_LAYER := 0
const HIT_COLLISION_MASK := 32

var chunk_coordinate := Vector2i.ZERO
var ground_body: StaticBody3D
var hit_area: Area3D
var _ground_shape: Shape3D
var _hit_shape: Shape3D
var _ground_shape_to_tile: Dictionary = {}
var _hit_shape_to_tile: Dictionary = {}
var _tile_count := 0


func configure(
	coordinate: Vector2i,
	ground_shape: Shape3D,
	hit_shape: Shape3D
) -> void:
	chunk_coordinate = coordinate
	_ground_shape = ground_shape
	_hit_shape = hit_shape
	name = "FarmCollisionChunk_%d_%d" % [coordinate.x, coordinate.y]

	ground_body = StaticBody3D.new()
	ground_body.name = "GroundCollision"
	ground_body.collision_layer = GROUND_COLLISION_LAYER
	ground_body.collision_mask = GROUND_COLLISION_MASK
	add_child(ground_body)

	hit_area = Area3D.new()
	hit_area.name = "HitDetection"
	hit_area.collision_layer = HIT_COLLISION_LAYER
	hit_area.collision_mask = HIT_COLLISION_MASK
	hit_area.monitoring = true
	hit_area.monitorable = false
	add_child(hit_area)
	hit_area.body_shape_entered.connect(_on_body_shape_entered)


func add_tile(tile: FarmTile, local_position: Vector3) -> void:
	if not is_instance_valid(tile) or ground_body == null or hit_area == null:
		return
	var ground_owner_id := ground_body.create_shape_owner(tile)
	ground_body.shape_owner_add_shape(ground_owner_id, _ground_shape)
	ground_body.shape_owner_set_transform(
		ground_owner_id,
		Transform3D(Basis.IDENTITY, local_position + Vector3.UP * 0.04)
	)
	var ground_shape_index := ground_body.shape_owner_get_shape_index(ground_owner_id, 0)
	_ground_shape_to_tile[ground_shape_index] = tile

	var hit_owner_id := hit_area.create_shape_owner(tile)
	hit_area.shape_owner_add_shape(hit_owner_id, _hit_shape)
	hit_area.shape_owner_set_transform(
		hit_owner_id,
		Transform3D(Basis.IDENTITY, local_position - Vector3.UP * 0.08)
	)
	var hit_shape_index := hit_area.shape_owner_get_shape_index(hit_owner_id, 0)
	_hit_shape_to_tile[hit_shape_index] = tile
	_tile_count += 1


func resolve_ground_shape(shape_index: int) -> FarmTile:
	return _ground_shape_to_tile.get(shape_index, null) as FarmTile


func resolve_hit_shape(shape_index: int) -> FarmTile:
	return _hit_shape_to_tile.get(shape_index, null) as FarmTile


func get_tile_count() -> int:
	return _tile_count


func _on_body_shape_entered(
	_body_rid: RID,
	body: Node3D,
	_body_shape_index: int,
	local_shape_index: int
) -> void:
	var tile := resolve_hit_shape(local_shape_index)
	if tile != null:
		tile.handle_chunk_hit_body(body)
