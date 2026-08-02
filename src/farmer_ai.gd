extends CharacterBody3D
class_name FarmerAI

## ============================================================
## Food-War Farmer AI
##
## 主要行为：
## - 根据 team_id 自动载入 farmer_blue.tscn / farmer_red.tscn。
## - 只经营己方农田：播种、收获、部署 PlantProtector、部署 FarmRunner。
## - FarmRunner 最多同时存在两个；工具冷却结束后会继续尝试补足。
## - PlantProtector 每次工具冷却结束后，会寻找新的合法农田格继续放置。
## - 20m ShapeCast3D 持续检测敌方玩家和 NormalDrone、BoomBuggy、SmallMouse。
## - 威胁优先级：远程设备 > 玩家；战斗时只使用 Shotgun。
## - 所有工具定义均从 res://data/tool_definitions.json 读取。
## ============================================================


enum AIState {
	THINK,
	MOVE_TO_FARM_TILE,
	WORK_FARM_TILE,
	MOVE_TO_PLACE_TILE,
	PLACE_TOOL,
	COMBAT,
	PATROL,
	DEAD,
}


enum FarmTask {
	NONE,
	PLANT,
	HARVEST,
	PLACE_PROTECTOR,
	PLACE_RUNNER,
}


const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"
const INVALID_POSITION := Vector3(INF, INF, INF)
const DEFAULT_TILE_SPACING := 2.2

const SPROUT_EXACT_IDS: Array[String] = ["sprout_blaster"]
const RUNNER_EXACT_IDS: Array[String] = ["farm_runner"]
const PROTECTOR_EXACT_IDS: Array[String] = [
	"plant_protector",
	"plantprotector",
]
const SHOTGUN_EXACT_IDS: Array[String] = [
	"shotgun",
	"pump_shotgun",
	"farm_shotgun",
]

const REMOTE_GROUPS: Array[StringName] = [
	&"remote_units",
	&"remote_devices",
	&"normal_drones",
	&"boom_buggies",
	&"small_mice",
	&"smallmouse",
]


@export_category("Identity")
@export_enum("blue", "red") var team_id: String = "blue"
## Optional map-assigned spawn. Empty means a random spawn point in team_id.
@export var spawn_point_id: String = ""
@export var server_authoritative: bool = true

@export_category("Health")
@export var max_hp: float = 200.0
## 与玩家和 FutureWarriorAI 保持一致：死亡后倒地 10 秒，再回到本队出生点。
@export_range(1.0, 30.0, 0.5) var respawn_seconds: float = 10.0
@export var default_bullet_damage: float = 12.0
@export var explosion_damage_multiplier: float = 1.0

@export_category("Movement")
@export var movement_enabled: bool = true
@export var move_speed: float = 4.6
@export var move_acceleration: float = 18.0
@export var turn_speed: float = 8.0
@export var jump_velocity: float = 3.4
@export var farm_interaction_distance: float = 2.35
@export var placement_interaction_distance: float = 2.45
@export var stuck_timeout: float = 1.7
@export var use_navigation_agent: bool = true
@export_range(0.05, 1.0, 0.05) var navigation_refresh_interval: float = 0.25

@export_category("Farming")
## FarmWorld 的 Farmlandmanager 已维护农田索引，低频同步即可。
@export_range(0.5, 10.0, 0.25) var farm_tile_rescan_interval: float = 2.0
## FarmerAI only operates when its own team already has a configured/claimed
## farm.  It must not wander through neutral fields on maps without a farm.
@export var allow_claimable_tiles_when_no_owned_land: bool = false
@export var harvest_before_planting: bool = true
@export var fallback_seed_name: String = "wheat"
@export var farm_action_pause: float = 0.30
@export var patrol_radius: float = 5.0

@export_category("FarmRunner")
@export_range(0, 8, 1) var max_active_farm_runners: int = 2
@export var farm_runner_scene_name: String = "FarmRunner"
@export var runner_fallback_cooldown: float = 10.0

@export_category("Plant Protector")
@export var plant_protector_scene_name: String = "PlantProtector"
@export var protector_fallback_cooldown: float = 15.0
@export var protector_requires_planted_tile: bool = true

@export_category("Threat Detection")
@export_range(1.0, 60.0, 0.5) var threat_detection_range: float = 20.0
@export_range(1.0, 80.0, 0.5) var threat_disengage_range: float = 24.0
## 当前所有远端设备都会注册节点组，ShapeCast 与节点组查询足够覆盖战斗目标。
## 全场景递归仅用于旧地图兼容；大型地图中会造成明显主线程卡顿。
@export var enable_recursive_threat_fallback: bool = false
@export_range(0.10, 3.0, 0.05) var fallback_threat_scan_interval: float = 0.75
@export_range(0.05, 1.0, 0.05) var threat_refresh_interval: float = 0.20
@export_flags_3d_physics var threat_detection_mask: int = 65535
@export_flags_3d_physics var combat_ray_mask: int = 138
@export_flags_3d_physics var interaction_ray_mask: int = 519
@export var threat_scan_max_results: int = 96

@export_category("Shotgun Combat")
@export var shotgun_standoff_distance: float = 7.0
@export var shotgun_min_distance: float = 3.0
@export var shotgun_fallback_cooldown: float = 0.85
@export var aim_height_player: float = 0.95
@export var aim_height_ground_device: float = 0.35
@export var aim_height_air_device: float = 0.0
@export var combat_aim_error: float = 0.04

@export_category("Fallback Tool Scenes")
## 仅当当前 tool_definitions.json 中没有相应条目时使用。
@export_file("*.tscn") var sprout_fallback_path: String = "res://character/weapons/SproutBlaster.tscn"
@export_file("*.tscn") var farm_runner_fallback_path: String = "res://character/weapons/FarmRunner.tscn"
@export_file("*.tscn") var plant_protector_fallback_path: String = "res://character/weapons/PlantProtector.tscn"
@export_file("*.tscn") var shotgun_fallback_path: String = "res://character/weapons/Shotgun.tscn"

@export_category("Runtime Diagnostics")
@export var show_health_label: bool = true
@export var print_decisions: bool = false
@export var print_tool_resolution: bool = true


# ------------------------------------------------------------------
# Runtime-created scene nodes
# ------------------------------------------------------------------

var head: Node3D
var upper_body_look_target: Marker3D
var right_hand_ik_target: Marker3D
var right_elbow_pole: Marker3D
var main_collision_shape: CollisionShape3D
var right_hand_socket: BoneAttachment3D
var tool_pivot: Node3D
var aim_ray: RayCast3D
var look_at_target: RayCast3D
var front_probe: RayCast3D
var left_probe: RayCast3D
var right_probe: RayCast3D
var navigation_agent: NavigationAgent3D
var threat_scan: ShapeCast3D
var hit_3d: Area3D
var hit_collision_shape: CollisionShape3D
var health_label: Label3D
var team_marker: MeshInstance3D
const TEAM_MARKER_HEIGHT := 3.15


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
# Tool data / equipped tool
# ------------------------------------------------------------------

var tool_definitions_by_id: Dictionary = {}
var tool_cooldowns: Dictionary = {}
var current_tool_id := ""
var held_tool: Node3D

var sprout_tool_id := ""
var farm_runner_tool_id := ""
var plant_protector_tool_id := ""
var shotgun_tool_id := ""


# ------------------------------------------------------------------
# AI state
# ------------------------------------------------------------------

var current_hp := 0.0
var state: int = AIState.THINK
var pending_task: int = FarmTask.NONE
var target_tile: Node3D
var combat_target: Node3D
var movement_target := INVALID_POSITION
var patrol_target := INVALID_POSITION

var think_timer := 0.0
var action_timer := 0.0
var farm_tile_rescan_timer := 0.0
var fallback_threat_scan_timer := 0.0
var threat_refresh_timer := 0.0
var navigation_refresh_timer := 0.0
var jump_timer := 0.0

var cached_farm_tiles: Array[Node3D] = []
var cached_team_plots: Array[Node3D] = []
var cached_claimable_plots: Array[Node3D] = []
var scene_scan_threat_candidates: Array[Node3D] = []
var rng := RandomNumberGenerator.new()
var knockback_velocity := Vector3.ZERO

var last_goal_distance := INF
var stuck_time := 0.0
var last_world_position := Vector3.ZERO


func _ready() -> void:
	rng.randomize()
	current_hp = max_hp
	last_world_position = global_position

	_create_required_runtime_nodes()
	add_to_group("farmer_ai")
	add_to_group("combat_characters")

	# Farmlandmanager 已保存农田索引。避免在加载界面期间递归遍历整张地图；
	# 仅在该管理器缺失的旧场景中才使用下面的缓存回退扫描。
	_refresh_farm_tile_cache(false)

	if not _load_tool_definitions():
		set_physics_process(false)
		return

	_resolve_required_tool_ids()
	_set_farmer_appearance()
	_ensure_team_marker_visual()
	_update_health_label()
	# 让首帧先完成画面呈现；农田选择会在下一秒开始。
	_schedule_think(1.0)


func _physics_process(delta: float) -> void:
	if state == AIState.DEAD:
		return

	if (
		server_authoritative
		and multiplayer.has_multiplayer_peer()
		and not multiplayer.is_server()
	):
		return

	_update_timers(delta)
	if threat_refresh_timer <= 0.0:
		threat_refresh_timer = threat_refresh_interval
		_refresh_continuous_threat_target()

	if is_instance_valid(combat_target):
		_update_combat(delta)
	else:
		if state == AIState.COMBAT:
			_schedule_think(0.05)
		_update_work_state(delta)

	_update_movement(delta)
	_update_upper_body_aim(delta)
	_update_tool_camera_alignment()


# ------------------------------------------------------------------
# Runtime node creation
# ------------------------------------------------------------------

func _create_required_runtime_nodes() -> void:
	# 与现有 GamePlayer / AIPlayer 的实体和受击层保持一致。
	collision_layer = 8
	collision_mask = 519

	head = _ensure_node3d(self, "Head")
	head.position = Vector3(0.0, 1.7080579, -0.45418245)

	upper_body_look_target = _ensure_marker3d(head, "UpperBodyLookTarget")
	upper_body_look_target.position = Vector3(0.0, 0.0, -3.0)

	right_hand_ik_target = _ensure_marker3d(head, "RightHandIKTarget")
	right_hand_ik_target.position = Vector3(0.28, -0.28, -0.42)

	main_collision_shape = _ensure_capsule_collision(
		self,
		"CollisionShape3D",
		Vector3(0.0, 0.8465799, -0.01983869),
		0.34,
		1.70
	)

	right_hand_socket = _ensure_bone_attachment(self, "RightHandSocket")
	right_hand_socket.bone_name = "Hand.R"

	tool_pivot = _ensure_node3d(right_hand_socket, "ToolPivot")

	right_elbow_pole = _ensure_marker3d(self, "RightElbowPole")
	right_elbow_pole.position = Vector3(0.65, 1.2, -0.1)

	aim_ray = _ensure_raycast3d(self, "RayCast3D")
	aim_ray.position = Vector3(0.0, 1.4506165, 0.0)
	aim_ray.target_position = Vector3(0.0, 0.0, -100.0)
	aim_ray.collision_mask = combat_ray_mask
	aim_ray.enabled = true

	# FarmRunner、SproutBlaster 和其他放置工具会按名称查找此射线。
	look_at_target = _ensure_raycast3d(self, "LookAtTarget")
	look_at_target.position = Vector3(0.0, 1.4506165, 0.0)
	look_at_target.target_position = Vector3(0.0, 0.0, -100.0)
	look_at_target.collision_mask = interaction_ray_mask
	look_at_target.enabled = true

	front_probe = _ensure_raycast3d(self, "FrontProbe")
	front_probe.position = Vector3(0.0, 0.75, 0.0)
	front_probe.target_position = Vector3(0.0, 0.0, -1.55)
	front_probe.collision_mask = 6
	front_probe.enabled = true

	left_probe = _ensure_raycast3d(self, "LeftProbe")
	left_probe.position = Vector3(0.0, 0.75, 0.0)
	left_probe.target_position = Vector3(-0.85, 0.0, -1.30)
	left_probe.collision_mask = 6
	left_probe.enabled = true

	right_probe = _ensure_raycast3d(self, "RightProbe")
	right_probe.position = Vector3(0.0, 0.75, 0.0)
	right_probe.target_position = Vector3(0.85, 0.0, -1.30)
	right_probe.collision_mask = 6
	right_probe.enabled = true

	navigation_agent = _ensure_navigation_agent(self, "NavigationAgent3D")
	navigation_agent.radius = 0.34
	navigation_agent.height = 1.70
	navigation_agent.path_desired_distance = 0.55
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.avoidance_enabled = false

	threat_scan = _ensure_shapecast3d(self, "ThreatScan20m")
	var threat_sphere := threat_scan.shape as SphereShape3D
	if threat_sphere == null:
		threat_sphere = SphereShape3D.new()
		threat_scan.shape = threat_sphere
	threat_sphere.radius = threat_detection_range
	threat_scan.position = Vector3(0.0, 1.0, 0.0)
	threat_scan.target_position = Vector3.ZERO
	threat_scan.collision_mask = threat_detection_mask
	threat_scan.collide_with_bodies = true
	threat_scan.collide_with_areas = true
	threat_scan.max_results = maxi(8, threat_scan_max_results)
	threat_scan.enabled = true

	hit_3d = _ensure_area3d(self, "Hit3D")
	hit_3d.collision_layer = 0
	hit_3d.collision_mask = 32
	hit_3d.monitoring = true
	hit_3d.monitorable = true

	hit_collision_shape = _ensure_capsule_collision(
		hit_3d,
		"CollisionShape3D",
		Vector3(0.0, 0.8376303, 0.0),
		0.38,
		1.72
	)

	if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
		hit_3d.body_entered.connect(_on_hit_3d_body_entered)
	if not hit_3d.area_entered.is_connected(_on_hit_3d_area_entered):
		hit_3d.area_entered.connect(_on_hit_3d_area_entered)

	health_label = _ensure_health_label(self, "HealthLabel3D")
	health_label.position = Vector3(0.0, 2.65, 0.0)
	health_label.visible = show_health_label


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


func _ensure_bone_attachment(parent: Node, node_name: String) -> BoneAttachment3D:
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


func _ensure_navigation_agent(parent: Node, node_name: String) -> NavigationAgent3D:
	var existing := parent.get_node_or_null(node_name) as NavigationAgent3D
	if existing != null:
		return existing
	var created := NavigationAgent3D.new()
	created.name = node_name
	parent.add_child(created)
	return created


func _ensure_shapecast3d(parent: Node, node_name: String) -> ShapeCast3D:
	var existing := parent.get_node_or_null(node_name) as ShapeCast3D
	if existing != null:
		return existing
	var created := ShapeCast3D.new()
	created.name = node_name
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


func _ensure_capsule_collision(
	parent: Node,
	node_name: String,
	local_position: Vector3,
	radius: float,
	height: float
) -> CollisionShape3D:
	var shape_node := parent.get_node_or_null(node_name) as CollisionShape3D
	if shape_node == null:
		shape_node = CollisionShape3D.new()
		shape_node.name = node_name
		parent.add_child(shape_node)

	shape_node.position = local_position
	var capsule := shape_node.shape as CapsuleShape3D
	if capsule == null:
		capsule = CapsuleShape3D.new()
		shape_node.shape = capsule
	capsule.radius = radius
	capsule.height = maxf(height, radius * 2.0 + 0.01)
	return shape_node


func _ensure_health_label(parent: Node, node_name: String) -> Label3D:
	var existing := parent.get_node_or_null(node_name) as Label3D
	if existing != null:
		return existing
	var created := Label3D.new()
	created.name = node_name
	created.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	created.font_size = 54
	created.outline_size = 9
	created.modulate = Color("#F5F7FA")
	created.outline_modulate = Color("#111722")
	parent.add_child(created)
	return created


# ------------------------------------------------------------------
# Tool JSON loading and ID resolution
# ------------------------------------------------------------------

func _load_tool_definitions() -> bool:
	tool_definitions_by_id.clear()
	tool_cooldowns.clear()

	if not FileAccess.file_exists(TOOL_CONFIG_PATH):
		push_error("[FarmerAI] Tool JSON missing: %s" % TOOL_CONFIG_PATH)
		return false

	var file := FileAccess.open(TOOL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_error("[FarmerAI] Could not open tool JSON.")
		return false

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error(
			"[FarmerAI] Tool JSON parse error line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
		return false

	if not json.data is Dictionary:
		push_error("[FarmerAI] Tool JSON root must be Dictionary.")
		return false

	var source_tools: Variant = json.data.get("tools", [])
	if not source_tools is Array:
		push_error("[FarmerAI] JSON field 'tools' must be Array.")
		return false

	for entry: Variant in source_tools:
		if not entry is Dictionary:
			continue
		var definition: Dictionary = (entry as Dictionary).duplicate(true)
		var tool_id := str(definition.get("id", "")).strip_edges()
		if tool_id.is_empty() or not definition.has("path"):
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

	return not tool_definitions_by_id.is_empty()


func _resolve_required_tool_ids() -> void:
	sprout_tool_id = _resolve_tool_id(
		SPROUT_EXACT_IDS,
		["sproutblaster", "播种炮", "播种枪"]
	)
	farm_runner_tool_id = _resolve_tool_id(
		RUNNER_EXACT_IDS,
		["farmrunner", "农场播种收获机", "播种收获机"]
	)
	plant_protector_tool_id = _resolve_tool_id(
		PROTECTOR_EXACT_IDS,
		["plantprotector", "植物保护器", "保护器"]
	)
	shotgun_tool_id = _resolve_tool_id(
		SHOTGUN_EXACT_IDS,
		["shotgun", "霰弹枪", "散弹枪", "猎枪"]
	)

	# 当前 JSON 版本缺少新工具条目时，仍可用导出的场景路径补充。
	if sprout_tool_id.is_empty():
		sprout_tool_id = _register_fallback_tool(
			"sprout_blaster",
			sprout_fallback_path,
			0.5,
			"utility",
			Vector3(0.0, 180.0, 180.0),
			Vector3.ONE
		)
	if farm_runner_tool_id.is_empty():
		farm_runner_tool_id = _register_fallback_tool(
			"farm_runner",
			farm_runner_fallback_path,
			runner_fallback_cooldown,
			"utility",
			Vector3.ZERO,
			Vector3(0.5, 0.5, 0.5)
		)
	if plant_protector_tool_id.is_empty():
		plant_protector_tool_id = _register_fallback_tool(
			"plant_protector",
			plant_protector_fallback_path,
			protector_fallback_cooldown,
			"utility",
			Vector3.ZERO,
			Vector3(0.5, 0.5, 0.5)
		)
	if shotgun_tool_id.is_empty():
		shotgun_tool_id = _register_fallback_tool(
			"shotgun",
			shotgun_fallback_path,
			shotgun_fallback_cooldown,
			"shooting",
			Vector3(0.0, 180.0, 180.0),
			Vector3.ONE
		)

	if sprout_tool_id.is_empty():
		push_error("[FarmerAI] Could not resolve SproutBlaster in tool_definitions.json.")
	if farm_runner_tool_id.is_empty() and max_active_farm_runners > 0:
		push_warning("[FarmerAI] Could not resolve FarmRunner tool ID.")
	if plant_protector_tool_id.is_empty():
		push_warning("[FarmerAI] Could not resolve PlantProtector tool ID.")
	if shotgun_tool_id.is_empty():
		push_warning("[FarmerAI] Could not resolve Shotgun tool ID.")

	if print_tool_resolution:
		print(
			"[FarmerAI] resolved tools sprout=%s protector=%s runner=%s shotgun=%s"
			% [
				sprout_tool_id,
				plant_protector_tool_id,
				farm_runner_tool_id,
				shotgun_tool_id,
			]
		)


func _register_fallback_tool(
	tool_id: String,
	scene_path: String,
	cooldown: float,
	category: String,
	grip_rotation: Vector3,
	grip_scale: Vector3
) -> String:
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		return ""

	tool_definitions_by_id[tool_id] = {
		"id": tool_id,
		"name": tool_id,
		"path": scene_path,
		"grip_position": Vector3.ZERO,
		"grip_rotation": grip_rotation,
		"grip_scale": grip_scale,
		"cooldown": cooldown,
		"category": category,
	}
	tool_cooldowns[tool_id] = 0.0
	push_warning(
		"[FarmerAI] Tool ID '%s' was not in JSON; using fallback scene %s."
		% [tool_id, scene_path]
	)
	return tool_id


func _resolve_tool_id(
	exact_ids: Array[String],
	identity_keywords: Array[String]
) -> String:
	for exact_id in exact_ids:
		if tool_definitions_by_id.has(exact_id):
			return exact_id

	for key: Variant in tool_definitions_by_id.keys():
		var tool_id := str(key)
		var definition: Dictionary = tool_definitions_by_id[tool_id]
		var identity := _normalize_identity(
			tool_id
			+ " " + str(definition.get("name", ""))
			+ " " + str(definition.get("short", ""))
			+ " " + str(definition.get("path", ""))
		)

		for keyword in identity_keywords:
			if identity.contains(_normalize_identity(keyword)):
				return tool_id

	return ""


func _json_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array or value.size() < 3:
		return fallback
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


func _equip_tool(tool_id: String) -> bool:
	if tool_id.is_empty() or not tool_definitions_by_id.has(tool_id):
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
			"[FarmerAI] Cannot load tool scene: %s"
			% str(definition.get("path", ""))
		)
		return false

	held_tool = scene.instantiate() as Node3D
	if held_tool == null:
		push_error("[FarmerAI] Tool scene root is not Node3D: %s" % tool_id)
		return false

	tool_pivot.add_child(held_tool)
	held_tool.position = definition.get("grip_position", Vector3.ZERO)
	held_tool.rotation_degrees = definition.get("grip_rotation", Vector3.ZERO)
	held_tool.scale = definition.get("grip_scale", Vector3.ONE)
	_set_property_if_present(held_tool, "tool_owner", team_id)
	_set_property_if_present(held_tool, "team_id", team_id)

	current_tool_id = tool_id
	return true


func _tool_ready(tool_id: String) -> bool:
	return (
		not tool_id.is_empty()
		and tool_definitions_by_id.has(tool_id)
		and float(tool_cooldowns.get(tool_id, 0.0)) <= 0.0
	)


func _set_tool_cooldown(tool_id: String, fallback: float = 1.0) -> void:
	if tool_id.is_empty():
		return
	var definition: Dictionary = tool_definitions_by_id.get(tool_id, {})
	var cooldown := float(definition.get("cooldown", fallback))
	tool_cooldowns[tool_id] = maxf(0.05, cooldown)


func _update_tool_cooldowns(delta: float) -> void:
	for key: Variant in tool_cooldowns.keys():
		var tool_id := str(key)
		tool_cooldowns[tool_id] = maxf(
			0.0,
			float(tool_cooldowns[tool_id]) - delta
		)


# ------------------------------------------------------------------
# Timers / main work state
# ------------------------------------------------------------------

func _update_timers(delta: float) -> void:
	_update_tool_cooldowns(delta)
	think_timer = maxf(0.0, think_timer - delta)
	action_timer = maxf(0.0, action_timer - delta)
	farm_tile_rescan_timer = maxf(0.0, farm_tile_rescan_timer - delta)
	fallback_threat_scan_timer = maxf(0.0, fallback_threat_scan_timer - delta)
	threat_refresh_timer = maxf(0.0, threat_refresh_timer - delta)
	navigation_refresh_timer = maxf(0.0, navigation_refresh_timer - delta)
	jump_timer = maxf(0.0, jump_timer - delta)

	if farm_tile_rescan_timer <= 0.0:
		_refresh_farm_tile_cache(false)


func _update_work_state(_delta: float) -> void:
	match state:
		AIState.THINK:
			if think_timer <= 0.0:
				_choose_farm_action()

		AIState.MOVE_TO_FARM_TILE:
			if not _is_valid_farm_tile(target_tile):
				_schedule_think(0.08)
			elif _has_reached(target_tile.global_position, farm_interaction_distance):
				movement_target = INVALID_POSITION
				state = AIState.WORK_FARM_TILE
				action_timer = 0.08

		AIState.WORK_FARM_TILE:
			if action_timer <= 0.0:
				_execute_farm_task()
				_schedule_think(farm_action_pause)

		AIState.MOVE_TO_PLACE_TILE:
			if not _is_valid_farm_tile(target_tile):
				_schedule_think(0.08)
			elif _has_reached(target_tile.global_position, placement_interaction_distance):
				movement_target = INVALID_POSITION
				state = AIState.PLACE_TOOL
				action_timer = 0.08

		AIState.PLACE_TOOL:
			if action_timer <= 0.0:
				_execute_placement_task()
				_schedule_think(farm_action_pause)

		AIState.PATROL:
			if (
				patrol_target == INVALID_POSITION
				or _has_reached(patrol_target, 0.75)
				or action_timer <= 0.0
			):
				_schedule_think(0.08)


func _choose_farm_action() -> void:
	target_tile = null
	pending_task = FarmTask.NONE
	movement_target = INVALID_POSITION

	# 先补足最多两个 FarmRunner。每放一个都会进入 JSON 中配置的冷却。
	if (
		max_active_farm_runners > 0
		and not farm_runner_tool_id.is_empty()
		and _tool_ready(farm_runner_tool_id)
		and _count_active_owned_tool("farmrunner") < max_active_farm_runners
	):
		var runner_tile := _choose_farm_runner_tile()
		if runner_tile != null:
			_begin_placement(FarmTask.PLACE_RUNNER, runner_tile)
			return

	# 冷却一结束就寻找新的合法作物格部署植物保护器。
	if (
		not plant_protector_tool_id.is_empty()
		and _tool_ready(plant_protector_tool_id)
	):
		var protector_tile := _choose_plant_protector_tile()
		if protector_tile != null:
			_begin_placement(FarmTask.PLACE_PROTECTOR, protector_tile)
			return

	if harvest_before_planting:
		var harvest_tile := _choose_harvest_tile()
		if harvest_tile != null:
			_begin_farm_work(FarmTask.HARVEST, harvest_tile)
			return

	if not sprout_tool_id.is_empty() and _tool_ready(sprout_tool_id):
		var empty_tile := _choose_plant_tile()
		if empty_tile != null:
			_begin_farm_work(FarmTask.PLANT, empty_tile)
			return

	if not harvest_before_planting:
		var late_harvest_tile := _choose_harvest_tile()
		if late_harvest_tile != null:
			_begin_farm_work(FarmTask.HARVEST, late_harvest_tile)
			return

	_start_farm_patrol()


func _begin_farm_work(task: int, tile: Node3D) -> void:
	pending_task = task
	target_tile = tile
	movement_target = _approach_position(tile.global_position, 1.75)
	state = AIState.MOVE_TO_FARM_TILE
	action_timer = 7.0
	_debug_decision("farm_task=%s tile=%s" % [_task_name(task), tile.name])


func _begin_placement(task: int, tile: Node3D) -> void:
	pending_task = task
	target_tile = tile
	movement_target = _approach_position(tile.global_position, 1.85)
	state = AIState.MOVE_TO_PLACE_TILE
	action_timer = 7.0
	_debug_decision("placement=%s tile=%s" % [_task_name(task), tile.name])


func _execute_farm_task() -> void:
	if not _is_valid_farm_tile(target_tile):
		return

	match pending_task:
		FarmTask.PLANT:
			_plant_target_tile(target_tile)
		FarmTask.HARVEST:
			_harvest_target_tile(target_tile)


func _plant_target_tile(tile: Node3D) -> bool:
	if not _tile_can_be_planted(tile):
		return false
	if not _tool_ready(sprout_tool_id) or not _equip_tool(sprout_tool_id):
		return false

	var seed_name := _choose_seed_name()
	_configure_sprout_seed(seed_name)
	_aim_tool(tile.global_position + Vector3.UP * 0.18)
	_set_tool_action(sprout_tool_id)

	# 首选真实 SproutBlaster.emit()；它可保留粒子、声音和工具自身逻辑。
	if held_tool.has_method("emit"):
		held_tool.call("emit")

	# 某些 SproutBlaster 依赖玩家 UI 中的种子选择。AI 没有该 UI 时，
	# 只有在 emit 后地块仍为空才使用 FarmTile.plant() 兼容回退。
	var success := not str(tile.get("seed_record")).is_empty()
	if not success and tile.has_method("plant"):
		var plant_result: Variant = tile.call("plant", seed_name, team_id)
		success = true if plant_result == null else bool(plant_result)

	_set_tool_cooldown(sprout_tool_id, 0.5)
	_debug_decision("plant seed=%s success=%s" % [seed_name, success])
	return success


func _harvest_target_tile(tile: Node3D) -> bool:
	if not _tile_can_be_harvested(tile):
		return false

	if not sprout_tool_id.is_empty():
		_equip_tool(sprout_tool_id)
	_aim_tool(tile.global_position + Vector3.UP * 0.25)
	_set_tool_action(sprout_tool_id)

	var result: Variant = tile.call("harvest", global_position)
	var success := true if result == null else bool(result)
	_debug_decision("harvest success=%s" % success)
	return success


func _configure_sprout_seed(seed_name: String) -> void:
	if not is_instance_valid(held_tool):
		return
	for property_name in [
		"seed_name",
		"selected_seed",
		"current_seed",
		"plant_name",
		"plant_item",
	]:
		_set_property_if_present(held_tool, property_name, seed_name)


func _choose_seed_name() -> String:
	var global_var := get_node_or_null("/root/GlobalVar")
	if global_var != null and _has_property(global_var, "plant_item_list"):
		var seed_list: Variant = global_var.get("plant_item_list")
		if seed_list is Array and not seed_list.is_empty():
			return str(seed_list[rng.randi_range(0, seed_list.size() - 1)])
	return fallback_seed_name


func _execute_placement_task() -> void:
	if not _is_valid_farm_tile(target_tile):
		return

	match pending_task:
		FarmTask.PLACE_RUNNER:
			_place_tool_on_tile(
				farm_runner_tool_id,
				_scene_name_for_tool(farm_runner_tool_id, farm_runner_scene_name),
				target_tile,
				runner_fallback_cooldown
			)

		FarmTask.PLACE_PROTECTOR:
			_place_tool_on_tile(
				plant_protector_tool_id,
				_scene_name_for_tool(
					plant_protector_tool_id,
					plant_protector_scene_name
				),
				target_tile,
				protector_fallback_cooldown
			)


func _place_tool_on_tile(
	tool_id: String,
	scene_tool_name: String,
	tile: Node3D,
	fallback_cooldown: float
) -> bool:
	if (
		tool_id.is_empty()
		or scene_tool_name.is_empty()
		or not _tool_ready(tool_id)
		or not _equip_tool(tool_id)
	):
		return false

	if is_instance_valid(tile.get("tool_child") as Node):
		return false

	_aim_tool(tile.global_position + Vector3.UP * 0.20)
	_set_tool_action(tool_id)

	# 当前项目 FarmTile.setting_tool() 的正式入口。
	var result: Variant = tile.call(
		"setting_tool",
		scene_tool_name,
		team_id,
		self
	)

	var success := true
	if result is bool:
		success = bool(result)

	# 老版本 setting_tool() 无返回值；以 tool_child 是否出现作为补充判断。
	var placed_child := tile.get("tool_child") as Node
	if result == null and not is_instance_valid(placed_child):
		# 某些场景会 call_deferred 创建，仍进入冷却以避免同帧重复部署。
		success = true

	if success:
		_set_tool_cooldown(tool_id, fallback_cooldown)

	_debug_decision(
		"placed scene=%s id=%s success=%s"
		% [scene_tool_name, tool_id, success]
	)
	return success


func _scene_name_for_tool(tool_id: String, fallback: String) -> String:
	if tool_definitions_by_id.has(tool_id):
		var definition: Dictionary = tool_definitions_by_id[tool_id]
		var path := str(definition.get("path", ""))
		if not path.is_empty():
			var basename := path.get_file().get_basename()
			if not basename.is_empty():
				return basename
	return fallback


# ------------------------------------------------------------------
# Continuous 20m threat detection and priority selection
# ------------------------------------------------------------------

func _refresh_continuous_threat_target() -> void:
	if threat_scan == null or not threat_scan.is_inside_tree():
		combat_target = null
		return

	# ShapeCast 会在物理帧自动更新。不要在这里强制同步查询，
	# 否则 65535 掩码会在大型地图上每帧阻塞物理服务器。
	var sphere := threat_scan.shape as SphereShape3D
	if sphere != null and not is_equal_approx(sphere.radius, threat_detection_range):
		sphere.radius = threat_detection_range
	threat_scan.collision_mask = threat_detection_mask

	var candidates: Array[Node3D] = []
	var seen: Dictionary = {}

	for index in range(threat_scan.get_collision_count()):
		var collider := threat_scan.get_collider(index) as Node
		var candidate := _resolve_combat_target_from_contact(collider)
		_append_unique_candidate(candidate, candidates, seen)

	# 组扫描解决 ShapeCast 只撞到复杂模型子节点或某些单位未配置碰撞的情况。
	for node in get_tree().get_nodes_in_group("human_players"):
		_append_unique_candidate(node as Node3D, candidates, seen)

	for group_name in REMOTE_GROUPS:
		for node in get_tree().get_nodes_in_group(group_name):
			_append_unique_candidate(
				_resolve_combat_target_from_contact(node),
				candidates,
				seen
			)
	for node in get_tree().get_nodes_in_group("combat_characters"):
		_append_unique_candidate(node as Node3D, candidates, seen)

	# 低频递归兜底，兼容尚未 add_to_group 的 NormalDrone/BoomBuggy/SmallMouse。
	# 主检测仍由每帧 ShapeCast 完成，避免高频遍历大型地图。
	if enable_recursive_threat_fallback:
		if fallback_threat_scan_timer <= 0.0:
			fallback_threat_scan_timer = fallback_threat_scan_interval
			scene_scan_threat_candidates.clear()
			var scene_root := get_tree().current_scene
			if scene_root != null:
				_collect_remote_candidates_recursive(
					scene_root,
					scene_scan_threat_candidates
				)

		for remote in scene_scan_threat_candidates:
			_append_unique_candidate(remote, candidates, seen)

	var best: Node3D
	var best_priority := 999
	var best_distance := INF

	for candidate in candidates:
		if not _is_valid_hostile_candidate(candidate):
			continue

		var distance := global_position.distance_to(candidate.global_position)
		if distance > threat_detection_range:
			continue

		# 远程设备优先级 0，玩家优先级 1。
		var priority := 0 if _is_priority_remote_device(candidate) else 1
		if priority < best_priority or (
			priority == best_priority and distance < best_distance
		):
			best = candidate
			best_priority = priority
			best_distance = distance

	if best != null:
		if combat_target != best:
			combat_target = best
			_begin_combat(best)
		return

	# 已锁定目标可在 20m 外短暂保留到 disengage 距离，避免边界抖动。
	if is_instance_valid(combat_target):
		if (
			global_position.distance_to(combat_target.global_position)
			<= threat_disengage_range
			and _is_valid_hostile_candidate(combat_target)
		):
			return

	combat_target = null


func _append_unique_candidate(
	candidate: Node3D,
	output: Array[Node3D],
	seen: Dictionary
) -> void:
	if not is_instance_valid(candidate) or candidate == self:
		return
	var instance_id := candidate.get_instance_id()
	if seen.has(instance_id):
		return
	seen[instance_id] = true
	output.append(candidate)


func _resolve_combat_target_from_contact(contact: Node) -> Node3D:
	var cursor: Node = contact
	var remote_fallback: Node3D
	var depth := 0

	while cursor != null and depth < 14:
		if cursor is Node3D:
			var node3d := cursor as Node3D
			if node3d.is_in_group("human_players"):
				return node3d

			if node3d.is_in_group("combat_characters"):
				return node3d

			if _is_priority_remote_device(node3d):
				remote_fallback = node3d
				if (
					node3d.has_method("impact")
					or _has_property(node3d, "tool_owner")
					or _has_property(node3d, "team_id")
				):
					return node3d

		cursor = cursor.get_parent()
		depth += 1

	return remote_fallback


func _collect_remote_candidates_recursive(
	node: Node,
	output: Array[Node3D]
) -> void:
	if node is Node3D and _is_priority_remote_device(node as Node3D):
		var resolved := _resolve_combat_target_from_contact(node)
		if resolved != null and not _is_under_tool_pivot(resolved):
			output.append(resolved)

	for child in node.get_children():
		_collect_remote_candidates_recursive(child, output)


func _is_priority_remote_device(node: Node3D) -> bool:
	if node == null:
		return false
	var identity := _normalize_identity(_node_identity_text(node))
	return (
		identity.contains("normaldrone")
		or identity.contains("boombuggy")
		or identity.contains("smallmouse")
	)


func _is_air_remote_device(node: Node3D) -> bool:
	return _normalize_identity(_node_identity_text(node)).contains("normaldrone")


func _is_valid_hostile_candidate(candidate: Node3D) -> bool:
	if not is_instance_valid(candidate) or candidate == self:
		return false
	if _is_under_tool_pivot(candidate):
		return false

	var is_player := candidate.is_in_group("human_players")
	var is_remote := _is_priority_remote_device(candidate)
	var is_ai_character := candidate.is_in_group("combat_characters")
	if not is_player and not is_remote and not is_ai_character:
		return false
	if is_ai_character and candidate.has_method("get_network_state"):
		var network_state := candidate.call("get_network_state") as Dictionary
		if bool(network_state.get("dead", false)):
			return false

	var candidate_team := _get_combat_team(candidate)
	if not candidate_team.is_empty() and candidate_team == team_id:
		return false
	return true


func _is_under_tool_pivot(node: Node) -> bool:
	var cursor: Node = node
	var depth := 0
	while cursor != null and depth < 10:
		if cursor.name == "ToolPivot":
			return true
		cursor = cursor.get_parent()
		depth += 1
	return false


# ------------------------------------------------------------------
# Shotgun combat
# ------------------------------------------------------------------

func _begin_combat(target: Node3D) -> void:
	if not is_instance_valid(target):
		return
	state = AIState.COMBAT
	target_tile = null
	pending_task = FarmTask.NONE
	_debug_decision("combat target=%s" % target.name)


func _update_combat(_delta: float) -> void:
	if not _is_valid_hostile_candidate(combat_target):
		combat_target = null
		_schedule_think(0.05)
		return

	var distance := global_position.distance_to(combat_target.global_position)
	if distance > threat_disengage_range:
		combat_target = null
		_schedule_think(0.05)
		return

	var aim_position := _combat_aim_position(combat_target)
	_aim_tool(aim_position)

	if distance > shotgun_standoff_distance + 1.0:
		movement_target = _combat_standoff_position(combat_target.global_position)
	elif distance < shotgun_min_distance:
		var away := global_position - combat_target.global_position
		away.y = 0.0
		if away.length_squared() < 0.001:
			away = global_transform.basis.z
		movement_target = global_position + away.normalized() * 3.5
	else:
		movement_target = INVALID_POSITION

	if (
		not shotgun_tool_id.is_empty()
		and _tool_ready(shotgun_tool_id)
		and _has_clear_line_to(combat_target, aim_position)
	):
		_fire_shotgun(aim_position)


func _fire_shotgun(world_target: Vector3) -> bool:
	if not _equip_tool(shotgun_tool_id):
		return false
	if not held_tool.has_method("emit"):
		push_warning("[FarmerAI] Resolved Shotgun has no emit().")
		return false

	var final_target := world_target + Vector3(
		rng.randf_range(-combat_aim_error, combat_aim_error),
		rng.randf_range(-combat_aim_error, combat_aim_error),
		rng.randf_range(-combat_aim_error, combat_aim_error)
	)
	_aim_tool(final_target)
	_update_tool_camera_alignment()
	_set_tool_action(shotgun_tool_id)
	held_tool.call("emit")
	_set_tool_cooldown(shotgun_tool_id, shotgun_fallback_cooldown)
	return true


func _combat_aim_position(target: Node3D) -> Vector3:
	if _is_air_remote_device(target):
		return target.global_position + Vector3.UP * aim_height_air_device
	if _is_priority_remote_device(target):
		return target.global_position + Vector3.UP * aim_height_ground_device
	return target.global_position + Vector3.UP * aim_height_player


func _combat_standoff_position(target_position: Vector3) -> Vector3:
	var away := global_position - target_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = Vector3(0.0, 0.0, -1.0 if team_id == "blue" else 1.0)
	return target_position + away.normalized() * shotgun_standoff_distance


func _has_clear_line_to(target: Node3D, aim_position: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		head.global_position,
		aim_position,
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
	var cursor: Node = collider
	var depth := 0
	while cursor != null and depth < 14:
		if cursor == target:
			return true
		cursor = cursor.get_parent()
		depth += 1
	return false


# ------------------------------------------------------------------
# Movement / patrol
# ------------------------------------------------------------------

func _update_movement(delta: float) -> void:
	if state == AIState.DEAD:
		return

	var direction := Vector3.ZERO
	if movement_enabled and movement_target != INVALID_POSITION:
		direction = _direction_to_goal(movement_target)

	if direction != Vector3.ZERO and front_probe.is_colliding():
		var left_free := not left_probe.is_colliding()
		var right_free := not right_probe.is_colliding()
		var side := Vector3.ZERO
		if left_free and not right_free:
			side = -global_transform.basis.x
		elif right_free and not left_free:
			side = global_transform.basis.x
		else:
			side = (
				-global_transform.basis.x
				if rng.randf() < 0.5
				else global_transform.basis.x
			)
		direction = (direction * 0.30 + side * 0.70).normalized()
		_try_jump()

	_apply_movement(direction, delta)


func _apply_movement(direction: Vector3, delta: float) -> void:
	var horizontal_step := direction * move_speed + knockback_velocity
	var proposed := global_position + Vector3(horizontal_step.x, 0.0, horizontal_step.z) * delta
	if WaterBody3D.is_navigation_blocked(proposed):
		# Do not let patrol or flee movement enter water; NavigationObstacle3D
		# handles path planning, this guard covers direct movement/knockback.
		direction = Vector3.ZERO
	var desired_velocity := direction * move_speed + knockback_velocity
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 18.0 * delta)

	velocity.x = move_toward(
		velocity.x,
		desired_velocity.x,
		move_acceleration * delta
	)
	velocity.z = move_toward(
		velocity.z,
		desired_velocity.z,
		move_acceleration * delta
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
			minf(1.0, delta * turn_speed)
		)

	move_and_slide()
	_update_stuck_detection(direction, delta)
	_update_ai_animation(direction)


func _update_stuck_detection(direction: Vector3, delta: float) -> void:
	if direction == Vector3.ZERO or movement_target == INVALID_POSITION:
		stuck_time = 0.0
		last_goal_distance = INF
		last_world_position = global_position
		return

	var moved := _horizontal_distance(global_position, last_world_position)
	var goal_distance := _horizontal_distance(global_position, movement_target)
	if moved < 0.025 and goal_distance >= last_goal_distance - 0.02:
		stuck_time += delta
	else:
		stuck_time = maxf(0.0, stuck_time - delta * 0.5)

	if stuck_time >= stuck_timeout:
		stuck_time = 0.0
		_try_jump()
		var sidestep := global_transform.basis.x
		if rng.randf() < 0.5:
			sidestep = -sidestep
		movement_target = global_position + sidestep * 2.5

	last_goal_distance = goal_distance
	last_world_position = global_position


func _try_jump() -> void:
	if not is_on_floor() or jump_timer > 0.0:
		return
	velocity.y = jump_velocity
	jump_timer = 0.8
	_play_body_animation(&"JumpStart", 0.05)


func _start_farm_patrol() -> void:
	# FarmerAI patrols only its own farm.  No configured/claimed farm means
	# there is no valid work destination, so remain idle instead of wandering
	# toward an enemy farm or a random point on the map.
	var plots := _get_workable_team_plots()
	if plots.is_empty():
		patrol_target = INVALID_POSITION
		_schedule_think(1.0)
		return
	var tile := plots[rng.randi_range(0, plots.size() - 1)] as Node3D
	patrol_target = tile.global_position

	movement_target = patrol_target
	state = AIState.PATROL
	action_timer = rng.randf_range(1.2, 2.4)


func _approach_position(target_position: Vector3, distance: float) -> Vector3:
	var away := global_position - target_position
	away.y = 0.0
	if away.length_squared() < 0.001:
		away = -global_transform.basis.z
	return target_position + away.normalized() * distance

func _direction_to_goal(goal: Vector3) -> Vector3:
	if goal == INVALID_POSITION:
		return Vector3.ZERO
	var direct := _horizontal_direction(global_position, goal)
	if not use_navigation_agent or navigation_agent == null or not _navigation_map_is_ready():
		return direct
	if navigation_refresh_timer <= 0.0:
		navigation_agent.target_position = goal
		navigation_refresh_timer = navigation_refresh_interval
	var next_position := navigation_agent.get_next_path_position()
	var routed := _horizontal_direction(global_position, next_position)
	return direct if routed == Vector3.ZERO else routed


func _navigation_map_is_ready() -> bool:
	if navigation_agent == null:
		return false
	var navigation_map := navigation_agent.get_navigation_map()
	return navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(navigation_map) > 0


func _has_reached(target_position: Vector3, distance: float) -> bool:
	return _horizontal_distance(global_position, target_position) <= distance


# ------------------------------------------------------------------
# FarmTile discovery / task selection
# ------------------------------------------------------------------

func _refresh_farm_tile_cache(force_log: bool = false) -> void:
	farm_tile_rescan_timer = farm_tile_rescan_interval
	cached_team_plots.clear()
	cached_claimable_plots.clear()
	cached_farm_tiles.clear()

	# 正常地图只读取 Farmlandmanager 已维护的索引，不遍历场景树。
	var farmland_manager := get_node_or_null("/root/Farmlandmanager")
	if farmland_manager != null and farmland_manager.has_method("get_team_plots"):
		var team_value: Variant = farmland_manager.call("get_team_plots", team_id)
		if team_value is Array:
			for item in team_value:
				if _is_valid_farm_tile(item):
					cached_team_plots.append(item as Node3D)
		if cached_team_plots.is_empty() and allow_claimable_tiles_when_no_owned_land \
				and farmland_manager.has_method("get_claimable_plots"):
			var claimable_value: Variant = farmland_manager.call("get_claimable_plots", team_id)
			if claimable_value is Array:
				for item in claimable_value:
					if _is_valid_farm_tile(item) and str((item as Node3D).get("land_owner")).is_empty():
						cached_claimable_plots.append(item as Node3D)
		if force_log and print_decisions:
			print("[FarmerAI] farm index own=%d claimable=%d" % [
				cached_team_plots.size(), cached_claimable_plots.size(),
			])
		return

	# 兼容不使用 Farmlandmanager 的旧测试场景。
	var scene_root := get_tree().current_scene
	if scene_root == null:
		scene_root = get_tree().root
	if scene_root != null:
		_collect_farm_tiles_recursive(scene_root, cached_farm_tiles)

	var unique_tiles: Array[Node3D] = []
	var seen: Dictionary = {}
	for tile in cached_farm_tiles:
		if not is_instance_valid(tile):
			continue
		var instance_id := tile.get_instance_id()
		if seen.has(instance_id):
			continue
		seen[instance_id] = true
		unique_tiles.append(tile)
	cached_farm_tiles = unique_tiles

	if force_log and print_decisions:
		print(
			"[FarmerAI] FarmTile scan=%d own=%d"
			% [cached_farm_tiles.size(), _get_team_plots(team_id).size()]
		)


func _collect_farm_tiles_recursive(
	node: Node,
	output: Array[Node3D]
) -> void:
	if _looks_like_farm_tile(node):
		output.append(node as Node3D)
	for child in node.get_children():
		_collect_farm_tiles_recursive(child, output)


func _looks_like_farm_tile(node: Node) -> bool:
	return (
		node is Node3D
		and node.has_method("setting_tool")
		and _has_property(node, "land_owner")
		and _has_property(node, "seed_record")
		and _has_property(node, "tool_child")
	)


func _get_team_plots(team_name: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if team_name == team_id:
		for tile in cached_team_plots:
			if _is_valid_farm_tile(tile):
				result.append(tile)
		return result
	for tile in cached_farm_tiles:
		if is_instance_valid(tile) and str(tile.get("land_owner")) == team_name:
			result.append(tile)
	return result


func _get_claimable_plots(team_name: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	if not allow_claimable_tiles_when_no_owned_land:
		return result
	if team_name == team_id:
		for tile in cached_claimable_plots:
			if _is_valid_farm_tile(tile) and str(tile.get("land_owner")).is_empty():
				result.append(tile)
	return result


func _get_workable_team_plots() -> Array[Node3D]:
	var owned := _get_team_plots(team_id)
	if not owned.is_empty():
		return owned
	return _get_claimable_plots(team_id)


func _choose_farm_runner_tile() -> Node3D:
	var existing_runner_tiles := _get_owned_tool_tiles("farmrunner")
	var best: Node3D
	var best_score := INF

	for tile in _get_workable_team_plots():
		if not _tile_is_empty_for_runner(tile):
			continue

		var score := _horizontal_distance(global_position, tile.global_position)
		# 两台 Runner 尽量分散到农田不同区域。
		for existing_tile in existing_runner_tiles:
			var separation := _horizontal_distance(
				tile.global_position,
				existing_tile.global_position
			)
			score += maxf(0.0, 10.0 - separation) * 4.0

		if score < best_score:
			best_score = score
			best = tile

	return best


func _choose_plant_protector_tile() -> Node3D:
	var best: Node3D
	var best_score := INF

	for tile in _get_team_plots(team_id):
		if not _tile_accepts_protector(tile):
			continue

		var score := _horizontal_distance(global_position, tile.global_position)
		if bool(tile.get("can_harvest")):
			score -= 5.0
		if _has_property(tile, "growth_value"):
			score -= float(tile.get("growth_value")) * 0.02

		if score < best_score:
			best_score = score
			best = tile

	return best


func _choose_harvest_tile() -> Node3D:
	var best: Node3D
	var best_distance := INF
	for tile in _get_team_plots(team_id):
		if not _tile_can_be_harvested(tile):
			continue
		var distance := _horizontal_distance(global_position, tile.global_position)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


func _choose_plant_tile() -> Node3D:
	var best: Node3D
	var best_distance := INF
	for tile in _get_workable_team_plots():
		if not _tile_can_be_planted(tile):
			continue
		var distance := _horizontal_distance(global_position, tile.global_position)
		if distance < best_distance:
			best_distance = distance
			best = tile
	return best


func _tile_is_empty_for_runner(tile: Node3D) -> bool:
	return (
		_is_valid_farm_tile(tile)
		and str(tile.get("seed_record")).is_empty()
		and not is_instance_valid(tile.get("tool_child") as Node)
		and _tile_owner_is_usable(tile)
	)


func _tile_accepts_protector(tile: Node3D) -> bool:
	if not _is_valid_farm_tile(tile) or not _tile_owner_is_usable(tile):
		return false
	if is_instance_valid(tile.get("tool_child") as Node):
		return false
	if protector_requires_planted_tile and str(tile.get("seed_record")).is_empty():
		return false
	return true


func _tile_can_be_planted(tile: Node3D) -> bool:
	return (
		_is_valid_farm_tile(tile)
		and _tile_owner_is_usable(tile)
		and str(tile.get("seed_record")).is_empty()
		and not is_instance_valid(tile.get("tool_child") as Node)
		and tile.has_method("plant")
	)


func _tile_can_be_harvested(tile: Node3D) -> bool:
	return (
		_is_valid_farm_tile(tile)
		and str(tile.get("land_owner")) == team_id
		and bool(tile.get("can_harvest"))
		and not is_instance_valid(tile.get("tool_child") as Node)
		and tile.has_method("harvest")
	)


func _tile_owner_is_usable(tile: Node3D) -> bool:
	var owner := str(tile.get("land_owner"))
	if owner == team_id:
		return true
	if not owner.is_empty():
		return false
	# 调用方已经从 _get_workable_team_plots() 取得可领取格。
	# 这里再对每个候选格搜索完整可领取列表会造成 O(n^2) 卡顿。
	return allow_claimable_tiles_when_no_owned_land


func _get_owned_tool_tiles(identity_part: String) -> Array[Node3D]:
	var result: Array[Node3D] = []
	var normalized_part := _normalize_identity(identity_part)
	for tile in _get_team_plots(team_id):
		var child := tile.get("tool_child") as Node
		if not is_instance_valid(child):
			continue
		if _normalize_identity(_node_identity_text(child)).contains(normalized_part):
			result.append(tile)
	return result


func _count_active_owned_tool(identity_part: String) -> int:
	return _get_owned_tool_tiles(identity_part).size()


func _is_valid_farm_tile(value: Variant) -> bool:
	return (
		value is Node3D
		and is_instance_valid(value)
		and (value as Node).has_method("setting_tool")
		and _has_property(value as Object, "land_owner")
		and _has_property(value as Object, "seed_record")
		and _has_property(value as Object, "tool_child")
	)


# ------------------------------------------------------------------
# Aiming / player-compatible Y-axis correction / animations
# ------------------------------------------------------------------

func _aim_tool(world_target: Vector3) -> void:
	if world_target.distance_squared_to(global_position) < 0.001:
		return

	upper_body_look_target.global_position = world_target
	var origin := head.global_position
	var target := world_target
	if target.distance_squared_to(origin) < 0.001:
		target += -global_transform.basis.z

	aim_ray.global_position = origin
	look_at_target.global_position = origin
	aim_ray.look_at(target, Vector3.UP)
	look_at_target.look_at(target, Vector3.UP)
	aim_ray.target_position = Vector3(0.0, 0.0, -100.0)
	look_at_target.target_position = Vector3(0.0, 0.0, -100.0)
	aim_ray.force_raycast_update()
	look_at_target.force_raycast_update()


func _update_tool_camera_alignment() -> void:
	if not is_instance_valid(held_tool) or not is_instance_valid(tool_pivot):
		return

	# 与 player.gd 相同的修正思路：先读取工具自身真正的发射轴，
	# 再反推出 ToolPivot 应有的 Basis。AI 用 aim_ray 替代玩家 Camera3D。
	var authoritative_aim: Node3D
	var direct_muzzle := held_tool.get_node_or_null("Muzzle") as Node3D
	if direct_muzzle != null:
		authoritative_aim = direct_muzzle
	else:
		authoritative_aim = held_tool.find_child(
			"RayCast3D",
			true,
			false
		) as Node3D

	if authoritative_aim == null:
		return

	var pivot_basis := tool_pivot.global_transform.basis
	var aim_basis := authoritative_aim.global_transform.basis
	var aim_from_pivot := pivot_basis.inverse() * aim_basis
	var desired_pivot_basis := (
		aim_ray.global_transform.basis * aim_from_pivot.inverse()
	)

	tool_pivot.global_transform = Transform3D(
		desired_pivot_basis,
		tool_pivot.global_position
	)


func _set_tool_action(tool_id: String) -> void:
	if appearance_player == null:
		return

	var definition: Dictionary = tool_definitions_by_id.get(tool_id, {})
	var category := str(definition.get("category", "utility"))
	action_anim_locked = true

	if category == "shooting" or tool_id == shotgun_tool_id:
		appearance_player.play(&"ShootOneHand", 0.05)
	else:
		appearance_player.play(&"ToolUseRight", 0.05)


func _set_farmer_appearance() -> void:
	if team_id not in ["blue", "red"]:
		push_error("[FarmerAI] team_id must be blue or red.")
		return

	var appearance_path := "res://character/hero_skeleton/farmer_%s.tscn" % team_id
	var appearance_scene := load(appearance_path) as PackedScene
	if appearance_scene == null:
		push_error("[FarmerAI] Cannot load appearance: %s" % appearance_path)
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
		push_error("[FarmerAI] Farmer animated skeleton initialization failed.")
		return

	right_hand_socket.use_external_skeleton = true
	right_hand_socket.external_skeleton = right_hand_socket.get_path_to(skeleton)
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
		var desired := upper_body_look_weights[index] * equipped_scale * action_scale
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
	elif state == AIState.COMBAT and is_instance_valid(held_tool):
		_play_body_animation(&"IdleAim", 0.10)
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
	if appearance_player.has_animation(animation_name):
		appearance_player.play(animation_name, blend_time)


func _on_skeleton_animation_finished(animation_name: StringName) -> void:
	match animation_name:
		&"JumpStart":
			if not is_on_floor():
				_play_body_animation(&"JumpLoop", 0.05)
		&"JumpLand":
			landing_animation = false
		&"ShootOneHand", &"ToolUseRight", &"PunchRIght", &"PunchRight":
			action_anim_locked = false


# ------------------------------------------------------------------
# Damage / Hit3D compatibility
# ------------------------------------------------------------------

func _on_hit_3d_body_entered(body: Node3D) -> void:
	_handle_hit_contact(body)


func _on_hit_3d_area_entered(area: Area3D) -> void:
	_handle_hit_contact(area)


func _handle_hit_contact(contact: Node) -> void:
	var bullet := _find_bullet_root(contact)
	if bullet == null or not bullet.has_method("get_bullet_owner"):
		return

	var attacker_team := str(bullet.call("get_bullet_owner"))
	if attacker_team == team_id:
		return

	var damage := default_bullet_damage
	var effect := "bullet"
	var hit_direction := Vector3.ZERO

	for damage_property in ["bullet_damage", "damage", "knockback_force"]:
		if _has_property(bullet, damage_property):
			damage = maxf(0.0, float(bullet.get(damage_property)))
			break
	if _has_property(bullet, "bullet_effect"):
		effect = str(bullet.get("bullet_effect"))
	if _has_property(bullet, "direction"):
		var direction_value: Variant = bullet.get("direction")
		if direction_value is Vector3:
			hit_direction = direction_value

	impact(effect, damage, attacker_team, hit_direction)
	if is_instance_valid(bullet):
		bullet.queue_free()


func _find_bullet_root(contact: Node) -> Node:
	var cursor: Node = contact
	var depth := 0
	while cursor != null and depth < 14:
		if cursor.has_method("get_bullet_owner"):
			return cursor
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
	if not attacker_team.is_empty() and attacker_team == team_id:
		return false

	var damage := maxf(0.0, strength)
	if effect == "explosion":
		damage *= explosion_damage_multiplier

	var horizontal := Vector3(hit_direction.x, 0.0, hit_direction.z)
	if horizontal.length_squared() > 0.001:
		knockback_velocity += horizontal.normalized() * minf(10.0, damage * 0.25)

	current_hp = maxf(0.0, current_hp - damage)
	_update_health_label()
	if current_hp <= 0.0:
		_die(attacker_team, effect)
	return true


func receive_bullet_hit(
	hit_direction: Vector3,
	force: float,
	shooter_team: String
) -> void:
	if shooter_team == team_id:
		return
	var horizontal := Vector3(hit_direction.x, 0.0, hit_direction.z)
	if horizontal.length_squared() > 0.001:
		knockback_velocity = horizontal.normalized() * force


func _update_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = show_health_label
	health_label.text = "Farmer AI  %d / %d" % [
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
	knockback_velocity = Vector3.ZERO
	action_anim_locked = true
	_play_body_animation(&"DeathFallForward", 0.08)
	if not attacker_team.is_empty() and (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		GameAuthority.award_team_ai_defeat(attacker_team, team_id, "Farmer AI")
	collision_layer = 0
	collision_mask = 0
	if hit_3d != null:
		hit_3d.monitoring = false
		hit_3d.monitorable = false
		hit_3d.collision_layer = 0
		hit_3d.collision_mask = 0
	if main_collision_shape != null:
		main_collision_shape.set_deferred("disabled", true)
	if hit_collision_shape != null:
		hit_collision_shape.set_deferred("disabled", true)
	if health_label != null:
		health_label.visible = false
	if threat_scan != null:
		threat_scan.enabled = false
	if is_instance_valid(held_tool):
		held_tool.queue_free()
		held_tool = null
	current_tool_id = ""
	print("[FarmerAI] defeated by=%s effect=%s; respawning in %.1f seconds" % [
		attacker_team, effect, respawn_seconds,
	])
	call_deferred("_finish_death")


func _finish_death() -> void:
	await get_tree().create_timer(respawn_seconds).timeout
	if not is_inside_tree() or state != AIState.DEAD:
		return
	_respawn_at_team_spawn()


func _respawn_at_team_spawn() -> void:
	var game_world: Node = GlobalVar.gameworld
	if is_instance_valid(game_world) and game_world.has_method("get_spawn_position_for_id"):
		var spawn_value: Variant = game_world.call(
			"get_spawn_position_for_id", spawn_point_id, team_id, 2, get_instance_id()
		)
		if spawn_value is Vector3 and spawn_value != Vector3.INF:
			global_position = spawn_value
	velocity = Vector3.ZERO
	knockback_velocity = Vector3.ZERO
	current_hp = max_hp
	combat_target = null
	target_tile = null
	pending_task = FarmTask.NONE
	movement_target = INVALID_POSITION
	patrol_target = INVALID_POSITION
	think_timer = 0.0
	action_timer = 0.0
	fallback_threat_scan_timer = 0.0
	stuck_time = 0.0
	last_goal_distance = INF
	action_anim_locked = false
	landing_animation = false
	was_on_floor = true
	state = AIState.THINK
	collision_layer = 8
	collision_mask = 519
	if main_collision_shape != null:
		main_collision_shape.set_deferred("disabled", false)
	if hit_collision_shape != null:
		hit_collision_shape.set_deferred("disabled", false)
	if hit_3d != null:
		hit_3d.collision_layer = 0
		hit_3d.collision_mask = 32
		hit_3d.monitoring = true
		hit_3d.monitorable = true
	if threat_scan != null:
		threat_scan.enabled = true
	_play_body_animation(&"Idle", 0.05)
	_update_health_label()
	_schedule_think(0.12)


# ------------------------------------------------------------------
# Generic helpers
# ------------------------------------------------------------------

func get_combat_team() -> String:
	return team_id


func get_network_state() -> Dictionary:
	return {
		"ai_id": str(get_meta("network_ai_id", name)),
		"ai_type": "farmer",
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
	team_marker.visible = (viewer_team.is_empty() or viewer_team == team_id) \
		and state != AIState.DEAD


func _get_combat_team(node: Node) -> String:
	if node == null:
		return ""
	if node.has_method("get_combat_team"):
		return str(node.call("get_combat_team"))
	for property_name in ["team_id", "team", "tool_owner"]:
		if _has_property(node, property_name):
			return str(node.get(property_name))
	return ""


func _set_property_if_present(
	object: Object,
	property_name: String,
	value: Variant
) -> void:
	if _has_property(object, property_name):
		object.set(property_name, value)


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _node_identity_text(node: Node) -> String:
	if node == null:
		return ""
	var text := node.name.to_lower()
	var script: Variant = node.get_script()
	if script is Script:
		text += " " + (script as Script).get_global_name().to_lower()
	if _has_property(node, "scene_file_path"):
		text += " " + str(node.get("scene_file_path")).to_lower()
	return text


func _normalize_identity(text: String) -> String:
	return text.to_lower().replace("_", "").replace("-", "").replace(" ", "")


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func _horizontal_direction(from_position: Vector3, to_position: Vector3) -> Vector3:
	var direction := to_position - from_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3.ZERO


func _schedule_think(delay: float = 0.12) -> void:
	state = AIState.THINK
	pending_task = FarmTask.NONE
	target_tile = null
	movement_target = INVALID_POSITION
	think_timer = maxf(0.0, delay)


func _task_name(task: int) -> String:
	match task:
		FarmTask.PLANT:
			return "plant"
		FarmTask.HARVEST:
			return "harvest"
		FarmTask.PLACE_PROTECTOR:
			return "plant_protector"
		FarmTask.PLACE_RUNNER:
			return "farm_runner"
		_:
			return "none"


func _debug_decision(message: String) -> void:
	if print_decisions:
		print("[FarmerAI] ", message)
