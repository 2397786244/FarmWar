extends VehicleBase
class_name CombineCar

## CombineCar's header is part of the imported vehicle visual rather than a
## separate HarvestReel attachment.  Keep the same movement threshold and
## reel speed as HarvestReel so both harvesting vehicles behave consistently.
const MOVEMENT_THRESHOLD := 0.1
const HEADER_REEL_ROTATION_SPEED_RADIANS := 1.5
const FARM_TILE_COLLISION_MASK := GameAuthority.COLLISION_LAYER_FARM_TILE
const HEADER_NODE_NAME := "HeaderReel"
const MESH_NODE_NAME := "Mesh"
const SHAPE_CAST_NODE_NAME := "ShapeCast3D"
const HEADLIGHT_MOUNT_NODE_NAME := "HeadLightPos"
const HEADLIGHT_LIGHT_NODE_NAME := "Light3D"
const PLAYER_INTERACTION_RANGE := 8.0

var _combine_mesh: Node3D
var _header_reel: Node3D
var _harvest_shape_cast: ShapeCast3D
var _headlight_light: Light3D
var _header_reel_base_rotation_x := 0.0
var _header_reel_rotation_phase := 0.0
var headlights_on := false


func _ready() -> void:
	super()
	_cache_combine_nodes()
	_configure_harvest_shape_cast()
	_capture_header_reel_rotation()
	_cache_headlight()
	_set_headlights(false)


func _process(delta: float) -> void:
	if _header_reel == null or not _is_vehicle_moving():
		return
	_header_reel_rotation_phase = wrapf(
		_header_reel_rotation_phase
			+ HEADER_REEL_ROTATION_SPEED_RADIANS * maxf(delta, 0.0),
		0.0,
		TAU
	)
	# Only overwrite X.  The authored Y/Z orientation of the imported header
	# remains unchanged so the reel rotates around its own model pivot.
	var next_rotation := _header_reel.rotation
	next_rotation.x = _header_reel_base_rotation_x + _header_reel_rotation_phase
	_header_reel.rotation = next_rotation


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	# FarmTile mutation is authoritative.  A proxy may still animate the
	# vehicle/header from snapshots, but it must never harvest locally.
	if not _is_vehicle_moving() or _harvest_shape_cast == null:
		return
	if not GameAuthority.is_local_authority() and not GameAuthority.is_server_authority():
		return
	if driver_peer_id <= 0 or not is_inside_tree() or get_world_3d() == null:
		return
	var driver_team := _get_driver_team()
	if driver_team.is_empty():
		return

	_harvest_shape_cast.force_shapecast_update()
	var detected_tiles: Array = []
	for collision_index in range(_harvest_shape_cast.get_collision_count()):
		var tile := Farmlandmanager.resolve_shapecast_tile(_harvest_shape_cast, collision_index)
		if tile != null:
			detected_tiles.append(tile)
	_harvest_detected_tiles(detected_tiles, driver_team)


func get_network_state() -> Dictionary:
	var state := super()
	state["headlights_on"] = headlights_on
	return state


func apply_network_state(state: Dictionary) -> void:
	super(state)
	_set_headlights(bool(state.get("headlights_on", headlights_on)))


func toggle_headlights() -> void:
	if GameAuthority.should_send_network_requests():
		return
	_set_headlights(not headlights_on)


func get_player_interaction_range() -> float:
	# The header and rear body extend well beyond the vehicle root. Keep the
	# generic player/server interaction checks usable from either end of this
	# large vehicle while retaining their facing and occlusion checks.
	return PLAYER_INTERACTION_RANGE


func _cache_combine_nodes() -> void:
	_combine_mesh = get_node_or_null(MESH_NODE_NAME) as Node3D
	if _combine_mesh == null:
		push_error("CombineCar: missing direct Mesh visual node.")
		return
	_header_reel = _combine_mesh.find_child(HEADER_NODE_NAME, true, false) as Node3D
	if _header_reel == null:
		push_error("CombineCar: Mesh is missing recursive child %s." % HEADER_NODE_NAME)
	_harvest_shape_cast = get_node_or_null(SHAPE_CAST_NODE_NAME) as ShapeCast3D
	if _harvest_shape_cast == null:
		push_error("CombineCar: missing root ShapeCast3D harvest area.")


func _configure_harvest_shape_cast() -> void:
	if _harvest_shape_cast == null:
		return
	_harvest_shape_cast.collision_mask = FARM_TILE_COLLISION_MASK
	_harvest_shape_cast.collide_with_bodies = true
	_harvest_shape_cast.collide_with_areas = false
	_harvest_shape_cast.exclude_parent = true
	_harvest_shape_cast.max_results = 64
	_harvest_shape_cast.target_position = Vector3.ZERO
	_harvest_shape_cast.enabled = true


func _cache_headlight() -> void:
	var mount := find_child(HEADLIGHT_MOUNT_NODE_NAME, true, false) as Node3D
	if mount == null:
		push_error("CombineCar: missing recursive %s marker." % HEADLIGHT_MOUNT_NODE_NAME)
		return
	_headlight_light = mount.find_child(HEADLIGHT_LIGHT_NODE_NAME, true, false) as Light3D
	if _headlight_light == null:
		push_error("CombineCar: missing %s below %s." % [HEADLIGHT_LIGHT_NODE_NAME, HEADLIGHT_MOUNT_NODE_NAME])


func _set_headlights(enabled: bool) -> void:
	headlights_on = enabled
	if is_instance_valid(_headlight_light):
		# CombineCar has no authored Glow mesh. The Light3D itself is the complete
		# headlight visual and is the only node affected by the switch.
		_headlight_light.visible = enabled


func _capture_header_reel_rotation() -> void:
	if _header_reel == null:
		return
	_header_reel_base_rotation_x = _header_reel.rotation.x
	_header_reel_rotation_phase = 0.0


func _is_vehicle_moving() -> bool:
	return absf(current_speed) > MOVEMENT_THRESHOLD


func _get_driver_team() -> String:
	if driver_peer_id <= 0:
		return ""
	var state_value: Variant = GameAuthority.player_states.get(driver_peer_id, {})
	if not state_value is Dictionary:
		return ""
	var team := str((state_value as Dictionary).get("team", ""))
	return team if team in ["red", "blue"] else ""


func _harvest_detected_tiles(detected_tiles: Array, driver_team: String) -> int:
	if driver_team.is_empty() or driver_peer_id <= 0:
		return 0
	var harvested_count := 0
	var seen_tiles: Dictionary = {}
	var absorb_source := _harvest_shape_cast.global_position if _harvest_shape_cast != null else global_position
	for tile_value: Variant in detected_tiles:
		var tile := tile_value as FarmTile
		if tile == null or not tile.can_harvest:
			continue
		var tile_id := tile.get_instance_id()
		if seen_tiles.has(tile_id):
			continue
		seen_tiles[tile_id] = true
		if tile.harvest(absorb_source, {
			"absorption_type": "farm_vehicle_crop",
			"owner_peer_id": driver_peer_id,
			"team": driver_team,
			"vehicle_id": get_vehicle_id(),
		}):
			harvested_count += 1
	return harvested_count
