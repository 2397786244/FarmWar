extends CharacterBody3D
class_name AIPlayer

## ============================================================
## Food-War 农场 AI
##
## 功能：
## - 不依赖 NavigationRegion3D / NavigationAgent3D。
## - 运行时自动创建原 tscn 中需要的所有子节点：
##   Head、UpperBodyLookTarget、RightHandIKTarget、CollisionShape3D、
##   RightHandSocket、ToolPivot、RightElbowPole、RayCast3D、
##   LookAtTarget、FrontProbe、Hit3D、HealthLabel3D。
## - 不使用 Eater、不使用任何 remote 工具。
## - 只使用：
##   NailGun、Revolver、FlameGun、FreezeGun、Wand、
##   AutoShooter、ShieldDoor、AntiAir（一次）、FarmRunner（一次）。
## - 开局优先在己方空 FarmTile 放置 FarmRunner，交给 FarmRunner 自动播种/收获。
## - 建造防御：FarmRunner -> AntiAir(一次) -> ShieldDoor -> AutoShooter。
## - 攻击敌方 FarmTile / 敌方玩家：射钉枪、左轮、火焰枪、冰冻枪、魔杖。
## - 检测到敌方 NormalDrone 或 BoomBuggy 后，优先撤离。
## - 200 HP，头顶 Label3D 显示当前生命。
## ============================================================


enum Difficulty {
	EASY,
	HARD,
}

enum AIState {
	THINK,
	MOVE_TO_PLACE,
	PLACE,
	MOVE_TO_ATTACK,
	ATTACK,
	PATROL,
	FLEE,
	DEAD,
}

enum PlaceTool {
	NONE,
	FARM_RUNNER,
	ANTI_AIR,
	SHIELD,
	AUTO_SHOOTER,
}

const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"
const INVALID_POSITION := Vector3(INF, INF, INF)
const DEFAULT_TILE_SPACING := 2.2

const ALLOWED_TOOL_IDS := {
	"nail_gun": true,
	"rubber_revolver": true,
	"flame_gun": true,
	"freeze_gun": true,
	"wand": true,
	"auto_shooter": true,
	"shield_door": true,
	"anti_air": true,
	"farm_runner": true,
}

const PLACE_TOOL_SCENE_NAMES := {
	PlaceTool.FARM_RUNNER: "FarmRunner",
	PlaceTool.ANTI_AIR: "AntiAir",
	PlaceTool.SHIELD: "ShieldDoor",
	PlaceTool.AUTO_SHOOTER: "AutoShooter",
}


@export_category("Identity")
@export_enum("简单", "困难") var difficulty: int = Difficulty.HARD
@export var selected_hero: String = "farmer"
@export var team_id: String = "blue"

@export_category("Health")
@export var max_hp: float = 200.0
@export var bullet_damage: float = 12.0
@export var color_bullet_damage: float = 15.0
@export var explosion_damage_multiplier: float = 1.0

@export_category("Movement")
@export var movement_enabled: bool = true
@export var easy_move_speed: float = 3.6
@export var hard_move_speed: float = 5.2
@export var easy_move_acceleration: float = 13.0
@export var hard_move_acceleration: float = 20.0
@export var jump_velocity_easy: float = 3.0
@export var jump_velocity_hard: float = 3.8

@export_category("Combat")
@export var player_detection_range: float = 18.0
@export var attack_standoff_distance: float = 9.0
@export var combat_ray_mask: int = 138
@export var print_decisions: bool = false

@export_category("Remote Threat Avoidance")
@export var remote_threat_range: float = 13.0
@export var remote_scan_interval: float = 0.35
@export var flee_distance: float = 9.0
@export var flee_minimum_seconds: float = 2.0

@export_category("Build Limits")
@export_range(0, 6, 1) var shield_limit: int = 3
@export_range(0, 6, 1) var auto_shooter_limit: int = 3

@export_category("FarmTile Discovery")
## 管理器未注册地块时，AI 会从当前场景递归扫描 FarmTile。
@export_range(0.2, 10.0, 0.1) var farm_tile_rescan_interval: float = 1.0
@export var print_farm_discovery: bool = true

## 仅当 Farmlandmanager 明确把无主地块列入 get_claimable_plots(team_id)
## 时，AI 才会将无主地块作为首次部署 FarmRunner / 防御设施的候选。
@export var allow_claimable_tiles_for_initial_build: bool = true

@export_category("Farm Startup Gate")
## 没有找到己方 FarmTile 时，AI 停在出生点并按此间隔重试。
@export_range(0.1, 5.0, 0.1) var farm_wait_retry_interval: float = 0.5

## 等待农田初始化期间，多久输出一次状态日志。
@export_range(0.5, 10.0, 0.5) var farm_wait_log_interval: float = 2.0


# ------------------------------------------------------------------
# Runtime-created nodes. Do not replace these with @onready:
# the script must also work on an otherwise empty CharacterBody3D root.
# ------------------------------------------------------------------

var head: Node3D
var upper_body_look_target: Marker3D
var right_hand_ik_target: Marker3D
var main_collision_shape: CollisionShape3D
var right_hand_socket: BoneAttachment3D
var tool_socket: Node3D
var right_elbow_pole: Marker3D
var aim_ray: RayCast3D
var look_at_target: RayCast3D
var front_probe: RayCast3D
var hit_3d: Area3D
var hit_collision_shape: CollisionShape3D
var health_label: Label3D

## FarmTile 缓存：管理器数据优先，场景扫描作为兜底。
var cached_farm_tiles: Array[Node3D] = []
var farm_tile_rescan_timer: float = 0.0
var farm_discovery_has_logged: bool = false

## 启动门控：在找到己方或合法可认领 FarmTile 前，AI 不会做任何决策。
var farm_ready := false
var farm_wait_retry_timer := 0.0
var farm_wait_log_timer := 0.0


# ------------------------------------------------------------------
# Appearance / animation
# ------------------------------------------------------------------

var appearance_player: AnimationPlayer
var skeleton: Skeleton3D
var upper_body_look_modifiers: Array[LookAtModifier3D] = []
var upper_body_look_weights: Array[float] = []
var right_arm_ik: TwoBoneIK3D
var hand_aim_look: LookAtModifier3D
var action_anim_locked := false
var was_on_floor := true
var landing_animation := false


# ------------------------------------------------------------------
# Tool runtime
# ------------------------------------------------------------------

var tool_definitions_by_id: Dictionary = {}
var tool_cooldowns: Dictionary = {}
var current_tool_id := ""
var held_tool: Node3D

var farm_runner_placed := false
var anti_air_placed := false


# ------------------------------------------------------------------
# AI runtime
# ------------------------------------------------------------------

var current_hp: float = 0.0
var state: int = AIState.THINK
var think_timer := 0.0
var state_timer := 0.0
var jump_timer := 0.0
var remote_scan_timer := 0.0
var flee_timer := 0.0

var target_plot: Node3D
var target_player: CharacterBody3D
var target_world_position := INVALID_POSITION
var movement_target := INVALID_POSITION
var patrol_target := INVALID_POSITION
var pending_place_tool: int = PlaceTool.NONE

var remote_threat: Node3D
var rubber_knockback := Vector3.ZERO
var rng := RandomNumberGenerator.new()
var combat_cycle_index := 0

var last_goal_distance := INF
var stuck_time := 0.0
const STUCK_TIMEOUT := 1.6
const STUCK_PROGRESS_EPSILON := 0.04


func _ready() -> void:
	rng.randomize()
	current_hp = max_hp

	_create_required_runtime_nodes()
	add_to_group("farmer_ai")

	# 当前场景可能在 AI _ready 之后才完成注册，因此立即扫一次，
	# 并在下一帧再扫一次，确保 FarmTile 一定能被发现。
	_refresh_farm_tile_cache(true)
	call_deferred("_refresh_farm_tile_cache", true)

	if not _load_allowed_tool_definitions():
		set_physics_process(false)
		return

	_set_ai_appearance(selected_hero, team_id)
	_sync_existing_one_time_tools()
	_update_health_label()

	# 即使 AI 比 FarmTile / Farmlandmanager 更早 ready，也不会误判地图没有土地。
	# 后续 _physics_process 会持续重试，直到发现己方或合法可认领地块。
	farm_ready = _has_initialized_farm()

	if farm_ready:
		print("[WreckAI] Farm ready at startup. AI decision loop started.")
		_schedule_think(0.15)
	else:
		state = AIState.THINK
		movement_target = INVALID_POSITION
		print(
			"[WreckAI] Waiting for farm initialization. "
			+ "No owned or claimable FarmTile found yet."
		)


func _create_required_runtime_nodes() -> void:
	# Preserve the collision setup from the supplied tscn.
	collision_layer = 8
	collision_mask = 519

	head = _ensure_node3d(self, "Head")
	head.position = Vector3(0.0, 1.7080579, -0.45418245)

	upper_body_look_target = _ensure_marker3d(
		head,
		"UpperBodyLookTarget"
	)
	upper_body_look_target.position = Vector3(0.0, 0.0, -3.0)

	right_hand_ik_target = _ensure_marker3d(
		head,
		"RightHandIKTarget"
	)
	right_hand_ik_target.position = Vector3(0.28, -0.28, -0.42)

	main_collision_shape = _ensure_collision_shape(
		self,
		"CollisionShape3D",
		Vector3(0.0, 0.8465799, -0.01983869),
		0.34,
		1.70
	)

	right_hand_socket = _ensure_bone_attachment(
		self,
		"RightHandSocket"
	)
	right_hand_socket.bone_name = "Hand.R"

	tool_socket = _ensure_node3d(
		right_hand_socket,
		"ToolPivot"
	)

	right_elbow_pole = _ensure_marker3d(
		self,
		"RightElbowPole"
	)
	right_elbow_pole.position = Vector3(0.65, 1.2, -0.1)

	aim_ray = _ensure_raycast3d(self, "RayCast3D")
	aim_ray.position = Vector3(0.0, 1.4506165, 0.0)
	aim_ray.target_position = Vector3(0.0, 0.0, -15.0)
	aim_ray.collision_mask = combat_ray_mask
	aim_ray.enabled = true

	# Compatibility ray: FarmRunner and several tool scenes search their
	# owning player for a node named LookAtTarget.
	look_at_target = _ensure_raycast3d(self, "LookAtTarget")
	look_at_target.position = Vector3(0.0, 1.4506165, 0.0)
	look_at_target.target_position = Vector3(0.0, 0.0, -100.0)
	look_at_target.collision_mask = combat_ray_mask
	look_at_target.enabled = true

	front_probe = _ensure_raycast3d(self, "FrontProbe")
	front_probe.position = Vector3(0.0, 0.8, 0.0)
	front_probe.target_position = Vector3(0.0, 0.0, -1.6)
	front_probe.collision_mask = 6
	front_probe.enabled = true

	hit_3d = _ensure_area3d(self, "Hit3D")
	hit_3d.collision_layer = 0
	hit_3d.collision_mask = 32
	hit_3d.monitoring = true
	hit_3d.monitorable = true

	hit_collision_shape = _ensure_collision_shape(
		hit_3d,
		"CollisionShape3D",
		Vector3(0.0, 0.8376303, 0.0),
		0.38,
		1.72
	)

	if not hit_3d.body_entered.is_connected(
		_on_hit_3d_body_entered
	):
		hit_3d.body_entered.connect(_on_hit_3d_body_entered)

	if not hit_3d.area_entered.is_connected(
		_on_hit_3d_area_entered
	):
		hit_3d.area_entered.connect(_on_hit_3d_area_entered)

	health_label = _ensure_health_label(self, "HealthLabel3D")
	health_label.position = Vector3(0.0, 2.65, 0.0)


func _ensure_node3d(parent: Node, node_name: String) -> Node3D:
	var existing := parent.get_node_or_null(node_name) as Node3D
	if existing != null:
		return existing

	var created := Node3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_marker3d(parent: Node, node_name: String) -> Marker3D:
	var existing := parent.get_node_or_null(node_name) as Marker3D
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
	var existing := parent.get_node_or_null(node_name) as BoneAttachment3D
	if existing != null:
		return existing

	var created := BoneAttachment3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_raycast3d(parent: Node, node_name: String) -> RayCast3D:
	var existing := parent.get_node_or_null(node_name) as RayCast3D
	if existing != null:
		return existing

	var created := RayCast3D.new()
	created.name = node_name
	created.exclude_parent = true
	parent.add_child(created)
	return created


func _ensure_area3d(parent: Node, node_name: String) -> Area3D:
	var existing := parent.get_node_or_null(node_name) as Area3D
	if existing != null:
		return existing

	var created := Area3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_collision_shape(
	parent: Node,
	node_name: String,
	local_position: Vector3,
	radius: float,
	height: float
) -> CollisionShape3D:
	var created_or_existing := (
		parent.get_node_or_null(node_name) as CollisionShape3D
	)

	if created_or_existing == null:
		created_or_existing = CollisionShape3D.new()
		created_or_existing.name = node_name
		parent.add_child(created_or_existing)

	created_or_existing.position = local_position

	var capsule := created_or_existing.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		created_or_existing.shape = capsule

	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0 + 0.01)
	return created_or_existing


func _ensure_health_label(parent: Node, node_name: String) -> Label3D:
	var existing := parent.get_node_or_null(node_name) as Label3D
	if existing != null:
		return existing

	var created := Label3D.new()
	created.name = node_name
	created.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	created.no_depth_test = false
	created.font_size = 56
	created.outline_size = 10
	created.modulate = Color("#F5F7FA")
	created.outline_modulate = Color("#111722")
	parent.add_child(created)
	return created


# ------------------------------------------------------------------
# Tool configuration
# ------------------------------------------------------------------

func _load_allowed_tool_definitions() -> bool:
	tool_definitions_by_id.clear()
	tool_cooldowns.clear()

	if not FileAccess.file_exists(TOOL_CONFIG_PATH):
		push_error("[WreckAI] Tool JSON missing: %s" % TOOL_CONFIG_PATH)
		return false

	var file := FileAccess.open(TOOL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[WreckAI] Could not open tool JSON.")
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error(
			"[WreckAI] Tool JSON parse error line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false

	if not json.data is Dictionary:
		push_error("[WreckAI] Tool JSON root must be Dictionary.")
		return false

	var source_tools: Variant = json.data.get("tools", [])
	if not source_tools is Array:
		push_error("[WreckAI] JSON field tools must be Array.")
		return false

	for entry: Variant in source_tools:
		if not entry is Dictionary:
			continue

		var definition: Dictionary = (entry as Dictionary).duplicate(true)
		var tool_id := str(definition.get("id", ""))

		if not ALLOWED_TOOL_IDS.has(tool_id):
			continue

		if not definition.has("path"):
			push_warning(
				"[WreckAI] Skipped allowed tool without path: %s"
				% tool_id
			)
			continue

		definition["grip_position"] = _json_to_vector3(
			definition.get("grip_position", []),
			Vector3.ZERO
		)
		definition["grip_rotation"] = _json_to_vector3(
			definition.get("grip_rotation", []),
			Vector3.ZERO
		)
		definition["grip_scale"] = _json_to_vector3(
			definition.get("grip_scale", []),
			Vector3.ONE
		)

		tool_definitions_by_id[tool_id] = definition
		tool_cooldowns[tool_id] = 0.0

	var required_ids := [
		"nail_gun",
		"rubber_revolver",
		"flame_gun",
		"freeze_gun",
		"wand",
		"auto_shooter",
		"shield_door",
		"anti_air",
		"farm_runner",
	]

	for required_id in required_ids:
		if not tool_definitions_by_id.has(required_id):
			push_error(
				"[WreckAI] Required AI tool missing from JSON: %s"
				% required_id
			)
			return false

	print(
		"[WreckAI] Loaded allowed tools: ",
		tool_definitions_by_id.keys()
	)
	return true


func _json_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array or value.size() < 3:
		return fallback

	return Vector3(
		float(value[0]),
		float(value[1]),
		float(value[2])
	)


func _equip_tool(tool_id: String) -> bool:
	if not tool_definitions_by_id.has(tool_id):
		push_warning("[WreckAI] Tool not allowed / unavailable: %s" % tool_id)
		return false

	if current_tool_id == tool_id and is_instance_valid(held_tool):
		return true

	if is_instance_valid(held_tool):
		held_tool.queue_free()
		held_tool = null

	var definition: Dictionary = tool_definitions_by_id[tool_id]
	var scene := load(str(definition.get("path", ""))) as PackedScene
	if scene == null:
		push_error(
			"[WreckAI] Cannot load tool scene: %s"
			% definition.get("path", "")
		)
		return false

	held_tool = scene.instantiate() as Node3D
	if held_tool == null:
		push_error("[WreckAI] Tool scene root is not Node3D: %s" % tool_id)
		return false

	tool_socket.add_child(held_tool)
	held_tool.position = definition.get("grip_position", Vector3.ZERO)
	held_tool.rotation_degrees = definition.get(
		"grip_rotation",
		Vector3.ZERO
	)
	held_tool.scale = definition.get("grip_scale", Vector3.ONE)
	held_tool.set("tool_owner", team_id)

	current_tool_id = tool_id
	return true


func _tool_ready(tool_id: String) -> bool:
	return float(tool_cooldowns.get(tool_id, 0.0)) <= 0.0


func _set_tool_cooldown(tool_id: String) -> void:
	if not tool_definitions_by_id.has(tool_id):
		return

	var definition: Dictionary = tool_definitions_by_id[tool_id]
	var base_cooldown := float(definition.get("cooldown", 1.0))
	var difficulty_multiplier := 1.30 if difficulty == Difficulty.EASY else 0.90
	tool_cooldowns[tool_id] = base_cooldown * difficulty_multiplier


func _update_tool_cooldowns(delta: float) -> void:
	for key: Variant in tool_cooldowns.keys():
		var tool_id := str(key)
		tool_cooldowns[tool_id] = maxf(
			0.0,
			float(tool_cooldowns[tool_id]) - delta
		)


# ------------------------------------------------------------------
# Main AI loop
# ------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	if state == AIState.DEAD:
		return

	# 农田未初始化时，AI 不建造、不攻击、不巡逻离开出生点。
	# 仍执行无方向移动，保证角色重力与 CharacterBody3D 碰撞正常。
	if not farm_ready:
		_update_farm_waiting(delta)
		_apply_movement(Vector3.ZERO, delta)
		return

	_update_timers(delta)
	_scan_for_remote_threat(delta)

	if is_instance_valid(remote_threat):
		_begin_or_refresh_flee(remote_threat)

	_update_state(delta)
	_update_movement(delta)


func _update_farm_waiting(delta: float) -> void:
	farm_wait_retry_timer = maxf(
		0.0,
		farm_wait_retry_timer - delta
	)
	farm_wait_log_timer = maxf(
		0.0,
		farm_wait_log_timer - delta
	)

	if farm_wait_retry_timer > 0.0:
		return

	farm_wait_retry_timer = farm_wait_retry_interval

	# 强制刷新场景扫描缓存：
	# 即使 Farmlandmanager 晚几秒注册，或 ChunkMap 晚加载，
	# AI 也会在这里重新发现真实 FarmTile。
	_refresh_farm_tile_cache(false)

	if _has_initialized_farm():
		farm_ready = true

		# 避免等待期间另一个实体已经放置 FarmRunner / AntiAir，
		# 当前 AI 启动后会正确继承“一次性工具已使用”状态。
		_sync_existing_one_time_tools()

		print(
			"[WreckAI] Farm initialization detected. "
			+ "owned=%d claimable=%d cached_total=%d. Starting AI."
			% [
				_get_team_plots(team_id).size(),
				_get_claimable_plots_for_team(team_id).size(),
				cached_farm_tiles.size(),
			]
		)

		_schedule_think(0.20)
		return

	if farm_wait_log_timer <= 0.0:
		farm_wait_log_timer = farm_wait_log_interval

		print(
			"[WreckAI] Still waiting for farm. "
			+ "owned=%d claimable=%d cached_total=%d"
			% [
				_get_team_plots(team_id).size(),
				_get_claimable_plots_for_team(team_id).size(),
				cached_farm_tiles.size(),
			]
		)


func _has_initialized_farm() -> bool:
	# 如果已经检测到己方 FarmRunner，则 AI 可以继续布防和攻击。
	if farm_runner_placed:
		return true

	# 正常情况：已有明确归属的己方 FarmTile。
	var owned_plots := _get_team_plots(team_id)
	if not owned_plots.is_empty():
		return true

	# 开局仍为无主地时，只接收 Farmlandmanager 明确允许认领的地块。
	# 不会将敌方 land_owner 误判为己方土地。
	var claimable_plots := _get_claimable_plots_for_team(team_id)
	if not claimable_plots.is_empty():
		return true

	return false


func _update_timers(delta: float) -> void:
	_update_tool_cooldowns(delta)
	think_timer = maxf(0.0, think_timer - delta)
	state_timer = maxf(0.0, state_timer - delta)
	jump_timer = maxf(0.0, jump_timer - delta)
	remote_scan_timer = maxf(0.0, remote_scan_timer - delta)
	flee_timer = maxf(0.0, flee_timer - delta)

	farm_tile_rescan_timer = maxf(0.0, farm_tile_rescan_timer - delta)
	if farm_tile_rescan_timer <= 0.0:
		_refresh_farm_tile_cache(false)


func _update_state(_delta: float) -> void:
	match state:
		AIState.THINK:
			if think_timer <= 0.0:
				_choose_action()

		AIState.MOVE_TO_PLACE:
			if not _is_valid_plot(target_plot):
				_schedule_think(0.15)
			elif _has_reached_plot(target_plot, 2.7):
				state = AIState.PLACE
				state_timer = 0.12

		AIState.PLACE:
			if state_timer <= 0.0:
				_execute_placement()
				_schedule_think(0.25)

		AIState.MOVE_TO_ATTACK:
			if not _has_valid_attack_target():
				_schedule_think(0.18)
			elif _horizontal_distance(global_position, movement_target) <= 0.9:
				state = AIState.ATTACK
				state_timer = 0.10

		AIState.ATTACK:
			if state_timer <= 0.0:
				_attack_current_target()
				state_timer = 0.12 if difficulty == Difficulty.HARD else 0.28

		AIState.PATROL:
			if (
				patrol_target == INVALID_POSITION
				or _horizontal_distance(global_position, patrol_target) <= 0.75
				or state_timer <= 0.0
			):
				_schedule_think(0.10)

		AIState.FLEE:
			if not is_instance_valid(remote_threat) and flee_timer <= 0.0:
				_schedule_think(0.10)
			elif _horizontal_distance(global_position, movement_target) <= 0.9:
				# Re-evaluate flee direction while danger remains visible.
				if is_instance_valid(remote_threat):
					_begin_or_refresh_flee(remote_threat)
				else:
					_schedule_think(0.10)


func _choose_action() -> void:
	target_plot = null
	target_player = null
	target_world_position = INVALID_POSITION
	movement_target = INVALID_POSITION
	pending_place_tool = PlaceTool.NONE

	# 最高优先级：FarmRunner 只要还没放，就在己方空地放一次。
	if not farm_runner_placed:
		var runner_tile := _choose_farm_runner_tile()
		if runner_tile != null:
			_begin_place_action(PlaceTool.FARM_RUNNER, runner_tile)
			return

	# 第二优先级：仅放置一次防空车。
	if not anti_air_placed:
		var anti_air_tile := _choose_backline_defence_tile()
		if anti_air_tile != null:
			_begin_place_action(PlaceTool.ANTI_AIR, anti_air_tile)
			return

	# 然后建立护盾和炮塔的组合。
	if _count_own_tool("Shield") < shield_limit:
		var shield_tile := _choose_shield_tile()
		if shield_tile != null:
			_begin_place_action(PlaceTool.SHIELD, shield_tile)
			return

	if _count_own_tool("AutoShooter") < auto_shooter_limit:
		var shooter_tile := _choose_auto_shooter_tile()
		if shooter_tile != null:
			_begin_place_action(PlaceTool.AUTO_SHOOTER, shooter_tile)
			return

	# 先优先攻击检测范围内敌方玩家。
	var enemy_player := _find_visible_enemy_player()
	if enemy_player != null:
		target_player = enemy_player
		target_world_position = (
			enemy_player.global_position + Vector3.UP * 0.9
		)
		movement_target = _make_attack_standoff_position(
			enemy_player.global_position
		)
		state = AIState.MOVE_TO_ATTACK
		state_timer = 5.0
		_debug_decision("attack_enemy_player")
		return

	# 没有可见玩家时，攻击对方种植地或其设施。
	var enemy_plot := _choose_enemy_attack_plot()
	if enemy_plot != null:
		target_plot = enemy_plot
		target_world_position = enemy_plot.global_position + Vector3.UP * 0.35
		movement_target = _make_attack_standoff_position(
			enemy_plot.global_position
		)
		state = AIState.MOVE_TO_ATTACK
		state_timer = 6.0
		_debug_decision("attack_enemy_farm")
		return

	_start_patrol()


func _begin_place_action(place_tool: int, tile: Node3D) -> void:
	pending_place_tool = place_tool
	target_plot = tile
	movement_target = _approach_position(tile.global_position, 2.0)
	state = AIState.MOVE_TO_PLACE
	state_timer = 7.0
	_debug_decision("place_%s" % _place_tool_name(place_tool))


func _execute_placement() -> void:
	if not _is_valid_plot(target_plot):
		return

	var tool_id := _tool_id_for_place_tool(pending_place_tool)
	if tool_id.is_empty():
		return

	if not _tool_ready(tool_id):
		return

	var scene_tool_name := str(
		PLACE_TOOL_SCENE_NAMES.get(pending_place_tool, "")
	)
	if scene_tool_name.is_empty():
		return

	# FarmTile.setting_tool() 是真正的部署入口：
	# 会把工具作为 FarmTile 的 tool_child 创建，FarmRunner 也会从这个 Tile 启动。
	if not _equip_tool(tool_id):
		return

	_aim_tool(target_plot.global_position + Vector3.UP * 0.25)
	_set_tool_action(tool_id)

	var placement_result: Variant = target_plot.call(
		"setting_tool",
		scene_tool_name,
		team_id,
		self
	)

	var success := true
	if placement_result is bool:
		success = placement_result as bool

	var placed_child: Node = target_plot.get("tool_child")
	if not is_instance_valid(placed_child) and placement_result == null:
		# setting_tool() 在旧版本中可能没有返回值；
		# 若同帧工具尚未建立，仍避免无限重复放置。
		success = true

	if not success:
		return

	_set_tool_cooldown(tool_id)

	match pending_place_tool:
		PlaceTool.FARM_RUNNER:
			farm_runner_placed = true
		PlaceTool.ANTI_AIR:
			anti_air_placed = true

	_debug_decision("placed_%s" % scene_tool_name)


func _attack_current_target() -> void:
	if not _has_valid_attack_target():
		_schedule_think(0.15)
		return

	var aim_position := _get_current_attack_position()
	if aim_position == INVALID_POSITION:
		_schedule_think(0.15)
		return

	var selected_tool := _choose_combat_tool(aim_position)
	if selected_tool.is_empty():
		return

	if not _tool_ready(selected_tool):
		return

	if not _equip_tool(selected_tool):
		return

	_aim_tool(aim_position)

	if not held_tool.has_method("emit"):
		push_warning(
			"[WreckAI] Selected tool has no emit(): %s"
			% selected_tool
		)
		return

	held_tool.call("emit")
	_set_tool_action(selected_tool)
	_set_tool_cooldown(selected_tool)

	if print_decisions:
		print(
			"[WreckAI] fired ",
			selected_tool,
			" at ",
			aim_position
		)


func _choose_combat_tool(aim_position: Vector3) -> String:
	var distance := global_position.distance_to(aim_position)

	# 所有允许的攻击工具都会轮换出现；
	# 近距离优先火焰/冰冻，中距离偏左轮，远距离偏射钉枪，
	# 魔杖每轮周期会获得一次优先机会。
	var ordered: Array[String] = []

	if combat_cycle_index % 5 == 4:
		ordered.append("wand")

	if distance <= 6.5:
		ordered.append_array([
			"flame_gun",
			"freeze_gun",
			"rubber_revolver",
			"nail_gun",
			"wand",
		])
	elif distance <= 12.0:
		ordered.append_array([
			"freeze_gun",
			"rubber_revolver",
			"nail_gun",
			"wand",
			"flame_gun",
		])
	else:
		ordered.append_array([
			"nail_gun",
			"rubber_revolver",
			"freeze_gun",
			"wand",
			"flame_gun",
		])

	combat_cycle_index = (combat_cycle_index + 1) % 5

	var seen: Dictionary = {}
	for tool_id in ordered:
		if seen.has(tool_id):
			continue
		seen[tool_id] = true

		if tool_definitions_by_id.has(tool_id) and _tool_ready(tool_id):
			return tool_id

	return ""


# ------------------------------------------------------------------
# Placement selection
# ------------------------------------------------------------------

func _choose_farm_runner_tile() -> Node3D:
	var candidates := _get_own_empty_plots()
	if candidates.is_empty():
		return null

	# 优先后方/边缘地块，避免占据前线护盾位。
	var best: Node3D
	var best_score := INF

	for tile in candidates:
		var score := _horizontal_distance(global_position, tile.global_position)
		score += _frontline_penalty(tile.global_position) * 3.0
		score += absf(tile.global_position.x) * 0.05

		if score < best_score:
			best_score = score
			best = tile

	return best


func _choose_backline_defence_tile() -> Node3D:
	var candidates := _get_own_empty_plots()
	if candidates.is_empty():
		return null

	var backline_z := _backline_z(_get_team_plots(team_id))
	var best: Node3D
	var best_score := INF

	for tile in candidates:
		var score := absf(tile.global_position.z - backline_z) * 5.0
		score += absf(tile.global_position.x) * 0.3
		score += _horizontal_distance(global_position, tile.global_position) * 0.02

		if score < best_score:
			best_score = score
			best = tile

	return best


func _choose_shield_tile() -> Node3D:
	var candidates := _get_own_empty_plots()
	if candidates.is_empty():
		return null

	var frontline_z := _frontline_z(_get_team_plots(team_id))
	var desired_xs := _desired_defence_xs()
	var best: Node3D
	var best_score := INF

	for tile in candidates:
		if absf(tile.global_position.z - frontline_z) > 0.45:
			continue

		var x_score := INF
		for desired_x in desired_xs:
			x_score = minf(
				x_score,
				absf(tile.global_position.x - desired_x)
			)

		var score := x_score + _horizontal_distance(
			global_position,
			tile.global_position
		) * 0.01

		if score < best_score:
			best_score = score
			best = tile

	return best


func _choose_auto_shooter_tile() -> Node3D:
	var candidates := _get_own_empty_plots()
	if candidates.is_empty():
		return null

	var shields := _get_own_tool_plots("Shield")
	var behind_sign := -1.0 if team_id == "blue" else 1.0
	var spacing := _farm_spacing()

	var best: Node3D
	var best_score := INF

	for tile in candidates:
		var score := INF

		for shield_tile in shields:
			var desired := shield_tile.global_position + Vector3(
				0.0,
				0.0,
				behind_sign * spacing
			)

			score = minf(
				score,
				_horizontal_distance(tile.global_position, desired)
			)

		if is_inf(score):
			# 没有可用护盾时放在后方中央。
			score = absf(tile.global_position.x) * 0.35
			score += _frontline_penalty(tile.global_position) * 2.0

		score += _horizontal_distance(
			global_position,
			tile.global_position
		) * 0.01

		if score < best_score:
			best_score = score
			best = tile

	return best


func _desired_defence_xs() -> Array[float]:
	if difficulty == Difficulty.EASY:
		return [0.0]

	return [0.0, -8.8, 8.8]


func _get_own_empty_plots() -> Array[Node3D]:
	var result: Array[Node3D] = []

	# 有己方地块时只在己方地块中部署；
	# 开局没有 owner 时，才使用管理器明确给出的 claimable 地块。
	for item in _get_buildable_plots_for_team(team_id):
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D
		if _plot_accepts_tool(tile):
			result.append(tile)

	return result


func _get_own_tool_plots(name_part: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var expected := name_part.to_lower()

	for item in _get_team_plots(team_id):
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D
		var child: Node = tile.get("tool_child")

		if not is_instance_valid(child):
			continue

		if _node_identity_text(child).contains(expected):
			result.append(tile)

	return result


func _count_own_tool(name_part: String) -> int:
	return _get_own_tool_plots(name_part).size()


func _sync_existing_one_time_tools() -> void:
	for item in _get_team_plots(team_id):
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D
		var child: Node = tile.get("tool_child")
		if not is_instance_valid(child):
			continue

		var identity := _node_identity_text(child)
		if identity.contains("farmrunner"):
			farm_runner_placed = true
		elif identity.contains("antiair"):
			anti_air_placed = true


# ------------------------------------------------------------------
# Enemy selection / remote threat detection
# ------------------------------------------------------------------

func _find_visible_enemy_player() -> CharacterBody3D:
	var nearest: CharacterBody3D
	var nearest_distance := player_detection_range

	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is CharacterBody3D:
			continue

		var player := node as CharacterBody3D
		if not is_instance_valid(player):
			continue

		if _get_combat_team(player) == team_id:
			continue

		var distance := global_position.distance_to(player.global_position)
		if distance > nearest_distance:
			continue

		if not _has_clear_line_to(player):
			continue

		nearest = player
		nearest_distance = distance

	return nearest


func _choose_enemy_attack_plot() -> Node3D:
	var best: Node3D
	var best_score := -INF

	for item in _get_team_plots(_enemy_team_id()):
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D
		var seed_record := str(tile.get("seed_record"))
		var tool_child: Node = tile.get("tool_child")

		if seed_record.is_empty() and not is_instance_valid(tool_child):
			continue

		var score := 1.0

		if bool(tile.get("can_harvest")):
			score += 4.0

		if is_instance_valid(tool_child):
			score += 5.0

		score -= _horizontal_distance(
			global_position,
			tile.global_position
		) * 0.03

		if score > best_score:
			best_score = score
			best = tile

	return best


func _scan_for_remote_threat(delta: float) -> void:
	if remote_scan_timer > 0.0:
		return

	remote_scan_timer = remote_scan_interval
	remote_threat = _find_nearest_hostile_remote()


func _find_nearest_hostile_remote() -> Node3D:
	var candidates: Array[Node] = []

	# 已规范加组的远程单位会优先从组中读取。
	for group_name in [
		"remote_units",
		"remote_devices",
		"normal_drones",
		"boom_buggies",
	]:
		for node in get_tree().get_nodes_in_group(group_name):
			candidates.append(node)

	# 项目现有远程工具没有强制 group 时，低频递归扫描当前场景。
	var current_scene := get_tree().current_scene
	if current_scene != null:
		_collect_possible_remote_nodes(current_scene, candidates)

	var nearest: Node3D
	var nearest_distance := remote_threat_range

	var visited: Dictionary = {}
	for candidate: Node in candidates:
		if not is_instance_valid(candidate):
			continue

		var candidate_id := candidate.get_instance_id()
		if visited.has(candidate_id):
			continue
		visited[candidate_id] = true

		var remote := candidate as Node3D
		if remote == null:
			continue

		if not _is_normal_drone_or_boom_buggy(remote):
			continue

		# 手里尚未部署的工具模型不属于威胁。
		if _is_under_tool_pivot(remote):
			continue

		if _get_combat_team(remote) == team_id:
			continue

		var distance := global_position.distance_to(remote.global_position)
		if distance < nearest_distance:
			nearest = remote
			nearest_distance = distance

	return nearest


func _collect_possible_remote_nodes(
	node: Node,
	output: Array[Node]
) -> void:
	if node is Node3D and _is_normal_drone_or_boom_buggy(node as Node3D):
		output.append(node)

	for child in node.get_children():
		_collect_possible_remote_nodes(child, output)


func _is_normal_drone_or_boom_buggy(node: Node3D) -> bool:
	var identity := _node_identity_text(node)

	return (
		identity.contains("normaldrone")
		or identity.contains("normal_drone")
		or identity.contains("boombuggy")
		or identity.contains("boom_buggy")
	)


func _is_under_tool_pivot(node: Node) -> bool:
	var cursor: Node = node
	var depth := 0

	while cursor != null and depth < 8:
		if cursor.name == "ToolPivot":
			return true
		cursor = cursor.get_parent()
		depth += 1

	return false


func _begin_or_refresh_flee(threat: Node3D) -> void:
	if not is_instance_valid(threat):
		return

	var away := global_position - threat.global_position
	away.y = 0.0

	if away.length_squared() < 0.001:
		away = Vector3(
			rng.randf_range(-1.0, 1.0),
			0.0,
			rng.randf_range(-1.0, 1.0)
		)

	away = away.normalized()

	movement_target = _clamp_to_own_farm_bounds(
		global_position + away * flee_distance
	)

	state = AIState.FLEE
	flee_timer = flee_minimum_seconds
	target_plot = null
	target_player = null

	_debug_decision("flee_%s" % threat.name)


# ------------------------------------------------------------------
# Movement without Navigation3D
# ------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	if state == AIState.DEAD:
		return

	var desired_direction := Vector3.ZERO

	if movement_enabled and movement_target != INVALID_POSITION:
		desired_direction = movement_target - global_position
		desired_direction.y = 0.0

		if desired_direction.length_squared() > 0.04:
			desired_direction = desired_direction.normalized()
		else:
			desired_direction = Vector3.ZERO

	if desired_direction != Vector3.ZERO and front_probe.is_colliding():
		var side := global_transform.basis.x
		if rng.randf() < 0.5:
			side = -side

		desired_direction = (
			desired_direction * 0.35 + side * 0.65
		).normalized()

		_try_jump()

	_apply_movement(desired_direction, delta)


func _apply_movement(direction: Vector3, delta: float) -> void:
	var move_speed := (
		easy_move_speed
		if difficulty == Difficulty.EASY
		else hard_move_speed
	)
	var acceleration := (
		easy_move_acceleration
		if difficulty == Difficulty.EASY
		else hard_move_acceleration
	)

	var desired_velocity := direction * move_speed + rubber_knockback
	rubber_knockback = rubber_knockback.move_toward(
		Vector3.ZERO,
		18.0 * delta
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

	if direction.length_squared() > 0.001:
		var desired_yaw := atan2(-direction.x, -direction.z)
		rotation.y = lerp_angle(
			rotation.y,
			desired_yaw,
			minf(1.0, delta * 8.0)
		)

	move_and_slide()
	_update_ai_animation(direction)
	_update_upper_body_aim(delta)


func _try_jump() -> void:
	if not is_on_floor() or jump_timer > 0.0:
		return

	velocity.y = (
		jump_velocity_easy
		if difficulty == Difficulty.EASY
		else jump_velocity_hard
	)
	jump_timer = 0.8
	_play_body_animation(&"JumpStart", 0.05)


func _start_patrol() -> void:
	var own_plots := _get_team_plots(team_id)

	if own_plots.is_empty():
		patrol_target = global_position + Vector3(
			rng.randf_range(-5.0, 5.0),
			0.0,
			rng.randf_range(-5.0, 5.0)
		)
	else:
		var selected: Node3D = own_plots[
			rng.randi_range(0, own_plots.size() - 1)
		] as Node3D
		patrol_target = selected.global_position

	movement_target = patrol_target
	state = AIState.PATROL
	state_timer = (
		rng.randf_range(2.0, 4.0)
		if difficulty == Difficulty.EASY
		else rng.randf_range(0.8, 1.6)
	)
	_debug_decision("patrol")


# ------------------------------------------------------------------
# Aim / animation
# ------------------------------------------------------------------

func _aim_tool(world_target: Vector3) -> void:
	if world_target.distance_squared_to(global_position) < 0.001:
		return

	upper_body_look_target.global_position = world_target

	var aim_origin := head.global_position
	var ray_target := world_target

	if ray_target.distance_squared_to(aim_origin) < 0.001:
		ray_target += -global_transform.basis.z

	aim_ray.global_position = aim_origin
	look_at_target.global_position = aim_origin

	aim_ray.look_at(ray_target, Vector3.UP)
	look_at_target.look_at(ray_target, Vector3.UP)

	aim_ray.target_position = Vector3(0.0, 0.0, -100.0)
	look_at_target.target_position = Vector3(0.0, 0.0, -100.0)

	aim_ray.force_raycast_update()
	look_at_target.force_raycast_update()

	if is_instance_valid(tool_socket):
		tool_socket.look_at(ray_target, Vector3.UP)


func _set_tool_action(tool_id: String) -> void:
	if appearance_player == null:
		return

	var definition: Dictionary = tool_definitions_by_id.get(tool_id, {})
	var category := str(definition.get("category", "utility"))

	action_anim_locked = true

	if category == "shooting":
		appearance_player.play(&"ShootOneHand", 0.05)
	else:
		appearance_player.play(&"ToolUseRight", 0.05)


func _set_ai_appearance(hero_name: String, team_name: String) -> void:
	if team_name not in ["blue", "red"]:
		push_error("[WreckAI] Unsupported team: %s" % team_name)
		return

	var appearance_path := (
		"res://character/hero_skeleton/%s_%s.tscn"
		% [hero_name, team_name]
	)

	var appearance_scene := load(appearance_path) as PackedScene
	if appearance_scene == null:
		push_error(
			"[WreckAI] Cannot load appearance: %s"
			% appearance_path
		)
		return

	var old_appearance := get_node_or_null("AppearanceNode")
	if old_appearance != null:
		old_appearance.queue_free()

	var appearance_node := appearance_scene.instantiate() as Node3D
	appearance_node.name = "AppearanceNode"
	appearance_node.rotation.y = deg_to_rad(180.0)
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
		push_error("[WreckAI] Animated skeleton initialization failed.")
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
	appearance_player.play(&"Idle")


func _setup_upper_body_aim() -> void:
	if skeleton == null:
		return

	upper_body_look_modifiers.clear()
	upper_body_look_weights.clear()

	_add_upper_body_look("SpineLook", "Spine", 0.10, 20.0)
	_add_upper_body_look("ChestLook", "Chest", 0.22, 30.0)
	_add_upper_body_look("NeckLook", "Neck", 0.16, 35.0)
	_add_upper_body_look("HeadLook", "Head_2", 0.28, 50.0)

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
	right_arm_ik.set_root_bone_name(0, "UpperArm.R")
	right_arm_ik.set_middle_bone_name(0, "Forearm.R")
	right_arm_ik.set_end_bone_name(0, "Hand.R")
	right_arm_ik.set_use_virtual_end(0, false)
	right_arm_ik.set_extend_end_bone(0, false)
	right_arm_ik.set_pole_direction(
		0,
		SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X
	)
	right_arm_ik.set_target_node(
		0,
		right_arm_ik.get_path_to(right_hand_ik_target)
	)
	right_arm_ik.set_pole_node(
		0,
		right_arm_ik.get_path_to(right_elbow_pole)
	)
	right_arm_ik.active = true
	right_arm_ik.influence = 0.0

	hand_aim_look = skeleton.find_child(
		"HandAimLook",
		false,
		false
	) as LookAtModifier3D

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
	hand_aim_look.target_node = hand_aim_look.get_path_to(
		upper_body_look_target
	)
	hand_aim_look.active = false
	hand_aim_look.influence = 0.0


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
		right_arm_ik.influence = move_toward(
			right_arm_ik.influence,
			0.88 * equipped_scale * action_scale,
			delta * 5.0
		)

	if is_instance_valid(hand_aim_look):
		hand_aim_look.influence = 0.0


func _update_ai_animation(direction: Vector3) -> void:
	if appearance_player == null:
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


func _play_body_animation(
	animation_name: StringName,
	blend_time: float = 0.12
) -> void:
	if appearance_player == null:
		return

	if (
		appearance_player.current_animation == animation_name
		and appearance_player.is_playing()
	):
		return

	appearance_player.play(animation_name, blend_time)


func _on_skeleton_animation_finished(animation_name: StringName) -> void:
	match animation_name:
		&"JumpStart":
			if not is_on_floor():
				_play_body_animation(&"JumpLoop", 0.05)

		&"JumpLand":
			landing_animation = false

		&"ShootOneHand", &"ToolUseRight":
			action_anim_locked = false


# ------------------------------------------------------------------
# Damage / Hit3D / HP
# ------------------------------------------------------------------

func _on_hit_3d_body_entered(body: Node3D) -> void:
	_handle_hit3d_contact(body)


func _on_hit_3d_area_entered(area: Area3D) -> void:
	_handle_hit3d_contact(area)


func _handle_hit3d_contact(contact: Node) -> void:
	var bullet := _find_bullet_root(contact)
	if bullet == null:
		return

	if not bullet.has_method("get_bullet_owner"):
		return

	var shooter_team := str(bullet.call("get_bullet_owner"))
	if shooter_team == team_id:
		return

	var hit_direction := Vector3.ZERO
	var knockback_force := 0.0
	var damage := bullet_damage
	var effect := "bullet"

	if bullet is RubberBullet:
		var rubber_bullet := bullet as RubberBullet
		hit_direction = rubber_bullet.direction
		knockback_force = float(rubber_bullet.knockback_force)
		damage = bullet_damage
		effect = "rubber_bullet"

	elif bullet is NailBullet:
		var nail_bullet := bullet as NailBullet
		hit_direction = nail_bullet.direction
		knockback_force = float(nail_bullet.knockback_force)
		damage = bullet_damage
		effect = "nail_bullet"

	elif bullet is ColorBullet:
		var color_bullet := bullet as ColorBullet
		hit_direction = color_bullet.direction
		knockback_force = float(color_bullet.knockback_force)
		damage = color_bullet_damage
		effect = str(color_bullet.bullet_effect)

	else:
		return

	impact(effect, damage, shooter_team, hit_direction)

	if is_instance_valid(bullet):
		bullet.queue_free()


func _find_bullet_root(contact: Node) -> Node:
	var node: Node = contact
	var depth := 0

	while node != null and depth < 12:
		if (
			node is RubberBullet
			or node is NailBullet
			or node is ColorBullet
		):
			return node

		node = node.get_parent()
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

	if not attacker_team.is_empty() and attacker_team == team_id:
		return false

	var damage := maxf(strength, 0.0)

	if effect == "explosion":
		damage *= explosion_damage_multiplier

		var away := global_position - _get_optional_explosion_origin()
		away.y = 0.0

		if away.length_squared() > 0.01:
			rubber_knockback += away.normalized() * minf(
				12.0,
				damage * 0.12
			)

	else:
		receive_bullet_hit(hit_direction, minf(10.0, damage * 0.35), attacker_team)

	_apply_damage(damage, effect, attacker_team)
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
		rubber_knockback = horizontal.normalized() * force


func _apply_damage(
	damage: float,
	effect: String,
	attacker_team: String
) -> void:
	current_hp = maxf(0.0, current_hp - damage)
	_update_health_label()

	print(
		"[WreckAI] hit effect=%s damage=%.1f hp=%.1f/%0.1f attacker=%s"
		% [
			effect,
			damage,
			current_hp,
			max_hp,
			attacker_team,
		]
	)

	if current_hp <= 0.0:
		_die(attacker_team, effect)


func _update_health_label() -> void:
	if health_label == null:
		return

	health_label.text = "AI  %d / %d" % [
		roundi(current_hp),
		roundi(max_hp),
	]

	var ratio := clampf(current_hp / maxf(max_hp, 0.001), 0.0, 1.0)
	health_label.modulate = Color(
		lerpf(1.0, 0.35, ratio),
		lerpf(0.35, 1.0, ratio),
		0.35,
		1.0
	)


func _die(attacker_team: String, effect: String) -> void:
	if state == AIState.DEAD:
		return

	state = AIState.DEAD
	velocity = Vector3.ZERO
	collision_layer = 0
	collision_mask = 0

	if hit_3d != null:
		hit_3d.monitoring = false

	if is_instance_valid(held_tool):
		held_tool.queue_free()

	print(
		"[WreckAI] destroyed by=%s effect=%s"
		% [attacker_team, effect]
	)

	call_deferred("queue_free")


func _get_optional_explosion_origin() -> Vector3:
	# BoomBuggy 当前 impact() 三参数调用没有传入爆心。
	# 返回前方一点仅用于产生稳定、可见的击退方向；
	# 后续若你扩展 impact 第五参，可在这里改为真实爆心。
	return global_position - global_transform.basis.z


# ------------------------------------------------------------------
# Generic helpers
# ------------------------------------------------------------------

func _refresh_farm_tile_cache(force_log: bool = false) -> void:
	farm_tile_rescan_timer = farm_tile_rescan_interval
	cached_farm_tiles.clear()

	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root

	if scene_root != null:
		_collect_farm_tiles_recursive(scene_root, cached_farm_tiles)

	# 去重：同一个节点不会因为嵌套扫描被重复存入。
	var unique_tiles: Array[Node3D] = []
	var seen: Dictionary = {}

	for tile in cached_farm_tiles:
		if not is_instance_valid(tile):
			continue

		var tile_id := tile.get_instance_id()
		if seen.has(tile_id):
			continue

		seen[tile_id] = true
		unique_tiles.append(tile)

	cached_farm_tiles = unique_tiles

	if print_farm_discovery and (force_log or not farm_discovery_has_logged):
		var team_counts: Dictionary = {}
		var unowned_count := 0

		for tile in cached_farm_tiles:
			var owner := str(tile.get("land_owner"))

			if owner.is_empty():
				unowned_count += 1
			else:
				team_counts[owner] = int(team_counts.get(owner, 0)) + 1

		print(
			"[WreckAI] FarmTile scan count=%d own=%d enemy=%d unowned=%d owners=%s"
			% [
				cached_farm_tiles.size(),
				_get_tiles_from_cache_for_team(team_id).size(),
				_get_tiles_from_cache_for_team(_enemy_team_id()).size(),
				unowned_count,
				team_counts,
			]
		)

		if cached_farm_tiles.is_empty():
			push_warning(
				"[WreckAI] No FarmTile found. Expected StaticBody3D with "
				+ "setting_tool(), land_owner, seed_record and tool_child."
			)

		farm_discovery_has_logged = true


func _collect_farm_tiles_recursive(
	node: Node,
	output: Array[Node3D]
) -> void:
	if _looks_like_farm_tile(node):
		output.append(node as Node3D)

	for child in node.get_children():
		_collect_farm_tiles_recursive(child, output)


func _looks_like_farm_tile(node: Node) -> bool:
	if not node is StaticBody3D:
		return false

	return (
		node.has_method("setting_tool")
		and _has_property(node, "land_owner")
		and _has_property(node, "seed_record")
		and _has_property(node, "tool_child")
	)


func _get_team_plots(team_name: String) -> Array:
	# 第一优先：你现有 Farmlandmanager 的注册结果。
	var farmland_manager := get_node_or_null("/root/Farmlandmanager")

	if (
		farmland_manager != null
		and farmland_manager.has_method("get_team_plots")
	):
		var manager_result: Variant = farmland_manager.call(
			"get_team_plots",
			team_name
		)

		if manager_result is Array:
			var valid_manager_tiles: Array[Node3D] = []

			for item in manager_result:
				if _is_valid_plot(item):
					valid_manager_tiles.append(item as Node3D)

			if not valid_manager_tiles.is_empty():
				return valid_manager_tiles

	# 第二优先：即使 manager 没注册或暂未更新，也从场景扫描缓存中取。
	return _get_tiles_from_cache_for_team(team_name)


func _get_tiles_from_cache_for_team(team_name: String) -> Array[Node3D]:
	var result: Array[Node3D] = []

	for tile in cached_farm_tiles:
		if not is_instance_valid(tile):
			continue

		if str(tile.get("land_owner")) == team_name:
			result.append(tile)

	return result


func _get_claimable_plots_for_team(team_name: String) -> Array[Node3D]:
	var result: Array[Node3D] = []

	if not allow_claimable_tiles_for_initial_build:
		return result

	var farmland_manager := get_node_or_null("/root/Farmlandmanager")

	if (
		farmland_manager == null
		or not farmland_manager.has_method("get_claimable_plots")
	):
		return result

	var manager_result: Variant = farmland_manager.call(
		"get_claimable_plots",
		team_name
	)

	if not manager_result is Array:
		return result

	for item in manager_result:
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D

		# 只接受无主空地；已归属敌人的绝不放置。
		if not str(tile.get("land_owner")).is_empty():
			continue

		if not str(tile.get("seed_record")).is_empty():
			continue

		var tool_child: Node = tile.get("tool_child")
		if is_instance_valid(tool_child):
			continue

		result.append(tile)

	return result


func _get_buildable_plots_for_team(team_name: String) -> Array[Node3D]:
	var owned := _get_team_plots(team_name)
	if not owned.is_empty():
		return owned

	# 没有任何己方地时，尝试由 Farmlandmanager 提供合法的开局可认领地。
	return _get_claimable_plots_for_team(team_name)


func _is_valid_plot(plot: Variant) -> bool:
	return (
		plot is StaticBody3D
		and is_instance_valid(plot)
		and (plot as Node).has_method("setting_tool")
		and _has_property(plot as Object, "land_owner")
		and _has_property(plot as Object, "seed_record")
		and _has_property(plot as Object, "tool_child")
	)


func _plot_accepts_tool(plot: Node3D) -> bool:
	if not _is_valid_plot(plot):
		return false

	var owner := str(plot.get("land_owner"))

	# 已被敌方占有的土地绝不作为部署候选。
	if not owner.is_empty() and owner != team_id:
		return false

	if not str(plot.get("seed_record")).is_empty():
		return false

	var tool_child: Node = plot.get("tool_child")
	if is_instance_valid(tool_child):
		return false

	# 己方地可以直接部署。无主地必须来自 manager 的 claimable 列表。
	if owner == team_id:
		return true

	for claimable in _get_claimable_plots_for_team(team_id):
		if claimable == plot:
			return true

	return false


func _has_reached_plot(plot: Node3D, distance: float) -> bool:
	return (
		_is_valid_plot(plot)
		and _horizontal_distance(
			global_position,
			plot.global_position
		) <= distance
	)


func _has_valid_attack_target() -> bool:
	return (
		is_instance_valid(target_player)
		or _is_valid_plot(target_plot)
	)


func _get_current_attack_position() -> Vector3:
	if is_instance_valid(target_player):
		return target_player.global_position + Vector3.UP * 0.9

	if _is_valid_plot(target_plot):
		return target_plot.global_position + Vector3.UP * 0.35

	return INVALID_POSITION


func _enemy_team_id() -> String:
	return "red" if team_id == "blue" else "blue"


func _get_combat_team(node: Node) -> String:
	if node == null:
		return ""

	if node.has_method("get_combat_team"):
		return str(node.call("get_combat_team"))

	if _has_property(node, "team_id"):
		return str(node.get("team_id"))

	if _has_property(node, "team"):
		return str(node.get("team"))

	if _has_property(node, "tool_owner"):
		return str(node.get("tool_owner"))

	return ""


func _has_clear_line_to(target: Node3D) -> bool:
	var origin := head.global_position
	var destination := target.global_position + Vector3.UP * 0.85

	var query := PhysicsRayQueryParameters3D.create(
		origin,
		destination,
		combat_ray_mask,
		[get_rid()]
	)

	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_from_inside = true

	var hit := get_world_3d().direct_space_state.intersect_ray(query)

	if hit.is_empty():
		return true

	var collider := hit.get("collider") as Node
	if collider == target:
		return true

	var cursor: Node = collider
	var depth := 0
	while cursor != null and depth < 10:
		if cursor == target:
			return true
		cursor = cursor.get_parent()
		depth += 1

	return false


func _make_attack_standoff_position(target_position: Vector3) -> Vector3:
	var from_target := global_position - target_position
	from_target.y = 0.0

	if from_target.length_squared() < 0.01:
		from_target = (
			Vector3(0.0, 0.0, -1.0)
			if team_id == "blue"
			else Vector3(0.0, 0.0, 1.0)
		)

	return _clamp_to_own_farm_bounds(
		target_position + from_target.normalized() * attack_standoff_distance
	)


func _approach_position(
	target_position: Vector3,
	distance: float
) -> Vector3:
	var from_target := global_position - target_position
	from_target.y = 0.0

	if from_target.length_squared() < 0.01:
		from_target = -global_transform.basis.z

	return target_position + from_target.normalized() * distance


func _clamp_to_own_farm_bounds(position_to_clamp: Vector3) -> Vector3:
	var plots := _get_team_plots(team_id)
	if plots.is_empty():
		return position_to_clamp

	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF

	for item in plots:
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D
		min_x = minf(min_x, tile.global_position.x)
		max_x = maxf(max_x, tile.global_position.x)
		min_z = minf(min_z, tile.global_position.z)
		max_z = maxf(max_z, tile.global_position.z)

	if is_inf(min_x):
		return position_to_clamp

	var margin := _farm_spacing() * 0.5

	return Vector3(
		clampf(position_to_clamp.x, min_x - margin, max_x + margin),
		global_position.y,
		clampf(position_to_clamp.z, min_z - margin, max_z + margin)
	)


func _frontline_z(plots: Array) -> float:
	var result := -INF if team_id == "blue" else INF

	for item in plots:
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D

		if team_id == "blue":
			result = maxf(result, tile.global_position.z)
		else:
			result = minf(result, tile.global_position.z)

	return result


func _backline_z(plots: Array) -> float:
	var result := INF if team_id == "blue" else -INF

	for item in plots:
		if not _is_valid_plot(item):
			continue

		var tile := item as Node3D

		if team_id == "blue":
			result = minf(result, tile.global_position.z)
		else:
			result = maxf(result, tile.global_position.z)

	return result


func _frontline_penalty(position_to_test: Vector3) -> float:
	var front_z := _frontline_z(_get_team_plots(team_id))

	if is_inf(front_z):
		return 0.0

	return absf(position_to_test.z - front_z)


func _farm_spacing() -> float:
	var manager := get_node_or_null("/root/Farmlandmanager")

	if manager == null:
		return DEFAULT_TILE_SPACING

	if manager.has_method("get_team_spacing"):
		return float(
			manager.call(
				"get_team_spacing",
				team_id,
				DEFAULT_TILE_SPACING
			)
		)

	return DEFAULT_TILE_SPACING


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _place_tool_name(place_tool: int) -> String:
	match place_tool:
		PlaceTool.FARM_RUNNER:
			return "farm_runner"
		PlaceTool.ANTI_AIR:
			return "anti_air"
		PlaceTool.SHIELD:
			return "shield_door"
		PlaceTool.AUTO_SHOOTER:
			return "auto_shooter"
		_:
			return "none"


func _tool_id_for_place_tool(place_tool: int) -> String:
	match place_tool:
		PlaceTool.FARM_RUNNER:
			return "farm_runner"
		PlaceTool.ANTI_AIR:
			return "anti_air"
		PlaceTool.SHIELD:
			return "shield_door"
		PlaceTool.AUTO_SHOOTER:
			return "auto_shooter"
		_:
			return ""


func _node_identity_text(node: Node) -> String:
	var text := node.name.to_lower()

	var script = node.get_script()
	if script is Script:
		text += " " + (script as Script).get_global_name().to_lower()

	return text


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true

	return false


func _schedule_think(delay: float = -1.0) -> void:
	state = AIState.THINK
	target_plot = null
	target_player = null
	target_world_position = INVALID_POSITION
	movement_target = INVALID_POSITION
	pending_place_tool = PlaceTool.NONE

	if delay >= 0.0:
		think_timer = delay
	else:
		think_timer = (
			rng.randf_range(0.35, 0.65)
			if difficulty == Difficulty.EASY
			else rng.randf_range(0.08, 0.20)
		)


func _debug_decision(message: String) -> void:
	if print_decisions:
		print("[WreckAI] decision=", message)
