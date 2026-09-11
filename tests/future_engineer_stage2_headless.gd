extends "res://tests/future_engineer_stage1_headless.gd"

## FutureEngineer 第二阶段 Squad / 多成员推进测试。
##
## 本场景验证随机散布 Crate 的多 Squad 生成和推进：
## - 20-30 个 CrateObject 随机散布在 128m x 128m 测试场地；
## - 中心战略目标附近保留一块连续空地，不生成箱子包围中心；
## - 包围圈内有一个红队五人 FutureWarrior Squad；
## - 包围圈西侧有 20 Bandit 的蓝队 Squad；
## - 包围圈东侧有 20 Bandit 的蓝队 Squad；
## - 红、蓝 Squad 都使用包围圈内部的 Node3D 战略 target；
## - 保留通信消息、导航路径刷新和 Engineer 爆破运行时表现。

const SQUAD_SPAWNER_SCENE := preload("res://character/EnemySquadSpawner.tscn")
const SQUAD_MESSAGE_SCRIPT := preload("res://src/squad_message.gd")
const CRATE_SCENE := preload("res://buildings/CrateObject.tscn")

## 这个半径同时决定两侧蓝队生成器的位置；保持原有出生点不变。
const STAGE2_RING_HALF_EXTENT := 30.0
const STAGE2_TEST_FIELD_HALF_EXTENT := 64.0
const STAGE2_CRATE_COUNT_MIN := 20
const STAGE2_CRATE_COUNT_MAX := 30
const STAGE2_CRATE_EDGE_MARGIN := 4.0
const STAGE2_CRATE_CENTER_CLEAR_RADIUS := 14.0
const STAGE2_CRATE_SPAWN_CLEAR_RADIUS := 8.0
const STAGE2_CRATE_MIN_SEPARATION := 4.2
const STAGE2_CRATE_SIZE := 3.0

@export_category("Stage 2 Squad Test")
@export var stage2_run_on_ready := true
@export var stage2_squad_warrior_debug := true
@export_range(1.0, 10.0, 0.5)
var squad_spawn_radius := 4.0
@export_range(1.0, 600.0, 1.0)
var squad_batch_respawn_seconds := 30.0
## 第二阶段红队防守 AI 的单体复活间隔。
@export_range(1.0, 600.0, 1.0)
var stage2_red_ai_respawn_seconds := 240.0
@export var stage2_show_air_walls := false

## 保留 squad_spawner 作为第一个蓝方生成器的兼容引用；实际测试有三个生成器。
var squad_spawner: EnemySquadSpawner
var red_squad_spawner: EnemySquadSpawner
var blue_squad_spawners: Array[EnemySquadSpawner] = []
var squad_warriors: Array[FutureWarriorAI] = []
var squad_engineers: Array[FutureEngineerAI] = []
var squad_assistants: Array[AssistantAI] = []
var squad_bandits: Array[BanditAI] = []
var red_squad_warriors: Array[FutureWarriorAI] = []
var stage2_area_targets: Array[Node3D] = []
var stage2_red_warriors: Array[FutureWarriorAI] = []
var stage2_red_target: Node3D
var stage2_blue_target: Node3D
var stage2_air_walls: Array[StaticBody3D] = []
var stage2_crates: Array[StaticBody3D] = []
var stage2_elapsed := 0.0
var stage2_communication_log_label: RichTextLabel
var stage2_communication_log_lines: Array[String] = []
var stage2_communication_log_layer: CanvasLayer
@export_range(20, 240, 10)
var stage2_communication_log_max_entries := 120


func _ready() -> void:
	## Stage2 不再沿用 Stage1 的墙体测试参数；保留父类数组为空，避免
	## 旧的“墙体数量”辅助检查误读本场景的 Crate 数量。
	wall_count = 0
	side_wall_count = 0
	if not stage2_run_on_ready:
		return
	call_deferred("_run_stage2_test")


func _physics_process(delta: float) -> void:
	## 阶段二是持续运行的观察场景，不设置测试超时或自动退出。
	stage2_elapsed += delta
	_test_elapsed = stage2_elapsed


func _run_stage2_test() -> void:
	print(
		(
			"[FutureEngineerStage2Test] starting random_crates=%d..%d "
			+ "red_squad=5 warriors blue_squad_west=20 bandits "
			+ "blue_squad_east=20 bandits"
		)
		% [STAGE2_CRATE_COUNT_MIN, STAGE2_CRATE_COUNT_MAX]
	)
	GameAuthority.start_local_mode()
	GlobalVar.gameworld = self
	_build_test_lighting_and_camera()
	_build_stage2_communication_log_ui()
	_build_test_floor()
	_build_stage2_air_walls()
	await _wait_for_test_navigation()
	_build_strategic_target()
	_build_stage2_crates()
	_register_stage2_crates_with_navigation()
	## 箱子加入后只重建它们所在的 64m 导航区块；AI 创建前等待该批完成。
	if test_navigation_grid != null:
		await test_navigation_grid.wait_for_idle()
	_build_stage2_red_future_warriors()
	await get_tree().physics_frame
	_build_blue_squad()
	await get_tree().process_frame

	print("[FutureEngineerStage2Test] running continuously; no automated checks or auto-quit")


func _build_stage2_communication_log_ui() -> void:
	if is_instance_valid(stage2_communication_log_layer):
		return
	stage2_communication_log_layer = CanvasLayer.new()
	stage2_communication_log_layer.name = "Stage2CommunicationLogLayer"
	stage2_communication_log_layer.layer = 50
	add_child(stage2_communication_log_layer)

	var panel := PanelContainer.new()
	panel.name = "SquadCommunicationLogPanel"
	panel.position = Vector2(14.0, 72.0)
	panel.size = Vector2(410.0, 610.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage2_communication_log_layer.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(column)

	var title := Label.new()
	title.text = "Squad 通信 / 导航记录（Stage2）"
	title.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25, 1.0))
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)

	var hint := Label.new()
	hint.text = "通信广播 + 小队AI导航路径刷新（爆破后会广播重新更新导航）"
	hint.add_theme_color_override("font_color", Color(0.72, 0.78, 0.88, 1.0))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(hint)

	stage2_communication_log_label = RichTextLabel.new()
	stage2_communication_log_label.name = "CommunicationLog"
	stage2_communication_log_label.bbcode_enabled = false
	stage2_communication_log_label.fit_content = false
	stage2_communication_log_label.scroll_active = true
	stage2_communication_log_label.scroll_following = true
	stage2_communication_log_label.custom_minimum_size = Vector2(380.0, 550.0)
	stage2_communication_log_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(stage2_communication_log_label)
	_refresh_stage2_communication_log()


func _connect_stage2_communication_log(channel: Node, target_node: Node3D = null) -> void:
	if not is_instance_valid(channel) or not channel.has_signal("message_broadcast"):
		return
	if not channel.message_broadcast.is_connected(_on_stage2_message_broadcast):
		channel.message_broadcast.connect(_on_stage2_message_broadcast)
	## EnemySquad 在生成时已经广播过一次设置 target；补一条当前快照，
	## 让测试界面的记录从第一条通信状态开始可读。
	var snapshot_target := target_node if is_instance_valid(target_node) else target
	if is_instance_valid(snapshot_target):
		_append_stage2_communication_line(
			"设置target | sender=%s | target=%s | initial snapshot"
			% [str(channel.get_parent().name), snapshot_target.name]
		)


func _connect_stage2_navigation_log() -> void:
	## 这是测试界面的本地诊断订阅，不使用 SquadCommunicationChannel。
	for member in red_squad_warriors:
		_connect_stage2_navigation_log_member(member)
	for member in squad_warriors:
		_connect_stage2_navigation_log_member(member)
	for member in squad_engineers:
		_connect_stage2_navigation_log_member(member)
	for member in squad_assistants:
		_connect_stage2_navigation_log_member(member)
	for member in squad_bandits:
		_connect_stage2_navigation_log_member(member)


func _connect_stage2_navigation_log_member(member: Node) -> void:
	if not is_instance_valid(member) or not member.has_signal("navigation_path_refreshed"):
		return
	var callback := Callable(self, "_on_stage2_navigation_path_refreshed").bind(member)
	if not member.navigation_path_refreshed.is_connected(callback):
		member.navigation_path_refreshed.connect(callback)


func _on_stage2_navigation_path_refreshed(
	chunk_ids: Array,
	was_stuck: bool,
	member: Node,
) -> void:
	if not is_instance_valid(member):
		return
	var stuck_text := "是" if was_stuck else "否"
	var refresh_detail := (
		"卡住后重试导航"
		if chunk_ids.is_empty()
		else "dirty_chunks=%s" % str(chunk_ids)
	)
	_append_stage2_communication_line(
		"导航路径更新 | member=%s | 困住=%s | %s"
		% [member.name, stuck_text, refresh_detail]
	)


func _on_stage2_message_broadcast(message: Dictionary) -> void:
	var message_type := int(message.get("type", -1))
	var type_name := SQUAD_MESSAGE_SCRIPT.type_name(message_type)
	var sender := str(message.get("sender_member_id", ""))
	var request_id := str(message.get("request_id", ""))
	var reply_to := str(message.get("reply_to", ""))
	var payload: Dictionary = message.get("payload", {})
	var details := ""
	if payload.has("target"):
		var target_node := payload.get("target") as Node3D
		details = "target=%s" % (target_node.name if is_instance_valid(target_node) else "invalid")
	elif payload.has("position"):
		var position: Variant = payload.get("position")
		if position is Vector3:
			details = "position=(%.1f, %.1f, %.1f)" % [position.x, position.y, position.z]
		if payload.has("radius"):
			details += " radius=%.1fm" % float(payload.get("radius", 0.0))
	elif payload.has("member_id"):
		details = "member=%s" % str(payload.get("member_id", ""))
	var line := "%s | sender=%s" % [type_name, sender]
	if not request_id.is_empty():
		line += " | request=%s" % request_id
	if not reply_to.is_empty():
		line += " | reply=%s" % reply_to
	if not details.is_empty():
		line += " | " + details
	_append_stage2_communication_line(line)


func _append_stage2_communication_line(line: String) -> void:
	stage2_communication_log_lines.append(
		"[%06.2f] %s" % [stage2_elapsed, line]
	)
	while stage2_communication_log_lines.size() > stage2_communication_log_max_entries:
		stage2_communication_log_lines.pop_front()
	_refresh_stage2_communication_log()


func _refresh_stage2_communication_log() -> void:
	if is_instance_valid(stage2_communication_log_label):
		stage2_communication_log_label.text = "\n".join(stage2_communication_log_lines)


func _build_strategic_target() -> void:
	## 红、蓝 Squad 各自持有一个真实 Node3D target；两个点都在防线内部。
	stage2_area_targets.clear()
	stage2_red_target = _create_stage2_target(
		"Stage2_RedSquadTarget_Inside",
		Vector3(0.0, 0.0, 6.0),
		Color(0.88, 0.08, 0.12, 0.95),
	)
	stage2_blue_target = _create_stage2_target(
		"Stage2_BlueSquadTarget_Inside",
		Vector3(0.0, 0.0, -6.0),
		Color(0.12, 0.45, 1.0, 0.95),
	)
	## 父类/旧测试辅助接口使用 target 表示蓝方战略目标。
	target = stage2_blue_target
	stage2_area_targets.append(stage2_red_target)
	stage2_area_targets.append(stage2_blue_target)


func _create_stage2_target(target_name: String, position: Vector3, color: Color) -> Node3D:
	var target_node := Node3D.new()
	target_node.name = target_name
	target_node.add_to_group("squad_target_points")
	target_node.set_meta("target_id", target_name)
	add_child(target_node)
	target_node.global_position = position

	var marker := MeshInstance3D.new()
	marker.name = "TargetMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.75
	marker_mesh.bottom_radius = 0.75
	marker_mesh.height = 0.12
	marker.mesh = marker_mesh
	marker.position.y = 0.06
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color * 0.55
	marker.material_override = material
	target_node.add_child(marker)
	return target_node


func _build_test_lighting_and_camera() -> void:
	super._build_test_lighting_and_camera()
	var camera := get_node_or_null("Stage1TestCamera") as Camera3D
	if camera == null:
		return
	## 默认从场地外的高处观察整个方形包围圈；仍可用测试相机的自由移动和鼠标旋转。
	camera.global_position = Vector3(52.0, 45.0, 52.0)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _build_stage2_red_future_warriors() -> void:
	## 红队成员也由 SquadSpawner 生成，死亡后按整批重生，不再独立复活。
	red_squad_warriors.clear()
	stage2_red_warriors.clear()
	red_squad_spawner = _create_stage2_spawner(
		"stage2_red_squad",
		"red",
		PackedStringArray([
			"future_warrior",
			"future_warrior",
			"future_warrior",
			"future_warrior",
			"future_warrior",
		]),
		stage2_red_target,
		Vector3(0.0, 0.02, 14.0),
		stage2_red_ai_respawn_seconds,
	)
	if not is_instance_valid(red_squad_spawner) or not is_instance_valid(red_squad_spawner.active_squad):
		push_error("[FutureEngineerStage2Test] red Squad did not spawn")
		return
	for member in red_squad_spawner.active_squad.get_member_nodes():
		if member is FutureWarriorAI and not (member is FutureEngineerAI or member is BanditAI):
			var warrior := member as FutureWarriorAI
			warrior.respawn_seconds = stage2_red_ai_respawn_seconds
			warrior.print_decisions = false
			red_squad_warriors.append(warrior)
	stage2_red_warriors.clear()
	stage2_red_warriors.append_array(red_squad_warriors)
	_connect_stage2_communication_log(
		red_squad_spawner.active_squad.communication_channel,
		stage2_red_target,
	)
	print(
		"[FutureEngineerStage2Test] red Squad spawned Warriors=%d target=%s spawn=%s"
		% [red_squad_warriors.size(), _target_name(stage2_red_target), _format_position(red_squad_spawner.global_position)]
	)


func _create_stage2_spawner(
	spawner_id_value: String,
	team_value: String,
	roles: PackedStringArray,
	target_node: Node3D,
	spawn_position: Vector3,
	respawn_seconds_value: float,
) -> EnemySquadSpawner:
	var spawner := SQUAD_SPAWNER_SCENE.instantiate() as EnemySquadSpawner
	if spawner == null:
		push_error("[FutureEngineerStage2Test] cannot instantiate SquadSpawner %s" % spawner_id_value)
		return null
	spawner.name = "EnemySquadSpawner_%s" % spawner_id_value
	spawner.spawner_id = spawner_id_value
	spawner.team_id = team_value
	spawner.member_roles = roles
	spawner.target_node = target_node
	spawner.spawn_radius = squad_spawn_radius
	spawner.respawn_seconds = respawn_seconds_value
	spawner.console_debug_enabled = true
	add_child(spawner)
	spawner.global_position = spawn_position
	spawner.activate_runtime_spawning()
	spawner.set_gameplay_enabled(true)
	return spawner


func _build_stage2_crates() -> void:
	## Crate 是测试场景中的普通导航障碍，不加入 ai_demolition_target，
	## 因此 Engineer 不会把它误认成可爆破的五种防御设施。
	walls.clear()
	all_walls.clear()
	wall_destroyed_flags.clear()
	wall_destroy_positions.clear()
	wall_destroy_times.clear()
	stage2_crates.clear()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var desired_count := rng.randi_range(STAGE2_CRATE_COUNT_MIN, STAGE2_CRATE_COUNT_MAX)
	var min_coordinate := -STAGE2_TEST_FIELD_HALF_EXTENT + STAGE2_CRATE_EDGE_MARGIN
	var max_coordinate := STAGE2_TEST_FIELD_HALF_EXTENT - STAGE2_CRATE_EDGE_MARGIN
	var reserved_spawn_points: Array[Vector2] = [
		Vector2(-STAGE2_RING_HALF_EXTENT, 0.0),
		Vector2(STAGE2_RING_HALF_EXTENT, 0.0),
		Vector2(0.0, 14.0),
	]
	var max_attempts := desired_count * 160
	var attempts := 0
	while stage2_crates.size() < desired_count and attempts < max_attempts:
		attempts += 1
		var candidate := Vector2(
			rng.randf_range(min_coordinate, max_coordinate),
			rng.randf_range(min_coordinate, max_coordinate),
		)
		## 中心战略目标周围始终保留一块连续空地，所以不会形成环形包围。
		if candidate.length() < STAGE2_CRATE_CENTER_CLEAR_RADIUS:
			continue
		var too_close_to_spawn := false
		for spawn_point in reserved_spawn_points:
			if candidate.distance_to(spawn_point) < STAGE2_CRATE_SPAWN_CLEAR_RADIUS:
				too_close_to_spawn = true
				break
		if too_close_to_spawn:
			continue
		var too_close_to_crate := false
		for crate in stage2_crates:
			if not is_instance_valid(crate):
				continue
			var crate_position := Vector2(crate.global_position.x, crate.global_position.z)
			if candidate.distance_to(crate_position) < STAGE2_CRATE_MIN_SEPARATION:
				too_close_to_crate = true
				break
		if too_close_to_crate:
			continue
		var crate := CRATE_SCENE.instantiate() as StaticBody3D
		if crate == null:
			push_error("[FutureEngineerStage2Test] cannot instantiate CrateObject")
			break
		crate.name = "Crate_Stage2_Random_%02d" % (stage2_crates.size() + 1)
		crate.collision_layer = GameAuthority.COLLISION_LAYER_WALL
		crate.collision_mask = GameAuthority.COLLISION_LAYER_CHARACTER
		crate.position = Vector3(candidate.x, 0.0, candidate.y)
		crate.rotation.y = rng.randf_range(-PI, PI)
		crate.add_to_group("ai_navigation_obstacle")
		crate.set_meta("stage2_random_crate", true)
		_add_stage2_crate_collision(crate)
		_add_stage2_crate_navigation_obstacle(crate)
		add_child(crate)
		## The transform is set before registration so the dynamic grid marks
		## the correct dirty chunk immediately.
		crate.global_position = Vector3(candidate.x, 0.0, candidate.y)
		stage2_crates.append(crate)

	print(
		"[FutureEngineerStage2Test] random CrateObject created=%d requested=%d center_clear=%.1fm attempts=%d"
		% [stage2_crates.size(), desired_count, STAGE2_CRATE_CENTER_CLEAR_RADIUS, attempts]
	)


func _add_stage2_crate_collision(crate: StaticBody3D) -> void:
	var collision := CollisionShape3D.new()
	collision.name = "Stage2CrateCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(STAGE2_CRATE_SIZE, STAGE2_CRATE_SIZE, STAGE2_CRATE_SIZE)
	collision.shape = shape
	collision.position = Vector3(0.0, STAGE2_CRATE_SIZE * 0.5, 0.0)
	crate.add_child(collision)


func _add_stage2_crate_navigation_obstacle(crate: StaticBody3D) -> void:
	var obstacle := NavigationObstacle3D.new()
	obstacle.name = "NavigationObstacle3D"
	obstacle.affect_navigation_mesh = true
	obstacle.carve_navigation_mesh = true
	obstacle.avoidance_enabled = true
	obstacle.height = STAGE2_CRATE_SIZE
	var half_size := STAGE2_CRATE_SIZE * 0.5 + 0.1
	obstacle.vertices = PackedVector3Array([
		Vector3(-half_size, 0.0, -half_size),
		Vector3(half_size, 0.0, -half_size),
		Vector3(half_size, 0.0, half_size),
		Vector3(-half_size, 0.0, half_size),
	])
	crate.add_child(obstacle)


func _build_test_floor() -> void:
	## 128m x 128m 的正方形测试场地：包围圈外两侧仍有足够的蓝方生成空间。
	test_floor = StaticBody3D.new()
	test_floor.name = "Stage2TestFloor"
	test_floor.collision_layer = 1
	test_floor.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		STAGE2_TEST_FIELD_HALF_EXTENT * 2.0,
		0.1,
		STAGE2_TEST_FIELD_HALF_EXTENT * 2.0,
	)
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, -0.05, 0.0)
	test_floor.add_child(shape_node)
	add_child(test_floor)

	var mesh_node := MeshInstance3D.new()
	mesh_node.name = "Stage2TestGroundMesh"
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_node.mesh = mesh
	mesh_node.position = shape_node.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.20, 0.13, 1.0)
	mesh_node.material_override = material
	add_child(mesh_node)
	mesh_node.add_to_group("navigation_ground")

	test_navigation_grid = DynamicNavigationChunkGrid.new()
	test_navigation_grid.name = "Stage2DynamicNavigationChunkGrid"
	test_navigation_grid.map_origin = Vector2(
		-STAGE2_TEST_FIELD_HALF_EXTENT,
		-STAGE2_TEST_FIELD_HALF_EXTENT,
	)
	test_navigation_grid.map_size = Vector2(
		STAGE2_TEST_FIELD_HALF_EXTENT * 2.0,
		STAGE2_TEST_FIELD_HALF_EXTENT * 2.0,
	)
	test_navigation_grid.chunk_size = 64.0
	test_navigation_grid.fallback_ground_y = 0.0
	add_child(test_navigation_grid)


func _build_stage2_air_walls() -> void:
	## 正方形测试场地的四面不可见空气墙，碰撞层统一为 Wall。
	## 这四面墙是不可见的边界碰撞体，不加入 ai_demolition_target，
	## 只用于防止测试中的 AI / 相机从场地边缘滑出。
	stage2_air_walls.clear()
	var wall_height := 12.0
	var wall_thickness := 1.0
	var wall_y := wall_height * 0.5 - 0.5
	var x_extent := STAGE2_TEST_FIELD_HALF_EXTENT
	var z_min := -STAGE2_TEST_FIELD_HALF_EXTENT
	var z_max := STAGE2_TEST_FIELD_HALF_EXTENT
	var z_center := (z_min + z_max) * 0.5
	_create_stage2_air_wall(
		"Stage2AirWall_North",
		Vector3(0.0, wall_y, z_max + wall_thickness * 0.5),
		Vector3((x_extent + wall_thickness) * 2.0, wall_height, wall_thickness),
	)
	_create_stage2_air_wall(
		"Stage2AirWall_South",
		Vector3(0.0, wall_y, z_min - wall_thickness * 0.5),
		Vector3((x_extent + wall_thickness) * 2.0, wall_height, wall_thickness),
	)
	_create_stage2_air_wall(
		"Stage2AirWall_West",
		Vector3(-x_extent - wall_thickness * 0.5, wall_y, z_center),
		Vector3(wall_thickness, wall_height, z_max - z_min),
	)
	_create_stage2_air_wall(
		"Stage2AirWall_East",
		Vector3(x_extent + wall_thickness * 0.5, wall_y, z_center),
		Vector3(wall_thickness, wall_height, z_max - z_min),
	)
	print(
		"[FutureEngineerStage2Test] air walls created=%d layer=Wall(%d) bounds=x[%s,%s] z[%s,%s]"
		% [
			stage2_air_walls.size(),
			GameAuthority.COLLISION_LAYER_WALL,
			str(-x_extent),
			str(x_extent),
			str(z_min),
			str(z_max),
		]
	)


func _create_stage2_air_wall(
	wall_name: String,
	wall_position: Vector3,
	wall_size: Vector3,
) -> void:
	var body := StaticBody3D.new()
	body.name = wall_name
	body.collision_layer = GameAuthority.COLLISION_LAYER_WALL
	body.collision_mask = 0
	body.set_meta("stage2_air_wall", true)
	add_child(body)
	body.global_position = wall_position
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = wall_size
	collision.shape = shape
	body.add_child(collision)
	stage2_air_walls.append(body)

	if stage2_show_air_walls:
		var marker := MeshInstance3D.new()
		marker.name = "DebugAirWall"
		var mesh := BoxMesh.new()
		mesh.size = wall_size
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.1, 0.55, 1.0, 0.14)
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = material
		marker.mesh = mesh
		body.add_child(marker)


func _register_stage2_crates_with_navigation() -> int:
	## Crate 不是防御设施，不注册到 placed_tool_states，也不进入爆破目标表。
	## 它只注册到动态导航网格，触发所在 64m 区块的局部重建。
	var registered_count := 0
	if not is_instance_valid(test_navigation_grid):
		return registered_count
	for crate in stage2_crates:
		if not is_instance_valid(crate):
			continue
		test_navigation_grid.register_dynamic_obstacle(crate, true)
		registered_count += 1
	print(
		"[FutureEngineerStage2Test] Crate navigation obstacles registered=%d chunks=64m"
		% registered_count
	)
	return registered_count


func _build_blue_squad() -> void:
	squad_warriors.clear()
	squad_engineers.clear()
	squad_assistants.clear()
	squad_bandits.clear()
	blue_squad_spawners.clear()
	var bandit_composition := PackedStringArray()
	for _member_index in range(5):
		bandit_composition.append("bandit")

	## 西侧蓝方 Squad：20 Bandit。
	var west_spawner := _create_stage2_spawner(
		"stage2_blue_west_squad",
		"blue",
		bandit_composition,
		stage2_blue_target,
		Vector3(-STAGE2_RING_HALF_EXTENT - 14.0, 0.02, 0.0),
		squad_batch_respawn_seconds,
	)
	if is_instance_valid(west_spawner):
		blue_squad_spawners.append(west_spawner)

	## 东侧蓝方 Squad：20 Bandit。
	var east_spawner := _create_stage2_spawner(
		"stage2_blue_east_squad",
		"blue",
		bandit_composition,
		stage2_blue_target,
		Vector3(STAGE2_RING_HALF_EXTENT + 14.0, 0.02, 0.0),
		squad_batch_respawn_seconds,
	)
	if is_instance_valid(east_spawner):
		blue_squad_spawners.append(east_spawner)

	if not blue_squad_spawners.is_empty():
		squad_spawner = blue_squad_spawners[0]
	for spawner in blue_squad_spawners:
		if not is_instance_valid(spawner.active_squad):
			continue
		_connect_stage2_communication_log(
			spawner.active_squad.communication_channel,
			stage2_blue_target,
		)
		for member in spawner.active_squad.get_member_nodes():
			if member is BanditAI:
				squad_bandits.append(member as BanditAI)
			elif member is FutureEngineerAI:
				var engineer_member := member as FutureEngineerAI
				engineer_member.max_hp = 125.0
				engineer_member.console_debug_enabled = true
				engineer_member.console_debug_interval = 0.5
				squad_engineers.append(engineer_member)
			elif member is FutureWarriorAI:
				var warrior_member := member as FutureWarriorAI
				warrior_member.print_decisions = stage2_squad_warrior_debug
				squad_warriors.append(warrior_member)
			elif member is AssistantAI:
				var assistant_member := member as AssistantAI
				assistant_member.console_debug_enabled = true
				assistant_member.console_debug_interval = 0.5
				squad_assistants.append(assistant_member)
	_connect_stage2_navigation_log()
	if not squad_engineers.is_empty():
		engineer = squad_engineers[0]
	if not squad_warriors.is_empty():
		blue_warrior = squad_warriors[0]
	print(
		"[FutureEngineerStage2Test] blue Squads spawned count=%d west=%s east=%s target=%s"
		% [blue_squad_spawners.size(), _squad_composition_summary(0), _squad_composition_summary(1), _target_name(stage2_blue_target)]
	)


func _count_member_type(members: Array[Node], type_name: String) -> int:
	var count := 0
	for member in members:
		match type_name:
			"warrior":
				if member is FutureWarriorAI and not (member is FutureEngineerAI or member is BanditAI):
					count += 1
			"engineer":
				if member is FutureEngineerAI:
					count += 1
			"assistant":
				if member is AssistantAI:
					count += 1
			"bandit":
				if member is BanditAI:
					count += 1
	return count


func _squad_composition_summary(index: int) -> String:
	if index < 0 or index >= blue_squad_spawners.size():
		return "invalid"
	var members := blue_squad_spawners[index].active_squad.get_member_nodes()
	return "%dW+%dE+%dA+%dB" % [
		_count_member_type(members, "warrior"),
		_count_member_type(members, "engineer"),
		_count_member_type(members, "assistant"),
		_count_member_type(members, "bandit"),
	]
