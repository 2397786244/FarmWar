extends Node

const SPATIAL_BUCKET_SIZE := 16.0
const INVALID_CLEANUP_INTERVAL := 30.0

var all_lands: Array[FarmTile] = []
var lands_record: Dictionary = {
	"red": [],
	"blue": [],
}

var field_configs: Dictionary = {}
var default_spacing := 2.2
var growth_tick := 0.0
var cleanup_tick := 0.0

var _land_by_id: Dictionary = {}
var _owner_lands: Dictionary = {
	"red": {},
	"blue": {},
}
var _owner_cache_dirty: Dictionary = {
	"red": false,
	"blue": false,
}
var _claimable_lands: Dictionary = {}
var _active_lands: Dictionary = {}
var _spatial_buckets: Dictionary = {}
var _tile_bucket_by_id: Dictionary = {}


func _physics_process(delta: float) -> void:
	if GameAuthority.is_client_proxy():
		return
	growth_tick += delta
	cleanup_tick += delta
	while growth_tick >= 1.0:
		growth_tick -= 1.0
		step_timer()
	if cleanup_tick >= INVALID_CLEANUP_INTERVAL:
		cleanup_tick = 0.0
		_cleanup_invalid_lands()


func register_field_config(field_id: String, spacing: float) -> void:
	if field_id.is_empty():
		return
	field_configs[field_id] = {"spacing": spacing}
	default_spacing = spacing


func register_land(tile: FarmTile) -> void:
	if not is_instance_valid(tile):
		return
	var tile_id := tile.get_instance_id()
	if _land_by_id.has(tile_id):
		return
	_land_by_id[tile_id] = tile
	all_lands.append(tile)
	_add_to_owner_index(tile, tile.land_owner)
	_add_to_spatial_index(tile)
	refresh_land_state(tile)


func reg_land(_team_name: String, land: FarmTile) -> void:
	register_land(land)


func unregister_land(tile: FarmTile) -> void:
	if tile == null:
		return
	var tile_id := tile.get_instance_id()
	if not _land_by_id.erase(tile_id):
		return
	all_lands.erase(tile)
	_claimable_lands.erase(tile_id)
	_active_lands.erase(tile_id)
	_remove_from_spatial_index(tile_id)
	for owner: String in _owner_lands:
		if (_owner_lands[owner] as Dictionary).erase(tile_id):
			_owner_cache_dirty[owner] = true


func change_land_owner(tile: FarmTile, new_owner: String) -> bool:
	if not is_instance_valid(tile):
		return false
	var old_owner := tile.land_owner
	if old_owner == new_owner:
		tile._on_land_owner_changed(old_owner, new_owner)
		return true

	var tile_id := tile.get_instance_id()
	for owner: String in _owner_lands:
		if (_owner_lands[owner] as Dictionary).erase(tile_id):
			_owner_cache_dirty[owner] = true
	tile.land_owner = new_owner
	_add_to_owner_index(tile, new_owner)
	tile._on_land_owner_changed(old_owner, new_owner)
	return true


func refresh_land_state(tile: FarmTile) -> void:
	if not is_instance_valid(tile):
		return
	var tile_id := tile.get_instance_id()
	if not _land_by_id.has(tile_id):
		return
	if tile.is_empty():
		_claimable_lands[tile_id] = tile
	else:
		_claimable_lands.erase(tile_id)
	if tile.needs_simulation_tick():
		_active_lands[tile_id] = tile
	else:
		_active_lands.erase(tile_id)


func get_all_plots() -> Array:
	return all_lands


func get_team_plots(team: String) -> Array:
	if not _owner_lands.has(team):
		return []
	if bool(_owner_cache_dirty.get(team, true)):
		var rebuilt: Array = (_owner_lands[team] as Dictionary).values()
		lands_record[team] = rebuilt
		_owner_cache_dirty[team] = false
	return lands_record[team]


func get_claimable_plots(_team: String) -> Array:
	return _claimable_lands.values()


func get_plots_in_radius(world_position: Vector3, radius: float) -> Array:
	var result: Array = []
	var radius_squared := radius * radius
	var minimum_bucket := _bucket_for_position(world_position - Vector3(radius, 0.0, radius))
	var maximum_bucket := _bucket_for_position(world_position + Vector3(radius, 0.0, radius))
	for bucket_x in range(minimum_bucket.x, maximum_bucket.x + 1):
		for bucket_y in range(minimum_bucket.y, maximum_bucket.y + 1):
			var bucket_key := Vector2i(bucket_x, bucket_y)
			var bucket: Dictionary = _spatial_buckets.get(bucket_key, {})
			for tile_value: Variant in bucket.values():
				var tile := tile_value as FarmTile
				if is_instance_valid(tile) and tile.global_position.distance_squared_to(world_position) <= radius_squared:
					result.append(tile)
	return result


func resolve_farm_tile(collider: Object, shape_index: int = -1) -> FarmTile:
	if collider is FarmTile:
		return collider as FarmTile
	if not collider is CollisionObject3D:
		return null
	var collision_object := collider as CollisionObject3D
	var chunk := collision_object.get_parent() as FarmCollisionChunk
	if chunk == null or shape_index < 0:
		return null
	if collision_object == chunk.ground_body:
		return chunk.resolve_ground_shape(shape_index)
	if collision_object == chunk.hit_area:
		return chunk.resolve_hit_shape(shape_index)
	return null


func resolve_raycast_tile(cast: RayCast3D) -> FarmTile:
	if cast == null or not cast.is_colliding():
		return null
	return resolve_farm_tile(cast.get_collider(), cast.get_collider_shape())


func resolve_shapecast_tile(cast: ShapeCast3D, collision_index: int) -> FarmTile:
	if cast == null or collision_index < 0 or collision_index >= cast.get_collision_count():
		return null
	return resolve_farm_tile(
		cast.get_collider(collision_index),
		cast.get_collider_shape(collision_index)
	)


func resolve_hit_tile(hit: Dictionary) -> FarmTile:
	return resolve_farm_tile(
		hit.get("collider", null),
		int(hit.get("shape", -1))
	)


func get_team_spacing(_owner: String, fallback := 2.2) -> float:
	return default_spacing if default_spacing > 0.0 else fallback


func step_timer() -> void:
	# Copying only the active set allows a tile to remove itself while stepping.
	var active_snapshot: Array = _active_lands.values()
	for tile_value: Variant in active_snapshot:
		var tile := tile_value as FarmTile
		if is_instance_valid(tile):
			tile.step()
			refresh_land_state(tile)


func get_performance_stats() -> Dictionary:
	return {
		"total_tiles": _land_by_id.size(),
		"active_tiles": _active_lands.size(),
		"claimable_tiles": _claimable_lands.size(),
		"spatial_buckets": _spatial_buckets.size(),
	}


func _add_to_owner_index(tile: FarmTile, owner: String) -> void:
	if owner.is_empty():
		return
	if not _owner_lands.has(owner):
		_owner_lands[owner] = {}
		_owner_cache_dirty[owner] = true
		lands_record[owner] = []
	var tile_id := tile.get_instance_id()
	(_owner_lands[owner] as Dictionary)[tile_id] = tile
	_owner_cache_dirty[owner] = true


func _add_to_spatial_index(tile: FarmTile) -> void:
	var tile_id := tile.get_instance_id()
	var bucket_key := _bucket_for_position(tile.global_position)
	if not _spatial_buckets.has(bucket_key):
		_spatial_buckets[bucket_key] = {}
	(_spatial_buckets[bucket_key] as Dictionary)[tile_id] = tile
	_tile_bucket_by_id[tile_id] = bucket_key


func _remove_from_spatial_index(tile_id: int) -> void:
	var bucket_key: Variant = _tile_bucket_by_id.get(tile_id, null)
	if bucket_key == null:
		return
	var bucket: Dictionary = _spatial_buckets.get(bucket_key, {})
	bucket.erase(tile_id)
	if bucket.is_empty():
		_spatial_buckets.erase(bucket_key)
	_tile_bucket_by_id.erase(tile_id)


func _bucket_for_position(position: Vector3) -> Vector2i:
	return Vector2i(
		floori(position.x / SPATIAL_BUCKET_SIZE),
		floori(position.z / SPATIAL_BUCKET_SIZE)
	)


func _cleanup_invalid_lands() -> void:
	var invalid_ids: Array[int] = []
	for tile_id: int in _land_by_id:
		if not is_instance_valid(_land_by_id[tile_id]):
			invalid_ids.append(tile_id)
	for tile_id in invalid_ids:
		_land_by_id.erase(tile_id)
		_claimable_lands.erase(tile_id)
		_active_lands.erase(tile_id)
		_remove_from_spatial_index(tile_id)
		for owner: String in _owner_lands:
			if (_owner_lands[owner] as Dictionary).erase(tile_id):
				_owner_cache_dirty[owner] = true
	if not invalid_ids.is_empty():
		var valid_lands: Array[FarmTile] = []
		for tile in all_lands:
			if is_instance_valid(tile):
				valid_lands.append(tile)
		all_lands = valid_lands
