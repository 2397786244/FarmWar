extends FutureWarriorAI
class_name BanditAI

## Bandit 复用 FutureWarrior 的导航、三维视觉球体/察觉度、战斗、受击反击、
## 死亡、手雷危险规避、爆破警告撤退和 Squad target/导航刷新消息。
## Bandit 自身不投掷手雷、不发出爆破/支援请求，也不响应支援请求。

const BANDIT_MAX_HP := 100.0
const BANDIT_WEAPON_ID := "suppressed_pistol"
const BANDIT_WEAPON_SCENE := "res://character/weapons/SuppressedPistol.tscn"
const BANDIT_SPEED_MULTIPLIER := 1.30
const BANDIT_SEARCH_SPEED_MULTIPLIER := 1.50
const BANDIT_COMBAT_SPEED_MULTIPLIER := 1.50
const BANDIT_FLEE_SPEED_MULTIPLIER := 1.50
## 父类默认 FLEE 为 3.7m/s：3.7 × 1.30 × 1.50 = 7.215m/s。
const BANDIT_FLEE_SPEED_MPS := 3.7 * BANDIT_SPEED_MULTIPLIER * BANDIT_FLEE_SPEED_MULTIPLIER
const CLIMBABLE_DEFENSE_SCENES := [
	"talllogwall",
	"tallbrick",
	"wiremeshgate",
	"tallmeshwall",
]


enum ClimbPhase {
	NONE,
	APPROACH,
	ASCEND,
	JUMP_DOWN,
}


@export_category("Bandit Climb")
@export var climb_detection_distance := 2.8
@export var climb_approach_distance := 0.62
@export var climb_approach_speed := 5.8
@export var climb_speed := 10.0
@export var climb_top_clearance := 0.22
@export var climb_jump_forward_speed := 4.8
@export var climb_jump_velocity := 4.2

@export_category("Bandit Evasive FLEE")
## 每次受到非致命伤害后，Bandit 在 FLEE 状态中进行短距离横向规避。
@export var hit_evasion_duration := 1.2
## 横向规避单次目标距离；远距离接敌时也用于放大左右摆动幅度。
@export var hit_evasion_distance := 9.0
## 攻击者在手枪射程外时，FLEE 不会按父类逻辑超时切回 SEARCH，
## 而是沿攻击者方向接近，并周期性左右切换、跳跃规避子弹。
@export var hit_evasion_hop_interval := 0.42
@export var hit_evasion_strafe_switch_interval := 0.65
@export var hit_evasion_jump_velocity := 4.8
@export_range(0.1, 1.0, 0.05) var hit_evasion_approach_weight := 0.82
@export_range(0.1, 1.0, 0.05) var hit_evasion_lateral_weight := 0.92

@export_category("Bandit Looting")
## SEARCH 状态每隔一小段时间检查一次前方视觉球半球，避免每个物理帧遍历掉落物。
@export_range(0.1, 2.0, 0.05) var loot_scan_interval := 0.35
@export_range(0.4, 3.0, 0.05) var pickup_collect_distance := 1.25
@export_range(0.4, 3.0, 0.05) var crop_harvest_distance := 1.2
## 0 表示视觉球的前半球：侧面可见，严格背后的物体绝不作为主动拾取/收获目标。
@export_range(-1.0, 1.0, 0.05) var loot_front_dot_min := 0.0

var climb_phase := ClimbPhase.NONE
var climb_target: Node3D
var climb_contact_position := INVALID_POSITION
var climb_direction := Vector3.ZERO
var climb_top_y := 0.0
var climb_jump_elapsed := 0.0
var bandit_evasion_direction := Vector3.ZERO
## 独立保存受击攻击者，避免父类 retaliation_timer 在远距离接敌时
## 到期后把 FLEE 目标刷新掉，导致 Bandit 原地回到 SEARCH。
var bandit_flee_attacker: CharacterBody3D
var bandit_evasion_approach := false
var bandit_evasion_lateral_sign := 1.0
var bandit_evasion_hop_timer := 0.0
var bandit_evasion_switch_timer := 0.0
var pickup_target: PickupItem
var crop_target: FarmTile
var loot_scan_timer := 0.0


func _ready() -> void:
	max_hp = BANDIT_MAX_HP
	## Bandit 比标准 FutureWarrior 快 30%。这些赋值刻意覆盖父类导出的默认值，
	## 因此无论由地图、SquadSpawner 还是多人视觉代理创建，三种长期状态一致。
	## 在此前 30% 角色速度加成的基础上，SEARCH/COMBAT 再提升 50%。
	## SEARCH 使用父类的 chase_speed 字段，因而也覆盖掉落物接近时的速度。
	chase_speed = 3.0 * BANDIT_SPEED_MULTIPLIER * BANDIT_SEARCH_SPEED_MULTIPLIER
	combat_move_speed = 2.2 * BANDIT_SPEED_MULTIPLIER * BANDIT_COMBAT_SPEED_MULTIPLIER
	## 当前 Bandit 的规避速度为 7.215m/s（原 4.81m/s 再提高 50%）。
	flee_speed = BANDIT_FLEE_SPEED_MPS
	## 仅覆盖 Bandit 的交火参数；不会改变玩家或其他 AI 使用消音手枪时的
	## 通用武器配置。20m 让其有机会在突破围墙后参与交火，但仍短于 M4。
	pistol_max_range = 20.0
	pistol_fire_interval = 0.20
	starting_grenade_count = 0
	grenade_tool_id = ""
	suppressed_pistol_tool_id = BANDIT_WEAPON_ID
	suppressed_pistol_scene_path = BANDIT_WEAPON_SCENE
	super._ready()
	add_to_group("bandit_ai")
	_update_health_label()


func _load_starting_loadout() -> void:
	## 只把消音手枪放入通用副武器槽，直接复用父类的弹匣和换弹逻辑。
	weapon_data.clear()
	weapon_data[WeaponSlot.SUPPRESSED_PISTOL] = _load_item_data(
		BANDIT_WEAPON_ID,
		BANDIT_WEAPON_SCENE,
		pistol_grip_position,
		pistol_grip_rotation,
		pistol_grip_scale,
		pistol_fire_interval,
		pistol_magazine_size,
		pistol_initial_reserve_ammo,
		pistol_reload_time
	)
	grenade_data.clear()
	grenades_remaining = 0


func _try_throw_grenade(_distance: float) -> void:
	return


func _uses_squad_demolition_requests() -> bool:
	## Bandit 能直接越过高墙，不应占用 Engineer 的爆破任务。
	return false


func _activate_squad_support_broadcast() -> void:
	## Bandit 受击后仍然由父类立即反击，但不向 Squad 请求支援。
	_squad_support_broadcast_active = false
	_squad_support_pending_after_bullet = false


func _request_squad_support() -> void:
	return


func _refresh_target() -> void:
	if target_refresh_timer > 0.0 or _is_climbing():
		return
	target_refresh_timer = target_refresh_interval
	var previous_target := target_player
	if state == AIState.FLEE and _is_valid_target(bandit_flee_attacker):
		target_player = bandit_flee_attacker
	elif retaliation_timer > 0.0 and _is_valid_target(retaliation_target):
		target_player = retaliation_target
	else:
		target_player = _find_best_visible_hostile()
	if not _is_valid_target(target_player):
		if state != AIState.FLEE:
			state = AIState.SEARCH
		_weapon_aim_active = false
		last_known_target_position = INVALID_POSITION
		return
	last_known_target_position = target_player.global_position
	if target_player != previous_target:
		_begin_target_engagement(target_player)
	if state == AIState.FLEE:
		return
	var distance := _horizontal_distance(global_position, target_player.global_position)
	state = AIState.COMBAT if _has_clear_line_to(target_player) and distance <= pistol_max_range else AIState.SEARCH


func _activate_retaliation_target(attacker: CharacterBody3D) -> void:
	if _is_climbing() or not _is_valid_target(attacker):
		return
	retaliation_target = attacker
	retaliation_timer = 5.0
	target_player = attacker
	target_refresh_timer = target_refresh_interval
	last_known_target_position = attacker.global_position
	var direction := _horizontal_direction(global_position, attacker.global_position)
	if direction.length_squared() > 0.001:
		rotation.y = atan2(-direction.x, -direction.z)
	_aim_at(_get_predicted_aim_position(attacker))
	fire_timer = 0.0
	ar15_burst_pause_timer = 0.0
	var distance := _horizontal_distance(global_position, attacker.global_position)
	state = AIState.COMBAT if _has_clear_line_to(attacker) and distance <= pistol_max_range else AIState.SEARCH
	_debug("bandit retaliation target=%s state=%s" % [attacker.name, _status_label_text()])


func _get_bandit_retaliation_target() -> CharacterBody3D:
	if _is_valid_target(bandit_flee_attacker):
		return bandit_flee_attacker
	if _is_valid_target(retaliation_target):
		return retaliation_target
	if _is_valid_target(target_player):
		return target_player
	return null


## 旧投射物、单人模式和部分多人命中回调可能只带 attacker_team 与
## hit_direction，没有直接传入攻击者节点。Bandit 需要在受击这一帧再做一次
## 无视线限制的反向候选搜索，避免“被打中但找不到攻击者”而只回 SEARCH。
func _resolve_bandit_attacker(
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> CharacterBody3D:
	if _is_valid_target(attacker_node):
		return attacker_node

	var remembered := _get_bandit_retaliation_target()
	if _is_valid_target(remembered) and (
		attacker_team.is_empty()
		or _get_combat_team(remembered) == attacker_team
	):
		return remembered

	## 复用父类的队伍/方向判定；成功时会同时更新 retaliation_target。
	if _remember_retaliation_target(attacker_team, hit_direction, attacker_node):
		remembered = _get_bandit_retaliation_target()
		if _is_valid_target(remembered):
			return remembered

	var candidates: Array[Node] = _authoritative_human_player_nodes()
	var seen: Dictionary = {}
	for candidate_node in candidates:
		if is_instance_valid(candidate_node):
			seen[candidate_node.get_instance_id()] = true
	for group_name in [&"wild_animals", &"combat_characters", &"ai_combat_targets"]:
		for candidate_node in get_tree().get_nodes_in_group(group_name):
			if not is_instance_valid(candidate_node):
				continue
			var candidate_id := candidate_node.get_instance_id()
			if seen.has(candidate_id):
				continue
			seen[candidate_id] = true
			candidates.append(candidate_node)

	var attack_direction := -hit_direction
	attack_direction.y = 0.0
	if attack_direction.length_squared() > 0.001:
		attack_direction = attack_direction.normalized()
	var closest: CharacterBody3D
	var best_score := INF
	for candidate_node in candidates:
		if not candidate_node is CharacterBody3D:
			continue
		var candidate := candidate_node as CharacterBody3D
		if not _is_active_hostile_candidate(candidate):
			continue
		if not attacker_team.is_empty() and _get_combat_team(candidate) != attacker_team:
			continue
		var offset := candidate.global_position - global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance <= 0.001:
			continue
		var score := distance
		if attack_direction.length_squared() > 0.001:
			var alignment := attack_direction.dot(offset / distance)
			## 命中方向可能来自旧实体子弹，允许少量误差，但不选明显在
			## 子弹来向相反侧的角色。
			if alignment < -0.20:
				continue
			var lateral_error := distance * sqrt(maxf(0.0, 1.0 - alignment * alignment))
			score = lateral_error * 4.0 + distance * 0.08
		if score < best_score:
			best_score = score
			closest = candidate
	return closest


func _bandit_search_goal() -> Vector3:
	## 父类 SEARCH 在到达战略目标后会生成 farm_patrol_position，Bandit
	## 不使用这套随机巡逻：它的 SEARCH 目标就是 target（或 Squad 为成员
	## 计算出的 target 附近导航点），不能因为随机巡逻点而向反方向移动。
	return _resolve_enemy_farm_position()


func _update_search_state(delta: float) -> Vector3:
	var search_goal := _bandit_search_goal()
	var route_direction := Vector3.ZERO
	if search_goal.is_finite():
		var distance_to_goal := _horizontal_distance(global_position, search_goal)
		if distance_to_goal > 1.5:
			route_direction = _direction_to_goal(search_goal)
			var direct_direction := _horizontal_direction(
				global_position,
				search_goal
			)
			if (
				route_direction.length_squared() > 0.001
				and direct_direction.length_squared() > 0.001
				and route_direction.normalized().dot(direct_direction) < 0.0
			):
				## 保留 NavigationAgent3D 的目标和路径状态，但不向调用层
				## 发出一个明显背离 target 的移动指令。下一帧仍会重新
				## 读取导航路径；如果确实需要绕行，侧向路径仍会被保留。
				route_direction = direct_direction
		_update_search_look_direction(route_direction, delta)
	if _is_valid_target(target_player):
		var distance := _horizontal_distance(global_position, target_player.global_position)
		if _has_clear_line_to(target_player) and distance <= pistol_max_range:
			_aim_at(_get_predicted_aim_position(target_player))
			_try_fire_at_target(distance)
	return route_direction


func _squad_stuck_goal_for_state() -> Vector3:
	## 卡住检测也必须使用真实 target，而不是父类保留的随机 farm patrol
	## 点，否则检测会认为 Bandit 正在朝另一个方向推进。
	if state == AIState.SEARCH:
		return _bandit_search_goal()
	return super._squad_stuck_goal_for_state()


func _update_combat_state() -> Vector3:
	if not _is_valid_target(target_player):
		state = AIState.SEARCH
		return Vector3.ZERO
	var distance := _horizontal_distance(global_position, target_player.global_position)
	if not _has_clear_line_to(target_player) or distance > pistol_max_range:
		state = AIState.SEARCH
		return Vector3.ZERO
	_aim_at(_get_predicted_aim_position(target_player))
	_try_fire_at_target(distance)
	var to_target := _horizontal_direction(global_position, target_player.global_position)
	if distance < minimum_combat_distance:
		return -to_target
	return Vector3(-to_target.z, 0.0, to_target.x) * strafe_sign


func _update_flee_state() -> Vector3:
	## 受击目标存在且在射程外时，FLEE 是“边左右跳边接近”，而不是
	## 父类那种短时间远离攻击者后进入 CHASE。Bandit 没有 CHASE 状态，
	## 进入手枪有效射程且视线清晰后立即恢复 COMBAT。
	var attacker := _get_bandit_retaliation_target()
	if _is_valid_target(attacker):
		target_player = attacker
		var distance := _horizontal_distance(global_position, attacker.global_position)
		var clear_line := _has_clear_line_to(attacker)
		if distance <= pistol_max_range and clear_line and flee_timer <= 0.0:
			bandit_evasion_approach = false
			bandit_evasion_direction = Vector3.ZERO
			bandit_flee_attacker = null
			flee_target = INVALID_POSITION
			flee_timer = 0.0
			state = AIState.COMBAT
			_aim_at(_get_predicted_aim_position(attacker))
			return _update_combat_state()

		if (
			bandit_evasion_approach
			or distance > pistol_max_range
			or not clear_line
			or flee_timer > 0.0
		):
			bandit_evasion_switch_timer = maxf(
				0.0,
				bandit_evasion_switch_timer
			)
			if bandit_evasion_switch_timer <= 0.0:
				bandit_evasion_lateral_sign *= -1.0
				bandit_evasion_switch_timer = hit_evasion_strafe_switch_interval
			var direct_approach_direction := _horizontal_direction(
					global_position,
					attacker.global_position
				)
			var navigation_approach := _direction_to_goal(attacker.global_position)
			navigation_approach.y = 0.0
			## 导航没有下一点、目标在导航区块外或路径刚被刷新时，
			## 不允许 FLEE 停在原地；使用攻击者方向作为短时移动兜底。
			var approach_direction := navigation_approach
			if approach_direction.length_squared() <= 0.001:
				approach_direction = direct_approach_direction
			elif direct_approach_direction.length_squared() > 0.001:
				## 保留正向导航绕行，但只要导航方向横向过大或反向，
				## 就加入更强的攻击者方向，确保 FLEE 真正向攻击者接近。
				var route_alignment := approach_direction.normalized().dot(
					direct_approach_direction
				)
				if route_alignment < 0.35:
					approach_direction = (
						approach_direction.normalized() * 0.30
						+ direct_approach_direction * 0.70
					).normalized()
			if approach_direction.length_squared() > 0.001:
				approach_direction = approach_direction.normalized()
				var lateral_basis := direct_approach_direction
				if lateral_basis.length_squared() <= 0.001:
					lateral_basis = approach_direction
				lateral_basis = lateral_basis.normalized()
				var lateral := Vector3(
					-lateral_basis.z,
					0.0,
					lateral_basis.x
				) * bandit_evasion_lateral_sign
				var lateral_weight := hit_evasion_lateral_weight * clampf(
					hit_evasion_distance / 9.0,
					0.75,
					1.25
				)
				var flee_direction := (
					approach_direction * hit_evasion_approach_weight
					+ lateral * lateral_weight
				).normalized()
				## 最低限保证移动指令仍然朝攻击者，而不是被路径和横移
				## 合成成侧向甚至反向；这样测试中能明确看到接近过程。
				if (
					direct_approach_direction.length_squared() > 0.001
					and flee_direction.dot(direct_approach_direction) < 0.35
				):
					flee_direction = (
						direct_approach_direction * 0.72
						+ lateral * 0.92
					).normalized()
				bandit_evasion_direction = flee_direction
				if bandit_evasion_hop_timer <= 0.0:
					_try_bandit_flee_jump()
					bandit_evasion_hop_timer = hit_evasion_hop_interval
				return bandit_evasion_direction

	if flee_timer > 0.0 and bandit_evasion_direction.length_squared() > 0.001:
		return bandit_evasion_direction

	bandit_flee_attacker = null
	bandit_evasion_approach = false
	bandit_evasion_direction = Vector3.ZERO
	bandit_evasion_hop_timer = 0.0
	flee_target = INVALID_POSITION
	state = AIState.SEARCH
	_reset_navigation_path()
	return Vector3.ZERO


func _try_bandit_flee_jump() -> void:
	## 这是 Bandit FLEE 专用的短周期规避跳跃，不依赖“前方有障碍”
	## 才触发；因此受到攻击后能稳定表现为左右横移并向攻击者接近。
	if not is_on_floor() or jump_timer > 0.0:
		return
	velocity.y = hit_evasion_jump_velocity
	jump_timer = minf(jump_cooldown, hit_evasion_hop_interval)
	_play_body_animation(&"JumpStart", 0.03)


func _update_role_specific_behavior(delta: float) -> bool:
	## Bandit 的长期行为状态只有 SEARCH / COMBAT / FLEE / DEAD；无论来自
	## 旧存档、网络状态或父类的边缘状态，都不能落入主动追击的 CHASE。
	if state == AIState.CHASE:
		state = AIState.SEARCH
	if state == AIState.FLEE:
		bandit_evasion_hop_timer = maxf(0.0, bandit_evasion_hop_timer - delta)
		bandit_evasion_switch_timer = maxf(0.0, bandit_evasion_switch_timer - delta)
	if _is_climbing():
		_update_climb(delta)
		return true
	## 掉落物优先于成熟作物；两者都只在 SEARCH 执行，因此不会打断
	## COMBAT、FLEE、手雷规避或小队爆炸撤离。
	if state == AIState.SEARCH and _update_looting_behavior(delta):
		return true
	if state == AIState.SEARCH and _try_begin_climb():
		_update_climb(delta)
		return true
	return false


func _should_force_flee_motion_when_avoidance_stalls() -> bool:
	## Bandit 的 FLEE 是受击后的强制机动；RVO 若在墙边/队员拥挤处返回
	## 零速度，不能让它只播放跳跃而不产生水平位移。
	return true


func _update_looting_behavior(delta: float) -> bool:
	loot_scan_timer = maxf(0.0, loot_scan_timer - delta)
	if not _is_valid_pickup_target(pickup_target) and not _is_valid_crop_target(crop_target):
		pickup_target = null
		crop_target = null
		if loot_scan_timer <= 0.0:
			loot_scan_timer = loot_scan_interval
			_select_front_visible_loot_target()

	if _is_valid_pickup_target(pickup_target):
		return _move_to_pickup_target(delta)
	if _is_valid_crop_target(crop_target):
		return _move_to_crop_target(delta)
	return false


func _select_front_visible_loot_target() -> void:
	## 优先级固定：任何前方可见、已落地的掉落物都先于 FarmTile。
	var nearest_pickup: PickupItem
	var nearest_pickup_distance := INF
	for node in get_tree().get_nodes_in_group("dropped_pickup_items"):
		if not node is PickupItem:
			continue
		var pickup := node as PickupItem
		if not _is_valid_pickup_target(pickup) or not _is_in_front_loot_view(pickup):
			continue
		var distance := global_position.distance_to(pickup.global_position)
		if distance < nearest_pickup_distance:
			nearest_pickup = pickup
			nearest_pickup_distance = distance
	if is_instance_valid(nearest_pickup):
		pickup_target = nearest_pickup
		crop_target = null
		_debug("bandit loot target pickup=%s distance=%.1f" % [nearest_pickup.item_id, nearest_pickup_distance])
		return

	var nearest_crop: FarmTile
	var nearest_crop_distance := INF
	for node in get_tree().get_nodes_in_group("farm_tiles"):
		if not node is FarmTile:
			continue
		var tile := node as FarmTile
		if not _is_valid_crop_target(tile) or not _is_in_front_loot_view(tile):
			continue
		var distance := global_position.distance_to(tile.global_position)
		if distance < nearest_crop_distance:
			nearest_crop = tile
			nearest_crop_distance = distance
	if is_instance_valid(nearest_crop):
		crop_target = nearest_crop
		_debug("bandit loot target crop=%s distance=%.1f" % [nearest_crop.name, nearest_crop_distance])


func _move_to_pickup_target(delta: float) -> bool:
	if not _is_valid_pickup_target(pickup_target):
		pickup_target = null
		return false
	var distance := _horizontal_distance(global_position, pickup_target.global_position)
	if distance <= pickup_collect_distance:
		var collected := false
		if GameAuthority.has_method("consume_dropped_item_for_bandit"):
			collected = bool(GameAuthority.call(
				"consume_dropped_item_for_bandit", pickup_target, self
			))
		if collected:
			_debug("bandit collected pickup=%s" % pickup_target.item_id)
			pickup_target = null
			loot_scan_timer = 0.0
			_reset_navigation_path()
			return true
		## 目标可能刚被其他玩家拾取；本帧停止并在下一帧重新选择，
		## 不能对已经释放的对象继续寻路。
		if not _is_valid_pickup_target(pickup_target):
			pickup_target = null
			loot_scan_timer = 0.0
		return true
	var direction := _direction_to_goal(pickup_target.global_position)
	_apply_character_movement(_avoid_immediate_obstacle(direction), chase_speed, delta)
	return true


func _move_to_crop_target(delta: float) -> bool:
	if not _is_valid_crop_target(crop_target):
		crop_target = null
		return false
	var distance := _horizontal_distance(global_position, crop_target.global_position)
	if distance <= crop_harvest_distance:
		## 不提供 owner_peer_id：Bandit 没有背包，FarmTile 会依现有默认链路将
		## 收获产物生成成普通世界掉落物，随后仍可被 Bandit 优先清除。
		var harvested := crop_target.harvest(global_position)
		if harvested:
			_debug("bandit harvested enemy crop tile=%s" % crop_target.name)
		crop_target = null
		loot_scan_timer = 0.0
		_reset_navigation_path()
		return true
	var direction := _direction_to_goal(crop_target.global_position)
	_apply_character_movement(_avoid_immediate_obstacle(direction), chase_speed, delta)
	return true


func _is_valid_pickup_target(value: Variant) -> bool:
	## 已释放对象传给带类型的参数会在进入函数前报错；先用 Variant 做有效性
	## 检查，再收窄为 PickupItem，和父类的目标引用清理规则保持一致。
	if not is_instance_valid(value) or not value is PickupItem:
		return false
	var pickup := value as PickupItem
	return (
		not pickup.is_queued_for_deletion()
		and pickup.landed
		and not pickup.item_id.is_empty()
	)


func _is_valid_crop_target(value: Variant) -> bool:
	if not is_instance_valid(value) or not value is FarmTile:
		return false
	var tile := value as FarmTile
	return (
		not tile.is_queued_for_deletion()
		and tile.can_harvest
		and not tile.seed_record.is_empty()
		and not tile.land_owner.is_empty()
		and tile.land_owner != team_id
	)


func _is_in_front_loot_view(value: Node3D) -> bool:
	if not is_instance_valid(value) or global_position.distance_to(value.global_position) > vision_range:
		return false
	var direction := _horizontal_direction(global_position, value.global_position)
	if direction.length_squared() <= 0.001:
		return true
	var forward := -global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() <= 0.001:
		return false
	if forward.normalized().dot(direction) < loot_front_dot_min:
		return false
	return _has_clear_loot_line(value)


func _has_clear_loot_line(value: Node3D) -> bool:
	var destination := value.global_position + Vector3.UP * 0.35
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
		## FarmTile 是 Node3D，本身没有独立物理体；射线没有命中物理对象时，
		## 代表两点之间没有遮挡，仍应视为可见。
		return true
	var cursor := hit.get("collider") as Node
	for _depth in range(12):
		if cursor == null:
			break
		if cursor == value:
			return true
		cursor = cursor.get_parent()
	## FarmTile 的地面碰撞统一由 FarmCollisionChunk 承载，不能沿父节点回溯到
	## Tile；若第一个命中点就在目标附近，则它是目标格地面而非中途遮挡。
	var hit_position: Variant = hit.get("position", Vector3.INF)
	return hit_position is Vector3 and (hit_position as Vector3).distance_to(destination) <= 0.75


func _try_begin_climb() -> bool:
	var goal := _resolve_enemy_farm_position()
	var direction := _horizontal_direction(global_position, goal)
	if not goal.is_finite() or direction.length_squared() <= 0.001:
		return false
	var origin := global_position + Vector3.UP * 0.9
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * climb_detection_distance,
		body_collision_mask,
		[get_rid()]
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var wall := _resolve_squad_demolition_root(hit.get("collider") as Node)
	if not _is_climbable_defense(wall):
		return false
	var top_y := _collision_top_y(wall)
	if top_y <= global_position.y + 0.5:
		return false
	climb_target = wall
	climb_contact_position = hit.get("position", wall.global_position) as Vector3
	climb_contact_position.y = global_position.y
	## 射线法线指向墙外、也就是 Bandit 当前所在的一侧；翻越方向必须
	## 指向墙面本身（法线反方向）。相比直接沿战略 target 的方向，这能让
	## Bandit 在斜向接近墙角时也正面贴着实际命中的那一面攀爬。
	var hit_normal_value: Variant = hit.get("normal", Vector3.ZERO)
	var hit_normal := hit_normal_value as Vector3 if hit_normal_value is Vector3 else Vector3.ZERO
	hit_normal.y = 0.0
	climb_direction = -hit_normal.normalized() if hit_normal.length_squared() > 0.001 else direction
	climb_top_y = top_y + climb_top_clearance
	climb_phase = ClimbPhase.APPROACH
	climb_jump_elapsed = 0.0
	action_animation_locked = true
	_debug("bandit climb start wall=%s top=%.2f" % [wall.name, climb_top_y])
	return true


func _update_climb(delta: float) -> void:
	if not is_instance_valid(climb_target):
		_finish_climb("target_invalid")
		return
	match climb_phase:
		ClimbPhase.APPROACH:
			var approach_position := climb_contact_position - climb_direction * climb_approach_distance
			approach_position.y = global_position.y
			var offset := approach_position - global_position
			offset.y = 0.0
			if offset.length_squared() > 0.04:
				_apply_character_movement(offset.normalized(), climb_approach_speed, delta, false, true)
				## 父类 SEARCH 会按巡逻扫视方向转身；攀墙接近阶段必须覆盖它，
				## 让模型的正面保持朝向刚命中的墙面。
				_face_climb_wall(delta)
				return
			velocity = Vector3.ZERO
			_face_climb_wall(delta, true)
			climb_phase = ClimbPhase.ASCEND
			_play_body_animation(&"LadderClimb", 0.03)
		ClimbPhase.ASCEND:
			velocity = Vector3.ZERO
			## 上爬过程锁定朝向，绝不能被 SEARCH 的左右扫视扭回墙外。
			_face_climb_wall(delta, true)
			global_position.y = move_toward(global_position.y, climb_top_y, climb_speed * delta)
			if global_position.y < climb_top_y - 0.02:
				return
			global_position += climb_direction * maxf(0.72, climb_approach_distance + 0.12)
			velocity = climb_direction * climb_jump_forward_speed
			velocity.y = climb_jump_velocity
			climb_phase = ClimbPhase.JUMP_DOWN
			climb_jump_elapsed = 0.0
			action_animation_locked = false
			_play_body_animation(&"JumpStart", 0.03)
		ClimbPhase.JUMP_DOWN:
			climb_jump_elapsed += delta
			_apply_character_movement(climb_direction, climb_jump_forward_speed, delta, false, true)
			_face_climb_wall(delta)
			if climb_jump_elapsed >= 0.15 and is_on_floor():
				_finish_climb("landed")


## CharacterBody3D 的正面为本地 -Z。climb_direction 始终是由 Bandit
## 指向墙面/越墙方向的水平向量；这会覆盖 SEARCH 状态的巡逻扫视朝向。
func _face_climb_wall(delta: float, snap: bool = false) -> void:
	if climb_direction.length_squared() <= 0.001:
		return
	var desired_yaw := atan2(-climb_direction.x, -climb_direction.z)
	if snap:
		rotation.y = desired_yaw
		return
	rotation.y = lerp_angle(
		rotation.y,
		desired_yaw,
		minf(1.0, maxf(rotation_speed, 18.0) * delta)
	)


func _finish_climb(reason: String) -> void:
	_debug("bandit climb finished reason=%s" % reason)
	climb_phase = ClimbPhase.NONE
	climb_target = null
	climb_contact_position = INVALID_POSITION
	climb_direction = Vector3.ZERO
	climb_top_y = 0.0
	climb_jump_elapsed = 0.0
	action_animation_locked = false
	state = AIState.SEARCH
	_reset_navigation_path()


func _is_climbing() -> bool:
	return climb_phase != ClimbPhase.NONE


func _is_climbable_defense(value: Node3D) -> bool:
	if not is_instance_valid(value) or not value.is_in_group("ai_demolition_target"):
		return false
	var key := value.scene_file_path.get_file().get_basename().to_lower()
	if key.is_empty():
		key = value.name.to_lower().replace("_", "")
	return key in CLIMBABLE_DEFENSE_SCENES


func _collision_top_y(value: Node3D) -> float:
	var collision := value.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or not collision.shape is BoxShape3D:
		return 0.0
	var box := collision.shape as BoxShape3D
	var vertical_scale := collision.global_transform.basis.y.length()
	return collision.global_position.y + box.size.y * 0.5 * vertical_scale


func receive_squad_message(message: Dictionary) -> void:
	## 保留 DEMOLITION_WARNING 的爆炸规避；SUPPORT_REQUEST 完全忽略。
	if int(message.get("type", -1)) == SquadMessageTypes.Type.SUPPORT_REQUEST:
		return
	super.receive_squad_message(message)


func _apply_damage(
	damage: float,
	effect: String,
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> void:
	var climbing_before_hit := _is_climbing()
	super._apply_damage(damage, effect, attacker_team, hit_direction, attacker_node)
	if state == AIState.DEAD:
		return
	if climbing_before_hit:
		## 攀爬不能被受击反击、撤退或父类状态切换打断；仍然正常扣血和死亡。
		state = AIState.SEARCH
		_squad_support_broadcast_active = false
		_squad_support_pending_after_bullet = false
		action_animation_locked = true
		return
	## Bandit 保留 COMBAT 交火，但绝不进入 CHASE 主动追击。
	_start_bandit_hit_evasion(attacker_team, hit_direction, attacker_node)


func _start_bandit_hit_evasion(
	attacker_team: String,
	hit_direction: Vector3,
	attacker_node: CharacterBody3D = null
) -> void:
	if state == AIState.DEAD:
		return

	var attacker := _resolve_bandit_attacker(
		attacker_team,
		hit_direction,
		attacker_node
	)
	if _is_valid_target(attacker):
		bandit_flee_attacker = attacker
		## 直接命中的节点优先；反向候选搜索得到的节点也要写回父类
		## retaliation_target，保证后续 target 刷新不会丢失远距离攻击者。
		if retaliation_target != attacker:
			_activate_retaliation_target(attacker)
		var distance_to_attacker := _horizontal_distance(
			global_position,
			attacker.global_position
		)
		## 远距离接近可能超过原先 5 秒的 retaliation 记忆时间；按
		## 当前 FLEE 速度预留“走到攻击者 + 5 秒”的记忆窗口。
		retaliation_timer = maxf(
			retaliation_timer,
			clampf(
				distance_to_attacker / maxf(flee_speed, 1.0) + 5.0,
				5.0,
				30.0
			)
		)

	var away_from_attacker := Vector3.ZERO
	if _is_valid_target(attacker):
		away_from_attacker = global_position - attacker.global_position
	elif is_instance_valid(attacker_node):
		away_from_attacker = global_position - attacker_node.global_position
	else:
		bandit_flee_attacker = null
		## 子弹方向是从攻击者指向 Bandit，因此它本身就是离开攻击者的
		## 方向；没有方向时再使用当前角色朝向作为稳定回退。
		away_from_attacker = hit_direction
	away_from_attacker.y = 0.0
	if away_from_attacker.length_squared() <= 0.001:
		away_from_attacker = -global_transform.basis.z
	away_from_attacker.y = 0.0
	if away_from_attacker.length_squared() <= 0.001:
		away_from_attacker = Vector3.FORWARD
	away_from_attacker = away_from_attacker.normalized()

	var lateral := Vector3(-away_from_attacker.z, 0.0, away_from_attacker.x)
	if rng.randf() < 0.5:
		lateral = -lateral
	## 先尝试左右横移，若某侧被墙挡住则交给现有 test_move 检查另一侧；
	## 最后才允许使用轻微的离开攻击者方向，避免原地抖动。
	bandit_evasion_direction = _find_open_movement_direction(
		lateral,
		maxf(0.8, hit_evasion_distance * 0.25)
	)
	bandit_evasion_lateral_sign = 1.0 if lateral.dot(
		Vector3(-away_from_attacker.z, 0.0, away_from_attacker.x)
	) >= 0.0 else -1.0
	bandit_evasion_approach = _is_valid_target(attacker) and (
		_horizontal_distance(global_position, attacker.global_position) > pistol_max_range
		or not _has_clear_line_to(attacker)
	)
	bandit_evasion_hop_timer = 0.0
	bandit_evasion_switch_timer = 0.0
	flee_target = global_position + bandit_evasion_direction * hit_evasion_distance
	flee_timer = maxf(0.1, hit_evasion_duration)
	flee_retrigger_timer = 0.0
	state = AIState.FLEE
	_debug(
		"bandit hit evasion FLEE direction=%s approach=%s speed=%.3fm/s duration=%.2fs attacker=%s"
		% [
			str(bandit_evasion_direction),
			str(bandit_evasion_approach),
			flee_speed,
			flee_timer,
			attacker.name if _is_valid_target(attacker) else "none",
		]
	)


func _respawn_at_team_spawn() -> void:
	bandit_flee_attacker = null
	bandit_evasion_approach = false
	bandit_evasion_direction = Vector3.ZERO
	bandit_evasion_hop_timer = 0.0
	bandit_evasion_switch_timer = 0.0
	super._respawn_at_team_spawn()


func _status_label_text() -> String:
	if state == AIState.DEAD:
		return "DEAD"
	if _is_climbing():
		return "CLIMB"
	if state == AIState.FLEE:
		return "FLEE"
	if state == AIState.COMBAT:
		return "COMBAT"
	return "SEARCH"


func get_network_state() -> Dictionary:
	var state_data := super.get_network_state()
	state_data["ai_type"] = "bandit"
	state_data["bandit_climb_phase"] = int(climb_phase)
	return state_data


func apply_network_state(data: Dictionary) -> void:
	super.apply_network_state(data)
	if data.has("bandit_climb_phase"):
		climb_phase = int(data.get("bandit_climb_phase", climb_phase))


func _load_future_warrior_appearance() -> void:
	## BanditAI.tscn 已经携带 Bandit Mesh，直接使用该实例作为 AppearanceNode，
	## 避免运行时再次实例化一份外观。
	var appearance_node := get_node_or_null("Mesh") as Node3D
	if appearance_node == null:
		super._load_future_warrior_appearance()
		return

	appearance_node.name = "AppearanceNode"
	appearance_node.rotation.y = deg_to_rad(180.0)
	appearance_player = appearance_node.find_child(
		"AnimationPlayer",
		true,
		false
	) as AnimationPlayer
	var skeleton_nodes := appearance_node.find_children(
		"*",
		"Skeleton3D",
		true,
		false
	)
	skeleton = skeleton_nodes[0] as Skeleton3D if not skeleton_nodes.is_empty() else null

	if appearance_player == null or skeleton == null:
		push_error("[BanditAI] Bandit Mesh needs AnimationPlayer and Skeleton3D.")
		return

	right_hand_socket.use_external_skeleton = true
	right_hand_socket.external_skeleton = right_hand_socket.get_path_to(skeleton)
	right_hand_socket.bone_name = "Hand.R"
	right_hand_socket.override_pose = false
	if not appearance_player.animation_finished.is_connected(_on_skeleton_animation_finished):
		appearance_player.animation_finished.connect(_on_skeleton_animation_finished)
	_setup_upper_body_aim()
	_play_body_animation(&"Idle", 0.0)


func _update_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = show_health_label and state != AIState.DEAD
	health_label.text = (
		"Bandit  %d / %d\n"
		+ "消音手枪 %d/%d\n"
		+ "状态: %s\n"
		+ "困住状态: %s\n"
		+ "最近消息: %s"
	) % [
		roundi(current_hp),
		roundi(max_hp),
		_weapon_ammo_in_mag(WeaponSlot.SUPPRESSED_PISTOL),
		_weapon_reserve_ammo(WeaponSlot.SUPPRESSED_PISTOL),
		_status_label_text(),
		_squad_stuck_label_text(),
		_last_squad_message_label(),
	]
