extends Node3D
class_name PlacementPreviewController

const PlacementQueryScript = preload("res://src/placement_query.gd")
const VEHICLE_PREVIEW_CACHE_MSEC := 100

const PREVIEW_GREEN := Color(0.15, 1.0, 0.30, 0.42)
const PREVIEW_RED := Color(1.0, 0.12, 0.12, 0.42)
const PREVIEW_GRAY := Color(0.58, 0.60, 0.64, 0.42)
const PREVIEW_GREEN_EMISSION := Color(0.03, 0.12, 0.04, 1.0)
const PREVIEW_RED_EMISSION := Color(0.15, 0.01, 0.01, 1.0)
const PREVIEW_GRAY_EMISSION := Color(0.08, 0.09, 0.12, 1.0)
const PREVIEW_TARGET_MASK := (
	1 | 2 | 8 | 64 | 128 | 4096 | 8192 | 16384 | 32768
)
const PREVIEW_BLOCKING_MASK := (
	2 | 8 | 16 | 128 | 4096 | 8192 | 32768
	| 16384
)
const SUPPORT_OVERLAP_BLOCKING_MASK := (
	PREVIEW_BLOCKING_MASK & ~(16 | 128 | 4096)
)
const FARM_TILE_TOOL_IDS := {
	"auto_shooter": "AutoShooter",
	"shield_door": "ShieldDoor",
	"wheat_sentry": "WheatSentry",
	"plant_protector": "PlantProtector",
	"brick": "Brick",
	"farm_runner": "FarmRunner",
}
const VEHICLE_TOOL_IDS := {
	"survey_rider": "res://character/weapons/SurveyRider.tscn",
	"field_kitchen": "res://character/weapons/KitchenCar.tscn",
}
const LIVESTOCK_TOOL_SCENES := {
	"animal_chicken": "res://items/Chicken.tscn",
	"animal_pig": "res://items/Pig.tscn",
	"animal_angus_cow": "res://items/AngusCow.tscn",
}
const WALL_TOOL_SCENES := {
	"tall_brick": "res://character/weapons/TallBrick.tscn",
	"tall_log_wall": "res://character/weapons/TallLogWall.tscn",
	"tall_mesh_wall": "res://character/weapons/TallMeshWall.tscn",
	"wire_mesh_gate": "res://character/weapons/WireMeshGate.tscn",
}

var player: Node3D
var preview_root: Node3D
var preview_model: Node3D
var preview_material_green: StandardMaterial3D
var preview_material_red: StandardMaterial3D
var preview_material_gray: StandardMaterial3D
var current_tool_id := ""
var current_mode := ""
var current_scene_path := ""
var current_definition: Dictionary = {}
var current_item: Dictionary = {}
var source_collision_shape: Shape3D
var source_collision_transform := Transform3D.IDENTITY
var source_placement_clearance := PlacementQueryScript.DEFAULT_CLEARANCE
var preview_valid := false
var preview_cooldown_active := false
var wall_snap_active := false
var wall_snap_position := Vector3.ZERO
var wall_snap_source_id := ""
var wall_snap_source_rid := RID()
var _vehicle_preview_cache_key := ""
var _vehicle_preview_cache_until_msec := 0
var _vehicle_preview_cache_result: Dictionary = {}


func setup(next_player: Node3D) -> void:
	player = next_player
	process_mode = Node.PROCESS_MODE_DISABLED
	preview_root = Node3D.new()
	preview_root.name = "LocalPlacementPreview"
	preview_root.top_level = true
	preview_root.visible = false
	add_child(preview_root)
	preview_material_green = _make_preview_material(PREVIEW_GREEN, PREVIEW_GREEN_EMISSION)
	preview_material_red = _make_preview_material(PREVIEW_RED, PREVIEW_RED_EMISSION)
	preview_material_gray = _make_preview_material(PREVIEW_GRAY, PREVIEW_GRAY_EMISSION)


func set_selection(definition: Dictionary, item: Dictionary = {}) -> void:
	clear_selection()
	if player == null or not is_instance_valid(player):
		return
	if bool(player.get("is_remote_proxy")):
		return
	current_definition = definition.duplicate(true)
	current_item = item.duplicate(true)
	current_tool_id = str(definition.get("id", item.get("tool_id", "")))

	var placement := _resolve_placement_definition(definition, item)
	if placement.is_empty() or not bool(placement.get("enabled", false)):
		return
	current_mode = str(placement.get("mode", ""))
	current_scene_path = str(placement.get("scene_path", ""))
	if current_scene_path.is_empty():
		return
	_build_preview_model(current_scene_path)


func clear_selection() -> void:
	current_tool_id = ""
	current_mode = ""
	current_scene_path = ""
	current_definition.clear()
	current_item.clear()
	source_collision_shape = null
	source_collision_transform = Transform3D.IDENTITY
	source_placement_clearance = PlacementQueryScript.DEFAULT_CLEARANCE
	preview_valid = false
	preview_cooldown_active = false
	wall_snap_active = false
	wall_snap_position = Vector3.ZERO
	wall_snap_source_id = ""
	wall_snap_source_rid = RID()
	_vehicle_preview_cache_key = ""
	_vehicle_preview_cache_until_msec = 0
	_vehicle_preview_cache_result.clear()
	if is_instance_valid(preview_root):
		preview_root.visible = false
	if is_instance_valid(preview_model):
		preview_model.queue_free()
		preview_model = null


func update_preview(allowed_by_player_state := true) -> void:
	if not allowed_by_player_state or current_mode.is_empty() or not is_instance_valid(preview_model):
		if is_instance_valid(preview_root):
			preview_root.visible = false
		return
	if player == null or not is_instance_valid(player) or bool(player.get("is_remote_proxy")):
		preview_root.visible = false
		return
	if not player.is_inside_tree() or player.get_world_3d() == null:
		preview_root.visible = false
		return

	# Calculate this frame's snap before the click path consumes the cached result.
	var request_value: Variant = player.call("_make_tool_request", false)
	var request: Dictionary = request_value as Dictionary if request_value is Dictionary else {}
	var yaw := float(player.rotation.y)
	var cooldown_remaining := 0.0
	if player.has_method("get_placement_preview_cooldown_remaining"):
		cooldown_remaining = maxf(
			0.0,
			float(player.call("get_placement_preview_cooldown_remaining"))
		)
	var cooldown_active := cooldown_remaining > 0.0001
	if current_mode == "farm_tile":
		_update_farm_tile_preview(request, yaw, cooldown_active)
	elif current_mode == "surface":
		_update_surface_preview(request, yaw, cooldown_active)
	else:
		_update_free_preview(request, yaw, cooldown_active)


func _resolve_placement_definition(definition: Dictionary, item: Dictionary) -> Dictionary:
	if str(item.get("kind", "")) == "cargo_crate":
		return {}
	var tool_id := str(definition.get("id", item.get("tool_id", "")))
	if tool_id.is_empty():
		return {}
	if tool_id == "auto_cooker":
		return {}
	var configured_value: Variant = definition.get("placement_preview", null)
	if configured_value is Dictionary:
		var configured := configured_value as Dictionary
		if not bool(configured.get("enabled", false)):
			return {}
		var configured_scene := str(configured.get("scene_path", definition.get("path", "")))
		return {
			"enabled": true,
			"mode": str(configured.get("mode", "free")),
			"scene_path": configured_scene,
			"allow_support_object_overlap": bool(
				configured.get(
					"allow_support_object_overlap",
					definition.get("allow_support_object_overlap", false)
				)
			),
		}
	if FARM_TILE_TOOL_IDS.has(tool_id):
		return {
			"enabled": true,
			"mode": "farm_tile",
			"scene_path": "res://character/weapons/%s.tscn" % str(FARM_TILE_TOOL_IDS[tool_id]),
		}
	if VEHICLE_TOOL_IDS.has(tool_id):
		return {
			"enabled": true,
			"mode": "vehicle",
			"scene_path": str(VEHICLE_TOOL_IDS[tool_id]),
		}
	if LIVESTOCK_TOOL_SCENES.has(tool_id):
		return {
			"enabled": true,
			"mode": "livestock",
			"scene_path": str(LIVESTOCK_TOOL_SCENES[tool_id]),
		}
	if bool(definition.get("free_placement", false)):
		return {
			"enabled": true,
			"mode": "free",
			"scene_path": str(definition.get("path", "")),
			"allow_support_object_overlap": bool(definition.get("allow_support_object_overlap", false)),
		}
	return {}


func _build_preview_model(scene_path: String) -> void:
	source_collision_shape = null
	source_collision_transform = Transform3D.IDENTITY
	source_placement_clearance = PlacementQueryScript.DEFAULT_CLEARANCE
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return
	var source := packed.instantiate() as Node3D
	if source == null:
		return
	var footprint := PlacementQueryScript.placement_footprint_for_node(source)
	if not footprint.is_empty():
		source_collision_shape = (footprint["shape"] as Shape3D).duplicate(true) as Shape3D
		source_collision_transform = footprint["transform"] as Transform3D
		source_placement_clearance = float(footprint.get("clearance", PlacementQueryScript.DEFAULT_CLEARANCE))
	else:
		var source_collision := _find_collision_shape(source)
		if source_collision != null and source_collision.shape != null:
			source_collision_shape = source_collision.shape.duplicate(true) as Shape3D
			source_collision_transform = source_collision.transform
	var clone := source.duplicate() as Node3D
	source.free()
	if clone == null:
		return
	preview_model = clone
	preview_model.name = "PreviewModel"
	_sanitize_preview_tree(preview_model)
	preview_root.add_child(preview_model)
	preview_root.visible = false


func _find_collision_shape(node: Node) -> CollisionShape3D:
	var direct := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if direct != null and direct.shape != null:
		return direct
	var vehicle_shape := node.get_node_or_null("VehicleShape") as CollisionShape3D
	if vehicle_shape != null and vehicle_shape.shape != null:
		return vehicle_shape
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			return child as CollisionShape3D
		var nested := _find_collision_shape(child)
		if nested != null:
			return nested
	return null


func _sanitize_preview_tree(node: Node) -> void:
	if node.has_method("set_script"):
		node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	node.set_process_unhandled_key_input(false)
	for group_value: StringName in node.get_groups():
		node.remove_from_group(group_value)
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is RigidBody3D:
		var rigid_body := node as RigidBody3D
		rigid_body.freeze = true
		rigid_body.sleeping = true
	if node is Area3D:
		var area := node as Area3D
		area.monitoring = false
		area.monitorable = false
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	if node is RayCast3D:
		(node as RayCast3D).enabled = false
	if node is ShapeCast3D:
		(node as ShapeCast3D).enabled = false
	if node is NavigationAgent3D:
		(node as NavigationAgent3D).avoidance_enabled = false
	if node is NavigationObstacle3D:
		var navigation_obstacle := node as NavigationObstacle3D
		navigation_obstacle.affect_navigation_mesh = false
		navigation_obstacle.avoidance_enabled = false
	if node is Timer:
		(node as Timer).stop()
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is CPUParticles3D:
		(node as CPUParticles3D).emitting = false
	if node is AnimationPlayer:
		(node as AnimationPlayer).stop()
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is Light3D:
		(node as Light3D).visible = false
	if node is Label3D:
		(node as Label3D).visible = false
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		(node as GeometryInstance3D).material_override = preview_material_green
	for child in node.get_children():
		_sanitize_preview_tree(child)


func _update_farm_tile_preview(request: Dictionary, yaw: float, cooldown_active := false) -> void:
	var tile := _resolve_target_farm_tile()
	if tile == null:
		_set_preview_transform(_resolve_fallback_target(request), yaw, false, cooldown_active)
		return
	var owner_value: Variant = tile.get("land_owner")
	var tile_owner := "" if owner_value == null else str(owner_value)
	var player_team := str(player.get("team"))
	var seed_value: Variant = tile.get("seed_record")
	var tool_value: Variant = tile.get("tool_child")
	var occupied := (seed_value != null and not str(seed_value).is_empty()) \
		or is_instance_valid(tool_value)
	var valid := not occupied and (tile_owner.is_empty() or tile_owner == player_team)
	if valid:
		var placement := PlacementQueryScript.resolve_free_placement(
			player.get_world_3d(),
			tile.global_position,
			player.global_position,
			yaw,
			source_collision_shape,
			source_collision_transform,
			_placement_blocking_mask(),
			_placement_exceptions(), 1, 5.0, source_placement_clearance, 20.0, 48.0
		)
		valid = bool(placement.get("ok", false))
	_set_preview_transform(tile.global_position + Vector3.UP * 0.1, yaw, valid, cooldown_active)


func _update_surface_preview(request: Dictionary, yaw: float, cooldown_active := false) -> void:
	var surface_target := _resolve_surface_target(request)
	var surface_position := surface_target.get(
		"position", _resolve_fallback_target(request)
	) as Vector3
	var surface_normal := surface_target.get("normal", Vector3.UP) as Vector3
	var support := PlacementQueryScript.tabletop_support_for_collider(surface_target.get("collider", null))
	var tabletop_placeable := bool(current_definition.get("tabletop_placeable", false))
	var result: Dictionary
	if tabletop_placeable and support != null:
		result = PlacementQueryScript.resolve_tabletop_surface_placement(
			player.get_world_3d(), support, surface_position, player.global_position, yaw,
			source_collision_shape, source_collision_transform, _placement_blocking_mask(),
			_placement_exceptions(), surface_normal, 5.0, source_placement_clearance
		)
	else:
		result = PlacementQueryScript.resolve_surface_placement(
			player.get_world_3d(), surface_position, player.global_position, yaw,
			source_collision_shape, source_collision_transform, _placement_blocking_mask(),
			_placement_exceptions(), surface_normal, 5.0, source_placement_clearance
		)
	var position := result.get("position", surface_position) as Vector3
	_set_preview_transform(position, yaw, bool(result.get("ok", false)), cooldown_active)


func _update_free_preview(request: Dictionary, yaw: float, cooldown_active := false) -> void:
	var fallback_distance := 3.0 if current_mode == "livestock" else 4.0
	var requested_position := _resolve_fallback_target(request, fallback_distance)
	if current_mode == "vehicle":
		var vehicle_result := _resolve_vehicle_preview(requested_position, yaw)
		var vehicle_preview_position := requested_position
		if bool(vehicle_result.get("ok", false)):
			vehicle_preview_position = _vector3_from_value(
				vehicle_result.get(
					"drop_start_position",
					vehicle_result.get("position", requested_position)
				)
			)
		_set_preview_transform(
			vehicle_preview_position,
			yaw,
			bool(vehicle_result.get("ok", false)),
			cooldown_active
		)
		return
	var placement_position := requested_position
	var placement_exceptions := _placement_exceptions()
	_reset_wall_snap()
	if WALL_TOOL_SCENES.has(current_tool_id):
		var wall_snap := _resolve_wall_snap(requested_position, yaw)
		if bool(wall_snap.get("active", false)):
			placement_position = wall_snap.get("position", requested_position) as Vector3
			wall_snap_source_id = str(wall_snap.get("source_id", ""))
			var source_rid_value: Variant = wall_snap.get("source_rid", RID())
			if source_rid_value is RID:
				wall_snap_source_rid = source_rid_value as RID
				if wall_snap_source_rid.is_valid():
					placement_exceptions.append(wall_snap_source_rid)
			wall_snap_active = true
			wall_snap_position = placement_position
	var result := PlacementQueryScript.resolve_free_placement(
		player.get_world_3d(),
		placement_position,
		player.global_position,
		yaw,
		source_collision_shape,
		source_collision_transform,
		_placement_blocking_mask(),
		placement_exceptions, 1, 5.0, source_placement_clearance, 20.0, 48.0
	)
	var position := result.get("position", placement_position) as Vector3
	_set_preview_transform(position, yaw, bool(result.get("ok", false)), cooldown_active)
	if wall_snap_active:
		wall_snap_position = position


func _resolve_vehicle_preview(requested_position: Vector3, yaw: float) -> Dictionary:
	var exceptions := _placement_exceptions()
	var key_parts: Array[String] = [
		current_scene_path,
		"%.1f" % snappedf(requested_position.x, 0.1),
		"%.1f" % snappedf(requested_position.y, 0.1),
		"%.1f" % snappedf(requested_position.z, 0.1),
		"%.2f" % snappedf(yaw, 0.01),
	]
	for rid_value: Variant in exceptions:
		key_parts.append(str(rid_value))
	var cache_key := "|".join(key_parts)
	var now_msec := Time.get_ticks_msec()
	if cache_key == _vehicle_preview_cache_key and now_msec < _vehicle_preview_cache_until_msec:
		return _vehicle_preview_cache_result.duplicate(true)
	var result := PlacementQueryScript.resolve_vehicle_spawn(
		player.get_world_3d(),
		requested_position,
		current_scene_path,
		{
			"yaw": yaw,
			"exclude_rids": exceptions,
			"max_search_radius": 12.0,
			"search_step": 1.0,
			"max_slope_degrees": 5.0,
			"clearance": 0.15,
			"max_candidates": 512,
		}
	)
	_vehicle_preview_cache_key = cache_key
	_vehicle_preview_cache_until_msec = now_msec + VEHICLE_PREVIEW_CACHE_MSEC
	_vehicle_preview_cache_result = result.duplicate(true)
	return result


func _placement_blocking_mask() -> int:
	return SUPPORT_OVERLAP_BLOCKING_MASK if bool(
		current_definition.get("allow_support_object_overlap", false)
	) else PREVIEW_BLOCKING_MASK


func _resolve_surface_target(request: Dictionary) -> Dictionary:
	var origin := request.get("origin", player.global_position) as Vector3
	var direction := request.get("direction", -player.global_transform.basis.z) as Vector3
	if direction.length_squared() <= 0.001:
		direction = -player.global_transform.basis.z
	direction = direction.normalized()
	var world := player.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 12.0)
		query.collision_mask = PREVIEW_TARGET_MASK
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.exclude = _placement_exceptions()
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.get("position") is Vector3:
			var normal_value: Variant = hit.get("normal", Vector3.UP)
			return {
				"position": hit.get("position") as Vector3,
				"normal": normal_value as Vector3 if normal_value is Vector3 else Vector3.UP,
				"collider": hit.get("collider", null),
			}
	var fallback := _resolve_fallback_target(request)
	return {"position": fallback, "normal": Vector3.UP}


func _reset_wall_snap() -> void:
	wall_snap_active = false
	wall_snap_position = Vector3.ZERO
	wall_snap_source_id = ""
	wall_snap_source_rid = RID()


func has_active_wall_snap() -> bool:
	return wall_snap_active and WALL_TOOL_SCENES.has(current_tool_id)


func get_wall_snap_position() -> Vector3:
	return wall_snap_position


func _resolve_wall_snap(requested_position: Vector3, yaw: float) -> Dictionary:
	var family := PlacementQueryScript.wall_family_for_tool(current_tool_id)
	if family.is_empty():
		return {"active": false, "position": requested_position}
	var current_half_length := PlacementQueryScript.wall_half_length_for_shape(
		source_collision_shape,
		source_collision_transform
	)
	var candidates := _collect_wall_snap_candidates(family)
	var result := PlacementQueryScript.resolve_wall_endpoint_snap(
		requested_position,
		yaw,
		current_half_length,
		candidates,
		PlacementQueryScript.WALL_SNAP_DISTANCE
	)
	if bool(result.get("active", false)):
		var source_id := str(result.get("source_id", ""))
		for candidate_value: Variant in candidates:
			if candidate_value is Dictionary and str((candidate_value as Dictionary).get("source_id", "")) == source_id:
				result["source_rid"] = (candidate_value as Dictionary).get("source_rid", RID())
				break
	return result


func _collect_wall_snap_candidates(family: String) -> Array:
	var candidates: Array = []
	var seen_ids := {}
	var authority := get_node_or_null("/root/GameAuthority")
	if authority != null:
		var states_value: Variant = authority.get("placed_tool_states")
		if states_value is Dictionary:
			for raw_id: Variant in (states_value as Dictionary).keys():
				var state_value: Variant = (states_value as Dictionary).get(raw_id, {})
				if not state_value is Dictionary:
					continue
				var state := state_value as Dictionary
				var source_id := str(raw_id)
				var tool_id := _wall_tool_id_from_state(source_id, state)
				if PlacementQueryScript.wall_family_for_tool(tool_id) != family:
					continue
				var node := _node_for_placement_state(state)
				var position := _state_position_or_node(state, node)
				var candidate_yaw := _state_yaw_or_node(state, node)
				var half_length := float(state.get("wall_half_length", 0.0))
				if half_length <= 0.0:
					half_length = PlacementQueryScript.wall_half_length_for_node(node)
				if half_length <= 0.0:
					half_length = _wall_half_length_from_scene(str(state.get("scene_path", "")))
				if half_length <= 0.0:
					continue
				candidates.append(_make_wall_candidate(source_id, position, candidate_yaw, half_length, node))
				seen_ids[source_id] = true
	var replicator := get_node_or_null("/root/MultiplayerWorldReplicator")
	if replicator != null:
		var visuals_value: Variant = replicator.get("placed_tool_visuals")
		if visuals_value is Dictionary:
			for raw_id: Variant in (visuals_value as Dictionary).keys():
				var source_id := str(raw_id)
				if seen_ids.has(source_id):
					continue
				var node := (visuals_value as Dictionary).get(raw_id, null) as Node3D
				if not is_instance_valid(node):
					continue
				var tool_id := _wall_tool_id_from_node(source_id, node)
				if PlacementQueryScript.wall_family_for_tool(tool_id) != family:
					continue
				var half_length := PlacementQueryScript.wall_half_length_for_node(node)
				if half_length <= 0.0:
					continue
				candidates.append(_make_wall_candidate(source_id, node.global_position, node.rotation.y, half_length, node))
	return candidates


func _make_wall_candidate(
	source_id: String,
	position: Vector3,
	yaw: float,
	half_length: float,
	node: Node
) -> Dictionary:
	var candidate := {
		"source_id": source_id,
		"position": position,
		"yaw": yaw,
		"half_length": half_length,
	}
	if node is CollisionObject3D:
		candidate["source_rid"] = (node as CollisionObject3D).get_rid()
	return candidate


func _wall_tool_id_from_state(source_id: String, state: Dictionary) -> String:
	var tool_id := str(state.get("tool_name", state.get("tool_id", source_id)))
	if not PlacementQueryScript.wall_family_for_tool(tool_id).is_empty():
		return tool_id.to_lower()
	return PlacementQueryScript.wall_tool_id_for_scene(str(state.get("scene_path", "")))


func _wall_tool_id_from_node(source_id: String, node: Node3D) -> String:
	if node != null and is_instance_valid(node):
		var scene_tool_id := PlacementQueryScript.wall_tool_id_for_scene(str(node.scene_file_path))
		if not scene_tool_id.is_empty():
			return scene_tool_id
		var node_name := node.name.to_lower().replace(" ", "_")
		if node_name.begins_with("tallbrick"):
			return "tall_brick"
		if node_name.begins_with("talllogwall"):
			return "tall_log_wall"
		if node_name.begins_with("tallmeshwall"):
			return "tall_mesh_wall"
		if node_name.begins_with("wiremeshgate"):
			return "wire_mesh_gate"
	return PlacementQueryScript.wall_tool_id_for_scene(source_id)


func _node_for_placement_state(state: Dictionary) -> Node3D:
	var path := str(state.get("path", state.get("device_id", "")))
	if not path.is_empty():
		var node := get_tree().root.get_node_or_null(NodePath(path)) as Node3D
		if node != null and is_instance_valid(node):
			return node
	return null


func _state_position_or_node(state: Dictionary, node: Node3D) -> Vector3:
	if node != null and is_instance_valid(node):
		return node.global_position
	var value: Variant = state.get("position", Vector3.ZERO)
	return value as Vector3 if value is Vector3 else Vector3.ZERO


func _state_yaw_or_node(state: Dictionary, node: Node3D) -> float:
	if node != null and is_instance_valid(node):
		return node.rotation.y
	return float(state.get("yaw", 0.0))


func _wall_half_length_from_scene(scene_path: String) -> float:
	if scene_path.is_empty():
		return 0.0
	var packed := load(scene_path) as PackedScene
	if packed == null:
		return 0.0
	var source := packed.instantiate() as Node3D
	if source == null:
		return 0.0
	var half_length := PlacementQueryScript.wall_half_length_for_node(source)
	source.free()
	return half_length


func _resolve_target_farm_tile() -> Node3D:
	var cast := player.find_child("LookAtTarget", true, false) as RayCast3D
	if cast == null:
		return null
	cast.force_raycast_update()
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null or not manager.has_method("resolve_raycast_tile"):
		return null
	return manager.call("resolve_raycast_tile", cast) as Node3D


func _resolve_fallback_target(request: Dictionary, fallback_distance := 4.0) -> Vector3:
	var origin := request.get("origin", player.global_position) as Vector3
	var direction := request.get("direction", -player.global_transform.basis.z) as Vector3
	if direction.length_squared() <= 0.001:
		direction = -player.global_transform.basis.z
	direction = direction.normalized()
	var target_value: Variant = request.get("target_position", Vector3.ZERO)
	if target_value is Vector3 and (target_value as Vector3) != Vector3.ZERO:
		var target_position := target_value as Vector3
		if target_position.distance_to(player.global_position) <= 10.0:
			return target_position
		return player.global_position + direction * fallback_distance
	var world := player.get_world_3d()
	if world != null:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * 12.0)
		query.collision_mask = PREVIEW_TARGET_MASK
		query.collide_with_bodies = true
		query.collide_with_areas = true
		query.exclude = _placement_exceptions()
		var hit := world.direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.has("position"):
			return hit.get("position") as Vector3
	return player.global_position + direction * 4.0


func _placement_exceptions() -> Array:
	var result: Array = []
	if player is CollisionObject3D:
		result.append((player as CollisionObject3D).get_rid())
	var authority := get_node_or_null("/root/GameAuthority")
	var authority_value: Variant = authority.get("player_physics_nodes") if authority != null else null
	if authority_value is Dictionary:
		var physics_node: Variant = (authority_value as Dictionary).get(
			int(player.get("authority_peer_id")),
			null
		)
		if physics_node is CollisionObject3D:
			result.append((physics_node as CollisionObject3D).get_rid())
	return result


func _vector3_from_value(value: Variant) -> Vector3:
	return value as Vector3 if value is Vector3 else Vector3.ZERO


func _set_preview_transform(
	position: Vector3,
	yaw: float,
	valid: bool,
	cooldown_active := false
) -> void:
	if not is_instance_valid(preview_root):
		return
	preview_valid = valid
	preview_cooldown_active = cooldown_active
	preview_root.global_transform = Transform3D(Basis(Vector3.UP, yaw), position)
	preview_root.visible = true
	var material := preview_material_gray if cooldown_active else preview_material_green if valid else preview_material_red
	_apply_preview_material(preview_model, material)


func _apply_preview_material(node: Node, material: Material) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = material
	for child in node.get_children():
		_apply_preview_material(child, material)


func _make_preview_material(color: Color, emission_color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = emission_color
	material.emission_energy_multiplier = 0.35
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
