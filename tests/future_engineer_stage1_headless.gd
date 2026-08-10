extends Node3D

## FutureEngineer 第一阶段连续障碍闭环测试。
##
## 这个脚本虽然保留了 headless 文件名，但它是一个普通 Node3D 场景脚本：
## - 可以在 Godot 编辑器中打开对应测试场景后按 F6 执行；
## - 也可以用 Godot 命令行运行该场景；
## - 它会先启动项目已有的 GameAuthority 本地模式，避免直接 --script
##   启动时出现 Autoload 初始化顺序问题。

const ENGINEER_SCENE := preload("res://character/FutureEngineerAI.tscn")
const FUTURE_WARRIOR_SCENE := preload("res://character/FutureWarriorAI.tscn")
const WALL_SCENE := preload("res://character/weapons/TallLogWall.tscn")
const REMOTE_BOMB_SCENE := preload("res://items/RemoteBomb.tscn")
const TEST_CAMERA_SCRIPT := preload("res://src/test_observer_camera.gd")

const WALL_SEGMENT_SPACING := 5.5
## 0-based 防线索引：1 和 2 之间就是第 2、3 道防线之间的区域。
const RED_WARRIOR_FIRST_AREA_LINE_INDEX := 1

@export_category("Stage 1 Test")
@export var run_on_ready := true
@export var force_manual_assignment := false
@export_range(1, 20, 1)
var wall_count := 11
@export_range(2, 3, 1)
var side_wall_count := 3
@export_range(7.0, 20.0, 0.5)
var wall_spacing := 9.0
@export_range(20.0, 240.0, 1.0)
var wait_timeout_seconds := 180.0
@export var quit_when_complete := false
@export var spawn_red_future_warriors := true
@export_range(-16.0, 16.0, 0.5)
var red_warrior_spawn_x := 7.0

var engineer: FutureEngineerAI
var blue_warrior: FutureWarriorAI
var target: Node3D
var test_floor: StaticBody3D
var test_navigation_grid: DynamicNavigationChunkGrid
## walls 只保存每条防线的中间墙，作为 Engineer 的 11 个爆破目标。
var walls: Array[Node3D] = []
## all_walls 保存中间墙及左右侧阻挡墙，用于碰撞、爆炸注册和完整性检查。
var all_walls: Array[Node3D] = []
var wall_destroyed_flags: Array[bool] = []
var wall_destroy_positions: Array[Vector3] = []
var wall_destroy_times: Array[float] = []
var red_future_warriors: Array[FutureWarriorAI] = []
var red_future_warrior_targets: Array[Node3D] = []
var _test_elapsed := 0.0


func _ready() -> void:
	if not run_on_ready:
		return
	call_deferred("_run_stage1_test")


func _run_stage1_test() -> void:
	var start_summary := (
		"[FutureEngineerStage1Test] starting defense_lines=%d side_walls_each_side=%d "
		+ "segments_per_line=%d line_spacing=%.1fm total_segments=%d"
	) % [
			wall_count,
			side_wall_count,
			_wall_segments_per_line(),
			wall_spacing,
			_total_wall_segments(),
	]
	print(start_summary)
	## 测试场景不是 FarmWorldInitializer，因此这里显式提供最小 gameworld 接口。
	GameAuthority.start_local_mode()
	GlobalVar.gameworld = self
	_build_test_lighting_and_camera()
	_build_test_floor()
	## 等待动态 NavigationRegion3D 注册到 NavigationServer3D，确保本测试不会回退直线。
	await _wait_for_test_navigation()
	_build_strategic_target()
	_build_demolition_walls()
	## 墙体创建会把相交的导航区块标记为 dirty；等待本批局部 bake 完成，
	## 再生成 AI，确保测试验证的是带防御设施阻挡的导航。
	if test_navigation_grid != null:
		await test_navigation_grid.wait_for_idle()
	_build_red_future_warriors()
	## 等待墙体的 StaticBody3D 变换同步到物理服务器，再启动 Engineer 的第一帧射线。
	await get_tree().physics_frame
	_build_engineer()
	_build_blue_warrior()
	await get_tree().process_frame
	var expected_demolition_count := mini(wall_count, engineer.explosives_remaining)
	print(
		"[FutureEngineerStage1Test] expected_demolitions=%d/%d because explosives=%d"
		% [expected_demolition_count, wall_count, engineer.explosives_remaining]
	)

	var checks_passed := 0
	var checks_total := 0
	checks_total += 1
	if engineer.target is Node3D and engineer.target == target:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS target is configured Node3D")
	else:
		push_error("[FutureEngineerStage1Test] FAIL target is not the configured Node3D")

	checks_total += 1
	if engineer.held_weapon != null and engineer.held_weapon.name == "FutureMPX":
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS weapon=FutureMPX")
	else:
		push_error("[FutureEngineerStage1Test] FAIL engineer did not equip FutureMPX")

	checks_total += 1
	if is_equal_approx(engineer.max_hp, 250.0):
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS FutureEngineer HP=250")
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL FutureEngineer HP=%.1f expected=250"
			% engineer.max_hp
		)

	checks_total += 1
	if is_instance_valid(blue_warrior) \
			and blue_warrior.team_id == "blue" \
			and blue_warrior.target == target \
			and blue_warrior.target is Node3D \
			and blue_warrior.use_navigation_agent:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS blue FutureWarrior shares target")
	else:
		push_error("[FutureEngineerStage1Test] FAIL blue FutureWarrior target/team setup")

	checks_total += 1
	if engineer.explosives_remaining == 10 and engineer.grenades_remaining == 0:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS explosives=10 grenades=0")
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL inventory explosives=%d grenades=%d"
			% [engineer.explosives_remaining, engineer.grenades_remaining]
		)

	checks_total += 1
	if engineer.use_navigation_agent and engineer.navigation_agent != null \
			and engineer._navigation_map_is_ready():
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS route=navigation NavigationMap ready")
	else:
		push_error("[FutureEngineerStage1Test] FAIL route did not initialize NavigationMap")

	checks_total += 1
	var expected_red_warrior_count := _expected_red_future_warrior_count()
	if red_future_warriors.size() == expected_red_warrior_count \
			and red_future_warrior_targets.size() == expected_red_warrior_count \
			and _red_future_warriors_are_configured():
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS red FutureWarriors=%d target_centers=%d"
			% [red_future_warriors.size(), red_future_warrior_targets.size()]
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL red FutureWarriors=%d/%d targets=%d/%d"
			% [
				red_future_warriors.size(),
				expected_red_warrior_count,
				red_future_warrior_targets.size(),
				expected_red_warrior_count,
			]
		)

	var demolition_group_count := 0
	for wall in all_walls:
		if wall.is_in_group("ai_demolition_target"):
			demolition_group_count += 1
	checks_total += 1
	if demolition_group_count == _total_wall_segments():
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS %d wall segments are demolition targets"
			% demolition_group_count
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL demolition target count=%d/%d segments"
			% [demolition_group_count, _total_wall_segments()]
		)

	## 注册为地图设施，确保爆炸使用与真实地图相同的 Boom 设施伤害路径。
	var registered_count := 0
	for index in range(all_walls.size()):
		var registered := GameAuthority.register_map_placed_tool(
			all_walls[index],
			"tall_log_wall",
			"stage1:test_tall_log_wall_segment_%03d" % (index + 1),
			"red"
		)
		if registered:
			registered_count += 1
	checks_total += 1
	if registered_count == _total_wall_segments():
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS registered %d wall segments in GameAuthority"
			% registered_count
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL wall registration=%d/%d segments"
			% [registered_count, _total_wall_segments()]
		)

	## 默认验证自主发现；打开 force_manual_assignment 可额外验证 Squad 预留入口。
	if force_manual_assignment:
		checks_total += 1
		if engineer.assign_demolition_target(walls[0]):
			checks_passed += 1
			print("[FutureEngineerStage1Test] PASS assign_demolition_target()")
		else:
			push_error("[FutureEngineerStage1Test] FAIL assign_demolition_target()")

	var saw_demolition_phase := false
	var saw_bomb := false
	var bombs_planted := 0
	var previous_explosive_count := engineer.explosives_remaining
	var previous_destroyed_count := 0
	var final_forward_progress := false
	var elapsed := 0.0
	while elapsed < wait_timeout_seconds:
		await get_tree().physics_frame
		elapsed += get_physics_process_delta_time()
		_test_elapsed = elapsed
		_refresh_destroyed_wall_flags()

		if engineer.demolition_target != null:
			saw_demolition_phase = true
		if is_instance_valid(engineer.active_remote_bomb):
			saw_bomb = true
		if engineer.explosives_remaining < previous_explosive_count:
			bombs_planted += previous_explosive_count - engineer.explosives_remaining
			previous_explosive_count = engineer.explosives_remaining

		var destroyed_count := _destroyed_wall_count()
		if destroyed_count > previous_destroyed_count:
			print(
				"[FutureEngineerStage1Test] progress destroyed=%d/%d engineer_pos=%s next_target=%s"
				% [
					destroyed_count,
					wall_count,
					_format_position(engineer.global_position),
					_target_name(engineer.demolition_target),
				]
			)
			previous_destroyed_count = destroyed_count

		if destroyed_count >= expected_demolition_count and expected_demolition_count > 0:
			var last_wall_z := -6.0 - wall_spacing * float(expected_demolition_count - 1)
			## 最后一次可用炸药爆炸后，工程师必须离开爆炸区并继续向 target 推进。
			if engineer.global_position.z < last_wall_z - 1.0:
				final_forward_progress = true
				break

	checks_total += 1
	if saw_demolition_phase:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS engineer entered demolition flow")
	else:
		push_error("[FutureEngineerStage1Test] FAIL engineer never entered demolition flow")

	checks_total += 1
	if saw_bomb:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS remote bombs were planted")
	else:
		push_error("[FutureEngineerStage1Test] FAIL remote bomb was never planted")

	checks_total += 1
	if bombs_planted == expected_demolition_count:
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS bombs_planted=%d/%d usable_walls=%d remaining=%d"
			% [bombs_planted, expected_demolition_count, wall_count, engineer.explosives_remaining]
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL bombs_planted=%d/%d usable_walls=%d remaining=%d"
			% [bombs_planted, expected_demolition_count, wall_count, engineer.explosives_remaining]
		)

	checks_total += 1
	if _destroyed_wall_count() == expected_demolition_count:
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS %d/%d walls destroyed by explosions"
			% [expected_demolition_count, wall_count]
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL destroyed walls=%d expected=%d total=%d"
			% [_destroyed_wall_count(), expected_demolition_count, wall_count]
		)

	checks_total += 1
	var forward_progress := _is_forward_progress_ordered(expected_demolition_count)
	if forward_progress:
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS engineer advanced after each demolition positions=%s"
			% _destroy_position_summary()
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL engineer did not advance between demolitions positions=%s"
			% _destroy_position_summary()
		)

	checks_total += 1
	if final_forward_progress:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS engineer continued toward target after final demolition")
	else:
		push_error("[FutureEngineerStage1Test] FAIL engineer stopped after final demolition")

	checks_total += 1
	var expected_remaining_explosives := maxi(0, 10 - expected_demolition_count)
	if engineer.explosives_remaining == expected_remaining_explosives:
		checks_passed += 1
		print(
			"[FutureEngineerStage1Test] PASS inventory consumed=%d remaining=%d"
			% [expected_demolition_count, engineer.explosives_remaining]
		)
	else:
		push_error(
			"[FutureEngineerStage1Test] FAIL inventory expected=%d actual=%d"
			% [expected_remaining_explosives, engineer.explosives_remaining]
		)

	if wall_count > expected_demolition_count:
		checks_total += 1
		var first_unfunded_wall_survives := not wall_destroyed_flags[expected_demolition_count]
		if first_unfunded_wall_survives:
			checks_passed += 1
			print(
				"[FutureEngineerStage1Test] PASS explosives exhausted before wall_%02d"
				% (expected_demolition_count + 1)
			)
		else:
			push_error(
				"[FutureEngineerStage1Test] FAIL wall_%02d was destroyed after explosives were exhausted"
				% (expected_demolition_count + 1)
			)

	var same_team_bomb_destroyed := await _validate_same_team_bomb_damage()
	checks_total += 1
	if same_team_bomb_destroyed:
		checks_passed += 1
		print("[FutureEngineerStage1Test] PASS same-team lightning can destroy RemoteBomb")
	else:
		push_error("[FutureEngineerStage1Test] FAIL same-team RemoteBomb impact")

	var result_summary := (
		"[FutureEngineerStage1Test] result=%d/%d walls_destroyed=%d/%d "
		+ "bombs_planted=%d elapsed=%.1fs"
	) % [
		checks_passed,
		checks_total,
		_destroyed_wall_count(),
		wall_count,
		bombs_planted,
		elapsed,
	]
	print(result_summary)
	if checks_passed == checks_total:
		print("[FutureEngineerStage1Test] COMPLETE")
	else:
		push_error("[FutureEngineerStage1Test] FAILED")

	if is_instance_valid(engineer):
		engineer.set_physics_process(false)
		engineer.set_process(false)
	## Headless 执行时自动退出，编辑器 F6 执行时保留测试现场供观察。
	if quit_when_complete or DisplayServer.get_name() == "headless":
		get_tree().quit(0 if checks_passed == checks_total else 1)


func _build_engineer() -> void:
	engineer = ENGINEER_SCENE.instantiate() as FutureEngineerAI
	if engineer == null:
		push_error("[FutureEngineerStage1Test] cannot instantiate FutureEngineer")
		return
	engineer.name = "FutureEngineer_Stage1_Test"
	engineer.team_id = "blue"
	engineer.target = target
	engineer.max_hp = 250.0
	engineer.use_navigation_agent = true
	engineer.console_debug_enabled = true
	engineer.console_debug_interval = 0.5
	## 使用正式移动速度，避免高速测试时绕开部分墙体的前向检测射线。
	engineer.chase_speed = 3.0
	engineer.flee_speed = 5.0
	engineer.target_refresh_interval = 0.1
	add_child(engineer)
	engineer.global_position = Vector3(0.0, 0.02, 0.0)


func _build_blue_warrior() -> void:
	blue_warrior = FUTURE_WARRIOR_SCENE.instantiate() as FutureWarriorAI
	if blue_warrior == null:
		push_error("[FutureEngineerStage1Test] cannot instantiate blue FutureWarrior")
		return
	blue_warrior.name = "FutureWarrior_Blue_Stage1_Companion"
	blue_warrior.team_id = "blue"
	blue_warrior.target = target
	blue_warrior.use_navigation_agent = true
	blue_warrior.print_decisions = false
	blue_warrior.chase_speed = 3.0
	blue_warrior.target_refresh_interval = 0.1
	add_child(blue_warrior)
	## 放在 Engineer 旁边而不是重叠；target 仍然与 Engineer 完全相同。
	blue_warrior.global_position = Vector3(3.0, 0.02, 1.5)
	print(
		"[FutureEngineerStage1Test] blue FutureWarrior=%s spawn=%s shared_target=%s"
		% [
			blue_warrior.name,
			_format_position(blue_warrior.global_position),
			_target_name(target),
		]
	)


func _build_red_future_warriors() -> void:
	red_future_warriors.clear()
	red_future_warrior_targets.clear()
	if not spawn_red_future_warriors or wall_count < 3:
		print("[FutureEngineerStage1Test] red FutureWarriors disabled")
		return

	var area_number := 0
	## 从第 2、3 道防线之间开始，逐个覆盖相邻防线之间的区域。
	for line_index in range(
		RED_WARRIOR_FIRST_AREA_LINE_INDEX,
		maxi(RED_WARRIOR_FIRST_AREA_LINE_INDEX, wall_count - 1)
	):
		var front_line_center := _defense_line_center(line_index)
		var back_line_center := _defense_line_center(line_index + 1)
		var area_center := _area_center_between(
			front_line_center,
			back_line_center,
		)
		_spawn_red_future_warrior(
			"Area_%02d_%02d" % [line_index + 1, line_index + 2],
			area_center,
			Vector3(red_warrior_spawn_x, 0.02, area_center.z),
			area_number,
		)
		area_number += 1

	## 最后一块区域是第 11 道防线与战略目标之间的区域。
	if wall_count > 0 and is_instance_valid(target):
		var last_line_center := _defense_line_center(wall_count - 1)
		var final_area_center := _area_center_between(
			last_line_center,
			target.global_position,
		)
		_spawn_red_future_warrior(
			"Area_%02d_Target" % wall_count,
			final_area_center,
			Vector3(-red_warrior_spawn_x, 0.02, final_area_center.z),
			area_number,
		)

	print(
		(
			"[FutureEngineerStage1Test] red FutureWarriors spawned=%d "
			+ "areas=between_line_02_03_to_final target=area_center"
		)
		% red_future_warriors.size()
	)


func _spawn_red_future_warrior(
	area_name: String,
	area_center: Vector3,
	spawn_position: Vector3,
	area_number: int,
) -> void:
	var area_target := Node3D.new()
	area_target.name = "RedFutureWarriorTarget_%s" % area_name
	area_target.set_meta("target_area_center", true)
	add_child(area_target)
	area_target.global_position = area_center
	red_future_warrior_targets.append(area_target)

	var marker := MeshInstance3D.new()
	marker.name = "TargetMarker"
	var marker_mesh := CylinderMesh.new()
	marker_mesh.top_radius = 0.35
	marker_mesh.bottom_radius = 0.35
	marker_mesh.height = 0.06
	marker.mesh = marker_mesh
	marker.position.y = 0.03
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color(0.85, 0.08, 0.12, 0.75)
	marker_material.emission_enabled = true
	marker_material.emission = Color(0.45, 0.01, 0.02, 1.0)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = marker_material
	area_target.add_child(marker)

	var warrior := FUTURE_WARRIOR_SCENE.instantiate() as FutureWarriorAI
	if warrior == null:
		push_error("[FutureEngineerStage1Test] cannot instantiate red FutureWarrior %s" % area_name)
		return
	warrior.name = "FutureWarrior_Red_%s" % area_name
	warrior.team_id = "red"
	warrior.target = area_target
	warrior.use_navigation_agent = true
	warrior.print_decisions = false
	warrior.set_meta("stage1_area_number", area_number + 1)
	warrior.set_meta("stage1_target_area_center", area_center)
	add_child(warrior)
	warrior.global_position = spawn_position
	red_future_warriors.append(warrior)
	print(
		"[FutureEngineerStage1Test] red FutureWarrior=%s spawn=%s target=%s"
		% [warrior.name, _format_position(spawn_position), _format_position(area_center)]
	)


func _build_demolition_walls() -> void:
	for line_index in range(wall_count):
		var line_z := -6.0 - wall_spacing * float(line_index)
		for segment_index in range(_wall_segments_per_line()):
			var offset_from_center := segment_index - side_wall_count
			var wall := WALL_SCENE.instantiate() as Node3D
			if wall == null:
				push_error(
					"[FutureEngineerStage1Test] cannot instantiate line=%d segment=%d"
					% [line_index + 1, segment_index + 1]
				)
				continue
			wall.name = "TallLogWall_Stage1_Line_%02d_Segment_%02d" % [
				line_index + 1,
				segment_index + 1,
			]
			wall.set("tool_owner", "red")
			add_child(wall)
			wall.global_position = Vector3(
				float(offset_from_center) * WALL_SEGMENT_SPACING,
				0.0,
				line_z,
			)
			all_walls.append(wall)

			## 仅中间段是 Engineer 逻辑上逐条识别的 11 个防线目标。
			if offset_from_center == 0:
				walls.append(wall)
				wall_destroyed_flags.append(false)
				wall_destroy_positions.append(Vector3.ZERO)
				wall_destroy_times.append(-1.0)
				if wall.has_signal("defense_destroyed"):
					wall.connect(
						"defense_destroyed",
						Callable(self, "_on_wall_destroyed").bind(line_index),
					)


func _line_z(line_index: int) -> float:
	return -6.0 - wall_spacing * float(line_index)


func _defense_line_center(line_index: int) -> Vector3:
	## 使用已经实例化并摆放完成的中间墙，避免模型/碰撞体偏移导致
	## “防线中心”和视觉上的实际位置不一致。
	if line_index >= 0 and line_index < walls.size():
		var wall := walls[line_index]
		if is_instance_valid(wall):
			return wall.global_position
	return Vector3(0.0, 0.0, _line_z(line_index))


func _area_center_between(first: Vector3, second: Vector3) -> Vector3:
	var center := first.lerp(second, 0.5)
	## 区域中心落在地面平面上；FutureWarrior 的根节点再使用自身的 0.02m
	## 站立高度，避免把 target 误设到墙体碰撞体的上半部。
	center.y = 0.0
	return center


func _expected_red_future_warrior_count() -> int:
	if not spawn_red_future_warriors or wall_count < 3:
		return 0
	## (2,3), (3,4), ... (N-1,N), (N,target)
	return wall_count - RED_WARRIOR_FIRST_AREA_LINE_INDEX


func _red_future_warriors_are_configured() -> bool:
	for index in range(red_future_warriors.size()):
		var warrior := red_future_warriors[index]
		var area_target := red_future_warrior_targets[index]
		if not is_instance_valid(warrior) or not is_instance_valid(area_target):
			return false
		if warrior.team_id != "red" or warrior.get_combat_team() != "red":
			return false
		if not warrior.use_navigation_agent or warrior.target != area_target:
			return false
		var expected_center: Variant = warrior.get_meta(
			"stage1_target_area_center",
			Vector3.INF,
		)
		if not expected_center is Vector3 \
				or not area_target.global_position.is_equal_approx(expected_center as Vector3):
			return false
	return true


func _build_strategic_target() -> void:
	target = Node3D.new()
	target.name = "StrategicTarget_Stage1_Test"
	add_child(target)
	target.global_position = Vector3(
		0.0,
		0.0,
		-6.0 - wall_spacing * float(maxi(0, wall_count - 1)) - 9.0,
	)
	var marker := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.55
	mesh.height = 0.08
	marker.mesh = mesh
	marker.position.y = 0.04
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.25, 0.12, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.55, 0.05, 0.01, 1.0)
	marker.material_override = material
	target.add_child(marker)


func _build_test_floor() -> void:
	test_floor = StaticBody3D.new()
	test_floor.name = "Stage1TestFloor"
	test_floor.collision_layer = 1
	test_floor.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(40.0, 0.1, 140.0)
	shape_node.shape = shape
	shape_node.position = Vector3(0.0, -0.05, -48.0)
	test_floor.add_child(shape_node)
	add_child(test_floor)
	var mesh_node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_node.mesh = mesh
	mesh_node.position = shape_node.position
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.20, 0.13, 1.0)
	mesh_node.material_override = material
	add_child(mesh_node)

	## 测试场景也使用统一的 64m 分区管理器。地面 Mesh 加入
	## navigation_ground，管理器会把这个 40m x 140m 测试走廊划成 1 x 3 区块。
	mesh_node.add_to_group("navigation_ground")
	test_navigation_grid = DynamicNavigationChunkGrid.new()
	test_navigation_grid.name = "Stage1DynamicNavigationChunkGrid"
	test_navigation_grid.map_origin = Vector2(-20.0, -118.0)
	test_navigation_grid.map_size = Vector2(40.0, 140.0)
	test_navigation_grid.chunk_size = 64.0
	test_navigation_grid.fallback_ground_y = 0.0
	add_child(test_navigation_grid)


func _wait_for_test_navigation() -> void:
	if test_navigation_grid == null:
		push_error("[FutureEngineerStage1Test] DynamicNavigationChunkGrid was not created")
		return
	for _attempt in range(180):
		if test_navigation_grid.is_navigation_ready():
			print(
				"[FutureEngineerStage1Test] NavigationMap ready chunks=%s"
				% [test_navigation_grid.get_chunk_count()]
			)
			return
		await get_tree().physics_frame
	push_error("[FutureEngineerStage1Test] NavigationMap was not ready after 180 physics frames")


func _build_test_lighting_and_camera() -> void:
	var light := DirectionalLight3D.new()
	light.name = "Stage1TestSun"
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.3
	add_child(light)
	var camera := Camera3D.new()
	camera.name = "Stage1TestCamera"
	## 复用项目已有测试观察相机：WASD/方向键移动，Shift 加速，Q/E 升降，
	## 按住鼠标右键并移动鼠标进行 yaw/pitch 旋转，滚轮前后移动。
	camera.set_script(TEST_CAMERA_SCRIPT)
	camera.set("yaw", -0.21)
	camera.set("pitch", -0.31)
	camera.position = Vector3(18.0, 28.0, 35.0)
	add_child(camera)
	camera.current = true
	print(
		"[FutureEngineerStage1Test] camera controls: WASD/arrows move, Shift speed, "
		+ "Q/E height, RMB+mouse pitch/yaw, wheel zoom"
	)


func _on_wall_destroyed(index: int) -> void:
	if index < 0 or index >= wall_destroyed_flags.size() or wall_destroyed_flags[index]:
		return
	wall_destroyed_flags[index] = true
	wall_destroy_positions[index] = engineer.global_position if is_instance_valid(engineer) else Vector3.ZERO
	wall_destroy_times[index] = _test_elapsed
	print(
		"[FutureEngineerStage1Test] wall_%02d destroyed at engineer_pos=%s elapsed=%.1fs"
		% [index + 1, _format_position(wall_destroy_positions[index]), _test_elapsed]
	)


func _refresh_destroyed_wall_flags() -> void:
	for index in range(walls.size()):
		if wall_destroyed_flags[index]:
			continue
		if not is_instance_valid(walls[index]):
			_on_wall_destroyed(index)


func _destroyed_wall_count() -> int:
	var count := 0
	for destroyed in wall_destroyed_flags:
		if destroyed:
			count += 1
	return count


func _wall_segments_per_line() -> int:
	return 1 + side_wall_count * 2


func _total_wall_segments() -> int:
	return wall_count * _wall_segments_per_line()


func _is_forward_progress_ordered(expected_count: int) -> bool:
	var previous_z := INF
	for index in range(expected_count):
		if not wall_destroyed_flags[index]:
			return false
		var current_z := wall_destroy_positions[index].z
		if index > 0 and current_z >= previous_z - 0.5:
			return false
		previous_z = current_z
	return true


func _destroy_position_summary() -> String:
	var values: Array[String] = []
	for position in wall_destroy_positions:
		values.append("%.1f" % position.z)
	return "[" + ", ".join(values) + "]"


func _validate_same_team_bomb_damage() -> bool:
	var bomb := REMOTE_BOMB_SCENE.instantiate() as RemoteBomb
	if bomb == null:
		return false
	bomb.name = "RemoteBomb_SameTeam_Stage1_Test"
	add_child(bomb)
	bomb.global_position = Vector3(8.0, 0.25, 0.0)
	await get_tree().process_frame
	bomb.setup(null, "blue", 50.0)
	bomb.impact("lightning", 50.0, "blue")
	return bomb.is_destroyed


## FutureEngineer / AIAssistant 使用的最小战略目标接口。
func get_random_enemy_spawn_position(_team: String, _random_seed := 0, _player_index := 0) -> Vector3:
	return target.global_position if is_instance_valid(target) else Vector3(0.0, 0.0, -18.0)


func get_spawn_position_for_id(_spawn_id: String, _team: String, _player_index := 0, _random_seed := 0) -> Vector3:
	return Vector3.ZERO


func _target_name(value: Node3D) -> String:
	return value.name if is_instance_valid(value) else "none"


func _format_position(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]
