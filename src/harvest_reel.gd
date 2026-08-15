extends StaticBody3D
class_name HarvestReel

## The reel is a moving physical attachment, not an independent vehicle or
## damageable target.  The combined layer is intentional: regular bodies
## listen for TOOL while tree/nature-resource bodies listen for BULLET.
const MOVEMENT_THRESHOLD := 0.1
const ROTATION_SPEED_RADIANS := 1.0
const BODY_COLLISION_LAYER := GameAuthority.COLLISION_LAYER_TOOL | GameAuthority.COLLISION_LAYER_BULLET
const BODY_COLLISION_MASK := GameAuthority.FREE_PLACEMENT_BLOCKING_MASK
const FARM_TILE_COLLISION_MASK := GameAuthority.COLLISION_LAYER_FARM_TILE
const VISUAL_NODE_NAME := "HarvestReel"
const PIVOT_NODE_NAME := "HarvestReelPivot"
const SHAPE_CAST_NODE_NAME := "ShapeCast3D"

var _vehicle: FarmBaseVehicle
var _visual_root: Node3D
var _reel_pivot: Node3D
var _shape_cast: ShapeCast3D
var _pivot_base_rotation_x := 0.0
var _rotation_phase := 0.0


func _ready() -> void:
	_vehicle = _find_parent_vehicle()
	_cache_nodes()
	_configure_collision()
	_configure_shape_cast()
	_capture_pivot_rotation()
	_configure_parent_collision_exception()


func _process(delta: float) -> void:
	if not _is_vehicle_moving() or _reel_pivot == null:
		return
	_rotation_phase = wrapf(
		_rotation_phase + ROTATION_SPEED_RADIANS * maxf(delta, 0.0),
		0.0,
		TAU
	)
	_reel_pivot.rotation.x = _pivot_base_rotation_x + _rotation_phase


func _physics_process(_delta: float) -> void:
	# A client only animates its local visual. FarmTile mutation and inventory
	# changes must happen once on the local/server authority.
	if not _is_vehicle_moving() or _vehicle == null:
		return
	if not GameAuthority.is_local_authority() and not GameAuthority.is_server_authority():
		return
	if _vehicle.driver_peer_id <= 0 or _shape_cast == null or not is_inside_tree():
		return
	var driver_team := _get_driver_team()
	if driver_team.is_empty():
		return
	if get_world_3d() == null:
		return

	_shape_cast.force_shapecast_update()
	var detected_tiles: Array = []
	for collision_index in range(_shape_cast.get_collision_count()):
		var tile := Farmlandmanager.resolve_shapecast_tile(_shape_cast, collision_index)
		if tile != null:
			detected_tiles.append(tile)
	_harvest_detected_tiles(detected_tiles, driver_team)


func _harvest_detected_tiles(detected_tiles: Array, driver_team: String) -> int:
	if _vehicle == null or driver_team.is_empty():
		return 0
	var harvested_count := 0
	var seen_tiles: Dictionary = {}
	for tile_value: Variant in detected_tiles:
		var tile := tile_value as FarmTile
		if tile == null or not tile.can_harvest:
			continue
		var tile_id := tile.get_instance_id()
		if seen_tiles.has(tile_id):
			continue
		seen_tiles[tile_id] = true
		if tile.harvest(global_position, {
			"absorption_type": "farm_vehicle_crop",
			"owner_peer_id": _vehicle.driver_peer_id,
			"team": driver_team,
			"vehicle_id": _vehicle.get_vehicle_id(),
		}):
			harvested_count += 1
	return harvested_count


func _cache_nodes() -> void:
	# The authored scene has a child named HarvestReel under the module root.
	# Resolve the pivot from that child first so another future node with the
	# same name elsewhere in the module cannot be selected accidentally.
	_visual_root = find_child(VISUAL_NODE_NAME, true, false) as Node3D
	if _visual_root != null:
		_reel_pivot = _visual_root.find_child(PIVOT_NODE_NAME, true, false) as Node3D
	if _reel_pivot == null:
		_reel_pivot = find_child(PIVOT_NODE_NAME, true, false) as Node3D
	_shape_cast = find_child(SHAPE_CAST_NODE_NAME, true, false) as ShapeCast3D
	if _visual_root == null:
		push_error("HarvestReel: missing recursive child %s." % VISUAL_NODE_NAME)
	if _reel_pivot == null:
		push_error("HarvestReel: missing recursive child %s." % PIVOT_NODE_NAME)
	if _shape_cast == null:
		push_error("HarvestReel: missing recursive child %s." % SHAPE_CAST_NODE_NAME)


func _configure_collision() -> void:
	collision_layer = BODY_COLLISION_LAYER
	collision_mask = BODY_COLLISION_MASK


func _configure_shape_cast() -> void:
	if _shape_cast == null:
		return
	_shape_cast.collision_mask = FARM_TILE_COLLISION_MASK
	_shape_cast.collide_with_bodies = true
	_shape_cast.collide_with_areas = false
	_shape_cast.exclude_parent = true
	_shape_cast.max_results = 64
	_shape_cast.enabled = true


func _capture_pivot_rotation() -> void:
	if _reel_pivot == null:
		return
	_pivot_base_rotation_x = _reel_pivot.rotation.x
	_rotation_phase = 0.0


func _configure_parent_collision_exception() -> void:
	if _vehicle == null:
		return
	# Both calls keep the relationship explicit for moving CharacterBody3D
	# parents and the attached StaticBody3D child.
	add_collision_exception_with(_vehicle)
	_vehicle.add_collision_exception_with(self)


func _find_parent_vehicle() -> FarmBaseVehicle:
	var current := get_parent()
	while current != null:
		if current is FarmBaseVehicle:
			return current as FarmBaseVehicle
		current = current.get_parent()
	return null


func _is_vehicle_moving() -> bool:
	return _vehicle != null and absf(_vehicle.current_speed) > MOVEMENT_THRESHOLD


func _get_driver_team() -> String:
	if _vehicle == null or _vehicle.driver_peer_id <= 0:
		return ""
	var state_value: Variant = GameAuthority.player_states.get(_vehicle.driver_peer_id, {})
	if not state_value is Dictionary:
		return ""
	var team := str((state_value as Dictionary).get("team", ""))
	return team if team in ["red", "blue"] else ""
