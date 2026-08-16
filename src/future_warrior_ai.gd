extends CharacterBody3D
class_name FutureWarriorAI

## ============================================================
## Future Warrior combat AI
##
## 根节点：
## - 创建一个空 CharacterBody3D，并挂载本脚本。
##
## 运行时自动创建：
## - Head
## - UpperBodyLookTarget
## - RightHandIKTarget
## - RightElbowPole
## - CollisionShape3D
## - RightHandSocket/ToolPivot
## - RayCast3D
## - LookAtTarget
## - FrontProbe / LeftProbe / RightProbe
## - NavigationAgent3D
## - Hit3D/CollisionShape3D
## - HealthLabel3D
##
## 外观：
## - res://character/hero_skeleton/enemy/future_warrior.tscn
##
## 初始装备：
## - FutureM4
## - SuppressedPistol
## - 2 枚 Grenade
##
## 行为：
## - 沿导航路径前往敌方农场，并以扇形视锥左右搜索敌方玩家。
## - 不种地、不收获、不放置农场工具。
## - 默认使用 FutureM4；主武器弹匣打空且仍在交火时才切换 SuppressedPistol。
## - 两把武器弹匣都打空时切回 FutureM4 换弹。
## - 每次锁定新的交火目标时尝试投掷一枚手雷，每人最多 2 枚。
## - 受伤时立即锁定、转向并反击实际攻击者。
##
## 兼容项目已有接口：
## - get_combat_team()
## - tool_owner
## - emit()
## - get_bullet_owner()
## - impact()
##
## 武器 Y 轴/骨骼姿态矫正：
## - 直接迁移 player.gd 的枪口基准反推算法。
## - 玩家版本以 camera.global_transform.basis 作为目标基准。
## - AI 版本以 aim_ray.global_transform.basis 作为目标基准。
## - 不直接用 ToolPivot.look_at()，避免 Hand.R 动画导致枪械翻滚和偏航。
## ============================================================


enum AIState {
	SEARCH,
	CHASE,
	COMBAT,
	FLEE,
	DEAD,
}


enum WeaponSlot {
	AR15,
	SUPPRESSED_PISTOL,
}


enum GrenadeMode {
	AUTO,
	PROJECTILE,
	TOOL,
}


const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"
const INVALID_POSITION := Vector3(INF, INF, INF)
## 死亡表现保留时间。死亡后不再复用原节点单体复活，时间到后由权威端移除。
const DEATH_CLEANUP_SECONDS := 10.0
const SquadMessageTypes := preload("res://src/squad_message.gd")

## 仅供本地调试/测试界面监听；既记录区块重建，也记录通信触发的路径刷新。
signal navigation_path_refreshed(chunk_ids: Array, was_stuck: bool)


# ------------------------------------------------------------------
# Identity
# ------------------------------------------------------------------

@export_category("Identity")

## team_id = "enemy" 时，会攻击 red 和 blue 玩家。
## 若改为 red 或 blue，则只攻击不同队伍。
@export var team_id: String = "enemy"

@export_file("*.tscn")
var future_warrior_scene_path: String = \
	"res://character/hero_skeleton/enemy/future_warrior.tscn"

## Dedicated Server / 联机模式中，AI 决策只在服务器运行。
@export var server_authoritative: bool = true


# ------------------------------------------------------------------
# Starting loadout
# ------------------------------------------------------------------

@export_category("Starting Loadout")

## 优先从 tool_definitions.json 中按 ID 查找。
## 找不到时使用下面的 fallback scene path。
@export var ar15_tool_id: String = "future_m4"
@export var suppressed_pistol_tool_id: String = "suppressed_pistol"
@export var grenade_tool_id: String = "grenade"

@export_file("*.tscn")
var ar15_scene_path: String = \
	"res://character/weapons/FutureM4.tscn"

@export_file("*.tscn")
var suppressed_pistol_scene_path: String = \
	"res://character/weapons/SuppressedPistol.tscn"

@export_file("*.tscn")
var grenade_scene_path: String = \
	"res://character/weapons/Grenade.tscn"

## 如果 JSON 中没有握持参数，使用这些默认参数。
@export var ar15_grip_position: Vector3 = Vector3.ZERO
@export var ar15_grip_rotation: Vector3 = Vector3.ZERO
@export var ar15_grip_scale: Vector3 = Vector3.ONE

@export var pistol_grip_position: Vector3 = Vector3.ZERO
@export var pistol_grip_rotation: Vector3 = Vector3.ZERO
@export var pistol_grip_scale: Vector3 = Vector3.ONE

@export var grenade_grip_position: Vector3 = Vector3.ZERO
@export var grenade_grip_rotation: Vector3 = Vector3.ZERO
@export var grenade_grip_scale: Vector3 = Vector3.ONE

@export_range(0, 10, 1)
var starting_grenade_count: int = 2

## AUTO：
## - 有 launch()、RigidBody3D 或 velocity 属性时，按投射物处理。
## - 否则有 emit() 时，按手持工具处理。
@export_enum("Auto", "Projectile", "Tool")
var grenade_mode: int = GrenadeMode.AUTO


# ------------------------------------------------------------------
# Health
# ------------------------------------------------------------------

@export_category("Health")

@export var max_hp: float = 260.0

## 兼容旧地图/测试场景的序列化字段。FutureAI 现在不会在原节点上单体复活；
## 小队的下一批生成由 EnemySquadSpawner.respawn_seconds 负责。
@export_range(1.0, 30.0, 0.5)
var respawn_seconds: float = 10.0

## Optional map-assigned spawn. Empty means a random spawn point in team_id.
@export var spawn_point_id: String = ""

## 可选战略目标。设置后，搜索阶段前往并巡逻该目标；为空时使用敌方出生点。
@export var target: Node3D

## 子弹没有公开 damage/bullet_damage 属性时使用。
@export var default_bullet_damage: float = 12.0
@export var color_bullet_damage: float = 15.0
@export var explosion_damage_multiplier: float = 1.0

@export_category("Death Drop")

## FutureWarrior/FutureEngineer 共用的现金掉落规则。
@export_range(0.0, 1.0, 0.05)
var cash_drop_chance := 0.5

@export_range(1, 1000000, 1)
var cash_drop_minimum := 50

@export_range(1, 1000000, 1)
var cash_drop_maximum := 300

## 每次受伤后是否触发短暂撤退。
@export var flee_on_any_damage: bool = true

@export var short_flee_duration: float = 1.8
@export var low_health_flee_duration: float = 3.2
@export var flee_retrigger_cooldown: float = 2.5

@export_range(0.05, 0.95, 0.01)
var low_health_flee_ratio: float = 0.38

## damage_memory_seconds 内累计伤害超过该值时，强制进行更长撤退。
@export var burst_damage_to_flee: float = 42.0
@export var damage_memory_seconds: float = 1.25


# ------------------------------------------------------------------
# Detection
# ------------------------------------------------------------------

@export_category("Detection")

@export var detection_range: float = 500.0
@export var lose_target_range: float = 600.0
@export var target_refresh_interval: float = 0.20

## 与玩家/障碍/Hit3D 所在碰撞层组合保持一致。
@export var combat_ray_mask: int = 138


# ------------------------------------------------------------------
# Movement
# ------------------------------------------------------------------

@export_category("Movement")

@export var chase_speed: float = 3.0
@export var combat_move_speed: float = 2.2
@export var flee_speed: float = 3.7

@export var acceleration: float = 22.0
@export var rotation_speed: float = 10.0

@export var preferred_combat_range: float = 12.0
@export var combat_range_tolerance: float = 2.2
@export var minimum_combat_distance: float = 4.0

@export var flee_distance: float = 15.0

@export var strafe_change_min: float = 0.8
@export var strafe_change_max: float = 1.7

## 地图有 NavigationRegion3D 时优先使用导航；未接入 Squad 的旧式 AI
## 才在导航不可用时回退到直线移动 + RayCast 避障。
@export var use_navigation_agent: bool = true

## 启用 NavigationAgent3D 的 RVO 局部速度避让。
## 这不会改变导航路径，角色仍必须使用 velocity_computed 返回的安全速度移动。
@export var navigation_avoidance_enabled: bool = true
@export var navigation_avoidance_neighbor_distance: float = 8.0
@export_range(1, 16, 1)
var navigation_avoidance_max_neighbors: int = 8

@export var navigation_refresh_interval: float = 0.18


@export_category("Grenade Avoidance")

## 手雷当前坐标进入爆炸半径外的这段缓冲区后，AI开始主动规避。
@export var grenade_avoidance_trigger_margin: float = 2.0
## AI 需要离开爆炸半径再加这一段余量，才算到达安全距离。
@export var grenade_avoidance_safe_margin: float = 1.5
## 到达安全距离后继续保持规避覆盖至少 5 秒，期间仍照常攻击/反击。
@export var grenade_avoidance_resume_delay: float = 5.0
@export var grenade_avoidance_repath_interval: float = 0.25

@export_category("Farm Search And Vision")

## 未发现目标时前往敌方农场；到达后在农场周边巡查。
@export var enemy_farm_arrival_radius: float = 10.0
@export var enemy_farm_patrol_radius: float = 16.0
@export var enemy_farm_refresh_interval: float = 2.0
## 256m 地图的可活动内侧边界。AI 接近空气墙时会主动折返。
@export var map_boundary_limit: float = 126.0
@export var boundary_turn_margin: float = 4.0

## 以 AI 为圆心的三维视觉球体半径。距离使用完整的 XYZ 距离。
@export_range(1.0, 80.0, 0.5) var vision_range: float = 80.0
## 正面扇区内的目标在视线通畅时立即被识别；球体其余部分使用察觉度累计。
@export_range(10.0, 180.0, 1.0) var vision_fov_degrees: float = 120.0
## 目标位于侧面/背部、且距离视觉球体边缘时，每秒获得的察觉度。
@export_range(0.01, 1.0, 0.01) var peripheral_awareness_far_per_second := 0.08
## 目标位于侧面/背部、且非常接近 AI 时，每秒获得的察觉度。
@export_range(0.1, 4.0, 0.05) var peripheral_awareness_near_per_second := 1.20
## 正后方的察觉速度乘数；越低越不容易从背后被立即发现。
@export_range(0.05, 1.0, 0.05) var rear_awareness_multiplier := 0.35
## 被遮挡或离开视觉球体后，察觉度保留多久才开始衰减。
@export_range(0.0, 10.0, 0.1) var awareness_memory_seconds := 1.5
## 失去视线后的察觉度衰减速度，归零后需要重新察觉。
@export_range(0.05, 4.0, 0.05) var awareness_decay_per_second := 0.60
@export_range(5.0, 90.0, 1.0) var search_look_sweep_degrees: float = 48.0
@export_range(0.5, 8.0, 0.1) var search_look_sweep_seconds: float = 2.8
@export_flags_3d_physics var vision_occlusion_mask: int = 65535

## 遇到低矮障碍时尝试跳跃。
@export var jump_velocity: float = 3.8
@export var jump_cooldown: float = 0.85


# ------------------------------------------------------------------
# Squad communication
# ------------------------------------------------------------------

@export_category("Squad Communication")

@export var squad_demolition_probe_distance := 3.0
@export var squad_demolition_request_cooldown := 0.75
## 进入 COMBAT 后首次立即请求；之后每 10 秒最多重复一次。
@export var squad_support_request_cooldown := 10.0
@export var squad_support_timeout := 12.0
## 响应支援时走到支援点附近 2.5m，再进入支援观察窗口。
@export var squad_support_arrival_distance := 2.5
@export var squad_support_wait_seconds := 10.0
@export var squad_support_max_response_distance := 50.0
## 只有远距离且明显偏离当前战略 target 的支援请求才会被忽略。
@export_range(0.0, 180.0, 1.0) var squad_support_max_off_target_angle_degrees := 120.0
@export var squad_warning_retreat_seconds := 12.0
## 收到 Squad 的“这里将要爆破请撤退”后，至少撤离到爆炸点 10m 外。
@export var squad_warning_retreat_distance := 10.0
@export var squad_minimum_member_distance := 2.0
@export_range(0.0, 1.0, 0.05) var squad_separation_weight := 0.35

## Squad 成员在推进状态下连续一段时间没有向当前行为目标取得有效进展时，
## 判定可能被障碍、边界或队友卡住。除了位移，还会检查目标距离、来回振荡
## 和 move_and_slide 的墙体碰撞，避免小范围来回移动一直被当成正常前进。
@export var squad_stuck_detection_seconds := 2.0
## 保留旧字段作为“窗口内有效目标进展”的兼容配置。
@export var squad_stuck_min_progress := 1.5
## 目标距离至少减少这么多才算有效推进；小于这个值时继续检查阻挡/振荡。
@export var squad_stuck_min_goal_progress := 0.75
## 窗口内实际移动少于这个距离时，即使没有报告碰撞也视为疑似卡住。
@export var squad_stuck_min_actual_motion := 0.65
## 持续碰撞超过这个时间后可直接确认卡住，不必等完整窗口结束。
@export var squad_stuck_blocked_seconds := 0.45
## 实际路程明显大于净位移时，判定为来回振荡。
@export_range(0.1, 0.95, 0.05) var squad_stuck_oscillation_ratio := 0.45
## 卡住状态持续 10 秒后执行一次随机方向脱困。
@export var squad_stuck_escape_after_seconds := 10.0
@export var squad_escape_distance := 5.0
@export var squad_escape_duration := 5.0
## 炸弹警告撤退被碰撞卡住时，先用随机方向脱离队员/墙体拥挤区域。
@export var squad_warning_stuck_after_seconds := 1.5
@export var squad_warning_escape_duration := 3.0

## 从 COMBAT 转为 CHASE 后，最多离开交火点 20m；超过后放弃追击并恢复 target。
@export var chase_max_distance_from_engagement := 20.0


# ------------------------------------------------------------------
# FutureM4
# ------------------------------------------------------------------

@export_category("FutureM4")

@export var ar15_min_range: float = 5.5
@export var ar15_max_range: float = 34.0

## 最小射击间隔。即使 JSON cooldown 更小，也不会快于该值。
@export var ar15_fire_interval: float = 0.11

## tool_definitions.json 缺失弹药字段时使用的后备值。
@export_range(1, 200, 1) var ar15_magazine_size: int = 60
@export_range(0, 1000, 1) var ar15_initial_reserve_ammo: int = 200
@export var ar15_reload_time: float = 2.0

@export_range(1, 12, 1)
var ar15_burst_size: int = 5

@export var ar15_burst_pause: float = 0.52


# ------------------------------------------------------------------
# Suppressed pistol
# ------------------------------------------------------------------

@export_category("Suppressed Pistol")

@export var pistol_switch_distance: float = 7.0
@export var pistol_max_range: float = 13.0
@export var pistol_fire_interval: float = 0.28
@export_range(1, 200, 1) var pistol_magazine_size: int = 30
@export_range(0, 1000, 1) var pistol_initial_reserve_ammo: int = 200
@export var pistol_reload_time: float = 1.5


# ------------------------------------------------------------------
# Aim
# ------------------------------------------------------------------

@export_category("Aim")

@export var target_height: float = 1.05
@export var aim_prediction_seconds: float = 0.15

## 轻微误差可避免 AI 像自瞄一样永不失手。
@export var standing_aim_error: float = 0.055
@export var moving_aim_error: float = 0.13


# ------------------------------------------------------------------
# Grenade
# ------------------------------------------------------------------

@export_category("Grenade")

@export var grenade_min_range: float = 7.5
@export var grenade_max_range: float = 20.0
@export var grenade_cooldown: float = 4.0

@export var grenade_flight_time: float = 1.1
@export var grenade_spawn_height: float = 1.35
@export var grenade_forward_offset: float = 0.45

@export var grenade_friendly_safety_radius: float = 5.0

## 保留该字段兼容旧场景；新逻辑不再随机掷雷，而是在新交火开始时确定性尝试一次。
@export_range(0.0, 1.0, 0.01)
var grenade_use_chance: float = 1.0

## 投射物手雷推荐实现：
## launch(initial_velocity: Vector3, owner_team: String)
@export var grenade_launch_method: StringName = &"launch"


# ------------------------------------------------------------------
# Runtime collision
# ------------------------------------------------------------------

@export_category("Runtime Collision")

## Character 层为 8；mask 额外包含工具层 128，使其能够阻挡已放置的防御墙。
@export var body_collision_layer: int = 8
@export_flags_3d_physics var body_collision_mask: int = 647

## 与现有玩家/AI Hit3D 设置一致。
@export var hit_area_collision_layer: int = 0
@export var hit_area_collision_mask: int = 32

@export var body_capsule_radius: float = 0.34
@export var body_capsule_height: float = 1.70

@export var body_capsule_position: Vector3 = \
	Vector3(0.0, 0.8465799, -0.01983869)

@export var hit_capsule_radius: float = 0.38
@export var hit_capsule_height: float = 1.72

@export var hit_capsule_position: Vector3 = \
	Vector3(0.0, 0.8376303, 0.0)


# ------------------------------------------------------------------
# Debug
# ------------------------------------------------------------------

@export_category("Debug")

@export var show_health_label: bool = true
@export var print_decisions: bool = false


# ------------------------------------------------------------------
# Runtime-created nodes
# ------------------------------------------------------------------

var head: Node3D
var upper_body_look_target: Marker3D
var right_hand_ik_target: Marker3D
var right_elbow_pole: Marker3D

var body_collision_shape: CollisionShape3D

var right_hand_socket: BoneAttachment3D
var tool_pivot: Node3D

var aim_ray: RayCast3D
var look_at_target: RayCast3D

var front_probe: RayCast3D
var left_probe: RayCast3D
var right_probe: RayCast3D

var navigation_agent: NavigationAgent3D

## NavigationAgent3D 的 RVO 回调结果在下一次物理移动中使用。
var _avoidance_safe_velocity := Vector3.ZERO
var _avoidance_safe_velocity_valid := false

var hit_3d: Area3D
var hit_collision_shape: CollisionShape3D

var health_label: Label3D
var team_marker: MeshInstance3D
const TEAM_MARKER_HEIGHT := 3.15


# ------------------------------------------------------------------
# Appearance / animation runtime
# ------------------------------------------------------------------

var appearance_player: AnimationPlayer
var skeleton: Skeleton3D

var upper_body_look_modifiers: Array[LookAtModifier3D] = []
var upper_body_look_weights: Array[float] = []
var right_arm_ik: TwoBoneIK3D

var action_animation_locked: bool = false
var landing_animation: bool = false
var was_on_floor: bool = true


# ------------------------------------------------------------------
# Loadout runtime
# ------------------------------------------------------------------

var weapon_data: Dictionary = {}
## 每个武器槽独立保存弹匣、备用弹药和换弹配置；切枪不会重置弹药。
var weapon_ammo: Dictionary = {}

var current_weapon_slot: int = -1
var held_weapon: Node3D
var reloading_weapon_slot: int = -1
var weapon_reload_timer: float = 0.0

var grenade_data: Dictionary = {}
var grenades_remaining: int = 0
var engagement_grenade_target_id: int = 0
var engagement_grenade_pending: bool = false

var fire_timer: float = 0.0
var grenade_timer: float = 0.0

var ar15_burst_shots_remaining: int = 0
var ar15_burst_pause_timer: float = 0.0


# ------------------------------------------------------------------
# AI runtime
# ------------------------------------------------------------------

var state: int = AIState.SEARCH
var interest_sleeping := false
var current_hp: float = 0.0
var _death_cleanup_deadline_msec := -1

var target_player: CharacterBody3D
var last_known_target_position: Vector3 = INVALID_POSITION
var retaliation_target: CharacterBody3D
var retaliation_timer: float = 0.0
var combat_engagement_point: Vector3 = INVALID_POSITION
var combat_engagement_target_id: int = 0

var target_refresh_timer: float = 0.0
## instance_id -> [0, 1]。只在视觉球体内且未位于正面扇区的目标使用。
var _target_awareness: Dictionary = {}
## instance_id -> Time.get_ticks_msec()，用于目标暂时被遮挡时的短暂记忆。
var _target_awareness_last_seen_msec: Dictionary = {}
var navigation_refresh_timer: float = 0.0
var enemy_farm_refresh_timer: float = 0.0
var enemy_farm_position: Vector3 = INVALID_POSITION
var farm_patrol_position: Vector3 = INVALID_POSITION
var search_look_phase: float = 0.0
var search_look_direction: Vector3 = Vector3.ZERO

## 服务器权威端和远端视觉代理共用的最终武器瞄准框架。多人客户端不运行
## AI 的 _process/_physics_process，因此必须同步方向，而不能让客户端用默认
## Hand.R 姿态猜枪口方向。
var _weapon_aim_position: Vector3 = INVALID_POSITION
var _weapon_aim_direction := Vector3.FORWARD
var _weapon_aim_active := false

var flee_target: Vector3 = INVALID_POSITION
var flee_timer: float = 0.0
var flee_retrigger_timer: float = 0.0
var low_health_flee_used: bool = false

var _grenade_avoidance_active := false
var _grenade_avoidance_safe_elapsed := 0.0
var _grenade_avoidance_repath_timer := 0.0
var _grenade_avoidance_center := INVALID_POSITION
var _grenade_avoidance_radius := 0.0
var _grenade_avoidance_direction := Vector3.ZERO

var damage_memory_timer: float = 0.0
var recent_damage: float = 0.0
var last_damage_source_position: Vector3 = INVALID_POSITION

var strafe_sign: float = 1.0
var strafe_timer: float = 0.0

var jump_timer: float = 0.0

var rubber_knockback: Vector3 = Vector3.ZERO
var rng := RandomNumberGenerator.new()
var _fallback_strategic_target: Node3D

var squad: Node
var squad_member_id := ""
var squad_ai_type := "future_warrior"
var squad_communicator: Node
var external_respawn_controller: Node
var last_squad_message_text := ""
var last_squad_message_type := -1
var _squad_demolition_probe_timer := 0.0
var _squad_support_request_timer := 0.0
var _squad_support_request_id := ""
var _squad_support_position := INVALID_POSITION
var _squad_support_timer := 0.0
var _squad_support_hold_timer := 0.0
var _squad_support_arrived := false
var _squad_support_broadcast_active := false
var _squad_support_pending_after_bullet := false
var _squad_warning_position := INVALID_POSITION
var _squad_warning_radius := 0.0
var _squad_warning_timer := 0.0
var _squad_stuck := false
var _squad_stuck_elapsed := 0.0
var _squad_progress_window_elapsed := 0.0
var _squad_progress_anchor := INVALID_POSITION
var _squad_tracking_goal := INVALID_POSITION
var _squad_window_travel_distance := 0.0
var _squad_blocked_elapsed := 0.0
var _squad_navigation_retry_timer := 0.0
var _navigation_using_direct_fallback := false
var _squad_escape_waypoint := INVALID_POSITION
var _squad_escape_direction := Vector3.ZERO
var _squad_escape_timer := 0.0
var _squad_warning_progress_anchor := INVALID_POSITION
var _squad_warning_no_progress_elapsed := 0.0
var _squad_warning_escape_direction := Vector3.ZERO
var _squad_warning_escape_timer := 0.0


# ------------------------------------------------------------------
# Initialization
# ------------------------------------------------------------------

func _ready() -> void:
	rng.randomize()

	current_hp = max_hp
	grenades_remaining = starting_grenade_count

	collision_layer = body_collision_layer
	collision_mask = body_collision_mask

	add_to_group("future_warrior_ai")
	add_to_group("combat_characters")
	_ensure_team_marker_visual()

	_create_required_runtime_nodes()
	_load_future_warrior_appearance()
	_load_starting_loadout()
	_initialize_weapon_ammo()

	## 出生后直接手持 FutureM4；若资源路径错误则退回消音手枪。
	if not _equip_weapon(WeaponSlot.AR15):
		_equip_weapon(WeaponSlot.SUPPRESSED_PISTOL)

	_update_health_label()

	strafe_sign = -1.0 if rng.randf() < 0.5 else 1.0
	_reset_strafe_timer()

	_debug(
		"ready team=%s grenades=%d"
		% [team_id, grenades_remaining]
	)


func _process(delta: float) -> void:
	if interest_sleeping or state == AIState.DEAD:
		return

	## 状态和最近一条 Squad 消息需要在状态切换后立即反映到头顶 Label3D；
	## 这里也覆盖多人客户端收到 apply_network_state 后的显示更新。
	_update_health_label()

	## 与 player.gd 一致：
	## 先更新上半身瞄准和 IK，再执行枪械基准矫正。
	_update_upper_body_aim(delta)
	_update_tool_camera_alignment()


func _physics_process(delta: float) -> void:
	if interest_sleeping:
		return
	if state == AIState.DEAD:
		_simulate_corpse_gravity(delta)
		return

	if not _has_simulation_authority():
		return

	_update_timers(delta)
	_sanitize_target_references()
	_squad_navigation_retry_timer = maxf(
		0.0,
		_squad_navigation_retry_timer - delta
	)
	## target 始终保持为 Node3D；未配置时创建指向敌方随机出生点的 fallback。
	## FutureEngineerAI 覆盖了这个方法，因此会继续使用 Engineer 自己的实现。
	_ensure_strategic_target()
	_refresh_target()
	if not _is_valid_target(target_player):
		_maintain_out_of_combat_loadout()
	_update_squad_obstacle_reporting()

	## 手雷规避是移动覆盖层，不切换 COMBAT/SEARCH 状态，也不清除 target。
	## 因而下面的原有攻击、换弹、反击和角色专属逻辑仍会继续执行。
	_update_grenade_avoidance(delta)
	if _grenade_avoidance_active:
		_maintain_combat_during_grenade_avoidance()

	## 爆破警告撤退是 Squad 成员的最高优先级；但放置炸药的 Engineer
	## 使用自己的 RETREAT_FROM_EXPLOSIVE 状态，因此不会依赖这里。
	if _squad_warning_can_override_role_behavior() and _update_squad_warning_retreat(delta):
		return

	## 10 秒仍未恢复移动时，先执行一次随机方向脱困，再恢复原 target。
	if _update_squad_escape(delta):
		return

	## 角色专属行为可以在这里接管本帧移动。FutureEngineer 使用这个钩子
	## 插入爆破流程，同时继续复用本类的目标刷新、导航、移动和战斗接口。
	if _update_role_specific_behavior(delta):
		return

	if _update_squad_support(delta):
		return

	var move_direction := Vector3.ZERO
	var move_speed := combat_move_speed

	match state:
		AIState.SEARCH:
			move_direction = _update_search_state(delta)
			move_speed = chase_speed

		AIState.CHASE:
			move_direction = _update_chase_state()
			move_speed = chase_speed

		AIState.COMBAT:
			move_direction = _update_combat_state()
			move_speed = combat_move_speed

		AIState.FLEE:
			move_direction = _update_flee_state()
			move_speed = flee_speed

	_apply_character_movement(
		_avoid_immediate_obstacle(move_direction),
		move_speed,
		delta
	)


## 尸体只保留与静态世界的碰撞：从 LadderClimb 等高处死亡时继续受重力影响，
## 但根 collision_layer 为 0，不会挡住队友或重新成为战斗/导航目标。
func _simulate_corpse_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0
	move_and_slide()


func _corpse_collision_mask() -> int:
	return (
		GameAuthority.COLLISION_LAYER_GROUND
		| GameAuthority.COLLISION_LAYER_WALL
		| GameAuthority.COLLISION_LAYER_FARM_TILE
		| GameAuthority.COLLISION_LAYER_TOOL
		| GameAuthority.COLLISION_LAYER_BUILDING
		| GameAuthority.COLLISION_LAYER_VEHICLES
		| GameAuthority.COLLISION_LAYER_NATURE_RESOURCE
	)


func _has_simulation_authority() -> bool:
	if not server_authoritative:
		return true
	# A cooperative host is a listen server: GameAuthority already knows that it
	# owns the authoritative world even while the same process renders a local
	# client. Prefer that explicit role over the transport-specific query.
	if GameAuthority.is_server_authority():
		return true
	if GameAuthority.is_client_proxy():
		return false

	if not multiplayer.has_multiplayer_peer():
		return true

	return multiplayer.is_server()


## 子类角色可以在这里接管本帧 AI 行为；普通 FutureWarrior 不接管。
## 返回 true 表示子类已经完成本帧移动/行为处理。
func _update_role_specific_behavior(_delta: float) -> bool:
	return false


# ------------------------------------------------------------------
# Squad membership and communication
# ------------------------------------------------------------------

func configure_squad_membership(
	value_squad: Node,
	member_id: String,
	ai_type: String,
	communicator: Node
) -> void:
	squad = value_squad
	squad_member_id = member_id
	squad_ai_type = ai_type
	squad_communicator = communicator
	last_squad_message_text = ""
	last_squad_message_type = -1
	_debug("joined squad=%s member=%s type=%s" % [value_squad.name, member_id, ai_type])


func set_squad(value: Node) -> void:
	squad = value


func set_external_respawn_controller(value: Node) -> void:
	external_respawn_controller = value


func is_eliminated_for_squad_batch() -> bool:
	return state == AIState.DEAD


func send_squad_message(type: int, payload: Dictionary = {}, reply_to := "") -> Dictionary:
	if not is_instance_valid(squad_communicator):
		return {"accepted": false, "reason": "not_in_squad"}
	return squad_communicator.send_message(type, payload, reply_to)


## 由 SquadCommunicator 在频道实际广播后调用。
## 只记录 sender_member_id 等于本 AI 的消息，收到队友消息不会覆盖自己的最近发布记录。
func record_squad_message(message: Dictionary) -> void:
	if squad_member_id.is_empty():
		return
	if str(message.get("sender_member_id", "")) != squad_member_id:
		return
	last_squad_message_type = int(message.get("type", -1))
	last_squad_message_text = SquadMessageTypes.type_name(last_squad_message_type)
	_update_health_label()


func _last_squad_message_label() -> String:
	return last_squad_message_text if not last_squad_message_text.is_empty() else "无"


func _status_label_text() -> String:
	match state:
		AIState.SEARCH:
			return "SEARCH"
		AIState.CHASE:
			return "CHASE"
		AIState.COMBAT:
			return "COMBAT"
		AIState.FLEE:
			return "FLEE"
		AIState.DEAD:
			return "DEAD"
	return "UNKNOWN"


func _squad_stuck_label_text() -> String:
	return "是" if _squad_stuck else "否"


func receive_squad_message(message: Dictionary) -> void:
	if state == AIState.DEAD:
		return
	var type := int(message.get("type", -1))
	var payload: Dictionary = message.get("payload", {})
	var request_id := str(message.get("request_id", ""))
	match type:
		SquadMessageTypes.Type.SET_TARGET:
			var new_target := payload.get("target") as Node3D
			if is_instance_valid(new_target):
				set_strategic_target(new_target)
				enemy_farm_position = INVALID_POSITION
				farm_patrol_position = INVALID_POSITION
				navigation_refresh_timer = 0.0
		SquadMessageTypes.Type.DEMOLITION_REQUEST:
			_try_claim_squad_demolition(request_id)
		SquadMessageTypes.Type.DEMOLITION_WARNING:
			if str(message.get("sender_member_id", "")) != squad_member_id:
				_receive_squad_demolition_warning(payload)
		SquadMessageTypes.Type.NAVIGATION_REFRESH:
			_receive_squad_navigation_refresh(request_id)
		SquadMessageTypes.Type.SUPPORT_REQUEST:
			var support_position: Vector3 = payload.get("position", INVALID_POSITION)
			_try_claim_squad_support(request_id, support_position)


func _try_claim_squad_demolition(request_id: String) -> void:
	if request_id.is_empty() or not has_method("is_available_for_demolition"):
		return
	## 频道重新开放任务时，原持有者会先完成本地清理；避免在同一调用栈中立刻抢回。
	if get("squad_demolition_request_id") == request_id:
		return
	if not call("is_available_for_demolition"):
		return
	var result := send_squad_message(SquadMessageTypes.Type.DEMOLITION_CLAIM, {"member_id": squad_member_id}, request_id)
	if not bool(result.get("accepted", false)):
		return
	var task: Dictionary = result.get("task", {})
	if has_method("accept_squad_demolition_task"):
		call("accept_squad_demolition_task", request_id, task)


func _try_claim_squad_support(request_id: String, support_position: Vector3) -> void:
	if request_id.is_empty() or not _can_accept_squad_support():
		return
	if not support_position.is_finite():
		return
	var support_distance := _horizontal_distance(global_position, support_position)
	if _support_request_is_far_and_off_target(support_position, support_distance):
		var target_direction := _horizontal_direction(global_position, target.global_position)
		var support_direction := _horizontal_direction(global_position, support_position)
		var angle_degrees := rad_to_deg(target_direction.angle_to(support_direction))
		_debug(
			"support ignored distance=%.1fm angle=%.1fdeg limit=%.1fdeg target=%s"
			% [
				support_distance,
				angle_degrees,
				squad_support_max_off_target_angle_degrees,
				_target_name(target),
			]
		)
		return
	var result := send_squad_message(SquadMessageTypes.Type.SUPPORT_ACK, {"member_id": squad_member_id}, request_id)
	if not bool(result.get("accepted", false)):
		return
	_squad_support_request_id = request_id
	_squad_support_position = result.get("position", INVALID_POSITION)
	_squad_support_timer = squad_support_timeout
	_squad_support_hold_timer = 0.0
	_squad_support_arrived = false


func _support_request_is_far_and_off_target(
	support_position: Vector3,
	support_distance: float
) -> bool:
	## 距离不超过 50m 时始终允许响应；只有远距离请求才检查推进方向。
	if support_distance <= squad_support_max_response_distance:
		return false
	## 没有战略 target 时无法判断是否偏离，不能退化成“超过 50m 一律拒绝”。
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return false
	var target_direction := _horizontal_direction(global_position, target.global_position)
	var support_direction := _horizontal_direction(global_position, support_position)
	if target_direction == Vector3.ZERO or support_direction == Vector3.ZERO:
		return false
	## 以自身为顶点，比较“自身 -> target”和“自身 -> 支援点”两条射线。
	## 夹角超过阈值代表支援点位于当前推进方向的明显反向区域。
	var angle_degrees := rad_to_deg(target_direction.angle_to(support_direction))
	return angle_degrees > squad_support_max_off_target_angle_degrees


func _can_accept_squad_support() -> bool:
	return (
		state != AIState.DEAD
		and state != AIState.COMBAT
		and _squad_support_timer <= 0.0
		and not _squad_support_arrived
	)


func _receive_squad_demolition_warning(payload: Dictionary) -> void:
	var position: Vector3 = payload.get("position", INVALID_POSITION)
	var radius := maxf(
		float(payload.get("radius", 0.0)),
		squad_warning_retreat_distance
	)
	if not position.is_finite():
		return
	var distance := _horizontal_distance(global_position, position)
	## 不要在接收时直接丢弃远处成员的警告。队员当前可能在安全距离外，
	## 但仍会沿 target 接近炸点；保留警告后，进入危险范围的下一帧仍能及时撤离。
	_squad_warning_position = position
	_squad_warning_radius = radius
	_squad_warning_timer = maxf(0.1, squad_warning_retreat_seconds)
	_squad_warning_progress_anchor = global_position
	_squad_warning_no_progress_elapsed = 0.0
	_squad_warning_escape_direction = Vector3.ZERO
	_squad_warning_escape_timer = 0.0
	_debug(
		"squad demolition warning received position=%s radius=%.1fm distance=%.1fm action=%s"
		% [
			_format_position(position),
			radius,
			distance,
			"retreat" if distance < radius else "monitor",
		]
	)


func _receive_squad_navigation_refresh(request_id: String) -> void:
	## 爆破后的导航刷新只让成员废弃旧路径，不会把任何成员拉向爆破点。
	if state == AIState.DEAD:
		return
	var was_stuck := _squad_stuck
	_reset_navigation_path()
	if _squad_stuck:
		_squad_stuck_elapsed = 0.0
		_reset_squad_progress_window(_squad_stuck_goal_for_state())
		_squad_navigation_retry_timer = maxf(0.75, navigation_refresh_interval * 3.0)
	navigation_path_refreshed.emit([], was_stuck)
	_debug(
		"squad navigation refresh received request=%s stuck=%s; target path reset"
		% [request_id, str(was_stuck)]
	)


func _update_squad_warning_retreat(delta: float) -> bool:
	if not _squad_warning_position.is_finite():
		return false
	if _squad_warning_timer <= 0.0:
		_clear_squad_warning_state()
		return false
	var away := global_position - _squad_warning_position
	away.y = 0.0
	if away.length_squared() < 0.01:
		away = Vector3.RIGHT.rotated(Vector3.UP, rng.randf_range(-PI, PI))
	var safe_distance := maxf(_squad_warning_radius, squad_warning_retreat_distance)
	if _horizontal_distance(global_position, _squad_warning_position) >= safe_distance:
		## 已经在安全距离外时不打断原来的 SEARCH/CHASE；警告仍保留到
		## 窗口结束，防止队员继续推进时重新进入爆炸范围。
		return false

	var previous_distance := _horizontal_distance(
		global_position,
		_squad_warning_position
	)
	var retreat_direction := away.normalized()
	if _squad_warning_escape_timer > 0.0:
		_squad_warning_escape_timer = maxf(0.0, _squad_warning_escape_timer - delta)
		retreat_direction = _squad_warning_escape_direction
	else:
		## 炸弹安全撤退不再把目标交给 NavigationAgent，避免安全点落在
		## 导航网格外时得到零方向；先按爆炸点反方向直接撤离。
		retreat_direction = _find_open_movement_direction(retreat_direction)
		retreat_direction = _avoid_immediate_obstacle(retreat_direction)
	if _movement_direction_is_blocked(retreat_direction, 0.8):
		_try_jump_over_obstacle()

	_apply_character_movement(
		retreat_direction,
		flee_speed,
		delta,
		## 爆破撤退必须优先于队形 RVO；仍保留 test_move、射线避障和碰撞，
		## 只是避免 NavigationAgent 的安全速度把撤退方向压成零速度。
		false
	)
	var progress := (
		_horizontal_distance(global_position, _squad_warning_position)
		- previous_distance
	)
	if progress >= 0.12:
		_squad_warning_progress_anchor = global_position
		_squad_warning_no_progress_elapsed = 0.0
	elif _squad_warning_escape_timer <= 0.0:
		_squad_warning_no_progress_elapsed += delta
		if _squad_warning_no_progress_elapsed >= squad_warning_stuck_after_seconds:
			_start_squad_warning_escape(away)
	return true


func _clear_squad_warning_state() -> void:
	_squad_warning_position = INVALID_POSITION
	_squad_warning_radius = 0.0
	_squad_warning_timer = 0.0
	_squad_warning_progress_anchor = INVALID_POSITION
	_squad_warning_no_progress_elapsed = 0.0
	_squad_warning_escape_direction = Vector3.ZERO
	_squad_warning_escape_timer = 0.0


func _start_squad_warning_escape(away: Vector3) -> void:
	var direction := away
	direction.y = 0.0
	if direction.length_squared() <= 0.01:
		direction = -global_transform.basis.z
	if direction.length_squared() <= 0.01:
		direction = Vector3.FORWARD
	## 以远离炸药为主，在左右方向加入随机偏转，绕开堵住的队员/墙角。
	direction = direction.normalized().rotated(
		Vector3.UP,
		rng.randf_range(-PI * 0.75, PI * 0.75)
	).normalized()
	direction = _find_open_movement_direction(direction)
	_squad_warning_escape_direction = direction
	_squad_warning_escape_timer = maxf(0.5, squad_warning_escape_duration)
	_squad_warning_no_progress_elapsed = 0.0
	_debug(
		"squad warning escape started direction=%s duration=%.1fs"
		% [_format_position(direction), _squad_warning_escape_timer]
	)


func _update_squad_escape(delta: float) -> bool:
	if _squad_escape_waypoint == INVALID_POSITION:
		return false
	_squad_escape_timer = maxf(0.0, _squad_escape_timer - delta)
	if _squad_escape_timer <= 0.0:
		_debug(
			"squad escape completed position=%s; resume target navigation"
			% _format_position(global_position)
		)
		_squad_escape_waypoint = INVALID_POSITION
		_squad_escape_direction = Vector3.ZERO
		_squad_escape_timer = 0.0
		_reset_navigation_path()
		return false
	## 脱困动作固定持续 5 秒，不能因为提前接近临时 waypoint 就立即恢复 target。
	if _movement_direction_is_blocked(_squad_escape_direction, 0.8):
		_try_jump_over_obstacle()
	## 方向在脱困开始时确定后，整整 5 秒不再用前方探测改向；这样
	## 墙边来回跳跃不会把“随机固定方向”重新变成原来的卡墙方向。
	_apply_character_movement(
		_squad_escape_direction,
		flee_speed,
		delta,
		false,
		true
	)
	return true


func _update_squad_support(delta: float) -> bool:
	if not _squad_support_position.is_finite():
		return false

	## 支援路上或支援点附近发现敌人进入 COMBAT，就立即结束支援移动，
	## 由普通战斗状态接管，不让支援优先级压住实际交火。
	if _squad_support_can_enter_combat():
		_clear_squad_support()
		state = AIState.COMBAT
		_begin_combat_engagement_if_needed(target_player)
		return false

	if not _squad_support_arrived:
		if _horizontal_distance(global_position, _squad_support_position) <= squad_support_arrival_distance:
			_squad_support_arrived = true
			_squad_support_timer = 0.0
			_squad_support_hold_timer = maxf(0.1, squad_support_wait_seconds)
			if _grenade_avoidance_active:
				_apply_character_movement(Vector3.ZERO, flee_speed, delta)
			else:
				velocity = Vector3.ZERO
			_debug(
				"support arrived position=%s wait=%.1fs"
				% [_format_position(_squad_support_position), _squad_support_hold_timer]
			)
			return true
		_apply_character_movement(
			_avoid_immediate_obstacle(_direction_to_goal(_squad_support_position)),
			chase_speed,
			delta
		)
		return true

	if _squad_support_hold_timer > 0.0:
		if _grenade_avoidance_active:
			## 支援等待不是“暂停模拟”；活动手雷出现时仍立即离开，
			## 同时 _maintain_combat_during_grenade_avoidance() 保持射击/反击。
			_apply_character_movement(Vector3.ZERO, flee_speed, delta)
		else:
			velocity = Vector3.ZERO
		return true

	## 到达支援点后 10 秒没有进入 COMBAT，放弃本次支援并恢复原战略 target。
	_clear_squad_support()
	state = AIState.SEARCH
	target_player = null
	last_known_target_position = INVALID_POSITION
	target_refresh_timer = 0.0
	_debug("support timeout; resume strategic target")
	return false


func _squad_support_can_enter_combat() -> bool:
	if state == AIState.COMBAT:
		return true
	if not _is_valid_target(target_player):
		return false
	var distance := _horizontal_distance(global_position, target_player.global_position)
	return (
		_has_clear_line_to(target_player)
		and distance <= preferred_combat_range + combat_range_tolerance
	)


func _clear_squad_support() -> void:
	_squad_support_request_id = ""
	_squad_support_position = INVALID_POSITION
	_squad_support_timer = 0.0
	_squad_support_hold_timer = 0.0
	_squad_support_arrived = false


func _activate_squad_support_broadcast() -> void:
	if state != AIState.COMBAT:
		return
	_squad_support_broadcast_active = true
	_squad_support_pending_after_bullet = false
	_squad_support_request_timer = 0.0
	_request_squad_support()


func _request_squad_support() -> void:
	if (
		state != AIState.COMBAT
		or not _squad_support_broadcast_active
		or _squad_support_request_timer > 0.0
		or not is_instance_valid(squad_communicator)
	):
		return
	var result := send_squad_message(SquadMessageTypes.Type.SUPPORT_REQUEST, {"position": global_position})
	if bool(result.get("accepted", false)):
		_squad_support_request_timer = squad_support_request_cooldown


func _update_squad_obstacle_reporting() -> void:
	if _squad_demolition_probe_timer > 0.0 or not _uses_squad_demolition_requests():
		return
	if not is_instance_valid(squad_communicator) or state != AIState.SEARCH or _is_valid_target(target_player):
		return
	_squad_demolition_probe_timer = squad_demolition_request_cooldown
	var detected := _detect_squad_demolition_obstacle()
	if detected.is_empty():
		return
	send_squad_message(SquadMessageTypes.Type.DEMOLITION_REQUEST, detected)


func _uses_squad_demolition_requests() -> bool:
	return true


func _detect_squad_demolition_obstacle() -> Dictionary:
	var strategic_position := _resolve_enemy_farm_position()
	if not strategic_position.is_finite():
		return {}
	var direction := _direction_to_goal(strategic_position)
	if direction.length_squared() < 0.01:
		return {}
	direction = direction.normalized()
	var origin := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * squad_demolition_probe_distance, body_collision_mask, [get_rid()])
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var obstacle := _resolve_squad_demolition_root(hit.get("collider") as Node)
	if not is_instance_valid(obstacle):
		return {}
	return {"target": obstacle, "position": hit.get("position", obstacle.global_position), "normal": hit.get("normal", Vector3.UP)}


func _resolve_squad_demolition_root(node: Node) -> Node3D:
	var cursor := node
	var depth := 0
	while is_instance_valid(cursor) and depth < 8:
		if cursor is Node3D and cursor.is_in_group("ai_demolition_target"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


# ------------------------------------------------------------------
# Runtime node creation
# ------------------------------------------------------------------

func _create_required_runtime_nodes() -> void:
	head = _ensure_node3d(self, "Head")
	head.position = Vector3(
		0.0,
		1.7080579,
		-0.45418245
	)

	upper_body_look_target = _ensure_marker3d(
		head,
		"UpperBodyLookTarget"
	)
	upper_body_look_target.position = Vector3(
		0.0,
		0.0,
		-3.0
	)

	right_hand_ik_target = _ensure_marker3d(
		head,
		"RightHandIKTarget"
	)
	right_hand_ik_target.position = Vector3(
		0.28,
		-0.28,
		-0.42
	)

	right_elbow_pole = _ensure_marker3d(
		self,
		"RightElbowPole"
	)
	right_elbow_pole.position = Vector3(
		0.65,
		1.2,
		-0.1
	)

	body_collision_shape = _ensure_capsule_collision(
		self,
		"CollisionShape3D",
		body_capsule_position,
		body_capsule_radius,
		body_capsule_height
	)

	right_hand_socket = _ensure_bone_attachment(
		self,
		"RightHandSocket"
	)
	right_hand_socket.bone_name = "Hand.R"

	tool_pivot = _ensure_node3d(
		right_hand_socket,
		"ToolPivot"
	)

	## 武器和工具可从玩家/AI 根节点查找这两个射线。
	aim_ray = _ensure_raycast3d(
		self,
		"RayCast3D"
	)
	aim_ray.position = Vector3(
		0.0,
		1.4506165,
		0.0
	)
	aim_ray.target_position = Vector3(
		0.0,
		0.0,
		-100.0
	)
	aim_ray.collision_mask = combat_ray_mask
	aim_ray.enabled = true

	look_at_target = _ensure_raycast3d(
		self,
		"LookAtTarget"
	)
	look_at_target.position = Vector3(
		0.0,
		1.4506165,
		0.0
	)
	look_at_target.target_position = Vector3(
		0.0,
		0.0,
		-100.0
	)
	look_at_target.collision_mask = combat_ray_mask
	look_at_target.enabled = true

	front_probe = _ensure_raycast3d(
		self,
		"FrontProbe"
	)
	front_probe.position = Vector3(
		0.0,
		0.8,
		0.0
	)
	front_probe.target_position = Vector3(
		0.0,
		0.0,
		-1.8
	)
	front_probe.collision_mask = body_collision_mask
	front_probe.enabled = true

	left_probe = _ensure_raycast3d(
		self,
		"LeftProbe"
	)
	left_probe.position = Vector3(
		0.0,
		0.8,
		0.0
	)
	left_probe.target_position = Vector3(
		-1.25,
		0.0,
		-1.45
	)
	left_probe.collision_mask = body_collision_mask
	left_probe.enabled = true

	right_probe = _ensure_raycast3d(
		self,
		"RightProbe"
	)
	right_probe.position = Vector3(
		0.0,
		0.8,
		0.0
	)
	right_probe.target_position = Vector3(
		1.25,
		0.0,
		-1.45
	)
	right_probe.collision_mask = body_collision_mask
	right_probe.enabled = true

	navigation_agent = _ensure_navigation_agent(
		self,
		"NavigationAgent3D"
	)
	navigation_agent.radius = maxf(
		0.25,
		body_capsule_radius
	)
	navigation_agent.height = body_capsule_height
	navigation_agent.path_desired_distance = 0.55
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.avoidance_enabled = navigation_avoidance_enabled
	navigation_agent.neighbor_distance = maxf(1.0, navigation_avoidance_neighbor_distance)
	navigation_agent.max_neighbors = maxi(1, navigation_avoidance_max_neighbors)
	if not navigation_agent.velocity_computed.is_connected(_on_navigation_velocity_computed):
		navigation_agent.velocity_computed.connect(_on_navigation_velocity_computed)

	hit_3d = _ensure_area3d(
		self,
		"Hit3D"
	)
	hit_3d.collision_layer = hit_area_collision_layer
	hit_3d.collision_mask = hit_area_collision_mask
	hit_3d.monitoring = true
	hit_3d.monitorable = true

	hit_collision_shape = _ensure_capsule_collision(
		hit_3d,
		"CollisionShape3D",
		hit_capsule_position,
		hit_capsule_radius,
		hit_capsule_height
	)

	if not hit_3d.body_entered.is_connected(
		_on_hit_3d_body_entered
	):
		hit_3d.body_entered.connect(
			_on_hit_3d_body_entered
		)

	if not hit_3d.area_entered.is_connected(
		_on_hit_3d_area_entered
	):
		hit_3d.area_entered.connect(
			_on_hit_3d_area_entered
		)

	health_label = _ensure_health_label(
		self,
		"HealthLabel3D"
	)
	health_label.position = Vector3(
		0.0,
		2.65,
		0.0
	)
	health_label.visible = show_health_label and state != AIState.DEAD


func _ensure_node3d(
	parent: Node,
	node_name: String
) -> Node3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as Node3D
	)

	if existing != null:
		return existing

	var created := Node3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_marker3d(
	parent: Node,
	node_name: String
) -> Marker3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as Marker3D
	)

	if existing != null:
		return existing

	var created := Marker3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_bone_attachment(
	parent: Node,
	node_name: String
) -> BoneAttachment3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as BoneAttachment3D
	)

	if existing != null:
		return existing

	var created := BoneAttachment3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_raycast3d(
	parent: Node,
	node_name: String
) -> RayCast3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as RayCast3D
	)

	if existing != null:
		return existing

	var created := RayCast3D.new()
	created.name = node_name
	created.exclude_parent = true
	parent.add_child(created)
	return created


func _ensure_navigation_agent(
	parent: Node,
	node_name: String
) -> NavigationAgent3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as NavigationAgent3D
	)

	if existing != null:
		return existing

	var created := NavigationAgent3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_area3d(
	parent: Node,
	node_name: String
) -> Area3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as Area3D
	)

	if existing != null:
		return existing

	var created := Area3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_capsule_collision(
	parent: Node,
	node_name: String,
	local_position: Vector3,
	radius: float,
	height: float
) -> CollisionShape3D:
	var collision := (
		parent.get_node_or_null(node_name)
		as CollisionShape3D
	)

	if collision == null:
		collision = CollisionShape3D.new()
		collision.name = node_name
		parent.add_child(collision)

	collision.position = local_position

	var capsule := collision.shape as CapsuleShape3D

	if capsule == null:
		capsule = CapsuleShape3D.new()
		collision.shape = capsule

	capsule.radius = radius
	capsule.height = maxf(
		height,
		radius * 2.0 + 0.01
	)

	return collision


func _ensure_health_label(
	parent: Node,
	node_name: String
) -> Label3D:
	var existing := (
		parent.get_node_or_null(node_name)
		as Label3D
	)

	if existing != null:
		return existing

	var created := Label3D.new()
	created.name = node_name
	created.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	created.font_size = 52
	created.outline_size = 9
	created.modulate = Color("#F5F7FA")
	created.outline_modulate = Color("#111722")
	parent.add_child(created)
	return created


# ------------------------------------------------------------------
# Appearance and player-style animation handling
# ------------------------------------------------------------------

func _load_future_warrior_appearance() -> void:
	var appearance_scene := load(
		future_warrior_scene_path
	) as PackedScene

	if appearance_scene == null:
		push_error(
			"[FutureWarriorAI] Cannot load appearance: %s"
			% future_warrior_scene_path
		)
		return

	var old_appearance := get_node_or_null(
		"AppearanceNode"
	)

	if old_appearance != null:
		old_appearance.queue_free()

	var appearance_node := (
		appearance_scene.instantiate()
		as Node3D
	)

	if appearance_node == null:
		push_error(
			"[FutureWarriorAI] futurewarrior.tscn root must be Node3D."
		)
		return

	appearance_node.name = "AppearanceNode"

	## 与 player.gd 的角色外观方向一致。
	appearance_node.rotation.y = deg_to_rad(
		180.0
	)

	add_child(appearance_node)

	appearance_player = appearance_node.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer

	skeleton = appearance_node.find_child(
		"Skeleton3D",
		true,
		false
	) as Skeleton3D

	if appearance_player == null or skeleton == null:
		push_error(
			"[FutureWarriorAI] AnimationPlayer or Skeleton3D not found."
		)
		return

	right_hand_socket.use_external_skeleton = true
	right_hand_socket.external_skeleton = (
		right_hand_socket.get_path_to(skeleton)
	)
	right_hand_socket.bone_name = "Hand.R"
	right_hand_socket.override_pose = false

	if not appearance_player.animation_finished.is_connected(
		_on_skeleton_animation_finished
	):
		appearance_player.animation_finished.connect(
			_on_skeleton_animation_finished
		)

	_setup_upper_body_aim()
	_play_body_animation(
		&"Idle",
		0.0
	)


func _setup_upper_body_aim() -> void:
	if skeleton == null:
		return

	upper_body_look_modifiers.clear()
	upper_body_look_weights.clear()

	## 与 player.gd 相同的脊柱、胸部、颈部和头部权重。
	_add_upper_body_look(
		"SpineLook",
		"Spine",
		0.10,
		20.0
	)
	_add_upper_body_look(
		"ChestLook",
		"Chest",
		0.22,
		30.0
	)
	_add_upper_body_look(
		"NeckLook",
		"Neck",
		0.16,
		35.0
	)
	_add_upper_body_look(
		"HeadLook",
		"Head_2",
		0.28,
		50.0
	)

	right_arm_ik = skeleton.find_child(
		"RightArmIK",
		false,
		false
	) as TwoBoneIK3D

	if right_arm_ik == null:
		right_arm_ik = TwoBoneIK3D.new()
		right_arm_ik.name = "RightArmIK"
		skeleton.add_child(right_arm_ik)

	right_arm_ik.setting_count = 1
	right_arm_ik.set_root_bone_name(
		0,
		"UpperArm.R"
	)
	right_arm_ik.set_middle_bone_name(
		0,
		"Forearm.R"
	)
	right_arm_ik.set_end_bone_name(
		0,
		"Hand.R"
	)
	right_arm_ik.set_use_virtual_end(
		0,
		false
	)
	right_arm_ik.set_extend_end_bone(
		0,
		false
	)
	right_arm_ik.set_pole_direction(
		0,
		SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X
	)
	right_arm_ik.set_target_node(
		0,
		right_arm_ik.get_path_to(
			right_hand_ik_target
		)
	)
	right_arm_ik.set_pole_node(
		0,
		right_arm_ik.get_path_to(
			right_elbow_pole
		)
	)
	right_arm_ik.active = true
	right_arm_ik.influence = 0.0


func _add_upper_body_look(
	node_name: String,
	bone_name: String,
	base_weight: float,
	limit_degrees: float
) -> void:
	var modifier := skeleton.find_child(
		node_name,
		false,
		false
	) as LookAtModifier3D

	if modifier == null:
		modifier = LookAtModifier3D.new()
		modifier.name = node_name
		skeleton.add_child(modifier)

	modifier.bone_name = bone_name
	modifier.forward_axis = (
		SkeletonModifier3D.BONE_AXIS_PLUS_Z
	)
	modifier.primary_rotation_axis = Vector3.AXIS_X
	modifier.use_secondary_rotation = false
	modifier.relative = true
	modifier.use_angle_limitation = true
	modifier.symmetry_limitation = true
	modifier.primary_limit_angle = deg_to_rad(
		limit_degrees
	)
	modifier.primary_damp_threshold = 1.0
	modifier.target_node = modifier.get_path_to(
		upper_body_look_target
	)
	modifier.active = true
	modifier.influence = 0.0

	upper_body_look_modifiers.append(
		modifier
	)
	upper_body_look_weights.append(
		base_weight
	)


func _update_upper_body_aim(delta: float) -> void:
	if skeleton == null:
		return

	var equipped_scale := (
		1.0
		if is_instance_valid(held_weapon)
		else 0.0
	)

	var action_scale := (
		0.70
		if action_animation_locked
		else 1.0
	)

	for index in range(
		upper_body_look_modifiers.size()
	):
		var modifier := (
			upper_body_look_modifiers[index]
		)

		if not is_instance_valid(modifier):
			continue

		var desired := (
			upper_body_look_weights[index]
			* equipped_scale
			* action_scale
		)

		modifier.influence = move_toward(
			modifier.influence,
			desired,
			delta * 3.5
		)

	if is_instance_valid(right_arm_ik):
		var desired_ik := (
			0.88
			* equipped_scale
			* action_scale
		)

		right_arm_ik.influence = move_toward(
			right_arm_ik.influence,
			desired_ik,
			delta * 5.0
		)


func _play_body_animation(
	animation_name: StringName,
	blend_time: float = 0.12
) -> void:
	if appearance_player == null:
		return

	if not appearance_player.has_animation(
		animation_name
	):
		return

	if (
		appearance_player.current_animation
		== animation_name
		and appearance_player.is_playing()
	):
		return

	appearance_player.play(
		animation_name,
		blend_time
	)


func _play_death_animation() -> void:
	## 四类 AI 统一优先播放 Death；旧外观才回退到 DeathFallForward。
	action_animation_locked = true
	if appearance_player == null:
		return
	var animation_name: StringName = &"Death"
	if not appearance_player.has_animation(animation_name):
		animation_name = &"DeathFallForward"
	if appearance_player.has_animation(animation_name):
		# 死亡后 AI 根节点可能停止常规处理，但 AnimationPlayer 仍需继续推进。
		appearance_player.process_mode = Node.PROCESS_MODE_ALWAYS
		appearance_player.set_process(true)
		appearance_player.play(animation_name, 0.08)


func _play_shoot_animation() -> void:
	action_animation_locked = true
	_play_body_animation(
		&"ShootOneHand",
		0.05
	)


func _play_grenade_animation() -> void:
	action_animation_locked = true
	_play_body_animation(
		&"ToolUseRight",
		0.05
	)


func _on_skeleton_animation_finished(
	animation_name: StringName
) -> void:
	match animation_name:
		&"JumpStart":
			if not is_on_floor():
				_play_body_animation(
					&"JumpLoop",
					0.05
				)

		&"JumpLand":
			landing_animation = false
			## 跳跃可能覆盖了尚未结束的 ShootOneHand/ToolUseRight。
			## 落地后解除动作锁，避免后续 Walk/Idle 更新一直被跳过。
			action_animation_locked = false

		&"ShootOneHand", &"ToolUseRight", &"PunchRIght":
			action_animation_locked = false


func _update_character_animation(
	_move_direction: Vector3,
	actual_horizontal_velocity: Vector3 = Vector3.ZERO
) -> void:
	if appearance_player == null:
		return

	var grounded := is_on_floor()

	if grounded and not was_on_floor:
		## 即使 JumpLand 没有触发 animation_finished，落地帧也会
		## 清掉被跳跃覆盖的射击/工具动画锁。
		action_animation_locked = false
		_play_body_animation(
			&"JumpLand",
			0.05
		)
		landing_animation = true
		was_on_floor = true
		return

	if landing_animation:
		was_on_floor = grounded
		return

	if action_animation_locked:
		was_on_floor = grounded
		return

	if not grounded:
		if (
			appearance_player.current_animation
			!= &"JumpStart"
		):
			_play_body_animation(
				&"JumpLoop",
				0.05
			)

	elif actual_horizontal_velocity.length_squared() > 0.01:
		_play_body_animation(
			&"Walk",
			0.08
		)

	elif is_instance_valid(target_player):
		_play_body_animation(
			&"IdleAim",
			0.10
		)

	elif is_instance_valid(held_weapon):
		_play_body_animation(
			&"IdleTool",
			0.10
		)

	else:
		_play_body_animation(
			&"Idle",
			0.10
		)

	was_on_floor = grounded


## 远端多人 AI 不运行本地物理，只通过快照更新位置。因此使用服务器
## 同步的水平速度直接更新表现层动画，而不是依赖本地 is_on_floor/velocity。
func _update_network_locomotion_animation(
	horizontal_velocity: Vector3,
	grounded: bool = true,
	aiming: bool = false
) -> void:
	if appearance_player == null or state == AIState.DEAD or action_animation_locked:
		return
	var horizontal := horizontal_velocity
	horizontal.y = 0.0
	if not grounded:
		if appearance_player.current_animation != &"JumpStart":
			_play_body_animation(&"JumpLoop", 0.05)
		return
	if horizontal.length_squared() > 0.01:
		_play_body_animation(&"Walk", 0.08)
	elif aiming or _is_valid_target(target_player):
		_play_body_animation(&"IdleAim", 0.10)
	elif is_instance_valid(held_weapon):
		_play_body_animation(&"IdleTool", 0.10)
	else:
		_play_body_animation(&"Idle", 0.10)


# ------------------------------------------------------------------
# Player-style weapon Y-axis / full-basis correction
# ------------------------------------------------------------------

func _update_tool_camera_alignment() -> void:
	if (
		not is_instance_valid(held_weapon)
		or not is_instance_valid(tool_pivot)
		or not is_instance_valid(aim_ray)
	):
		return

	## 这部分与 player.gd 的算法一致：
	## 1. Muzzle 或武器内部 RayCast3D 代表武器真实前向。
	## 2. 计算武器瞄准基准相对 ToolPivot 的固定偏移。
	## 3. 用 AI 的 aim_ray 基准替代玩家 camera 基准。
	## 4. 反推出 ToolPivot 应有的完整 Basis。
	##
	## 因此同时修正 X/Y/Z 三轴，尤其能解决：
	## - Hand.R 动画造成的 Y 轴偏航；
	## - 枪械横滚；
	## - 不同枪模型自身轴向不一致。

	var muzzle := (
		held_weapon.get_node_or_null("Muzzle")
		as Node3D
	)

	var weapon_aim_basis: Basis

	if muzzle != null:
		weapon_aim_basis = muzzle.global_transform.basis.orthonormalized()

	else:
		var weapon_aim_ray := held_weapon.find_child(
			"RayCast3D",
			true,
			false
		) as RayCast3D

		if (
			weapon_aim_ray == null
			or weapon_aim_ray.target_position.is_zero_approx()
		):
			tool_pivot.transform = Transform3D.IDENTITY
			return

		var weapon_ray_direction := (
			weapon_aim_ray.to_global(
				weapon_aim_ray.target_position
			)
			- weapon_aim_ray.global_position
		).normalized()

		var preferred_up := held_weapon.global_transform.basis.y.normalized()

		if absf(
			weapon_ray_direction.dot(preferred_up)
		) > 0.98:
			preferred_up = aim_ray.global_transform.basis.x.normalized()

		weapon_aim_basis = Basis.looking_at(
			weapon_ray_direction,
			preferred_up
		).orthonormalized()

	if weapon_aim_basis.determinant() == 0.0:
		tool_pivot.transform = Transform3D.IDENTITY
		return

	var pivot_basis: Basis = tool_pivot.global_transform.basis.orthonormalized()

	## 武器瞄准轴相对 ToolPivot 的固定差值。
	var aim_from_pivot: Basis = (
		pivot_basis.inverse()
		* weapon_aim_basis
	).orthonormalized()

	## 玩家原算法这里直接使用 camera.global_transform.basis。AI 的
	## aim_ray 是玩家 Camera 的等价瞄准参考节点，所以也必须直接使用它的
	## 完整 Basis，而不是只用水平朝向或重新用 Vector3.UP 构造 Basis；后者
	## 会丢掉俯仰/滚转，表现为多人模式下枪口 Y 轴和实际瞄准线分离。
	var desired_aim_basis: Basis = aim_ray.global_transform.basis.orthonormalized()
	if is_zero_approx(desired_aim_basis.determinant()):
		tool_pivot.transform = Transform3D.IDENTITY
		return

	var desired_pivot_basis: Basis = (
		desired_aim_basis
		* aim_from_pivot.inverse()
	).orthonormalized()

	tool_pivot.global_transform = Transform3D(
		desired_pivot_basis,
		tool_pivot.global_position
	)


# ------------------------------------------------------------------
# Loadout
# ------------------------------------------------------------------

func _load_starting_loadout() -> void:
	weapon_data.clear()

	weapon_data[WeaponSlot.AR15] = _load_item_data(
		ar15_tool_id,
		ar15_scene_path,
		ar15_grip_position,
		ar15_grip_rotation,
		ar15_grip_scale,
		ar15_fire_interval,
		ar15_magazine_size,
		ar15_initial_reserve_ammo,
		ar15_reload_time
	)

	weapon_data[
		WeaponSlot.SUPPRESSED_PISTOL
	] = _load_item_data(
		suppressed_pistol_tool_id,
		suppressed_pistol_scene_path,
		pistol_grip_position,
		pistol_grip_rotation,
		pistol_grip_scale,
		pistol_fire_interval,
		pistol_magazine_size,
		pistol_initial_reserve_ammo,
		pistol_reload_time
	)

	grenade_data = _load_item_data(
		grenade_tool_id,
		grenade_scene_path,
		grenade_grip_position,
		grenade_grip_rotation,
		grenade_grip_scale,
		grenade_cooldown
	)


func _load_item_data(
	tool_id: String,
	fallback_path: String,
	fallback_position: Vector3,
	fallback_rotation: Vector3,
	fallback_scale: Vector3,
	fallback_cooldown: float,
	fallback_magazine_size: int = 0,
	fallback_reserve_ammo: int = 0,
	fallback_reload_time: float = 0.0
) -> Dictionary:
	var result := {
		"id": tool_id,
		"path": fallback_path,
		"grip_position": fallback_position,
		"grip_rotation": fallback_rotation,
		"grip_scale": fallback_scale,
		"cooldown": fallback_cooldown,
		"magazine_size": fallback_magazine_size,
		"initial_reserve_ammo": fallback_reserve_ammo,
		"reload_time": fallback_reload_time,
		"scene": null,
	}

	var json_definition := (
		_find_tool_definition(tool_id)
	)

	if not json_definition.is_empty():
		result["path"] = str(
			json_definition.get(
				"path",
				fallback_path
			)
		)

		result["grip_position"] = _variant_to_vector3(
			json_definition.get(
				"grip_position",
				fallback_position
			),
			fallback_position
		)

		result["grip_rotation"] = _variant_to_vector3(
			json_definition.get(
				"grip_rotation",
				fallback_rotation
			),
			fallback_rotation
		)

		result["grip_scale"] = _variant_to_vector3(
			json_definition.get(
				"grip_scale",
				fallback_scale
			),
			fallback_scale
		)

		result["cooldown"] = float(
			json_definition.get(
				"cooldown",
				fallback_cooldown
			)
		)

		result["magazine_size"] = int(
			json_definition.get(
				"magazine_size",
				fallback_magazine_size
			)
		)

		# Player weapons now receive no free reserve ammunition; they reload from
		# AmmoSupplyBox items. AI loadouts are independent and do not have player
		# backpacks, so keep using each AI's exported reserve setting instead of
		# inheriting the player-only value from the shared tool definition.
		result["initial_reserve_ammo"] = fallback_reserve_ammo

		result["reload_time"] = float(
			json_definition.get(
				"reload_time",
				fallback_reload_time
			)
		)

	var packed_scene := load(
		str(result["path"])
	) as PackedScene

	if packed_scene == null:
		push_error(
			"[FutureWarriorAI] Cannot load item scene: %s"
			% str(result["path"])
		)
	else:
		result["scene"] = packed_scene

	return result


func _find_tool_definition(
	requested_tool_id: String
) -> Dictionary:
	if not FileAccess.file_exists(
		TOOL_CONFIG_PATH
	):
		return {}

	var file := FileAccess.open(
		TOOL_CONFIG_PATH,
		FileAccess.READ
	)

	if file == null:
		return {}

	var json := JSON.new()

	if json.parse(file.get_as_text()) != OK:
		push_warning(
			"[FutureWarriorAI] Invalid tool_definitions.json."
		)
		return {}

	if not json.data is Dictionary:
		return {}

	var source_tools: Variant = (
		json.data.get("tools", [])
	)

	if not source_tools is Array:
		return {}

	var requested_normalized := (
		_normalize_identifier(requested_tool_id)
	)

	## 第一轮：标准化后的 ID 完全匹配。
	for entry: Variant in source_tools:
		if not entry is Dictionary:
			continue

		var definition := entry as Dictionary
		var entry_id := _normalize_identifier(
			str(definition.get("id", ""))
		)

		if entry_id == requested_normalized:
			return definition.duplicate(true)

	## 第二轮：ID、名称、短名、路径模糊匹配。
	for entry: Variant in source_tools:
		if not entry is Dictionary:
			continue

		var definition := entry as Dictionary

		var searchable := _normalize_identifier(
			str(definition.get("id", ""))
			+ " "
			+ str(definition.get("name", ""))
			+ " "
			+ str(definition.get("short", ""))
			+ " "
			+ str(definition.get("path", ""))
		)

		if (
			searchable.contains(requested_normalized)
			or requested_normalized.contains(searchable)
		):
			return definition.duplicate(true)

	return {}


func _normalize_identifier(value: String) -> String:
	return value.to_lower() \
		.replace("_", "") \
		.replace("-", "") \
		.replace(" ", "") \
		.replace("/", "") \
		.replace("\\", "")


func _variant_to_vector3(
	value: Variant,
	fallback: Vector3
) -> Vector3:
	if value is Vector3:
		return value

	if value is Array and value.size() >= 3:
		return Vector3(
			float(value[0]),
			float(value[1]),
			float(value[2])
		)

	return fallback


func _initialize_weapon_ammo() -> void:
	weapon_ammo.clear()
	reloading_weapon_slot = -1
	weapon_reload_timer = 0.0
	for slot_value: Variant in weapon_data.keys():
		var slot := int(slot_value)
		var definition: Dictionary = weapon_data.get(slot, {})
		var capacity := maxi(1, int(definition.get("magazine_size", 1)))
		weapon_ammo[slot] = {
			"ammo_in_mag": capacity,
			"reserve_ammo": maxi(0, int(definition.get("initial_reserve_ammo", 0))),
			"magazine_size": capacity,
			"reload_time": maxf(0.05, float(definition.get("reload_time", 1.0))),
		}


func _weapon_ammo_in_mag(slot: int) -> int:
	var ammo_state: Dictionary = weapon_ammo.get(slot, {})
	return maxi(0, int(ammo_state.get("ammo_in_mag", 0)))


func _weapon_reserve_ammo(slot: int) -> int:
	var ammo_state: Dictionary = weapon_ammo.get(slot, {})
	return maxi(0, int(ammo_state.get("reserve_ammo", 0)))


func _weapon_magazine_capacity(slot: int) -> int:
	var ammo_state: Dictionary = weapon_ammo.get(slot, {})
	return maxi(1, int(ammo_state.get("magazine_size", 1)))


func _weapon_has_loaded_rounds(slot: int) -> bool:
	return weapon_data.has(slot) and _weapon_ammo_in_mag(slot) > 0


func _weapon_can_reload(slot: int) -> bool:
	return (
		weapon_data.has(slot)
		and _weapon_ammo_in_mag(slot) < _weapon_magazine_capacity(slot)
		and _weapon_reserve_ammo(slot) > 0
	)


func _consume_weapon_round(slot: int) -> void:
	if not weapon_ammo.has(slot):
		return
	var ammo_state: Dictionary = weapon_ammo[slot]
	ammo_state["ammo_in_mag"] = maxi(0, int(ammo_state.get("ammo_in_mag", 0)) - 1)
	weapon_ammo[slot] = ammo_state
	_update_health_label()


func _start_weapon_reload(slot: int) -> bool:
	if not _weapon_can_reload(slot):
		return false
	if reloading_weapon_slot == slot:
		return true
	if reloading_weapon_slot >= 0:
		_cancel_weapon_reload("switch_reload")
	if not _equip_weapon(slot):
		return false
	var ammo_state: Dictionary = weapon_ammo.get(slot, {})
	reloading_weapon_slot = slot
	weapon_reload_timer = maxf(0.05, float(ammo_state.get("reload_time", 1.0)))
	if slot == WeaponSlot.AR15:
		ar15_burst_shots_remaining = 0
		ar15_burst_pause_timer = 0.0
	_debug(
		"reload started slot=%d mag=%d reserve=%d duration=%.2fs"
		% [slot, _weapon_ammo_in_mag(slot), _weapon_reserve_ammo(slot), weapon_reload_timer]
	)
	return true


func _finish_weapon_reload() -> void:
	var slot := reloading_weapon_slot
	reloading_weapon_slot = -1
	weapon_reload_timer = 0.0
	if slot < 0 or not weapon_ammo.has(slot):
		return
	var ammo_state: Dictionary = weapon_ammo[slot]
	var needed := maxi(0, _weapon_magazine_capacity(slot) - int(ammo_state.get("ammo_in_mag", 0)))
	var transferred := mini(needed, maxi(0, int(ammo_state.get("reserve_ammo", 0))))
	ammo_state["ammo_in_mag"] = int(ammo_state.get("ammo_in_mag", 0)) + transferred
	ammo_state["reserve_ammo"] = int(ammo_state.get("reserve_ammo", 0)) - transferred
	weapon_ammo[slot] = ammo_state
	_debug(
		"reload completed slot=%d mag=%d reserve=%d"
		% [slot, _weapon_ammo_in_mag(slot), _weapon_reserve_ammo(slot)]
	)
	_update_health_label()


func _cancel_weapon_reload(reason: String) -> void:
	if reloading_weapon_slot < 0:
		return
	_debug("reload cancelled slot=%d reason=%s" % [reloading_weapon_slot, reason])
	reloading_weapon_slot = -1
	weapon_reload_timer = 0.0


func _maintain_out_of_combat_loadout() -> void:
	if reloading_weapon_slot >= 0:
		return
	## 脱离交火后先补满主武器，再补副武器，最后恢复默认手持 FutureM4。
	if _weapon_can_reload(WeaponSlot.AR15):
		_start_weapon_reload(WeaponSlot.AR15)
		return
	if _weapon_can_reload(WeaponSlot.SUPPRESSED_PISTOL):
		_start_weapon_reload(WeaponSlot.SUPPRESSED_PISTOL)
		return
	_equip_weapon(WeaponSlot.AR15)


func _equip_weapon(slot: int) -> bool:
	if (
		current_weapon_slot == slot
		and is_instance_valid(held_weapon)
	):
		return true

	if not weapon_data.has(slot):
		return false

	var definition: Dictionary = (
		weapon_data[slot]
	)

	var packed_scene := (
		definition.get("scene")
		as PackedScene
	)

	if packed_scene == null:
		return false

	if is_instance_valid(held_weapon):
		held_weapon.queue_free()
		held_weapon = null

	held_weapon = (
		packed_scene.instantiate()
		as Node3D
	)

	if held_weapon == null:
		return false

	tool_pivot.add_child(held_weapon)

	held_weapon.position = definition.get(
		"grip_position",
		Vector3.ZERO
	)

	held_weapon.rotation_degrees = definition.get(
		"grip_rotation",
		Vector3.ZERO
	)

	held_weapon.scale = definition.get(
		"grip_scale",
		Vector3.ONE
	)

	_set_optional_property(
		held_weapon,
		"tool_owner",
		team_id
	)
	_set_optional_property(
		held_weapon,
		"team",
		team_id
	)
	_set_optional_property(
		held_weapon,
		"team_id",
		team_id
	)
	_set_optional_property(
		held_weapon,
		"owner_team",
		team_id
	)

	if held_weapon.has_method("set_aiming"):
		held_weapon.call(
			"set_aiming",
			true
		)

	current_weapon_slot = slot

	if slot != WeaponSlot.AR15:
		ar15_burst_shots_remaining = 0
		ar15_burst_pause_timer = 0.0

	## 装备后立即按枪口真实轴向重新矫正。
	call_deferred(
		"_update_tool_camera_alignment"
	)

	_debug(
		"equipped slot=%d path=%s"
		% [slot, str(definition.get("path", ""))]
	)

	return true


# ------------------------------------------------------------------
# Timers
# ------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	if reloading_weapon_slot >= 0:
		weapon_reload_timer = maxf(0.0, weapon_reload_timer - delta)
		if weapon_reload_timer <= 0.0:
			_finish_weapon_reload()
	_squad_demolition_probe_timer = maxf(0.0, _squad_demolition_probe_timer - delta)
	_squad_support_request_timer = maxf(0.0, _squad_support_request_timer - delta)
	_squad_support_timer = maxf(0.0, _squad_support_timer - delta)
	_squad_support_hold_timer = maxf(0.0, _squad_support_hold_timer - delta)
	_squad_warning_timer = maxf(0.0, _squad_warning_timer - delta)
	if (
		not _squad_support_arrived
		and _squad_support_timer <= 0.0
		and _squad_support_position.is_finite()
	):
		_clear_squad_support()
	if state != AIState.COMBAT:
		_squad_support_broadcast_active = false
	if state in [AIState.SEARCH, AIState.FLEE]:
		_squad_support_pending_after_bullet = false
	## 警告计时只用于记录初始撤退窗口，不能在队员仍处于爆炸半径内时
	## 清除警告；真正的清理由 _update_squad_warning_retreat 在到达安全距离后完成。
	target_refresh_timer = maxf(
		0.0,
		target_refresh_timer - delta
	)

	navigation_refresh_timer = maxf(
		0.0,
		navigation_refresh_timer - delta
	)

	enemy_farm_refresh_timer = maxf(0.0, enemy_farm_refresh_timer - delta)
	search_look_phase = fmod(search_look_phase + delta, maxf(0.1, search_look_sweep_seconds))

	fire_timer = maxf(
		0.0,
		fire_timer - delta
	)

	grenade_timer = maxf(
		0.0,
		grenade_timer - delta
	)

	ar15_burst_pause_timer = maxf(
		0.0,
		ar15_burst_pause_timer - delta
	)

	flee_timer = maxf(
		0.0,
		flee_timer - delta
	)

	flee_retrigger_timer = maxf(
		0.0,
		flee_retrigger_timer - delta
	)
	retaliation_timer = maxf(0.0, retaliation_timer - delta)
	if retaliation_timer <= 0.0:
		retaliation_target = null

	damage_memory_timer = maxf(
		0.0,
		damage_memory_timer - delta
	)

	strafe_timer = maxf(
		0.0,
		strafe_timer - delta
	)

	jump_timer = maxf(
		0.0,
		jump_timer - delta
	)

	if damage_memory_timer <= 0.0:
		recent_damage = 0.0

	if strafe_timer <= 0.0:
		strafe_sign *= -1.0
		_reset_strafe_timer()


func _reset_strafe_timer() -> void:
	strafe_timer = rng.randf_range(
		strafe_change_min,
		strafe_change_max
	)


# ------------------------------------------------------------------
# Target selection
# ------------------------------------------------------------------

## Squad/地图可以通过这个接口设置战略目标。
## target 的类型始终是 Node3D；传入 null 时下一次 AI 更新会重新选择敌方出生点。
func set_strategic_target(value: Node3D) -> void:
	if is_instance_valid(_fallback_strategic_target) and _fallback_strategic_target != value:
		_fallback_strategic_target.queue_free()
		_fallback_strategic_target = null
	target = value
	_debug("strategic target changed to %s" % _target_name(target))


func set_target(value: Node3D) -> void:
	set_strategic_target(value)


func get_strategic_target() -> Node3D:
	return target if is_instance_valid(target) and not target.is_queued_for_deletion() else null


func _ensure_strategic_target() -> void:
	if is_instance_valid(target) and not target.is_queued_for_deletion():
		if is_instance_valid(_fallback_strategic_target) and target != _fallback_strategic_target:
			_fallback_strategic_target.queue_free()
			_fallback_strategic_target = null
		return

	if is_instance_valid(_fallback_strategic_target):
		_fallback_strategic_target.queue_free()
		_fallback_strategic_target = null
	target = null

	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world) or not game_world.has_method("get_random_enemy_spawn_position"):
		return

	var value: Variant = game_world.call(
		"get_random_enemy_spawn_position",
		team_id,
		get_instance_id() + int(Time.get_ticks_msec() / 1000.0),
		0,
	)
	if not value is Vector3 or (value as Vector3) == Vector3.INF:
		return

	var fallback := Node3D.new()
	fallback.name = "%s_Target_EnemySpawn" % name
	fallback.set_meta("future_warrior_target_source", "enemy_spawn")
	fallback.set_meta("future_warrior_target_owner", get_instance_id())
	game_world.add_child(fallback)
	fallback.global_position = value as Vector3
	_fallback_strategic_target = fallback
	target = fallback
	_debug(
		"target fallback selected enemy_spawn position=%s"
		% _format_position(fallback.global_position)
	)

func _refresh_target() -> void:
	if target_refresh_timer > 0.0:
		return

	target_refresh_timer = target_refresh_interval
	var previous_target := target_player
	if retaliation_timer > 0.0 and _is_valid_target(retaliation_target):
		target_player = retaliation_target
	else:
		target_player = _find_best_visible_hostile()

	if target_player == null:
		if state != AIState.FLEE:
			state = AIState.SEARCH
		_weapon_aim_active = false

		last_known_target_position = (
			INVALID_POSITION
		)
		return

	last_known_target_position = (
		target_player.global_position
	)
	if target_player != previous_target:
		_begin_target_engagement(target_player)

	if state != AIState.FLEE:
		state = AIState.CHASE

	_debug(
		"target=%s"
		% target_player.name
	)


func _begin_target_engagement(candidate: CharacterBody3D) -> void:
	if not _is_valid_target(candidate):
		return
	var candidate_id := int(candidate.get_instance_id())
	if engagement_grenade_target_id == candidate_id:
		return
	engagement_grenade_target_id = candidate_id
	engagement_grenade_pending = grenades_remaining > 0
	_debug(
		"engagement started target=%s grenade_pending=%s"
		% [candidate.name, str(engagement_grenade_pending)]
	)


func _begin_combat_engagement_if_needed(candidate: CharacterBody3D) -> void:
	if not _is_valid_target(candidate):
		return
	var candidate_id := int(candidate.get_instance_id())
	if (
		combat_engagement_target_id != candidate_id
		or not combat_engagement_point.is_finite()
	):
		combat_engagement_target_id = candidate_id
		combat_engagement_point = global_position
		_debug(
			"combat engagement point=%s target=%s"
			% [_format_position(combat_engagement_point), candidate.name]
		)


func _find_best_enemy_player() -> CharacterBody3D:
	return _find_best_visible_hostile()


func _uses_server_player_proxies() -> bool:
	## Multiplayer authority owns ServerPlayerPhysicsBody nodes. The host also
	## has a local GamePlayer presentation node, but that node is prediction/UI
	## state and must never become an AI combat target on the server.
	return GameAuthority.is_server_authority()


func _authoritative_human_player_groups() -> Array[StringName]:
	var groups: Array[StringName] = []
	groups.append(
		&"server_human_players"
		if _uses_server_player_proxies()
		else &"human_players"
	)
	return groups


func _authoritative_human_player_nodes() -> Array[Node]:
	# Return live authority-side player bodies, not stale presentation nodes.
	var result: Array[Node] = []
	var seen: Dictionary = {}
	if _uses_server_player_proxies():
		var proxy_map: Dictionary = GameAuthority.player_physics_nodes
		for proxy_value: Variant in proxy_map.values():
			if not proxy_value is CharacterBody3D or not is_instance_valid(proxy_value) \
					or not (proxy_value as CharacterBody3D).is_inside_tree():
				continue
			var proxy := proxy_value as Node
			if seen.has(proxy.get_instance_id()):
				continue
			seen[proxy.get_instance_id()] = true
			result.append(proxy)
		for node in get_tree().get_nodes_in_group("server_human_players"):
			if not node is CharacterBody3D or not is_instance_valid(node) \
					or not (node as CharacterBody3D).is_inside_tree():
				continue
			if seen.has(node.get_instance_id()):
				continue
			seen[node.get_instance_id()] = true
			result.append(node)
		return result
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is CharacterBody3D or not is_instance_valid(node) \
				or not (node as CharacterBody3D).is_inside_tree():
			continue
		if seen.has(node.get_instance_id()):
			continue
		seen[node.get_instance_id()] = true
		result.append(node)
	return result


func _server_presentation_player_query_exclusions() -> Array[RID]:
	## Match GameAuthority's server raycast rule: presentation players are
	## excluded from authority-side vision and clear-line queries so they cannot
	## occlude the authoritative physics proxy.
	var exclusions: Array[RID] = []
	if not _uses_server_player_proxies():
		return exclusions
	for node in get_tree().get_nodes_in_group("human_players"):
		# ServerPlayerPhysicsBody is also in human_players for compatibility;
		# only exclude the full presentation GamePlayer nodes.
		if not node is GamePlayer or not node is CollisionObject3D:
			continue
		var rid := (node as CollisionObject3D).get_rid()
		if not exclusions.has(rid):
			exclusions.append(rid)
	return exclusions


func _find_best_visible_hostile() -> CharacterBody3D:
	var best_target: CharacterBody3D
	var best_score := INF
	var now_msec := Time.get_ticks_msec()

	var candidates: Array[Node] = _authoritative_human_player_nodes()
	var seen: Dictionary = {}
	for player_node in candidates:
		seen[player_node.get_instance_id()] = true
	# Deployed remote devices and vehicles opt into ai_combat_targets.  Keep this
	# group-based so new attackable equipment does not need a per-AI type check.
	for group_name in [&"wild_animals", &"combat_characters", &"ai_combat_targets"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if is_instance_valid(node) and not seen.has(node.get_instance_id()):
				seen[node.get_instance_id()] = true
				candidates.append(node)
	for node in candidates:
		if not node is CharacterBody3D:
			continue
		var candidate := node as CharacterBody3D
		if not _is_active_hostile_candidate(candidate):
			continue
		if not _is_inside_vision_cone(candidate) or not _has_visual_contact(candidate):
			continue
		if not _is_candidate_aware(candidate, now_msec):
			continue

		# 视线内玩家优先；AI、野生动物、遥控设备和载具同级后按距离选择。
		var priority := 0.0 if candidate.is_in_group("human_players") \
			or candidate.is_in_group("server_human_players") else 1000.0
		var score := priority + global_position.distance_to(candidate.global_position)
		if score < best_score:
			best_score = score
			best_target = candidate

	_decay_unseen_target_awareness(now_msec)
	return best_target


func _sanitize_target_references() -> void:
	## A target can be queue_free()'d by damage/explosion processing between two
	## target refreshes. Clear the stale typed references before any state code
	## tries to pass them into a CharacterBody3D-specific method.
	if not is_instance_valid(target_player):
		target_player = null
	if not is_instance_valid(retaliation_target):
		retaliation_target = null
		retaliation_timer = 0.0


func _is_valid_target(candidate: Variant) -> bool:
	## Do not type this parameter as CharacterBody3D: GDScript validates typed
	## call arguments before entering the function, and a previously freed target
	## would therefore throw before is_instance_valid() could reject it.
	if not is_instance_valid(candidate) or not candidate is CharacterBody3D:
		return false
	var character := candidate as CharacterBody3D
	return (
		not character.is_queued_for_deletion()
		and _is_active_hostile_candidate(character)
	)


func _is_active_hostile_candidate(candidate: CharacterBody3D) -> bool:
	if candidate == null or candidate == self:
		return false
	if candidate.is_in_group("human_players") or candidate.is_in_group("server_human_players"):
		var expected_group := "server_human_players" if _uses_server_player_proxies() else "human_players"
		if not candidate.is_in_group(expected_group):
			return false
	if candidate.has_method("get_network_state"):
		var network_state := candidate.call("get_network_state") as Dictionary
		if bool(network_state.get("dead", false)):
			return false
	if candidate.is_in_group("wild_animals"):
		return candidate is BlackBear and int((candidate as BlackBear).state) != BlackBear.State.DEAD
	return _is_enemy(candidate)


func _is_inside_vision_cone(candidate: Node3D) -> bool:
	# Despite the legacy method name, vision is now a true 3D sphere.  The
	# forward cone is used by _is_candidate_aware() only to decide whether
	# identification is instant or must accumulate peripheral awareness.
	return global_position.distance_to(candidate.global_position) <= vision_range


func _is_candidate_aware(candidate: CharacterBody3D, now_msec: int) -> bool:
	var candidate_id := candidate.get_instance_id()
	_target_awareness_last_seen_msec[candidate_id] = now_msec

	var direction := _horizontal_direction(global_position, candidate.global_position)
	if direction == Vector3.ZERO:
		_target_awareness[candidate_id] = 1.0
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.0001:
		_target_awareness[candidate_id] = 1.0
		return true
	forward = forward.normalized()
	var facing_dot := forward.dot(direction)
	var direct_view_threshold := cos(deg_to_rad(vision_fov_degrees * 0.5))
	if facing_dot >= direct_view_threshold:
		_target_awareness[candidate_id] = 1.0
		return true

	# Peripheral/back awareness deliberately builds over repeated 0.2s scans.
	# A small random factor makes first discovery probabilistic without causing
	# a detected target to flicker between found and lost states.
	var distance_ratio := clampf(
		global_position.distance_to(candidate.global_position) / maxf(0.01, vision_range),
		0.0,
		1.0
	)
	var proximity := 1.0 - distance_ratio
	var rear_amount := clampf(
		(direct_view_threshold - facing_dot) / maxf(0.01, direct_view_threshold + 1.0),
		0.0,
		1.0
	)
	var awareness_rate := lerpf(
		peripheral_awareness_far_per_second,
		peripheral_awareness_near_per_second,
		proximity
	)
	awareness_rate *= lerpf(1.0, rear_awareness_multiplier, rear_amount)
	awareness_rate *= rng.randf_range(0.75, 1.25)
	var awareness := clampf(
		float(_target_awareness.get(candidate_id, 0.0))
		+ awareness_rate * maxf(0.01, target_refresh_interval),
		0.0,
		1.0
	)
	_target_awareness[candidate_id] = awareness
	return awareness >= 1.0


func _decay_unseen_target_awareness(now_msec: int) -> void:
	var stale_ids: Array[int] = []
	for id_value in _target_awareness.keys():
		var candidate_id := int(id_value)
		var last_seen_msec := int(_target_awareness_last_seen_msec.get(candidate_id, 0))
		if now_msec - last_seen_msec <= roundi(awareness_memory_seconds * 1000.0):
			continue
		var awareness := maxf(
			0.0,
			float(_target_awareness.get(candidate_id, 0.0))
			- awareness_decay_per_second * maxf(0.01, target_refresh_interval)
		)
		if awareness <= 0.0:
			stale_ids.append(candidate_id)
		else:
			_target_awareness[candidate_id] = awareness
	for candidate_id in stale_ids:
		_target_awareness.erase(candidate_id)
		_target_awareness_last_seen_msec.erase(candidate_id)


func _has_visual_contact(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	var visible_rays := 0
	for height in [0.38, target_height, 1.55]:
		var destination := candidate.global_position + Vector3.UP * float(height)
		if _vision_ray_reaches_candidate(candidate, destination):
			visible_rays += 1
	# ServerPlayerPhysicsBody is deliberately a compact capsule, unlike the full
	# visual GamePlayer skeleton. A single unobstructed chest/head ray is enough
	# to establish real visual contact; requiring two out of three rays made a
	# plainly visible proxy fail detection at slopes and behind low cover.
	return visible_rays >= 1


func _vision_ray_reaches_candidate(candidate: Node3D, destination: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		head.global_position,
		destination,
		vision_occlusion_mask,
		[get_rid()] + _server_presentation_player_query_exclusions()
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var cursor := hit.get("collider") as Node
	var depth := 0
	while cursor != null and depth < 12:
		if cursor == candidate:
			return true
		cursor = cursor.get_parent()
		depth += 1
	return false


# ------------------------------------------------------------------
# State updates
# ------------------------------------------------------------------

func _update_search_state(delta: float) -> Vector3:
	if enemy_farm_refresh_timer <= 0.0 or enemy_farm_position == INVALID_POSITION:
		enemy_farm_refresh_timer = enemy_farm_refresh_interval
		enemy_farm_position = _resolve_enemy_farm_position()
		if farm_patrol_position == INVALID_POSITION:
			farm_patrol_position = enemy_farm_position

	if enemy_farm_position == INVALID_POSITION:
		search_look_direction = Vector3.ZERO
		return Vector3.ZERO

	if _is_near_map_boundary():
		# 已接近空气墙时优先退回地图内部，不能继续追随已失效的巡逻点。
		farm_patrol_position = _map_interior_turn_position()
		var return_direction := _direction_to_goal(farm_patrol_position)
		_update_search_look_direction(return_direction, delta)
		return return_direction

	if farm_patrol_position == INVALID_POSITION \
		or _horizontal_distance(global_position, farm_patrol_position) <= 1.5:
		farm_patrol_position = _next_enemy_farm_patrol_position()

	var route_direction := _direction_to_goal(farm_patrol_position)
	_update_search_look_direction(route_direction, delta)
	return route_direction


func _resolve_enemy_farm_position() -> Vector3:
	_ensure_strategic_target()
	if is_instance_valid(target) and not target.is_queued_for_deletion():
		if is_instance_valid(squad) and squad.has_method("get_member_navigation_goal"):
			return squad.get_member_navigation_goal(squad_member_id, target.global_position)
		return target.global_position
	return INVALID_POSITION


func _target_name(value: Node3D) -> String:
	return value.name if is_instance_valid(value) else "none"


func _format_position(value: Vector3) -> String:
	return "(%.1f, %.1f, %.1f)" % [value.x, value.y, value.z]


func _next_enemy_farm_patrol_position() -> Vector3:
	if enemy_farm_position == INVALID_POSITION:
		return INVALID_POSITION
	var offset := Vector3(
		rng.randf_range(-enemy_farm_patrol_radius, enemy_farm_patrol_radius),
		0.0,
		rng.randf_range(-enemy_farm_patrol_radius, enemy_farm_patrol_radius)
	)
	if offset.length_squared() < 4.0:
		offset = Vector3(enemy_farm_patrol_radius, 0.0, 0.0)
	return _clamp_to_map_interior(enemy_farm_position + offset)


func _is_near_map_boundary() -> bool:
	var safe_limit := maxf(0.0, map_boundary_limit - boundary_turn_margin)
	return absf(global_position.x) >= safe_limit or absf(global_position.z) >= safe_limit


func _map_interior_turn_position() -> Vector3:
	var safe_limit := maxf(0.0, map_boundary_limit - boundary_turn_margin * 2.0)
	return Vector3(
		clampf(global_position.x, -safe_limit, safe_limit),
		global_position.y,
		clampf(global_position.z, -safe_limit, safe_limit)
	)


func _clamp_to_map_interior(position: Vector3) -> Vector3:
	var safe_limit := maxf(0.0, map_boundary_limit - boundary_turn_margin * 2.0)
	return Vector3(
		clampf(position.x, -safe_limit, safe_limit),
		position.y,
		clampf(position.z, -safe_limit, safe_limit)
	)


func _update_search_look_direction(route_direction: Vector3, _delta: float) -> void:
	if route_direction == Vector3.ZERO:
		search_look_direction = -global_transform.basis.z
		return
	var progress := search_look_phase / maxf(0.1, search_look_sweep_seconds)
	var sweep_angle := sin(progress * TAU) * deg_to_rad(search_look_sweep_degrees)
	search_look_direction = route_direction.rotated(Vector3.UP, sweep_angle).normalized()


func _update_chase_state() -> Vector3:
	if not _is_valid_target(target_player):
		state = AIState.SEARCH
		return Vector3.ZERO

	if (
		combat_engagement_point.is_finite()
		and combat_engagement_target_id == int(target_player.get_instance_id())
		and _horizontal_distance(global_position, combat_engagement_point)
		>= chase_max_distance_from_engagement
	):
		_disengage_from_chase()
		return Vector3.ZERO

	var target_position := (
		target_player.global_position
	)

	var distance := _horizontal_distance(
		global_position,
		target_position
	)

	var clear_line := _has_clear_line_to(
		target_player
	)

	last_known_target_position = target_position

	_aim_at(
		_get_predicted_aim_position(
			target_player
		)
	)

	if (
		clear_line
		and distance
		<= preferred_combat_range
		+ combat_range_tolerance
	):
		state = AIState.COMBAT
		return _update_combat_state()

	## 追击过程中进入射程也允许开火。
	if clear_line:
		_try_throw_grenade(distance)
		_try_fire_at_target(distance)

	return _direction_to_goal(
		target_position
	)


func _disengage_from_chase() -> void:
	_debug(
		"chase leash reached %.1fm; resume strategic target"
		% chase_max_distance_from_engagement
	)
	state = AIState.SEARCH
	target_player = null
	retaliation_target = null
	retaliation_timer = 0.0
	last_known_target_position = INVALID_POSITION
	combat_engagement_point = INVALID_POSITION
	combat_engagement_target_id = 0
	_weapon_aim_active = false
	_squad_support_broadcast_active = false
	_squad_support_pending_after_bullet = false
	target_refresh_timer = 0.0


func _update_combat_state() -> Vector3:
	if not _is_valid_target(target_player):
		state = AIState.SEARCH
		return Vector3.ZERO

	var target_position := (
		target_player.global_position
	)

	var distance := _horizontal_distance(
		global_position,
		target_position
	)

	var to_target := _horizontal_direction(
		global_position,
		target_position
	)

	var clear_line := _has_clear_line_to(
		target_player
	)

	last_known_target_position = target_position

	_aim_at(
		_get_predicted_aim_position(
			target_player
		)
	)

	if (
		not clear_line
		or distance
		> preferred_combat_range
		+ combat_range_tolerance
	):
		_squad_support_broadcast_active = false
		state = AIState.CHASE
		return _direction_to_goal(
			target_position
		)

	_begin_combat_engagement_if_needed(target_player)
	if _squad_support_pending_after_bullet:
		_activate_squad_support_broadcast()
	_request_squad_support()
	_try_throw_grenade(distance)
	_try_fire_at_target(distance)

	## 太近时向后退。
	if distance < minimum_combat_distance:
		return -to_target

	## 正常射击距离内左右横移，并做轻微距离修正。
	var perpendicular := Vector3(
		-to_target.z,
		0.0,
		to_target.x
	) * strafe_sign

	var range_error := (
		distance
		- preferred_combat_range
	)

	var radial_correction := (
		to_target
		* clampf(
			range_error * 0.18,
			-0.55,
			0.55
		)
	)

	return (
		perpendicular * 0.82
		+ radial_correction
	).normalized()


func _update_flee_state() -> Vector3:
	if flee_timer <= 0.0:
		flee_target = INVALID_POSITION

		if _is_valid_target(target_player):
			state = AIState.CHASE
		else:
			state = AIState.SEARCH

		return Vector3.ZERO

	## 撤退过程中也遵循主武器优先、主武器空仓才切副武器的规则。
	if _is_valid_target(target_player):
		var distance := _horizontal_distance(
			global_position,
			target_player.global_position
		)

		if (
			distance <= pistol_max_range
			and _has_clear_line_to(target_player)
		):
			_aim_at(
				_get_predicted_aim_position(
					target_player
				)
			)

			_try_fire_at_target(distance)

	if (
		flee_target == INVALID_POSITION
		or _horizontal_distance(
			global_position,
			flee_target
		) <= 1.2
	):
		_refresh_flee_target()

	return _direction_to_goal(
		flee_target
	)


func _begin_flee(
	duration: float,
	source_position: Vector3 = INVALID_POSITION
) -> void:
	if state == AIState.DEAD:
		return

	if flee_retrigger_timer > 0.0:
		return

	if source_position != INVALID_POSITION:
		last_damage_source_position = (
			source_position
		)

	state = AIState.FLEE
	flee_timer = maxf(
		duration,
		0.1
	)
	flee_retrigger_timer = (
		flee_retrigger_cooldown
	)

	_refresh_flee_target()

	_debug(
		"flee duration=%.2f"
		% flee_timer
	)


func _refresh_flee_target() -> void:
	var danger_position := (
		last_damage_source_position
	)

	if (
		danger_position == INVALID_POSITION
		and _is_valid_target(target_player)
	):
		danger_position = (
			target_player.global_position
		)

	if danger_position == INVALID_POSITION:
		danger_position = (
			global_position
			+ global_transform.basis.z
		)

	var away := (
		global_position
		- danger_position
	)
	away.y = 0.0

	if away.length_squared() < 0.001:
		away = Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0,
			rng.randf_range(-1.0, 1.0)
		)

	away = away.normalized()

	var lateral := Vector3(
		-away.z,
		0.0,
		away.x
	) * rng.randf_range(
		-0.45,
		0.45
	)

	flee_target = (
		global_position
		+ (away + lateral).normalized()
		* flee_distance
	)

	navigation_refresh_timer = 0.0


# ------------------------------------------------------------------
# Shooting
# ------------------------------------------------------------------

func _try_fire_at_target(
	distance: float
) -> void:
	if not _is_valid_target(target_player):
		return

	var desired_slot := -1
	if _weapon_has_loaded_rounds(WeaponSlot.AR15):
		desired_slot = WeaponSlot.AR15
	elif _weapon_has_loaded_rounds(WeaponSlot.SUPPRESSED_PISTOL):
		## 只有 FutureM4 当前弹匣已经打空并且仍处于交火时才使用手枪。
		desired_slot = WeaponSlot.SUPPRESSED_PISTOL
	else:
		## 两把武器都空仓：按要求切回 FutureM4 并优先为主武器换弹。
		if not _start_weapon_reload(WeaponSlot.AR15):
			_start_weapon_reload(WeaponSlot.SUPPRESSED_PISTOL)
		return

	if desired_slot == WeaponSlot.AR15 and distance > ar15_max_range:
		return
	if desired_slot == WeaponSlot.SUPPRESSED_PISTOL and distance > pistol_max_range:
		return

	_try_fire_weapon(desired_slot)


func _try_fire_weapon(slot: int) -> void:
	if fire_timer > 0.0:
		return

	if not _is_valid_target(target_player):
		return

	if not _has_clear_line_to(target_player):
		return

	if reloading_weapon_slot >= 0:
		if reloading_weapon_slot == slot:
			return
		## 交火时需要另一把已有弹药的武器，允许中断当前换弹动作。
		_cancel_weapon_reload("firefight_weapon_switch")

	if not _weapon_has_loaded_rounds(slot):
		return

	if slot == WeaponSlot.AR15:
		if ar15_burst_pause_timer > 0.0:
			return

		if ar15_burst_shots_remaining <= 0:
			ar15_burst_shots_remaining = (
				ar15_burst_size
			)

	if not _equip_weapon(slot):
		return

	var aim_position := (
		_get_predicted_aim_position(
			target_player
		)
	)

	aim_position += _make_aim_error(
		aim_position
	)

	_aim_at(aim_position)

	## 在同一帧先执行一次矫正，保证 emit() 读取到正确朝向。
	_update_tool_camera_alignment()

	if not held_weapon.has_method("emit"):
		push_warning(
			"[FutureWarriorAI] Weapon has no emit(): %s"
			% held_weapon.name
		)
		return

	var fired := false
	if _is_ai_hitscan_weapon(slot):
		## FutureM4/FutureMPX gameplay is resolved once by the authority ray.
		## The weapon scene only emits a non-gameplay tracer afterwards.
		fired = _fire_ai_hitscan_weapon()
	else:
		## Keep compatibility for any custom weapon assigned to this slot. The
		## built-in FutureM4/FutureMPX paths never reach this branch.
		held_weapon.call("emit")
		fired = true
	if not fired:
		return
	_consume_weapon_round(slot)
	_play_shoot_animation()

	if slot == WeaponSlot.AR15:
		ar15_burst_shots_remaining -= 1

		fire_timer = maxf(
			_get_weapon_cooldown(
				WeaponSlot.AR15,
				ar15_fire_interval
			),
			ar15_fire_interval
		)

		if ar15_burst_shots_remaining <= 0:
			ar15_burst_pause_timer = (
				ar15_burst_pause
			)

	else:
		fire_timer = maxf(
			_get_weapon_cooldown(
				WeaponSlot.SUPPRESSED_PISTOL,
				pistol_fire_interval
			),
			pistol_fire_interval
		)


func _is_ai_hitscan_weapon(slot: int) -> bool:
	if not is_instance_valid(held_weapon):
		return false
	var weapon_id := str(weapon_data.get(slot, {}).get("id", ""))
	if weapon_id.is_empty():
		weapon_id = ar15_tool_id if slot == WeaponSlot.AR15 else suppressed_pistol_tool_id
	## All handheld firearms used by the current Future AI roles resolve their
	## gameplay ray on the authority. Bandit's suppressed pistol used to fall
	## through to the legacy physical-bullet branch, which was neither
	## server-authoritative nor replicated as a multiplayer tracer.
	return weapon_id in ["future_m4", "future_mpx", "suppressed_pistol"] \
		and held_weapon.has_method("get_fire_origin") \
		and held_weapon.has_method("get_fire_direction")


func _fire_ai_hitscan_weapon() -> bool:
	if not is_instance_valid(held_weapon):
		return false
	if not GameAuthority.has_method("server_ai_hitscan"):
		push_warning("[FutureWarriorAI] GameAuthority has no AI hitscan endpoint")
		return false
	if not GameAuthority.is_server_authority() and not GameAuthority.is_local_authority():
		return false
	var weapon_id := str(weapon_data.get(current_weapon_slot, {}).get("id", ""))
	if weapon_id.is_empty():
		weapon_id = ar15_tool_id
	var origin := held_weapon.call("get_fire_origin") as Vector3
	var direction := held_weapon.call("get_fire_direction") as Vector3
	if direction.length_squared() <= 0.001:
		return false
	var result: Dictionary = GameAuthority.server_ai_hitscan(
		self,
		team_id,
		weapon_id,
		origin,
		direction
	)
	if not bool(result.get("ok", false)):
		return false

	## Local single-player has no network event loop to replay the tracer. In
	## listen-server and dedicated-server modes GameAuthority broadcasts the
	## same visual event to the host/clients, so emitting it here would duplicate
	## the host's tracer.
	if GameAuthority.is_local_authority():
		var travel_distance := float(result.get(
			"visual_distance",
			CombatBalance.get_float(weapon_id, "range")
		))
		if held_weapon.has_method("emit_visual_only_tracer"):
			held_weapon.call(
				"emit_visual_only_tracer",
				direction,
				travel_distance
			)
		elif held_weapon.has_method("emit_visual_only"):
			held_weapon.call("emit_visual_only")
	return true


func _get_weapon_cooldown(
	slot: int,
	fallback: float
) -> float:
	var definition: Dictionary = (
		weapon_data.get(slot, {})
	)

	return float(
		definition.get(
			"cooldown",
			fallback
		)
	)


func _get_predicted_aim_position(
	target: CharacterBody3D
) -> Vector3:
	return (
		target.global_position
		+ Vector3.UP * target_height
		+ target.velocity
		* aim_prediction_seconds
	)


func _make_aim_error(
	aim_position: Vector3
) -> Vector3:
	var is_moving := (
		Vector2(
			velocity.x,
			velocity.z
		).length() > 0.4
	)

	var error_amount := (
		moving_aim_error
		if is_moving
		else standing_aim_error
	)

	var distance_scale := clampf(
		global_position.distance_to(
			aim_position
		) / 15.0,
		0.6,
		1.8
	)

	return Vector3(
		rng.randf_range(-1.0, 1.0),
		rng.randf_range(-0.6, 0.6),
		rng.randf_range(-1.0, 1.0)
	) * error_amount * distance_scale


func _aim_at(
	world_target: Vector3
) -> void:
	if (
		world_target.distance_squared_to(
			global_position
		) < 0.001
	):
		return

	upper_body_look_target.global_position = (
		world_target
	)

	var aim_origin := head.global_position
	_weapon_aim_position = world_target
	_weapon_aim_active = true

	aim_ray.global_position = aim_origin
	look_at_target.global_position = aim_origin

	## 只旋转瞄准参考节点。
	## ToolPivot 的旋转由 _update_tool_camera_alignment() 计算。
	aim_ray.look_at(
		world_target,
		Vector3.UP
	)
	look_at_target.look_at(
		world_target,
		Vector3.UP
	)

	aim_ray.target_position = Vector3(
		0.0,
		0.0,
		-100.0
	)
	look_at_target.target_position = Vector3(
		0.0,
		0.0,
		-100.0
	)

	aim_ray.force_raycast_update()
	look_at_target.force_raycast_update()
	_weapon_aim_direction = -aim_ray.global_transform.basis.z.normalized()


# ------------------------------------------------------------------
# Grenade
# ------------------------------------------------------------------

func _try_throw_grenade(
	distance: float
) -> void:
	## 手雷规避或安全等待期间不再发起新的投掷，但不影响主武器射击。
	if _grenade_avoidance_active or _has_nearby_grenade_threat():
		return
	if grenades_remaining <= 0:
		engagement_grenade_pending = false
		return
	if not engagement_grenade_pending:
		return

	if grenade_timer > 0.0:
		return

	if (
		distance < grenade_min_range
		or distance > grenade_max_range
	):
		return

	if not _is_valid_target(target_player):
		return

	if not _has_clear_line_to(target_player):
		return

	var target_position := (
		target_player.global_position
		+ target_player.velocity * 0.30
	)

	if _would_grenade_hurt_friend(
		target_position
	):
		return

	var previous_count := grenades_remaining
	_throw_grenade(target_position)
	if grenades_remaining < previous_count:
		## 一次交火只安排一枚；锁定新的攻击目标时才会再次安排。
		engagement_grenade_pending = false


func _throw_grenade(
	target_position: Vector3
) -> void:
	## AI 手雷优先进入玩家使用的 GameAuthority 权威投射物系统；这样本地、ENet、
	## Steam 都使用同一套飞行、爆炸伤害与视觉同步，而不是只生成一个本地模型。
	if _throw_grenade_authoritatively(target_position):
		_complete_grenade_throw()
		return

	var packed_scene := (
		grenade_data.get("scene")
		as PackedScene
	)

	if packed_scene == null:
		push_warning(
			"[FutureWarriorAI] Grenade scene is unavailable."
		)
		grenade_timer = grenade_cooldown
		return

	var grenade_instance := (
		packed_scene.instantiate()
		as Node3D
	)

	if grenade_instance == null:
		return

	var resolved_mode := grenade_mode

	if resolved_mode == GrenadeMode.AUTO:
		if _looks_like_projectile_grenade(
			grenade_instance
		):
			resolved_mode = GrenadeMode.PROJECTILE

		elif grenade_instance.has_method("emit"):
			resolved_mode = GrenadeMode.TOOL

		else:
			resolved_mode = GrenadeMode.PROJECTILE

	var launched := false

	match resolved_mode:
		GrenadeMode.TOOL:
			launched = _throw_grenade_as_tool(
				grenade_instance,
				target_position
			)

		GrenadeMode.PROJECTILE:
			launched = _throw_grenade_as_projectile(
				grenade_instance,
				target_position
			)

	if not launched:
		if is_instance_valid(grenade_instance):
			grenade_instance.queue_free()

		grenade_timer = 0.8
		return

	_complete_grenade_throw()


func _complete_grenade_throw() -> void:
	grenades_remaining = maxi(0, grenades_remaining - 1)
	grenade_timer = maxf(
		grenade_cooldown,
		float(
			grenade_data.get(
				"cooldown",
				grenade_cooldown
			)
		)
	)

	_play_grenade_animation()
	_update_health_label()

	_debug(
		"grenade remaining=%d"
		% grenades_remaining
	)


func _throw_grenade_authoritatively(target_position: Vector3) -> bool:
	if not GameAuthority.has_method("spawn_ai_grenade"):
		return false
	if not GameAuthority.is_server_authority() and not GameAuthority.is_local_authority():
		return false
	var forward := -global_transform.basis.z
	var spawn_position := (
		global_position
		+ Vector3.UP * grenade_spawn_height
		+ forward * grenade_forward_offset
	)
	var initial_velocity := _calculate_grenade_velocity(
		spawn_position,
		target_position,
		grenade_flight_time,
		CombatBalance.get_float("grenade", "gravity")
	)
	return bool(GameAuthority.spawn_ai_grenade(
		spawn_position,
		initial_velocity,
		team_id,
		get_instance_id()
	))


func _looks_like_projectile_grenade(
	grenade_instance: Node3D
) -> bool:
	if grenade_instance is RigidBody3D:
		return true

	if (
		not String(grenade_launch_method).is_empty()
		and grenade_instance.has_method(
			grenade_launch_method
		)
	):
		return true

	return (
		_has_property(
			grenade_instance,
			"velocity"
		)
		or _has_property(
			grenade_instance,
			"linear_velocity"
		)
	)


func _throw_grenade_as_tool(
	grenade_tool: Node3D,
	target_position: Vector3
) -> bool:
	if not grenade_tool.has_method("emit"):
		return false

	## 暂时收起枪支。
	if is_instance_valid(held_weapon):
		held_weapon.visible = false

	tool_pivot.add_child(grenade_tool)

	grenade_tool.position = grenade_data.get(
		"grip_position",
		Vector3.ZERO
	)
	grenade_tool.rotation_degrees = grenade_data.get(
		"grip_rotation",
		Vector3.ZERO
	)
	grenade_tool.scale = grenade_data.get(
		"grip_scale",
		Vector3.ONE
	)

	_set_optional_property(
		grenade_tool,
		"tool_owner",
		team_id
	)
	_set_optional_property(
		grenade_tool,
		"team",
		team_id
	)
	_set_optional_property(
		grenade_tool,
		"team_id",
		team_id
	)
	_set_optional_property(
		grenade_tool,
		"owner_team",
		team_id
	)

	_aim_at(target_position)

	## 手雷工具也使用与玩家相同的枪口/射线轴向矫正。
	var previous_weapon := held_weapon
	held_weapon = grenade_tool
	_update_tool_camera_alignment()

	grenade_tool.call("emit")

	held_weapon = previous_weapon

	grenade_tool.queue_free()

	if is_instance_valid(held_weapon):
		held_weapon.visible = true

	call_deferred(
		"_update_tool_camera_alignment"
	)

	return true


func _throw_grenade_as_projectile(
	grenade_projectile: Node3D,
	target_position: Vector3
) -> bool:
	var scene_root := get_tree().current_scene

	if scene_root == null:
		scene_root = get_tree().root

	scene_root.add_child(
		grenade_projectile
	)

	var forward := (
		-global_transform.basis.z
	)

	var spawn_position := (
		global_position
		+ Vector3.UP * grenade_spawn_height
		+ forward * grenade_forward_offset
	)

	grenade_projectile.global_position = (
		spawn_position
	)

	_set_optional_property(
		grenade_projectile,
		"tool_owner",
		team_id
	)
	_set_optional_property(
		grenade_projectile,
		"team",
		team_id
	)
	_set_optional_property(
		grenade_projectile,
		"team_id",
		team_id
	)
	_set_optional_property(
		grenade_projectile,
		"owner_team",
		team_id
	)

	var initial_velocity := (
		_calculate_grenade_velocity(
			spawn_position,
			target_position,
			grenade_flight_time
		)
	)

	if (
		not String(grenade_launch_method).is_empty()
		and grenade_projectile.has_method(
			grenade_launch_method
		)
	):
		grenade_projectile.call(
			grenade_launch_method,
			initial_velocity,
			team_id
		)
		return true

	if grenade_projectile is RigidBody3D:
		var rigid_grenade := (
			grenade_projectile
			as RigidBody3D
		)

		rigid_grenade.linear_velocity = (
			initial_velocity
		)
		return true

	if _has_property(
		grenade_projectile,
		"velocity"
	):
		grenade_projectile.set(
			"velocity",
			initial_velocity
		)
		return true

	if _has_property(
		grenade_projectile,
		"linear_velocity"
	):
		grenade_projectile.set(
			"linear_velocity",
			initial_velocity
		)
		return true

	push_warning(
		"[FutureWarriorAI] Grenade projectile must be RigidBody3D, "
		+ "have velocity, or implement launch(Vector3, String)."
	)

	return false


func _has_nearby_grenade_threat() -> bool:
	## 这是投掷前的即时安全闸门。正常物理帧已经在
	## _update_grenade_avoidance() 中查询过一次；保留这里的独立检查，
	## 也能覆盖测试脚本或其他角色直接调用 _try_throw_grenade() 的情况。
	if not GameAuthority.has_method("get_grenade_threat_for_ai"):
		return false
	return not GameAuthority.get_grenade_threat_for_ai(self).is_empty()


func _calculate_grenade_velocity(
	origin: Vector3,
	target: Vector3,
	flight_time: float,
	gravity_override: float = -1.0
) -> Vector3:
	var safe_time := maxf(
		flight_time,
		0.25
	)

	var displacement := target - origin

	var gravity := gravity_override if gravity_override >= 0.0 else float(
		ProjectSettings.get_setting(
			"physics/3d/default_gravity",
			9.8
		)
	)

	var result := displacement / safe_time

	result.y = (
		displacement.y
		+ 0.5
		* gravity
		* safe_time
		* safe_time
	) / safe_time

	return result


func _would_grenade_hurt_friend(
	target_position: Vector3
) -> bool:
	var checked: Dictionary = {}
	var safety_radius := maxf(
		grenade_friendly_safety_radius,
		CombatBalance.get_float("grenade", "damage_radius")
	)

	var candidate_groups := _authoritative_human_player_groups()
	candidate_groups.append_array([&"combat_characters", &"future_warrior_ai"])
	for group_name in candidate_groups:
		for node in get_tree().get_nodes_in_group(
			group_name
		):
			if not node is Node3D:
				continue

			var character := node as Node3D
			var instance_id := character.get_instance_id()

			if checked.has(instance_id):
				continue

			checked[instance_id] = true

			if (
				_get_combat_team(character)
				!= team_id
			):
				continue

			if (
				character.global_position.distance_to(
					target_position
				)
				< safety_radius
			):
				return true

	## 自身不一定会出现在所有地图测试场景的角色 group 中，单独检查一次。
	if global_position.distance_to(target_position) < safety_radius:
		return true

	return false


func _update_grenade_avoidance(delta: float) -> void:
	var threat: Dictionary = {}
	if GameAuthority.has_method("get_grenade_threat_for_ai"):
		threat = GameAuthority.get_grenade_threat_for_ai(self)

	if threat.is_empty():
		if not _grenade_avoidance_active:
			return
		var distance_to_last_center := INF
		if _grenade_avoidance_center.is_finite():
			distance_to_last_center = global_position.distance_to(
				_grenade_avoidance_center
			)
		var safe_distance := _grenade_avoidance_radius + grenade_avoidance_safe_margin
		if distance_to_last_center < safe_distance:
			_grenade_avoidance_safe_elapsed = 0.0
		else:
			_grenade_avoidance_safe_elapsed += delta
		_grenade_avoidance_repath_timer = maxf(
			0.0,
			_grenade_avoidance_repath_timer - delta
		)
		if _grenade_avoidance_repath_timer <= 0.0 \
				and distance_to_last_center < safe_distance:
			_refresh_grenade_avoidance_direction()
		if _grenade_avoidance_safe_elapsed >= grenade_avoidance_resume_delay:
			_finish_grenade_avoidance()
		return

	var center_value: Variant = threat.get("explosion_position", threat.get("position", INVALID_POSITION))
	if not center_value is Vector3:
		return
	var center := center_value as Vector3
	var radius := maxf(0.1, float(threat.get("radius", 0.1)))
	var distance_to_center := global_position.distance_to(center)
	var safe_distance := radius + grenade_avoidance_safe_margin
	## 已经完成 5 秒安全保持后，仍在触发缓冲区但已经离开安全距离时，
	## 不重复进入规避；若手雷再次靠近安全距离，下一帧会重新触发。
	if not _grenade_avoidance_active and distance_to_center >= safe_distance:
		return

	if not _grenade_avoidance_active:
		_grenade_avoidance_active = true
		_grenade_avoidance_safe_elapsed = 0.0
		_grenade_avoidance_repath_timer = 0.0
		_debug(
			"grenade evade start position=%s radius=%.1fm"
			% [
				_format_position(center),
				radius,
			]
		)

	_grenade_avoidance_center = center
	_grenade_avoidance_radius = radius
	if distance_to_center < safe_distance:
		_grenade_avoidance_safe_elapsed = 0.0
	else:
		_grenade_avoidance_safe_elapsed += delta
	_grenade_avoidance_repath_timer = maxf(
		0.0,
		_grenade_avoidance_repath_timer - delta
	)
	if _grenade_avoidance_repath_timer <= 0.0 \
			or _grenade_avoidance_direction.length_squared() <= 0.001:
		_refresh_grenade_avoidance_direction()
	if _grenade_avoidance_safe_elapsed >= grenade_avoidance_resume_delay:
		_finish_grenade_avoidance()


func _finish_grenade_avoidance() -> void:
	if _grenade_avoidance_active:
		_debug(
			"grenade evade end position=%s safe_hold=%.1fs"
			% [
				_format_position(global_position),
				_grenade_avoidance_safe_elapsed,
			]
		)
	_grenade_avoidance_active = false
	_grenade_avoidance_safe_elapsed = 0.0
	_grenade_avoidance_repath_timer = 0.0
	_grenade_avoidance_center = INVALID_POSITION
	_grenade_avoidance_radius = 0.0
	_grenade_avoidance_direction = Vector3.ZERO
	_reset_navigation_path()


func _is_grenade_avoidance_active() -> bool:
	return _grenade_avoidance_active


func _maintain_combat_during_grenade_avoidance() -> void:
	## 规避和安全保持都不能让 AI 进入“只等待、不攻击”的状态。
	## 这里不投掷手雷，但继续沿用子类可能覆盖的开火/换弹逻辑。
	if not _is_valid_target(target_player):
		return
	var distance := _horizontal_distance(global_position, target_player.global_position)
	if not _has_clear_line_to(target_player):
		return
	_aim_at(_get_predicted_aim_position(target_player))
	_try_fire_at_target(distance)


func _refresh_grenade_avoidance_direction() -> void:
	if not _grenade_avoidance_center.is_finite():
		return
	var away := _horizontal_direction(
		_grenade_avoidance_center,
		global_position
	)
	if away.length_squared() <= 0.001:
		away = -global_transform.basis.z
	if away.length_squared() <= 0.001:
		away = Vector3.FORWARD
	away = away.normalized()

	var side_sign := 1.0 if get_instance_id() % 2 == 0 else -1.0
	var candidates: Array[Vector3] = [
		away,
		away.rotated(Vector3.UP, side_sign * PI * 0.25),
		away.rotated(Vector3.UP, -side_sign * PI * 0.25),
		away.rotated(Vector3.UP, side_sign * PI * 0.5),
		away.rotated(Vector3.UP, -side_sign * PI * 0.5),
		away.rotated(Vector3.UP, PI),
	]
	var best_direction := away
	var best_score := -INF
	var escape_distance := maxf(
		3.0,
		_grenade_avoidance_radius + grenade_avoidance_safe_margin
	)
	for candidate in candidates:
		var open_direction := _find_open_movement_direction(candidate, 1.15)
		if _movement_direction_is_blocked(open_direction, 0.9):
			continue
		var route_direction := open_direction
		if _navigation_map_is_ready() and navigation_agent != null:
			var escape_goal := global_position + open_direction * escape_distance
			navigation_agent.target_position = escape_goal
			navigation_refresh_timer = navigation_refresh_interval
			var next_position := navigation_agent.get_next_path_position()
			var navigation_direction := _horizontal_direction(
				global_position,
				next_position
			)
			if navigation_direction.length_squared() > 0.001:
				route_direction = _find_open_movement_direction(
					navigation_direction,
					1.15
				)
		var score := route_direction.dot(away)
		if not WaterBody3D.is_navigation_blocked(
			global_position + route_direction * 1.5
		):
			score += 0.25
		if score > best_score:
			best_score = score
			best_direction = route_direction.normalized()

	_grenade_avoidance_direction = best_direction.normalized()
	_grenade_avoidance_repath_timer = maxf(
		0.05,
		grenade_avoidance_repath_interval
	)


func _apply_grenade_avoidance_direction(direction: Vector3) -> Vector3:
	if not _grenade_avoidance_active \
			or _grenade_avoidance_direction.length_squared() <= 0.001:
		return direction
	var hazard_direction := _grenade_avoidance_direction.normalized()
	var additional_hazard_direction := _get_additional_movement_hazard_direction()
	if additional_hazard_direction.length_squared() > 0.001:
		## FutureEngineer 在已放置炸弹的撤退阶段会通过这个虚拟接口
		## 提供第二个“远离中心”，因此规避手雷时不会反向走回自己的炸弹。
		var combined_hazard := (
			hazard_direction + additional_hazard_direction.normalized()
		)
		if combined_hazard.length_squared() > 0.001:
			hazard_direction = combined_hazard.normalized()
		else:
			## 两个危险源正好位于相反方向时，选择切向方向，
			## 避免把其中一个危险源重新作为前进方向。
			hazard_direction = hazard_direction.cross(Vector3.UP).normalized()
			if hazard_direction.length_squared() <= 0.001:
				hazard_direction = Vector3.RIGHT
	var requested := direction
	requested.y = 0.0
	if requested.length_squared() <= 0.001:
		return hazard_direction
	requested = requested.normalized()

	## 如果原行为方向正朝向手雷，先去掉朝向爆炸中心的分量，再叠加规避方向。
	if _grenade_avoidance_center.is_finite():
		var toward_center := _horizontal_direction(
			global_position,
			_grenade_avoidance_center
		)
		var toward_amount := requested.dot(toward_center)
		if toward_amount > 0.0:
			requested = (requested - toward_center * toward_amount).normalized()
			if requested.length_squared() <= 0.001:
				requested = hazard_direction

	var hazard_weight := 0.78 if _grenade_avoidance_safe_elapsed <= 0.0 else 0.35
	var combined := (
		requested * (1.0 - hazard_weight)
		+ hazard_direction * hazard_weight
	).normalized()
	if combined.length_squared() <= 0.001:
		combined = hazard_direction
	return _find_open_movement_direction(combined, 1.0)


## 子类可以提供额外的移动危险源方向。普通 FutureWarrior 没有第二个危险源。
func _get_additional_movement_hazard_direction() -> Vector3:
	return Vector3.ZERO


# ------------------------------------------------------------------
# Navigation and movement
# ------------------------------------------------------------------

func _on_navigation_velocity_computed(safe_velocity: Vector3) -> void:
	## NavigationServer 在物理步之间返回 RVO 安全速度；下一次移动时消费。
	_avoidance_safe_velocity = safe_velocity
	_avoidance_safe_velocity_valid = true


func _reset_navigation_path() -> void:
	navigation_refresh_timer = 0.0
	_avoidance_safe_velocity = Vector3.ZERO
	_avoidance_safe_velocity_valid = false
	if navigation_agent == null:
		return
	## target_position 的 setter 会清除当前内部路径；下一次 _direction_to_goal
	## 会用真实 target/入口重新设置目标。
	navigation_agent.target_position = global_position


func _direction_to_goal(
	goal: Vector3
) -> Vector3:
	_navigation_using_direct_fallback = false
	if goal == INVALID_POSITION:
		return Vector3.ZERO

	var direct_direction := (
		_horizontal_direction(
			global_position,
			goal
		)
	)

	if (
		not use_navigation_agent
		or navigation_agent == null
	):
		_navigation_using_direct_fallback = true
		return direct_direction

	## 已配置导航但地图还没有 ready 时，Squad AI 先等待导航，不直接穿过
	## 墙体。没有 Squad 的旧式 AI 才保留直线兜底，避免影响未接入小队的角色。
	if not _navigation_map_is_ready():
		if not is_instance_valid(squad):
			_navigation_using_direct_fallback = true
			return direct_direction
		return Vector3.ZERO

	if navigation_refresh_timer <= 0.0:
		navigation_agent.target_position = goal
		navigation_refresh_timer = (
			navigation_refresh_interval
		)

	var next_position := (
		navigation_agent.get_next_path_position()
	)

	var navigation_direction := (
		_horizontal_direction(
			global_position,
			next_position
		)
	)

	if navigation_direction.length_squared() > 0.001:
		return navigation_direction

	## 导航地图有效但当前路径没有下一点：普通 Squad AI 先保持原地，
	## 让卡住检测确认并刷新路径；只有确认卡住、且给导航一次重试窗口
	## 仍然没有路径后，才允许直线兜底。
	if is_instance_valid(squad) \
			and (not _squad_stuck or _squad_navigation_retry_timer > 0.0):
		return Vector3.ZERO
	_navigation_using_direct_fallback = true
	return direct_direction


func _navigation_map_is_ready() -> bool:
	if navigation_agent == null:
		return false

	var navigation_map := (
		navigation_agent.get_navigation_map()
	)

	if not navigation_map.is_valid():
		return false

	return (
		NavigationServer3D.map_get_iteration_id(
			navigation_map
		) > 0
	)


func is_squad_navigation_stuck() -> bool:
	return _squad_stuck


func notify_navigation_chunks_rebuilt(_chunk_ids: Array) -> void:
	## DynamicNavigationChunkGrid 在权威端替换局部导航网格后调用。
	## 先清除旧路径；已经卡住的 AI 保留卡住标记，但重新获得一次导航
	## 尝试，仍无位移时再执行固定方向脱困。
	if state == AIState.DEAD:
		return
	var was_stuck := _squad_stuck
	_reset_navigation_path()
	if _squad_stuck:
		_squad_stuck_elapsed = 0.0
		_squad_progress_window_elapsed = 0.0
		_squad_progress_anchor = global_position
		_squad_navigation_retry_timer = maxf(
			0.75,
			navigation_refresh_interval * 3.0
		)
		_debug(
			"navigation chunks rebuilt while stuck; retry target navigation chunks=%s"
			% [_chunk_ids]
		)
	else:
		_debug("navigation chunks rebuilt; target path refreshed chunks=%s" % [_chunk_ids])
	_update_health_label()
	## 测试场景可订阅这个本地信号，把区块重建后的实际路径刷新显示到调试面板。
	navigation_path_refreshed.emit(_chunk_ids.duplicate(), was_stuck)


func _avoid_immediate_obstacle(
	direction: Vector3
) -> Vector3:
	if direction == Vector3.ZERO:
		return direction

	if not front_probe.is_colliding():
		return direction

	var left_blocked := left_probe.is_colliding()
	var right_blocked := right_probe.is_colliding()

	var side := global_transform.basis.x

	if left_blocked and not right_blocked:
		side = global_transform.basis.x

	elif right_blocked and not left_blocked:
		side = -global_transform.basis.x

	elif rng.randf() < 0.5:
		side = -side

	_try_jump_over_obstacle()

	return (
		direction * 0.30
		+ side * 0.70
	).normalized()


## 对脱困/爆炸撤退方向做一次实际碰撞预检。RayCast 的朝向可能还停留在
## 上一帧，test_move 能直接验证 CharacterBody3D 当前变换前方是否可走。
func _movement_direction_is_blocked(direction: Vector3, distance := 1.25) -> bool:
	var horizontal := direction
	horizontal.y = 0.0
	if horizontal.length_squared() <= 0.001:
		return true
	return test_move(
		global_transform,
		horizontal.normalized() * maxf(0.25, distance)
	)


func _find_open_movement_direction(preferred: Vector3, distance := 1.25) -> Vector3:
	var base := preferred
	base.y = 0.0
	if base.length_squared() <= 0.001:
		base = -global_transform.basis.z
	if base.length_squared() <= 0.001:
		base = Vector3.FORWARD
	base = base.normalized()
	var candidates: Array[Vector3] = [
		base,
		base.rotated(Vector3.UP, PI * 0.5),
		base.rotated(Vector3.UP, -PI * 0.5),
		base.rotated(Vector3.UP, PI * 0.25),
		base.rotated(Vector3.UP, -PI * 0.25),
		base.rotated(Vector3.UP, PI),
	]
	for candidate in candidates:
		if not _movement_direction_is_blocked(candidate, distance):
			return candidate.normalized()
	return base


func _try_jump_over_obstacle() -> void:
	if not is_on_floor():
		return

	if jump_timer > 0.0:
		return

	velocity.y = jump_velocity
	jump_timer = jump_cooldown

	_play_body_animation(
		&"JumpStart",
		0.05
	)


func _apply_character_movement(
	direction: Vector3,
	speed: float,
	delta: float,
	use_navigation_avoidance: bool = true,
	preserve_direction: bool = false
) -> void:
	var previous_position := global_position
	if _grenade_avoidance_active:
		direction = _apply_grenade_avoidance_direction(direction)
		## 安全保持阶段也必须实际离开危险区；即使原状态本帧要求
		## 悬停/等待，也使用现有的逃离速度移动，而不是把 velocity 清零。
		if direction.length_squared() > 0.001:
			speed = maxf(speed, flee_speed)
	if not preserve_direction:
		direction = _apply_squad_soft_separation(direction)
	speed *= GameAuthority.get_chain_link_fence_speed_multiplier(
		global_position,
		team_id,
		"ai"
	)
	var horizontal_step := direction * speed + rubber_knockback
	var proposed := global_position + Vector3(horizontal_step.x, 0.0, horizontal_step.z) * delta
	if WaterBody3D.is_navigation_blocked(proposed):
		# Water is a hard navigation boundary for enemy AI.
		direction = Vector3.ZERO
		rubber_knockback.x = 0.0
		rubber_knockback.z = 0.0
	var desired_velocity := (
		direction * speed
		+ rubber_knockback
	)
	var movement_velocity := desired_velocity
	## 手雷规避期间即使原状态为了炸弹撤退而请求 bypass，也不能关闭
	## NavigationAgent3D 的 avoidance_enabled；RVO 和下方的 test_move/RayCast
	## 共同选择可行的离开方向。
	if (use_navigation_avoidance or _grenade_avoidance_active) \
			and _navigation_avoidance_is_active():
		## RVO 只计算期望速度；实际安全速度由 velocity_computed 回调返回。
		navigation_agent.set_velocity(
			Vector3(desired_velocity.x, 0.0, desired_velocity.z)
		)
		if _avoidance_safe_velocity_valid:
			movement_velocity.x = _avoidance_safe_velocity.x
			movement_velocity.z = _avoidance_safe_velocity.z
			## 某些拥挤/贴墙场景中 RVO 会返回接近零的安全速度，
			## 让角色看起来原地跳跃。角色专属 AI 可选择使用自己的
			## test_move 方向作为最低限度的移动兜底，avoidance_enabled
			## 仍然保持开启并且每帧仍会提交 set_velocity。
			if _should_force_flee_motion_when_avoidance_stalls() \
					and state == AIState.FLEE:
				var requested_speed := Vector2(
					desired_velocity.x,
					desired_velocity.z
				).length()
				var safe_speed := Vector2(
					movement_velocity.x,
					movement_velocity.z
				).length()
				if requested_speed > 0.25 \
						and safe_speed < maxf(0.35, requested_speed * 0.20):
					var flee_fallback := _find_open_movement_direction(
						direction,
						0.75
					)
					movement_velocity.x = flee_fallback.x * speed + rubber_knockback.x
					movement_velocity.z = flee_fallback.z * speed + rubber_knockback.z
		_avoidance_safe_velocity_valid = false
	else:
		_avoidance_safe_velocity_valid = false

	rubber_knockback = (
		rubber_knockback.move_toward(
			Vector3.ZERO,
			18.0 * delta
		)
	)

	velocity.x = move_toward(
		velocity.x,
		movement_velocity.x,
		acceleration * delta
	)

	velocity.z = move_toward(
		velocity.z,
		movement_velocity.z,
		acceleration * delta
	)

	if not is_on_floor():
		velocity += get_gravity() * delta

	elif velocity.y < 0.0:
		velocity.y = 0.0

	var facing_direction := direction

	## 搜索阶段沿路线移动，同时左右扫视而不是始终朝着目的地。
	if state == AIState.SEARCH and search_look_direction.length_squared() > 0.001:
		facing_direction = search_look_direction

	## 交战和撤退时允许侧移/后退，但身体继续面向玩家。
	if (
		_is_valid_target(target_player)
		and state in [
			AIState.COMBAT,
			AIState.FLEE,
		]
	):
		facing_direction = (
			_horizontal_direction(
				global_position,
				target_player.global_position
			)
		)

	_rotate_toward_direction(
		facing_direction,
		delta
	)

	move_and_slide()

	var actual_horizontal_velocity := (
		(global_position - previous_position) / maxf(delta, 0.0001)
	)
	actual_horizontal_velocity.y = 0.0
	_update_character_animation(
		direction,
		actual_horizontal_velocity
	)
	_update_squad_stuck_tracking(previous_position, direction, speed, delta)


func _navigation_avoidance_is_active() -> bool:
	return (
		navigation_avoidance_enabled
		and use_navigation_agent
		and navigation_agent != null
		and navigation_agent.avoidance_enabled
		and _navigation_map_is_ready()
	)


## 角色可以覆盖这个钩子，处理 RVO 在 FLEE 期间把安全速度压成零的情况。
## 普通 FutureWarrior / FutureEngineer 保持原有的严格 RVO 结果。
func _should_force_flee_motion_when_avoidance_stalls() -> bool:
	return false


## Engineer 可以覆盖此钩子，在安装/撤退炸药等关键阶段不进入普通卡住计时。
func _squad_stuck_tracking_allowed() -> bool:
	return true


## 困住判定完成后统一先重置 NavigationAgent3D 路径；子类只能在这个
## 已重试导航的时点追加角色专属动作，不能跳过后续固定方向脱困流程。
func _on_squad_stuck_detected(_goal: Vector3) -> void:
	return


## FutureEngineer 在自己已放置 RemoteBomb 后必须优先完成自身安全撤退；
## 其他成员的爆破警告会暂存，不能打断这条最高优先级状态。
func _squad_warning_can_override_role_behavior() -> bool:
	return true


func _squad_stuck_goal_for_state() -> Vector3:
	match state:
		AIState.SEARCH:
			if farm_patrol_position.is_finite():
				return farm_patrol_position
			if enemy_farm_position.is_finite():
				return enemy_farm_position
			if is_instance_valid(target):
				return target.global_position
		AIState.CHASE:
			if _is_valid_target(target_player):
				return target_player.global_position
			if last_known_target_position.is_finite():
				return last_known_target_position
		AIState.FLEE:
			return flee_target
	return INVALID_POSITION


func _reset_squad_progress_window(goal: Vector3 = INVALID_POSITION) -> void:
	_squad_progress_window_elapsed = 0.0
	_squad_progress_anchor = global_position
	_squad_tracking_goal = goal
	_squad_window_travel_distance = 0.0
	_squad_blocked_elapsed = 0.0


func _squad_frame_has_blocking_collision(
	previous_position: Vector3,
	direction: Vector3,
	speed: float,
	delta: float
) -> bool:
	var intended_direction := direction
	intended_direction.y = 0.0
	var actual_motion := global_position - previous_position
	actual_motion.y = 0.0
	var actual_distance := actual_motion.length()
	var expected_distance := maxf(0.0, speed) * maxf(0.0, delta)

	## 没有明显实际位移时先记为本帧疑似阻挡；完整窗口会过滤单帧抖动。
	if intended_direction.length_squared() > 0.001 \
			and expected_distance > 0.12 \
			and actual_distance < maxf(0.025, expected_distance * 0.18):
		return true

	## 通过 move_and_slide 的碰撞法线区分“沿墙移动”和“命令方向撞墙”。
	## 地面法线被忽略，只检查水平墙体、空气墙和建筑碰撞。
	if intended_direction.length_squared() > 0.001:
		intended_direction = intended_direction.normalized()
		for collision_index in range(get_slide_collision_count()):
			var collision := get_slide_collision(collision_index)
			if collision == null:
				continue
			var normal := collision.get_normal()
			normal.y = 0.0
			if normal.length_squared() <= 0.01:
				continue
			if intended_direction.dot(normal.normalized()) < -0.25:
				return true

	return false


func _update_squad_stuck_tracking(
	previous_position: Vector3,
	direction: Vector3,
	speed: float,
	delta: float
) -> void:
	var trackable_state := state in [
		AIState.SEARCH,
		AIState.CHASE,
		AIState.FLEE,
	]
	if (
		not is_instance_valid(squad)
		or not _squad_stuck_tracking_allowed()
		or not trackable_state
		or _squad_escape_waypoint != INVALID_POSITION
	):
		_reset_squad_stuck_tracking()
		return
	## 导航网格仍在初始化时是“等待导航”，不是被障碍卡住；避免把
	## 初始 bake 的等待错误显示成困住。
	if use_navigation_agent and navigation_agent != null \
			and not _navigation_map_is_ready():
		_reset_squad_stuck_tracking()
		return

	var goal := _squad_stuck_goal_for_state()
	if not goal.is_finite():
		_reset_squad_stuck_tracking()
		return

	## SEARCH 在战略 target 附近本来就可能没有移动意图。到达战略
	## target 或当前 patrol waypoint 时，不把正常停留误判成卡住。
	if state == AIState.SEARCH:
		if not is_instance_valid(target) \
				or _horizontal_distance(global_position, target.global_position) <= 2.5:
			_reset_squad_stuck_tracking()
			return

	if _horizontal_distance(global_position, goal) <= 1.2:
		_reset_squad_stuck_tracking()
		return

	## patrol 点、追击目标或 FLEE 目标改变时开启新的窗口。
	if not _squad_tracking_goal.is_finite() \
			or _horizontal_distance(_squad_tracking_goal, goal) > 1.25:
		_reset_squad_progress_window(goal)

	_squad_progress_window_elapsed += delta
	_squad_window_travel_distance += _horizontal_distance(
		previous_position,
		global_position
	)
	var start_goal_distance := _horizontal_distance(
		_squad_progress_anchor,
		_squad_tracking_goal
	)
	var current_goal_distance := _horizontal_distance(
		global_position,
		goal
	)
	var goal_progress := start_goal_distance - current_goal_distance
	var net_window_displacement := _horizontal_distance(
		_squad_progress_anchor,
		global_position
	)
	var blocked_this_frame := _squad_frame_has_blocking_collision(
		previous_position,
		direction,
		speed,
		delta
	)
	if blocked_this_frame:
		_squad_blocked_elapsed += delta
	else:
		## 轻微衰减而不是立即清零，避免碰撞法线在相邻帧抖动时漏掉墙边卡住。
		_squad_blocked_elapsed = maxf(
			0.0,
			_squad_blocked_elapsed - delta * 0.5
		)

	var effective_goal_progress := squad_stuck_min_goal_progress
	if effective_goal_progress <= 0.05:
		effective_goal_progress = squad_stuck_min_progress
	effective_goal_progress = maxf(0.05, effective_goal_progress)
	var navigation_is_making_progress := (
		not _squad_stuck
		or not _navigation_using_direct_fallback
	)
	if goal_progress >= effective_goal_progress and navigation_is_making_progress:
		_reset_squad_progress_window(goal)
		if _squad_stuck:
			_squad_stuck = false
			_squad_stuck_elapsed = 0.0
			_debug("squad stuck state cleared by goal progress=%.1fm" % goal_progress)
		return

	var elapsed := _squad_progress_window_elapsed
	var expected_motion := maxf(0.0, speed) * elapsed
	var minimum_motion := maxf(
		squad_stuck_min_actual_motion,
		expected_motion * 0.2
	)
	var insufficient_motion := _squad_window_travel_distance < minimum_motion
	var oscillating := (
		_squad_window_travel_distance >= maxf(1.0, minimum_motion * 2.0)
		and net_window_displacement
			<= maxf(0.8, _squad_window_travel_distance * squad_stuck_oscillation_ratio)
		and goal_progress < effective_goal_progress
	)
	var command_direction := direction
	command_direction.y = 0.0
	var actual_direction := global_position - previous_position
	actual_direction.y = 0.0
	var command_alignment := 0.0
	if command_direction.length_squared() > 0.001 \
			and actual_direction.length_squared() > 0.001:
		command_alignment = command_direction.normalized().dot(
			actual_direction.normalized()
		)
	var goal_alignment := 0.0
	var goal_direction := _horizontal_direction(global_position, goal)
	if goal_direction.length_squared() > 0.001 \
			and actual_direction.length_squared() > 0.001:
		goal_alignment = goal_direction.dot(actual_direction.normalized())
	var moving_sideways_without_goal_progress := (
		_squad_window_travel_distance >= minimum_motion
		and command_alignment < 0.1
		and goal_progress < effective_goal_progress
	)
	var moving_without_goal_alignment := (
		_squad_window_travel_distance >= minimum_motion
		and goal_alignment < 0.15
		and goal_progress < effective_goal_progress
	)
	var progress_efficiency := goal_progress / maxf(
		0.05,
		_squad_window_travel_distance
	)
	var inefficient_goal_progress := (
		_squad_window_travel_distance >= minimum_motion
		and progress_efficiency < 0.15
		and goal_progress < effective_goal_progress
	)
	var no_goal_progress := goal_progress < effective_goal_progress
	var collision_confirmed := _squad_blocked_elapsed >= maxf(
		0.05,
		squad_stuck_blocked_seconds
	)
	var confirmation_window := squad_stuck_detection_seconds
	if collision_confirmed:
		## 持续撞墙时不必完整等待 2 秒，但保留至少 0.75 秒的抗抖窗口。
		confirmation_window = minf(confirmation_window, 0.75)

	if not _squad_stuck:
		if elapsed < confirmation_window:
			return
		var stuck_evidence := (
			collision_confirmed
			or insufficient_motion
			or oscillating
			or moving_sideways_without_goal_progress
			or moving_without_goal_alignment
			or inefficient_goal_progress
		)
		if not no_goal_progress or not stuck_evidence:
			return
		_squad_stuck = true
		_squad_stuck_elapsed = 0.0
		var detected_travel := _squad_window_travel_distance
		var detected_blocked := _squad_blocked_elapsed
		_reset_squad_progress_window(goal)
		## 卡住的第一步是重新请求当前行为目标的导航路径；只有这次
		## 导航重试仍无有效下一点，才会在 _direction_to_goal 中使用直线兜底。
		_reset_navigation_path()
		_squad_navigation_retry_timer = maxf(
			0.75,
			navigation_refresh_interval * 3.0
		)
		## 这是 AI 因“困住”主动重试导航的本地诊断事件，不是 Squad 通信。
		navigation_path_refreshed.emit([], true)
		_on_squad_stuck_detected(goal)
		_debug(
			(
				"squad stuck detected state=%s elapsed=%.1fs goal_progress=%.2fm "
				+ "travel=%.2fm blocked=%.2fs oscillating=%s alignment=%.2f "
				+ "goal_alignment=%.2f goal=%s"
			)
			% [
				_status_label_text(),
				elapsed,
				goal_progress,
				detected_travel,
				detected_blocked,
				str(oscillating),
				command_alignment,
				goal_alignment,
				_format_position(goal),
			]
		)
		return

	_squad_stuck_elapsed += delta
	if _squad_stuck_elapsed >= squad_stuck_escape_after_seconds:
		_start_squad_escape()


func _reset_squad_stuck_tracking() -> void:
	_squad_stuck = false
	_squad_stuck_elapsed = 0.0
	_squad_navigation_retry_timer = 0.0
	_reset_squad_progress_window()


func _start_squad_escape() -> void:
	var direction := Vector3.ZERO
	var escape_position := global_position
	var escape_distance := maxf(1.0, squad_escape_distance)
	for _attempt in range(8):
		var candidate := Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0,
			rng.randf_range(-1.0, 1.0)
		)
		if candidate.length_squared() <= 0.01:
			continue
		candidate = candidate.normalized()
		var candidate_position := _clamp_to_map_interior(
			global_position + candidate * escape_distance
		)
		if (
			_horizontal_distance(global_position, candidate_position) >= escape_distance * 0.45
			and not _movement_direction_is_blocked(candidate, minf(1.5, escape_distance))
		):
			direction = candidate
			escape_position = candidate_position
			break
	if direction.length_squared() <= 0.01:
		direction = -global_transform.basis.z
		direction.y = 0.0
		if direction.length_squared() <= 0.01:
			direction = Vector3.FORWARD
		direction = direction.normalized()
		escape_position = _clamp_to_map_interior(
			global_position + direction * escape_distance
		)
	direction = _find_open_movement_direction(direction, minf(1.5, escape_distance))
	escape_position = _clamp_to_map_interior(
		global_position + direction * escape_distance
	)
	_squad_escape_waypoint = escape_position
	_squad_escape_direction = direction
	_squad_escape_timer = maxf(0.5, squad_escape_duration)
	_squad_stuck = false
	_squad_stuck_elapsed = 0.0
	_squad_progress_window_elapsed = 0.0
	_squad_progress_anchor = global_position
	_reset_navigation_path()
	_debug(
		"squad escape started direction=%s waypoint=%s"
		% [_format_position(direction), _format_position(escape_position)]
	)


func _apply_squad_soft_separation(route_direction: Vector3) -> Vector3:
	if route_direction.length_squared() < 0.001 or not is_instance_valid(squad):
		return route_direction
	if not squad.has_method("get_member_nodes"):
		return route_direction
	var minimum_distance := squad_minimum_member_distance
	var weight := squad_separation_weight
	var squad_minimum = squad.get("minimum_member_distance")
	var squad_weight = squad.get("separation_weight")
	if squad_minimum != null:
		minimum_distance = float(squad_minimum)
	if squad_weight != null:
		weight = float(squad_weight)
	var separation := Vector3.ZERO
	for member in squad.get_member_nodes():
		if member == self or not is_instance_valid(member) or not member is Node3D:
			continue
		var member_3d := member as Node3D
		var away: Vector3 = global_position - member_3d.global_position
		away.y = 0.0
		var distance: float = away.length()
		if distance > 0.001 and distance < minimum_distance:
			separation += away.normalized() * (1.0 - distance / minimum_distance)
	if separation.length_squared() < 0.001:
		return route_direction
	## 仅做软修正：在狭窄入口中导航方向继续占主导，不强行把队员分开。
	return (route_direction.normalized() + separation.normalized() * clampf(weight, 0.0, 0.6)).normalized()


func _rotate_toward_direction(
	direction: Vector3,
	delta: float
) -> void:
	if direction.length_squared() < 0.001:
		return

	var desired_yaw := atan2(
		-direction.x,
		-direction.z
	)

	rotation.y = lerp_angle(
		rotation.y,
		desired_yaw,
		minf(
			1.0,
			rotation_speed * delta
		)
	)


# ------------------------------------------------------------------
# Team and visibility
# ------------------------------------------------------------------

func get_combat_team() -> String:
	return team_id


func _ensure_team_marker_visual() -> void:
	if is_instance_valid(team_marker):
		_update_team_marker_visibility()
		return
	team_marker = MeshInstance3D.new()
	team_marker.name = "TeamMarker"
	team_marker.position = Vector3.UP * TEAM_MARKER_HEIGHT
	team_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	team_marker.ignore_occlusion_culling = true
	var sphere := SphereMesh.new()
	sphere.radius = 0.14
	sphere.height = 0.28
	sphere.radial_segments = 16
	sphere.rings = 8
	team_marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = _team_marker_color()
	material.emission_enabled = true
	material.emission = _team_marker_color()
	material.emission_energy_multiplier = 2.5
	material.render_priority = 120
	team_marker.material_override = material
	add_child(team_marker)
	_update_team_marker_visibility()


func _team_marker_color() -> Color:
	return Color("#F04455") if team_id == "red" else Color("#398CFF")


func _local_viewer_team() -> String:
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is Node:
			continue
		if _has_property(node, "is_remote_proxy") and bool(node.get("is_remote_proxy")):
			continue
		var value := _get_combat_team(node)
		if not value.is_empty():
			return value
	return ""


func _update_team_marker_visibility() -> void:
	if not is_instance_valid(team_marker):
		return
	var material := team_marker.material_override as StandardMaterial3D
	var marker_color := _team_marker_color()
	if material != null:
		material.albedo_color = marker_color
		material.emission = marker_color
	var viewer_team := _local_viewer_team()
	# Teammate markers are always visible. If the local player has not been
	# created yet, keep the marker visible until the viewer team is known.
	team_marker.visible = (viewer_team.is_empty() or viewer_team == team_id) \
		and state != AIState.DEAD


func get_network_state() -> Dictionary:
	var weapon_id := str(weapon_data.get(current_weapon_slot, {}).get("id", ""))
	return {
		"ai_id": str(get_meta("network_ai_id", name)),
		"ai_type": "futurewarrior",
		"name": name,
		"team": team_id,
		"position": global_position,
		"yaw": rotation.y,
		"hp": current_hp,
		"max_hp": max_hp,
		"dead": state == AIState.DEAD,
		"respawn_left": 0.0,
		"death_cleanup_left": _death_cleanup_remaining_seconds(),
		"state": int(state),
		"squad_stuck": _squad_stuck,
		"weapon_slot": current_weapon_slot,
		"weapon_id": weapon_id,
		"aim_active": _weapon_aim_active,
		"aim_position": _weapon_aim_position,
		"aim_direction": _weapon_aim_direction,
		"velocity": velocity,
		"grounded": is_on_floor(),
	}


func can_enter_interest_sleep() -> bool:
	return state != AIState.DEAD


func set_interest_sleeping(value: bool) -> void:
	if value:
		if state == AIState.DEAD:
			return
		interest_sleeping = true
		velocity = Vector3.ZERO
		target_player = null
		retaliation_target = null
		_weapon_aim_active = false
		action_animation_locked = false
		_play_body_animation(&"Idle", 0.08)
		_update_health_label()
		return
	interest_sleeping = false
	if state == AIState.DEAD:
		return
	state = AIState.SEARCH
	velocity = Vector3.ZERO
	target_player = null
	_weapon_aim_active = false
	action_animation_locked = false


func apply_network_state(data: Dictionary) -> void:
	var was_dead := state == AIState.DEAD
	var incoming_dead := bool(data.get("dead", false))
	global_position = data.get("position", global_position) as Vector3
	rotation.y = float(data.get("yaw", rotation.y))
	current_hp = float(data.get("hp", current_hp))
	if not incoming_dead and data.has("weapon_slot"):
		var incoming_weapon_slot := int(data.get("weapon_slot", current_weapon_slot))
		if incoming_weapon_slot >= 0 and incoming_weapon_slot != current_weapon_slot:
			_equip_weapon(incoming_weapon_slot)
	if incoming_dead:
		state = AIState.DEAD
	elif data.has("state"):
		state = int(data.get("state", state))
	if data.has("squad_stuck"):
		_squad_stuck = bool(data.get("squad_stuck", _squad_stuck))
	if incoming_dead and not was_dead:
		## 远端代理不执行 _die()，否则会重复掉落金钱、通知小队和结算击杀；
		## 这里只同步死亡动画和不可交互表现。
		velocity = Vector3.ZERO
		_death_cleanup_deadline_msec = Time.get_ticks_msec() + roundi(
			maxf(0.0, float(data.get("death_cleanup_left", DEATH_CLEANUP_SECONDS)))
			* 1000.0
		)
		_play_death_animation()
		collision_layer = 0
		collision_mask = _corpse_collision_mask()
		if hit_3d != null:
			hit_3d.set_deferred("monitoring", false)
			hit_3d.set_deferred("monitorable", false)
		if body_collision_shape != null:
			body_collision_shape.set_deferred("disabled", false)
		if hit_collision_shape != null:
			hit_collision_shape.set_deferred("disabled", true)
	elif not incoming_dead:
		_death_cleanup_deadline_msec = -1
	if not incoming_dead:
		_apply_network_weapon_aim(data)
		var velocity_value: Variant = data.get("velocity", Vector3.ZERO)
		var network_velocity := (
			velocity_value as Vector3
			if velocity_value is Vector3
			else Vector3.ZERO
		)
		_update_network_locomotion_animation(
			network_velocity,
			bool(data.get("grounded", true)),
			bool(data.get("aim_active", false))
		)
	_update_team_marker_visibility()
	if health_label != null:
		health_label.visible = not incoming_dead
		_update_health_label()


func _apply_network_weapon_aim(data: Dictionary) -> void:
	## Remote AI proxies have their runtime processing disabled. Apply the same
	## aim frame used by the authority before correcting ToolPivot, so the visible
	## FutureM4/FutureMPX muzzle keeps the player's Y/pitch correction.
	if not is_instance_valid(head) or not is_instance_valid(aim_ray) \
		or not is_instance_valid(look_at_target):
		return
	var aim_active := bool(data.get("aim_active", false))
	var direction_value: Variant = data.get("aim_direction", _weapon_aim_direction)
	var direction := direction_value as Vector3 if direction_value is Vector3 else Vector3.ZERO
	if direction.length_squared() <= 0.001:
		direction = -global_transform.basis.z
	direction = direction.normalized()
	var position_value: Variant = data.get("aim_position", INVALID_POSITION)
	_weapon_aim_position = position_value as Vector3 if position_value is Vector3 else INVALID_POSITION
	_weapon_aim_direction = direction
	_weapon_aim_active = aim_active
	var aim_origin := head.global_position
	if aim_active:
		## 使用权威端同步的最终方向，而不是客户端重新查找目标或用过期
		## presentation player 节点重算瞄准点。
		_aim_at(aim_origin + direction * 100.0)
		_weapon_aim_position = position_value as Vector3 \
			if position_value is Vector3 else INVALID_POSITION
	else:
		## 从交火恢复到普通移动时清掉上一帧的俯仰，避免枪口继续指向
		## 已经离开的玩家；根节点的当前 yaw 仍会自然带动武器。
		aim_ray.rotation = Vector3.ZERO
		look_at_target.rotation = Vector3.ZERO
	_update_tool_camera_alignment()


func _is_enemy(node: Node) -> bool:
	if node == null:
		return false

	var other_team := _get_combat_team(node)

	if other_team.is_empty():
		return false

	if team_id == "enemy":
		return other_team != "enemy"

	return other_team != team_id


func _get_combat_team(
	node: Node
) -> String:
	if node == null:
		return ""

	if node.has_method("get_combat_team"):
		return str(
			node.call("get_combat_team")
		)

	for property_name in [
		"team_id",
		"team",
		"tool_owner",
		"owner_team",
		"kitchen_team",
	]:
		if _has_property(
			node,
			property_name
		):
			return str(
				node.get(property_name)
			)

	return ""


func _has_clear_line_to(
	target: Node3D
) -> bool:
	if not is_instance_valid(target):
		return false

	var origin := head.global_position

	var destination := (
		target.global_position
		+ Vector3.UP * target_height
	)

	var query := (
		PhysicsRayQueryParameters3D.create(
			origin,
			destination,
			combat_ray_mask,
			[get_rid()] + _server_presentation_player_query_exclusions()
		)
	)

	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_from_inside = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return true

	var collider := (
		hit.get("collider")
		as Node
	)

	if collider == target:
		return true

	var cursor := collider
	var depth := 0

	while cursor != null and depth < 12:
		if cursor == target:
			return true

		cursor = cursor.get_parent()
		depth += 1

	return false


# ------------------------------------------------------------------
# Hit3D, damage and death
# ------------------------------------------------------------------

func _on_hit_3d_body_entered(
	body: Node3D
) -> void:
	_handle_hit3d_contact(body)


func _on_hit_3d_area_entered(
	area: Area3D
) -> void:
	_handle_hit3d_contact(area)


func _handle_hit3d_contact(
	contact: Node
) -> void:
	var bullet := _find_projectile_root(
		contact
	)

	if bullet == null:
		return

	if not bullet.has_method(
		"get_bullet_owner"
	):
		return

	var shooter_team := str(
		bullet.call(
			"get_bullet_owner"
		)
	)

	if shooter_team == team_id:
		return

	var damage := default_bullet_damage
	var effect := "bullet"
	var hit_direction := Vector3.ZERO
	var knockback_force := 0.0

	if _has_property(
		bullet,
		"damage"
	):
		damage = float(
			bullet.get("damage")
		)

	elif _has_property(
		bullet,
		"bullet_damage"
	):
		damage = float(
			bullet.get("bullet_damage")
		)

	if _has_property(
		bullet,
		"bullet_effect"
	):
		effect = str(
			bullet.get("bullet_effect")
		)

		if (
			not _has_property(bullet, "damage")
			and not _has_property(
				bullet,
				"bullet_damage"
			)
		):
			damage = color_bullet_damage

	if _has_property(
		bullet,
		"direction"
	):
		var direction_value: Variant = (
			bullet.get("direction")
		)

		if direction_value is Vector3:
			hit_direction = direction_value

	if _has_property(
		bullet,
		"knockback_force"
	):
		knockback_force = float(
			bullet.get(
				"knockback_force"
			)
		)

	if hit_direction == Vector3.ZERO:
		hit_direction = (
			_horizontal_direction(
				bullet.global_position,
				global_position
			)
		)

	var attacker_node: CharacterBody3D
	if bullet.has_method("get_bullet_shooter"):
		attacker_node = bullet.call("get_bullet_shooter") as CharacterBody3D

	impact(
		effect,
		damage,
		shooter_team,
		hit_direction,
		attacker_node
	)

	if knockback_force > 0.0:
		receive_bullet_hit(
			hit_direction,
			knockback_force,
			shooter_team
		)

	if is_instance_valid(bullet):
		bullet.queue_free()


func _find_projectile_root(
	contact: Node
) -> Node3D:
	var cursor := contact
	var depth := 0

	while cursor != null and depth < 12:
		if (
			cursor is Node3D
			and cursor.has_method(
				"get_bullet_owner"
			)
		):
			return cursor as Node3D

		cursor = cursor.get_parent()
		depth += 1

	return null


func impact(
	effect: String,
	strength: float,
	attacker_team: String = "",
	hit_direction: Vector3 = Vector3.ZERO,
	attacker_node: CharacterBody3D = null
) -> bool:
	if state == AIState.DEAD:
		return false

	if (
		not attacker_team.is_empty()
		and attacker_team == team_id
	):
		return false

	var damage := maxf(
		strength,
		0.0
	)

	if effect == "explosion":
		damage *= explosion_damage_multiplier
	elif effect.to_lower() == "bug_storm":
		damage = CombatBalance.get_bug_storm_impact_damage(strength)

	_apply_damage(
		damage,
		effect,
		attacker_team,
		hit_direction,
		attacker_node
	)

	return true


func impact_from_peer(
	effect: String,
	strength: float,
	attacker_team: String,
	attacker_peer_id: int
) -> bool:
	var attacker_node := _find_human_attacker_by_peer_id(attacker_peer_id)
	var hit_direction := Vector3.ZERO
	if is_instance_valid(attacker_node):
		hit_direction = global_position - attacker_node.global_position
	return impact(effect, strength, attacker_team, hit_direction, attacker_node)


func receive_bullet_hit(
	hit_direction: Vector3,
	force: float,
	shooter_team: String
) -> void:
	if shooter_team == team_id:
		return

	var horizontal := Vector3(
		hit_direction.x,
		0.0,
		hit_direction.z
	)

	if horizontal.length_squared() > 0.001:
		rubber_knockback += (
			horizontal.normalized()
			* force
		)


func _apply_damage(
	damage: float,
	effect: String,
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> void:
	current_hp = maxf(
		0.0,
		current_hp - damage
	)

	recent_damage += damage
	damage_memory_timer = (
		damage_memory_seconds
	)

	if is_instance_valid(attacker_node):
		last_damage_source_position = attacker_node.global_position

	elif hit_direction.length_squared() > 0.001:
		last_damage_source_position = (
			global_position
			- hit_direction.normalized()
			* 3.0
		)

	elif _is_valid_target(target_player):
		last_damage_source_position = (
			target_player.global_position
		)

	var retaliation_started := _remember_retaliation_target(
		attacker_team,
		hit_direction,
		attacker_node
	)

	_update_health_label()

	_debug(
		"hit effect=%s damage=%.1f hp=%.1f attacker=%s"
		% [
			effect,
			damage,
			current_hp,
			attacker_team,
		]
	)

	if current_hp <= 0.0:
		_die(
			attacker_team,
			effect
		)
		return

	## 只有子弹命中、并且受击者已经进入 COMBAT，才开启 Squad 支援广播。
	## 如果攻击距离较远导致先进入 CHASE，则等真正进入 COMBAT 后再发送。
	if _is_bullet_damage_effect(effect) and retaliation_started:
		_squad_support_pending_after_bullet = true
		if state == AIState.COMBAT:
			_activate_squad_support_broadcast()

	## 已经找到实际攻击者时，受击反击优先于旧的自动撤退逻辑。
	## 这样不会再先切手枪逃跑 1.8 秒后才回头攻击。
	if retaliation_started:
		return

	var health_ratio := (
		current_hp
		/ maxf(max_hp, 0.001)
	)

	if (
		health_ratio <= low_health_flee_ratio
		and not low_health_flee_used
	):
		low_health_flee_used = true

		_begin_flee(
			low_health_flee_duration,
			last_damage_source_position
		)
		return

	if recent_damage >= burst_damage_to_flee:
		recent_damage = 0.0

		_begin_flee(
			short_flee_duration + 0.8,
			last_damage_source_position
		)
		return

	if flee_on_any_damage:
		_begin_flee(
			short_flee_duration,
			last_damage_source_position
		)


func _is_bullet_damage_effect(effect: String) -> bool:
	var effect_key := effect.to_lower()
	return effect_key in [
		"bullet",
		"nail",
		"nail_bullet",
		"rubber",
		"rubber_bullet",
		"flame",
		"freeze",
		"color",
		"color_bullet",
	]


func _remember_retaliation_target(
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> bool:
	if _is_valid_target(attacker_node):
		_activate_retaliation_target(attacker_node)
		return true

	## 旧投射物和部分爆炸只携带队伍与方向。此时沿受击反方向寻找最匹配的
	## 敌方角色，并把 combat_characters 纳入候选，避免 Warrior 互射时找不到攻击者。
	var attack_direction := Vector3.ZERO
	if hit_direction.length_squared() > 0.001:
		attack_direction = -hit_direction.normalized()
	var closest: CharacterBody3D
	var best_score := INF
	var visited := {}
	var candidate_groups := _authoritative_human_player_groups()
	candidate_groups.append_array([&"wild_animals", &"combat_characters"])
	for group_name in candidate_groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			var candidate_id := int(candidate.get_instance_id())
			if visited.has(candidate_id):
				continue
			visited[candidate_id] = true
			if not _is_active_hostile_candidate(candidate):
				continue
			if not attacker_team.is_empty() and _get_combat_team(candidate) != attacker_team:
				continue
			var offset := candidate.global_position - global_position
			offset.y = 0.0
			var distance := offset.length()
			var score := distance
			if attack_direction != Vector3.ZERO and distance > 0.001:
				var alignment := attack_direction.dot(offset / distance)
				if alignment <= 0.05:
					continue
				var lateral_error := distance * sqrt(maxf(0.0, 1.0 - alignment * alignment))
				score = lateral_error * 4.0 + distance * 0.08
			if score < best_score:
				closest = candidate
				best_score = score

	if closest == null:
		return false
	_activate_retaliation_target(closest)
	return true


func _activate_retaliation_target(attacker: CharacterBody3D) -> void:
	retaliation_target = attacker
	retaliation_timer = 5.0
	target_player = attacker
	target_refresh_timer = target_refresh_interval
	last_known_target_position = attacker.global_position
	_begin_target_engagement(attacker)
	var direction := _horizontal_direction(global_position, attacker.global_position)
	if direction.length_squared() > 0.001:
		## 受击帧直接完成水平转向；后续帧继续由正常瞄准与移动逻辑接管。
		rotation.y = atan2(-direction.x, -direction.z)
	_aim_at(_get_predicted_aim_position(attacker))
	fire_timer = 0.0
	ar15_burst_pause_timer = 0.0
	var distance := _horizontal_distance(global_position, attacker.global_position)
	state = AIState.COMBAT if _has_clear_line_to(attacker) \
		and distance <= preferred_combat_range + combat_range_tolerance else AIState.CHASE
	_debug("immediate retaliation target=%s distance=%.1f" % [attacker.name, distance])


func _find_human_attacker_by_peer_id(peer_id: int) -> CharacterBody3D:
	if peer_id <= 0:
		return null
	## The listen server contains both the local GamePlayer presentation and its
	## ServerPlayerPhysicsBody. Prefer the same authoritative group used by AI
	## target selection; otherwise damage retaliation could lock onto the stale
	## presentation transform even though hitscan uses the server proxy.
	for group_name in _authoritative_human_player_groups():
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D or not _has_property(node, "authority_peer_id"):
				continue
			if int(node.get("authority_peer_id")) == peer_id:
				return node as CharacterBody3D
	return null


func _update_health_label() -> void:
	if health_label == null:
		return

	health_label.visible = show_health_label

	health_label.text = (
		"Future Warrior  %d / %d\n"
		+ "FutureM4 %d/%d · Pistol %d/%d · Grenade x%d\n"
		+ "状态: %s\n"
		+ "困住状态: %s\n"
		+ "最近消息: %s"
	) % [
		roundi(current_hp),
		roundi(max_hp),
		_weapon_ammo_in_mag(WeaponSlot.AR15),
		_weapon_reserve_ammo(WeaponSlot.AR15),
		_weapon_ammo_in_mag(WeaponSlot.SUPPRESSED_PISTOL),
		_weapon_reserve_ammo(WeaponSlot.SUPPRESSED_PISTOL),
		grenades_remaining,
		_status_label_text(),
		_squad_stuck_label_text(),
		_last_squad_message_label(),
	]

	var ratio := clampf(
		current_hp / maxf(max_hp, 0.001),
		0.0,
		1.0
	)

	health_label.modulate = Color(
		lerpf(1.0, 0.35, ratio),
		lerpf(0.30, 1.0, ratio),
		0.35,
		1.0
	)


func _die(
	attacker_team: String,
	effect: String
) -> void:
	if state == AIState.DEAD:
		return

	state = AIState.DEAD
	_finish_grenade_avoidance()
	_clear_squad_support()
	_squad_support_broadcast_active = false
	_squad_support_pending_after_bullet = false
	_clear_squad_warning_state()
	combat_engagement_point = INVALID_POSITION
	combat_engagement_target_id = 0
	_weapon_aim_active = false
	_squad_escape_waypoint = INVALID_POSITION
	_squad_escape_direction = Vector3.ZERO
	_squad_escape_timer = 0.0
	_reset_squad_stuck_tracking()
	_avoidance_safe_velocity = Vector3.ZERO
	_avoidance_safe_velocity_valid = false
	if not attacker_team.is_empty() and (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		GameAuthority.award_future_warrior_defeat(attacker_team, team_id)
	_try_spawn_cash_drop_on_death()
	velocity = Vector3.ZERO
	rubber_knockback = Vector3.ZERO
	action_animation_locked = true
	_death_cleanup_deadline_msec = Time.get_ticks_msec() + roundi(
		DEATH_CLEANUP_SECONDS * 1000.0
	)
	_play_death_animation()

	collision_layer = 0
	collision_mask = _corpse_collision_mask()

	if hit_3d != null:
		## _die() 可能由 Hit3D.body_entered 直接调用；此时物理服务器正在
		## flush 查询，Area3D 的监控属性不能同步修改，否则会报
		## "Function blocked during in/out signal"。
		hit_3d.set_deferred("monitoring", false)
		hit_3d.set_deferred("monitorable", false)
		hit_3d.set_deferred("collision_layer", 0)
		hit_3d.set_deferred("collision_mask", 0)

	if body_collision_shape != null:
		body_collision_shape.set_deferred("disabled", false)

	if hit_collision_shape != null:
		hit_collision_shape.set_deferred(
			"disabled",
			true
		)

	if is_instance_valid(held_weapon):
		held_weapon.queue_free()
		held_weapon = null
	current_weapon_slot = -1
	if health_label != null:
		health_label.visible = false

	_debug("killed by=%s effect=%s; death animation playing; removal in %.1f seconds" % [
		attacker_team, effect, DEATH_CLEANUP_SECONDS,
	])
	if is_instance_valid(external_respawn_controller) and external_respawn_controller.has_method("notify_squad_member_dead"):
		external_respawn_controller.notify_squad_member_dead(self)

	call_deferred(
		"_finish_death"
	)


func _try_spawn_cash_drop_on_death() -> void:
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		return
	if cash_drop_chance <= 0.0 or rng.randf() >= cash_drop_chance:
		return
	var minimum := mini(cash_drop_minimum, cash_drop_maximum)
	var maximum := maxi(cash_drop_minimum, cash_drop_maximum)
	var amount := rng.randi_range(minimum, maximum)
	var direction := Vector3(
		rng.randf_range(-1.0, 1.0),
		0.35,
		rng.randf_range(-1.0, 1.0)
	).normalized()
	var authority := get_node_or_null("/root/GameAuthority")
	if authority == null or not authority.has_method("spawn_cash_drop"):
		_debug("cash drop skipped: GameAuthority.spawn_cash_drop unavailable")
		return
	var spawned := bool(authority.call(
		"spawn_cash_drop",
		global_position,
		amount,
		team_id,
		direction
	))
	if spawned:
		_debug("cash drop spawned amount=%d position=%s" % [amount, global_position])


func _finish_death() -> void:
	## 无论是否属于小队，死亡节点都只保留十秒用于播放倒地表现。
	## 小队生成器仍然按自己的 respawn_seconds 生成下一批，不复用这个节点。
	await get_tree().create_timer(
		_death_cleanup_remaining_seconds()
	).timeout
	if not is_inside_tree() or state != AIState.DEAD:
		return
	_debug("death cleanup complete; removing node")
	queue_free()


func _death_cleanup_remaining_seconds() -> float:
	if state != AIState.DEAD or _death_cleanup_deadline_msec < 0:
		return 0.0
	return maxf(
		0.0,
		float(_death_cleanup_deadline_msec - Time.get_ticks_msec()) / 1000.0
	)


func _respawn_at_team_spawn() -> void:
	_death_cleanup_deadline_msec = -1
	_finish_grenade_avoidance()
	var spawn_position := _get_team_respawn_position()
	global_position = spawn_position
	velocity = Vector3.ZERO
	rubber_knockback = Vector3.ZERO
	current_hp = max_hp
	grenades_remaining = starting_grenade_count
	engagement_grenade_target_id = 0
	engagement_grenade_pending = false
	target_player = null
	retaliation_target = null
	retaliation_timer = 0.0
	last_known_target_position = INVALID_POSITION
	flee_target = INVALID_POSITION
	flee_timer = 0.0
	flee_retrigger_timer = 0.0
	low_health_flee_used = false
	damage_memory_timer = 0.0
	recent_damage = 0.0
	last_damage_source_position = INVALID_POSITION
	fire_timer = 0.0
	grenade_timer = 0.0
	ar15_burst_shots_remaining = 0
	ar15_burst_pause_timer = 0.0
	action_animation_locked = false
	landing_animation = false
	was_on_floor = true
	state = AIState.SEARCH
	_clear_squad_support()
	_squad_support_broadcast_active = false
	_squad_support_pending_after_bullet = false
	_clear_squad_warning_state()
	_squad_support_request_timer = 0.0
	combat_engagement_point = INVALID_POSITION
	combat_engagement_target_id = 0
	_squad_escape_waypoint = INVALID_POSITION
	_squad_escape_direction = Vector3.ZERO
	_squad_escape_timer = 0.0
	_reset_squad_stuck_tracking()
	_avoidance_safe_velocity = Vector3.ZERO
	_avoidance_safe_velocity_valid = false
	if navigation_agent != null:
		navigation_agent.set_velocity(Vector3.ZERO)
	collision_layer = body_collision_layer
	collision_mask = body_collision_mask
	if body_collision_shape != null:
		body_collision_shape.set_deferred("disabled", false)
	if hit_collision_shape != null:
		hit_collision_shape.set_deferred("disabled", false)
	if hit_3d != null:
		hit_3d.collision_layer = hit_area_collision_layer
		hit_3d.collision_mask = hit_area_collision_mask
		hit_3d.monitoring = true
		hit_3d.monitorable = true
	_initialize_weapon_ammo()
	_equip_weapon(WeaponSlot.AR15)
	_play_body_animation(&"Idle", 0.05)
	_update_health_label()
	_debug("respawned at %s team spawn" % team_id)


func _get_team_respawn_position() -> Vector3:
	var game_world: Node = GlobalVar.gameworld
	if is_instance_valid(game_world) and game_world.has_method("get_spawn_position_for_id"):
		var spawn_value: Variant = game_world.call(
			"get_spawn_position_for_id", spawn_point_id, team_id, 1, get_instance_id()
		)
		if spawn_value is Vector3 and spawn_value != Vector3.INF:
			return spawn_value
	return global_position


# ------------------------------------------------------------------
# Generic helpers
# ------------------------------------------------------------------

func _horizontal_distance(
	a: Vector3,
	b: Vector3
) -> float:
	return Vector2(
		a.x,
		a.z
	).distance_to(
		Vector2(
			b.x,
			b.z
		)
	)


func _horizontal_direction(
	from_position: Vector3,
	to_position: Vector3
) -> Vector3:
	var direction := (
		to_position
		- from_position
	)

	direction.y = 0.0

	if direction.length_squared() < 0.001:
		return Vector3.ZERO

	return direction.normalized()


func _has_property(
	object: Object,
	property_name: String
) -> bool:
	for property_info: Dictionary in (
		object.get_property_list()
	):
		if str(
			property_info.get(
				"name",
				""
			)
		) == property_name:
			return true

	return false


func _set_optional_property(
	object: Object,
	property_name: String,
	value: Variant
) -> void:
	if _has_property(
		object,
		property_name
	):
		object.set(
			property_name,
			value
		)


func _debug(message: String) -> void:
	if print_decisions:
		print(
			"[FutureWarriorAI] ",
			message
		)
