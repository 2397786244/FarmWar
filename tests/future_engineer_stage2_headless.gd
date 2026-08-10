extends "res://tests/future_engineer_stage1_headless.gd"

## FutureEngineer 第二阶段 Squad / 多成员推进测试。
##
## 复用第一阶段测试的：
## - 11 道防线及每道防线左右侧阻挡墙；
## - NavigationRegion3D、地面、相机和战略 target；
## - 墙体注册、爆破顺序和入口推进检查基础。
##
## 本阶段额外验证：
## - 第 2/3 道防线之间到最终 target 的每个区域内有 2 个红队 Warrior；
## - 蓝队 EnemySquadSpawner 生成 3 个 Warrior + 2 个 Engineer；
## - 两名 Engineer 使用同一个 Squad 通信频道和同一个 target；
## - FutureEngineer HP=250；
## - 所有 Engineer 炸药任务完成后仍会继续向共同 target 推进。

const SQUAD_SPAWNER_SCENE := preload("res://character/EnemySquadSpawner.tscn")
const SQUAD_MESSAGE_SCRIPT := preload("res://src/squad_message.gd")

@export_category("Stage 2 Squad Test")
@export var stage2_run_on_ready := true
@export_range(30.0, 240.0, 1.0)
var stage2_wait_timeout_seconds := 150.0
@export var stage2_quit_when_complete := false
@export var stage2_squad_warrior_debug := true
@export_range(1.0, 10.0, 0.5)
var squad_spawn_radius := 4.0
@export_range(1.0, 600.0, 1.0)
var squad_batch_respawn_seconds := 30.0
## 第二阶段红队防守 AI 的单体复活间隔。
@export_range(1.0, 600.0, 1.0)
var stage2_red_ai_respawn_seconds := 240.0
@export var stage2_show_air_walls := false

var squad_spawner: EnemySquadSpawner
var squad_warriors: Array[FutureWarriorAI] = []
var squad_engineers: Array[FutureEngineerAI] = []
var stage2_area_targets: Array[Node3D] = []
var stage2_red_warriors: Array[FutureWarriorAI] = []
var stage2_air_walls: Array[StaticBody3D] = []
var stage2_registered_wall_count := 0
var stage2_elapsed := 0.0
var stage2_communication_log_label: RichTextLabel
var stage2_communication_log_lines: Array[String] = []
var stage2_communication_log_layer: CanvasLayer
@export_range(20, 240, 10)
var stage2_communication_log_max_entries := 120


func _ready() -> void:
	if not stage2_run_on_ready:
		return
	call_deferred("_run_stage2_test")


func _run_stage2_test() -> void:
	print(
		(
			"[FutureEngineerStage2Test] starting defense_lines=%d side_walls_each_side=%d "
			+ "red_warriors_per_area=2 squad_warriors=3 squad_engineers=2"
		)
		% [wall_count, side_wall_count]
	)
	GameAuthority.start_local_mode()
	GlobalVar.gameworld = self
	_build_test_lighting_and_camera()
	_build_stage2_communication_log_ui()
	_build_test_floor()
	_build_stage2_air_walls()
	await _wait_for_test_navigation()
	_build_strategic_target()
	_build_demolition_walls()
	## 11 条防线加入后会触发相交导航区块的批量局部重建；AI 创建前等待该批完成。
	if test_navigation_grid != null:
		await test_navigation_grid.wait_for_idle()
	stage2_registered_wall_count = _register_stage2_walls_with_authority()
	_build_stage2_red_future_warriors()
	await get_tree().physics_frame
	_build_blue_squad()
	await get_tree().process_frame

	var checks_passed := 0
	var checks_total := 0
	checks_total += 1
	if target is Node3D and is_instance_valid(target):
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS shared strategic target is Node3D")
	else:
		push_error("[FutureEngineerStage2Test] FAIL strategic target is invalid")

	checks_total += 1
	if all_walls.size() == _total_wall_segments() and walls.size() == wall_count:
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS 11 defense lines and side walls=%d" % all_walls.size())
	else:
		push_error(
			"[FutureEngineerStage2Test] FAIL wall layout lines=%d/%d total=%d/%d"
			% [walls.size(), wall_count, all_walls.size(), _total_wall_segments()]
		)

	checks_total += 1
	if stage2_registered_wall_count == _total_wall_segments():
		checks_passed += 1
		print(
			"[FutureEngineerStage2Test] PASS registered walls=%d/%d in GameAuthority"
			% [stage2_registered_wall_count, _total_wall_segments()]
		)
	else:
		push_error(
			"[FutureEngineerStage2Test] FAIL registered walls=%d/%d in GameAuthority"
			% [stage2_registered_wall_count, _total_wall_segments()]
		)

	checks_total += 1
	if _stage2_air_walls_are_configured():
		checks_passed += 1
		print(
			"[FutureEngineerStage2Test] PASS air walls=%d collision_layer=Wall(%d)"
			% [stage2_air_walls.size(), GameAuthority.COLLISION_LAYER_WALL]
		)
	else:
		push_error("[FutureEngineerStage2Test] FAIL air wall boundary configuration")

	checks_total += 1
	if stage2_red_warriors.size() == _expected_stage2_red_warrior_count() \
			and _stage2_red_warriors_are_configured():
		checks_passed += 1
		print(
			"[FutureEngineerStage2Test] PASS red FutureWarriors=%d areas=%d per_area=2"
			% [stage2_red_warriors.size(), stage2_area_targets.size()]
		)
	else:
		push_error(
			"[FutureEngineerStage2Test] FAIL red FutureWarriors=%d expected=%d targets=%d"
			% [
				stage2_red_warriors.size(),
				_expected_stage2_red_warrior_count(),
				stage2_area_targets.size(),
			]
		)

	checks_total += 1
	if stage2_red_warriors.all(func(member: FutureWarriorAI) -> bool:
		return is_equal_approx(member.respawn_seconds, stage2_red_ai_respawn_seconds)
	):
		checks_passed += 1
		print(
			"[FutureEngineerStage2Test] PASS red FutureWarriors respawn=%.0fs"
			% stage2_red_ai_respawn_seconds
		)
	else:
		push_error(
			"[FutureEngineerStage2Test] FAIL red FutureWarriors respawn expected=%.1fs values=%s"
			% [stage2_red_ai_respawn_seconds, _red_warrior_respawn_summary()]
		)

	checks_total += 1
	if _squad_has_expected_composition():
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS Squad composition Warrior=3 Engineer=2")
	else:
		push_error("[FutureEngineerStage2Test] FAIL Squad composition is not 3 Warrior + 2 Engineer")

	checks_total += 1
	if _squad_warning_distance_is_configured():
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS demolition warning retreat distance=10m")
	else:
		push_error("[FutureEngineerStage2Test] FAIL demolition warning retreat distance is below 10m")

	checks_total += 1
	if _squad_members_share_target_and_navigation():
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS Squad members share target, Navigation and avoidance")
	else:
		push_error("[FutureEngineerStage2Test] FAIL Squad target/navigation configuration")

	checks_total += 1
	if _stage2_communication_log_is_configured():
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS left communication log connected")
	else:
		push_error("[FutureEngineerStage2Test] FAIL left communication log is not connected")

	checks_total += 1
	if _stage2_navigation_log_is_configured():
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS left navigation refresh log connected")
	else:
		push_error("[FutureEngineerStage2Test] FAIL left navigation refresh log is not connected")

	checks_total += 1
	if squad_engineers.size() == 2 and squad_engineers.all(func(member: FutureEngineerAI) -> bool:
		return is_equal_approx(member.max_hp, 250.0)
	):
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS FutureEngineer HP=250 for both Engineers")
	else:
		push_error("[FutureEngineerStage2Test] FAIL FutureEngineer HP is not 250")

	var saw_demolition := false
	var saw_bomb := false
	var previous_destroyed_count := 0
	var previous_bomb_count := _total_remaining_explosives()
	var final_forward_progress := false
	var elapsed := 0.0
	while elapsed < stage2_wait_timeout_seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		stage2_elapsed = elapsed
		_refresh_destroyed_wall_flags()
		for member in squad_engineers:
			if not is_instance_valid(member):
				continue
			if member.demolition_target != null or member.demolition_phase != FutureEngineerAI.DemolitionPhase.NONE:
				saw_demolition = true
			if is_instance_valid(member.active_remote_bomb):
				saw_bomb = true

		var current_destroyed_count := _destroyed_wall_count()
		var current_bomb_count := _total_remaining_explosives()
		if current_bomb_count < previous_bomb_count:
			print(
				"[FutureEngineerStage2Test] bombs_planted=%d remaining=%d"
				% [previous_bomb_count - current_bomb_count, current_bomb_count]
			)
			previous_bomb_count = current_bomb_count
		if current_destroyed_count > previous_destroyed_count:
			print(
				"[FutureEngineerStage2Test] progress destroyed=%d/%d engineer_positions=%s"
				% [current_destroyed_count, wall_count, _engineer_position_summary()]
			)
			previous_destroyed_count = current_destroyed_count

		if current_destroyed_count >= wall_count:
			var last_line_z := _defense_line_center(wall_count - 1).z
			for member in squad_engineers:
				if is_instance_valid(member) and member.global_position.z < last_line_z - 1.0:
					final_forward_progress = true
			if final_forward_progress:
				break

	checks_total += 1
	if saw_demolition:
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS Squad Engineer entered demolition flow")
	else:
		push_error("[FutureEngineerStage2Test] FAIL no Engineer entered demolition flow")

	checks_total += 1
	if saw_bomb:
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS Squad Engineer planted RemoteBomb")
	else:
		push_error("[FutureEngineerStage2Test] FAIL no RemoteBomb was planted")

	checks_total += 1
	if _destroyed_wall_count() == wall_count:
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS all 11 defense lines destroyed")
	else:
		push_error(
			"[FutureEngineerStage2Test] FAIL destroyed walls=%d/%d"
			% [_destroyed_wall_count(), wall_count]
		)

	checks_total += 1
	if _is_forward_progress_ordered(wall_count):
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS demolition progress follows defense order")
	else:
		push_error("[FutureEngineerStage2Test] FAIL demolition progress order=%s" % _destroy_position_summary())

	checks_total += 1
	if final_forward_progress:
		checks_passed += 1
		print("[FutureEngineerStage2Test] PASS Squad continued toward target after final demolition")
	else:
		push_error("[FutureEngineerStage2Test] FAIL Squad did not continue toward target")

	print(
		"[FutureEngineerStage2Test] result=%d/%d walls_destroyed=%d/%d elapsed=%.1fs"
		% [checks_passed, checks_total, _destroyed_wall_count(), wall_count, elapsed]
	)
	if checks_passed == checks_total:
		print("[FutureEngineerStage2Test] COMPLETE")
	else:
		push_error("[FutureEngineerStage2Test] FAILED")

	for member in squad_warriors:
		if is_instance_valid(member):
			member.set_physics_process(false)
			member.set_process(false)
	for member in squad_engineers:
		if is_instance_valid(member):
			member.set_physics_process(false)
			member.set_process(false)
	if stage2_quit_when_complete or DisplayServer.get_name() == "headless":
		get_tree().quit(0 if checks_passed == checks_total else 1)


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
	hint.text = "通信广播 + 小队AI导航路径刷新（导航刷新不发送通信消息）"
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


func _connect_stage2_communication_log(channel: Node) -> void:
	if not is_instance_valid(channel) or not channel.has_signal("message_broadcast"):
		return
	if not channel.message_broadcast.is_connected(_on_stage2_message_broadcast):
		channel.message_broadcast.connect(_on_stage2_message_broadcast)
	## EnemySquad 在生成时已经广播过一次设置 target；补一条当前快照，
	## 让测试界面的记录从第一条通信状态开始可读。
	if is_instance_valid(target):
		_append_stage2_communication_line(
			"设置target | sender=squad | target=%s | initial snapshot" % target.name
		)


func _connect_stage2_navigation_log() -> void:
	## 这是测试界面的本地诊断订阅，不使用 SquadCommunicationChannel。
	for member in squad_warriors:
		_connect_stage2_navigation_log_member(member)
	for member in squad_engineers:
		_connect_stage2_navigation_log_member(member)


func _connect_stage2_navigation_log_member(member: FutureWarriorAI) -> void:
	if not is_instance_valid(member) or not member.has_signal("navigation_path_refreshed"):
		return
	var callback := Callable(self, "_on_stage2_navigation_path_refreshed").bind(member)
	if not member.navigation_path_refreshed.is_connected(callback):
		member.navigation_path_refreshed.connect(callback)


func _on_stage2_navigation_path_refreshed(
	chunk_ids: Array,
	was_stuck: bool,
	member: FutureWarriorAI,
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
		"导航路径更新（非通信） | member=%s | 困住=%s | %s"
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


func _build_stage2_red_future_warriors() -> void:
	stage2_red_warriors.clear()
	stage2_area_targets.clear()
	var area_number := 0
	for line_index in range(RED_WARRIOR_FIRST_AREA_LINE_INDEX, maxi(RED_WARRIOR_FIRST_AREA_LINE_INDEX, wall_count - 1)):
		var area_center := _area_center_between(
			_defense_line_center(line_index),
			_defense_line_center(line_index + 1),
		)
		_spawn_stage2_red_area("Area_%02d_%02d" % [line_index + 1, line_index + 2], area_center, area_number)
		area_number += 1
	if wall_count > 0 and is_instance_valid(target):
		var final_center := _area_center_between(_defense_line_center(wall_count - 1), target.global_position)
		_spawn_stage2_red_area("Area_%02d_Target" % wall_count, final_center, area_number)
	print(
		"[FutureEngineerStage2Test] red FutureWarriors spawned=%d areas=%d per_area=2"
		% [stage2_red_warriors.size(), stage2_area_targets.size()]
	)


func _build_stage2_air_walls() -> void:
	## 测试地面范围与第一阶段保持一致：x=-20..20，z=-118..22。
	## 这四面墙是不可见的边界碰撞体，不加入 ai_demolition_target，
	## 只用于防止测试中的 AI / 相机从场地边缘滑出。
	stage2_air_walls.clear()
	var wall_height := 12.0
	var wall_thickness := 1.0
	var wall_y := wall_height * 0.5 - 0.5
	var x_extent := 20.0
	var z_min := -118.0
	var z_max := 22.0
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


func _stage2_air_walls_are_configured() -> bool:
	if stage2_air_walls.size() != 4:
		return false
	for wall in stage2_air_walls:
		if not is_instance_valid(wall):
			return false
		if wall.collision_layer != GameAuthority.COLLISION_LAYER_WALL:
			return false
		if wall.collision_mask != 0:
			return false
		if wall.is_in_group("ai_demolition_target"):
			return false
		var collision := wall.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collision == null or collision.shape == null:
			return false
	return true


func _register_stage2_walls_with_authority() -> int:
	## RemoteBomb 的权威爆炸通过 placed_tool_states 扫描建筑；
	## 测试场景动态创建的墙也必须走和真实地图相同的注册入口。
	var registered_count := 0
	for index in range(all_walls.size()):
		var wall := all_walls[index]
		if not is_instance_valid(wall):
			continue
		if GameAuthority.register_map_placed_tool(
			wall,
			"tall_log_wall",
			"stage2:test_tall_log_wall_segment_%03d" % (index + 1),
			"red",
		):
			registered_count += 1
	return registered_count


func _spawn_stage2_red_area(area_name: String, area_center: Vector3, area_number: int) -> void:
	var area_target := Node3D.new()
	area_target.name = "RedFutureWarriorTarget_Stage2_%s" % area_name
	area_target.set_meta("stage2_target_area_center", true)
	add_child(area_target)
	area_target.global_position = area_center
	stage2_area_targets.append(area_target)
	var marker := MeshInstance3D.new()
	marker.name = "TargetMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.35
	marker_mesh.bottom_radius = 0.35
	marker_mesh.height = 0.06
	marker.mesh = marker_mesh
	marker.position.y = 0.03
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.85, 0.08, 0.12, 0.75)
	material.emission_enabled = true
	material.emission = Color(0.45, 0.01, 0.02, 1.0)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = material
	area_target.add_child(marker)

	_spawn_stage2_red_warrior(area_name, area_target, area_center + Vector3(-3.0, 0.02, 0.0), area_number, 1)
	_spawn_stage2_red_warrior(area_name, area_target, area_center + Vector3(3.0, 0.02, 0.0), area_number, 2)


func _spawn_stage2_red_warrior(
	area_name: String,
	area_target: Node3D,
	spawn_position: Vector3,
	area_number: int,
	member_number: int,
) -> void:
	var warrior := FUTURE_WARRIOR_SCENE.instantiate() as FutureWarriorAI
	if warrior == null:
		push_error("[FutureEngineerStage2Test] cannot instantiate red FutureWarrior %s" % area_name)
		return
	warrior.name = "FutureWarrior_Red_Stage2_%s_%02d" % [area_name, member_number]
	warrior.team_id = "red"
	warrior.target = area_target
	warrior.respawn_seconds = stage2_red_ai_respawn_seconds
	warrior.use_navigation_agent = true
	warrior.print_decisions = false
	warrior.set_meta("stage2_area_number", area_number + 1)
	warrior.set_meta("stage2_target_area_center", area_target.global_position)
	add_child(warrior)
	warrior.global_position = spawn_position
	stage2_red_warriors.append(warrior)


func _red_warrior_respawn_summary() -> String:
	var values: Array[String] = []
	for warrior in stage2_red_warriors:
		if is_instance_valid(warrior):
			values.append("%s=%.1fs" % [warrior.name, warrior.respawn_seconds])
	return ", ".join(values)


func _build_blue_squad() -> void:
	squad_spawner = SQUAD_SPAWNER_SCENE.instantiate() as EnemySquadSpawner
	if squad_spawner == null:
		push_error("[FutureEngineerStage2Test] cannot instantiate EnemySquadSpawner")
		return
	squad_spawner.name = "EnemySquadSpawner_Stage2_Test"
	squad_spawner.spawner_id = "stage2_blue_squad"
	squad_spawner.team_id = "blue"
	squad_spawner.member_roles = PackedStringArray([
		"future_warrior",
		"future_warrior",
		"future_warrior",
		"future_engineer",
		"future_engineer",
	])
	squad_spawner.target_node = target
	squad_spawner.spawn_radius = squad_spawn_radius
	squad_spawner.respawn_seconds = squad_batch_respawn_seconds
	squad_spawner.console_debug_enabled = true
	add_child(squad_spawner)
	squad_spawner.global_position = Vector3(0.0, 0.02, 0.8)
	squad_spawner.activate_runtime_spawning()
	squad_spawner.set_gameplay_enabled(true)

	if not is_instance_valid(squad_spawner.active_squad):
		return
	_connect_stage2_communication_log(squad_spawner.active_squad.communication_channel)
	for member in squad_spawner.active_squad.get_member_nodes():
		if member is FutureEngineerAI:
			var engineer_member := member as FutureEngineerAI
			engineer_member.console_debug_enabled = true
			engineer_member.console_debug_interval = 0.5
			squad_engineers.append(engineer_member)
		elif member is FutureWarriorAI:
			var warrior_member := member as FutureWarriorAI
			warrior_member.print_decisions = stage2_squad_warrior_debug
			squad_warriors.append(warrior_member)
	_connect_stage2_navigation_log()
	if not squad_engineers.is_empty():
		engineer = squad_engineers[0]
	if not squad_warriors.is_empty():
		blue_warrior = squad_warriors[0]
	print(
		"[FutureEngineerStage2Test] blue Squad spawned Warrior=%d Engineer=%d target=%s"
		% [squad_warriors.size(), squad_engineers.size(), _target_name(target)]
	)


func _expected_stage2_red_warrior_count() -> int:
	return stage2_area_targets.size() * 2


func _stage2_red_warriors_are_configured() -> bool:
	for warrior in stage2_red_warriors:
		if not is_instance_valid(warrior) or warrior.team_id != "red" or not warrior.use_navigation_agent:
			return false
		if not warrior.target is Node3D or not warrior.target in stage2_area_targets:
			return false
	return true


func _squad_has_expected_composition() -> bool:
	return is_instance_valid(squad_spawner) \
		and is_instance_valid(squad_spawner.active_squad) \
		and squad_warriors.size() == 3 \
		and squad_engineers.size() == 2


func _squad_warning_distance_is_configured() -> bool:
	if not is_instance_valid(squad_spawner) or not is_instance_valid(squad_spawner.active_squad):
		return false
	var channel := squad_spawner.active_squad.communication_channel
	if not is_instance_valid(channel) or float(channel.demolition_warning_radius) < 10.0:
		return false
	for member in squad_spawner.active_squad.get_member_nodes():
		if member is FutureWarriorAI and float(member.squad_warning_retreat_distance) < 10.0:
			return false
		if member is FutureEngineerAI and float(member.remote_bomb_safe_distance) < 10.0:
			return false
	return true


func _squad_members_share_target_and_navigation() -> bool:
	for member in squad_warriors:
		if member.target != target or not member.use_navigation_agent:
			return false
		if member.navigation_agent == null or not member.navigation_agent.avoidance_enabled:
			return false
	for member in squad_engineers:
		if member.target != target or not member.use_navigation_agent:
			return false
		if member.navigation_agent == null or not member.navigation_agent.avoidance_enabled:
			return false
	return true


func _stage2_communication_log_is_configured() -> bool:
	return (
		is_instance_valid(stage2_communication_log_label)
		and is_instance_valid(squad_spawner)
		and is_instance_valid(squad_spawner.active_squad)
		and is_instance_valid(squad_spawner.active_squad.communication_channel)
		and squad_spawner.active_squad.communication_channel.has_signal("message_broadcast")
		and squad_spawner.active_squad.communication_channel.message_broadcast.is_connected(
			_on_stage2_message_broadcast
		)
	)


func _stage2_navigation_log_is_configured() -> bool:
	if not is_instance_valid(stage2_communication_log_label):
		return false
	if squad_warriors.is_empty() and squad_engineers.is_empty():
		return false
	for member in squad_warriors:
		if not _stage2_navigation_log_member_is_configured(member):
			return false
	for member in squad_engineers:
		if not _stage2_navigation_log_member_is_configured(member):
			return false
	return true


func _stage2_navigation_log_member_is_configured(member: FutureWarriorAI) -> bool:
	if not is_instance_valid(member) or not member.has_signal("navigation_path_refreshed"):
		return false
	var callback := Callable(self, "_on_stage2_navigation_path_refreshed").bind(member)
	return member.navigation_path_refreshed.is_connected(callback)


func _total_remaining_explosives() -> int:
	var total := 0
	for member in squad_engineers:
		if is_instance_valid(member):
			total += member.explosives_remaining
	return total


func _engineer_position_summary() -> String:
	var values: Array[String] = []
	for member in squad_engineers:
		if is_instance_valid(member):
			values.append("%s:%s" % [member.name, _format_position(member.global_position)])
	return "[" + ", ".join(values) + "]"
