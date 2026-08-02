extends CharacterBody3D
class_name AIPlayerv2
## 可扩展的 AI 玩家。参考 player.gd / wreck_ai.gd，支持 10 职业、11 工具、
## 简单/困难模式、NavigationAgent3D 寻路、多 NPC 协作、HP/respawn 战斗。

enum Difficulty { EASY, HARD }
enum AIState {
	THINK,
	MOVE_TO_SOW,
	SOW,
	MOVE_TO_HARVEST,
	HARVEST,
	MOVE_TO_ATTACK,
	ATTACK,
	MOVE_TO_PLACE,
	PLACE,
	ABSORB,
	SHOOT_PLAYER,
	CAST_WAND,
	ASSIST,
	STUNNED,
	PATROL,
	SCOUT,
	DEFEND_FARM,
}
enum DecisionAction { HARVEST, SHIELD, TURRET, ANTIAIR, SOW, ATTACK, SHOOT_PLAYER, CAST_WAND, ASSIST, SCOUT, PATROL, DEFEND_FARM }

const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"
const PROFESSION_CONFIG_PATH := "res://data/profession_tools.json"
const INVALID_POSITION := Vector3(INF, INF, INF)
const THREAT_MEMORY_SECONDS := 7.0
const CLAIM_EXPIRE := 5.0
const DEFAULT_HP := 200.0
const RESPAWN_DELAY := 10.0

## 工具分类，用于决定动画与行为
const TOOL_CATEGORY_SHOOTING := "shooting"
const TOOL_CATEGORY_UTILITY := "utility"

## 全局工具 id -> 工具定义字典（含 path/grip/category/cooldown）
var tool_definitions: Dictionary = {}
## 本职业可用工具 id 列表（4 个）
var profession_tool_ids: Array[String] = []
## 本职业工具本地索引(0..2) -> 工具定义
var local_tools: Array[Dictionary] = []
## 本职业工具本地索引 -> 冷却剩余
var cooldowns: Array[float] = []

# --- 协作静态变量 ---
## team -> { claim_key: { "claimer": AIPlayerv2, "expire": float } }
static var _team_claims: Dictionary = {}
## team -> CharacterBody3D（当前集火目标）
static var _focus_target: Dictionary = {}
## team -> { "position": Vector3, "expire": float, "reporter": AIPlayerv2 }
## 己方土地被攻击时的威胁广播，供队友感知并前往防御
static var _farm_threats: Dictionary = {}
## team -> 正在 DEFEND_FARM 状态的 AI 数量（避免全员防御）
static var _defending_count: Dictionary = {}

# --- 节点引用 ---
@onready var hand_socket: BoneAttachment3D = $RightHandSocket
@onready var tool_socket: Node3D = $RightHandSocket/ToolPivot
@onready var upper_body_look_target: Marker3D = $Head/UpperBodyLookTarget
@onready var right_hand_ik_target: Marker3D = $Head/RightHandIKTarget
@onready var right_elbow_pole: Marker3D = $RightElbowPole
@onready var front_probe: RayCast3D = $FrontProbe
@onready var lookat_ray: RayCast3D = $Head/LookAtTarget
@onready var nav_agent: NavigationAgent3D = $NavigationAgent3D

# --- export ---
@export_enum("简单", "困难") var difficulty: int = Difficulty.HARD
@export_enum("farmer", "cook", "guard", "mage", "engineer", "apothecary",
		"assistant", "trickster", "prospector", "rider") var profession := "farmer"
@export var team_id: String = "blue"
@export var movement_enabled := true
@export var print_decisions := false
@export var player_shooting_range := 18.0
@export var max_hp: float = DEFAULT_HP

# --- 状态 ---
var state: int = AIState.THINK
var current_tool_index: int = -1  # local_tools 索引
var held_tool: Node3D
var target_plot: Node3D
var target_bullet: CharacterBody3D
var target_player: CharacterBody3D
var movement_target := INVALID_POSITION
var patrol_target := INVALID_POSITION
var placement_tool_index: int = -1  # 当前放置的工具 local index
var spawn_position := Vector3.ZERO

var think_timer := 0.0
var state_timer := 0.0
var jump_timer := 0.0
var bullet_scan_timer := 0.0
var recent_enemy_bullet_timer := 0.0
var respawn_timer := 0.0
var scout_scan_timer := 0.0
var last_decision: int = DecisionAction.PATROL
var last_utility_scores: Dictionary = {}
var rng := RandomNumberGenerator.new()
var rubber_knockback := Vector3.ZERO
## 是否使用 NavigationAgent3D 寻路。默认 false=直线移动+FrontProbe避障（最稳定）。
## 在编辑器里勾选启用，需确保 NavMesh 烘焙完整。
@export var use_navigation := false

# --- 外观/动画 ---
var appearance_player: AnimationPlayer
var skeleton: Skeleton3D
var upper_body_look_modifiers: Array[LookAtModifier3D] = []
var upper_body_look_weights: Array[float] = []
var right_arm_ik: TwoBoneIK3D
var hand_aim_look: LookAtModifier3D
var action_anim_locked := false
var was_on_floor := true
var landing_animation := false
## 当前工具瞄准的世界坐标目标。每帧由 _update_tool_aim_alignment 用来重新对齐
## tool_socket，补偿骨骼动画/IK 对 BoneAttachment3D 子节点朝向的覆盖。
var aim_target_position := Vector3.ZERO

# --- 战斗状态 ---
var hp: float = DEFAULT_HP
var stun_remaining := 0.0
var slow_remaining := 0.0
var burn_remaining := 0.0
var burn_dps := 0.0
var under_attack_timer := 0.0
var last_attacker: CharacterBody3D = null
var is_dead := false

## 防御目标：己方被威胁的土地位置（DEFEND_FARM 状态使用）
var defend_target := INVALID_POSITION
## 防御状态扫描计时器
var defend_scan_timer := 0.0
## 上次扫描时己方土地的作物/工具总数，用于检测是否被破坏
var last_farm_content_count := -1


func _ready() -> void:
	rng.randomize()
	add_to_group("farmer_ai")
	add_to_group("ai_players")
	spawn_position = global_position
	hp = max_hp

	if not _load_tool_definitions():
		set_physics_process(false)
		return
	if not _load_profession_tools():
		set_physics_process(false)
		return

	# 导航默认禁用（export use_navigation=false），用直线移动+FrontProbe避障。
	# 如需启用导航，在编辑器里勾选 use_navigation，并确保 NavMesh 烘焙完整。

	set_ai_appearance(profession, team_id)
	# 默认装备第一个非 wand 工具（Wand 实例化时 owner_node 类型检查会报错）
	_equip_default_tool()
	_schedule_think(0.2)


# ===========================================================================
# 配置加载
# ===========================================================================

func _load_tool_definitions() -> bool:
	tool_definitions.clear()
	if not FileAccess.file_exists(TOOL_CONFIG_PATH):
		push_error("AI tool config not found: " + TOOL_CONFIG_PATH)
		return false
	var file := FileAccess.open(TOOL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open tool config: " + TOOL_CONFIG_PATH)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("AI could not parse " + TOOL_CONFIG_PATH)
		return false
	var source_tools: Variant = json.data.get("tools", [])
	if not source_tools is Array:
		push_error("Tool JSON 'tools' must be an array.")
		return false
	for source_tool: Variant in source_tools:
		if not source_tool is Dictionary:
			continue
		var definition: Dictionary = source_tool.duplicate(true)
		var tid := str(definition.get("id", ""))
		if tid.is_empty():
			continue
		definition["grip_position"] = _json_to_vector3(
			definition.get("grip_position", []), Vector3.ZERO)
		definition["grip_rotation"] = _json_to_vector3(
			definition.get("grip_rotation", []), Vector3.ZERO)
		definition["grip_scale"] = _json_to_vector3(
			definition.get("grip_scale", []), Vector3.ONE)
		definition["color"] = Color.from_string(
			str(definition.get("color", "#FFFFFF")), Color.WHITE)
		tool_definitions[tid] = definition
	return not tool_definitions.is_empty()


func _load_profession_tools() -> bool:
	profession_tool_ids.clear()
	local_tools.clear()
	cooldowns.clear()
	if not FileAccess.file_exists(PROFESSION_CONFIG_PATH):
		push_error("Profession config not found: " + PROFESSION_CONFIG_PATH)
		return false
	var file := FileAccess.open(PROFESSION_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to open profession config: " + PROFESSION_CONFIG_PATH)
		return false
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("AI could not parse " + PROFESSION_CONFIG_PATH)
		return false
	var professions: Dictionary = json.data.get("professions", {})
	if not professions.has(profession):
		push_error("Profession not found in config: " + profession)
		return false
	var tool_ids: Array = professions[profession].get("tools", [])
	for tid in tool_ids:
		var tid_str := str(tid)
		if not tool_definitions.has(tid_str):
			push_warning("Tool id missing in tool_definitions: " + tid_str)
			continue
		profession_tool_ids.append(tid_str)
		local_tools.append(tool_definitions[tid_str])
		cooldowns.append(0.0)
	if local_tools.is_empty():
		push_error("No valid tools for profession: " + profession)
		return false
	if print_decisions:
		print("AIPlayerv2 %s/%s loaded tools: %s" % [
			profession, team_id, profession_tool_ids])
	return true


func _json_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array or value.size() < 3:
		return fallback
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


# ===========================================================================
# 主循环
# ===========================================================================

func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_update_combat_status(delta)

	if is_dead:
		_update_respawn(delta)
		_apply_movement(Vector3.ZERO, delta)
		return

	if stun_remaining > 0.0:
		_apply_movement(Vector3.ZERO, delta)
		return

	if _should_scan_for_bullets():
		bullet_scan_timer = _reaction_interval()
		var danger := _find_dangerous_bullet()
		if danger != null:
			recent_enemy_bullet_timer = THREAT_MEMORY_SECONDS
			if _has_tool_id("eater"):
				_begin_absorption(danger)

	# 检测己方土地威胁并广播给队友（防御感知）
	if defend_scan_timer <= 0.0:
		defend_scan_timer = 0.6 if difficulty == Difficulty.HARD else 1.0
		var farm_threat := _detect_farm_threat()
		if farm_threat != INVALID_POSITION:
			_broadcast_farm_threat(farm_threat)

	if state == AIState.ABSORB:
		_update_absorption(delta)
		_apply_movement(Vector3.ZERO, delta)
		return

	_update_state(delta)
	_update_movement(delta)


func _update_timers(delta: float) -> void:
	for index in range(cooldowns.size()):
		cooldowns[index] = maxf(0.0, cooldowns[index] - delta)
	think_timer = maxf(0.0, think_timer - delta)
	state_timer = maxf(0.0, state_timer - delta)
	jump_timer = maxf(0.0, jump_timer - delta)
	bullet_scan_timer = maxf(0.0, bullet_scan_timer - delta)
	recent_enemy_bullet_timer = maxf(0.0, recent_enemy_bullet_timer - delta)
	under_attack_timer = maxf(0.0, under_attack_timer - delta)
	defend_scan_timer = maxf(0.0, defend_scan_timer - delta)
	_cleanup_team_claims()
	_decay_farm_threats(delta)


## 团队威胁广播过期清理
static func _decay_farm_threats(delta: float) -> void:
	for team in _farm_threats.keys():
		var threat: Dictionary = _farm_threats[team]
		var expire: float = float(threat.get("expire", 0.0))
		expire -= delta
		if expire <= 0.0:
			_farm_threats.erase(team)
		else:
			threat["expire"] = expire
			_farm_threats[team] = threat


func _update_combat_status(delta: float) -> void:
	if burn_remaining > 0.0:
		var tick := minf(delta, burn_remaining)
		burn_remaining = maxf(0.0, burn_remaining - delta)
		_take_damage(burn_dps * tick)
		if burn_remaining <= 0.0:
			burn_dps = 0.0
	if slow_remaining > 0.0:
		slow_remaining = maxf(0.0, slow_remaining - delta)
	if stun_remaining > 0.0:
		stun_remaining = maxf(0.0, stun_remaining - delta)
		if stun_remaining <= 0.0 and state == AIState.STUNNED:
			_schedule_think(0.1)


func _update_respawn(delta: float) -> void:
	respawn_timer -= delta
	if respawn_timer <= 0.0:
		_respawn()


# ===========================================================================
# 状态机
# ===========================================================================

func _update_state(delta: float) -> void:
	match state:
		AIState.THINK:
			if think_timer <= 0.0:
				_choose_action()
		AIState.MOVE_TO_SOW:
			if state_timer <= 0.0 or not _is_valid_plot(target_plot) or \
					not _plot_is_empty(target_plot):
				_release_claim("sow", target_plot)
				_schedule_think()
			elif _has_reached_plot(target_plot, 2.8):
				state = AIState.SOW
				state_timer = 0.15
		AIState.SOW:
			if state_timer <= 0.0:
				_sow_target()
				_release_claim("sow", target_plot)
				_schedule_think(0.2)
		AIState.MOVE_TO_HARVEST:
			if state_timer <= 0.0 or not _is_valid_plot(target_plot) or \
					not target_plot.can_harvest:
				_release_claim("harvest", target_plot)
				_schedule_think()
			elif _has_reached_plot(target_plot, 3.0):
				state = AIState.HARVEST
				state_timer = 0.1
		AIState.HARVEST:
			if state_timer <= 0.0:
				_harvest_target()
				_release_claim("harvest", target_plot)
				_schedule_think(0.2)
		AIState.MOVE_TO_ATTACK:
			if state_timer <= 0.0 or not _is_valid_plot(target_plot):
				_release_claim("attack", target_plot)
				_schedule_think()
			elif _horizontal_distance(global_position, movement_target) < 0.8:
				state = AIState.ATTACK
				state_timer = rng.randf_range(0.1, 0.35)
		AIState.ATTACK:
			if state_timer <= 0.0:
				_attack_target()
				_release_claim("attack", target_plot)
				_schedule_think(0.25)
		AIState.MOVE_TO_PLACE:
			if state_timer <= 0.0 or not _is_valid_plot(target_plot) or \
					not _plot_accepts_tool(target_plot):
				_release_claim("place", target_plot)
				_schedule_think()
			elif _has_reached_plot(target_plot, 2.8):
				state = AIState.PLACE
				state_timer = 0.15
		AIState.PLACE:
			if state_timer <= 0.0:
				_place_defence()
				_release_claim("place", target_plot)
				_schedule_think(0.3)
		AIState.SHOOT_PLAYER:
			if state_timer <= 0.0:
				_shoot_player()
				_schedule_think(0.12)
		AIState.CAST_WAND:
			if state_timer <= 0.0:
				_cast_wand()
				_schedule_think(0.2)
		AIState.ASSIST:
			if state_timer <= 0.0:
				_assist_action()
				_schedule_think(0.15)
		AIState.PATROL:
			if patrol_target == INVALID_POSITION or \
					_horizontal_distance(global_position, patrol_target) < 0.8 or \
					state_timer <= 0.0:
				_schedule_think(0.1)
		AIState.SCOUT:
			# 侦查中：到达敌方区域或超时后重新决策
			# 途中每0.5秒重新检测敌人/作物（发现会自动切换到 SHOOT_PLAYER/ATTACK）
			scout_scan_timer -= delta
			if movement_target == INVALID_POSITION or \
					_horizontal_distance(global_position, movement_target) < 1.5 or \
					state_timer <= 0.0:
				_schedule_think(0.1)
			elif scout_scan_timer <= 0.0:
				scout_scan_timer = 0.5
				_schedule_think(0.05)
		AIState.DEFEND_FARM:
			# 防御己方土地：到达后执行防御动作，超时或威胁消失则重新决策
			defend_scan_timer -= delta
			if state_timer <= 0.0:
				_schedule_think(0.1)
			elif defend_scan_timer <= 0.0:
				defend_scan_timer = 0.3 if difficulty == Difficulty.HARD else 0.5
				_perform_defend_action()


# ===========================================================================
# 决策（效用评分）
# ===========================================================================

func _choose_action() -> void:
	target_plot = null
	target_player = null
	movement_target = INVALID_POSITION

	var own_plots := _get_team_plots(team_id)
	var enemy_team := "red" if team_id == "blue" else "blue"
	var enemy_plots := _get_team_plots(enemy_team)

	# 一次性统计，避免重复遍历农田（性能优化）
	var stats := _compute_farm_stats(own_plots, enemy_plots)
	var mature_count: int = stats["mature_count"]
	var empty_count: int = stats["empty_count"]
	var planted_count: int = stats["planted_count"]
	var enemy_mature_count: int = stats["enemy_mature_count"]
	var enemy_tool_count: int = stats["enemy_tool_count"]
	var enemy_target_count: int = stats["enemy_target_count"]
	var shield_count: int = stats["shield_count"]
	var turret_count: int = stats["turret_count"]
	var antiair_count: int = stats["antiair_count"]

	# 预获取前线 z 坐标和农场间距，传给子函数，避免循环内重复查询
	var front_z := _frontline_z(own_plots)
	var farm_spacing := _farm_spacing()

	var mature_plot := _nearest_plot(own_plots, true, false)
	var sow_plot := _choose_sow_plot(own_plots, front_z, farm_spacing)
	var enemy_plot := _choose_enemy_target()
	var shield_plot := _choose_frontline_shield_plot(own_plots, front_z, farm_spacing)
	var turret_plot := _choose_paired_turret_plot(own_plots, farm_spacing)
	var antiair_pos := _choose_antiair_position(front_z)
	target_player = _find_visible_enemy_player()

	var shield_limit := _shield_limit()
	var turret_limit := _turret_limit()
	var antiair_limit := _antiair_limit()
	var threat := clampf(
		recent_enemy_bullet_timer / THREAT_MEMORY_SECONDS, 0.0, 1.0)
	var empty_ratio := float(empty_count) / maxf(1.0, float(own_plots.size()))

	var scores := {
		DecisionAction.HARVEST: -INF,
		DecisionAction.SHIELD: -INF,
		DecisionAction.TURRET: -INF,
		DecisionAction.ANTIAIR: -INF,
		DecisionAction.SOW: -INF,
		DecisionAction.ATTACK: -INF,
		DecisionAction.SHOOT_PLAYER: -INF,
		DecisionAction.CAST_WAND: -INF,
		DecisionAction.ASSIST: -INF,
		DecisionAction.SCOUT: -INF,
		DecisionAction.DEFEND_FARM: -INF,
		DecisionAction.PATROL: 5.0,
	}

	if mature_plot != null and _has_tool_id("eater") and \
			_try_claim("harvest", mature_plot):
		scores[DecisionAction.HARVEST] = 92.0 + minf(28.0, mature_count * 3.5)

	if shield_plot != null and _has_tool_id("shield_door") and \
			_try_claim("place", shield_plot):
		var first_shield_bonus := 38.0 if shield_count == 0 else 0.0
		scores[DecisionAction.SHIELD] = 72.0 + first_shield_bonus + \
				threat * 48.0 + maxf(0.0, shield_limit - shield_count) * 4.0

	if turret_plot != null and _has_tool_id("auto_shooter") and \
			_try_claim("place", turret_plot):
		var unpaired_shield_bonus := 25.0 if turret_count < shield_count else 0.0
		scores[DecisionAction.TURRET] = 78.0 + unpaired_shield_bonus + \
				shield_count * 5.0 + enemy_target_count * 0.8

	if antiair_pos != INVALID_POSITION and _has_tool_id("anti_air") and \
			antiair_count < antiair_limit:
		scores[DecisionAction.ANTIAIR] = 60.0 + threat * 35.0 + \
				maxf(0.0, antiair_limit - antiair_count) * 5.0

	if sow_plot != null and _has_tool_id("sprout_blaster") and \
			_try_claim("sow", sow_plot):
		var early_farm_bonus := 30.0 if planted_count < 6 else 0.0
		scores[DecisionAction.SOW] = 72.0 + empty_ratio * 30.0 + \
				early_farm_bonus - threat * 12.0

	if enemy_plot != null and _has_tool_id("wreck") and \
			_try_claim("attack", enemy_plot):
		scores[DecisionAction.ATTACK] = 64.0 + enemy_target_count * 1.2 + \
				enemy_mature_count * 4.0 + enemy_tool_count * 6.0 - threat * 8.0

	# 射击类工具：优先 revover/flame/freeze/nail_gun
	var shoot_tool_index := _find_shooting_tool_index()
	if is_instance_valid(target_player) and shoot_tool_index >= 0 and \
			_tool_ready(shoot_tool_index):
		var player_distance := global_position.distance_to(target_player.global_position)
		var close_range_bonus := (player_shooting_range - player_distance) * 4.0
		# 集火加成：若该目标是团队焦点目标，加分
		var focus_bonus := 25.0 if _is_focus_target(target_player) else 0.0
		scores[DecisionAction.SHOOT_PLAYER] = 88.0 + close_range_bonus + \
			focus_bonus + (16.0 if difficulty == Difficulty.HARD else 0.0)

	# Wand 雷击
	var wand_index := _find_tool_index("wand")
	if is_instance_valid(target_player) and wand_index >= 0 and \
			_tool_ready(wand_index):
		var focus_bonus := 20.0 if _is_focus_target(target_player) else 0.0
		scores[DecisionAction.CAST_WAND] = 85.0 + focus_bonus

	# 协作：队友被攻击，优先支援
	var assist_target := _find_ally_in_trouble()
	if is_instance_valid(assist_target):
		# 射击职业直接支援；非射击职业（eater/wreck）也前往支援
		if shoot_tool_index >= 0 or _has_tool_id("eater") or _has_tool_id("wreck"):
			scores[DecisionAction.ASSIST] = 80.0 + \
					(10.0 if difficulty == Difficulty.HARD else 0.0)

	# 防御己方土地：检测到己方土地被攻击（自己发现或队友广播）
	var farm_threat_pos := _get_team_farm_threat()
	if farm_threat_pos == INVALID_POSITION:
		farm_threat_pos = _detect_farm_threat()
	if farm_threat_pos != INVALID_POSITION:
		# 有防御能力的职业前往防御：eater 吸弹 / 射击反击 / wreck 反击
		var can_defend := _has_tool_id("eater") or shoot_tool_index >= 0 or \
				_has_tool_id("wreck") or wand_index >= 0
		if can_defend:
			# 限制防御人数：若已有队友在防御，大幅降分，确保有人继续种地
			var defenders: int = int(_defending_count.get(team_id, 0))
			# 正在防御的自己不算
			if state == AIState.DEFEND_FARM:
				defenders = maxi(0, defenders - 1)
			var defend_penalty := 0.0
			if defenders >= 2:
				defend_penalty = 80.0  # 已有2人防御，其他人基本不防御
			elif defenders >= 1:
				defend_penalty = 30.0  # 已有1人防御，其他人降优先级
			var defend_distance := global_position.distance_to(farm_threat_pos)
			var proximity_bonus := maxf(0.0, 30.0 - defend_distance * 0.5)
			scores[DecisionAction.DEFEND_FARM] = 110.0 + proximity_bonus + \
					threat * 20.0 + (8.0 if difficulty == Difficulty.HARD else 0.0) - \
					defend_penalty

	# 侦查进攻：有进攻工具（射击/破坏/雷击）但无明确目标时，主动前往敌方区域侦查
	# 分数上限控制在 70 以下，避免压制防御和种地等更高优先级行为
	var has_offense_tool := shoot_tool_index >= 0 or wand_index >= 0 or _has_tool_id("wreck")
	if has_offense_tool:
		scores[DecisionAction.SCOUT] = 35.0 + \
				minf(20.0, enemy_target_count * 1.0) + \
				minf(15.0, enemy_tool_count * 1.5) + \
				(8.0 if difficulty == Difficulty.HARD else 0.0)

	var decision_noise := 13.0 if difficulty == Difficulty.EASY else 2.0
	for action in scores:
		if scores[action] > -INF:
			scores[action] += rng.randf_range(-decision_noise, decision_noise)

	var chosen_action := DecisionAction.PATROL
	var chosen_score := -INF
	for action in scores:
		if scores[action] > chosen_score:
			chosen_action = action
			chosen_score = scores[action]

	last_decision = chosen_action
	last_utility_scores = scores.duplicate()

	match chosen_action:
		DecisionAction.HARVEST:
			_start_plot_action(AIState.MOVE_TO_HARVEST, mature_plot)
		DecisionAction.SHIELD:
			placement_tool_index = _find_tool_index("shield_door")
			_start_plot_action(AIState.MOVE_TO_PLACE, shield_plot)
		DecisionAction.TURRET:
			placement_tool_index = _find_tool_index("auto_shooter")
			_start_plot_action(AIState.MOVE_TO_PLACE, turret_plot)
		DecisionAction.ANTIAIR:
			placement_tool_index = _find_tool_index("anti_air")
			_start_antiair_action(antiair_pos)
		DecisionAction.SOW:
			_start_plot_action(AIState.MOVE_TO_SOW, sow_plot)
		DecisionAction.ATTACK:
			_start_attack(enemy_plot, front_z)
		DecisionAction.SHOOT_PLAYER:
			_set_focus_target(target_player)
			state = AIState.SHOOT_PLAYER
			state_timer = rng.randf_range(0.28, 0.5) if difficulty == Difficulty.EASY \
				else rng.randf_range(0.08, 0.16)
			movement_target = INVALID_POSITION
		DecisionAction.CAST_WAND:
			_set_focus_target(target_player)
			state = AIState.CAST_WAND
			state_timer = 0.1
			movement_target = INVALID_POSITION
		DecisionAction.ASSIST:
			state = AIState.ASSIST
			state_timer = 0.15
			movement_target = INVALID_POSITION
		DecisionAction.SCOUT:
			_start_scout()
		DecisionAction.DEFEND_FARM:
			_start_defend_farm(farm_threat_pos)
		_:
			_start_patrol()

	if print_decisions:
		var target_pos := "(none)"
		if is_instance_valid(target_plot):
			target_pos = "(%.1f, %.1f) owner=%s" % [target_plot.global_position.x, target_plot.global_position.z, target_plot.land_owner]
		elif movement_target != INVALID_POSITION:
			target_pos = "(%.1f, %.1f)" % [movement_target.x, movement_target.z]
		print("AIPlayerv2 decision=", DecisionAction.keys()[chosen_action],
				" score=", snappedf(chosen_score, 0.1), " prof=", profession,
				" team=", team_id, " target=", target_pos)


func _start_attack(plot: Node3D, front_z: float = INF) -> void:
	target_plot = plot
	# 不再固定在前线射击，而是靠近目标到有效射程（18m）内再攻击
	# wreck 炮弹速度 30、重力 18，18m 距离平射即可命中
	var target_pos := plot.global_position
	var to_target := target_pos - global_position
	to_target.y = 0.0
	var dist := to_target.length()
	var effective_range := 18.0
	if dist > effective_range:
		# 靠近目标到有效射程
		movement_target = target_pos - to_target.normalized() * effective_range
		movement_target.y = global_position.y
	else:
		# 已在射程内，原地射击
		movement_target = global_position
	state = AIState.MOVE_TO_ATTACK
	state_timer = 8.0


func _start_plot_action(next_state: int, plot: Node3D) -> void:
	target_plot = plot
	movement_target = _approach_position(plot.global_position)
	state = next_state
	state_timer = 7.0


func _start_antiair_action(pos: Vector3) -> void:
	movement_target = pos
	target_plot = null
	state = AIState.MOVE_TO_PLACE
	state_timer = 7.0


func _start_patrol() -> void:
	var patrol_min := _patrol_min()
	var patrol_max := _patrol_max()
	patrol_target = Vector3(
		rng.randf_range(patrol_min.x, patrol_max.x),
		global_position.y,
		rng.randf_range(patrol_min.z, patrol_max.z)
	)
	movement_target = patrol_target
	state = AIState.PATROL
	state_timer = rng.randf_range(2.5, 5.0) if difficulty == Difficulty.EASY \
			else rng.randf_range(0.7, 1.4)


## 前往己方被威胁的土地进行防御。
## 到达后根据职业能力选择防御方式：eater 吸弹 / 射击反击 / wreck 反击。
func _start_defend_farm(threat_pos: Vector3) -> void:
	defend_target = threat_pos
	# 移动到威胁点附近（偏移 2.5m 避免站在爆炸中心）
	var offset := global_position - threat_pos
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, -1.0)
	movement_target = threat_pos + offset.normalized() * 2.5
	_exit_defend_state()
	state = AIState.DEFEND_FARM
	_enter_defend_state()
	state_timer = 8.0


## 进入 DEFEND_FARM 状态时增加计数
func _enter_defend_state() -> void:
	_defending_count[team_id] = int(_defending_count.get(team_id, 0)) + 1


## 退出 DEFEND_FARM 状态时减少计数
func _exit_defend_state() -> void:
	if state == AIState.DEFEND_FARM:
		_defending_count[team_id] = maxi(0, int(_defending_count.get(team_id, 0)) - 1)


## 防御动作执行：到达防御点后，根据威胁类型和职业能力智能选择防御方式。
func _perform_defend_action() -> void:
	if defend_target == INVALID_POSITION:
		_schedule_think(0.1)
		return
	# 检测附近是否有敌方炮弹需要吸收
	if _has_tool_id("eater"):
		var danger := _find_dangerous_bullet()
		if danger != null:
			_begin_absorption(danger)
			return
	# 检测可视范围内的敌方玩家，射击反击
	var enemy := _find_visible_enemy_player()
	if is_instance_valid(enemy):
		var shoot_idx := _find_shooting_tool_index()
		if shoot_idx >= 0 and _tool_ready(shoot_idx):
			target_player = enemy
			_set_focus_target(enemy)
			_shoot_player()
			return
		# wand 反击
		var wand_idx := _find_tool_index("wand")
		if wand_idx >= 0 and _tool_ready(wand_idx):
			target_player = enemy
			_set_focus_target(enemy)
			_cast_wand()
			return
	# 没有直接目标，检查威胁是否还在
	var current_threat := _detect_farm_threat()
	if current_threat == INVALID_POSITION and _get_team_farm_threat() == INVALID_POSITION:
		_schedule_think(0.1)
		return
	# 若有 wreck 且威胁点有敌方工具/作物，反击敌方土地
	if _has_tool_id("wreck"):
		var wreck_idx := _find_tool_index("wreck")
		if wreck_idx >= 0 and _tool_ready(wreck_idx):
			var enemy_team := "red" if team_id == "blue" else "blue"
			var enemy_plot := _nearest_plot(_get_team_plots(enemy_team), false, false)
			if enemy_plot != null:
				target_plot = enemy_plot
				_attack_target()
				return
	# 继续待命防御
	defend_target = current_threat if current_threat != INVALID_POSITION else defend_target


func _start_scout() -> void:
	# 侦查进攻：前往敌方农田区域中心附近，途中遇敌射击/遇作物破坏
	var enemy_team := "red" if team_id == "blue" else "blue"
	var enemy_plots := _get_team_plots(enemy_team)
	var scout_target := INVALID_POSITION
	if not enemy_plots.is_empty():
		# 计算敌方农田中心的水平坐标
		var sum := Vector3.ZERO
		var count := 0
		for plot in enemy_plots:
			if _is_valid_plot(plot):
				sum += plot.global_position
				count += 1
		if count > 0:
			scout_target = sum / float(count)
			# 加随机偏移避免每次去同一点
			scout_target.x += rng.randf_range(-8.0, 8.0)
			scout_target.z += rng.randf_range(-4.0, 4.0)
			scout_target.y = global_position.y
	if scout_target == INVALID_POSITION:
		# 找不到敌方农田，回退到敌方方向
		scout_target = global_position + Vector3(
			rng.randf_range(-10.0, 10.0), 0.0,
			15.0 if team_id == "blue" else -15.0
		)
	movement_target = scout_target
	state = AIState.SCOUT
	state_timer = rng.randf_range(4.0, 7.0)


func _attack_line_z() -> float:
	# 蓝队在 z 负侧，攻击线在己方前线
	var plots := _get_team_plots(team_id)
	var front_z := _frontline_z(plots)
	if is_inf(front_z):
		return -3.8 if team_id == "blue" else 3.8
	return front_z


func _patrol_min() -> Vector3:
	return Vector3(-25.0, 0.0, -25.0) if team_id == "blue" else \
			Vector3(-25.0, 0.0, 3.6)


func _patrol_max() -> Vector3:
	return Vector3(25.0, 0.0, -3.6) if team_id == "blue" else \
			Vector3(25.0, 0.0, 25.0)


# ===========================================================================
# 移动与寻路
# ===========================================================================

func _update_movement(delta: float) -> void:
	if not movement_enabled:
		_apply_movement(Vector3.ZERO, delta)
		return

	var desired := Vector3.ZERO
	if movement_target != INVALID_POSITION and state not in [
		AIState.THINK, AIState.SOW, AIState.HARVEST, AIState.ATTACK,
		AIState.PLACE, AIState.SHOOT_PLAYER, AIState.CAST_WAND, AIState.ASSIST,
		AIState.STUNNED
	]:
		desired = _compute_move_direction()

	if desired != Vector3.ZERO and front_probe.is_colliding():
		var side := global_transform.basis.x
		if rng.randf() < 0.5:
			side = -side
		desired = (desired * 0.35 + side * 0.65).normalized()
		_try_jump()
	elif desired != Vector3.ZERO and difficulty == Difficulty.HARD and \
			rng.randf() < 0.004:
		_try_jump()

	# AI 间分离力，避免重叠堆叠
	var separation := _compute_separation()
	if separation != Vector3.ZERO:
		if desired == Vector3.ZERO:
			desired = separation
		else:
			desired = (desired * 0.7 + separation * 0.3).normalized()

	_apply_movement(desired, delta)


## 计算与其他 AI 的分离力，避免重叠
func _compute_separation() -> Vector3:
	var push := Vector3.ZERO
	for node in get_tree().get_nodes_in_group("ai_players"):
		if node == self or not is_instance_valid(node) or not node is CharacterBody3D:
			continue
		var other := node as CharacterBody3D
		if other.is_dead if "is_dead" in other else false:
			continue
		var diff := global_position - other.global_position
		diff.y = 0.0
		var dist_sq := diff.length_squared()
		if dist_sq > 0.01 and dist_sq < 2.25:  # 1.5m 内
			var dist := sqrt(dist_sq)
			push += diff.normalized() * (1.5 - dist) / 1.5
	return push.normalized() if push.length_squared() > 0.01 else Vector3.ZERO


func _compute_move_direction() -> Vector3:
	if use_navigation:
		nav_agent.target_position = movement_target
		# 若目标可达（有有效路径），用导航方向；否则回退直线
		if not nav_agent.is_navigation_finished():
			var next_pos := nav_agent.get_next_path_position()
			if not next_pos.is_equal_approx(global_position):
				var dir := next_pos - global_position
				dir.y = 0.0
				if dir.length_squared() > 0.01:
					return dir.normalized()
	# 回退直线（NavMesh 未烘焙或目标不可达时）
	var dir := movement_target - global_position
	dir.y = 0.0
	if dir.length_squared() > 0.04:
		return dir.normalized()
	return Vector3.ZERO


func _apply_movement(direction: Vector3, delta: float) -> void:
	var base_speed := 3.6 if difficulty == Difficulty.EASY else 5.2
	var speed := base_speed
	if slow_remaining > 0.0:
		speed *= 0.5
	var horizontal_step := direction * speed + rubber_knockback
	var proposed := global_position + Vector3(horizontal_step.x, 0.0, horizontal_step.z) * delta
	if WaterBody3D.is_navigation_blocked(proposed):
		# Keep this legacy AI consistent with the current navigation actors.
		direction = Vector3.ZERO
		rubber_knockback.x = 0.0
		rubber_knockback.z = 0.0
	var acceleration := 13.0 if difficulty == Difficulty.EASY else 20.0
	var desired_velocity := direction * speed
	desired_velocity += rubber_knockback
	rubber_knockback = rubber_knockback.move_toward(Vector3.ZERO, 16.0 * delta)
	velocity.x = move_toward(velocity.x, desired_velocity.x, acceleration * delta)
	velocity.z = move_toward(velocity.z, desired_velocity.z, acceleration * delta)

	if not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if direction.length_squared() > 0.01:
		var desired_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(rotation.y, desired_yaw, minf(1.0, delta * 8.0))

	move_and_slide()
	_update_ai_animation(direction)
	_update_upper_body_aim(delta)
	_update_tool_aim_alignment()


func _try_jump() -> void:
	if is_on_floor() and jump_timer <= 0.0:
		velocity.y = 3.0 if difficulty == Difficulty.EASY else 3.8
		jump_timer = 0.8
		_play_body_animation(&"JumpStart", 0.05)


# ===========================================================================
# 工具行为
# ===========================================================================

func _sow_target() -> void:
	if not _is_valid_plot(target_plot) or not _plot_is_empty(target_plot):
		return
	var idx := _find_tool_index("sprout_blaster")
	if idx < 0 or not _tool_ready(idx):
		return
	_equip_tool(idx)
	_aim_tool(target_plot.global_position)
	_prepare_lookat_for_target(target_plot.global_position)
	_set_tool_action(idx)
	_emit_tool()
	# 回退：若工具未成功播种，直接调用 plant
	if _plot_is_empty(target_plot):
		var global_var := get_node_or_null("/root/GlobalVar")
		if global_var != null and not global_var.plant_item_list.is_empty():
			var seed_name: String = global_var.plant_item_list[
				rng.randi_range(0, global_var.plant_item_list.size() - 1)]
			target_plot.plant(seed_name, team_id)
	_set_cooldown(idx)


func _harvest_target() -> void:
	if not _is_valid_plot(target_plot) or not target_plot.can_harvest:
		return
	var idx := _find_tool_index("eater")
	if idx < 0 or not _tool_ready(idx):
		return
	_equip_tool(idx)
	_aim_tool(target_plot.global_position)
	_set_tool_action(idx)
	_emit_tool()
	if target_plot.can_harvest:
		var absorb_point := held_tool.global_position + Vector3.UP * 0.2
		target_plot.harvest(absorb_point)
	_set_cooldown(idx)


func _attack_target() -> void:
	if not _is_valid_plot(target_plot):
		return
	var idx := _find_tool_index("wreck")
	if idx < 0 or not _tool_ready(idx):
		return
	_equip_tool(idx)
	var aim_point := target_plot.global_position + Vector3.UP * 0.35
	var jitter := 0.75 if difficulty == Difficulty.EASY else 0.18
	aim_point += Vector3(
		rng.randf_range(-jitter, jitter),
		rng.randf_range(0.0, jitter * 0.4),
		rng.randf_range(-jitter, jitter)
	)
	# 抛物线仰角补偿：wreck 炮弹速度 30、重力 18
	# 根据水平距离计算抬高量，使炮弹能命中目标
	var horizontal_dist := _horizontal_distance(global_position, aim_point)
	if horizontal_dist > 3.0:
		var v := 30.0  # 炮弹初速度
		var g := 18.0  # 重力
		# 抛物线公式：抬高高度 h = g * d^2 / (2 * v^2)
		var elevation := g * horizontal_dist * horizontal_dist / (2.0 * v * v)
		# 困难模式精确补偿，简单模式补偿不足（模拟不熟练）
		if difficulty == Difficulty.EASY:
			elevation *= 0.7
		aim_point.y += elevation
	_aim_tool(aim_point)
	_set_tool_action(idx)
	_emit_tool()
	_set_cooldown(idx)


func _shoot_player() -> void:
	if not is_instance_valid(target_player):
		return
	var idx := _find_shooting_tool_index()
	if idx < 0 or not _tool_ready(idx):
		return
	if not _has_clear_shot(target_player):
		return
	_equip_tool(idx)
	var aim_point := target_player.global_position + Vector3.UP * 1.0
	if difficulty == Difficulty.EASY:
		aim_point += Vector3(
			rng.randf_range(-0.35, 0.35),
			rng.randf_range(-0.2, 0.35),
			rng.randf_range(-0.35, 0.35)
		)
	_aim_tool(aim_point)
	_set_tool_action(idx)
	_emit_tool()
	_set_cooldown(idx)


func _cast_wand() -> void:
	if not is_instance_valid(target_player):
		return
	var idx := _find_tool_index("wand")
	if idx < 0 or not _tool_ready(idx):
		return
	_equip_tool(idx)
	var aim_point := target_player.global_position + Vector3.UP * 1.0
	_aim_tool(aim_point)
	# 准备 LookAtTarget 指向目标，供 Wand.gd 的 emit() 使用
	_prepare_lookat_for_target(aim_point)
	_set_tool_action(idx)
	_emit_tool()
	_set_cooldown(idx)


func _assist_action() -> void:
	var ally := _find_ally_in_trouble()
	if not is_instance_valid(ally):
		return
	# 朝 ally 附近的威胁方向射击
	var idx := _find_shooting_tool_index()
	if idx < 0 or not _tool_ready(idx):
		return
	# 尝试找攻击者
	var attacker := ally.get("last_attacker") as CharacterBody3D
	if is_instance_valid(attacker) and _has_clear_shot(attacker):
		target_player = attacker
		_shoot_player()
	elif is_instance_valid(target_player) and _has_clear_shot(target_player):
		_shoot_player()


func _place_defence() -> void:
	if placement_tool_index < 0 or not _tool_ready(placement_tool_index):
		return
	var tool_id := str(local_tools[placement_tool_index].get("id", ""))
	_equip_tool(placement_tool_index)

	if tool_id == "anti_air":
		# AntiAir 不需要 FarmTile，在到达点放置
		_place_antiair()
		_set_cooldown(placement_tool_index)
		return

	if not _is_valid_plot(target_plot) or not _plot_accepts_tool(target_plot):
		return
	# 放置前让 AI 面向敌方方向，确保护盾/炮台朝向正确（防御面朝敌方）
	var enemy_dir_z := 1.0 if team_id == "blue" else -1.0
	var face_target := target_plot.global_position + Vector3(0, 0, enemy_dir_z * 5.0)
	_aim_tool(face_target)
	_prepare_lookat_for_target(target_plot.global_position)
	var tool_name := _tool_id_to_scene_name(tool_id)
	var count_before := _count_placed_tool(tool_name)
	_set_tool_action(placement_tool_index)
	_emit_tool()
	# 回退：若射线未放置成功，直接调 setting_tool
	if _count_placed_tool(tool_name) == count_before and \
			not is_instance_valid(target_plot.tool_child):
		target_plot.setting_tool(tool_name, team_id, self)
	_set_cooldown(placement_tool_index)


func _place_antiair() -> void:
	# AntiAir 的 emit() 用 LookAtTarget.get_collision_point() 在 gameworld 放置
	# 将 LookAtTarget 朝向当前移动目标地面点
	var target_pos := movement_target if movement_target != INVALID_POSITION \
			else global_position + Vector3(0, 0, -3)
	_prepare_lookat_for_target(target_pos)
	_set_tool_action(placement_tool_index)
	_emit_tool()


# ===========================================================================
# 子弹吸收
# ===========================================================================

func _should_scan_for_bullets() -> bool:
	return bullet_scan_timer <= 0.0 and state != AIState.ABSORB


func _reaction_interval() -> float:
	return rng.randf_range(0.5, 0.8) if difficulty == Difficulty.EASY \
			else rng.randf_range(0.25, 0.4)


func _find_dangerous_bullet() -> CharacterBody3D:
	var radius := 4.0 if difficulty == Difficulty.EASY else 6.0
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP)
	query.collision_mask = 32
	query.collide_with_bodies = true
	query.exclude = [get_rid()]
	var results := get_world_3d().direct_space_state.intersect_shape(query, 16)
	var best: CharacterBody3D
	var best_distance := INF
	for result in results:
		var collider = result.get("collider")
		if _is_boom_bullet(collider):
			if collider.get_bullet_owner() == team_id:
				continue
			var distance := global_position.distance_squared_to(collider.global_position)
			if distance < best_distance:
				best = collider
				best_distance = distance
	return best


## 检测己方土地附近的威胁（敌方炮弹/敌方玩家/作物被破坏），返回威胁位置。
func _detect_farm_threat() -> Vector3:
	var own_plots := _get_team_plots(team_id)
	if own_plots.is_empty():
		return INVALID_POSITION
	# 收集敌方玩家列表
	var enemies: Array[CharacterBody3D] = []
	for node in get_tree().get_nodes_in_group("ai_players"):
		if not is_instance_valid(node) or not node is CharacterBody3D:
			continue
		if node == self:
			continue
		var enemy := node as CharacterBody3D
		if not enemy.has_method("get_combat_team"):
			continue
		if str(enemy.call("get_combat_team")) == team_id:
			continue
		enemies.append(enemy)
	# 策略1：检测敌方玩家是否在己方土地 30m 范围内
	var threat_radius := 30.0
	var threat_radius_sq := threat_radius * threat_radius
	var current_content_count := 0
	for plot in own_plots:
		if not _is_valid_plot(plot):
			continue
		var has_content := not _plot_is_empty(plot) or is_instance_valid(plot.tool_child)
		if has_content:
			current_content_count += 1
		var plot_pos: Vector3 = plot.global_position
		for enemy in enemies:
			if plot_pos.distance_squared_to(enemy.global_position) <= threat_radius_sq:
				return plot_pos
	# 策略2：检测作物/工具数量是否减少（被破坏则触发防御）
	if last_farm_content_count < 0:
		last_farm_content_count = current_content_count
	elif current_content_count < last_farm_content_count:
		last_farm_content_count = current_content_count
		var nearest_enemy_pos := INVALID_POSITION
		var nearest_dist_sq := 80.0 * 80.0
		for enemy in enemies:
			var d: float = global_position.distance_squared_to(enemy.global_position)
			if d < nearest_dist_sq:
				nearest_dist_sq = d
				nearest_enemy_pos = enemy.global_position
		if nearest_enemy_pos != INVALID_POSITION:
			return nearest_enemy_pos
	else:
		last_farm_content_count = current_content_count
	# 策略3：检测己方前线土地附近是否有敌方炮弹
	var front_z := _frontline_z(own_plots)
	if not is_inf(front_z):
		for plot in own_plots:
			if not _is_valid_plot(plot):
				continue
			if _plot_is_empty(plot) and not is_instance_valid(plot.tool_child):
				continue
			if absf(plot.global_position.z - front_z) > 5.0:
				continue
			var plot_pos: Vector3 = plot.global_position
			var sphere := SphereShape3D.new()
			sphere.radius = 8.0
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = sphere
			query.transform = Transform3D(Basis.IDENTITY, plot_pos + Vector3.UP * 2.0)
			query.collision_mask = 32  # Bullets 层
			query.collide_with_bodies = true
			var results := get_world_3d().direct_space_state.intersect_shape(query, 4)
			for result in results:
				var collider = result.get("collider")
				if _is_boom_bullet(collider) and \
						str(collider.get_bullet_owner()) != team_id:
					return plot_pos
	return INVALID_POSITION


## 广播己方土地威胁给队友（静态协作）
func _broadcast_farm_threat(threat_position: Vector3) -> void:
	_farm_threats[team_id] = {
		"position": threat_position,
		"expire": THREAT_MEMORY_SECONDS,
		"reporter": self,
	}


## 获取团队广播的威胁位置（可能是队友发现的）
func _get_team_farm_threat() -> Vector3:
	if not _farm_threats.has(team_id):
		return INVALID_POSITION
	var threat: Dictionary = _farm_threats[team_id]
	return threat.get("position", INVALID_POSITION)


func _begin_absorption(bullet: CharacterBody3D) -> void:
	if not is_instance_valid(bullet):
		return
	target_bullet = bullet
	state = AIState.ABSORB
	state_timer = 2.5
	movement_target = INVALID_POSITION
	var idx := _find_tool_index("eater")
	if idx >= 0:
		_equip_tool(idx)
	_aim_tool(bullet.global_position)
	target_bullet.set_physics_process(false)
	target_bullet.collision_layer = 0
	target_bullet.collision_mask = 0
	target_bullet.velocity = Vector3.ZERO
	_set_eater_particles(true)


func _update_absorption(delta: float) -> void:
	if not is_instance_valid(target_bullet):
		_finish_absorption()
		return
	var mouth := tool_socket.global_position - tool_socket.global_transform.basis.z * 0.65
	var to_mouth := mouth - target_bullet.global_position
	_aim_tool(target_bullet.global_position)
	var pull_speed := 9.0 if difficulty == Difficulty.EASY else 15.0
	target_bullet.global_position += to_mouth.normalized() * \
			minf(to_mouth.length(), pull_speed * delta)
	var mesh := target_bullet.get_node_or_null("MeshInstance3D")
	if mesh is Node3D:
		var visual_scale := clampf(to_mouth.length() / 4.0, 0.15, 1.0)
		mesh.scale = Vector3.ONE * visual_scale
	if to_mouth.length() <= 0.3 or state_timer <= 0.0:
		target_bullet.queue_free()
		_finish_absorption()


func _finish_absorption() -> void:
	target_bullet = null
	_set_eater_particles(false)
	var idx := _find_tool_index("eater")
	if idx >= 0:
		_set_cooldown(idx)
	_schedule_think(0.1)


func _set_eater_particles(enabled: bool) -> void:
	if not is_instance_valid(held_tool):
		return
	var particles := held_tool.get_node_or_null("GPUParticles3D")
	if particles is GPUParticles3D:
		particles.emitting = enabled


# ===========================================================================
# 工具装备/瞄准/动画
# ===========================================================================

func _equip_default_tool() -> void:
	if local_tools.is_empty():
		return
	# 优先装备第一个非 wand 工具（Wand 实例化会触发 owner_node 类型报错）
	for i in range(local_tools.size()):
		if profession_tool_ids[i] != "wand":
			_equip_tool(i)
			return
	# 全是 wand 的情况只能装备 wand
	_equip_tool(0)


func _equip_tool(local_index: int) -> void:
	if local_index < 0 or local_index >= local_tools.size():
		return
	if current_tool_index == local_index and is_instance_valid(held_tool):
		return
	if is_instance_valid(held_tool):
		held_tool.queue_free()
	var definition: Dictionary = local_tools[local_index]
	var tool_scene := load(str(definition.get("path"))) as PackedScene
	if tool_scene == null:
		push_error("AI could not load tool: " + str(definition.get("path")))
		return
	held_tool = tool_scene.instantiate() as Node3D
	tool_socket.add_child(held_tool)
	held_tool.position = definition.get("grip_position", Vector3.ZERO)
	held_tool.rotation_degrees = definition.get("grip_rotation", Vector3.ZERO)
	held_tool.scale = definition.get("grip_scale", Vector3.ONE)
	held_tool.set("tool_owner", team_id)
	current_tool_index = local_index
	# 初始化瞄准目标为正前方，避免 _update_tool_aim_alignment 朝向 (0,0,0)
	aim_target_position = global_position + -global_transform.basis.z * 5.0


func _aim_tool(world_target: Vector3) -> void:
	var target := world_target
	if target.distance_squared_to(tool_socket.global_position) < 0.01:
		target += -global_transform.basis.z
	upper_body_look_target.global_position = target
	# 先让 AI 身体朝向目标，确保工具挂载方向正确（wreck 炮弹沿工具 -Z 发射）
	var dir_to_target := target - global_position
	dir_to_target.y = 0.0
	if dir_to_target.length_squared() > 0.01:
		var desired_yaw := atan2(-dir_to_target.x, -dir_to_target.z)
		rotation.y = desired_yaw
	# 记录瞄准目标，供 _update_tool_aim_alignment 每帧重新对齐 tool_socket。
	# tool_socket 挂在 BoneAttachment3D 下，骨骼动画/IK 每帧都会改变它的全局
	# 朝向，单次 look_at 会被骨骼姿态覆盖，必须每帧补偿。
	aim_target_position = target
	# 立即对齐一次：_emit_tool 可能在 _update_tool_aim_alignment 之前被调用
	# （_update_state 在 _apply_movement 之前），发射时工具必须已对准目标。
	_update_tool_aim_alignment()


func _emit_tool() -> void:
	if is_instance_valid(held_tool) and held_tool.has_method("emit"):
		held_tool.emit()


func _prepare_lookat_for_target(target_pos: Vector3) -> void:
	# 将 LookAtTarget RayCast3D 定位到头部位置，朝向 target_pos
	lookat_ray.global_position = $Head.global_position
	var dir := (target_pos - lookat_ray.global_position).normalized()
	if dir.length_squared() > 0.001:
		lookat_ray.global_transform = lookat_ray.global_transform.looking_at(
			lookat_ray.global_position + dir, Vector3.UP)
		lookat_ray.target_position = dir * 30.0
	lookat_ray.enabled = true
	lookat_ray.force_raycast_update()


func _set_tool_action(local_index: int) -> void:
	if not is_instance_valid(appearance_player):
		return
	action_anim_locked = true
	var definition: Dictionary = local_tools[local_index]
	match str(definition.get("category", "utility")):
		TOOL_CATEGORY_SHOOTING:
			appearance_player.play(&"ShootOneHand", 0.05)
		"melee":
			appearance_player.play(&"PunchRight", 0.05)
		_:
			appearance_player.play(&"ToolUseRight", 0.05)


func _tool_ready(local_index: int) -> bool:
	return cooldowns[local_index] <= 0.0


func _set_cooldown(local_index: int) -> void:
	var multiplier := 1.45 if difficulty == Difficulty.EASY else 0.85
	cooldowns[local_index] = float(
		local_tools[local_index].get("cooldown", 1.0)) * multiplier


func _has_tool_id(tool_id: String) -> bool:
	return profession_tool_ids.has(tool_id)


func _find_tool_index(tool_id: String) -> int:
	for i in range(profession_tool_ids.size()):
		if profession_tool_ids[i] == tool_id:
			return i
	return -1


func _find_shooting_tool_index() -> int:
	# 优先级：nail_gun > rubber_revolver > flame_gun > freeze_gun
	for tid in ["nail_gun", "rubber_revolver", "flame_gun", "freeze_gun"]:
		var idx := _find_tool_index(tid)
		if idx >= 0 and _tool_ready(idx):
			return idx
	return -1


func _tool_id_to_scene_name(tool_id: String) -> String:
	match tool_id:
		"auto_shooter":
			return "AutoShooter"
		"shield_door":
			return "ShieldDoor"
		"anti_air":
			return "AntiAir"
	return ""


# ===========================================================================
# 地块工具函数
# ===========================================================================

func _get_team_plots(team: String) -> Array:
	var farmland_manager := get_node_or_null("/root/Farmlandmanager")
	if farmland_manager == null:
		return []
	return farmland_manager.get_team_plots(team)


func _get_claimable_plots() -> Array:
	var farmland_manager := get_node_or_null("/root/Farmlandmanager")
	if farmland_manager == null:
		return []
	return farmland_manager.get_claimable_plots(team_id)


func _get_neutral_plots_with_content() -> Array:
	# 中立农田（land_owner 为空）里有作物或工具的地块，用于争夺中心高地
	var farmland_manager := get_node_or_null("/root/Farmlandmanager")
	if farmland_manager == null:
		return []
	var result: Array = []
	for tile in farmland_manager.get_all_plots():
		if not _is_valid_plot(tile):
			continue
		if tile.land_owner != "":
			continue  # 已归属队伍的跳过
		if not _plot_is_empty(tile) or is_instance_valid(tile.tool_child):
			result.append(tile)
	return result


func _nearest_plot(plots: Array, require_mature: bool, require_empty: bool) -> Node3D:
	var best: Node3D
	var best_score := INF
	for item in plots:
		if not _is_valid_plot(item):
			continue
		var plot := item as Node3D
		if require_mature and not plot.can_harvest:
			continue
		if require_empty and not _plot_is_empty(plot):
			continue
		var score := global_position.distance_squared_to(plot.global_position)
		if difficulty == Difficulty.EASY:
			score += rng.randf_range(0.0, 30.0)
		if score < best_score:
			best = plot
			best_score = score
	return best


func _choose_enemy_target() -> Node3D:
	var candidates: Array[Node3D] = []
	var enemy_team := "red" if team_id == "blue" else "blue"
	# 敌方队伍地块
	for item in _get_team_plots(enemy_team):
		if _is_valid_plot(item):
			var plot := item as Node3D
			if not _plot_is_empty(plot) or is_instance_valid(plot.tool_child):
				if not _is_claimed("attack", plot):
					candidates.append(plot)
	# 中立农田（无主）里有非本队作物/工具的，也作为攻击候选（争夺中心高地）
	for item in _get_neutral_plots_with_content():
		if _is_valid_plot(item) and not _is_claimed("attack", item):
			candidates.append(item)
	if candidates.is_empty():
		return null
	if difficulty == Difficulty.EASY:
		return candidates[rng.randi_range(0, candidates.size() - 1)]
	var best := candidates[0]
	var best_score := -INF
	for plot in candidates:
		var score := 3.0 if plot.can_harvest else 1.0
		if is_instance_valid(plot.tool_child):
			score += 4.0
		score -= global_position.distance_to(plot.global_position) * 0.02
		if score > best_score:
			best = plot
			best_score = score
	return best


func _choose_frontline_shield_plot(
		own_plots: Array = [],
		front_z: float = INF,
		farm_spacing: float = 2.2
) -> Node3D:
	if _count_placed_tool("ShieldDoor") >= _shield_limit():
		return null
	if is_inf(front_z):
		return null
	var existing_shields := _get_tool_plots("ShieldTool", own_plots)
	var desired_xs := _desired_shield_xs()
	var best: Node3D
	var best_score := INF
	for slot_index in range(desired_xs.size()):
		var desired_x: float = desired_xs[slot_index]
		var slot_occupied := false
		for shield_plot in existing_shields:
			if absf(shield_plot.global_position.x - desired_x) <= farm_spacing * 0.75:
				slot_occupied = true
				break
		if slot_occupied:
			continue
		for item in own_plots:
			if not _is_valid_plot(item) or not _plot_accepts_tool(item):
				continue
			if _is_claimed("place", item):
				continue
			var plot := item as Node3D
			if absf(plot.global_position.z - front_z) > 0.35:
				continue
			var score := absf(plot.global_position.x - desired_x)
			score += slot_index * 0.2
			score += _horizontal_distance(global_position, plot.global_position) * 0.01
			if score < best_score:
				best = plot
				best_score = score
	return best


func _choose_paired_turret_plot(
		own_plots: Array = [],
		farm_spacing: float = 2.2
) -> Node3D:
	if _count_placed_tool("AutoShooter") >= _turret_limit():
		return null
	var shield_plots := _get_tool_plots("ShieldTool", own_plots)
	if shield_plots.is_empty():
		return null
	var turret_plots := _get_tool_plots("AutoShooterTool", own_plots)
	var behind_direction := -1.0 if team_id == "blue" else 1.0
	var best: Node3D
	var best_score := INF
	for shield_plot in shield_plots:
		var desired := shield_plot.global_position + \
				Vector3(0.0, 0.0, behind_direction * farm_spacing)
		var already_paired := false
		for turret_plot in turret_plots:
			if _horizontal_distance(turret_plot.global_position, desired) < 0.8:
				already_paired = true
				break
		if already_paired:
			continue
		for item in own_plots:
			if not _is_valid_plot(item) or not _plot_accepts_tool(item):
				continue
			if _is_claimed("place", item):
				continue
			var plot := item as Node3D
			var pair_distance := _horizontal_distance(plot.global_position, desired)
			if pair_distance > farm_spacing * 0.6:
				continue
			var score := pair_distance + \
					_horizontal_distance(global_position, plot.global_position) * 0.01
			if score < best_score:
				best = plot
				best_score = score
	return best


func _choose_antiair_position(front_z: float = INF) -> Vector3:
	# 防空车不需要 FarmTile，找一个前线附近的空地
	if is_inf(front_z):
		var plots := _get_team_plots(team_id)
		front_z = _frontline_z(plots)
	if is_inf(front_z):
		front_z = -3.8 if team_id == "blue" else 3.8
	var behind := 2.0 if team_id == "blue" else -2.0
	return Vector3(
		rng.randf_range(-8.0, 8.0),
		global_position.y,
		front_z + behind
	)


func _choose_sow_plot(
		own_plots: Array = [],
		front_z: float = INF,
		farm_spacing: float = 2.2
) -> Node3D:
	var best: Node3D
	var best_score := INF
	# 优先在己方空地播种；己方无空地时才考虑中立农田（高地争夺）
	var own_empty: Array = []
	for item in own_plots:
		if _is_valid_plot(item) and _plot_is_empty(item) and \
				not _is_claimed("sow", item) and not _is_reserved_frontline_slot(item, front_z, farm_spacing):
			own_empty.append(item)
	var candidates: Array = own_empty if not own_empty.is_empty() else _get_claimable_plots()
	for item in candidates:
		if not _is_valid_plot(item) or not _plot_is_empty(item):
			continue
		if _is_claimed("sow", item):
			continue
		var plot := item as Node3D
		if _is_reserved_frontline_slot(plot, front_z, farm_spacing):
			continue
		var score := global_position.distance_squared_to(plot.global_position)
		# 己方农田额外加分（降低 score），确保优先种自己的地
		if plot.land_owner == team_id:
			score -= 400.0
		if difficulty == Difficulty.EASY:
			score += rng.randf_range(0.0, 30.0)
		if score < best_score:
			best = plot
			best_score = score
	return best


func _is_reserved_frontline_slot(
		plot: Node3D,
		front_z: float = INF,
		farm_spacing: float = 2.2
) -> bool:
	if is_inf(front_z) or absf(plot.global_position.z - front_z) > 0.35:
		return false
	for desired_x in _desired_shield_xs():
		if absf(plot.global_position.x - desired_x) <= farm_spacing * 0.6:
			return true
	return false


func _frontline_z(plots: Array) -> float:
	var result := -INF if team_id == "blue" else INF
	for item in plots:
		if not _is_valid_plot(item):
			continue
		if team_id == "blue":
			result = maxf(result, item.global_position.z)
		else:
			result = minf(result, item.global_position.z)
	return result


func _desired_shield_xs() -> Array:
	if difficulty == Difficulty.EASY:
		return [0.0]
	return [0.0, -8.8, 8.8]


func _shield_limit() -> int:
	return 1 if difficulty == Difficulty.EASY else 3


func _turret_limit() -> int:
	return 1 if difficulty == Difficulty.EASY else 3


func _antiair_limit() -> int:
	return 1 if difficulty == Difficulty.EASY else 2


func _get_tool_plots(script_class: String, plots: Array = []) -> Array[Node3D]:
	var result: Array[Node3D] = []
	# 若未提供 plots，回退到实时查询（兼容旧调用方）
	var source_plots: Array = plots if not plots.is_empty() else _get_team_plots(team_id)
	for item in source_plots:
		if not _is_valid_plot(item):
			continue
		var child = item.tool_child
		if is_instance_valid(child) and _script_class_name(child) == script_class:
			result.append(item)
	return result


func _compute_farm_stats(own_plots: Array, enemy_plots: Array) -> Dictionary:
	# 一次性遍历所有农田完成统计，避免 _choose_action 中重复遍历（性能优化）
	var result := {
		"mature_count": 0,
		"empty_count": 0,
		"planted_count": 0,
		"enemy_mature_count": 0,
		"enemy_tool_count": 0,
		"enemy_target_count": 0,
		"shield_count": 0,
		"turret_count": 0,
		"antiair_count": 0,
	}
	for item in own_plots:
		if not _is_valid_plot(item):
			continue
		if item.can_harvest:
			result["mature_count"] += 1
		if _plot_is_empty(item):
			result["empty_count"] += 1
		if item.seed_record != "":
			result["planted_count"] += 1
		var child = item.tool_child
		if is_instance_valid(child):
			var cls := _script_class_name(child)
			if cls == "ShieldTool":
				result["shield_count"] += 1
			elif cls == "AutoShooterTool":
				result["turret_count"] += 1
	for item in enemy_plots:
		if not _is_valid_plot(item):
			continue
		if item.can_harvest:
			result["enemy_mature_count"] += 1
		if is_instance_valid(item.tool_child):
			result["enemy_tool_count"] += 1
		if item.seed_record != "" or is_instance_valid(item.tool_child):
			result["enemy_target_count"] += 1
	# AntiAir 放在 gameworld，不在 FarmTile 上
	var world := get_node_or_null("/root/GlobalVar")
	if world and world.gameworld:
		for child in world.gameworld.get_children():
			if child is AntiAirTool and str(child.tool_owner) == team_id:
				result["antiair_count"] += 1
	return result


func _count_placed_tool(tool_name: String) -> int:
	if tool_name == "AutoShooter":
		return _get_tool_plots("AutoShooterTool").size()
	if tool_name == "ShieldDoor":
		return _get_tool_plots("ShieldTool").size()
	if tool_name == "AntiAir":
		# AntiAir 放在 gameworld，不在 FarmTile 上
		var count := 0
		var world := get_node_or_null("/root/GlobalVar")
		if world and world.gameworld:
			for child in world.gameworld.get_children():
				if child is AntiAirTool and str(child.tool_owner) == team_id:
					count += 1
		return count
	return 0


func _count_mature_plots(plots: Array) -> int:
	var count := 0
	for item in plots:
		if _is_valid_plot(item) and item.can_harvest:
			count += 1
	return count


func _count_empty_plots(plots: Array) -> int:
	var count := 0
	for item in plots:
		if _is_valid_plot(item) and _plot_is_empty(item):
			count += 1
	return count


func _count_planted_plots(plots: Array) -> int:
	var count := 0
	for item in plots:
		if _is_valid_plot(item) and item.seed_record != "":
			count += 1
	return count


func _count_all_placed_tools(plots: Array) -> int:
	var count := 0
	for item in plots:
		if _is_valid_plot(item) and is_instance_valid(item.tool_child):
			count += 1
	return count


func _count_attackable_plots(plots: Array) -> int:
	var count := 0
	for item in plots:
		if not _is_valid_plot(item):
			continue
		if item.seed_record != "" or is_instance_valid(item.tool_child):
			count += 1
	return count


func _approach_position(plot_position: Vector3) -> Vector3:
	var offset := global_position - plot_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, -1.0)
	return plot_position + offset.normalized() * 2.1


func _has_reached_plot(plot: Node3D, distance: float) -> bool:
	return _is_valid_plot(plot) and \
			_horizontal_distance(global_position, plot.global_position) <= distance


func _plot_is_empty(plot: Node3D) -> bool:
	return _is_valid_plot(plot) and plot.seed_record == "" and \
			not is_instance_valid(plot.tool_child)


func _plot_accepts_tool(plot: Node3D) -> bool:
	return _is_valid_plot(plot) and plot.land_owner == team_id and \
			plot.seed_record == "" and not is_instance_valid(plot.tool_child)


func _is_valid_plot(plot) -> bool:
	return plot is StaticBody3D and is_instance_valid(plot) and \
			plot.has_method("plant") and plot.has_method("setting_tool")


func _is_boom_bullet(body) -> bool:
	return body is CharacterBody3D and is_instance_valid(body) and \
			body.has_method("get_bullet_owner")


func _script_class_name(node) -> String:
	if not is_instance_valid(node):
		return ""
	var script = node.get_script()
	if script is Script:
		return script.get_global_name()
	return ""


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _farm_spacing() -> float:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null:
		return 2.2
	return manager.get_team_spacing(team_id, 2.2)


func _schedule_think(delay := -1.0) -> void:
	_exit_defend_state()
	state = AIState.THINK
	movement_target = INVALID_POSITION
	target_plot = null
	if delay >= 0.0:
		think_timer = delay
	else:
		think_timer = rng.randf_range(0.35, 0.65) if difficulty == Difficulty.EASY \
				else rng.randf_range(0.3, 0.5)


# ===========================================================================
# 敌人感知
# ===========================================================================

func _find_visible_enemy_player() -> CharacterBody3D:
	var nearest: CharacterBody3D
	var nearest_distance := player_shooting_range
	# 检查 human_players 组
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is CharacterBody3D or not is_instance_valid(node):
			continue
		var candidate := node as CharacterBody3D
		if candidate.has_method("get_combat_team") and \
				str(candidate.call("get_combat_team")) == team_id:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance and _has_clear_shot(candidate):
			nearest = candidate
			nearest_distance = distance
	# 检查 ai_players 组（含 AIPlayerv2）
	for node in get_tree().get_nodes_in_group("ai_players"):
		if node == self or not is_instance_valid(node):
			continue
		if not node is CharacterBody3D:
			continue
		var candidate := node as CharacterBody3D
		if candidate.has_method("get_combat_team") and \
				str(candidate.call("get_combat_team")) == team_id:
			continue
		var distance := global_position.distance_to(candidate.global_position)
		if distance <= nearest_distance and _has_clear_shot(candidate):
			nearest = candidate
			nearest_distance = distance
	return nearest


func _has_clear_shot(candidate: CharacterBody3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	var origin := global_position + Vector3.UP * 1.3
	var destination := candidate.global_position + Vector3.UP * 1.0
	var query := PhysicsRayQueryParameters3D.create(origin, destination, 138)
	query.exclude = [get_rid()]
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return not hit.is_empty() and hit.get("collider") == candidate


# ===========================================================================
# 协作系统
# ===========================================================================

func _claim_key(action: String, plot: Node3D) -> String:
	if is_instance_valid(plot):
		return "%s:%s:%s" % [action, team_id, plot.get_instance_id()]
	return ""


func _try_claim(action: String, plot: Node3D) -> bool:
	if not is_instance_valid(plot):
		return true  # 无 plot 的行为不 claim
	var key := _claim_key(action, plot)
	if not _team_claims.has(team_id):
		_team_claims[team_id] = {}
	var team_claims: Dictionary = _team_claims[team_id]
	if team_claims.has(key):
		var claim: Dictionary = team_claims[key]
		var claimer = claim.get("claimer")
		if claimer != self and is_instance_valid(claimer):
			return false
	team_claims[key] = {"claimer": self, "expire": CLAIM_EXPIRE}
	_team_claims[team_id] = team_claims
	return true


func _release_claim(action: String, plot: Node3D) -> void:
	if not is_instance_valid(plot):
		return
	if not _team_claims.has(team_id):
		return
	var key := _claim_key(action, plot)
	var team_claims: Dictionary = _team_claims[team_id]
	if team_claims.has(key):
		var claim: Dictionary = team_claims[key]
		if claim.get("claimer") == self:
			team_claims.erase(key)


func _is_claimed(action: String, plot: Node3D) -> bool:
	if not is_instance_valid(plot):
		return false
	if not _team_claims.has(team_id):
		return false
	var key := _claim_key(action, plot)
	var team_claims: Dictionary = _team_claims[team_id]
	if not team_claims.has(key):
		return false
	var claim: Dictionary = team_claims[key]
	var claimer = claim.get("claimer")
	if claimer == self or not is_instance_valid(claimer):
		return false
	return true


static func _cleanup_team_claims() -> void:
	for team in _team_claims.keys():
		var team_claims: Dictionary = _team_claims[team]
		var to_remove := []
		for key in team_claims.keys():
			var claim: Dictionary = team_claims[key]
			var expire: float = float(claim.get("expire", 0.0))
			var claimer = claim.get("claimer")
			if expire <= 0.0 or not is_instance_valid(claimer):
				to_remove.append(key)
			else:
				claim["expire"] = expire - 0.1
				team_claims[key] = claim
		for key in to_remove:
			team_claims.erase(key)
		_team_claims[team] = team_claims


func _set_focus_target(enemy: CharacterBody3D) -> void:
	if is_instance_valid(enemy):
		_focus_target[team_id] = enemy


func _is_focus_target(enemy: CharacterBody3D) -> bool:
	if not _focus_target.has(team_id):
		return false
	return _focus_target[team_id] == enemy


func _find_ally_in_trouble() -> CharacterBody3D:
	var nearest: CharacterBody3D
	var nearest_distance := 15.0
	for node in get_tree().get_nodes_in_group("ai_players"):
		if node == self or not is_instance_valid(node):
			continue
		if not node is CharacterBody3D:
			continue
		var ally := node as CharacterBody3D
		if not ally.has_method("get_combat_team"):
			continue
		if str(ally.call("get_combat_team")) != team_id:
			continue
		# 检查 ally 是否在被攻击（通过其 under_attack_timer）
		var under_attack: float = float(ally.get("under_attack_timer"))
		if under_attack <= 0.0:
			continue
		var distance := global_position.distance_to(ally.global_position)
		if distance < nearest_distance:
			nearest = ally
			nearest_distance = distance
	return nearest


# ===========================================================================
# 战斗系统
# ===========================================================================

func _take_damage(amount: float) -> void:
	if is_dead:
		return
	hp = maxf(0.0, hp - amount)
	if hp <= 0.0:
		_die()


func _die() -> void:
	is_dead = true
	respawn_timer = RESPAWN_DELAY
	_exit_defend_state()
	state = AIState.THINK
	movement_target = INVALID_POSITION
	target_plot = null
	target_player = null
	if is_instance_valid(held_tool):
		held_tool.queue_free()
		held_tool = null
	current_tool_index = -1
	# 隐藏外观（简单处理：禁用可见性）
	var appearance := get_node_or_null("AppearanceNode")
	if appearance is Node3D:
		appearance.visible = false


func _respawn() -> void:
	is_dead = false
	hp = max_hp
	stun_remaining = 0.0
	slow_remaining = 0.0
	burn_remaining = 0.0
	burn_dps = 0.0
	under_attack_timer = 0.0
	global_position = spawn_position
	velocity = Vector3.ZERO
	var appearance := get_node_or_null("AppearanceNode")
	if appearance is Node3D:
		appearance.visible = true
	if not local_tools.is_empty():
		_equip_default_tool()
	_schedule_think(0.3)


func impact(effect: String, strength: float, attacker_team: String = "") -> void:
	if is_dead:
		return
	var eff := effect.to_lower()
	if eff == "medicine_storm":
		if not attacker_team.is_empty() and attacker_team == team_id:
			hp = minf(max_hp, hp + maxf(0.0, strength))
		else:
			_take_damage(maxf(0.0, strength))
		return
	if not attacker_team.is_empty() and attacker_team == team_id:
		return
	_take_damage(strength * 0.5)  # 直接伤害
	if is_dead:
		return
	match eff:
		"lightening":
			stun_remaining = maxf(stun_remaining, 5.0)
			state = AIState.STUNNED
		"flame":
			burn_remaining = 3.0
			burn_dps = maxf(burn_dps, strength * 0.2)
		"freeze":
			slow_remaining = maxf(slow_remaining, 5.0)
		"lightning":  # 兼容拼写
			stun_remaining = maxf(stun_remaining, 5.0)
			state = AIState.STUNNED


func get_combat_team() -> String:
	return team_id


func receive_bullet_hit(
	hit_direction: Vector3,
	force: float,
	shooter_team: String
) -> void:
	if shooter_team == team_id:
		return
	var horizontal_direction := Vector3(
		hit_direction.x, 0.0, hit_direction.z).normalized()
	rubber_knockback = horizontal_direction * force
	under_attack_timer = 3.0
	# 尝试记录攻击者以便队友支援
	# （攻击者信息有限，这里仅标记自身被攻击）


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if not (
		body is RubberBullet
		or body is NailBullet
		or body is ColorBullet
	):
		return
	var shooter_team := str(body.call("get_bullet_owner"))
	if shooter_team == team_id:
		return
	var hit_direction := Vector3.ZERO
	var knockback_force := 0.0
	var bullet_strength := 0.0
	var bullet_effect := "None"
	if body is RubberBullet:
		var bullet := body as RubberBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		bullet_strength = float(bullet.bullet_strength)
	elif body is NailBullet:
		var bullet := body as NailBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		bullet_strength = float(bullet.bullet_strength)
	elif body is ColorBullet:
		var bullet := body as ColorBullet
		hit_direction = bullet.direction
		knockback_force = float(bullet.knockback_force)
		bullet_strength = float(bullet.bullet_strength)
		bullet_effect = bullet.bullet_effect
	receive_bullet_hit(hit_direction, knockback_force, shooter_team)
	# 应用子弹效果（Flame/Freeze/Lightening）
	if bullet_effect != "None":
		impact(bullet_effect, bullet_strength, shooter_team)
	else:
		_take_damage(bullet_strength * 0.6)
	body.queue_free()


# ===========================================================================
# 外观与骨骼动画（参考 player.gd 第 760-946 行）
# ===========================================================================

func _remove_emotion_controllers(node: Node) -> void:
	# 递归查找并立即从父节点移除 EmotionController，避免其 _ready 触发报错
	if node == null:
		return
	for child in node.get_children():
		if child is EmotionController:
			node.remove_child(child)
			child.queue_free()
		else:
			_remove_emotion_controllers(child)


func set_ai_appearance(hero_name: String, team_name: String) -> void:
	if team_name not in ["blue", "red"]:
		push_error("Unsupported AI team appearance: " + team_name)
		return
	var actual_hero := hero_name
	var appearance_path := "res://character/hero_skeleton/%s_%s.tscn" % [
		actual_hero, team_name]
	var appearance_scene := load(appearance_path) as PackedScene
	# Prospector scenes normally exist for both teams; red remains a safe fallback.
	if appearance_scene == null and actual_hero == "prospector":
		appearance_scene = load(
			"res://character/hero_skeleton/prospector_red.tscn") as PackedScene
	if appearance_scene == null:
		push_warning("Fallback appearance for " + hero_name + "/" + team_name)
		appearance_scene = load(
			"res://character/hero_skeleton/farmer_%s.tscn" % team_name) as PackedScene
	if appearance_scene == null:
		push_error("Unable to load AI appearance: " + appearance_path)
		return
	var appearance_node := appearance_scene.instantiate() as Node3D
	# 在进入场景树前移除 EmotionController，避免部分模型（如 engineer）
	# 因结构不匹配在 _ready 中报错。queue_free 是延迟的，必须立即从父节点摘除。
	_remove_emotion_controllers(appearance_node)
	add_child(appearance_node)
	appearance_node.rotation.y = deg_to_rad(180.0)
	appearance_node.name = "AppearanceNode"
	appearance_player = appearance_node.find_child(
		"AnimationPlayer", true, false) as AnimationPlayer
	skeleton = appearance_node.find_child(
		"Skeleton3D", true, false) as Skeleton3D
	if appearance_player == null or skeleton == null:
		push_error("Unable to initialize the AI animated skeleton.")
		return
	hand_socket.use_external_skeleton = true
	hand_socket.external_skeleton = hand_socket.get_path_to(skeleton)
	hand_socket.bone_name = "Hand.R"
	hand_socket.override_pose = false
	if not appearance_player.animation_finished.is_connected(
			_skeleton_animation_finished):
		appearance_player.animation_finished.connect(
			_skeleton_animation_finished)
	_setup_upper_body_aim()
	appearance_player.play(&"Idle")


func _play_body_animation(
	anim_name: StringName,
	blend_time := 0.12
) -> void:
	if not is_instance_valid(appearance_player):
		return
	if appearance_player.current_animation == anim_name and \
			appearance_player.is_playing():
		return
	appearance_player.play(anim_name, blend_time)


func _update_ai_animation(direction: Vector3) -> void:
	if not is_instance_valid(appearance_player):
		return
	var grounded := is_on_floor()
	if action_anim_locked:
		was_on_floor = grounded
		return
	if grounded and not was_on_floor:
		appearance_player.play(&"JumpLand", 0.05)
		landing_animation = true
		was_on_floor = true
		return
	if landing_animation:
		was_on_floor = grounded
		return
	if not grounded:
		if appearance_player.current_animation != &"JumpStart":
			_play_body_animation(&"JumpLoop", 0.05)
	elif direction.length_squared() > 0.001:
		_play_body_animation(&"Walk", 0.08)
	elif is_instance_valid(held_tool):
		_play_body_animation(&"IdleTool", 0.10)
	else:
		_play_body_animation(&"Idle", 0.10)
	was_on_floor = grounded


func _setup_upper_body_aim() -> void:
	upper_body_look_modifiers.clear()
	upper_body_look_weights.clear()
	_add_upper_body_look("SpineLook", "Spine", 0.10, 20.0)
	_add_upper_body_look("ChestLook", "Chest", 0.22, 30.0)
	_add_upper_body_look("NeckLook", "Neck", 0.16, 35.0)
	_add_upper_body_look("HeadLook", "Head_2", 0.28, 50.0)
	right_arm_ik = skeleton.find_child("RightArmIK", false, false) as TwoBoneIK3D
	if right_arm_ik == null:
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)
	right_arm_ik.setting_count = 1
	right_arm_ik.set_root_bone_name(0, "UpperArm.R")
	right_arm_ik.set_middle_bone_name(0, "Forearm.R")
	right_arm_ik.set_end_bone_name(0, "Hand.R")
	right_arm_ik.set_use_virtual_end(0, false)
	right_arm_ik.set_extend_end_bone(0, false)
	right_arm_ik.set_pole_direction(0, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X)
	right_arm_ik.set_target_node(0, right_arm_ik.get_path_to(right_hand_ik_target))
	right_arm_ik.set_pole_node(0, right_arm_ik.get_path_to(right_elbow_pole))
	right_arm_ik.active = true
	right_arm_ik.influence = 0.0
	hand_aim_look = skeleton.find_child("HandAimLook", false, false) as LookAtModifier3D
	if hand_aim_look == null:
		hand_aim_look = LookAtModifier3D.new()
		hand_aim_look.name = "HandAimLook"
		skeleton.add_child(hand_aim_look)
	hand_aim_look.bone_name = "Hand.R"
	hand_aim_look.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Y
	hand_aim_look.primary_rotation_axis = Vector3.AXIS_X
	hand_aim_look.use_secondary_rotation = false
	hand_aim_look.relative = false
	hand_aim_look.use_angle_limitation = true
	hand_aim_look.symmetry_limitation = true
	hand_aim_look.primary_limit_angle = deg_to_rad(55.0)
	hand_aim_look.primary_damp_threshold = 1.0
	hand_aim_look.target_node = hand_aim_look.get_path_to(upper_body_look_target)
	hand_aim_look.active = false
	hand_aim_look.influence = 0.0


func _add_upper_body_look(
	node_name: String,
	bone_name: String,
	base_weight: float,
	limit_degrees: float
) -> void:
	var modifier := skeleton.find_child(node_name, false, false) as LookAtModifier3D
	if modifier == null:
		modifier = LookAtModifier3D.new()
		modifier.name = node_name
		skeleton.add_child(modifier)
	modifier.bone_name = bone_name
	modifier.forward_axis = SkeletonModifier3D.BONE_AXIS_PLUS_Z
	modifier.primary_rotation_axis = Vector3.AXIS_X
	modifier.use_secondary_rotation = false
	modifier.relative = true
	modifier.use_angle_limitation = true
	modifier.symmetry_limitation = true
	modifier.primary_limit_angle = deg_to_rad(limit_degrees)
	modifier.primary_damp_threshold = 1.0
	modifier.target_node = modifier.get_path_to(upper_body_look_target)
	modifier.active = true
	modifier.influence = 0.0
	upper_body_look_modifiers.append(modifier)
	upper_body_look_weights.append(base_weight)


func _update_upper_body_aim(delta: float) -> void:
	if skeleton == null:
		return
	var equipped_scale := 1.0 if is_instance_valid(held_tool) else 0.0
	var action_scale := 0.70 if action_anim_locked else 1.0
	for index in range(upper_body_look_modifiers.size()):
		var modifier := upper_body_look_modifiers[index]
		if not is_instance_valid(modifier):
			continue
		var desired := upper_body_look_weights[index] * \
				equipped_scale * action_scale
		modifier.influence = move_toward(
			modifier.influence, desired, delta * 3.5)
	if is_instance_valid(right_arm_ik):
		var desired_ik := 0.88 * equipped_scale * action_scale
		right_arm_ik.influence = move_toward(
			right_arm_ik.influence, desired_ik, delta * 5.0)
	if is_instance_valid(hand_aim_look):
		hand_aim_look.influence = 0.0


## 每帧重新对齐 tool_socket，使工具的 Muzzle/RayCast3D 前向指向 aim_target_position。
## tool_socket 挂在 BoneAttachment3D(Hand.R) 下，骨骼动画和 TwoBoneIK 每帧
## 都会覆盖它的全局朝向，单次 look_at 无法保持。
## 算法参考 Player._update_tool_camera_alignment：取工具权威前向(Muzzle/RayCast3D)，
## 计算其相对 pivot 的局部偏移，再用 AI 瞄准方向基替代相机基重新组合 pivot 朝向。
func _update_tool_aim_alignment() -> void:
	if not is_instance_valid(held_tool) or not is_instance_valid(tool_socket):
		return

	# 1. 取工具权威前向（Muzzle 的 basis，或 RayCast3D 的方向）
	var muzzle := held_tool.get_node_or_null("Muzzle") as Node3D
	var aim_basis: Basis
	if muzzle != null:
		aim_basis = muzzle.global_transform.basis.orthonormalized()
	else:
		var aim_ray := held_tool.find_child("RayCast3D", true, false) as RayCast3D
		if aim_ray == null or aim_ray.target_position.is_zero_approx():
			# 无 Muzzle/RayCast3D 的工具（如 Eater/SproutBlaster），用工具自身 -Z
			aim_basis = held_tool.global_transform.basis.orthonormalized()
		else:
			var ray_direction := (
				aim_ray.to_global(aim_ray.target_position)
				- aim_ray.global_position
			).normalized()
			var preferred_up := held_tool.global_transform.basis.y.normalized()
			if absf(ray_direction.dot(preferred_up)) > 0.98:
				preferred_up = global_transform.basis.x.normalized()
			aim_basis = Basis.looking_at(ray_direction, preferred_up).orthonormalized()

	if aim_basis.determinant() == 0.0:
		return

	# 2. 计算 aim_from_pivot：工具权威前向相对 pivot 的局部偏移
	var pivot_basis := tool_socket.global_transform.basis.orthonormalized()
	var aim_from_pivot := (pivot_basis.inverse() * aim_basis).orthonormalized()

	# 3. 构造 AI 瞄准方向基（替代 Player 的 camera basis）
	var aim_origin := tool_socket.global_position
	var aim_dir := (aim_target_position - aim_origin).normalized()
	if aim_dir.length_squared() < 0.001:
		return
	var preferred_up := global_transform.basis.y.normalized()
	if absf(aim_dir.dot(preferred_up)) > 0.98:
		preferred_up = global_transform.basis.x.normalized()
	var aim_target_basis := Basis.looking_at(aim_dir, preferred_up).orthonormalized()

	# 4. 重组 pivot 朝向，保持 grip 局部偏移不变
	var desired_pivot_basis := (aim_target_basis * aim_from_pivot.inverse()).orthonormalized()
	tool_socket.global_transform = Transform3D(desired_pivot_basis, tool_socket.global_position)


func _skeleton_animation_finished(anim_name: StringName) -> void:
	match anim_name:
		&"JumpStart":
			if not is_on_floor():
				_play_body_animation(&"JumpLoop", 0.05)
		&"JumpLand":
			landing_animation = false
		&"ShootOneHand", &"PunchRight", &"ToolUseRight":
			action_anim_locked = false
