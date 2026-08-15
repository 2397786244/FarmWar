extends Node3D
class_name DynamicNavigationChunkGrid

## 地图级动态导航分区管理器。
##
## - 地图被划分为固定大小的 NavigationRegion3D 区块；
## - 运行时障碍只会使相交区块 dirty；
## - 连续若干个物理帧内的变更合并为一次异步 bake；
## - 服务器/单人权威重建导航，客户端不重建也不接收导航网格；
## - bake 完成后只通知目标位于 dirty 区块内或当前卡住的 AI。

signal navigation_ready
signal navigation_rebuild_started(chunk_ids: Array)
signal navigation_chunks_rebuilt(chunk_ids: Array)
signal navigation_idle

const NAVIGATION_MANAGER_GROUP := "dynamic_navigation_chunk_grids"
const OBSTACLE_GROUP := "ai_demolition_target"
## 普通会阻挡移动、但不允许 Engineer 爆破的对象使用这个分组。
## 例如测试场景的 Crate；它们仍参与局部导航烘焙，但不会进入 Squad
## 的“这里需要爆破”目标候选。
const NAVIGATION_ONLY_OBSTACLE_GROUP := "ai_navigation_obstacle"
const GENERATED_BUILDING_OBSTACLE_META := "dynamic_building_navigation_obstacle"
const SCANNED_BUILDING_META := "dynamic_building_navigation_scanned"
const GROUND_GROUP := "navigation_ground"

@export_category("Grid")
@export var map_origin := Vector2(-128.0, -128.0)
@export var map_size := Vector2(256.0, 256.0)
@export var chunk_size := 64.0
@export var create_regions_on_ready := true

@export_category("Source geometry")
## 该路径用于地图编辑器生成的 TerrainChunk 网格；为空时使用
## navigation_ground group 中的 MeshInstance3D。
@export var ground_source_root_path: NodePath
@export var fallback_ground_y := 0.0
@export var bake_vertical_range := Vector2(-50.0, 150.0)
@export var agent_height := 1.8
@export var agent_radius := 0.4
@export var bake_border_size := 1.0
@export var bake_cell_size := 0.25
@export var bake_cell_height := 0.25

@export_category("Runtime batching")
## 第一次变更后等待的物理帧数。后续变更会合并到同一批，不会重新计时。
@export_range(1, 30, 1) var rebuild_batch_physics_frames := 5
## 防止连续建造/摧毁让 dirty 队列无限期等待。
@export_range(0.05, 2.0, 0.05) var rebuild_max_delay_seconds := 0.25
## 同一时间只执行一个异步 bake，避免服务器瞬时创建多个高峰任务。
@export var one_bake_at_a_time := true

var _regions: Dictionary = {}
var _obstacles: Dictionary = {}
var _ground_meshes: Array[MeshInstance3D] = []
var _dirty_chunks: Dictionary = {}
var _bake_queue: Array[Vector2i] = []
var _bake_active := false
var _bake_chunk := Vector2i.ZERO
var _bake_generation := 0
var _batch_first_frame := -1
var _batch_deadline_msec := 0
var _initial_bakes_remaining := 0
var _initialized := false
var _scan_timer := 0.0
var _building_scan_timer := 0.0
var _last_building_navigation_obstacle_count := -1
var _client_navigation_dropped := false


func _ready() -> void:
	add_to_group(NAVIGATION_MANAGER_GROUP)
	if not _has_navigation_authority():
		## 客户端使用服务器同步后的 AI 位置，不在本地创建或重建动态导航。
		## 保留 physics tick 仅用于处理“场景先加载、随后切换到客户端”
		## 的极少数启动时序；正常客户端不会创建任何 NavigationRegion3D。
		return
	if create_regions_on_ready:
		call_deferred("_initialize_grid")


func _physics_process(delta: float) -> void:
	if not _has_navigation_authority():
		_drop_navigation_for_client()
		return
	if _client_navigation_dropped:
		_client_navigation_dropped = false
		if create_regions_on_ready:
			call_deferred("_initialize_grid")
		return
	if not _initialized:
		return

	_scan_timer -= delta
	_building_scan_timer -= delta
	if _building_scan_timer <= 0.0:
		_building_scan_timer = 1.0
		_ensure_building_navigation_obstacles()
	if _scan_timer <= 0.0:
		_scan_timer = 0.5
		_scan_demolition_obstacles()

	if _dirty_chunks.is_empty() or _bake_active:
		return

	var physics_frame := Engine.get_physics_frames()
	var frame_ready := _batch_first_frame >= 0 \
		and physics_frame >= _batch_first_frame + maxi(1, rebuild_batch_physics_frames)
	var deadline_ready := _batch_deadline_msec > 0 \
		and Time.get_ticks_msec() >= _batch_deadline_msec
	if not frame_ready and not deadline_ready:
		return

	_flush_dirty_chunks_to_bake_queue()
	_start_next_bake()


func _has_navigation_authority() -> bool:
	if is_instance_valid(GameAuthority):
		if GameAuthority.has_method("is_client_proxy") \
				and GameAuthority.is_client_proxy():
			return false
		if GameAuthority.has_method("is_server_authority") \
				and GameAuthority.is_server_authority():
			return true
		if GameAuthority.has_method("is_local_authority") \
				and GameAuthority.is_local_authority():
			return true
	if multiplayer.has_multiplayer_peer():
		return multiplayer.is_server()
	return true


func _initialize_grid() -> void:
	if _initialized or not _has_navigation_authority():
		return
	_client_navigation_dropped = false
	if chunk_size <= 0.0 or map_size.x <= 0.0 or map_size.y <= 0.0:
		push_error("DynamicNavigationChunkGrid: map_size and chunk_size must be positive")
		return

	_collect_ground_meshes()
	_create_regions()
	_ensure_building_navigation_obstacles()
	_scan_demolition_obstacles()
	_initialized = true

	var chunk_ids: Array[Vector2i] = []
	for chunk_id in _regions.keys():
		chunk_ids.append(chunk_id as Vector2i)
		_dirty_chunks[chunk_id] = true
	_initial_bakes_remaining = chunk_ids.size()
	_batch_first_frame = Engine.get_physics_frames()
	_batch_deadline_msec = Time.get_ticks_msec()
	## 初始导航不需要等待五帧，直接放入队列；运行时变更仍按五帧合并。
	_flush_dirty_chunks_to_bake_queue()
	_start_next_bake()


func _drop_navigation_for_client() -> void:
	if _client_navigation_dropped and _regions.is_empty() and not _initialized:
		return
	## 异步 bake 的旧回调通过 generation 检查丢弃，避免客户端在切换时
	## 接收或应用服务器之外生成的导航数据。
	_bake_generation += 1
	_bake_active = false
	_bake_queue.clear()
	_dirty_chunks.clear()
	_initial_bakes_remaining = 0
	_initialized = false
	for region_value in _regions.values():
		var region := region_value as NavigationRegion3D
		if is_instance_valid(region):
			region.queue_free()
	_regions.clear()
	_client_navigation_dropped = true


func _collect_ground_meshes() -> void:
	_ground_meshes.clear()
	var root: Node = null
	if not ground_source_root_path.is_empty():
		root = get_node_or_null(ground_source_root_path)
	if root != null:
		_collect_meshes_recursive(root)
	if _ground_meshes.is_empty():
		for node in get_tree().get_nodes_in_group(GROUND_GROUP):
			if node is MeshInstance3D and not _ground_meshes.has(node):
				_ground_meshes.append(node as MeshInstance3D)


func _collect_meshes_recursive(node: Node) -> void:
	if node is MeshInstance3D and not _ground_meshes.has(node):
		_ground_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes_recursive(child)


func _create_regions() -> void:
	for child in get_children():
		if child is NavigationRegion3D:
			child.queue_free()
	_regions.clear()

	var count_x := maxi(1, ceili(map_size.x / chunk_size))
	var count_z := maxi(1, ceili(map_size.y / chunk_size))
	for z in range(count_z):
		for x in range(count_x):
			var chunk_id := Vector2i(x, z)
			var region := NavigationRegion3D.new()
			region.name = "NavigationRegion_%02d_%02d" % [x, z]
			region.navigation_layers = 1
			region.use_edge_connections = true
			region.set_meta("navigation_chunk_coordinate", chunk_id)
			region.set_meta("navigation_chunk_size", chunk_size)
			add_child(region)
			_regions[chunk_id] = region


func _chunk_bounds(chunk_id: Vector2i, expanded: float = 0.0) -> AABB:
	var minimum := Vector3(
		map_origin.x + float(chunk_id.x) * chunk_size - expanded,
		bake_vertical_range.x,
		map_origin.y + float(chunk_id.y) * chunk_size - expanded
	)
	var width := minf(chunk_size, map_size.x - float(chunk_id.x) * chunk_size)
	var depth := minf(chunk_size, map_size.y - float(chunk_id.y) * chunk_size)
	return AABB(
		minimum,
		Vector3(
			maxf(0.1, width + expanded * 2.0),
			maxf(0.1, bake_vertical_range.y - bake_vertical_range.x),
			maxf(0.1, depth + expanded * 2.0),
		)
	)


func _chunk_ids_for_aabb(bounds: AABB) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var min_x := floori((bounds.position.x - map_origin.x) / chunk_size)
	var min_z := floori((bounds.position.z - map_origin.y) / chunk_size)
	var max_x := floori((bounds.end.x - map_origin.x - 0.001) / chunk_size)
	var max_z := floori((bounds.end.z - map_origin.y - 0.001) / chunk_size)
	var count_x := maxi(1, ceili(map_size.x / chunk_size))
	var count_z := maxi(1, ceili(map_size.y / chunk_size))
	for z in range(clampi(min_z, 0, count_z - 1), clampi(max_z, 0, count_z - 1) + 1):
		for x in range(clampi(min_x, 0, count_x - 1), clampi(max_x, 0, count_x - 1) + 1):
			result.append(Vector2i(x, z))
	return result


func _ensure_building_navigation_obstacles() -> void:
	## 地图建筑场景本身只需要维护真实 CollisionShape/CollisionPolygon；
	## 这里在权威端为它们生成导航包络，避免逐个建筑手写重复的顶点数据。
	## 只扫描名为 Buildings 的地图内容根节点，不会把 AI、玩家或自然资源
	## 当成普通建筑障碍。
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	var building_roots: Array[Node3D] = []
	if scene_root is Node3D and (scene_root as Node3D).name == "Buildings":
		building_roots.append(scene_root as Node3D)
	for candidate in scene_root.find_children("Buildings", "Node3D", true, false):
		if candidate is Node3D and not building_roots.has(candidate as Node3D):
			building_roots.append(candidate as Node3D)

	for buildings_root in building_roots:
		if not is_instance_valid(buildings_root):
			continue
		for child in buildings_root.get_children():
			if child is Node3D:
				_ensure_one_building_navigation_obstacle(child as Node3D)
	var obstacle_count := 0
	for node in get_tree().get_nodes_in_group(NAVIGATION_ONLY_OBSTACLE_GROUP):
		if node is Node3D and is_instance_valid(node) \
				and (node as Node3D).find_child("NavigationObstacle3D", true, false) != null:
			obstacle_count += 1
	if obstacle_count != _last_building_navigation_obstacle_count \
			and not building_roots.is_empty():
		_last_building_navigation_obstacle_count = obstacle_count
		print(
			"[DynamicNavigationChunkGrid] building navigation obstacles=%d group=%s"
			% [obstacle_count, NAVIGATION_ONLY_OBSTACLE_GROUP]
		)


func _ensure_one_building_navigation_obstacle(building: Node3D) -> void:
	if not is_instance_valid(building) or building.is_queued_for_deletion():
		return
	## 可爆破的五种设施仍由 ai_demolition_target 自己管理，不能被这里
	## 改成“仅导航障碍”或覆盖它们的生命/导航状态。
	if building.is_in_group(OBSTACLE_GROUP):
		return
	if bool(building.get_meta("farmwar_editor_visual_only", false)):
		return
	if bool(building.get_meta(SCANNED_BUILDING_META, false)):
		return

	var existing_obstacle := building.find_child(
		"NavigationObstacle3D", true, false
	) as NavigationObstacle3D
	if existing_obstacle != null:
		building.add_to_group(NAVIGATION_ONLY_OBSTACLE_GROUP)
		building.set_meta(SCANNED_BUILDING_META, true)
		return
	if bool(building.get_meta(GENERATED_BUILDING_OBSTACLE_META, false)):
		return

	var bounds_data := _collect_building_collision_bounds(building)
	if not bool(bounds_data.get("found", false)):
		building.set_meta(SCANNED_BUILDING_META, true)
		return
	var bounds: AABB = bounds_data.get("bounds", AABB())
	if bounds.size.x <= 0.01 or bounds.size.z <= 0.01:
		building.set_meta(SCANNED_BUILDING_META, true)
		return

	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "NavigationObstacle3D"
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.avoidance_enabled = true
	## obstacle 的基点和顶点都使用建筑根节点的局部坐标；这样建筑旋转、
	## 缩放或被编辑器移动后，导航包络会随建筑一起变换。
	obstacle.position = Vector3(0.0, bounds.position.y, 0.0)
	obstacle.height = maxf(0.1, bounds.size.y)
	var margin := maxf(0.05, agent_radius * 0.25)
	var min_x := bounds.position.x - margin
	var max_x := bounds.end.x + margin
	var min_z := bounds.position.z - margin
	var max_z := bounds.end.z + margin
	obstacle.vertices = PackedVector3Array([
		Vector3(min_x, 0.0, min_z),
		Vector3(max_x, 0.0, min_z),
		Vector3(max_x, 0.0, max_z),
		Vector3(min_x, 0.0, max_z),
	])
	building.add_child(obstacle)
	building.add_to_group(NAVIGATION_ONLY_OBSTACLE_GROUP)
	building.set_meta(GENERATED_BUILDING_OBSTACLE_META, true)
	building.set_meta(SCANNED_BUILDING_META, true)


func _collect_building_collision_bounds(building: Node3D) -> Dictionary:
	var result := {"found": false, "bounds": AABB()}
	_collect_building_collision_bounds_recursive(building, building, result)
	return result


func _merge_collision_bounds(result: Dictionary, candidate: AABB) -> void:
	if candidate.size.length_squared() <= 0.0001:
		return
	if not bool(result.get("found", false)):
		result["bounds"] = candidate
		result["found"] = true
		return
	var current: AABB = result.get("bounds", AABB())
	result["bounds"] = current.merge(candidate)


func _collect_building_collision_bounds_recursive(
	node: Node,
	building: Node3D,
	result: Dictionary,
) -> void:
	for child in node.get_children():
		if child is CollisionShape3D:
			var shape_node := child as CollisionShape3D
			if not shape_node.disabled and shape_node.shape != null:
				var owner := _collision_object_for_shape(shape_node, building)
				if _is_character_blocking_building_collision(owner):
					var candidate := _shape_bounds_in_building_space(building, shape_node)
					_merge_collision_bounds(result, candidate)
		elif child is CollisionPolygon3D:
			var polygon_node := child as CollisionPolygon3D
			if not polygon_node.disabled and not polygon_node.polygon.is_empty():
				var owner := _collision_object_for_shape(polygon_node, building)
				if _is_character_blocking_building_collision(owner):
					var candidate := _polygon_bounds_in_building_space(building, polygon_node)
					_merge_collision_bounds(result, candidate)
		_collect_building_collision_bounds_recursive(child, building, result)


func _collision_object_for_shape(
	shape_node: Node,
	building: Node3D,
) -> CollisionObject3D:
	var cursor := shape_node.get_parent()
	while cursor != null:
		if cursor is Area3D:
			return null
		if cursor is CollisionObject3D:
			return cursor as CollisionObject3D
		if cursor == building:
			break
		cursor = cursor.get_parent()
	return building as CollisionObject3D


func _is_character_blocking_building_collision(owner: CollisionObject3D) -> bool:
	if not is_instance_valid(owner) or owner is Area3D:
		return false
	var layer := owner.collision_layer
	## 512 是交互/商店层；只有它的 StaticBody 不会挡路，不应生成导航障碍。
	if layer == 0 or layer == 512:
		return false
	return true


func _shape_bounds_in_building_space(
	building: Node3D,
	shape_node: CollisionShape3D,
) -> AABB:
	var local_bounds := _shape_local_bounds(shape_node.shape)
	var shape_to_building := building.global_transform.affine_inverse() \
		* shape_node.global_transform
	return _transform_aabb(local_bounds, shape_to_building)


func _polygon_bounds_in_building_space(
	building: Node3D,
	polygon_node: CollisionPolygon3D,
) -> AABB:
	var polygon := polygon_node.polygon
	if polygon.is_empty():
		return AABB()
	var half_depth := maxf(0.05, polygon_node.depth * 0.5)
	var local_bounds := AABB(
		Vector3(polygon[0].x, polygon[0].y, -half_depth),
		Vector3.ZERO,
	)
	for point in polygon:
		local_bounds = local_bounds.expand(Vector3(point.x, point.y, -half_depth))
		local_bounds = local_bounds.expand(Vector3(point.x, point.y, half_depth))
	var polygon_to_building := building.global_transform.affine_inverse() \
		* polygon_node.global_transform
	return _transform_aabb(local_bounds, polygon_to_building)


func _shape_local_bounds(shape: Shape3D) -> AABB:
	if shape is BoxShape3D:
		var size := (shape as BoxShape3D).size
		return AABB(-size * 0.5, size)
	if shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		var diameter := radius * 2.0
		return AABB(Vector3(-radius, -radius, -radius), Vector3.ONE * diameter)
	if shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		return AABB(
			Vector3(-cylinder.radius, -cylinder.height * 0.5, -cylinder.radius),
			Vector3(cylinder.radius * 2.0, cylinder.height, cylinder.radius * 2.0),
		)
	if shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		return AABB(
			Vector3(-capsule.radius, -capsule.height * 0.5, -capsule.radius),
			Vector3(capsule.radius * 2.0, capsule.height, capsule.radius * 2.0),
		)
	if shape is ConvexPolygonShape3D:
		return _points_bounds((shape as ConvexPolygonShape3D).points)
	if shape is ConcavePolygonShape3D:
		return _points_bounds((shape as ConcavePolygonShape3D).get_faces())
	## 未知 Shape3D 类型仍给出一个保守的小包络，避免脚本因资源类型变化
	## 失败；常见的建筑 Shape 都在上面的分支中精确处理。
	return AABB(Vector3(-0.5, -0.5, -0.5), Vector3.ONE)


func _points_bounds(points: PackedVector3Array) -> AABB:
	if points.is_empty():
		return AABB()
	var result := AABB(points[0], Vector3.ZERO)
	for index in range(1, points.size()):
		result = result.expand(points[index])
	return result


func _transform_aabb(local_bounds: AABB, transform: Transform3D) -> AABB:
	var corners := [
		Vector3(local_bounds.position.x, local_bounds.position.y, local_bounds.position.z),
		Vector3(local_bounds.end.x, local_bounds.position.y, local_bounds.position.z),
		Vector3(local_bounds.position.x, local_bounds.end.y, local_bounds.position.z),
		Vector3(local_bounds.end.x, local_bounds.end.y, local_bounds.position.z),
		Vector3(local_bounds.position.x, local_bounds.position.y, local_bounds.end.z),
		Vector3(local_bounds.end.x, local_bounds.position.y, local_bounds.end.z),
		Vector3(local_bounds.position.x, local_bounds.end.y, local_bounds.end.z),
		Vector3(local_bounds.end.x, local_bounds.end.y, local_bounds.end.z),
	]
	var result := AABB(transform * corners[0], Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result


func _scan_demolition_obstacles() -> void:
	var seen: Dictionary = {}
	for group_name in [OBSTACLE_GROUP, NAVIGATION_ONLY_OBSTACLE_GROUP]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is Node3D or not is_instance_valid(node):
				continue
			var owner := node as Node3D
			var obstacle := owner.find_child("NavigationObstacle3D", true, false) as NavigationObstacle3D
			if obstacle == null:
				continue
			var id := owner.get_instance_id()
			seen[id] = true
			_register_obstacle(owner, obstacle, _is_obstacle_active(obstacle))

	for id_value in _obstacles.keys():
		var id := int(id_value)
		if not seen.has(id):
			var old_value: Variant = _obstacles.get(id)
			if old_value is Dictionary:
				_mark_bounds_dirty((old_value as Dictionary).get("bounds", AABB()))
			_obstacles.erase(id)


func _register_obstacle(owner: Node3D, obstacle: NavigationObstacle3D, active: bool) -> void:
	if not is_instance_valid(owner) or not is_instance_valid(obstacle):
		return
	var id := owner.get_instance_id()
	var bounds := _get_obstacle_bounds(owner, obstacle)
	var previous: Variant = _obstacles.get(id)
	var previous_bounds := AABB()
	var previous_active := false
	if previous is Dictionary:
		previous_bounds = (previous as Dictionary).get("bounds", AABB())
		previous_active = bool((previous as Dictionary).get("active", false))
	_obstacles[id] = {
		"owner": owner,
		"obstacle": obstacle,
		"bounds": bounds,
		"active": active,
	}
	if previous == null or previous_active != active or previous_bounds != bounds:
		_mark_bounds_dirty(previous_bounds)
		_mark_bounds_dirty(bounds)


func register_dynamic_obstacle(owner: Node3D, active: bool) -> void:
	## 防御设施/地图对象在激活状态改变时调用。建筑和普通道具没有调用，
	## 因此本阶段不会进入动态导航烘焙。
	if not _has_navigation_authority() or not is_instance_valid(owner):
		return
	var obstacle := owner.find_child("NavigationObstacle3D", true, false) as NavigationObstacle3D
	if obstacle == null:
		return
	_register_obstacle(owner, obstacle, active)
	_set_obstacle_active(obstacle, active)


func request_dynamic_obstacle_rebuild(owner: Node3D, active: bool) -> void:
	## 放置和周期复活是“对象重新进入导航世界”的明确生命周期事件。
	## 即使 obstacle 注册表暂时已经记录了相同状态，也要强制把旧/新
	## 包围盒标记为 dirty，确保该事件一定触发局部区块重建。
	if not _has_navigation_authority() or not is_instance_valid(owner):
		return
	var obstacle := owner.find_child("NavigationObstacle3D", true, false) as NavigationObstacle3D
	if obstacle == null:
		return
	var id := owner.get_instance_id()
	var previous: Variant = _obstacles.get(id)
	var previous_bounds := AABB()
	if previous is Dictionary:
		previous_bounds = (previous as Dictionary).get("bounds", AABB())
	var bounds := _get_obstacle_bounds(owner, obstacle)
	_obstacles[id] = {
		"owner": owner,
		"obstacle": obstacle,
		"bounds": bounds,
		"active": active,
	}
	_mark_bounds_dirty(previous_bounds)
	_mark_bounds_dirty(bounds)
	_set_obstacle_active(obstacle, active)


func unregister_dynamic_obstacle(owner: Node3D) -> void:
	if owner == null:
		return
	var id := owner.get_instance_id()
	var old_value: Variant = _obstacles.get(id)
	if old_value is Dictionary:
		_mark_bounds_dirty((old_value as Dictionary).get("bounds", AABB()))
	_obstacles.erase(id)


func _get_obstacle_bounds(owner: Node3D, obstacle: NavigationObstacle3D) -> AABB:
	var vertices: PackedVector3Array = obstacle.vertices
	if vertices.is_empty():
		return AABB(owner.global_position, Vector3.ZERO)
	var first := obstacle.global_transform * vertices[0]
	var result := AABB(first, Vector3.ZERO)
	for vertex in vertices:
		result = result.expand(obstacle.global_transform * vertex)
	result.position.y = bake_vertical_range.x
	result.size.y = maxf(result.size.y, bake_vertical_range.y - bake_vertical_range.x)
	return result


func _is_obstacle_active(obstacle: NavigationObstacle3D) -> bool:
	return is_instance_valid(obstacle) and obstacle.affect_navigation_mesh


func _set_obstacle_active(obstacle: NavigationObstacle3D, active: bool) -> void:
	if not is_instance_valid(obstacle):
		return
	## NavigationObstacle3D 没有 enabled 属性；两个开关一起切换，既让
	## 它参与局部 navmesh bake，也避免它继续参加 NavigationServer RVO。
	obstacle.set_deferred("affect_navigation_mesh", active)
	obstacle.set_deferred("avoidance_enabled", active)


func _mark_bounds_dirty(bounds: AABB) -> void:
	if bounds.size.length_squared() <= 0.0001:
		return
	var expanded := bounds.grow(maxf(agent_radius, 0.75))
	for chunk_id in _chunk_ids_for_aabb(expanded):
		_dirty_chunks[chunk_id] = true
	if _batch_first_frame < 0:
		_batch_first_frame = Engine.get_physics_frames()
		## 任何帧率下都至少完整等待 rebuild_batch_physics_frames 个物理帧；
		## max_delay 只作为物理循环暂停时的兜底，不会提前打断五帧合并窗口。
		var frame_window_seconds := float(maxi(1, rebuild_batch_physics_frames)) \
				/ maxf(1.0, float(Engine.physics_ticks_per_second))
		_batch_deadline_msec = Time.get_ticks_msec() + int(
			maxf(rebuild_max_delay_seconds, frame_window_seconds) * 1000.0
		)


func _flush_dirty_chunks_to_bake_queue() -> void:
	if _dirty_chunks.is_empty():
		return
	var chunk_ids: Array[Vector2i] = []
	for key in _dirty_chunks.keys():
		chunk_ids.append(key as Vector2i)
	_dirty_chunks.clear()
	_batch_first_frame = -1
	_batch_deadline_msec = 0
	for chunk_id in chunk_ids:
		if not _bake_queue.has(chunk_id):
			_bake_queue.append(chunk_id)


func _start_next_bake() -> void:
	if _bake_active or _bake_queue.is_empty() or not _initialized:
		return
	## 当前实现始终串行提交 async bake；即使场景把开关误设为 false，
	## 也不能让同一个 _bake_active 状态被多个回调覆盖。
	_bake_active = true
	_bake_chunk = _bake_queue.pop_front()
	_bake_generation += 1
	navigation_rebuild_started.emit([_bake_chunk])

	var region := _regions.get(_bake_chunk, null) as NavigationRegion3D
	if region == null:
		_bake_active = false
		call_deferred("_start_next_bake")
		return
	var navigation_mesh := _make_navigation_mesh(_bake_chunk)
	var source := _make_source_geometry(_bake_chunk)
	NavigationServer3D.bake_from_source_geometry_data_async(
		navigation_mesh,
		source,
		Callable(self, "_on_bake_completed").bind(_bake_chunk, navigation_mesh, _bake_generation)
	)


func _make_navigation_mesh(chunk_id: Vector2i) -> NavigationMesh:
	var navigation_mesh := NavigationMesh.new()
	navigation_mesh.agent_height = agent_height
	navigation_mesh.agent_radius = agent_radius
	navigation_mesh.cell_size = bake_cell_size
	navigation_mesh.cell_height = bake_cell_height
	navigation_mesh.border_size = bake_border_size
	navigation_mesh.sample_partition_type = NavigationMesh.SAMPLE_PARTITION_LAYERS
	navigation_mesh.filter_baking_aabb = _chunk_bounds(chunk_id)
	return navigation_mesh


func _make_source_geometry(chunk_id: Vector2i) -> NavigationMeshSourceGeometryData3D:
	var source := NavigationMeshSourceGeometryData3D.new()
	var bake_bounds := _chunk_bounds(chunk_id, bake_border_size + agent_radius)
	var added_ground := false
	for mesh_instance in _ground_meshes:
		if not is_instance_valid(mesh_instance) or mesh_instance.mesh == null:
			continue
		if not _mesh_instance_bounds(mesh_instance).intersects(bake_bounds):
			continue
		if _add_mesh_geometry_to_source(source, mesh_instance):
			added_ground = true
	if not added_ground:
		_add_fallback_ground(source, _chunk_bounds(chunk_id))

	for obstacle_value in _obstacles.values():
		if not obstacle_value is Dictionary:
			continue
		var data := obstacle_value as Dictionary
		if not bool(data.get("active", false)):
			continue
		var bounds: AABB = data.get("bounds", AABB())
		if not bounds.intersects(bake_bounds):
			continue
		var obstacle := data.get("obstacle", null) as NavigationObstacle3D
		if obstacle == null or obstacle.vertices.is_empty():
			continue
		var vertices := PackedVector3Array()
		for vertex in obstacle.vertices:
			var world_vertex := obstacle.global_transform * vertex
			vertices.append(Vector3(world_vertex.x, 0.0, world_vertex.z))
		var height := maxf(0.1, obstacle.height)
		source.add_projected_obstruction(
			vertices,
			obstacle.global_position.y,
			height,
			obstacle.carve_navigation_mesh
		)
	return source


func _add_mesh_geometry_to_source(
	source: NavigationMeshSourceGeometryData3D,
	mesh_instance: MeshInstance3D
) -> bool:
	## 不调用 add_mesh(RenderingServer RID)，避免运行时从 GPU 回读整个视觉网格。
	## 直接读取 Mesh surface 数组，并只把三角面传给本区块的 source geometry。
	var mesh := mesh_instance.mesh
	if mesh == null:
		return false
	var added := false
	for surface_index in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface_index)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if vertices.is_empty():
			continue
		var indices: PackedInt32Array = PackedInt32Array()
		if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
			indices = arrays[Mesh.ARRAY_INDEX]
		var faces := PackedVector3Array()
		if indices.is_empty():
			for vertex_index in range(0, vertices.size() - 2, 3):
				faces.append(vertices[vertex_index])
				faces.append(vertices[vertex_index + 1])
				faces.append(vertices[vertex_index + 2])
		else:
			for index in indices:
				if index >= 0 and index < vertices.size():
					faces.append(vertices[index])
		if faces.size() >= 3:
			source.add_faces(faces, mesh_instance.global_transform)
			added = true
	return added


func _add_fallback_ground(source: NavigationMeshSourceGeometryData3D, bounds: AABB) -> void:
	var min_x := bounds.position.x
	var max_x := bounds.end.x
	var min_z := bounds.position.z
	var max_z := bounds.end.z
	var y := fallback_ground_y
	var faces := PackedVector3Array([
		Vector3(min_x, y, min_z),
		Vector3(max_x, y, min_z),
		Vector3(max_x, y, max_z),
		Vector3(min_x, y, min_z),
		Vector3(max_x, y, max_z),
		Vector3(min_x, y, max_z),
	])
	source.add_faces(faces, Transform3D.IDENTITY)


func _mesh_instance_bounds(mesh_instance: MeshInstance3D) -> AABB:
	var local_bounds := mesh_instance.get_aabb()
	var transform := mesh_instance.global_transform
	var result := AABB(transform * local_bounds.position, Vector3.ZERO)
	for x in [local_bounds.position.x, local_bounds.end.x]:
		for y in [local_bounds.position.y, local_bounds.end.y]:
			for z in [local_bounds.position.z, local_bounds.end.z]:
				result = result.expand(transform * Vector3(x, y, z))
	return result


func _on_bake_completed(
	chunk_id: Vector2i,
	baked_mesh: NavigationMesh,
	request_generation: int,
) -> void:
	## NavigationServer 的 bake 回调可能与物理更新交错；把 Region 写入延迟到
	## 主线程下一轮，避免在服务器同步阶段直接替换导航数据。
	call_deferred(
		"_finish_bake",
		chunk_id,
		baked_mesh,
		request_generation,
	)


func _finish_bake(
	chunk_id: Vector2i,
	baked_mesh: NavigationMesh,
	_request_generation: int,
) -> void:
	if _request_generation != _bake_generation or not _has_navigation_authority():
		return
	var region := _regions.get(chunk_id, null) as NavigationRegion3D
	if region != null and baked_mesh != null:
		region.navigation_mesh = baked_mesh
	_bake_active = false
	_initial_bakes_remaining = maxi(0, _initial_bakes_remaining - 1)

	var rebuilt: Array[Vector2i] = [chunk_id]
	navigation_chunks_rebuilt.emit(rebuilt)
	_notify_ai_navigation_updated(rebuilt)
	if _initial_bakes_remaining == 0:
		navigation_ready.emit()

	if not _bake_queue.is_empty():
		_start_next_bake()
	elif _dirty_chunks.is_empty():
		navigation_idle.emit()


func _notify_ai_navigation_updated(chunk_ids: Array[Vector2i]) -> void:
	var candidates: Array[Node] = []
	candidates.append_array(get_tree().get_nodes_in_group("future_warrior_ai"))
	candidates.append_array(get_tree().get_nodes_in_group("assistant_ai"))
	for node in candidates:
		if not is_instance_valid(node) or not node is Node3D \
				or not node.has_method("notify_navigation_chunks_rebuilt"):
			continue
		var should_notify := false
		var current_position: Vector3 = (node as Node3D).global_position
		var target_value: Variant = node.get("target")
		var target_position := Vector3.INF
		if target_value is Node3D and is_instance_valid(target_value):
			target_position = (target_value as Node3D).global_position
		for chunk_id in chunk_ids:
			var bounds := _chunk_bounds(chunk_id, agent_radius + 1.0)
			if bounds.has_point(current_position) \
					or (target_position.is_finite() and bounds.has_point(target_position)):
				should_notify = true
				break
		if not should_notify \
					and node.has_method("is_squad_navigation_stuck") \
					and bool(node.call("is_squad_navigation_stuck")):
			should_notify = true
		if should_notify:
			node.call("notify_navigation_chunks_rebuilt", chunk_ids)


func is_navigation_ready() -> bool:
	if not _initialized or _initial_bakes_remaining > 0:
		return false
	var navigation_map := get_world_3d().navigation_map
	return navigation_map.is_valid() \
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0


func get_navigation_map() -> RID:
	return get_world_3d().navigation_map


func get_region(chunk_id: Vector2i) -> NavigationRegion3D:
	return _regions.get(chunk_id, null) as NavigationRegion3D


func get_chunk_count() -> Vector2i:
	return Vector2i(
		maxi(1, ceili(map_size.x / chunk_size)),
		maxi(1, ceili(map_size.y / chunk_size)),
	)


func wait_for_idle() -> void:
	while not _initialized or _bake_active or not _bake_queue.is_empty() \
			or not _dirty_chunks.is_empty():
		await get_tree().physics_frame
	await get_tree().physics_frame
