extends Node3D

const WAIT_TIMEOUT_FRAMES := 900
const SEAM_TOLERANCE := 0.05

var failures := 0
var _grid: DynamicNavigationChunkGrid


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "NavigationChunkSeamValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self
	_create_flat_ground()
	_create_navigation_grid()

	var waited_frames := 0
	while not _grid.is_navigation_ready() and waited_frames < WAIT_TIMEOUT_FRAMES:
		await get_tree().physics_frame
		waited_frames += 1
	_check(_grid.is_navigation_ready(), "two navigation chunks finish baking")
	if not _grid.is_navigation_ready():
		_finish()
		return

	## NavigationServer applies region changes on the following synchronization.
	for _frame in range(3):
		await get_tree().physics_frame
	_validate_shared_seam()
	_validate_cross_chunk_path()
	await _validate_seam_obstacle_rebuild()
	_finish()


func _create_flat_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "NavigationGround"
	var plane := PlaneMesh.new()
	plane.size = Vector2(128.0, 64.0)
	ground.mesh = plane
	add_child(ground)
	ground.add_to_group(DynamicNavigationChunkGrid.GROUND_GROUP)


func _create_navigation_grid() -> void:
	_grid = DynamicNavigationChunkGrid.new()
	_grid.name = "TwoChunkNavigationGrid"
	_grid.create_regions_on_ready = false
	_grid.map_origin = Vector2(-64.0, -32.0)
	_grid.map_size = Vector2(128.0, 64.0)
	_grid.chunk_size = 64.0
	_grid.agent_radius = 0.4
	_grid.bake_cell_size = 0.25
	_grid.bake_cell_height = 0.25
	_grid.bake_border_size = 1.0
	add_child(_grid)
	_grid.call_deferred("_initialize_grid")


func _validate_shared_seam() -> void:
	var left_region := _grid.get_region(Vector2i(0, 0))
	var right_region := _grid.get_region(Vector2i(1, 0))
	_check(left_region != null and right_region != null, "both navigation regions exist")
	if left_region == null or right_region == null:
		return
	var left_mesh := left_region.navigation_mesh
	var right_mesh := right_region.navigation_mesh
	_check(left_mesh != null and right_mesh != null, "both navigation meshes exist")
	if left_mesh == null or right_mesh == null:
		return
	_check(
		is_equal_approx(left_mesh.border_size, 1.0)
			and is_equal_approx(right_mesh.border_size, 1.0),
		"expanded bake bounds use a matching one-meter border",
	)
	var left_vertices := left_mesh.vertices
	var right_vertices := right_mesh.vertices
	_check(not left_vertices.is_empty() and not right_vertices.is_empty(), "both meshes contain vertices")
	if left_vertices.is_empty() or right_vertices.is_empty():
		return
	var left_max_x := -INF
	var right_min_x := INF
	for vertex in left_vertices:
		left_max_x = maxf(left_max_x, vertex.x)
	for vertex in right_vertices:
		right_min_x = minf(right_min_x, vertex.x)
	var seam_gap := right_min_x - left_max_x
	_check(
		absf(seam_gap) <= SEAM_TOLERANCE,
		"shared seam gap is %.3fm (maximum %.3fm)" % [seam_gap, SEAM_TOLERANCE],
	)


func _validate_cross_chunk_path() -> void:
	_check(_path_reaches_across_seam(), "NavigationServer returns a path across the chunk seam")


func _validate_seam_obstacle_rebuild() -> void:
	var wall_owner := Node3D.new()
	wall_owner.name = "SeamBlockingWall"
	add_child(wall_owner)
	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "NavigationObstacle3D"
	obstacle.height = 3.0
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.avoidance_enabled = false
	obstacle.vertices = PackedVector3Array([
		Vector3(-0.5, 0.0, -40.0),
		Vector3(0.5, 0.0, -40.0),
		Vector3(0.5, 0.0, 40.0),
		Vector3(-0.5, 0.0, 40.0),
	])
	wall_owner.add_child(obstacle)
	_grid.request_dynamic_obstacle_rebuild(wall_owner, true)
	await _grid.wait_for_idle()
	for _frame in range(3):
		await get_tree().physics_frame
	_check(
		not _path_reaches_across_seam(),
		"a wall on the seam blocks navigation instead of being bypassed by edge links",
	)

	_grid.unregister_dynamic_obstacle(wall_owner)
	wall_owner.queue_free()
	await _grid.wait_for_idle()
	for _frame in range(3):
		await get_tree().physics_frame
	_check(
		_path_reaches_across_seam(),
		"removing the seam obstacle rebuilds both chunks and restores the path",
	)
	_validate_shared_seam()


func _path_across_seam() -> PackedVector3Array:
	var navigation_map := _grid.get_navigation_map()
	var start := NavigationServer3D.map_get_closest_point(
		navigation_map,
		Vector3(-16.0, 0.0, 0.0),
	)
	var finish := NavigationServer3D.map_get_closest_point(
		navigation_map,
		Vector3(16.0, 0.0, 0.0),
	)
	return NavigationServer3D.map_get_path(navigation_map, start, finish, true)


func _path_reaches_across_seam() -> bool:
	var path := _path_across_seam()
	if path.size() < 2:
		return false
	var navigation_map := _grid.get_navigation_map()
	var expected_finish := NavigationServer3D.map_get_closest_point(
		navigation_map,
		Vector3(16.0, 0.0, 0.0),
	)
	return path[path.size() - 1].distance_to(expected_finish) <= 0.5


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[NavigationChunkSeamValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[NavigationChunkSeamValidation] FAIL: %s" % description)


func _finish() -> void:
	if failures == 0:
		print("[NavigationChunkSeamValidation] PASS all checks")
	else:
		push_error("[NavigationChunkSeamValidation] FAIL count=%d" % failures)
	if is_instance_valid(GameAuthority):
		GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)
