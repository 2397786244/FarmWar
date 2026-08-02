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
## - AR15
## - SuppressedPistol
## - 2 枚 Grenade
##
## 行为：
## - 沿导航路径前往敌方农场，并以扇形视锥左右搜索敌方玩家。
## - 不种地、不收获、不放置农场工具。
## - 中远距离 AR15 点射。
## - 近距离自动切换 SuppressedPistol。
## - 合适时投掷手雷。
## - 受伤时进行战术撤退，并在撤退时用手枪还击。
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
@export var ar15_tool_id: String = "ar15"
@export var suppressed_pistol_tool_id: String = "suppressed_pistol"
@export var grenade_tool_id: String = "grenade"

@export_file("*.tscn")
var ar15_scene_path: String = \
	"res://character/weapons/AR15.tscn"

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

## 与玩家保持一致：死亡后保留倒地表现 10 秒，再回到本队出生点。
@export_range(1.0, 30.0, 0.5)
var respawn_seconds: float = 10.0

## Optional map-assigned spawn. Empty means a random spawn point in team_id.
@export var spawn_point_id: String = ""

## 子弹没有公开 damage/bullet_damage 属性时使用。
@export var default_bullet_damage: float = 12.0
@export var color_bullet_damage: float = 15.0
@export var explosion_damage_multiplier: float = 1.0

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

## 地图有 NavigationRegion3D 时使用导航。
## 没有有效导航地图时自动回退到直线移动 + RayCast 避障。
@export var use_navigation_agent: bool = true

@export var navigation_refresh_interval: float = 0.18

@export_category("Farm Search And Vision")

## 未发现目标时前往敌方农场；到达后在农场周边巡查。
@export var enemy_farm_arrival_radius: float = 10.0
@export var enemy_farm_patrol_radius: float = 16.0
@export var enemy_farm_refresh_interval: float = 2.0
## 256m 地图的可活动内侧边界。AI 接近空气墙时会主动折返。
@export var map_boundary_limit: float = 126.0
@export var boundary_turn_margin: float = 4.0

## 视锥随巡逻视线转动。角色的实际前方采用 Godot CharacterBody3D 的 -Z 轴。
@export_range(1.0, 80.0, 0.5) var vision_range: float = 80.0
@export_range(10.0, 180.0, 1.0) var vision_fov_degrees: float = 120.0
@export_range(5.0, 90.0, 1.0) var search_look_sweep_degrees: float = 48.0
@export_range(0.5, 8.0, 0.1) var search_look_sweep_seconds: float = 2.8
@export_flags_3d_physics var vision_occlusion_mask: int = 65535

## 遇到低矮障碍时尝试跳跃。
@export var jump_velocity: float = 3.8
@export var jump_cooldown: float = 0.85


# ------------------------------------------------------------------
# AR15
# ------------------------------------------------------------------

@export_category("AR15")

@export var ar15_min_range: float = 5.5
@export var ar15_max_range: float = 34.0

## 最小射击间隔。即使 JSON cooldown 更小，也不会快于该值。
@export var ar15_fire_interval: float = 0.11

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

@export_range(0.0, 1.0, 0.01)
var grenade_use_chance: float = 0.72

## 投射物手雷推荐实现：
## launch(initial_velocity: Vector3, owner_team: String)
@export var grenade_launch_method: StringName = &"launch"


# ------------------------------------------------------------------
# Runtime collision
# ------------------------------------------------------------------

@export_category("Runtime Collision")

## 与现有玩家/AI CharacterBody3D 设置一致。
@export var body_collision_layer: int = 8
@export var body_collision_mask: int = 519

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

var current_weapon_slot: int = -1
var held_weapon: Node3D

var grenade_data: Dictionary = {}
var grenades_remaining: int = 0

var fire_timer: float = 0.0
var grenade_timer: float = 0.0

var ar15_burst_shots_remaining: int = 0
var ar15_burst_pause_timer: float = 0.0


# ------------------------------------------------------------------
# AI runtime
# ------------------------------------------------------------------

var state: int = AIState.SEARCH
var current_hp: float = 0.0

var target_player: CharacterBody3D
var last_known_target_position: Vector3 = INVALID_POSITION
var retaliation_target: CharacterBody3D
var retaliation_timer: float = 0.0

var target_refresh_timer: float = 0.0
var navigation_refresh_timer: float = 0.0
var enemy_farm_refresh_timer: float = 0.0
var enemy_farm_position: Vector3 = INVALID_POSITION
var farm_patrol_position: Vector3 = INVALID_POSITION
var search_look_phase: float = 0.0
var search_look_direction: Vector3 = Vector3.ZERO

var flee_target: Vector3 = INVALID_POSITION
var flee_timer: float = 0.0
var flee_retrigger_timer: float = 0.0
var low_health_flee_used: bool = false

var damage_memory_timer: float = 0.0
var recent_damage: float = 0.0
var last_damage_source_position: Vector3 = INVALID_POSITION

var strafe_sign: float = 1.0
var strafe_timer: float = 0.0

var jump_timer: float = 0.0

var rubber_knockback: Vector3 = Vector3.ZERO
var rng := RandomNumberGenerator.new()


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

	## 出生后直接手持 AR15；若资源路径错误则退回消音手枪。
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
	if state == AIState.DEAD:
		return

	## 与 player.gd 一致：
	## 先更新上半身瞄准和 IK，再执行枪械基准矫正。
	_update_upper_body_aim(delta)
	_update_tool_camera_alignment()


func _physics_process(delta: float) -> void:
	if state == AIState.DEAD:
		return

	if not _has_simulation_authority():
		return

	_update_timers(delta)
	_refresh_target()

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


func _has_simulation_authority() -> bool:
	if not server_authoritative:
		return true

	if not multiplayer.has_multiplayer_peer():
		return true

	return multiplayer.is_server()


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
	navigation_agent.avoidance_enabled = false

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
	health_label.visible = show_health_label


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

		&"ShootOneHand", &"ToolUseRight", &"PunchRIght":
			action_animation_locked = false


func _update_character_animation(
	move_direction: Vector3
) -> void:
	if appearance_player == null:
		return

	var grounded := is_on_floor()

	if grounded and not was_on_floor:
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

	elif move_direction.length_squared() > 0.001:
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

	## 玩家原算法这里使用 camera.global_transform.basis。
	## AI 使用已经朝向目标的 aim_ray 基准。
	var desired_aim_basis: Basis = aim_ray.global_transform.basis.orthonormalized()

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
		ar15_fire_interval
	)

	weapon_data[
		WeaponSlot.SUPPRESSED_PISTOL
	] = _load_item_data(
		suppressed_pistol_tool_id,
		suppressed_pistol_scene_path,
		pistol_grip_position,
		pistol_grip_rotation,
		pistol_grip_scale,
		pistol_fire_interval
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
	fallback_cooldown: float
) -> Dictionary:
	var result := {
		"id": tool_id,
		"path": fallback_path,
		"grip_position": fallback_position,
		"grip_rotation": fallback_rotation,
		"grip_scale": fallback_scale,
		"cooldown": fallback_cooldown,
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

func _refresh_target() -> void:
	if target_refresh_timer > 0.0:
		return

	target_refresh_timer = target_refresh_interval
	if retaliation_timer > 0.0 and _is_valid_target(retaliation_target):
		target_player = retaliation_target
	else:
		target_player = _find_best_visible_hostile()

	if target_player == null:
		if state != AIState.FLEE:
			state = AIState.SEARCH

		last_known_target_position = (
			INVALID_POSITION
		)
		return

	last_known_target_position = (
		target_player.global_position
	)

	if state != AIState.FLEE:
		state = AIState.CHASE

	_debug(
		"target=%s"
		% target_player.name
	)


func _find_best_enemy_player() -> CharacterBody3D:
	return _find_best_visible_hostile()


func _find_best_visible_hostile() -> CharacterBody3D:
	var best_target: CharacterBody3D
	var best_score := INF

	for group_name in [&"human_players", &"wild_animals", &"combat_characters"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			if not _is_active_hostile_candidate(candidate):
				continue
			if not _is_inside_vision_cone(candidate) or not _has_visual_contact(candidate):
				continue

			# 视线内玩家优先于野生动物；同类再按距离选择。
			var priority := 0.0 if candidate.is_in_group("human_players") else 1000.0
			var score := priority + _horizontal_distance(global_position, candidate.global_position)
			if score < best_score:
				best_score = score
				best_target = candidate

	return best_target


func _is_valid_target(
	candidate: CharacterBody3D
) -> bool:
	return (
		is_instance_valid(candidate)
		and not candidate.is_queued_for_deletion()
		and _is_active_hostile_candidate(candidate)
	)


func _is_active_hostile_candidate(candidate: CharacterBody3D) -> bool:
	if candidate == null or candidate == self:
		return false
	if candidate.has_method("get_network_state"):
		var network_state := candidate.call("get_network_state") as Dictionary
		if bool(network_state.get("dead", false)):
			return false
	if candidate.is_in_group("wild_animals"):
		return candidate is BlackBear and int((candidate as BlackBear).state) != BlackBear.State.DEAD
	return _is_enemy(candidate)


func _is_inside_vision_cone(candidate: Node3D) -> bool:
	var direction := _horizontal_direction(global_position, candidate.global_position)
	if direction == Vector3.ZERO:
		return true
	if _horizontal_distance(global_position, candidate.global_position) > vision_range:
		return false
	var forward := -global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	return forward.dot(direction) >= cos(deg_to_rad(vision_fov_degrees * 0.5))


func _has_visual_contact(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate):
		return false
	var visible_rays := 0
	for height in [0.38, target_height, 1.55]:
		var destination := candidate.global_position + Vector3.UP * float(height)
		if _vision_ray_reaches_candidate(candidate, destination):
			visible_rays += 1
	# 至少两条确认射线抵达目标，避免只从墙边露出极小部分时被立即锁定。
	return visible_rays >= 2


func _vision_ray_reaches_candidate(candidate: Node3D, destination: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		head.global_position, destination, vision_occlusion_mask, [get_rid()]
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
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return INVALID_POSITION
	if game_world.has_method("get_random_enemy_spawn_position"):
		var value: Variant = game_world.call(
			"get_random_enemy_spawn_position",
			team_id,
			get_instance_id() + int(Time.get_ticks_msec() / 1000.0),
			0
		)
		if value is Vector3 and value != Vector3.INF:
			return value as Vector3
	return INVALID_POSITION


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
		_try_fire_at_target(distance)

	return _direction_to_goal(
		target_position
	)


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
		state = AIState.CHASE
		return _direction_to_goal(
			target_position
		)

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

	## 撤退过程中使用 SuppressedPistol 压制追击者。
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

			_try_fire_weapon(
				WeaponSlot.SUPPRESSED_PISTOL
			)

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

	## 撤退期间自动换成更灵活的消音手枪。
	_equip_weapon(
		WeaponSlot.SUPPRESSED_PISTOL
	)

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

	var desired_slot := WeaponSlot.AR15

	if distance <= pistol_switch_distance:
		desired_slot = (
			WeaponSlot.SUPPRESSED_PISTOL
		)

	if desired_slot == WeaponSlot.AR15:
		if (
			distance < ar15_min_range
			or distance > ar15_max_range
		):
			return

	else:
		if distance > pistol_max_range:
			return

	_try_fire_weapon(desired_slot)


func _try_fire_weapon(slot: int) -> void:
	if fire_timer > 0.0:
		return

	if not _is_valid_target(target_player):
		return

	if not _has_clear_line_to(target_player):
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

	held_weapon.call("emit")
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


# ------------------------------------------------------------------
# Grenade
# ------------------------------------------------------------------

func _try_throw_grenade(
	distance: float
) -> void:
	if grenades_remaining <= 0:
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

	if rng.randf() > grenade_use_chance:
		grenade_timer = 0.45
		return

	var target_position := (
		target_player.global_position
		+ target_player.velocity * 0.30
	)

	if _would_grenade_hurt_friend(
		target_position
	):
		return

	_throw_grenade(target_position)


func _throw_grenade(
	target_position: Vector3
) -> void:
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

	grenades_remaining -= 1
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


func _calculate_grenade_velocity(
	origin: Vector3,
	target: Vector3,
	flight_time: float
) -> Vector3:
	var safe_time := maxf(
		flight_time,
		0.25
	)

	var displacement := target - origin

	var gravity := float(
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

	for group_name in [
		"human_players",
		"combat_characters",
		"future_warrior_ai",
	]:
		for node in get_tree().get_nodes_in_group(
			group_name
		):
			if not node is Node3D:
				continue

			var character := node as Node3D

			if character == self:
				continue

			var instance_id := (
				character.get_instance_id()
			)

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
				< grenade_friendly_safety_radius
			):
				return true

	return false


# ------------------------------------------------------------------
# Navigation and movement
# ------------------------------------------------------------------

func _direction_to_goal(
	goal: Vector3
) -> Vector3:
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
		or not _navigation_map_is_ready()
	):
		return direct_direction

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

	if navigation_direction == Vector3.ZERO:
		return direct_direction

	return navigation_direction


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
	delta: float
) -> void:
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

	rubber_knockback = (
		rubber_knockback.move_toward(
			Vector3.ZERO,
			18.0 * delta
		)
	)

	velocity.x = move_toward(
		velocity.x,
		desired_velocity.x,
		acceleration * delta
	)

	velocity.z = move_toward(
		velocity.z,
		desired_velocity.z,
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

	_update_character_animation(
		direction
	)


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
		"state": int(state),
	}


func apply_network_state(data: Dictionary) -> void:
	global_position = data.get("position", global_position) as Vector3
	rotation.y = float(data.get("yaw", rotation.y))
	current_hp = float(data.get("hp", current_hp))
	if data.has("state"):
		state = int(data.get("state", state))
	_update_team_marker_visibility()
	if health_label != null:
		health_label.visible = not bool(data.get("dead", false))
		_update_health_label()


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
			[get_rid()]
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

	impact(
		effect,
		damage,
		shooter_team,
		hit_direction
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
	hit_direction: Vector3 = Vector3.ZERO
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

	_apply_damage(
		damage,
		effect,
		attacker_team,
		hit_direction
	)

	return true


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
	hit_direction: Vector3
) -> void:
	current_hp = maxf(
		0.0,
		current_hp - damage
	)

	recent_damage += damage
	damage_memory_timer = (
		damage_memory_seconds
	)

	if hit_direction.length_squared() > 0.001:
		last_damage_source_position = (
			global_position
			- hit_direction.normalized()
			* 3.0
		)

	elif _is_valid_target(target_player):
		last_damage_source_position = (
			target_player.global_position
		)

	_remember_retaliation_target(attacker_team, hit_direction)

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


func _remember_retaliation_target(attacker_team: String, hit_direction: Vector3) -> void:
	var expected_position := global_position
	if hit_direction.length_squared() > 0.001:
		expected_position -= hit_direction.normalized() * vision_range

	var closest: CharacterBody3D
	var closest_distance := INF
	for group_name in [&"human_players", &"wild_animals"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			if not _is_active_hostile_candidate(candidate):
				continue
			if not attacker_team.is_empty() and _get_combat_team(candidate) != attacker_team:
				continue
			var distance := candidate.global_position.distance_to(expected_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance

	if closest != null:
		retaliation_target = closest
		retaliation_timer = 5.0


func _update_health_label() -> void:
	if health_label == null:
		return

	health_label.visible = show_health_label

	health_label.text = (
		"Future Warrior  %d / %d\n"
		+ "AR15 · Pistol · Grenade x%d"
	) % [
		roundi(current_hp),
		roundi(max_hp),
		grenades_remaining,
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
	if not attacker_team.is_empty() and (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		GameAuthority.award_future_warrior_defeat(attacker_team, team_id)
	velocity = Vector3.ZERO
	rubber_knockback = Vector3.ZERO
	action_animation_locked = true
	_play_body_animation(&"DeathFallForward", 0.08)

	collision_layer = 0
	collision_mask = 0

	if hit_3d != null:
		hit_3d.monitoring = false
		hit_3d.monitorable = false
		hit_3d.collision_layer = 0
		hit_3d.collision_mask = 0

	if body_collision_shape != null:
		body_collision_shape.set_deferred(
			"disabled",
			true
		)

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

	_debug("killed by=%s effect=%s; respawning in %.1f seconds" % [
		attacker_team, effect, respawn_seconds,
	])

	call_deferred(
		"_finish_death"
	)


func _finish_death() -> void:
	await get_tree().create_timer(
		respawn_seconds
	).timeout
	if not is_inside_tree() or state != AIState.DEAD:
		return
	_respawn_at_team_spawn()


func _respawn_at_team_spawn() -> void:
	var spawn_position := _get_team_respawn_position()
	global_position = spawn_position
	velocity = Vector3.ZERO
	rubber_knockback = Vector3.ZERO
	current_hp = max_hp
	grenades_remaining = starting_grenade_count
	target_player = null
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
