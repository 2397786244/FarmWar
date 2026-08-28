extends Node3D

## 独立的载具生成观察场景。
##
## 这个场景只服务于手动观察，不接入正式地图、编辑器工具或联机流程：
## - 鼠标指向地面时显示目标点和解析后的落地点。
## - 左键调用现有的本地权威载具放置入口。
## - 数字 1～9 选择要生成的载具。
## - WASD 移动观察相机，Q/E 调整高度，按住鼠标右键旋转视角。

const VEHICLE_CATALOG := preload("res://src/vehicle_spawn_catalog.gd")
const PLACEMENT_QUERY := preload("res://src/placement_query.gd")
const BLACK_BEAR_SCENE := preload("res://items/BlackBear.tscn")
const FUTURE_WARRIOR_SCENE := preload("res://character/FutureWarriorAI.tscn")

const GROUND_LAYER := 1
const MOVE_SPEED := 18.0
const FAST_MOVE_SPEED := 42.0
const LOOK_SENSITIVITY := 0.0025
const MIN_CAMERA_Y := 3.0
const MAX_CAMERA_Y := 60.0
const GROUND_SIZE := 128.0
const NAVIGATION_CHUNK_SIZE := 64.0
const PREVIEW_SETTLE_DELAY_SECONDS := 0.10
const PREVIEW_TARGET_REQUERY_DISTANCE := 0.35

const VEHICLE_SLOTS: Array[Dictionary] = [
	{"id": "mini_car", "label": "迷你车"},
	{"id": "sedan", "label": "轿车"},
	{"id": "sport_car", "label": "运动型跑车"},
	{"id": "van", "label": "厢式货车"},
	{"id": "atv", "label": "越野摩托车"},
	{"id": "farm_base_vehicle", "label": "农场基础载具"},
	{"id": "police_car", "label": "警车"},
	{"id": "fire_pickup", "label": "消防车"},
	{"id": "cargo_car", "label": "货运车（红队）"},
]

@export_category("观察场景")
@export var build_on_ready := true
@export var selected_team := "red"
@export_range(0, 24, 1) var black_bear_count := 12
@export_range(0, 24, 1) var future_warrior_count := 12

var _camera: Camera3D
var _camera_yaw := 0.0
var _camera_pitch := deg_to_rad(-42.0)
var _look_active := false
var _preview_dirty := true
var _preview_settle_remaining := 0.0
var _last_preview_input_target := Vector3.ZERO
var _last_preview_input_target_valid := false
var _selected_slot := 0
var _placement_serial := 0
var _mouse_target := Vector3.ZERO
var _mouse_target_valid := false
var _placement_result: Dictionary = {}
var _waypoint: Node3D
var _target_marker: MeshInstance3D
var _landing_marker: MeshInstance3D
var _status_label: Label
var _preview_label: Label
var _selection_label: Label
var _slot_label: Label
var _authority_started := false


func _ready() -> void:
	if not build_on_ready:
		return

	# 让这一张独立场景使用与游戏一致的本地权威逻辑。这里没有真实玩家节点，
	# 只在 player_states 中登记一个观察者，以便复用已有的载具放置入口。
	GlobalVar.gameworld = self
	GameAuthority.start_local_mode({
		"display_name": "VehicleSpawnObserver",
		"team": selected_team,
		"position": Vector3.ZERO,
		"yaw": 0.0,
		"hp": 200.0,
		# The observer has no presentation body. Keeping its virtual tool as a
		# torch makes wildlife ignore this bookkeeping-only player state.
		"current_tool_id": "torch",
	})
	_authority_started = true

	_build_environment()
	_build_floor()
	_build_navigation_grid()
	_build_camera()
	_build_population()
	_build_markers()
	_build_hud()
	_update_mouse_target()
	_refresh_preview()


func _process(delta: float) -> void:
	if not build_on_ready:
		return
	_update_free_camera(delta)
	_update_mouse_target()
	if _preview_dirty:
		_preview_settle_remaining = maxf(0.0, _preview_settle_remaining - delta)
		if _preview_settle_remaining <= 0.0:
			_refresh_preview()


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _authority_started and GameAuthority.is_local_authority():
		GameAuthority.stop_authority()
	if GlobalVar.gameworld == self:
		GlobalVar.gameworld = null


func _build_environment() -> void:
	var world_environment := WorldEnvironment.new()
	world_environment.name = "ObserverEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#111b24")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#a8b6c7")
	environment.ambient_light_energy = 0.85
	world_environment.environment = environment
	add_child(world_environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "ObserverKeyLight"
	key_light.rotation_degrees = Vector3(-55.0, -28.0, 0.0)
	key_light.light_energy = 1.25
	key_light.shadow_enabled = true
	add_child(key_light)

	var fill_light := DirectionalLight3D.new()
	fill_light.name = "ObserverFillLight"
	fill_light.rotation_degrees = Vector3(-35.0, 145.0, 0.0)
	fill_light.light_energy = 0.28
	add_child(fill_light)


func _build_floor() -> void:
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("#324b3b")
	floor_material.roughness = 0.92

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "ObserverFloor"
	var floor_box := BoxMesh.new()
	floor_box.size = Vector3(GROUND_SIZE, 0.10, GROUND_SIZE)
	floor_mesh.mesh = floor_box
	floor_mesh.position = Vector3(0.0, -0.05, 0.0)
	floor_mesh.material_override = floor_material
	floor_mesh.add_to_group("navigation_ground")
	add_child(floor_mesh)

	var floor_body := StaticBody3D.new()
	floor_body.name = "ObserverGroundCollision"
	floor_body.collision_layer = GROUND_LAYER
	floor_body.collision_mask = 0
	var floor_shape := CollisionShape3D.new()
	var floor_box_shape := BoxShape3D.new()
	floor_box_shape.size = Vector3(GROUND_SIZE, 0.10, GROUND_SIZE)
	floor_shape.shape = floor_box_shape
	floor_shape.position = Vector3(0.0, -0.05, 0.0)
	floor_body.add_child(floor_shape)
	add_child(floor_body)

	# 简单网格只用于观察位置，不参与碰撞。
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color = Color(0.75, 0.88, 0.76, 0.18)
	grid_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid_material.blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	for coordinate in range(-64, 65, 8):
		_add_visual_bar(
			"GridX_%d" % coordinate,
			Vector3(float(coordinate), 0.012, 0.0),
			Vector3(0.025, 0.015, GROUND_SIZE),
			grid_material
		)
		_add_visual_bar(
			"GridZ_%d" % coordinate,
			Vector3(0.0, 0.014, float(coordinate)),
			Vector3(GROUND_SIZE, 0.015, 0.025),
			grid_material
		)
	_add_navigation_chunk_dividers()


func _build_navigation_grid() -> void:
	var navigation_grid := DynamicNavigationChunkGrid.new()
	navigation_grid.name = "ObserverNavigationGrid"
	navigation_grid.map_origin = Vector2(-GROUND_SIZE * 0.5, -GROUND_SIZE * 0.5)
	navigation_grid.map_size = Vector2(GROUND_SIZE, GROUND_SIZE)
	navigation_grid.chunk_size = NAVIGATION_CHUNK_SIZE
	navigation_grid.fallback_ground_y = 0.0
	navigation_grid.create_regions_on_ready = true
	add_child(navigation_grid)


func _add_navigation_chunk_dividers() -> void:
	var divider_material := StandardMaterial3D.new()
	divider_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	divider_material.albedo_color = Color("#f1c65d")
	divider_material.emission_enabled = true
	divider_material.emission = Color("#c69438")
	divider_material.emission_energy_multiplier = 0.7
	_add_visual_bar(
		"NavigationChunkDividerX",
		Vector3(0.0, 0.025, 0.0),
		Vector3(0.14, 0.025, GROUND_SIZE),
		divider_material
	)
	_add_visual_bar(
		"NavigationChunkDividerZ",
		Vector3(0.0, 0.027, 0.0),
		Vector3(GROUND_SIZE, 0.025, 0.14),
		divider_material
	)
	for chunk_data: Dictionary in [
		{"label": "导航区块 0,0", "position": Vector3(-32.0, 0.05, -32.0)},
		{"label": "导航区块 1,0", "position": Vector3(32.0, 0.05, -32.0)},
		{"label": "导航区块 0,1", "position": Vector3(-32.0, 0.05, 32.0)},
		{"label": "导航区块 1,1", "position": Vector3(32.0, 0.05, 32.0)},
	]:
		var label := Label3D.new()
		label.name = "Observer%s" % str(chunk_data["label"]).replace(",", "_")
		label.text = str(chunk_data["label"])
		label.position = chunk_data["position"] as Vector3
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.modulate = Color("#f3d687")
		add_child(label)


func _add_visual_bar(
	node_name: String,
	position: Vector3,
	size: Vector3,
	material: Material
) -> void:
	var visual := MeshInstance3D.new()
	visual.name = node_name
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.position = position
	visual.material_override = material
	add_child(visual)


func _build_camera() -> void:
	_camera = Camera3D.new()
	_camera.name = "ObserverCamera"
	_camera.near = 0.1
	_camera.far = 180.0
	_camera.fov = 65.0
	_camera.position = Vector3(0.0, 25.0, 28.0)
	add_child(_camera)
	_camera.current = true
	_apply_camera_rotation()


func _build_population() -> void:
	_waypoint = Node3D.new()
	_waypoint.name = "AIObservationWaypoint"
	# All four groups cross the central chunk boundaries on the way to this
	# point, making it easy to observe a parked vehicle updating one or more
	# 64m navigation regions.
	_waypoint.position = Vector3(0.0, 0.0, 0.0)
	add_child(_waypoint)

	var bear_positions: Array[Vector3] = [
		# Chunk 0,0
		Vector3(-52.0, 0.0, -50.0), Vector3(-44.0, 0.0, -42.0), Vector3(-28.0, 0.0, -52.0),
		# Chunk 1,0
		Vector3(24.0, 0.0, -50.0), Vector3(39.0, 0.0, -43.0), Vector3(53.0, 0.0, -29.0),
		# Chunk 0,1
		Vector3(-51.0, 0.0, 24.0), Vector3(-37.0, 0.0, 39.0), Vector3(-24.0, 0.0, 52.0),
		# Chunk 1,1
		Vector3(24.0, 0.0, 25.0), Vector3(40.0, 0.0, 42.0), Vector3(53.0, 0.0, 53.0),
	]
	for index in range(mini(black_bear_count, bear_positions.size())):
		var bear := BLACK_BEAR_SCENE.instantiate() as BlackBear
		if bear == null:
			continue
		bear.name = "ObserverBlackBear_%02d" % index
		bear.animal_id = "observer_black_bear_%02d" % index
		bear.home_position = bear_positions[index]
		bear.position = bear_positions[index]
		add_child(bear)
		# Keep the bears as dynamic physical blockers for placement and navigation
		# observation, but do not let FutureWarrior combat logic select them as
		# hostile targets in this non-combat test scene.
		bear.remove_from_group("wild_animals")

	var warrior_positions: Array[Vector3] = [
		# Chunk 0,0
		Vector3(-54.0, 0.0, -35.0), Vector3(-42.0, 0.0, -55.0), Vector3(-26.0, 0.0, -30.0),
		# Chunk 1,0
		Vector3(26.0, 0.0, -54.0), Vector3(44.0, 0.0, -35.0), Vector3(55.0, 0.0, -22.0),
		# Chunk 0,1
		Vector3(-55.0, 0.0, 26.0), Vector3(-38.0, 0.0, 51.0), Vector3(-22.0, 0.0, 31.0),
		# Chunk 1,1
		Vector3(25.0, 0.0, 54.0), Vector3(43.0, 0.0, 35.0), Vector3(55.0, 0.0, 22.0),
	]
	for index in range(mini(future_warrior_count, warrior_positions.size())):
		var warrior := FUTURE_WARRIOR_SCENE.instantiate() as FutureWarriorAI
		if warrior == null:
			continue
		warrior.name = "ObserverFutureWarrior_%02d" % index
		# The test is for placement behaviour, not combat. Use the observer's
		# team so spawned test vehicles cannot become Future AI targets.
		warrior.team_id = selected_team
		warrior.server_authoritative = false
		warrior.use_navigation_agent = true
		warrior.navigation_avoidance_enabled = true
		warrior.target = _waypoint
		warrior.starting_grenade_count = 0
		warrior.print_decisions = false
		warrior.map_boundary_limit = 60.0
		warrior.position = warrior_positions[index]
		add_child(warrior)


func _build_markers() -> void:
	_target_marker = _make_marker("ObserverTargetMarker", 0.18, Color("#f7d34e"))
	_landing_marker = _make_marker("ObserverLandingMarker", 0.85, Color("#53d978"))
	_landing_marker.visible = false


func _make_marker(node_name: String, radius: float, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = node_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.06
	marker.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	marker.material_override = material
	marker.position = Vector3(0.0, 0.04, 0.0)
	add_child(marker)
	return marker


func _build_hud() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "ObserverHUD"
	add_child(canvas)

	var panel := ColorRect.new()
	panel.name = "InstructionsPanel"
	panel.position = Vector2(18.0, 18.0)
	panel.size = Vector2(545.0, 315.0)
	panel.color = Color(0.035, 0.055, 0.075, 0.92)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(panel)

	var title := Label.new()
	title.text = "载具放置与导航分块观察场景（128×128）"
	title.position = Vector2(18.0, 12.0)
	title.size = Vector2(500.0, 30.0)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#f4d36b"))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(title)

	var controls := Label.new()
	controls.text = "WASD 移动  |  Q/E 升降  |  按住右键旋转视角\n左键：在鼠标指向地面放置  |  Shift：加速  |  黄色十字：四个 64m 导航区块"
	controls.position = Vector2(18.0, 48.0)
	controls.size = Vector2(510.0, 46.0)
	controls.add_theme_font_size_override("font_size", 14)
	controls.add_theme_color_override("font_color", Color("#d6e2e8"))
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(controls)

	_selection_label = Label.new()
	_selection_label.position = Vector2(18.0, 102.0)
	_selection_label.size = Vector2(510.0, 28.0)
	_selection_label.add_theme_font_size_override("font_size", 17)
	_selection_label.add_theme_color_override("font_color", Color("#ffffff"))
	_selection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_selection_label)

	_slot_label = Label.new()
	_slot_label.position = Vector2(18.0, 134.0)
	_slot_label.size = Vector2(510.0, 104.0)
	_slot_label.add_theme_font_size_override("font_size", 14)
	_slot_label.add_theme_color_override("font_color", Color("#c3d1d8"))
	_slot_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_slot_label)

	_preview_label = Label.new()
	_preview_label.position = Vector2(18.0, 244.0)
	_preview_label.size = Vector2(510.0, 30.0)
	_preview_label.add_theme_font_size_override("font_size", 14)
	_preview_label.add_theme_color_override("font_color", Color("#73df91"))
	_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_preview_label)

	_status_label = Label.new()
	_status_label.position = Vector2(18.0, 275.0)
	_status_label.size = Vector2(510.0, 30.0)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color("#f2b4b4"))
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(_status_label)
	_status_label.text = "等待放置。黄色标记是鼠标目标，绿色/橙色标记是解析后的落地点。"

	_refresh_selection_hud()


func _update_free_camera(delta: float) -> void:
	if _camera == null:
		return
	var speed := FAST_MOVE_SPEED if Input.is_key_pressed(KEY_SHIFT) else MOVE_SPEED
	var input_direction := Vector3.ZERO
	var forward := -_camera.global_transform.basis.z
	var right := _camera.global_transform.basis.x
	forward.y = 0.0
	right.y = 0.0
	if forward.length_squared() > 0.001:
		forward = forward.normalized()
	if right.length_squared() > 0.001:
		right = right.normalized()
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		input_direction += forward
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		input_direction -= forward
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		input_direction += right
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		input_direction -= right
	if Input.is_key_pressed(KEY_Q):
		input_direction += Vector3.DOWN
	if Input.is_key_pressed(KEY_E):
		input_direction += Vector3.UP
	if input_direction.length_squared() > 0.001:
		_camera.global_position += input_direction.normalized() * speed * delta
	_camera.global_position.x = clampf(_camera.global_position.x, -46.0, 46.0)
	_camera.global_position.y = clampf(_camera.global_position.y, MIN_CAMERA_Y, MAX_CAMERA_Y)
	_camera.global_position.z = clampf(_camera.global_position.z, -46.0, 46.0)


func _apply_camera_rotation() -> void:
	if _camera == null:
		return
	_camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _update_mouse_target() -> void:
	if _camera == null:
		return
	var mouse_position := get_viewport().get_mouse_position()
	var ray_origin := _camera.project_ray_origin(mouse_position)
	var ray_direction := _camera.project_ray_normal(mouse_position)
	var ray_query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_direction * 180.0
	)
	ray_query.collision_mask = GROUND_LAYER
	ray_query.collide_with_bodies = true
	ray_query.collide_with_areas = false
	var hit := get_world_3d().direct_space_state.intersect_ray(ray_query)
	if not hit.is_empty() and hit.get("position", null) is Vector3:
		_mouse_target = hit["position"] as Vector3
		_mouse_target_valid = true
	else:
		# 没有碰到场景时仍在 y=0 的观察平面上给出一个目标点。
		if absf(ray_direction.y) > 0.0001:
			var distance := -ray_origin.y / ray_direction.y
			if distance >= 0.0:
				_mouse_target = ray_origin + ray_direction * distance
				_mouse_target_valid = true
			else:
				_mouse_target_valid = false

	if _target_marker != null:
		_target_marker.visible = _mouse_target_valid
		if _mouse_target_valid:
			_target_marker.global_position = _mouse_target + Vector3.UP * 0.04
	_mark_preview_dirty_for_mouse_target()


func _mark_preview_dirty_for_mouse_target() -> void:
	if not _mouse_target_valid:
		if _last_preview_input_target_valid:
			_last_preview_input_target_valid = false
			_preview_dirty = true
			_preview_settle_remaining = PREVIEW_SETTLE_DELAY_SECONDS
		return
	if _last_preview_input_target_valid and _mouse_target.distance_squared_to(
			_last_preview_input_target
	) < PREVIEW_TARGET_REQUERY_DISTANCE * PREVIEW_TARGET_REQUERY_DISTANCE:
		return
	_last_preview_input_target = _mouse_target
	_last_preview_input_target_valid = true
	_preview_dirty = true
	_preview_settle_remaining = PREVIEW_SETTLE_DELAY_SECONDS


func _refresh_preview() -> void:
	_preview_dirty = false
	_preview_settle_remaining = 0.0
	_last_preview_input_target_valid = _mouse_target_valid
	if _mouse_target_valid:
		_last_preview_input_target = _mouse_target
	if not _mouse_target_valid or _camera == null:
		_placement_result = {}
		if _landing_marker != null:
			_landing_marker.visible = false
		if _preview_label != null:
			_preview_label.text = "预览：没有可用的地面目标"
		return

	var slot := VEHICLE_SLOTS[_selected_slot]
	_placement_result = PLACEMENT_QUERY.resolve_vehicle_spawn(
		get_world_3d(),
		_mouse_target,
		str(slot["id"]),
		{
			"team": selected_team,
			"yaw": 0.0,
			"max_search_radius": 12.0,
			"search_step": 1.0,
			"max_slope_degrees": 5.0,
			"clearance": 0.15,
			"max_candidates": 512,
		}
	)
	_update_preview_visuals()


func _update_preview_visuals() -> void:
	if _landing_marker == null or _preview_label == null:
		return
	var label := str(VEHICLE_SLOTS[_selected_slot]["label"])
	if bool(_placement_result.get("ok", false)):
		var landing := _placement_result.get("position", Vector3.ZERO) as Vector3
		_landing_marker.visible = true
		_landing_marker.global_position = landing + Vector3.UP * 0.07
		var mode := str(_placement_result.get("spawn_mode", "ground"))
		if mode == "airdrop":
			_set_marker_color(_landing_marker, Color("#f0a23c"))
			_preview_label.text = "预览：%s  空投兜底，落地点已找到" % label
		else:
			_set_marker_color(_landing_marker, Color("#53d978"))
			_preview_label.text = "预览：%s  地面放置可用" % label
	else:
		_landing_marker.visible = true
		_landing_marker.global_position = _mouse_target + Vector3.UP * 0.07
		_set_marker_color(_landing_marker, Color("#ed6666"))
		_preview_label.text = "预览：%s  不可放置：%s" % [label, _placement_reason_text(_placement_result)]


func _set_marker_color(marker: MeshInstance3D, color: Color) -> void:
	var material := marker.material_override as StandardMaterial3D
	if material == null:
		return
	material.albedo_color = color
	material.emission = color


func _placement_reason_text(result: Dictionary) -> String:
	var reason := str(result.get("reason", "未知原因"))
	match reason:
		"no_vehicle_spawn_point":
			return "附近没有符合条件的位置"
		"placement_query_unavailable":
			return "物理世界不可用"
		"invalid_vehicle_type":
			return "载具未登记"
		"invalid_vehicle_profile":
			return "载具碰撞轮廓不可用"
		_:
			return reason


func _refresh_selection_hud() -> void:
	if _selection_label == null or _slot_label == null:
		return
	var selected_label := str(VEHICLE_SLOTS[_selected_slot]["label"])
	_selection_label.text = "当前选择：%s（%d）" % [selected_label, _selected_slot + 1]
	var lines: Array[String] = []
	for index in range(VEHICLE_SLOTS.size()):
		var prefix := "> " if index == _selected_slot else "  "
		lines.append("%s%d  %s" % [prefix, index + 1, str(VEHICLE_SLOTS[index]["label"])])
	_slot_label.text = "\n".join(lines)


func _select_slot(index: int) -> void:
	if index < 0 or index >= VEHICLE_SLOTS.size():
		return
	_selected_slot = index
	_refresh_selection_hud()
	_preview_dirty = true
	_preview_settle_remaining = 0.0
	if _status_label != null:
		_status_label.text = "已选择 %s。移动鼠标查看新的落点。" % str(VEHICLE_SLOTS[index]["label"])


func _place_selected_vehicle() -> void:
	if not _mouse_target_valid:
		if _status_label != null:
			_status_label.text = "没有找到鼠标对应的地面点。"
		return
	var slot := VEHICLE_SLOTS[_selected_slot]
	var vehicle_id := str(slot["id"])
	var resolution := VEHICLE_CATALOG.resolve_scene_path(vehicle_id, selected_team)
	if not bool(resolution.get("ok", false)):
		if _status_label != null:
			_status_label.text = "载具场景未登记：%s" % vehicle_id
		return

	# 直接复用 GameAuthority 现有的本地权威入口。它会再次执行完整解析，
	# 因此这里的预览永远不会替代最终的权威检测。
	var mouse_ray_origin := _camera.project_ray_origin(get_viewport().get_mouse_position())
	var mouse_ray_direction := _camera.project_ray_normal(get_viewport().get_mouse_position())
	var request := {
		"player_position": _mouse_target,
		"target_position": _mouse_target,
		"origin": mouse_ray_origin,
		"direction": mouse_ray_direction,
		"yaw": 0.0,
	}
	_placement_serial += 1
	var tool_id := "observer_%s_%d" % [vehicle_id, _placement_serial]
	var raw_result: Variant = GameAuthority.call(
		"_server_place_vehicle_scene",
		GameAuthority.LOCAL_PLAYER_ID,
		request,
		tool_id,
		str(resolution.get("scene_path", ""))
	)
	var result: Dictionary = {}
	if raw_result is Dictionary:
		result = raw_result as Dictionary
	if bool(result.get("ok", false)):
		var mode := str(result.get("spawn_mode", "ground"))
		var position := result.get("position", _mouse_target) as Vector3
		if mode == "airdrop":
			_status_label.text = "%s 已开始空投，落地点：(%0.1f, %0.1f, %0.1f)" % [
				str(slot["label"]), position.x, position.y, position.z
			]
		else:
			_status_label.text = "%s 已放置：(%0.1f, %0.1f, %0.1f)" % [
				str(slot["label"]), position.x, position.y, position.z
			]
	else:
		_status_label.text = "放置失败：%s" % _placement_reason_text(result)
	_preview_dirty = true
	_preview_settle_remaining = PREVIEW_SETTLE_DELAY_SECONDS


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
			_look_active = mouse_event.pressed
			if _look_active:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			if not _look_active:
				_place_selected_vehicle()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseMotion and _look_active:
		var motion := event as InputEventMouseMotion
		_camera_yaw -= motion.screen_relative.x * LOOK_SENSITIVITY
		_camera_pitch -= motion.screen_relative.y * LOOK_SENSITIVITY
		_camera_pitch = clampf(_camera_pitch, deg_to_rad(-85.0), deg_to_rad(-8.0))
		_apply_camera_rotation()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var slot_index := _number_key_to_slot(key_event.physical_keycode)
		if slot_index >= 0:
			_select_slot(slot_index)
			get_viewport().set_input_as_handled()


func _number_key_to_slot(keycode: int) -> int:
	match keycode:
		KEY_1:
			return 0
		KEY_2:
			return 1
		KEY_3:
			return 2
		KEY_4:
			return 3
		KEY_5:
			return 4
		KEY_6:
			return 5
		KEY_7:
			return 6
		KEY_8:
			return 7
		KEY_9:
			return 8
		_:
			return -1
