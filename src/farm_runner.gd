extends CharacterBody3D
class_name FarmRunner

## FarmRunner v19：阻挡后升高越障 + 五 RayCast 向下延长 + 每到新格尝试降回基础悬浮高度。
## 先悬浮 -> 勘测真实边界 -> 沿四条边播种/收获 -> 用真实边界进行 Z 字扫描。
##
## 必需节点：
## FarmRunner (CharacterBody3D)
## ├── Mesh
## ├── CollisionShape3D
## ├── Hit3D (Area3D)
## ├── center_cast   # 位于本机中心，垂直向下
## ├── forward_cast  # position=(0, 0, +tile_spacing)，垂直向下
## ├── backward_cast # position=(0, 0, -tile_spacing)，垂直向下
## ├── left_cast     # position=(-tile_spacing, 0, 0)，垂直向下
## └── right_cast    # position=(+tile_spacing, 0, 0)，垂直向下
##
## 强制约定：
## 1. 根节点、Mesh 与所有 RayCast3D 均不旋转；FarmRunner 只沿世界 X / Z 直线移动。
## 2. 五个 RayCast3D 的 enabled、collision_mask、exclude_parent、position、target_position
##    完全由场景手动设置，本脚本绝不修改。
## 3. forward_cast = 世界 +Z，backward_cast = 世界 -Z，
##    left_cast = 世界 -X，right_cast = 世界 +X。
##    注意：FarmTile.grid_coordinate 的 +X/+Z 不要求与世界 +X/+Z 同向；
##    本脚本会在启动时根据相邻 FarmTile 自动校准坐标方向映射。
## 4. FarmTile 必须具有唯一 grid_coordinate；同一农田必须具有相同且非空的 field_id。
## 5. FarmRunner 必须由 FarmTile.setting_tool() 作为该起始 FarmTile 的直接子节点创建。
##
## 启动流程：
## activate_tool()
## -> collision_layer = 128
## -> 从父 FarmTile 取得起点
## -> 立即升到 hover_height
## -> 自动校准 grid_coordinate 的 +X/+Z 与世界 Cast 方向的对应关系
## -> 再沿 width_direction 走到 grid +X/-X 边界，再沿 height_direction 走到 grid +Z/-Z 边界
## -> 每次按 Cast 偏移量实际走一整格，center_cast 确认边界后退一格
## -> 从该角开始绕四条边，边走边播种/收获
## -> 根据勘测到的真实 min/max X/Z 构建 Z 字扫描
##
## 出界保护：
## 任一移动阶段，FarmRunner 先完整走完一格；仅当 center_cast 在该完整目标点确认脚下没有
## “本 field_id 的 FarmTile”，才标记为田外并退回刚才那一整格；退回后重新读取五个 RayCast 再规划。

const CELL_UNKNOWN := 0
const CELL_FARM := 1
const CELL_EMPTY := 2

## presence（是否存在 FarmTile）与 access（当前是否能进入）分离。
## CELL_EMPTY 只允许在“已完整抵达目标中心，且 center_cast 确认无 FarmTile”时写入。
const ACCESS_WALKABLE := 0
const ACCESS_TEMP_BLOCKED := 1
const ACCESS_TOOL_OCCUPIED := 2

const CARDINAL_DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(-1, 0),
	Vector2i(0, 1),
	Vector2i(0, -1),
]

enum WorkState {
	WAITING_FOR_START_TILE,
	LIFTING,

	SURVEY_ADVANCE,
	SURVEY_MOVING,
	SURVEY_WORKING,
	SURVEY_BLOCKED,
	SURVEY_DETOUR_MOVING,

	## v19：物理阻挡不再横向绕路，改为垂直升高/下降。
	OVERFLIGHT_ASCENDING,
	OVERFLIGHT_LOWERING,

	PLAN_NEXT_TARGET,
	MOVING_ROUTE,
	WORKING_ON_TILE,

	BOUNDARY_BACKTRACK,
	RETURNING_HOME,
	RECOVERING,
	CYCLE_PAUSE,
	DESTROYED,
}

enum SurveyStage {
	FIND_X_EDGE,
	FIND_Z_EDGE,
	TRACE_PERIMETER,
}

enum RoutePurpose {
	TO_SCAN_TARGET,
	TO_HOME,
}

## 高空到达新格后，下降完成（或下降被挡后重新升高）要继续的到格收尾类型。
enum HeightResumeAction {
	NONE,
	SURVEY_TILE,
	ROUTE_STEP,
	BOUNDARY_BACKTRACK,
}

@export_category("Owner / Runtime")
@export var tool_owner: String = ""
@export var is_active: bool = false
@export_range(1.0, 10000.0, 1.0) var max_hp: float = 220.0

@export_category("Scan Safety Limit")
## 正常情况下，真正扫描范围由边界勘测自动得到。
## 这两个值只用于“勘测被其他工具阻断时”的保守回退范围。
@export_range(1, 64, 1) var field_height: int = 6
@export_range(1, 64, 1) var field_width: int = 6
@export_enum("+X", "-X") var width_direction: int = 0
@export_enum("+Z", "-Z") var height_direction: int = 0

@export_category("Movement")
@export_range(0.1, 10.0, 0.05) var hover_height: float = 0.5
@export_range(0.1, 20.0, 0.05) var work_move_speed: float = 2.5
@export_range(0.1, 20.0, 0.05) var vertical_follow_speed: float = 5.0
@export_range(0.01, 1.0, 0.01) var arrive_distance: float = 0.06
@export_range(0.0, 3.0, 0.05) var action_duration: float = 0.35
@export_range(0.0, 10.0, 0.05) var cycle_pause_duration: float = 0.5

@export_category("Stuck Recovery")
@export_range(0.5, 20.0, 0.1) var stuck_timeout: float = 2.0
@export_range(0.001, 1.0, 0.001) var stuck_progress_epsilon: float = 0.012
@export_range(0.5, 20.0, 0.1) var temporary_block_duration: float = 4.0
@export_range(1, 10, 1) var maximum_recovery_attempts: int = 3

@export_category("Return Home Recovery")
## 返航阶段也会检测“距离目标是否持续缩短”；此前版本没有这层检测，
## 因此返航路上再次被玩家/建筑挡住时会静止但没有明确日志。
@export_range(0.5, 20.0, 0.1) var return_home_stuck_timeout: float = 2.0
@export_range(0.05, 5.0, 0.05) var return_home_retry_delay: float = 0.60
@export_range(1, 10, 1) var return_home_max_retries: int = 3

## 仅在返航连续卡住 return_home_max_retries 次后触发。
## 用于避免机器被动态角色永久顶住，导致“已请求返航但永远到不了家”。
@export var emergency_snap_home_after_retries: bool = true

@export_category("Global No-Motion Return Watchdog")
## 覆盖所有“本应持续移动”的正常活动状态：
## 巡边移动、巡边受阻恢复、绕行、BFS 路线、回退、普通恢复。
## 不检查工作动作、等待、周期暂停和返航本身，避免正常静止误触发。
@export var global_no_motion_return_enabled: bool = true

## 连续这么久没有产生粗略水平位移，就强制启动返航。
## 它不读取额外 RayCast、不执行额外 BFS，只读取自身 global_position。
@export_range(2.0, 120.0, 1.0) var global_no_motion_return_timeout: float = 20.0

## 位置变化达到这个水平距离，视为“仍在运动”，并重置 20 秒计时。
## 故意做得粗糙，避免微小物理抖动无限延长计时。
@export_range(0.01, 2.0, 0.01) var global_no_motion_position_epsilon: float = 0.10

@export_category("Boundary Survey")
@export var survey_boundary_on_start: bool = true

## 小车已经判定“前进受阻”后，需要先退回 last_safe_world_position。
## 若连回退也在此时间内没有接近安全格，说明双向都被卡住：
## 直接走返航重启流程，不会永远停在 SURVEY_BLOCKED。
@export_range(0.5, 20.0, 0.1) var survey_safe_return_stuck_timeout: float = 1.5
## 保留给你手动调用 _finish_boundary_survey_with_known_bounds() 的兼容选项。
## 自动巡边在阻挡重试耗尽后会返航并重新勘测，不再自动退化为局部范围扫描。
@export var fallback_to_known_bounds_when_survey_blocked: bool = true

@export_category("Boundary Detour")
## 巡边时被玩家、建筑或其他碰撞体挡住后，先回到最后一个确认安全格，
## 再尝试沿与 survey_direction 垂直的方向绕一格，随后继续原来的边界确认任务。
@export_range(0.05, 3.0, 0.05) var survey_block_retry_delay: float = 0.45
@export_range(1, 12, 1) var survey_block_max_retries: int = 5
@export_range(0, 12, 1) var survey_detour_max_steps: int = 4

@export_category("Obstacle Overflight")
## 物理碰撞阻挡时：不改变原本的 X/Z 格子路线，不进行侧向绕行。
## 仅升到基础悬浮高度以上，再沿原方向继续移动。
@export var obstacle_overflight_enabled: bool = true

## 默认 +8m。基础 hover_height=0.5m 时，目标高度为离地约 8.5m。
@export_range(0.5, 30.0, 0.5) var obstacle_overflight_height: float = 8.0

## 越障时对五个向下 RayCast3D 的 target_position.y 额外向下延长。
## 例如初始 target_position.y=-3，extension=8 时会变为 -11。
@export_range(0.5, 30.0, 0.5) var obstacle_overflight_raycast_extension: float = 8.0

## 到达真实 FarmTile 后，若当前在高空，先尝试下降回基础高度。
## 连续这么久没有明显下降，表示下方仍有玩家/工具/建筑；重新升高并保持高空。
@export_range(0.10, 5.0, 0.05) var overflight_lower_stuck_timeout: float = 0.50
@export_range(0.001, 0.50, 0.001) var overflight_lower_progress_epsilon: float = 0.02

@export_category("Low Frequency Map Reconciliation")
## 非关键时刻最多每隔此时间才读一次五条 Cast。
## 关键节点（到格、回退、受阻）会请求一次立即刷新。
@export_range(0.10, 3.0, 0.05) var local_reconcile_interval: float = 0.35
## frontier 中每次规划最多尝试几个候选，防止一次规划反复 BFS。
@export_range(1, 16, 1) var frontier_candidates_per_plan: int = 4

## center_cast 与四周四条 Cast 在连续这么多次“低频校验”中都没有
## 本 field_id 的 FarmTile，说明 Runner 已经脱离农田或状态异常：
## 立即回到起始 FarmTile，并清空本轮地图后重新开始边界勘测。
## 2 次可避免一次瞬时射线漏检就误触发返航。
@export_range(1, 6, 1) var no_local_farmtile_checks_before_return: int = 2

@export_category("RayCast")
## 五个 RayCast3D 的 position、rotation、enabled、collision_mask、exclude_parent 均由场景手动配置。
## 本脚本只会在升高越障期间临时延长 target_position.y，下降到基础高度后恢复其初始长度。

@export_category("Grid / World Mapping")
## true：启动后用 center_cast 与四周 Cast 命中的 FarmTile.grid_coordinate，
## 自动推导“grid +X / +Z 分别对应哪个世界方向”。
## 你的日志显示 grid +X 实际对应世界 -X，因此必须开启。
@export var auto_calibrate_grid_world_mapping: bool = true

@export_category("SeedEmitter")
## 场景中可以不放 SeedEmitter；脚本会运行时自动创建黄色种子粒子。
@export var auto_create_seed_emitter: bool = true
@export_range(1, 64, 1) var seed_particle_count: int = 18
@export_range(0.1, 3.0, 0.05) var seed_particle_lifetime: float = 0.55
@export_range(0.005, 0.10, 0.001) var seed_particle_radius: float = 0.025
@export_range(0.01, 0.40, 0.01) var seed_particle_spread_radius: float = 0.10
@export_range(0.01, 2.0, 0.01) var seed_particle_speed_min: float = 0.35
@export_range(0.01, 2.0, 0.01) var seed_particle_speed_max: float = 0.75
@export_range(-0.20, 0.30, 0.01) var seed_emitter_ground_offset: float = 0.08
@export var seed_particle_color: Color = Color(1.0, 0.78, 0.12, 1.0)

@export_category("Debug")
@export var print_debug: bool = false

## true 时，阻挡、重试、绕行、返航、返航卡住与强制回家都会打印。
## 这些日志只在状态切换或一次重试发生时打印，不会每 physics frame 刷屏。
@export var print_block_debug: bool = true
@export var hp_debug_label: bool = true

@onready var hit_3d: Area3D = $Hit3D
## 返航时仅关闭根 CharacterBody3D 的物理碰撞形状；
## Hit3D 是 Area3D，保持启用，仍可接收攻击回调。
@onready var runner_collision_shape: CollisionShape3D = $CollisionShape3D
@onready var center_cast: RayCast3D = $center_cast
@onready var forward_cast: RayCast3D = $forward_cast
@onready var backward_cast: RayCast3D = $backward_cast
@onready var left_cast: RayCast3D = $left_cast
@onready var right_cast: RayCast3D = $right_cast
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

var seed_emitter: GPUParticles3D

var current_hp: float = 0.0
var work_state: int = WorkState.WAITING_FOR_START_TILE
var initialized: bool = false

# coord -> {
#   state: CELL_UNKNOWN / CELL_FARM / CELL_EMPTY,
#   access: ACCESS_WALKABLE / ACCESS_TEMP_BLOCKED / ACCESS_TOOL_OCCUPIED,
#   tile, walkable, seen, walked, last_seen_msec
# }
var discovered_map: Dictionary = {}
var temporary_blocked_cells: Dictionary = {}

# 低频五 Cast 校验调度；正常移动阶段不会每个 physics frame 强制刷新五条 RayCast。
var _local_reconcile_timer: float = 0.0
var _local_reconcile_requested: bool = true

## 复用已有五 Cast 低频校验的 found_count，不额外增加射线刷新。
var _no_local_farmtile_check_count: int = 0

## true 时 RETURNING_HOME 抵达起始 FarmTile 后，不进入普通扫描，
## 而是清空本轮勘测数据并重新做完整边界检测。
var _restart_boundary_survey_after_home: bool = false
var _restart_boundary_survey_reason: String = ""

# 后续发现的新地块 / 已恢复可走地块优先进入前沿队列。
# 只有触发新发现、边界扩展、阻挡释放时入队；不会每帧 BFS。
var frontier_queue: Array[Vector2i] = []
var frontier_set: Dictionary = {}
var scan_order_dirty: bool = false
var scan_processed_this_cycle: Dictionary = {}
var _active_target_is_frontier: bool = false

var start_tile: FarmTile
var start_field_id: String = ""
var start_grid_coord: Vector2i = Vector2i.ZERO
var current_grid_coord: Vector2i = Vector2i.ZERO
var last_safe_grid_coord: Vector2i = Vector2i.ZERO
var start_world_tile_position: Vector3 = Vector3.ZERO
var hover_world_y: float = 0.0

# 由手动摆放的 RayCast3D 位置自动测得，不读取 FarmTile.tile_spacing。
# step_right_world / step_forward_world 仅表示“物理 Cast 偏移”。
# grid +X/+Z 对应的世界位移由启动校准变量 grid_positive_x_world / grid_positive_z_world 决定。
var step_right_world: Vector3 = Vector3.ZERO
var step_forward_world: Vector3 = Vector3.ZERO
var step_x_distance: float = 0.0
var step_z_distance: float = 0.0

## grid 坐标轴到世界位移的映射。
## 不再假设 grid +X 一定等于世界 +X，也不再假设 grid +Z 一定等于世界 +Z。
## 例：若 right_cast 命中的邻居 grid delta 是 (-1, 0)，
## 则 grid +X 实际对应世界 -X（left_cast 的方向）。
var grid_positive_x_world: Vector3 = Vector3.ZERO
var grid_positive_z_world: Vector3 = Vector3.ZERO
var grid_direction_mapping: Dictionary = {}
var grid_mapping_calibrated: bool = false

# 最近一次经 center_cast 实际确认的“农田内格子中心”。
# 出界时严格退回这里，正好就是反方向的一整格。
var last_safe_world_position: Vector3 = Vector3.ZERO

# 真实农田范围：由边界巡逻中的同 field_id FarmTile 自动更新。
var field_bounds_ready: bool = false
var field_min_x: int = 0
var field_max_x: int = 0
var field_min_z: int = 0
var field_max_z: int = 0

# 边界巡逻状态。
var survey_stage: int = SurveyStage.FIND_X_EDGE
var survey_direction: Vector2i = Vector2i.ZERO
var survey_side_index: int = 0
var survey_move_target_coord: Vector2i = Vector2i.ZERO
var survey_move_target_world: Vector3 = Vector3.ZERO
var survey_processed_coords: Dictionary = {}

# 巡边受阻后的局部避障状态。
# survey_direction 始终是“真正要确认哪一条边”的方向；
# detour_direction 只是临时横向绕过玩家/建筑的方向。
var survey_blocked_target_coord: Vector2i = Vector2i.ZERO
var survey_blocked_reason: String = ""
var survey_block_retry_left: float = 0.0
var survey_block_retry_count: int = 0
var survey_retry_original_pending: bool = false
var survey_detour_count: int = 0
var survey_detour_direction: Vector2i = Vector2i.ZERO
var survey_detour_target_coord: Vector2i = Vector2i.ZERO
var survey_detour_target_world: Vector3 = Vector3.ZERO
var survey_detour_tried_coords: Dictionary = {}
var survey_block_needs_safe_return: bool = false
var survey_safe_return_last_distance: float = INF
var survey_safe_return_stuck_time: float = 0.0
var boundary_survey_incomplete: bool = false

## base_hover_world_y 是正常工作高度；hover_world_y 是当前目标高度。
## 越障时 hover_world_y = base_hover_world_y + obstacle_overflight_height。
var base_hover_world_y: float = 0.0
var overflight_active: bool = false
var overflight_resume_state: int = WorkState.PLAN_NEXT_TARGET
var overflight_finish_after_raise: bool = false

## 新格下降尝试完成后要继续的工作。
var height_resume_action: int = HeightResumeAction.NONE
var height_resume_tile: FarmTile
var overflight_lower_last_y: float = 0.0
var overflight_lower_stuck_time: float = 0.0

## 备份五条 RayCast 的初始 target_position，避免假定所有初始长度都是 -3。
var base_raycast_target_positions: Dictionary = {}

## 只有完整四边巡逻由 center_cast 确认后才为 true。
## 返航时以此决定：
## - false：清空本轮地图，回家后重新边界检测；
## - true：保留已确认边界，回家后继续现有扫描任务。
var boundary_survey_confirmed: bool = false

# 常规 Z 字扫描状态。
var scan_order: Array[Vector2i] = []
var scan_index: int = 0
var desired_scan_coord: Vector2i = Vector2i.ZERO

# 常规 BFS 路线状态。
var current_route: Array[Vector2i] = []
var route_index: int = 0
var route_purpose: int = RoutePurpose.TO_SCAN_TARGET
var movement_goal_coord: Vector2i = Vector2i.ZERO

# 动作 / 卡住 / 回退状态。
var action_time_left: float = 0.0
var cycle_pause_left: float = 0.0
var last_goal_distance: float = INF
var stuck_time: float = 0.0
var recovery_attempt_count: int = 0
var recovery_world_goal: Vector3 = Vector3.ZERO

## RETURNING_HOME 专用卡住检测。与巡边 / 普通路线分开，避免互相污染计时。
var return_home_last_goal_distance: float = INF
var return_home_stuck_time: float = 0.0
var return_home_retry_count: int = 0
var return_home_retry_left: float = 0.0

## 全局无位移看门狗：只读自身水平位置，不触发额外 Cast/BFS。
var _global_motion_watch_active: bool = false
var _global_motion_watch_last_position: Vector3 = Vector3.ZERO
var _global_motion_watch_still_time: float = 0.0

## 返航期间临时关闭根 CollisionShape3D，避免被角色、工具、建筑阻挡。
## 记录原始 disabled 状态，确保到家后恢复场景原本配置。
var _return_home_collision_override_active: bool = false
var _runner_collision_previous_disabled: bool = false

# 出界后，必须退回的上一格，以及退回完成后应该进入的状态。
var boundary_backtrack_coord: Vector2i = Vector2i.ZERO
var boundary_resume_state: int = WorkState.PLAN_NEXT_TARGET
# true 表示刚才的“走完整整一格后 center_cast 为空”已确认是巡边终点。
var boundary_backtrack_is_confirmed_survey_edge: bool = false

var home:StaticBody3D
const NETWORK_VISUAL_INTERPOLATION_SPEED := 12.0
var _network_visual_target_position := Vector3.ZERO
var _network_visual_target_yaw := 0.0
var _has_network_visual_state := false
var _electronics_disabled_remaining := 0.0

#func _ready() -> void:
	#print("GENERATE Farm Runner!")

func _physics_process(delta: float) -> void:
	# Remote FarmRunner instances are snapshot visuals only. Harvesting remains
	# on the server, which emits the confirmed absorption event for every client.
	if GameAuthority.is_client_proxy():
		_update_network_visual(delta)
		velocity = Vector3.ZERO
		return
	_electronics_disabled_remaining = maxf(0.0, _electronics_disabled_remaining - delta)
	if is_electronics_disabled():
		velocity = Vector3.ZERO
		return
	if work_state == WorkState.DESTROYED:
		return

	if not is_active:
		velocity = Vector3.ZERO
		return

	# 启动期间不需要任何 RayCast：直接依据父 FarmTile 上升。
	if work_state == WorkState.LIFTING:
		_move_to_hover_height()
		if absf(global_position.y - hover_world_y) <= 0.025:
			global_position.y = hover_world_y
			velocity = Vector3.ZERO
			_finish_initialization_after_lift()
		return

	if not initialized:
		_begin_startup_lift()
		return

	_cleanup_temporary_blocks()

	# 低频地图校验：
	# - 常态约每 local_reconcile_interval 秒读取一次 5 条 Cast；
	# - 到格、回退、受阻、阻挡解除会主动请求立即校验；
	# - 不在每个 physics frame 强制刷新五条 RayCast。
	_update_local_reconcile_scheduler(delta)

	match work_state:
		WorkState.SURVEY_ADVANCE:
			_advance_boundary_survey()

		WorkState.SURVEY_MOVING:
			_move_survey_step(delta)

		WorkState.SURVEY_WORKING:
			_hold_hover()
			action_time_left -= delta
			if action_time_left <= 0.0:
				work_state = WorkState.SURVEY_ADVANCE

		WorkState.SURVEY_BLOCKED:
			_update_survey_blocked(delta)

		WorkState.SURVEY_DETOUR_MOVING:
			_move_survey_detour(delta)

		WorkState.OVERFLIGHT_ASCENDING:
			_update_overflight_ascending(delta)

		WorkState.OVERFLIGHT_LOWERING:
			_update_overflight_lowering(delta)

		WorkState.PLAN_NEXT_TARGET:
			_plan_next_target()

		WorkState.MOVING_ROUTE:
			_move_along_current_route(delta)

		WorkState.WORKING_ON_TILE:
			_hold_hover()
			action_time_left -= delta
			if action_time_left <= 0.0:
				_advance_scan_target()

		WorkState.CYCLE_PAUSE:
			_hold_hover()
			cycle_pause_left -= delta
			if cycle_pause_left <= 0.0:
				scan_index = 0
				scan_processed_this_cycle.clear()
				work_state = WorkState.PLAN_NEXT_TARGET

		WorkState.BOUNDARY_BACKTRACK:
			_move_cardinal_to_world(recovery_world_goal)
			if not _is_at_world_goal(recovery_world_goal):
				var backtrack_distance: float = _flat_distance(
					global_position,
					recovery_world_goal
				)
				_update_stuck_watch(
					backtrack_distance,
					delta,
					WorkState.BOUNDARY_BACKTRACK,
					"Boundary backtrack blocked before last safe tile."
				)
				if work_state != WorkState.BOUNDARY_BACKTRACK:
					return
				if not _is_at_world_goal(recovery_world_goal):
					return

			_snap_to_hover_goal(recovery_world_goal)
			_observe_center_tile_during_return()
			_request_local_reconcile(true)
			_finish_boundary_backtrack()

		WorkState.RETURNING_HOME:
			_update_returning_home(delta)

		WorkState.RECOVERING:
			_move_cardinal_to_world(recovery_world_goal)
			if not _is_at_world_goal(recovery_world_goal):
				var recovery_distance: float = _flat_distance(
					global_position,
					recovery_world_goal
				)
				_update_stuck_watch(
					recovery_distance,
					delta,
					WorkState.RECOVERING,
					"Recovery movement blocked before last safe tile."
				)
				if work_state != WorkState.RECOVERING:
					return
				if not _is_at_world_goal(recovery_world_goal):
					return

			_snap_to_hover_goal(recovery_world_goal)
			_observe_center_tile_during_return()
			_request_local_reconcile(true)
			stuck_time = 0.0
			last_goal_distance = INF
			work_state = WorkState.PLAN_NEXT_TARGET

	# 独立于 BLOCK 状态、RayCast 和 BFS 的最终活动兜底。
	# 只监控“按设计本来应该移动”的状态；连续 20 秒几乎没有水平位移才返航。
	_update_global_no_motion_return_watchdog(delta)


# ------------------------------------------------------------------
# Public API
# ------------------------------------------------------------------

func activate_tool() -> void:
	print(self)
	print(self.get_parent())
	_connect_hit_callbacks()
	_ensure_seed_emitter()
	# Godot 第 8 个 Collision Layer，对应掩码 1 << 7 = 128。
	collision_layer = 128
	_set_runner_collision_enabled(true, "activate_tool")
	_reset_global_no_motion_return_watchdog()
	is_active = true
	self.rotation_degrees=Vector3.ZERO
	current_hp = max_hp
	_update_health_label()
	if not is_node_ready():
		call_deferred("_begin_startup_lift")
		return
	
	_begin_startup_lift()


func emit() -> void:
	# 用于“手持 FarmRunner 部署工具”。
	# 默认层级：当前工具 -> ToolPivot -> 武器节点 -> 玩家。
	
	if tool_owner.is_empty():
		return

	var setting_player: Node3D = get_node_or_null("../../../") as Node3D
	if setting_player == null:
		return

	var raycast: RayCast3D = setting_player.find_child("LookAtTarget", true) as RayCast3D
	if raycast == null:
		return

	raycast.force_raycast_update()
	if not raycast.is_colliding():
		return

	var tile := Farmlandmanager.resolve_raycast_tile(raycast)
	if tile != null:
		tile.setting_tool("FarmRunner", tool_owner, setting_player)
		home =  load("res://character/weapons/RunnerHome.tscn").instantiate()
		tile.add_child(home)
		home.global_position = tile.global_position + Vector3(0,0.1,0)
		
func deactivate_tool() -> void:
	is_active = false
	velocity = Vector3.ZERO
	_set_runner_collision_enabled(true, "deactivate_tool")
	_reset_global_no_motion_return_watchdog()


## 外部可调用的返航请求。
## 边界尚未完整确认时：回家后清空旧地图并重新边界检测；
## 边界已确认时：仅回家，保留已确认边界与扫描进度。
func request_return_home(reason: String = "External return request") -> void:
	_request_return_home_for_current_boundary_phase(reason)


## 若你在运行中重新摆放 FarmTile、修改 grid_coordinate，
## 可在小车正停在一个 FarmTile 中心时由外部调用它。
func recalibrate_grid_world_mapping() -> bool:
	return _calibrate_grid_world_mapping()


func impact(effect: String, strength: float, attacker_team: String = "") -> bool:
	if work_state == WorkState.DESTROYED:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	var normalized_effect := effect.to_lower()
	if normalized_effect == "repair_laser" or normalized_effect == "lightening" or normalized_effect == "lightning":
		var duration_effect := "repair_laser" if normalized_effect == "repair_laser" else "lightning"
		_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, CombatBalance.get_electronic_disable_duration("farm_runner", duration_effect))
		velocity = Vector3.ZERO
		return true
	if strength <= 0.0:
		return false

	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	_debug("Impact=%s strength=%.1f hp=%.1f" % [effect, strength, current_hp])
	
	
	## 增加效果处理代码
	
	if current_hp <= 0.0:
		_destroy_runner()
	return true


func is_electronics_disabled() -> bool:
	return _electronics_disabled_remaining > 0.0


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	is_active = true
	_update_health_label()


func get_network_visual_state() -> Dictionary:
	return {
		"position": global_position,
		"yaw": rotation.y,
		"is_active": is_active,
		"electronics_disabled_remaining": _electronics_disabled_remaining,
	}


func apply_network_visual_state(state: Dictionary) -> void:
	var position_value: Variant = state.get("position", global_position)
	if position_value is Vector3:
		_network_visual_target_position = position_value
		if not _has_network_visual_state:
			global_position = _network_visual_target_position
	_network_visual_target_yaw = float(state.get("yaw", rotation.y))
	is_active = bool(state.get("is_active", is_active))
	_electronics_disabled_remaining = maxf(_electronics_disabled_remaining, float(state.get("electronics_disabled_remaining", 0.0)))
	_has_network_visual_state = true
	_update_health_label()


func enable_network_visuals() -> void:
	# FarmTile disables normal tool gameplay on client replicas. FarmRunner still
	# needs its physics callback to interpolate authoritative transform snapshots.
	set_process(false)
	set_physics_process(true)
	set_process_input(false)
	collision_layer = 0
	collision_mask = 0
	var root_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if root_shape != null:
		root_shape.set_deferred("disabled", true)
	if is_instance_valid(hit_3d):
		hit_3d.monitoring = false
		hit_3d.monitorable = false
	for cast in [center_cast, forward_cast, backward_cast, left_cast, right_cast]:
		if is_instance_valid(cast):
			cast.enabled = false


func _update_network_visual(delta: float) -> void:
	if not _has_network_visual_state:
		return
	var blend := clampf(delta * NETWORK_VISUAL_INTERPOLATION_SPEED, 0.0, 1.0)
	global_position = global_position.lerp(_network_visual_target_position, blend)
	rotation.y = lerp_angle(rotation.y, _network_visual_target_yaw, blend)


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and is_active
	health_label.text = "%d" % int(ceil(current_hp))


# ------------------------------------------------------------------
# Startup
# ------------------------------------------------------------------

func _begin_startup_lift() -> void:
	if work_state == WorkState.DESTROYED or not is_active:
		return
	if work_state == WorkState.LIFTING or initialized:
		return
	if tool_owner.is_empty():
		_debug("Cannot start: tool_owner is empty.")
		return

	# FarmTile.setting_tool() 会把 FarmRunner 作为起始 FarmTile 的直接子节点。
	var parent_tile: FarmTile = get_parent() as FarmTile
	if parent_tile == null:
		_debug("Cannot start: direct parent is not FarmTile.")
		return

	start_tile = parent_tile
	start_field_id = start_tile.field_id
	_no_local_farmtile_check_count = 0
	boundary_survey_confirmed = false
	_set_runner_collision_enabled(true, "startup_lift")
	_reset_global_no_motion_return_watchdog()
	start_grid_coord = start_tile.grid_coordinate
	current_grid_coord = start_grid_coord
	last_safe_grid_coord = start_grid_coord
	start_world_tile_position = start_tile.global_position

	# 每一格的实际移动距离由“相邻 Cast 与 center_cast 的位置差”决定。
	# 不使用 FarmTile.tile_spacing，因此你把四个方向 Cast 设为 2.5m 偏移时，
	# FarmRunner 就会严格每次移动 2.5m。
	if not _read_grid_step_from_manual_cast_offsets():
		_debug("Cannot start: manual RayCast offsets are invalid.")
		return

	# field_id 为空时，无法区分两块相邻农田；仍会运行，但所有空 field_id 的相邻地块会被视为同一片。
	if start_field_id.is_empty():
		_debug("Warning: start FarmTile.field_id is empty. Adjacent empty field_id tiles are treated as one field.")

	base_hover_world_y = start_world_tile_position.y + hover_height
	hover_world_y = base_hover_world_y
	overflight_active = false
	overflight_finish_after_raise = false
	height_resume_action = HeightResumeAction.NONE
	height_resume_tile = null
	_cache_base_raycast_target_positions()
	_restore_base_raycast_lengths("startup")

	last_safe_world_position = Vector3(
		start_world_tile_position.x,
		hover_world_y,
		start_world_tile_position.z
	)
	_update_seed_emitter_position()

	work_state = WorkState.LIFTING
	_debug("Lift begins. start=%s field_id=%s hover_y=%.3f" % [
		start_grid_coord,
		start_field_id,
		hover_world_y,
	])


func _finish_initialization_after_lift() -> void:
	if start_tile == null or not is_instance_valid(start_tile):
		initialized = false
		work_state = WorkState.WAITING_FOR_START_TILE
		_debug("Startup failed: start FarmTile disappeared.")
		return

	_register_farm_tile(start_tile)
	last_safe_world_position = Vector3(
		start_tile.global_position.x,
		hover_world_y,
		start_tile.global_position.z
	)
	_observe_local_farm_tiles()

	if auto_calibrate_grid_world_mapping:
		_calibrate_grid_world_mapping()

	_request_local_reconcile(true)

	initialized = true

	if survey_boundary_on_start:
		_begin_boundary_survey()
	else:
		# 未开启边界巡逻时，按原本 H x W 安全范围构建扫描。
		_build_fallback_bounds_from_exports()
		_build_serpentine_scan_order_from_bounds()
		work_state = WorkState.PLAN_NEXT_TARGET


# ------------------------------------------------------------------
# Boundary survey: full-step center confirmation + local obstacle detours
# ------------------------------------------------------------------
#
# 边界确认唯一合法条件：
# 1) FarmRunner 已完整抵达理论下一格中心；
# 2) 该位置的 center_cast 没有命中同 field_id FarmTile。
#
# 物理阻挡、玩家、建筑、工具占据、卡住：
# - 都不是边界；
# - 不写 CELL_EMPTY；
# - 先回到 last_safe_world_position；
# - 用四周 Cast 只选择“垂直于 survey_direction”的一格小绕行；
# - 然后继续原来的 survey_direction，仍在执行同一条边的确认任务。

func _begin_boundary_survey() -> void:
	boundary_survey_confirmed = false
	survey_processed_coords.clear()
	survey_detour_tried_coords.clear()
	survey_stage = SurveyStage.FIND_X_EDGE
	survey_direction = _width_direction_vector()
	survey_side_index = 0
	survey_block_retry_count = 0
	survey_retry_original_pending = false
	survey_detour_count = 0
	boundary_survey_incomplete = false

	work_state = WorkState.SURVEY_ADVANCE
	_request_local_reconcile(true)

	# 边界勘测不是“只走边不工作”：
	# 从起始格起，所有实际到达并 center_cast 确认的 FarmTile 都同步尝试播种/收获。
	# 起始格若被本 FarmRunner 自己占据，FarmTile.plant() 本身会拒绝，函数会安全跳过。
	var initial_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if initial_tile != null and _is_same_field_tile(initial_tile):
		_service_survey_tile(initial_tile)

	_debug(
		"Boundary survey starts. step_x=%.3f step_z=%.3f, first direction=%s."
		% [step_x_distance, step_z_distance, survey_direction]
	)


func _advance_boundary_survey() -> void:
	# 不把相邻 Cast 未命中当成边界。
	# 无论四周 Cast 当前是否命中，都必须先完整移动一格，再用 center_cast 最终裁决。
	survey_move_target_coord = current_grid_coord + survey_direction
	survey_move_target_world = last_safe_world_position + _world_step_for_direction(
		survey_direction
	)

	last_goal_distance = INF
	stuck_time = 0.0
	work_state = WorkState.SURVEY_MOVING

	if survey_block_retry_count > 0:
		_block_debug(
			(
				"SURVEY_RETRY_MOVE origin=%s target=%s direction=%s world_goal=%s "
				+ "block_count=%d/%d."
			)
			% [
				current_grid_coord,
				survey_move_target_coord,
				survey_direction,
				survey_move_target_world,
				survey_block_retry_count,
				survey_block_max_retries,
			]
		)


func _move_survey_step(delta: float) -> void:
	_move_cardinal_to_world(survey_move_target_world)

	if not _is_at_world_goal(survey_move_target_world):
		var distance: float = _flat_distance(
			global_position,
			survey_move_target_world
		)
		_update_survey_stuck_watch(distance, delta)

		if work_state != WorkState.SURVEY_MOVING:
			return

		if not _is_at_world_goal(survey_move_target_world):
			return

	_snap_to_hover_goal(survey_move_target_world)

	var arrived_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if arrived_tile == null or not _is_same_field_tile(arrived_tile):
		_begin_confirmed_survey_edge_backtrack(
			"Moved one full step to %s, then center_cast found no same-field FarmTile."
			% survey_move_target_coord
		)
		return

	_register_farm_tile(arrived_tile)
	current_grid_coord = arrived_tile.grid_coordinate
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		arrived_tile.global_position.x,
		hover_world_y,
		arrived_tile.global_position.z
	)
	_mark_cell_walked(current_grid_coord)
	_request_local_reconcile(true)

	# 处于高空时：在该新 FarmTile 上先尝试降到基础 hover。
	if _begin_lower_after_arrival(
		HeightResumeAction.SURVEY_TILE,
		arrived_tile
	):
		return

	_finalize_survey_tile_after_height(arrived_tile)

func _update_survey_stuck_watch(
	distance_to_goal: float,
	delta: float
) -> void:
	if last_goal_distance == INF:
		last_goal_distance = distance_to_goal
		return

	if last_goal_distance - distance_to_goal >= stuck_progress_epsilon:
		last_goal_distance = distance_to_goal
		stuck_time = 0.0
		return

	stuck_time += delta
	if stuck_time < stuck_timeout:
		return

	_block_debug(
		(
			"OVERFLIGHT_TRIGGER survey_target=%s distance=%.3f "
			+ "stuck=%.2f/%.2f contacts=%s."
		)
		% [
			survey_move_target_coord,
			distance_to_goal,
			stuck_time,
			stuck_timeout,
			_get_recent_slide_collision_summary(),
		]
	)

	_begin_overflight_for_resume(
		WorkState.SURVEY_MOVING,
		"Survey movement blocked before center_cast could confirm %s."
		% survey_move_target_coord
	)

func _cache_base_raycast_target_positions() -> void:
	if not base_raycast_target_positions.is_empty():
		return

	for cast in _all_farm_raycast_nodes():
		if cast == null:
			continue

		var key: String = str(cast.get_path())
		base_raycast_target_positions[key] = cast.target_position


func _apply_overflight_raycast_lengths(reason: String = "") -> void:
	_cache_base_raycast_target_positions()

	for cast in _all_farm_raycast_nodes():
		if cast == null:
			continue

		var key: String = str(cast.get_path())
		var base_target: Variant = base_raycast_target_positions.get(
			key,
			cast.target_position
		)

		if base_target is Vector3:
			var target: Vector3 = base_target as Vector3
			cast.target_position = Vector3(
				target.x,
				target.y - obstacle_overflight_raycast_extension,
				target.z
			)

	_block_debug(
		(
			"OVERFLIGHT_RAYCAST_EXTENDED extension=%.2f center_target_y=%.2f "
			+ "reason=%s."
		)
		% [
			obstacle_overflight_raycast_extension,
			center_cast.target_position.y,
			reason,
		]
	)


func _restore_base_raycast_lengths(reason: String = "") -> void:
	if base_raycast_target_positions.is_empty():
		return

	for cast in _all_farm_raycast_nodes():
		if cast == null:
			continue

		var key: String = str(cast.get_path())
		var base_target: Variant = base_raycast_target_positions.get(
			key,
			null
		)
		if base_target is Vector3:
			cast.target_position = base_target as Vector3

	_block_debug(
		"OVERFLIGHT_RAYCAST_RESTORED center_target_y=%.2f reason=%s."
		% [center_cast.target_position.y, reason]
	)


func _begin_overflight_for_resume(
	resume_state: int,
	reason: String
) -> void:
	if not obstacle_overflight_enabled:
		_block_debug(
			"OVERFLIGHT_DISABLED state=%s reason=%s."
			% [_work_state_name(resume_state), reason]
		)
		stuck_time = 0.0
		last_goal_distance = INF
		return

	overflight_active = true
	overflight_resume_state = resume_state
	overflight_finish_after_raise = false
	hover_world_y = base_hover_world_y + obstacle_overflight_height
	_apply_overflight_raycast_lengths(reason)
	_update_seed_emitter_position()

	stuck_time = 0.0
	last_goal_distance = INF
	work_state = WorkState.OVERFLIGHT_ASCENDING

	_block_debug(
		(
			"OVERFLIGHT_ASCEND_BEGIN resume=%s base_y=%.3f target_y=%.3f "
			+ "reason=%s."
		)
		% [
			_work_state_name(resume_state),
			base_hover_world_y,
			hover_world_y,
			reason,
		]
	)


func _update_overflight_ascending(_delta: float) -> void:
	_move_to_hover_height()

	if absf(global_position.y - hover_world_y) > 0.025:
		return

	global_position.y = hover_world_y
	velocity = Vector3.ZERO
	_request_local_reconcile(true)

	_block_debug(
		"OVERFLIGHT_ASCEND_REACHED y=%.3f finish_arrival=%s."
		% [global_position.y, overflight_finish_after_raise]
	)

	if overflight_finish_after_raise:
		overflight_finish_after_raise = false
		_complete_height_resume_action()
		return

	work_state = overflight_resume_state


func _begin_lower_after_arrival(
	resume_action: int,
	tile: FarmTile
) -> bool:
	if not overflight_active:
		return false

	if global_position.y <= base_hover_world_y + 0.025:
		overflight_active = false
		hover_world_y = base_hover_world_y
		_restore_base_raycast_lengths("already at base")
		return false

	height_resume_action = resume_action
	height_resume_tile = tile
	overflight_lower_last_y = global_position.y
	overflight_lower_stuck_time = 0.0

	# 保持延长的 downward casts，直到确认确实降回基础高度。
	hover_world_y = base_hover_world_y
	work_state = WorkState.OVERFLIGHT_LOWERING

	_block_debug(
		(
			"OVERFLIGHT_LOWER_ATTEMPT action=%s from_y=%.3f base_y=%.3f "
			+ "tile=%s."
		)
		% [
			_height_resume_action_name(resume_action),
			global_position.y,
			base_hover_world_y,
			tile.grid_coordinate if tile != null else Vector2i.ZERO,
		]
	)
	return true


func _update_overflight_lowering(delta: float) -> void:
	_move_to_hover_height()

	if global_position.y <= base_hover_world_y + 0.025:
		global_position.y = base_hover_world_y
		velocity = Vector3.ZERO
		overflight_active = false
		_restore_base_raycast_lengths("lower succeeded")
		_update_seed_emitter_position()

		_block_debug(
			"OVERFLIGHT_LOWER_SUCCEEDED y=%.3f."
			% global_position.y
		)
		_complete_height_resume_action()
		return

	var lowered_distance: float = (
		overflight_lower_last_y - global_position.y
	)
	if lowered_distance >= overflight_lower_progress_epsilon:
		overflight_lower_last_y = global_position.y
		overflight_lower_stuck_time = 0.0
		return

	overflight_lower_stuck_time += delta
	if overflight_lower_stuck_time < overflight_lower_stuck_timeout:
		return

	# 下降不下去：重新升回完整高空，而不是停在半空。
	hover_world_y = base_hover_world_y + obstacle_overflight_height
	overflight_active = true
	overflight_finish_after_raise = true
	overflight_lower_last_y = global_position.y
	overflight_lower_stuck_time = 0.0
	work_state = WorkState.OVERFLIGHT_ASCENDING
	_update_seed_emitter_position()

	_block_debug(
		(
			"OVERFLIGHT_LOWER_BLOCKED y=%.3f timeout=%.2f; "
			+ "reascend_to=%.3f and continue high."
		)
		% [
			global_position.y,
			overflight_lower_stuck_timeout,
			hover_world_y,
		]
	)


func _complete_height_resume_action() -> void:
	var action: int = height_resume_action
	var tile: FarmTile = height_resume_tile

	height_resume_action = HeightResumeAction.NONE
	height_resume_tile = null

	if tile == null or not is_instance_valid(tile):
		tile = _get_farm_tile_from_cast(center_cast)

	match action:
		HeightResumeAction.SURVEY_TILE:
			if tile == null or not _is_same_field_tile(tile):
				_request_return_home_for_current_boundary_phase(
					"FarmTile disappeared while finalizing survey overflight."
				)
				return
			_finalize_survey_tile_after_height(tile)

		HeightResumeAction.ROUTE_STEP:
			if tile == null or not _is_same_field_tile(tile):
				_request_return_home_for_current_boundary_phase(
					"FarmTile disappeared while finalizing route overflight."
				)
				return
			_finalize_route_step_after_height(tile)

		HeightResumeAction.BOUNDARY_BACKTRACK:
			if tile == null or not _is_same_field_tile(tile):
				_request_return_home_for_current_boundary_phase(
					"FarmTile disappeared while finalizing backtrack overflight."
				)
				return
			_finish_boundary_backtrack_after_height(tile)

		_:
			work_state = overflight_resume_state


func _height_resume_action_name(action: int) -> String:
	match action:
		HeightResumeAction.SURVEY_TILE:
			return "SURVEY_TILE"
		HeightResumeAction.ROUTE_STEP:
			return "ROUTE_STEP"
		HeightResumeAction.BOUNDARY_BACKTRACK:
			return "BOUNDARY_BACKTRACK"
		_:
			return "NONE"


func _finalize_survey_tile_after_height(tile: FarmTile) -> void:
	_register_farm_tile(tile)
	current_grid_coord = tile.grid_coordinate
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		tile.global_position.x,
		hover_world_y,
		tile.global_position.z
	)
	_mark_cell_walked(current_grid_coord)
	_update_seed_emitter_position()
	_service_survey_tile(tile)


func _finalize_route_step_after_height(tile: FarmTile) -> void:
	_register_farm_tile(tile)

	if tile.grid_coordinate != movement_goal_coord:
		_begin_boundary_backtrack(
			movement_goal_coord,
			WorkState.PLAN_NEXT_TARGET,
			"Expected %s, center_cast found %s after overflight."
			% [movement_goal_coord, tile.grid_coordinate],
			false
		)
		return

	if _is_occupied_by_other_tool(tile):
		_set_temporary_block(movement_goal_coord)
		_request_recovery(
			"Another tool occupies route cell %s."
			% movement_goal_coord
		)
		return

	current_grid_coord = movement_goal_coord
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		tile.global_position.x,
		hover_world_y,
		tile.global_position.z
	)
	_mark_cell_walked(current_grid_coord)
	_update_seed_emitter_position()
	_request_local_reconcile(true)

	route_index += 1
	stuck_time = 0.0
	last_goal_distance = INF

	if route_index >= current_route.size():
		_finish_route()
	else:
		movement_goal_coord = current_route[route_index]


func _finish_boundary_backtrack_after_height(
	center_tile: FarmTile
) -> void:
	_reconcile_seen_farm_tile(center_tile)
	current_grid_coord = center_tile.grid_coordinate
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		center_tile.global_position.x,
		hover_world_y,
		center_tile.global_position.z
	)
	_mark_cell_walked(current_grid_coord)
	_update_seed_emitter_position()
	_request_local_reconcile(true)

	stuck_time = 0.0
	last_goal_distance = INF
	recovery_attempt_count = 0

	if boundary_backtrack_is_confirmed_survey_edge:
		boundary_backtrack_is_confirmed_survey_edge = false
		_on_survey_edge_reached()
		return

	work_state = boundary_resume_state


func _begin_survey_blocked(reason: String) -> void:
	if work_state == WorkState.DESTROYED:
		return

	# 先保存真实卡住瞬间的数据用于日志；随后才重置计时供回退阶段使用。
	var block_distance: float = _flat_distance(
		global_position,
		survey_move_target_world
	)
	var block_last_distance: float = last_goal_distance
	var block_stuck_time: float = stuck_time

	survey_blocked_target_coord = survey_move_target_coord
	survey_blocked_reason = reason
	survey_block_retry_count += 1

	# 第一次被挡时，优先回安全格、等待并重试原方向。
	# 这样玩家只要走开，小车不会立即改走平行内侧格。
	# 若原方向再次失败（count >= 2），才进入四周 Cast 的侧向绕行。
	survey_retry_original_pending = (
		survey_block_retry_count == 1
	)
	survey_block_retry_left = (
		survey_block_retry_delay
		if survey_retry_original_pending
		else 0.0
	)

	survey_block_needs_safe_return = not _is_at_world_goal(
		last_safe_world_position
	)
	survey_safe_return_last_distance = INF
	survey_safe_return_stuck_time = 0.0

	# 这是临时不可通过，不是已确认田外。
	_set_temporary_block(survey_blocked_target_coord)
	_request_local_reconcile(true)

	velocity = Vector3.ZERO
	last_goal_distance = INF
	stuck_time = 0.0
	work_state = WorkState.SURVEY_BLOCKED

	_block_debug(
		(
			"SURVEY_BLOCK_DETECTED count=%d/%d origin=%s target=%s direction=%s "
			+ "distance=%.3f last_distance=%.3f stuck=%.2f/%.2f "
			+ "first_retry_original=%s reason=%s contacts=%s"
		)
		% [
			survey_block_retry_count,
			survey_block_max_retries,
			current_grid_coord,
			survey_blocked_target_coord,
			survey_direction,
			block_distance,
			block_last_distance,
			block_stuck_time,
			stuck_timeout,
			survey_retry_original_pending,
			reason,
			_get_recent_slide_collision_summary(),
		]
	)


func _update_survey_blocked(delta: float) -> void:
	# 先回到最后一个经 center_cast 确认的格子中心，再进行避障判断。
	# v16 的问题：若“回安全格”这一步也被挡住，代码没有 watchdog，
	# 因此会永久留在 SURVEY_BLOCKED，只能看到 TEMP_BLOCK_EXPIRED。
	if survey_block_needs_safe_return:
		_move_cardinal_to_world(last_safe_world_position)

		if not _is_at_world_goal(last_safe_world_position):
			var return_distance: float = _flat_distance(
				global_position,
				last_safe_world_position
			)
			_update_survey_safe_return_stuck_watch(
				return_distance,
				delta
			)

			if work_state != WorkState.SURVEY_BLOCKED:
				return

			if not _is_at_world_goal(last_safe_world_position):
				return

		_snap_to_hover_goal(last_safe_world_position)
		_observe_center_tile_during_return()
		survey_block_needs_safe_return = false
		survey_safe_return_last_distance = INF
		survey_safe_return_stuck_time = 0.0
		_request_local_reconcile(true)

		_block_debug(
			"SURVEY_BLOCK_SAFE_RETURN arrived=%s; retry_original=%s."
			% [
				current_grid_coord,
				survey_retry_original_pending,
			]
		)
		return

	_hold_hover()
	survey_block_retry_left -= delta
	if survey_block_retry_left > 0.0:
		return

	# 第一次受阻后，优先清空旧缓存并重试原 survey_direction。
	# 玩家离开时会从这里恢复，而不是先绕到平行的一行。
	if survey_retry_original_pending:
		survey_retry_original_pending = false

		_clear_temporary_block(
			survey_blocked_target_coord,
			"retry original survey direction"
		)

		_block_debug(
			"SURVEY_RETRY_ORIGINAL target=%s direction=%s after_wait=%.2fs."
			% [
				survey_blocked_target_coord,
				survey_direction,
				survey_block_retry_delay,
			]
		)

		work_state = WorkState.SURVEY_ADVANCE
		return

	# 第二次及以后的失败才进行一次即时五 Cast 校验与侧向绕行。
	var found_count: int = _reconcile_local_farm_map()
	_block_debug(
		"SURVEY_BLOCK_RECHECK target=%s same_field_casts=%d retry=%d/%d detours=%d/%d."
		% [
			survey_blocked_target_coord,
			found_count,
			survey_block_retry_count,
			survey_block_max_retries,
			survey_detour_count,
			survey_detour_max_steps,
		]
	)

	if _try_begin_survey_detour():
		return

	if survey_block_retry_count < survey_block_max_retries:
		survey_retry_original_pending = true
		survey_block_retry_left = survey_block_retry_delay

		_block_debug(
			"SURVEY_WAIT_BEFORE_RETRY target=%s wait=%.2fs."
			% [survey_blocked_target_coord, survey_block_retry_delay]
		)
		return

	_block_debug(
		(
			"SURVEY_BLOCK_EXHAUSTED target=%s retries=%d/%d detours=%d/%d; "
			+ "requesting home restart."
		)
		% [
			survey_blocked_target_coord,
			survey_block_retry_count,
			survey_block_max_retries,
			survey_detour_count,
			survey_detour_max_steps,
		]
	)
	_suspend_boundary_survey(
		"Survey remains physically blocked; no center-confirmed boundary at %s."
		% survey_blocked_target_coord
	)


func _update_survey_safe_return_stuck_watch(
	distance_to_safe: float,
	delta: float
) -> void:
	if survey_safe_return_last_distance == INF:
		survey_safe_return_last_distance = distance_to_safe
		return

	if (
		survey_safe_return_last_distance - distance_to_safe
		>= stuck_progress_epsilon
	):
		survey_safe_return_last_distance = distance_to_safe
		survey_safe_return_stuck_time = 0.0
		return

	survey_safe_return_stuck_time += delta
	if survey_safe_return_stuck_time < survey_safe_return_stuck_timeout:
		return

	_block_debug(
		(
			"SURVEY_SAFE_RETURN_STUCK safe_grid=%s distance=%.3f "
			+ "stuck=%.2f/%.2f contacts=%s; requesting home restart."
		)
		% [
			last_safe_grid_coord,
			distance_to_safe,
			survey_safe_return_stuck_time,
			survey_safe_return_stuck_timeout,
			_get_recent_slide_collision_summary(),
		]
	)

	# 无法后退到安全格，说明它已被角色/建筑双向卡住。
	# 直接启用已有的 RETURNING_HOME 逻辑；该逻辑还带二次卡住重试和
	# emergency_snap_home_after_retries 兜底，不会永久静止。
	_request_return_home_and_restart_boundary_survey(
		"Unable to return to last center-cast-confirmed safe tile."
	)


func _get_survey_detour_directions() -> Array[Vector2i]:
	# 只允许横向避障，绝不反向或顺着原边界确认方向乱走。
	if survey_direction.x != 0:
		return [Vector2i(0, 1), Vector2i(0, -1)]
	return [Vector2i(1, 0), Vector2i(-1, 0)]


func _try_begin_survey_detour() -> bool:
	if survey_detour_count >= survey_detour_max_steps:
		_block_debug(
			"SURVEY_DETOUR_SKIP budget exhausted: %d/%d."
			% [survey_detour_count, survey_detour_max_steps]
		)
		return false

	for detour_direction in _get_survey_detour_directions():
		var neighbor_tile: FarmTile = _get_same_field_neighbor_tile(
			detour_direction
		)

		if neighbor_tile == null:
			_block_debug(
				"SURVEY_DETOUR_REJECT direction=%s reason=no same-field neighbor."
				% detour_direction
			)
			continue

		var neighbor_coord: Vector2i = neighbor_tile.grid_coordinate
		if survey_detour_tried_coords.has(neighbor_coord):
			_block_debug(
				"SURVEY_DETOUR_REJECT direction=%s coord=%s reason=already tried."
				% [detour_direction, neighbor_coord]
			)
			continue

		if _is_occupied_by_other_tool(neighbor_tile):
			_block_debug(
				"SURVEY_DETOUR_REJECT direction=%s coord=%s reason=other tool."
				% [detour_direction, neighbor_coord]
			)
			continue

		if _is_temporarily_blocked(neighbor_coord):
			_block_debug(
				"SURVEY_DETOUR_REJECT direction=%s coord=%s reason=temp cache."
				% [detour_direction, neighbor_coord]
			)
			continue

		_register_farm_tile(neighbor_tile)
		survey_detour_tried_coords[neighbor_coord] = true
		survey_detour_direction = detour_direction
		survey_detour_target_coord = neighbor_coord
		survey_detour_target_world = (
			last_safe_world_position
			+ _world_step_for_direction(detour_direction)
		)

		last_goal_distance = INF
		stuck_time = 0.0
		work_state = WorkState.SURVEY_DETOUR_MOVING

		_block_debug(
			(
				"SURVEY_DETOUR_BEGIN direction=%s target=%s world_goal=%s "
				+ "then_resume_edge=%s."
			)
			% [
				detour_direction,
				neighbor_coord,
				survey_detour_target_world,
				survey_direction,
			]
		)
		return true

	return false


func _move_survey_detour(delta: float) -> void:
	_move_cardinal_to_world(survey_detour_target_world)

	# 与主巡边步骤相同：先确认是否已经进入 X/Z 到达容差。
	if not _is_at_world_goal(survey_detour_target_world):
		var distance: float = _flat_distance(
			global_position,
			survey_detour_target_world
		)

		if last_goal_distance == INF:
			last_goal_distance = distance
		elif last_goal_distance - distance >= stuck_progress_epsilon:
			last_goal_distance = distance
			stuck_time = 0.0
		else:
			stuck_time += delta

		if stuck_time >= stuck_timeout:
			_set_temporary_block(survey_detour_target_coord)
			_begin_survey_blocked(
				"Survey detour physically blocked before target %s."
				% survey_detour_target_coord
			)
			return

		if not _is_at_world_goal(survey_detour_target_world):
			return

	_snap_to_hover_goal(survey_detour_target_world)

	var detour_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if detour_tile == null or not _is_same_field_tile(detour_tile):
		# 这里已抵达横向理论格中心且 center_cast 为空，能确认该横向格确实不存在。
		# 但这不是 survey_direction 的边界结论，只是一个真实空格记录。
		_begin_verified_empty_backtrack(
			survey_detour_target_coord,
			WorkState.SURVEY_BLOCKED,
			"Detour target reached but center_cast found no same-field FarmTile."
		)
		return

	if _is_occupied_by_other_tool(detour_tile):
		_set_temporary_block(detour_tile.grid_coordinate)
		_begin_survey_blocked(
			"Detour target became tool-occupied at %s."
			% detour_tile.grid_coordinate
		)
		return

	_register_farm_tile(detour_tile)
	current_grid_coord = detour_tile.grid_coordinate
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		detour_tile.global_position.x,
		hover_world_y,
		detour_tile.global_position.z
	)
	_mark_cell_walked(current_grid_coord)

	survey_detour_count += 1
	# 注意：不要在横向绕行成功后把 survey_block_retry_count 清零。
	# 只有原 survey_direction 真正成功推进一格时才清零，
	# 否则同一障碍可以让小车不断横向绕行、永远不触发返航重测。
	_block_debug(
		"SURVEY_DETOUR_ARRIVED at=%s; keep block_count=%d/%d and resume edge=%s."
		% [
			current_grid_coord,
			survey_block_retry_count,
			survey_block_max_retries,
			survey_direction,
		]
	)
	_request_local_reconcile(true)

	# 绕行中真实经过的 FarmTile 同样同步播种/收获；
	# 动作结束后 SURVEY_WORKING 会回到 SURVEY_ADVANCE，继续原 survey_direction。
	_service_survey_tile(detour_tile)


func _suspend_boundary_survey(reason: String) -> void:
	boundary_survey_incomplete = true
	boundary_survey_confirmed = false
	_block_debug("SURVEY_SUSPEND_AND_RETURN_HOME reason=%s" % reason)

	# 受阻重试与横向绕行预算均耗尽后，不能把当前已知局部范围当成最终边界。
	# 直接返航，抵达起点后清空本轮地图并重新做一次边界检测。
	_request_return_home_and_restart_boundary_survey(
		"Boundary survey retries exhausted. " + reason
	)


func _on_survey_edge_reached() -> void:
	match survey_stage:
		SurveyStage.FIND_X_EDGE:
			survey_stage = SurveyStage.FIND_Z_EDGE
			survey_direction = _height_direction_vector()
			survey_block_retry_count = 0
			survey_retry_original_pending = false
			survey_detour_count = 0
			survey_detour_tried_coords.clear()
			work_state = WorkState.SURVEY_ADVANCE
			_debug("Confirmed first field edge at %s; now find second edge direction=%s." % [
				current_grid_coord,
				survey_direction,
			])

		SurveyStage.FIND_Z_EDGE:
			survey_stage = SurveyStage.TRACE_PERIMETER
			survey_side_index = 0
			survey_direction = -_width_direction_vector()
			survey_block_retry_count = 0
			survey_retry_original_pending = false
			survey_detour_count = 0
			survey_detour_tried_coords.clear()

			var corner_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
			if corner_tile != null and _is_same_field_tile(corner_tile):
				_service_survey_tile(corner_tile)
			else:
				work_state = WorkState.SURVEY_ADVANCE

			_debug("Confirmed survey corner at %s; start perimeter side 1 direction=%s." % [
				current_grid_coord,
				survey_direction,
			])

		SurveyStage.TRACE_PERIMETER:
			survey_side_index += 1

			if survey_side_index >= 4:
				_finish_boundary_survey()
				return

			survey_direction = _perimeter_direction_for_side(survey_side_index)
			survey_block_retry_count = 0
			survey_retry_original_pending = false
			survey_detour_count = 0
			survey_detour_tried_coords.clear()
			work_state = WorkState.SURVEY_ADVANCE
			_debug("Perimeter side %d confirmed; turn to side %d direction=%s." % [
				survey_side_index,
				survey_side_index + 1,
				survey_direction,
			])


func _perimeter_direction_for_side(side_index: int) -> Vector2i:
	match side_index:
		0:
			return -_width_direction_vector()
		1:
			return -_height_direction_vector()
		2:
			return _width_direction_vector()
		_:
			return _height_direction_vector()


func _service_survey_tile(tile: FarmTile) -> void:
	if tile == null or not _is_same_field_tile(tile):
		work_state = WorkState.SURVEY_ADVANCE
		return

	var coord: Vector2i = tile.grid_coordinate
	if survey_processed_coords.has(coord):
		work_state = WorkState.SURVEY_ADVANCE
		return

	survey_processed_coords[coord] = true
	_register_farm_tile(tile)

	if _has_any_tool(tile):
		work_state = WorkState.SURVEY_ADVANCE
		return

	var acted: bool = false
	if tile.seed_record.is_empty():
		acted = _plant_on_tile(tile)
	elif tile.can_harvest and tile.land_owner == tool_owner:
		acted = tile.harvest(global_position, {
			"absorption_type": "farm_runner_crop",
			"owner_peer_id": GameAuthority.get_placed_tool_owner_peer_id(self),
		})

	if acted:
		action_time_left = action_duration
		work_state = WorkState.SURVEY_WORKING
	else:
		work_state = WorkState.SURVEY_ADVANCE


func _finish_boundary_survey() -> void:
	if not field_bounds_ready:
		_build_fallback_bounds_from_exports()

	boundary_survey_incomplete = false
	boundary_survey_confirmed = true
	_build_serpentine_scan_order_from_bounds()
	scan_order_dirty = false
	work_state = WorkState.PLAN_NEXT_TARGET

	_debug(
		"Boundary survey complete from center-cast confirmation. "
		+ "bounds x=[%d,%d] z=[%d,%d], scan_cells=%d."
		% [field_min_x, field_max_x, field_min_z, field_max_z, scan_order.size()]
	)


func _finish_boundary_survey_with_known_bounds(reason: String) -> void:
	if not fallback_to_known_bounds_when_survey_blocked:
		_request_return_home_for_current_boundary_phase("Boundary survey suspended: %s" % reason)
		return

	if not field_bounds_ready or (
		field_min_x == field_max_x
		and field_min_z == field_max_z
	):
		_build_fallback_bounds_from_exports()

	# 这不是“边界完成”，而是用当前已确认范围先进入扫描。
	# 后续低频 reconcile 发现新 FarmTile 后会扩展边界、加入 frontier。
	boundary_survey_confirmed = false
	_build_serpentine_scan_order_from_bounds()
	scan_order_dirty = false
	work_state = WorkState.PLAN_NEXT_TARGET
	_request_local_reconcile(true)

	_debug(
		"Boundary survey suspended, not confirmed complete. reason=%s "
		+ "known bounds x=[%d,%d] z=[%d,%d]."
		% [reason, field_min_x, field_max_x, field_min_z, field_max_z]
	)


func _build_fallback_bounds_from_exports() -> void:
	var x_sign: int = 1 if width_direction == 0 else -1
	var z_sign: int = 1 if height_direction == 0 else -1
	var fallback_end_x: int = start_grid_coord.x + (field_width - 1) * x_sign
	var fallback_end_z: int = start_grid_coord.y + (field_height - 1) * z_sign

	field_min_x = mini(start_grid_coord.x, fallback_end_x)
	field_max_x = maxi(start_grid_coord.x, fallback_end_x)
	field_min_z = mini(start_grid_coord.y, fallback_end_z)
	field_max_z = maxi(start_grid_coord.y, fallback_end_z)
	field_bounds_ready = true


func _build_serpentine_scan_order_from_bounds() -> void:
	scan_order.clear()
	scan_index = 0

	var z_count: int = field_max_z - field_min_z + 1
	var x_count: int = field_max_x - field_min_x + 1
	if z_count <= 0 or x_count <= 0:
		return

	for row in range(z_count):
		var z: int = field_min_z + row
		if height_direction != 0:
			z = field_max_z - row

		var reverse_row: bool = (row % 2) == 1
		for logical_col in range(x_count):
			var col: int = logical_col
			var goes_positive_x: bool = width_direction == 0

			if reverse_row:
				goes_positive_x = not goes_positive_x
			if not goes_positive_x:
				col = x_count - 1 - logical_col

			var x: int = field_min_x + col
			scan_order.append(Vector2i(x, z))


# ------------------------------------------------------------------
# SeedEmitter
# ------------------------------------------------------------------

func _ensure_seed_emitter() -> void:
	seed_emitter = get_node_or_null("SeedEmitter") as GPUParticles3D
	if seed_emitter == null:
		if not auto_create_seed_emitter:
			return
		seed_emitter = GPUParticles3D.new()
		seed_emitter.name = "SeedEmitter"
		add_child(seed_emitter)

	_configure_seed_emitter()


func _configure_seed_emitter() -> void:
	if seed_emitter == null:
		return

	seed_emitter.position = Vector3(0.0, -hover_height + seed_emitter_ground_offset, 0.0)
	seed_emitter.one_shot = true
	seed_emitter.emitting = false
	seed_emitter.amount = seed_particle_count
	seed_emitter.lifetime = seed_particle_lifetime
	seed_emitter.explosiveness = 1.0
	seed_emitter.randomness = 0.25
	seed_emitter.local_coords = false
	seed_emitter.visibility_aabb = AABB(
		Vector3(-0.55, -0.85, -0.55),
		Vector3(1.10, 1.10, 1.10)
	)

	var particle_process: ParticleProcessMaterial = ParticleProcessMaterial.new()
	particle_process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	particle_process.emission_sphere_radius = seed_particle_spread_radius
	particle_process.direction = Vector3.DOWN
	particle_process.spread = 24.0
	particle_process.gravity = Vector3(0.0, -6.5, 0.0)
	particle_process.initial_velocity_min = seed_particle_speed_min
	particle_process.initial_velocity_max = seed_particle_speed_max
	particle_process.damping_min = 0.8
	particle_process.damping_max = 1.4
	particle_process.scale_min = 0.75
	particle_process.scale_max = 1.20
	particle_process.color = seed_particle_color

	var seed_mesh: SphereMesh = SphereMesh.new()
	seed_mesh.radius = seed_particle_radius
	seed_mesh.height = seed_particle_radius * 2.0
	seed_mesh.radial_segments = 8
	seed_mesh.rings = 4

	var seed_material: StandardMaterial3D = StandardMaterial3D.new()
	seed_material.albedo_color = seed_particle_color
	seed_material.vertex_color_use_as_albedo = true
	seed_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	seed_mesh.material = seed_material

	seed_emitter.process_material = particle_process
	seed_emitter.draw_pass_1 = seed_mesh


func _update_seed_emitter_position() -> void:
	if seed_emitter == null:
		return

	# 根节点升到 8m 时，种子粒子仍从地块附近出现，而不是从高空落下。
	var ground_reference_y: float = start_world_tile_position.y
	seed_emitter.position = Vector3(
		0.0,
		ground_reference_y
		+ seed_emitter_ground_offset
		- global_position.y,
		0.0
	)

func _read_grid_step_from_manual_cast_offsets() -> bool:
	# 读取的是“Cast 节点位置差”，不是射线 target_position。
	# 你的配置中：
	# right_cast.position.x - center_cast.position.x = 一格 X 距离；
	# forward_cast.position.z - center_cast.position.z = 一格 Z 距离。
	var center_world: Vector3 = center_cast.global_position

	var right_offset: Vector3 = right_cast.global_position - center_world
	right_offset.y = 0.0
	if right_offset.length() < 0.05:
		right_offset = center_world - left_cast.global_position
		right_offset.y = 0.0

	var forward_offset: Vector3 = forward_cast.global_position - center_world
	forward_offset.y = 0.0
	if forward_offset.length() < 0.05:
		forward_offset = center_world - backward_cast.global_position
		forward_offset.y = 0.0

	if right_offset.length() < 0.05 or forward_offset.length() < 0.05:
		_debug(
			"RayCast offset invalid. center/right/forward positions must differ by one FarmTile spacing."
		)
		return false

	step_right_world = right_offset
	step_forward_world = forward_offset
	step_x_distance = right_offset.length()
	step_z_distance = forward_offset.length()

	# 先设置一个兼容旧版本的回退映射。
	# 后续 _calibrate_grid_world_mapping() 会根据实际 FarmTile.grid_coordinate 覆盖它。
	grid_positive_x_world = step_right_world
	grid_positive_z_world = step_forward_world
	grid_direction_mapping.clear()
	grid_mapping_calibrated = false

	# 可选一致性提醒：left/backward 应位于相反方向的一整格位置。
	var left_offset: Vector3 = left_cast.global_position - center_world
	left_offset.y = 0.0
	var backward_offset: Vector3 = backward_cast.global_position - center_world
	backward_offset.y = 0.0

	if left_offset.length() > 0.05 and absf(left_offset.length() - step_x_distance) > 0.05:
		_debug("Warning: left_cast offset differs from right_cast offset.")
	if backward_offset.length() > 0.05 and absf(backward_offset.length() - step_z_distance) > 0.05:
		_debug("Warning: backward_cast offset differs from forward_cast offset.")

	_debug(
		"Measured tile steps from Cast offsets: X=%.3f, Z=%.3f."
		% [step_x_distance, step_z_distance]
	)
	return true


func _world_step_for_direction(direction: Vector2i) -> Vector3:
	var mapped_entry: Variant = grid_direction_mapping.get(direction, null)
	if mapped_entry is Dictionary:
		var mapped_step: Vector3 = mapped_entry.get(
			"world_step",
			Vector3.ZERO
		)
		if mapped_step.length_squared() > 0.0001:
			return mapped_step

	# 映射尚未成功校准时，使用旧版本的物理方向作为安全回退。
	# 正常启动时会由 _calibrate_grid_world_mapping() 覆盖。
	if direction == Vector2i(1, 0):
		return grid_positive_x_world
	if direction == Vector2i(-1, 0):
		return -grid_positive_x_world
	if direction == Vector2i(0, 1):
		return grid_positive_z_world
	if direction == Vector2i(0, -1):
		return -grid_positive_z_world
	return Vector3.ZERO


## 由当前中心 FarmTile 与四个邻居 Cast 的真实 grid_coordinate 关系校准。
##
## 例如：
## center=(7,1)，right_cast 命中=(6,1)
## => 世界右侧对应 grid (-1,0)
## => grid (+1,0) 必须走世界左侧，而不是世界右侧。
##
## 这正是本次日志中“first direction=(1,0) 却从 x=7 连续走向 x=0”的根因。
func _calibrate_grid_world_mapping() -> bool:
	var center_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if center_tile == null or not _is_same_field_tile(center_tile):
		return false

	var center_coord: Vector2i = center_tile.grid_coordinate
	var candidate_casts: Array[RayCast3D] = [
		right_cast,
		left_cast,
		forward_cast,
		backward_cast,
	]

	var candidate_steps: Array[Vector3] = [
		step_right_world,
		-step_right_world,
		step_forward_world,
		-step_forward_world,
	]

	var candidate_names: Array[String] = [
		"right_cast",
		"left_cast",
		"forward_cast",
		"backward_cast",
	]

	var new_mapping: Dictionary = {}
	var mapping_labels: Dictionary = {}

	for index in range(candidate_casts.size()):
		var cast: RayCast3D = candidate_casts[index]
		var neighbor: FarmTile = _get_farm_tile_from_cast(cast)
		if neighbor == null or not _is_same_field_tile(neighbor):
			continue

		var grid_delta: Vector2i = (
			neighbor.grid_coordinate
			- center_coord
		)

		# 只接受相邻一格的标准 cardinal delta。
		if abs(grid_delta.x) + abs(grid_delta.y) != 1:
			continue

		var physical_step: Vector3 = candidate_steps[index]
		var cast_name: String = candidate_names[index]

		new_mapping[grid_delta] = {
			"world_step": physical_step,
			"cast": cast,
			"cast_name": cast_name,
		}

		# 同一对轴的反方向对应物理相反方向。
		var opposite_delta: Vector2i = -grid_delta
		var opposite_cast: RayCast3D = _opposite_neighbor_cast(cast)
		new_mapping[opposite_delta] = {
			"world_step": -physical_step,
			"cast": opposite_cast,
			"cast_name": _neighbor_cast_name(opposite_cast),
		}

		mapping_labels[grid_delta] = cast_name

	if not new_mapping.has(Vector2i(1, 0)):
		return false
	if not new_mapping.has(Vector2i(0, 1)):
		return false

	grid_direction_mapping = new_mapping

	var positive_x_entry: Dictionary = grid_direction_mapping[
		Vector2i(1, 0)
	]
	var positive_z_entry: Dictionary = grid_direction_mapping[
		Vector2i(0, 1)
	]

	grid_positive_x_world = positive_x_entry.get(
		"world_step",
		step_right_world
	)
	grid_positive_z_world = positive_z_entry.get(
		"world_step",
		step_forward_world
	)

	var mapping_was_new: bool = not grid_mapping_calibrated
	grid_mapping_calibrated = true

	if mapping_was_new:
		_debug(
			"Grid mapping calibrated: grid +X -> %s, grid +Z -> %s."
			% [
				str(positive_x_entry.get("cast_name", "unknown")),
				str(positive_z_entry.get("cast_name", "unknown")),
			]
		)

	return true


func _opposite_neighbor_cast(cast: RayCast3D) -> RayCast3D:
	if cast == right_cast:
		return left_cast
	if cast == left_cast:
		return right_cast
	if cast == forward_cast:
		return backward_cast
	if cast == backward_cast:
		return forward_cast
	return null


func _neighbor_cast_name(cast: RayCast3D) -> String:
	if cast == right_cast:
		return "right_cast"
	if cast == left_cast:
		return "left_cast"
	if cast == forward_cast:
		return "forward_cast"
	if cast == backward_cast:
		return "backward_cast"
	return "unknown_cast"


func _all_farm_raycast_nodes() -> Array[RayCast3D]:
	return [
		center_cast,
		forward_cast,
		backward_cast,
		left_cast,
		right_cast,
	]


## 事件驱动 + 低频调度入口。
## immediate=true 只把下一次检查安排为“下一 physics 帧尽快执行”，
## 不会在调用点同步递归扫描。
func _request_local_reconcile(immediate: bool = false) -> void:
	_local_reconcile_requested = true
	if immediate:
		_local_reconcile_timer = 0.0


func _update_local_reconcile_scheduler(delta: float) -> void:
	_local_reconcile_timer -= delta

	if not _local_reconcile_requested and _local_reconcile_timer > 0.0:
		return

	_local_reconcile_requested = false
	_local_reconcile_timer = local_reconcile_interval
	_reconcile_local_farm_map()


## 低频本地地图自修复：
## - 读取 5 条已手动配置的 RayCast；
## - 当前真实检测结果优先于旧 discovered_map；
## - 发现旧 EMPTY 现在实际是 FarmTile、旧工具阻挡已释放、
##   或发现原边界外的新 FarmTile 时，登记并加入 frontier_queue；
## - 本函数不调用 BFS。
func _reconcile_local_farm_map() -> int:
	var found_count: int = 0
	var current_tile: FarmTile = null

	for cast in _all_farm_raycast_nodes():
		var tile: FarmTile = _get_farm_tile_from_cast(cast)
		if tile == null or not _is_same_field_tile(tile):
			continue

		_reconcile_seen_farm_tile(tile)
		found_count += 1

		if cast == center_cast:
			current_tile = tile

	if current_tile != null:
		_register_farm_tile(current_tile)
		current_grid_coord = current_tile.grid_coordinate

		if not _is_occupied_by_other_tool(current_tile):
			last_safe_grid_coord = current_grid_coord
			last_safe_world_position = Vector3(
				current_tile.global_position.x,
				hover_world_y,
				current_tile.global_position.z
			)
			_mark_cell_walked(current_grid_coord)

	# 如果启动时四周没有足够可见相邻格，低频地图校验中再尝试一次。
	# 这里不会额外增加一轮 Cast；校准复用本函数刚读取的结果。
	if auto_calibrate_grid_world_mapping and not grid_mapping_calibrated:
		_calibrate_grid_world_mapping()

	# 复用上方已经读取完的五条 Cast 的统计结果：
	# center + 前后左右都无本 field_id FarmTile 时，连续确认后返航重做边界检测。
	# 不会因此新增 force_raycast_update() 或 BFS。
	_update_no_local_farmtile_watch(found_count)

	return found_count


## 只在 _reconcile_local_farm_map() 已完成一次五 Cast 低频读取后调用。
## found_count == 0 等价于 center_cast 和四周四条 Cast 都没有同 field_id FarmTile。
func _update_no_local_farmtile_watch(found_count: int) -> void:
	if not initialized:
		return

	# 已在返航或销毁时不重复触发；返航抵达后会由重启流程重新清零。
	if work_state == WorkState.RETURNING_HOME \
	or work_state == WorkState.DESTROYED:
		return

	if found_count > 0:
		_no_local_farmtile_check_count = 0
		return

	_no_local_farmtile_check_count += 1
	_debug(
		"No local same-field FarmTile: %d/%d low-frequency checks."
		% [
			_no_local_farmtile_check_count,
			no_local_farmtile_checks_before_return,
		]
	)

	if _no_local_farmtile_check_count < no_local_farmtile_checks_before_return:
		return

	_no_local_farmtile_check_count = 0
	_block_debug(
		"NO_LOCAL_FARMTILE_RETURN triggered after %d low-frequency checks."
		% no_local_farmtile_checks_before_return
	)
	_request_return_home_and_restart_boundary_survey(
		"center_cast and all four neighbor Casts found no same-field FarmTile."
	)


## 保留旧名称，供初始化/回退等已有调用使用。
func _observe_local_farm_tiles() -> int:
	return _reconcile_local_farm_map()


func _reconcile_seen_farm_tile(tile: FarmTile) -> void:
	var coord: Vector2i = tile.grid_coordinate
	var had_entry: bool = discovered_map.has(coord)
	var old_entry: Dictionary = discovered_map.get(coord, _new_cell_entry())
	var old_state: int = int(old_entry.get("state", CELL_UNKNOWN))
	var old_walkable: bool = bool(old_entry.get("walkable", false))

	var old_min_x: int = field_min_x
	var old_max_x: int = field_max_x
	var old_min_z: int = field_min_z
	var old_max_z: int = field_max_z
	var had_bounds: bool = field_bounds_ready

	_register_farm_tile(tile)

	var new_entry: Dictionary = discovered_map[coord]
	var new_walkable: bool = bool(new_entry.get("walkable", false))
	var bounds_expanded: bool = (
		not had_bounds
		or field_min_x != old_min_x
		or field_max_x != old_max_x
		or field_min_z != old_min_z
		or field_max_z != old_max_z
	)

	# 当前真实 Cast 打到 FarmTile 时，以真实结果覆盖任何旧误判。
	# 特别是以前错误写为 CELL_EMPTY、或曾被工具/临时阻挡的格。
	var needs_frontier: bool = (
		not had_entry
		or old_state != CELL_FARM
		or (not old_walkable and new_walkable)
		or bounds_expanded
	)

	if initialized and needs_frontier:
		if old_state == CELL_EMPTY:
			_debug(
				"Map repair: coord %s was EMPTY but local Cast now sees FarmTile."
				% coord
			)

		_enqueue_frontier(coord)

	if bounds_expanded and initialized:
		# 只标脏，不在此处立即重建 scan_order，更不在此处 BFS。
		scan_order_dirty = true
		_debug(
			"Map expanded by local Cast: x=[%d,%d] z=[%d,%d]."
			% [field_min_x, field_max_x, field_min_z, field_max_z]
		)


func _enqueue_frontier(coord: Vector2i) -> void:
	if coord == current_grid_coord:
		return
	if frontier_set.has(coord):
		return

	frontier_set[coord] = true
	frontier_queue.append(coord)


func _pop_frontier() -> Vector2i:
	if frontier_queue.is_empty():
		return Vector2i.ZERO

	var coord: Vector2i = frontier_queue[0]
	frontier_queue.remove_at(0)
	frontier_set.erase(coord)
	return coord


func _observe_center_tile_during_return() -> void:
	var tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if tile == null or not _is_same_field_tile(tile):
		return

	_reconcile_seen_farm_tile(tile)
	current_grid_coord = tile.grid_coordinate
	_mark_cell_walked(current_grid_coord)

	if not _is_occupied_by_other_tool(tile):
		last_safe_grid_coord = current_grid_coord
		last_safe_world_position = Vector3(
			tile.global_position.x,
			hover_world_y,
			tile.global_position.z
		)


func _get_neighbor_cast(direction: Vector2i) -> RayCast3D:
	var mapped_entry: Variant = grid_direction_mapping.get(direction, null)
	if mapped_entry is Dictionary:
		var mapped_cast: RayCast3D = mapped_entry.get(
			"cast",
			null
		) as RayCast3D
		if mapped_cast != null:
			return mapped_cast

	# 映射尚未校准时，保留旧版约定作为回退。
	if direction == Vector2i(0, 1):
		return forward_cast
	if direction == Vector2i(0, -1):
		return backward_cast
	if direction == Vector2i(-1, 0):
		return left_cast
	if direction == Vector2i(1, 0):
		return right_cast
	return null


func _get_same_field_neighbor_tile(direction: Vector2i) -> FarmTile:
	var center_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if center_tile == null or not _is_same_field_tile(center_tile):
		return null

	var cast: RayCast3D = _get_neighbor_cast(direction)
	if cast != null:
		var tile: FarmTile = _get_farm_tile_from_cast(cast)
		if tile != null and _is_same_field_tile(tile):
			if tile.grid_coordinate - center_tile.grid_coordinate == direction:
				return tile

	# 校准尚未完成、或者地图方向被重新配置时，低频受阻处理里
	# 再扫描四个邻居兜底；不会在每个 physics frame 调用。
	for fallback_cast in [
		forward_cast,
		backward_cast,
		left_cast,
		right_cast,
	]:
		var fallback_tile: FarmTile = _get_farm_tile_from_cast(
			fallback_cast
		)
		if fallback_tile == null:
			continue
		if not _is_same_field_tile(fallback_tile):
			continue
		if fallback_tile.grid_coordinate - center_tile.grid_coordinate == direction:
			return fallback_tile

	return null


func _get_farm_tile_from_cast(cast: RayCast3D) -> FarmTile:
	if cast == null:
		return null

	cast.force_raycast_update()
	if not cast.is_colliding():
		return null

	return Farmlandmanager.resolve_raycast_tile(cast)


func _is_same_field_tile(tile: FarmTile) -> bool:
	if tile == null or start_tile == null:
		return false

	return tile.field_id == start_field_id


func _register_farm_tile(tile: FarmTile) -> void:
	if tile == null or not _is_same_field_tile(tile):
		return

	var coord: Vector2i = tile.grid_coordinate
	var entry: Dictionary = discovered_map.get(coord, _new_cell_entry())
	var occupied_by_other_tool: bool = _is_occupied_by_other_tool(tile)

	entry["state"] = CELL_FARM
	entry["tile"] = tile
	entry["walkable"] = not occupied_by_other_tool
	entry["access"] = (
		ACCESS_TOOL_OCCUPIED
		if occupied_by_other_tool
		else ACCESS_WALKABLE
	)
	entry["seen"] = true
	entry["last_seen_msec"] = Time.get_ticks_msec()

	discovered_map[coord] = entry
	_update_field_bounds(coord)


func _update_field_bounds(coord: Vector2i) -> void:
	if not field_bounds_ready:
		field_min_x = coord.x
		field_max_x = coord.x
		field_min_z = coord.y
		field_max_z = coord.y
		field_bounds_ready = true
		return

	field_min_x = mini(field_min_x, coord.x)
	field_max_x = maxi(field_max_x, coord.x)
	field_min_z = mini(field_min_z, coord.y)
	field_max_z = maxi(field_max_z, coord.y)


## 仅由“完整到达该格中心 + center_cast 确认无 FarmTile”调用。
func _mark_cell_empty(coord: Vector2i) -> void:
	var entry: Dictionary = discovered_map.get(coord, _new_cell_entry())
	entry["state"] = CELL_EMPTY
	entry["tile"] = null
	entry["walkable"] = false
	entry["access"] = ACCESS_TEMP_BLOCKED
	entry["seen"] = true
	entry["last_seen_msec"] = Time.get_ticks_msec()
	discovered_map[coord] = entry


## 对失效 Tile 引用只降级为 UNKNOWN，不擅自写 EMPTY。
## 因为引用失效、分块加载等并不等价于“该坐标没有 FarmTile”。
func _mark_cell_unknown(coord: Vector2i) -> void:
	var entry: Dictionary = discovered_map.get(coord, _new_cell_entry())
	entry["state"] = CELL_UNKNOWN
	entry["tile"] = null
	entry["walkable"] = false
	entry["access"] = ACCESS_TEMP_BLOCKED
	entry["last_seen_msec"] = Time.get_ticks_msec()
	discovered_map[coord] = entry


func _mark_cell_walked(coord: Vector2i) -> void:
	var entry: Dictionary = discovered_map.get(coord, _new_cell_entry())
	entry["walked"] = true
	discovered_map[coord] = entry


func _new_cell_entry() -> Dictionary:
	return {
		"state": CELL_UNKNOWN,
		"access": ACCESS_TEMP_BLOCKED,
		"tile": null,
		"walkable": false,
		"seen": false,
		"walked": false,
		"last_seen_msec": 0,
	}


func _refresh_known_cell(coord: Vector2i) -> void:
	if not discovered_map.has(coord):
		return

	var entry: Dictionary = discovered_map[coord]
	if int(entry.get("state", CELL_UNKNOWN)) != CELL_FARM:
		return

	var tile: FarmTile = entry.get("tile") as FarmTile
	if not is_instance_valid(tile) or not _is_same_field_tile(tile):
		_mark_cell_unknown(coord)
		return

	var occupied_by_other_tool: bool = _is_occupied_by_other_tool(tile)
	entry["walkable"] = not occupied_by_other_tool
	entry["access"] = (
		ACCESS_TOOL_OCCUPIED
		if occupied_by_other_tool
		else ACCESS_WALKABLE
	)
	entry["last_seen_msec"] = Time.get_ticks_msec()
	discovered_map[coord] = entry


func _is_occupied_by_other_tool(tile: FarmTile) -> bool:
	if tile == null:
		return true
	if not is_instance_valid(tile.tool_child):
		return false
	return tile.tool_child != self


func _has_any_tool(tile: FarmTile) -> bool:
	return tile != null and is_instance_valid(tile.tool_child)


# ------------------------------------------------------------------
# Standard Z-scan jobs
# ------------------------------------------------------------------

func _plan_next_target() -> void:
	# 边界扩展后只在“准备规划下一目标”时重建扫描序列。
	# 不会在移动途中改路线，也不会在 reconcile 内部立刻 BFS。
	if scan_order_dirty and field_bounds_ready:
		_build_serpentine_scan_order_from_bounds()
		scan_order_dirty = false
		_debug("Rebuilt scan order after map expansion. cells=%d." % scan_order.size())

	# 新发现 / 旧阻挡恢复的 FarmTile 优先尝试一次。
	# 每次最多 frontier_candidates_per_plan 个候选，避免大量 BFS。
	if _try_plan_frontier_target():
		return

	if scan_order.is_empty():
		cycle_pause_left = cycle_pause_duration
		work_state = WorkState.CYCLE_PAUSE
		return

	# scan_order 重建后，已在本轮处理过的格会被跳过，避免重复播种/收获。
	while (
		scan_index < scan_order.size()
		and scan_processed_this_cycle.has(scan_order[scan_index])
	):
		scan_index += 1

	if scan_index >= scan_order.size():
		cycle_pause_left = cycle_pause_duration
		work_state = WorkState.CYCLE_PAUSE
		return

	_active_target_is_frontier = false
	desired_scan_coord = scan_order[scan_index]
	_refresh_known_cell(desired_scan_coord)

	if _is_known_unusable(desired_scan_coord):
		_advance_scan_target()
		return

	if current_grid_coord == desired_scan_coord:
		_service_current_target_tile()
		return

	if not _begin_route_to(desired_scan_coord, RoutePurpose.TO_SCAN_TARGET):
		# 当前这一轮不能到达，不会反复对同一目标每帧 BFS。
		_debug("No route to %s. Skip for this scan cycle." % desired_scan_coord)
		_advance_scan_target()


func _try_plan_frontier_target() -> bool:
	var tried_count: int = 0

	while not frontier_queue.is_empty() and tried_count < frontier_candidates_per_plan:
		tried_count += 1
		var frontier_coord: Vector2i = _pop_frontier()

		if scan_processed_this_cycle.has(frontier_coord):
			continue
		if not _is_inside_active_bounds(frontier_coord):
			continue

		_refresh_known_cell(frontier_coord)
		if _is_known_unusable(frontier_coord):
			continue

		desired_scan_coord = frontier_coord
		_active_target_is_frontier = true

		if current_grid_coord == desired_scan_coord:
			_service_current_target_tile()
			return true

		if _begin_route_to(desired_scan_coord, RoutePurpose.TO_SCAN_TARGET):
			return true

		# 该前沿当前不可达：本轮先不重复塞回队列。
		# 后续 Cast 重发现、工具释放、临时阻挡到期时会重新入队。
		_debug("Frontier %s currently has no route; defer." % frontier_coord)

	return false


func _service_current_target_tile() -> void:
	var tile: FarmTile = _get_farm_tile_at_coord(desired_scan_coord)
	if tile == null:
		# 这里只在 current_grid_coord 已等于 desired_scan_coord，
		# 或刚刚 _on_route_step_reached() 完成 center_cast 校验后调用。
		# 再读一次 center_cast：命中空才允许写 EMPTY。
		var center_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
		if (
			center_tile == null
			or not _is_same_field_tile(center_tile)
		):
			_mark_cell_empty(desired_scan_coord)
		else:
			_reconcile_seen_farm_tile(center_tile)

		_advance_scan_target()
		return

	_register_farm_tile(tile)

	if _has_any_tool(tile):
		_advance_scan_target()
		return

	var acted: bool = false
	if tile.seed_record.is_empty():
		acted = _plant_on_tile(tile)
	elif tile.can_harvest:
		acted = tile.harvest(global_position, {
			"absorption_type": "farm_runner_crop",
			"owner_peer_id": GameAuthority.get_placed_tool_owner_peer_id(self),
		})

	if acted:
		action_time_left = action_duration
		work_state = WorkState.WORKING_ON_TILE
	else:
		_advance_scan_target()


func _plant_on_tile(tile: FarmTile) -> bool:
	if tool_owner.is_empty() or GlobalVar.plant_item_list.is_empty():
		return false

	var index: int = randi_range(0, GlobalVar.plant_item_list.size() - 1)
	var seed_name: String = str(GlobalVar.plant_item_list[index])
	var did_plant: bool = tile.plant(seed_name, tool_owner)

	if did_plant and is_instance_valid(seed_emitter):
		seed_emitter.restart()

	return did_plant


func _advance_scan_target() -> void:
	# 无论是普通 scan 还是 frontier，到此都视为本轮已经检查过。
	scan_processed_this_cycle[desired_scan_coord] = true

	if _active_target_is_frontier:
		_active_target_is_frontier = false
		work_state = WorkState.PLAN_NEXT_TARGET
		return

	scan_index += 1

	if scan_index >= scan_order.size():
		cycle_pause_left = cycle_pause_duration
		work_state = WorkState.CYCLE_PAUSE
	else:
		work_state = WorkState.PLAN_NEXT_TARGET


# ------------------------------------------------------------------
# Cardinal BFS pathfinding
# ------------------------------------------------------------------

func _begin_route_to(target_coord: Vector2i, purpose: int) -> bool:
	var origin: Vector2i = current_grid_coord
	var center_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if center_tile != null and _is_same_field_tile(center_tile):
		origin = center_tile.grid_coordinate
	else:
		origin = _estimate_grid_coord_from_world(global_position)

	var path: Array[Vector2i] = _find_cardinal_path(origin, target_coord)
	if path.is_empty():
		return false

	if path.size() == 1:
		current_grid_coord = target_coord
		if purpose == RoutePurpose.TO_SCAN_TARGET:
			_service_current_target_tile()
		else:
			work_state = WorkState.PLAN_NEXT_TARGET
		return true

	current_route = path
	route_index = 1
	route_purpose = purpose
	movement_goal_coord = current_route[route_index]
	last_goal_distance = INF
	stuck_time = 0.0
	work_state = WorkState.MOVING_ROUTE
	return true


func _find_cardinal_path(from_coord: Vector2i, to_coord: Vector2i) -> Array[Vector2i]:
	if not _is_inside_active_bounds(from_coord) or not _is_inside_active_bounds(to_coord):
		return []

	var queue: Array[Vector2i] = [from_coord]
	var head: int = 0
	var came_from: Dictionary = {from_coord: from_coord}

	while head < queue.size():
		var current: Vector2i = queue[head]
		head += 1

		if current == to_coord:
			return _reconstruct_path(came_from, from_coord, to_coord)

		for direction in CARDINAL_DIRECTIONS:
			var next_coord: Vector2i = current + direction

			if came_from.has(next_coord):
				continue
			if not _can_enter_cell(next_coord):
				continue

			came_from[next_coord] = current
			queue.append(next_coord)

	return []


func _reconstruct_path(
	came_from: Dictionary,
	from_coord: Vector2i,
	to_coord: Vector2i
) -> Array[Vector2i]:
	var reversed_path: Array[Vector2i] = []
	var cursor: Vector2i = to_coord

	while cursor != from_coord:
		reversed_path.append(cursor)
		var previous: Vector2i = came_from[cursor]
		cursor = previous

	reversed_path.append(from_coord)
	reversed_path.reverse()
	return reversed_path


func _can_enter_cell(coord: Vector2i) -> bool:
	if not _is_inside_active_bounds(coord):
		return false
	if _is_temporarily_blocked(coord):
		return false

	_refresh_known_cell(coord)

	if not discovered_map.has(coord):
		# 边界扩大后才可能出现新的 UNKNOWN 内部格，允许 center_cast 在到格后最终确认。
		return true

	var entry: Dictionary = discovered_map[coord]
	var state: int = int(entry.get("state", CELL_UNKNOWN))

	if state == CELL_EMPTY:
		return false
	if state == CELL_FARM:
		return bool(entry.get("walkable", false))

	# UNKNOWN 不把它当作边界；允许谨慎探索。
	return true


func _is_known_unusable(coord: Vector2i) -> bool:
	if _is_temporarily_blocked(coord):
		return true

	if not discovered_map.has(coord):
		return false

	var entry: Dictionary = discovered_map[coord]
	var state: int = int(entry.get("state", CELL_UNKNOWN))
	return state == CELL_EMPTY or (
		state == CELL_FARM
		and not bool(entry.get("walkable", false))
	)


func _is_inside_active_bounds(coord: Vector2i) -> bool:
	if field_bounds_ready:
		return (
			coord.x >= field_min_x
			and coord.x <= field_max_x
			and coord.y >= field_min_z
			and coord.y <= field_max_z
		)

	# 理论上仅在关闭边界勘测时使用。
	var x_sign: int = 1 if width_direction == 0 else -1
	var z_sign: int = 1 if height_direction == 0 else -1
	var end_x: int = start_grid_coord.x + (field_width - 1) * x_sign
	var end_z: int = start_grid_coord.y + (field_height - 1) * z_sign

	return (
		coord.x >= mini(start_grid_coord.x, end_x)
		and coord.x <= maxi(start_grid_coord.x, end_x)
		and coord.y >= mini(start_grid_coord.y, end_z)
		and coord.y <= maxi(start_grid_coord.y, end_z)
	)


# ------------------------------------------------------------------
# Movement and center-cast verification
# ------------------------------------------------------------------

func _move_along_current_route(delta: float) -> void:
	if current_route.is_empty() or route_index >= current_route.size():
		_finish_route()
		return

	var goal_world: Vector3 = _world_position_for_grid(movement_goal_coord)
	_move_cardinal_to_world(goal_world)

	if not _is_at_world_goal(goal_world):
		var distance: float = _flat_distance(global_position, goal_world)
		_update_stuck_watch(
			distance,
			delta,
			WorkState.MOVING_ROUTE,
			"Route movement blocked before grid %s." % movement_goal_coord
		)

		if work_state != WorkState.MOVING_ROUTE:
			return

		if not _is_at_world_goal(goal_world):
			return

	_snap_to_hover_goal(goal_world)
	_on_route_step_reached()


func _move_cardinal_to_world(goal_world: Vector3) -> void:
	var delta_x: float = goal_world.x - global_position.x
	var delta_z: float = goal_world.z - global_position.z
	var horizontal_velocity: Vector3 = Vector3.ZERO

	# 永远单轴移动：先 X，后 Z；根节点、Mesh、RayCast 都不旋转。
	if absf(delta_x) > arrive_distance:
		horizontal_velocity.x = signf(delta_x) * work_move_speed
	elif absf(delta_z) > arrive_distance:
		horizontal_velocity.z = signf(delta_z) * work_move_speed

	velocity.x = horizontal_velocity.x
	velocity.z = horizontal_velocity.z
	velocity.y = clampf(
		(hover_world_y - global_position.y) * vertical_follow_speed,
		-vertical_follow_speed,
		vertical_follow_speed
	)

	move_and_slide()
	_update_seed_emitter_position()


func _move_to_hover_height() -> void:
	velocity = Vector3(
		0.0,
		clampf(
			(hover_world_y - global_position.y) * vertical_follow_speed,
			-vertical_follow_speed,
			vertical_follow_speed
		),
		0.0
	)
	move_and_slide()
	_update_seed_emitter_position()


func _hold_hover() -> void:
	velocity = Vector3(
		0.0,
		clampf(
			(hover_world_y - global_position.y) * vertical_follow_speed,
			-vertical_follow_speed,
			vertical_follow_speed
		),
		0.0
	)
	move_and_slide()
	_update_seed_emitter_position()


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var flat_delta: Vector3 = b - a
	flat_delta.y = 0.0
	return flat_delta.length()


func _is_at_world_goal(goal: Vector3) -> bool:
	# _move_cardinal_to_world() 也是按 X/Z 两个轴分别判断是否继续移动：
	# 两个轴均进入 arrive_distance 时，它就停止输出水平速度。
	# 因此这里必须使用同一规则，不能再用二维斜线距离。
	#
	# 旧版本会出现：
	# dx=0.046、dz=0.046（两轴都已停止）
	# flat_distance=0.065 > 0.060
	# -> 小车实际不再移动，却在 2 秒后被误判成“阻挡”。
	return (
		absf(goal.x - global_position.x) <= arrive_distance
		and absf(goal.z - global_position.z) <= arrive_distance
	)


func _snap_to_hover_goal(goal: Vector3) -> void:
	global_position = Vector3(goal.x, hover_world_y, goal.z)
	velocity = Vector3.ZERO


func _on_route_step_reached() -> void:
	var tile: FarmTile = _get_farm_tile_from_cast(center_cast)

	if tile == null or not _is_same_field_tile(tile):
		_begin_boundary_backtrack(
			movement_goal_coord,
			WorkState.PLAN_NEXT_TARGET,
			"No FarmTile at fully reached route step %s."
			% movement_goal_coord,
			true
		)
		return

	_register_farm_tile(tile)

	if tile.grid_coordinate != movement_goal_coord:
		_begin_boundary_backtrack(
			movement_goal_coord,
			WorkState.PLAN_NEXT_TARGET,
			"Expected %s, center_cast found %s."
			% [movement_goal_coord, tile.grid_coordinate],
			false
		)
		return

	if _begin_lower_after_arrival(HeightResumeAction.ROUTE_STEP, tile):
		return

	_finalize_route_step_after_height(tile)

func _finish_route() -> void:
	current_route.clear()
	route_index = 0
	stuck_time = 0.0
	last_goal_distance = INF
	recovery_attempt_count = 0

	if route_purpose == RoutePurpose.TO_SCAN_TARGET:
		_service_current_target_tile()
	else:
		work_state = WorkState.PLAN_NEXT_TARGET


func _world_position_for_grid(coord: Vector2i) -> Vector3:
	var tile: FarmTile = _get_farm_tile_at_coord(coord)
	if tile != null:
		return Vector3(tile.global_position.x, hover_world_y, tile.global_position.z)

	# grid 坐标与世界方向的关系由启动校准得出。
	var x_steps: float = float(coord.x - start_grid_coord.x)
	var z_steps: float = float(coord.y - start_grid_coord.y)
	var world_pos: Vector3 = (
		start_world_tile_position
		+ grid_positive_x_world * x_steps
		+ grid_positive_z_world * z_steps
	)
	return Vector3(world_pos.x, hover_world_y, world_pos.z)


func _get_farm_tile_at_coord(coord: Vector2i) -> FarmTile:
	_refresh_known_cell(coord)

	if not discovered_map.has(coord):
		var below: FarmTile = _get_farm_tile_from_cast(center_cast)
		if below != null and _is_same_field_tile(below) and below.grid_coordinate == coord:
			_register_farm_tile(below)
			return below
		return null

	var entry: Dictionary = discovered_map[coord]
	if int(entry.get("state", CELL_UNKNOWN)) != CELL_FARM:
		return null

	var tile: FarmTile = entry.get("tile") as FarmTile
	if not is_instance_valid(tile) or not _is_same_field_tile(tile):
		# 引用失效不是中心射线确认的田外，降级 UNKNOWN 等待后续 reconcile。
		_mark_cell_unknown(coord)
		return null

	return tile


func _estimate_grid_coord_from_world(world_position: Vector3) -> Vector2i:
	# 用经过校准的 grid 正方向向量投影，支持 grid 坐标轴反向，
	# 也支持 X/Z 与世界物理方向不一致的 FarmTile 布局。
	var flat_offset: Vector3 = world_position - start_world_tile_position
	flat_offset.y = 0.0

	var x_offset: int = 0
	var z_offset: int = 0

	if grid_positive_x_world.length_squared() > 0.001:
		var x_axis: Vector3 = grid_positive_x_world.normalized()
		x_offset = roundi(
			flat_offset.dot(x_axis)
			/ grid_positive_x_world.length()
		)

	if grid_positive_z_world.length_squared() > 0.001:
		var z_axis: Vector3 = grid_positive_z_world.normalized()
		z_offset = roundi(
			flat_offset.dot(z_axis)
			/ grid_positive_z_world.length()
		)

	return start_grid_coord + Vector2i(x_offset, z_offset)


# ------------------------------------------------------------------
# Boundary backtrack / stuck recovery / home return
# ------------------------------------------------------------------

func _update_stuck_watch(
	distance_to_goal: float,
	delta: float,
	resume_state: int,
	reason: String
) -> void:
	if last_goal_distance == INF:
		last_goal_distance = distance_to_goal
		return

	if last_goal_distance - distance_to_goal >= stuck_progress_epsilon:
		last_goal_distance = distance_to_goal
		stuck_time = 0.0
		return

	stuck_time += delta
	if stuck_time < stuck_timeout:
		return

	_block_debug(
		(
			"OVERFLIGHT_TRIGGER state=%s distance=%.3f stuck=%.2f/%.2f "
			+ "contacts=%s reason=%s."
		)
		% [
			_work_state_name(resume_state),
			distance_to_goal,
			stuck_time,
			stuck_timeout,
			_get_recent_slide_collision_summary(),
			reason,
		]
	)

	_begin_overflight_for_resume(resume_state, reason)

func _begin_confirmed_survey_edge_backtrack(reason: String) -> void:
	_begin_verified_empty_backtrack(
		survey_move_target_coord,
		WorkState.SURVEY_ADVANCE,
		reason,
		true
	)


func _begin_verified_empty_backtrack(
	failed_coord: Vector2i,
	resume_state: int,
	reason: String,
	is_survey_edge: bool = false
) -> void:
	# 唯一允许写 EMPTY 的辅助入口：
	# 调用者必须已经完整到达 failed_coord 理论中心，并由 center_cast 确认无本田 FarmTile。
	_mark_cell_empty(failed_coord)

	boundary_backtrack_coord = last_safe_grid_coord
	boundary_resume_state = resume_state
	boundary_backtrack_is_confirmed_survey_edge = is_survey_edge
	current_route.clear()
	route_index = 0
	recovery_world_goal = last_safe_world_position
	work_state = WorkState.BOUNDARY_BACKTRACK
	stuck_time = 0.0
	last_goal_distance = INF

	_debug(
		"Verified empty cell=%s. Backtrack to=%s. survey_edge=%s. %s"
		% [failed_coord, boundary_backtrack_coord, is_survey_edge, reason]
	)


func _begin_boundary_backtrack(
	failed_coord: Vector2i,
	resume_state: int,
	reason: String,
	confirmed_empty: bool = false
) -> void:
	# confirmed_empty=false 时，失败可能是玩家、建筑、工具或碰撞体阻挡；
	# 只能临时避开，绝不写 CELL_EMPTY。
	if confirmed_empty:
		_mark_cell_empty(failed_coord)
	else:
		_set_temporary_block(failed_coord)

	boundary_backtrack_coord = last_safe_grid_coord
	boundary_resume_state = resume_state
	boundary_backtrack_is_confirmed_survey_edge = false
	current_route.clear()
	route_index = 0

	recovery_world_goal = last_safe_world_position
	work_state = WorkState.BOUNDARY_BACKTRACK
	stuck_time = 0.0
	last_goal_distance = INF

	_debug(
		"Backtrack: failed=%s return=%s confirmed_empty=%s reason=%s"
		% [failed_coord, boundary_backtrack_coord, confirmed_empty, reason]
	)


func _finish_boundary_backtrack() -> void:
	var center_tile: FarmTile = _get_farm_tile_from_cast(center_cast)

	if center_tile == null or not _is_same_field_tile(center_tile):
		_request_return_home_for_current_boundary_phase(
			"Backtrack did not return to the start field."
		)
		return

	if _begin_lower_after_arrival(
		HeightResumeAction.BOUNDARY_BACKTRACK,
		center_tile
	):
		return

	_finish_boundary_backtrack_after_height(center_tile)

func _request_recovery(reason: String) -> void:
	recovery_attempt_count += 1
	_debug("Recovery %d: %s" % [recovery_attempt_count, reason])

	if recovery_attempt_count > maximum_recovery_attempts:
		_request_return_home_for_current_boundary_phase("Recovery attempts exhausted. " + reason)
		return

	recovery_world_goal = last_safe_world_position
	work_state = WorkState.RECOVERING
	stuck_time = 0.0
	last_goal_distance = INF


## 单独管理返航状态，避免原版本“已经进入 RETURNING_HOME，
## 但返航路上再次被角色顶住后没有任何超时与日志”的问题。
func _update_returning_home(delta: float) -> void:
	if return_home_retry_left > 0.0:
		_hold_hover()
		return_home_retry_left -= delta

		if return_home_retry_left <= 0.0:
			return_home_last_goal_distance = INF
			return_home_stuck_time = 0.0
			_block_debug(
				"RETURN_HOME_RETRY retry=%d/%d."
				% [return_home_retry_count, return_home_max_retries]
			)
		return

	_move_cardinal_to_world(recovery_world_goal)

	if not _is_at_world_goal(recovery_world_goal):
		var distance: float = _flat_distance(
			global_position,
			recovery_world_goal
		)
		_update_return_home_stuck_watch(distance, delta)

		if work_state != WorkState.RETURNING_HOME:
			return

		if not _is_at_world_goal(recovery_world_goal):
			return

	_snap_to_hover_goal(recovery_world_goal)
	_finish_returning_home()


func _update_return_home_stuck_watch(
	distance_to_goal: float,
	delta: float
) -> void:
	if return_home_last_goal_distance == INF:
		return_home_last_goal_distance = distance_to_goal
		return

	if (
		return_home_last_goal_distance - distance_to_goal
		>= stuck_progress_epsilon
	):
		return_home_last_goal_distance = distance_to_goal
		return_home_stuck_time = 0.0
		return

	return_home_stuck_time += delta
	if return_home_stuck_time < return_home_stuck_timeout:
		return

	return_home_retry_count += 1
	_block_debug(
		"RETURN_HOME_BLOCKED retry=%d/%d distance=%.3f stuck=%.2f/%.2f contacts=%s"
		% [
			return_home_retry_count,
			return_home_max_retries,
			distance_to_goal,
			return_home_stuck_time,
			return_home_stuck_timeout,
			_get_recent_slide_collision_summary(),
		]
	)

	if return_home_retry_count >= return_home_max_retries:
		if emergency_snap_home_after_retries:
			_block_debug(
				"RETURN_HOME_FAILSAFE_SNAP after %d blocked retries."
				% return_home_retry_count
			)
			_snap_to_hover_goal(recovery_world_goal)
			_finish_returning_home()
			return

		# 不允许 emergency snap 时，保留返航状态并继续低频等待重试。
		return_home_retry_count = 0

	return_home_retry_left = return_home_retry_delay
	return_home_last_goal_distance = INF
	return_home_stuck_time = 0.0


func _finish_returning_home() -> void:
	# 已经到达 home 的目标中心，恢复 CharacterBody3D 根碰撞。
	# 使用 deferred，避免在物理查询刷新期间直接修改 CollisionShape3D 状态。
	_set_runner_collision_enabled(true, "return_home_reached")
	_reset_global_no_motion_return_watchdog()

	overflight_active = false
	overflight_finish_after_raise = false
	height_resume_action = HeightResumeAction.NONE
	height_resume_tile = null
	hover_world_y = base_hover_world_y
	_restore_base_raycast_lengths("return_home_reached")
	_update_seed_emitter_position()

	_observe_center_tile_during_return()
	_request_local_reconcile(true)
	stuck_time = 0.0
	last_goal_distance = INF
	recovery_attempt_count = 0
	return_home_last_goal_distance = INF
	return_home_stuck_time = 0.0
	return_home_retry_left = 0.0

	_block_debug(
		"RETURN_HOME_REACHED current_grid=%s restart_pending=%s."
		% [current_grid_coord, _restart_boundary_survey_after_home]
	)

	if _restart_boundary_survey_after_home:
		_restart_boundary_survey_from_home()
	else:
		work_state = WorkState.PLAN_NEXT_TARGET


## 独立的全局活动看门狗。
##
## 与 BLOCK / center_cast / frontier / BFS 完全独立：
## - 不额外 force_raycast_update；
## - 不额外执行 BFS；
## - 只在“理论上必须移动”的状态粗略比较自身水平位置。
##
## 连续 global_no_motion_return_timeout 秒没有超过
## global_no_motion_position_epsilon 的水平位移时：
## - 边界未完整确认：返航并清空本轮地图、重新边界勘测；
## - 边界已完整确认：只返航，保留现有已确认地图与扫描进度。
func _update_global_no_motion_return_watchdog(delta: float) -> void:
	if not global_no_motion_return_enabled:
		_reset_global_no_motion_return_watchdog()
		return

	if not _is_global_motion_watch_state():
		_reset_global_no_motion_return_watchdog()
		return

	if not _global_motion_watch_active:
		_global_motion_watch_active = true
		_global_motion_watch_last_position = global_position
		_global_motion_watch_still_time = 0.0
		return

	var moved_distance: float = _flat_distance(
		global_position,
		_global_motion_watch_last_position
	)

	if moved_distance >= global_no_motion_position_epsilon:
		_global_motion_watch_last_position = global_position
		_global_motion_watch_still_time = 0.0
		return

	_global_motion_watch_still_time += delta
	if _global_motion_watch_still_time < global_no_motion_return_timeout:
		return

	_block_debug(
		(
			"GLOBAL_NO_MOTION_RETURN state=%s still=%.2f/%.2f "
			+ "epsilon=%.3f boundary_confirmed=%s position=%s."
		)
		% [
			_work_state_name(work_state),
			_global_motion_watch_still_time,
			global_no_motion_return_timeout,
			global_no_motion_position_epsilon,
			boundary_survey_confirmed,
			global_position,
		]
	)

	_reset_global_no_motion_return_watchdog()
	_request_return_home_for_current_boundary_phase(
		"Global no-motion watchdog timeout in "
		+ _work_state_name(work_state)
	)


func _is_global_motion_watch_state() -> bool:
	# 这些状态按设计应该持续产生位移；若 20 秒几乎不动，说明不论
	# 原因在 BLOCK、普通路径、边界回退还是恢复流程，都应该统一返航。
	return (
		work_state == WorkState.SURVEY_MOVING
		or work_state == WorkState.SURVEY_BLOCKED
		or work_state == WorkState.SURVEY_DETOUR_MOVING
		or work_state == WorkState.OVERFLIGHT_ASCENDING
		or work_state == WorkState.OVERFLIGHT_LOWERING
		or work_state == WorkState.MOVING_ROUTE
		or work_state == WorkState.BOUNDARY_BACKTRACK
		or work_state == WorkState.RECOVERING
	)


func _reset_global_no_motion_return_watchdog() -> void:
	_global_motion_watch_active = false
	_global_motion_watch_last_position = global_position
	_global_motion_watch_still_time = 0.0


## 统一决定“返航后是否重新边界检测”。
## 不再把这个决定分散在 BLOCK 逻辑里。
func _request_return_home_for_current_boundary_phase(reason: String) -> void:
	if not initialized:
		return

	if boundary_survey_confirmed:
		_block_debug(
			"RETURN_HOME_KEEP_CONFIRMED_BOUNDARY reason=%s."
			% reason
		)
		_request_return_home(reason)
		return

	_block_debug(
		"RETURN_HOME_RESTART_UNCONFIRMED_BOUNDARY reason=%s."
		% reason
	)
	_request_return_home_and_restart_boundary_survey(reason)


func _work_state_name(state: int) -> String:
	match state:
		WorkState.WAITING_FOR_START_TILE:
			return "WAITING_FOR_START_TILE"
		WorkState.LIFTING:
			return "LIFTING"
		WorkState.SURVEY_ADVANCE:
			return "SURVEY_ADVANCE"
		WorkState.SURVEY_MOVING:
			return "SURVEY_MOVING"
		WorkState.SURVEY_WORKING:
			return "SURVEY_WORKING"
		WorkState.SURVEY_BLOCKED:
			return "SURVEY_BLOCKED"
		WorkState.SURVEY_DETOUR_MOVING:
			return "SURVEY_DETOUR_MOVING"
		WorkState.OVERFLIGHT_ASCENDING:
			return "OVERFLIGHT_ASCENDING"
		WorkState.OVERFLIGHT_LOWERING:
			return "OVERFLIGHT_LOWERING"
		WorkState.PLAN_NEXT_TARGET:
			return "PLAN_NEXT_TARGET"
		WorkState.MOVING_ROUTE:
			return "MOVING_ROUTE"
		WorkState.WORKING_ON_TILE:
			return "WORKING_ON_TILE"
		WorkState.BOUNDARY_BACKTRACK:
			return "BOUNDARY_BACKTRACK"
		WorkState.RETURNING_HOME:
			return "RETURNING_HOME"
		WorkState.RECOVERING:
			return "RECOVERING"
		WorkState.CYCLE_PAUSE:
			return "CYCLE_PAUSE"
		WorkState.DESTROYED:
			return "DESTROYED"
		_:
			return "UNKNOWN_%d" % state


## 启用 / 禁用根 CharacterBody3D 的碰撞形状。
## 返回途中关闭它，避免玩家、工具、建筑或 FarmTile 边缘阻挡返航；
## Hit3D 是独立 Area3D，不在这里关闭。
func _set_runner_collision_enabled(enabled: bool, reason: String = "") -> void:
	if runner_collision_shape == null:
		_block_debug(
			"RUNNER_COLLISION_MISSING requested_enabled=%s reason=%s."
			% [enabled, reason]
		)
		return

	if not enabled:
		if not _return_home_collision_override_active:
			_runner_collision_previous_disabled = (
				runner_collision_shape.disabled
			)
			_return_home_collision_override_active = true

		runner_collision_shape.set_deferred("disabled", true)
		_block_debug(
			"RUNNER_COLLISION_DISABLED_FOR_RETURN reason=%s."
			% reason
		)
		return

	if not _return_home_collision_override_active:
		return

	runner_collision_shape.set_deferred(
		"disabled",
		_runner_collision_previous_disabled
	)
	_return_home_collision_override_active = false

	_block_debug(
		"RUNNER_COLLISION_RESTORED disabled=%s reason=%s."
		% [_runner_collision_previous_disabled, reason]
	)


## 用于“巡边多次绕行失败”或“本地五 Cast 全部丢失”。
## 保留返航标记，抵达 home 后会从干净状态重新测边界。
func _request_return_home_and_restart_boundary_survey(reason: String) -> void:
	if not initialized:
		return

	if _restart_boundary_survey_after_home:
		_block_debug(
			"RETURN_HOME_RESTART_ALREADY_PENDING existing_reason=%s."
			% _restart_boundary_survey_reason
		)
		return

	_restart_boundary_survey_after_home = true
	_restart_boundary_survey_reason = reason
	_debug("Return home then restart boundary survey: %s" % reason)
	_request_return_home(reason)


## 返回起始 FarmTile 后清空“本轮”边界与路线状态。
## 不清空 tool_owner、start_tile、物理 Cast 配置或种子粒子配置。
func _restart_boundary_survey_from_home() -> void:
	var reason: String = _restart_boundary_survey_reason
	_restart_boundary_survey_after_home = false
	_restart_boundary_survey_reason = ""
	_no_local_farmtile_check_count = 0

	# 重新勘测必须不继承旧边界、旧 EMPTY、旧临时阻挡或旧 frontier。
	discovered_map.clear()
	temporary_blocked_cells.clear()
	frontier_queue.clear()
	frontier_set.clear()
	scan_order.clear()
	scan_processed_this_cycle.clear()
	scan_index = 0
	current_route.clear()
	route_index = 0
	scan_order_dirty = false
	_active_target_is_frontier = false

	field_bounds_ready = false
	field_min_x = start_grid_coord.x
	field_max_x = start_grid_coord.x
	field_min_z = start_grid_coord.y
	field_max_z = start_grid_coord.y

	survey_processed_coords.clear()
	survey_detour_tried_coords.clear()
	survey_block_retry_count = 0
	survey_detour_count = 0
	survey_retry_original_pending = false
	boundary_survey_incomplete = false
	boundary_survey_confirmed = false
	_reset_global_no_motion_return_watchdog()

	var home_tile: FarmTile = _get_farm_tile_from_cast(center_cast)
	if home_tile == null or not _is_same_field_tile(home_tile):
		# 正常情况下 Runner 已经精确回到 start_world_tile_position，这里必须能看到起点。
		# 若连起点也看不到，回到 WAITING_FOR_START_TILE，让启动流程重新取得父 FarmTile。
		_debug(
			"Home restart could not see start field by center_cast. "
			+ "Reset to startup wait. reason=%s" % reason
		)
		initialized = false
		work_state = WorkState.WAITING_FOR_START_TILE
		return

	current_grid_coord = home_tile.grid_coordinate
	last_safe_grid_coord = current_grid_coord
	last_safe_world_position = Vector3(
		home_tile.global_position.x,
		hover_world_y,
		home_tile.global_position.z
	)
	start_grid_coord = home_tile.grid_coordinate
	start_world_tile_position = home_tile.global_position

	_register_farm_tile(home_tile)
	_mark_cell_walked(current_grid_coord)

	# 重新在起点基于真实邻居校准 grid -> world 映射。
	grid_mapping_calibrated = false
	grid_direction_mapping.clear()
	if auto_calibrate_grid_world_mapping:
		_calibrate_grid_world_mapping()

	_request_local_reconcile(true)
	_begin_boundary_survey()

	_block_debug(
		"RETURN_HOME_ARRIVED; boundary survey restarted. reason=%s start=%s."
		% [reason, current_grid_coord]
	)


func _request_return_home(reason: String) -> void:
	if not initialized:
		return

	# 返航时只关闭根 CollisionShape3D；Hit3D 仍保留，攻击检测不受影响。
	_set_runner_collision_enabled(false, "return_home_begin")
	_reset_global_no_motion_return_watchdog()

	recovery_world_goal = _world_position_for_grid(start_grid_coord)
	return_home_last_goal_distance = INF
	return_home_stuck_time = 0.0
	return_home_retry_count = 0
	return_home_retry_left = 0.0

	work_state = WorkState.RETURNING_HOME
	stuck_time = 0.0
	last_goal_distance = INF

	_block_debug(
		"RETURN_HOME_BEGIN reason=%s from=%s home_grid=%s home_world=%s."
		% [
			reason,
			global_position,
			start_grid_coord,
			recovery_world_goal,
		]
	)


## 主动清除“旧的物理阻挡记忆”。
## 在玩家已经离开后重试原方向前调用，避免 temporary_block_duration
## 让脚本仍把目标当成不可走。
func _clear_temporary_block(coord: Vector2i, reason: String = "") -> void:
	if not temporary_blocked_cells.has(coord):
		return

	temporary_blocked_cells.erase(coord)
	_refresh_known_cell(coord)
	_enqueue_frontier(coord)

	_block_debug(
		"TEMP_BLOCK_CLEARED coord=%s reason=%s."
		% [coord, reason]
	)


func _get_recent_slide_collision_summary() -> String:
	var collision_count: int = get_slide_collision_count()
	if collision_count <= 0:
		return "none"

	var labels: Array[String] = []
	var max_count: int = mini(collision_count, 3)

	for index in range(max_count):
		var collision: KinematicCollision3D = get_slide_collision(index)
		if collision == null:
			continue

		var collider: Object = collision.get_collider()
		if collider is Node:
			var collider_node: Node = collider as Node
			labels.append(
				"%s<%s>"
				% [str(collider_node.get_path()), collider_node.get_class()]
			)
		elif collider != null:
			labels.append(str(collider))
		else:
			labels.append("null")

	return " | ".join(labels)


func _block_debug(message: String) -> void:
	if print_debug or print_block_debug:
		print("[FarmRunner][BLOCK] ", message)


func _set_temporary_block(coord: Vector2i) -> void:
	var expiry_time: float = _now_seconds() + temporary_block_duration
	temporary_blocked_cells[coord] = expiry_time

	_block_debug(
		"TEMP_BLOCK_SET coord=%s duration=%.2fs expires_at=%.2f."
		% [coord, temporary_block_duration, expiry_time]
	)

	if discovered_map.has(coord):
		var entry: Dictionary = discovered_map[coord]
		if int(entry.get("state", CELL_UNKNOWN)) == CELL_FARM:
			entry["access"] = ACCESS_TEMP_BLOCKED
			entry["walkable"] = false
			discovered_map[coord] = entry


func _is_temporarily_blocked(coord: Vector2i) -> bool:
	if not temporary_blocked_cells.has(coord):
		return false

	if _now_seconds() >= float(temporary_blocked_cells[coord]):
		temporary_blocked_cells.erase(coord)
		_refresh_known_cell(coord)
		_enqueue_frontier(coord)
		_request_local_reconcile(false)
		return false

	return true


func _cleanup_temporary_blocks() -> void:
	var now: float = _now_seconds()
	var expired: Array[Vector2i] = []

	for coord in temporary_blocked_cells.keys():
		if now >= float(temporary_blocked_cells[coord]):
			expired.append(coord)

	for coord in expired:
		temporary_blocked_cells.erase(coord)
		_refresh_known_cell(coord)
		_enqueue_frontier(coord)
		_block_debug("TEMP_BLOCK_EXPIRED coord=%s." % coord)

	if not expired.is_empty():
		_request_local_reconcile(false)


func _now_seconds() -> float:
	return float(Time.get_ticks_msec()) * 0.001


func _width_direction_vector() -> Vector2i:
	return Vector2i(1, 0) if width_direction == 0 else Vector2i(-1, 0)


func _height_direction_vector() -> Vector2i:
	return Vector2i(0, 1) if height_direction == 0 else Vector2i(0, -1)


# ------------------------------------------------------------------
# Hit3D callbacks
# ------------------------------------------------------------------

func _connect_hit_callbacks() -> void:
	if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
		hit_3d.body_entered.connect(_on_hit_3d_body_entered)

func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet or \
	body is DetectLaserBullet):
		return
	var projectile_owner := str(body.get_bullet_owner())
	if projectile_owner == tool_owner:
		return

	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = body.bullet_effect
	var strength = body.bullet_strength
	if impact(effect, strength, projectile_owner):
		body.queue_free()

func _destroy_runner() -> void:
	is_active = false
	velocity = Vector3.ZERO
	work_state = WorkState.DESTROYED
	queue_free()


func _debug(message: String) -> void:
	if print_debug:
		print("[FarmRunner] ", message)
