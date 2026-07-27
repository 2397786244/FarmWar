extends AIPlayerv2
class_name EnemyAI
## 进攻方敌人 AI。基于 AIPlayerv2，移除种植/收获逻辑，专注进攻和破坏。
## 三种敌人类型：bandit（盗匪）、bruiser_rider（重装骑兵）、future_warrior（未来战士）
## 敌人队伍 team_id = "enemy"，目标是进攻 blue 队（防守方）的农田和队员。

const ENEMY_CONFIG_PATH := "res://data/enemy_types.json"

@export_enum("bandit", "bruiser_rider", "future_warrior") var enemy_type := "bandit"


func _ready() -> void:
	rng.randomize()
	add_to_group("farmer_ai")
	add_to_group("ai_players")
	add_to_group("enemies")
	spawn_position = global_position
	hp = max_hp

	if not _load_tool_definitions():
		set_physics_process(false)
		return
	if not _load_enemy_tools():
		set_physics_process(false)
		return

	# 用 enemy_type 作为外观名加载敌人模型
	set_ai_appearance(enemy_type, team_id)
	_equip_default_tool()
	_schedule_think(0.2)


func _load_enemy_tools() -> bool:
	profession_tool_ids.clear()
	local_tools.clear()
	cooldowns.clear()
	if not FileAccess.file_exists(ENEMY_CONFIG_PATH):
		push_error("Enemy config not found: " + ENEMY_CONFIG_PATH)
		return false
	var file := FileAccess.open(ENEMY_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open enemy config: " + ENEMY_CONFIG_PATH)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("Enemy config parse error: " + ENEMY_CONFIG_PATH)
		return false
	var enemies: Dictionary = json.data.get("enemies", {})
	if not enemies.has(enemy_type):
		push_error("Enemy type not found: " + enemy_type)
		return false
	var tool_ids: Array = enemies[enemy_type].get("tools", [])
	for tid in tool_ids:
		var tid_str := str(tid)
		if not tool_definitions.has(tid_str):
			push_warning("Tool id missing: " + tid_str)
			continue
		profession_tool_ids.append(tid_str)
		local_tools.append(tool_definitions[tid_str])
		cooldowns.append(0.0)
	if local_tools.is_empty():
		push_error("No valid tools for enemy: " + enemy_type)
		return false
	if print_decisions:
		print("EnemyAI %s loaded tools: %s" % [enemy_type, profession_tool_ids])
	return true


## 加载敌人模型（从 character/hero_skeleton/enemy/ 目录）
func set_ai_appearance(hero_name: String, _team_name: String) -> void:
	var appearance_path := "res://character/hero_skeleton/enemy/%s.tscn" % hero_name
	var appearance_scene := load(appearance_path) as PackedScene
	if appearance_scene == null:
		push_error("Unable to load enemy appearance: " + appearance_path)
		return
	var appearance_node := appearance_scene.instantiate() as Node3D
	_remove_emotion_controllers(appearance_node)
	add_child(appearance_node)
	appearance_node.rotation.y = deg_to_rad(180.0)
	appearance_node.name = "AppearanceNode"
	appearance_player = appearance_node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = appearance_node.find_child("Skeleton3D", true, false) as Skeleton3D
	if appearance_player == null or skeleton == null:
		push_error("Unable to init enemy skeleton for: " + hero_name)
		return
	hand_socket.use_external_skeleton = true
	hand_socket.external_skeleton = hand_socket.get_path_to(skeleton)
	hand_socket.bone_name = "Hand.R"
	hand_socket.override_pose = false
	if not appearance_player.animation_finished.is_connected(_skeleton_animation_finished):
		appearance_player.animation_finished.connect(_skeleton_animation_finished)
	_setup_upper_body_aim()
	appearance_player.play(&"Idle")


## 敌人进攻决策：只保留攻击/射击/侦查/防空，移除种植/收获/防御己方农田
func _choose_action() -> void:
	target_plot = null
	target_player = null
	movement_target = INVALID_POSITION

	# 敌人的"敌方"是 blue（防守方）
	var defender_team := "blue"
	var defender_plots := _get_team_plots(defender_team)

	var stats := _compute_farm_stats([], defender_plots)
	var enemy_mature_count: int = stats["enemy_mature_count"]
	var enemy_tool_count: int = stats["enemy_tool_count"]
	var enemy_target_count: int = stats["enemy_target_count"]

	var enemy_plot := _choose_enemy_target()
	target_player = _find_visible_enemy_player()

	var threat := clampf(recent_enemy_bullet_timer / THREAT_MEMORY_SECONDS, 0.0, 1.0)

	var scores := {
		DecisionAction.ANTIAIR: -INF,
		DecisionAction.ATTACK: -INF,
		DecisionAction.SHOOT_PLAYER: -INF,
		DecisionAction.CAST_WAND: -INF,
		DecisionAction.SCOUT: -INF,
		DecisionAction.PATROL: 5.0,
	}

	# 防空车（不需要 FarmTile，保护自身免受炮弹）
	if _has_tool_id("anti_air") and _count_placed_tool("AntiAir") < _antiair_limit():
		var antiair_pos := _choose_antiair_position()
		if antiair_pos != INVALID_POSITION:
			scores[DecisionAction.ANTIAIR] = 55.0 + threat * 35.0

	# 攻击防守方农田/工具（敌人核心任务）
	if enemy_plot != null and _has_tool_id("wreck") and _try_claim("attack", enemy_plot):
		scores[DecisionAction.ATTACK] = 85.0 + enemy_target_count * 1.5 + \
				enemy_mature_count * 4.0 + enemy_tool_count * 6.0

	# 射击防守方队员（最高优先级）
	var shoot_tool_index := _find_shooting_tool_index()
	if is_instance_valid(target_player) and shoot_tool_index >= 0 and \
			_tool_ready(shoot_tool_index):
		var dist := global_position.distance_to(target_player.global_position)
		var close_bonus := maxf(0.0, (player_shooting_range - dist) * 4.0)
		scores[DecisionAction.SHOOT_PLAYER] = 95.0 + close_bonus + \
				(16.0 if difficulty == Difficulty.HARD else 0.0)

	# 魔杖雷击
	var wand_index := _find_tool_index("wand")
	if is_instance_valid(target_player) and wand_index >= 0 and _tool_ready(wand_index):
		scores[DecisionAction.CAST_WAND] = 90.0

	# 侦查：向防守方领地推进
	var has_offense := shoot_tool_index >= 0 or wand_index >= 0 or _has_tool_id("wreck")
	if has_offense:
		scores[DecisionAction.SCOUT] = 45.0 + enemy_target_count * 1.0 + \
				enemy_tool_count * 1.5 + (8.0 if difficulty == Difficulty.HARD else 0.0)

	# 决策噪声
	var noise := 13.0 if difficulty == Difficulty.EASY else 2.0
	for action in scores:
		if scores[action] > -INF:
			scores[action] += rng.randf_range(-noise, noise)

	var chosen := DecisionAction.PATROL
	var best_score := -INF
	for action in scores:
		if scores[action] > best_score:
			chosen = action
			best_score = scores[action]

	last_decision = chosen
	last_utility_scores = scores.duplicate()

	match chosen:
		DecisionAction.ANTIAIR:
			placement_tool_index = _find_tool_index("anti_air")
			_start_antiair_action(_choose_antiair_position())
		DecisionAction.ATTACK:
			_start_attack(enemy_plot, _enemy_attack_line_z())
		DecisionAction.SHOOT_PLAYER:
			_set_focus_target(target_player)
			state = AIState.SHOOT_PLAYER
			state_timer = rng.randf_range(0.08, 0.16) if difficulty == Difficulty.HARD \
					else rng.randf_range(0.28, 0.5)
			movement_target = INVALID_POSITION
		DecisionAction.CAST_WAND:
			_set_focus_target(target_player)
			state = AIState.CAST_WAND
			state_timer = 0.1
			movement_target = INVALID_POSITION
		DecisionAction.SCOUT:
			_start_enemy_scout()
		_:
			_start_patrol()

	if print_decisions:
		var target_pos := "(none)"
		if is_instance_valid(target_plot):
			target_pos = "(%.1f, %.1f)" % [target_plot.global_position.x, target_plot.global_position.z]
		elif movement_target != INVALID_POSITION:
			target_pos = "(%.1f, %.1f)" % [movement_target.x, movement_target.z]
		print("EnemyAI decision=", DecisionAction.keys()[chosen],
				" score=", snappedf(best_score, 0.1), " type=", enemy_type,
				" target=", target_pos)


## 敌人攻击线：靠近防守方一侧，但保持一定距离用于炮击
func _enemy_attack_line_z() -> float:
	# 敌人在 z 正侧（z=60），向 z 负侧（防守方）推进
	# 攻击线设在中央偏己方一侧，确保 wreck 炮弹能打到防守方农田
	return 20.0


## 敌人侦查：直接前往防守方农田区域中心
func _start_enemy_scout() -> void:
	var defender_plots := _get_team_plots("blue")
	var scout_target := INVALID_POSITION
	if not defender_plots.is_empty():
		var sum := Vector3.ZERO
		var count := 0
		for plot in defender_plots:
			if _is_valid_plot(plot):
				sum += plot.global_position
				count += 1
		if count > 0:
			scout_target = sum / float(count)
			scout_target.x += rng.randf_range(-8.0, 8.0)
			scout_target.z += rng.randf_range(-4.0, 4.0)
			scout_target.y = global_position.y
	if scout_target == INVALID_POSITION:
		scout_target = global_position + Vector3(0.0, 0.0, -15.0)
	movement_target = scout_target
	state = AIState.SCOUT
	state_timer = rng.randf_range(4.0, 7.0)


## 敌人巡逻范围：在防守方一侧活动
func _patrol_min() -> Vector3:
	return Vector3(-25.0, 0.0, 3.6)


func _patrol_max() -> Vector3:
	return Vector3(25.0, 0.0, 25.0)
