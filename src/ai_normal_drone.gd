extends NormalDrone
class_name AINormalDrone

## 蓝方 AssistantAI 使用的自主投弹无人机。
## 继承 NormalDrone，保留其 HP、Hit3D、炸弹、SignalJam 与电子状态效果。

signal destroyed
signal signal_link_lost

enum AttackMode {
	HUNT_PLAYERS,
	BOMBARD_ENEMY_FARM,
}

@export var team_id := "blue"
@export var target_scan_range := 50.0
@export var attack_standoff_distance := 9.0
@export var ai_move_speed := 11.0
@export var target_refresh_interval := 0.35
@export var minimum_effective_signal_to_attack := 0.20
@export var evasion_seconds := 2.5
@export var cruise_altitude := 16.0
@export var bombing_altitude := 10.0
@export var search_altitude := 20.0
@export var search_radius := 80.0
@export var search_target_arrival_radius := 8.0
@export var search_minimum_radius := 20.0
@export var search_boundary_margin := 8.0
@export var search_waypoint_attempts := 20
@export var search_timeout_seconds := 30.0
@export var movement_stall_seconds := 3.0
@export var movement_stall_min_displacement := 1.5
@export var evasion_altitude := 20.0
@export var evasion_vertical_clearance := 6.0
@export var evasion_lateral_distance := 18.0
@export var evasion_lateral_speed := 14.0
@export var console_debug_enabled := true
@export var player_hunt_seconds := 30.0
## 名称为兼容既有场景资源；实际轰炸的是 Assistant 的战略 target，而非农田。
@export var farm_bombard_seconds := 30.0
@export var farm_bomb_interval := 2.0
@export var strategic_bombard_radius := 10.0
@export var strategic_bombard_waypoint_switch_radius := 2.5
@export var strategic_bombard_waypoint_stopping_distance := 0.5

var target_player: CharacterBody3D
var target_refresh_timer := 0.0
var destroyed_emitted := false
var signal_lost_emitted := false
var ai_controller: Node3D
var operator_defensive_hold := false
var evasion_remaining := 0.0
var evasion_target_height := 0.0
var evasion_direction := Vector3.ZERO
var evasion_start_position := Vector3.ZERO
var attack_mode := AttackMode.HUNT_PLAYERS
var phase_remaining := 0.0
var farm_bomb_timer := 0.0
var search_elapsed := 0.0
var search_waypoint := Vector3.INF
var search_detour_waypoint := Vector3.INF
var search_target_origin := Vector3.INF
var search_target_reached := false
var bombard_waypoint := Vector3.INF
var bombard_target_origin := Vector3.INF
var fallback_strategic_target := Vector3.INF
var movement_stall_elapsed := 0.0
var movement_stall_origin := Vector3.INF
var movement_stall_waypoint := Vector3.INF
var cached_map_bounds := Rect2()
var cached_map_bounds_valid := false

const MAP_BOUNDARY_COLLISION_LAYER := 2


func _ready() -> void:
	tool_owner = team_id
	_placed = true
	power_on = true
	super._ready()
	activate_tool()
	power_on = true
	move_speed = ai_move_speed
	add_to_group("ai_normal_drones")
	add_to_group("remote_units")
	add_to_group("remote_devices")
	if health_label != null:
		health_label.visible = true
		health_label.text = "AI Drone\n%d / %d" % [roundi(current_hp), roundi(SET_HP)]


func set_ai_controller(controller: Node3D) -> void:
	ai_controller = controller
	# Directly reuse NormalDrone's distance, SignalJam, and SignalAugment calculations.
	set_remote_receiver(controller)


func has_attack_link() -> bool:
	return is_instance_valid(ai_controller) \
		and get_effective_signal_strength(ai_controller) >= minimum_effective_signal_to_attack


func has_active_target() -> bool:
	return is_instance_valid(target_player) and has_attack_link()


func set_operator_defensive_hold(value: bool) -> void:
	operator_defensive_hold = value
	if value:
		target_player = null
		velocity = Vector3.ZERO


func get_debug_status() -> String:
	if evasion_remaining > 0.0:
		return "受击规避 %.1fs" % evasion_remaining
	if operator_defensive_hold:
		return "防御悬停"
	if not is_instance_valid(ai_controller):
		return "控制端丢失"
	var signal_percent := roundi(get_effective_signal_strength(ai_controller) * 100.0)
	if not has_attack_link():
		return "弱信号悬停 %d%%" % signal_percent
	var mode_text := "攻击玩家" if is_instance_valid(target_player) else "高空搜索"
	if attack_mode == AttackMode.BOMBARD_ENEMY_FARM:
		mode_text = "目标机动轰炸"
	var phase_text := "攻击 %.1f / %.0fs" % [phase_remaining, player_hunt_seconds]
	if attack_mode == AttackMode.BOMBARD_ENEMY_FARM:
		phase_text = "目标附近 %.0fm 轰炸 %.1f / %.0fs" % [strategic_bombard_radius, phase_remaining, farm_bombard_seconds]
	elif not is_instance_valid(target_player):
		phase_text = "先抵达目标" if not search_target_reached else "圆形搜索 %.0fm %.1f / %.0fs" % [search_radius, search_elapsed, search_timeout_seconds]
	var player_text: String = "无" if not is_instance_valid(target_player) else str(target_player.name)
	return "%s | %s | 锁定:%s | 信号 %d%%" % [mode_text, phase_text, player_text, signal_percent]


func get_console_debug_status() -> String:
	var waypoint_text := "无"
	var active_waypoint := bombard_waypoint if attack_mode == AttackMode.BOMBARD_ENEMY_FARM else search_waypoint
	if attack_mode == AttackMode.HUNT_PLAYERS and search_detour_waypoint != Vector3.INF:
		active_waypoint = search_detour_waypoint
	if active_waypoint != Vector3.INF:
		waypoint_text = "(%s)" % _format_debug_vector(active_waypoint)
	return "%s drone_pos=(%s) velocity=(%s) waypoint=%s" % [
		get_debug_status(),
		_format_debug_vector(global_position),
		_format_debug_vector(velocity),
		waypoint_text,
	]


func _physics_process(delta: float) -> void:
	# AI 行为与投弹仅由本地/服务器权威执行；客户端只接收权威状态，
	# 不能再生成一枚未登记到 GameAuthority 的本地 BoomBullet。
	if GameAuthority.is_client_proxy():
		return
	if destroyed_emitted:
		return
	# AI 不读取遥控输入，但保持与 NormalDrone 一致的电子状态与旋翼更新。
	if _bomb_cooldown_left > 0.0:
		_bomb_cooldown_left = maxf(0.0, _bomb_cooldown_left - delta)
	_tick_electronic_status(delta)
	_update_health_label()
	if is_electronics_disabled():
		_reset_movement_stall()
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	# 受击规避必须优先于 Assistant 的低信号悬停和防御保持，
	# 否则刚受到攻击时可能只会原地刹车，玩家看不到规避动作。
	if evasion_remaining > 0.0:
		_update_evasion(delta)
		return
	if operator_defensive_hold:
		_reset_movement_stall()
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	if not is_instance_valid(ai_controller):
		_reset_movement_stall()
		_emit_signal_lost_once()
		return
	if not has_attack_link():
		# Weak signal is recoverable. Hover in place while the Assistant closes the gap.
		_reset_movement_stall()
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	_update_rotors(delta)
	match attack_mode:
		AttackMode.HUNT_PLAYERS:
			_update_player_hunt(delta)
		AttackMode.BOMBARD_ENEMY_FARM:
			_update_farm_bombardment(delta)


func _update_player_hunt(delta: float) -> void:
	# 锁定后不再因为一次视觉刷新失败而清空 target；只有目标死亡或
	# 30 秒攻击周期结束才会离开锁定状态。
	if is_instance_valid(target_player) and _is_target_player_dead(target_player):
		_enter_target_bombardment()
		return
	if not is_instance_valid(target_player):
		target_refresh_timer = maxf(0.0, target_refresh_timer - delta)
		if target_refresh_timer <= 0.0:
			target_refresh_timer = target_refresh_interval
			var candidate := _find_visible_enemy_player()
			if is_instance_valid(candidate):
				target_player = candidate
				phase_remaining = 0.0
				search_elapsed = 0.0
				search_waypoint = Vector3.INF
				search_detour_waypoint = Vector3.INF
				_reset_movement_stall()
		if not is_instance_valid(target_player):
			# 轰炸周期结束后，始终在战略目标上空的 80m 区域内搜索，
			# 而不是因暂时丢失玩家直接切回轰炸。
			_update_high_altitude_search(delta)
			return
	phase_remaining += delta
	_fly_toward(target_player.global_position + Vector3.UP * 1.2, true, bombing_altitude)
	if phase_remaining >= player_hunt_seconds:
		_enter_target_bombardment()


func _enter_target_bombardment() -> void:
	attack_mode = AttackMode.BOMBARD_ENEMY_FARM
	phase_remaining = 0.0
	farm_bomb_timer = 0.0
	search_elapsed = 0.0
	search_target_reached = false
	target_player = null
	bombard_waypoint = Vector3.INF
	bombard_target_origin = Vector3.INF
	search_detour_waypoint = Vector3.INF
	_reset_movement_stall()


func _update_farm_bombardment(delta: float) -> void:
	phase_remaining += delta
	farm_bomb_timer = maxf(0.0, farm_bomb_timer - delta)
	var strategic_target := _get_strategic_target_position()
	if strategic_target == Vector3.INF:
		_reset_movement_stall()
		_update_high_altitude_search(delta)
		return
	if bombard_target_origin == Vector3.INF \
			or _horizontal_distance_between(bombard_target_origin, strategic_target) > 1.0:
		bombard_target_origin = strategic_target
		bombard_waypoint = Vector3.INF
	if bombard_waypoint == Vector3.INF \
			or _horizontal_distance_to(bombard_waypoint) <= strategic_bombard_waypoint_switch_radius:
		bombard_waypoint = _generate_radial_waypoint(
			strategic_target,
			2.0,
			strategic_bombard_radius
		)
	# target 模式不是飞到中心后悬停，而是在 target 周边 10m 内持续切换航点。
	_fly_toward(
		bombard_waypoint,
		false,
		bombing_altitude,
		strategic_bombard_waypoint_stopping_distance
	)
	var in_bombard_area := _horizontal_distance_to(strategic_target) <= strategic_bombard_radius + 2.0
	if in_bombard_area and farm_bomb_timer <= 0.0 and _bomb_cooldown_left <= 0.0:
		_drop_bomb()
		if _bomb_cooldown_left > 0.0:
			farm_bomb_timer = farm_bomb_interval
	if phase_remaining >= farm_bombard_seconds:
		# 未配置 target 时，每轮轰炸结束都重新随机一个敌方出生点；
		# 显式 target 则始终保持地图指定节点。
		_get_strategic_target_position(true)
		attack_mode = AttackMode.HUNT_PLAYERS
		phase_remaining = 0.0
		target_refresh_timer = 0.0
		search_waypoint = Vector3.INF
		search_detour_waypoint = Vector3.INF
		search_target_origin = Vector3.INF
		search_target_reached = false
		search_elapsed = 0.0
		bombard_waypoint = Vector3.INF
		bombard_target_origin = Vector3.INF
		_reset_movement_stall()


func _fly_toward(
	target_position: Vector3,
	allow_bomb: bool,
	desired_altitude: float,
	stopping_distance: float = -1.0
) -> void:
	if target_position == Vector3.INF:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * get_physics_process_delta_time())
		move_and_slide()
		return
	var horizontal := target_position - global_position
	horizontal.y = 0.0
	var distance := horizontal.length()
	var resolved_stopping_distance := attack_standoff_distance if stopping_distance < 0.0 else stopping_distance
	if distance > resolved_stopping_distance:
		velocity = horizontal.normalized() * ai_move_speed * GameAuthority.get_chain_link_fence_speed_multiplier(
			global_position,
			team_id,
			"remote"
		)
	else:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * get_physics_process_delta_time())
	var vertical_speed_multiplier := GameAuthority.get_chain_link_fence_speed_multiplier(
		global_position,
		team_id,
		"remote"
	)
	velocity.y = clampf(
		(desired_altitude - global_position.y) * 4.0,
		-ascend_speed * vertical_speed_multiplier,
		ascend_speed * vertical_speed_multiplier
	)
	look_at(target_position, Vector3.UP)
	move_and_slide()
	if _is_navigation_move_active():
		if _did_hit_map_boundary():
			# 边界碰撞不等待 3 秒，立即生成一个朝地图内部的新航点。
			_reroute_navigation_waypoint()
		else:
			_monitor_navigation_progress(target_position, resolved_stopping_distance)
	else:
		_reset_movement_stall()
	if allow_bomb and distance <= attack_standoff_distance + 3.0 and _bomb_cooldown_left <= 0.0:
		_drop_bomb()


func _drop_bomb() -> void:
	if _bomb_cooldown_left > 0.0 or not is_instance_valid(bullet_mount_slot):
		return
	var initial_velocity := velocity + Vector3.DOWN * bomb_initial_down_speed
	if GameAuthority.spawn_ai_drone_bomb(
		bullet_mount_slot.global_position,
		initial_velocity,
		team_id,
		bomb_damage,
		bomb_explosion_radius
	):
		_bomb_cooldown_left = bomb_cooldown


func _get_strategic_target_position(force_refresh := false) -> Vector3:
	if is_instance_valid(ai_controller) and ai_controller.has_method("get_attack_target_position"):
		var controller_target: Variant = ai_controller.call("get_attack_target_position", force_refresh)
		if controller_target is Vector3 and controller_target != Vector3.INF:
			return controller_target as Vector3
	if force_refresh:
		fallback_strategic_target = Vector3.INF
	if fallback_strategic_target != Vector3.INF:
		return fallback_strategic_target
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return Vector3.INF
	if game_world.has_method("get_random_enemy_spawn_position"):
		var value: Variant = game_world.call(
			"get_random_enemy_spawn_position", team_id, get_instance_id(), 0
		)
		if value is Vector3 and value != Vector3.INF:
			fallback_strategic_target = value as Vector3
	return fallback_strategic_target


func _update_high_altitude_search(delta: float) -> void:
	var strategic_target := _get_strategic_target_position()
	if strategic_target == Vector3.INF:
		_reset_movement_stall()
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * get_physics_process_delta_time())
		move_and_slide()
		return
	# 战略目标变化时，先重新飞抵新目标，不能沿用旧的巡航航点。
	if search_target_origin == Vector3.INF \
			or _horizontal_distance_between(search_target_origin, strategic_target) > 1.0:
		search_target_origin = strategic_target
		search_target_reached = false
		search_waypoint = Vector3.INF
		search_detour_waypoint = Vector3.INF
		search_elapsed = 0.0
		_reset_movement_stall()
	# 先抵达 target 上空，再开始在目标中心 80m 半径内巡航。
	if not search_target_reached:
		if search_detour_waypoint != Vector3.INF:
			if _horizontal_distance_to(search_detour_waypoint) <= 1.0:
				search_detour_waypoint = Vector3.INF
			else:
				_fly_toward(search_detour_waypoint, false, search_altitude, 1.0)
				return
		if _horizontal_distance_to(strategic_target) > search_target_arrival_radius:
			_fly_toward(strategic_target, false, search_altitude, 1.0)
			return
		search_target_reached = true
		search_elapsed = 0.0
		_reset_movement_stall()
	# 只有真正抵达 target 并进入圆形巡航后才开始计算 30 秒搜索时间。
	search_elapsed += delta
	if search_elapsed >= search_timeout_seconds:
		_enter_target_bombardment()
		return
	if search_waypoint == Vector3.INF or _horizontal_distance_to(search_waypoint) <= 5.0:
		search_waypoint = _generate_search_waypoint(strategic_target)
	_fly_toward(search_waypoint, false, search_altitude, 1.0)


func _horizontal_distance_to(target_position: Vector3) -> float:
	var offset := target_position - global_position
	offset.y = 0.0
	return offset.length()


func _horizontal_distance_between(first: Vector3, second: Vector3) -> float:
	var offset := second - first
	offset.y = 0.0
	return offset.length()


func _generate_search_waypoint(origin: Vector3, force_inward := false) -> Vector3:
	var minimum_radius := minf(search_minimum_radius, search_radius)
	return _generate_radial_waypoint(origin, minimum_radius, search_radius, force_inward)


func _generate_radial_waypoint(
	origin: Vector3,
	minimum_radius: float,
	maximum_radius: float,
	force_inward := false
) -> Vector3:
	var min_radius := maxf(0.0, minf(minimum_radius, maximum_radius))
	var max_radius := maxf(min_radius, maximum_radius)
	var inward_angle := randf_range(0.0, TAU)
	if force_inward:
		var safe_bounds := _get_safe_map_bounds()
		if safe_bounds.size.x > 0.0 and safe_bounds.size.y > 0.0:
			var inward := safe_bounds.get_center() - Vector2(global_position.x, global_position.z)
			if inward.length_squared() > 0.001:
				inward_angle = inward.angle()
		elif Vector2(velocity.x, velocity.z).length_squared() > 0.001:
			inward_angle = Vector2(-velocity.x, -velocity.z).angle()
	for attempt in range(maxi(1, search_waypoint_attempts)):
		var angle := randf_range(0.0, TAU)
		if force_inward:
			angle = inward_angle + randf_range(-0.9, 0.9)
		var radius := lerpf(min_radius, max_radius, sqrt(randf()))
		var candidate := origin + Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)
		if _is_safe_waypoint(candidate):
			return candidate
	# 地图很窄或 target 紧贴边界时，随机圆内可能没有合格点；最后仍然
	# 把候选点夹到安全矩形内，确保不会把无人机再次送向边界墙。
	var fallback := origin + Vector3(cos(inward_angle) * max_radius, 0.0, sin(inward_angle) * max_radius)
	return _clamp_waypoint_to_safe_bounds(fallback)


func _generate_inward_detour_waypoint(origin: Vector3) -> Vector3:
	var safe_bounds := _get_safe_map_bounds()
	var direction := Vector2.ZERO
	if safe_bounds.size.x > 0.0 and safe_bounds.size.y > 0.0:
		direction = safe_bounds.get_center() - Vector2(global_position.x, global_position.z)
	if direction.length_squared() <= 0.001:
		direction = Vector2(-velocity.x, -velocity.z)
	if direction.length_squared() <= 0.001:
		direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	direction = direction.normalized()
	var detour_distance := clampf(search_radius * 0.35, 12.0, 30.0)
	var base_angle := direction.angle()
	for attempt in range(maxi(1, search_waypoint_attempts)):
		var angle := base_angle + randf_range(-0.75, 0.75)
		var candidate := global_position + Vector3(
			cos(angle) * detour_distance,
			origin.y - global_position.y,
			sin(angle) * detour_distance
		)
		if _is_safe_waypoint(candidate):
			return candidate
	return _clamp_waypoint_to_safe_bounds(global_position + Vector3(
		direction.x * detour_distance,
		origin.y - global_position.y,
		direction.y * detour_distance
	))


func _is_safe_waypoint(candidate: Vector3) -> bool:
	var safe_bounds := _get_safe_map_bounds()
	if safe_bounds.size.x <= 0.0 or safe_bounds.size.y <= 0.0:
		# 没有边界元数据的旧地图仍使用 3 秒无位移脱卡规则。
		return true
	return safe_bounds.has_point(Vector2(candidate.x, candidate.z))


func _clamp_waypoint_to_safe_bounds(candidate: Vector3) -> Vector3:
	var safe_bounds := _get_safe_map_bounds()
	if safe_bounds.size.x <= 0.0 or safe_bounds.size.y <= 0.0:
		return candidate
	return Vector3(
		clampf(candidate.x, safe_bounds.position.x, safe_bounds.end.x),
		candidate.y,
		clampf(candidate.z, safe_bounds.position.y, safe_bounds.end.y)
	)


func _get_safe_map_bounds() -> Rect2:
	var bounds := _get_playable_map_bounds()
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0:
		return Rect2()
	var margin := minf(
		maxf(0.0, search_boundary_margin),
		minf(bounds.size.x, bounds.size.y) * 0.45
	)
	return Rect2(
		bounds.position + Vector2.ONE * margin,
		bounds.size - Vector2.ONE * margin * 2.0
	)


func _get_playable_map_bounds() -> Rect2:
	if cached_map_bounds_valid:
		return cached_map_bounds
	var world := GlobalVar.gameworld as Node3D
	if not is_instance_valid(world):
		world = get_tree().current_scene as Node3D
	if not is_instance_valid(world):
		return Rect2()
	var boundary_root := world.get_node_or_null("MapBoundaryWalls")
	var boundary_bounds := _get_bounds_from_boundary_walls(boundary_root)
	if boundary_bounds.size.x > 0.0 and boundary_bounds.size.y > 0.0:
		cached_map_bounds = boundary_bounds
		cached_map_bounds_valid = true
		return cached_map_bounds
	var map_size_value: Variant = world.get_meta("farmwar_map_size", Vector2.ZERO)
	var map_size := Vector2.ZERO
	if map_size_value is Vector2:
		map_size = map_size_value as Vector2
	elif map_size_value is Vector2i:
		map_size = Vector2(map_size_value as Vector2i)
	if map_size.x <= 0.0 or map_size.y <= 0.0:
		return Rect2()
	var center := Vector2(world.global_position.x, world.global_position.z)
	cached_map_bounds = Rect2(center - map_size * 0.5, map_size)
	cached_map_bounds_valid = true
	return cached_map_bounds


func _get_bounds_from_boundary_walls(boundary_root: Node) -> Rect2:
	if not is_instance_valid(boundary_root):
		return Rect2()
	var walls: Array[Dictionary] = []
	for child in boundary_root.get_children():
		var wall := child as Node3D
		if wall == null:
			continue
		var shape_node := wall.find_child("CollisionShape3D", true, false) as CollisionShape3D
		if shape_node == null or not shape_node.shape is BoxShape3D:
			continue
		var box := shape_node.shape as BoxShape3D
		var shape_scale := shape_node.global_transform.basis.get_scale()
		walls.append({
			"name": str(wall.name).to_lower(),
			"center": shape_node.global_position,
			"half_x": absf(box.size.x * shape_scale.x) * 0.5,
			"half_z": absf(box.size.z * shape_scale.z) * 0.5,
		})
	if walls.size() < 4:
		return Rect2()
	var north: Dictionary = {}
	var south: Dictionary = {}
	var west: Dictionary = {}
	var east: Dictionary = {}
	var north_z := INF
	var south_z := -INF
	var west_x := INF
	var east_x := -INF
	for wall_data in walls:
		var center: Vector3 = wall_data["center"]
		var wall_name: String = wall_data["name"]
		if wall_name.contains("north"):
			north = wall_data
		if wall_name.contains("south"):
			south = wall_data
		if wall_name.contains("west"):
			west = wall_data
		if wall_name.contains("east"):
			east = wall_data
		if float(wall_data["half_x"]) >= float(wall_data["half_z"]):
			if center.z < north_z:
				north_z = center.z
				if north.is_empty():
					north = wall_data
			if center.z > south_z:
				south_z = center.z
				if south.is_empty():
					south = wall_data
		else:
			if center.x < west_x:
				west_x = center.x
				if west.is_empty():
					west = wall_data
			if center.x > east_x:
				east_x = center.x
				if east.is_empty():
					east = wall_data
	if north.is_empty() or south.is_empty() or west.is_empty() or east.is_empty():
		return Rect2()
	var north_center: Vector3 = north["center"]
	var south_center: Vector3 = south["center"]
	var west_center: Vector3 = west["center"]
	var east_center: Vector3 = east["center"]
	var min_x := west_center.x + float(west["half_x"])
	var max_x := east_center.x - float(east["half_x"])
	var min_z := north_center.z + float(north["half_z"])
	var max_z := south_center.z - float(south["half_z"])
	if max_x <= min_x or max_z <= min_z:
		return Rect2()
	return Rect2(Vector2(min_x, min_z), Vector2(max_x - min_x, max_z - min_z))


func _is_navigation_move_active() -> bool:
	return attack_mode == AttackMode.BOMBARD_ENEMY_FARM \
		or (attack_mode == AttackMode.HUNT_PLAYERS and not is_instance_valid(target_player))


func _did_hit_map_boundary() -> bool:
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider := collision.get_collider()
		if collider is CollisionObject3D \
				and ((collider as CollisionObject3D).collision_layer & MAP_BOUNDARY_COLLISION_LAYER) != 0:
			return true
		var cursor := collider as Node
		while cursor != null:
			if cursor.name == "MapBoundaryWalls":
				return true
			cursor = cursor.get_parent()
	return false


func _monitor_navigation_progress(target_position: Vector3, stopping_distance: float) -> void:
	if not _is_navigation_move_active() or _horizontal_distance_to(target_position) <= stopping_distance + 0.5:
		_reset_movement_stall()
		return
	if movement_stall_waypoint == Vector3.INF \
			or _horizontal_distance_between(movement_stall_waypoint, target_position) > 0.5:
		movement_stall_waypoint = target_position
		movement_stall_origin = global_position
		movement_stall_elapsed = 0.0
		return
	movement_stall_elapsed += get_physics_process_delta_time()
	if movement_stall_elapsed < movement_stall_seconds:
		return
	var moved_distance := _horizontal_distance_between(movement_stall_origin, global_position)
	if moved_distance < movement_stall_min_displacement:
		# 对边界和高空建筑都适用：放弃当前方向，重新生成朝内/侧向航点。
		_reroute_navigation_waypoint()
	else:
		movement_stall_origin = global_position
		movement_stall_elapsed = 0.0


func _reset_movement_stall() -> void:
	movement_stall_elapsed = 0.0
	movement_stall_origin = Vector3.INF
	movement_stall_waypoint = Vector3.INF


func _reroute_navigation_waypoint() -> void:
	_reset_movement_stall()
	if attack_mode == AttackMode.BOMBARD_ENEMY_FARM:
		var bombard_target := _get_strategic_target_position()
		if bombard_target != Vector3.INF:
			bombard_waypoint = _generate_radial_waypoint(
				bombard_target,
				2.0,
				strategic_bombard_radius,
				true
			)
		return
	if attack_mode == AttackMode.HUNT_PLAYERS and not is_instance_valid(target_player):
		var search_target := _get_strategic_target_position()
		if search_target == Vector3.INF:
			return
		if search_target_reached:
			search_waypoint = _generate_search_waypoint(search_target, true)
		else:
			search_detour_waypoint = _generate_inward_detour_waypoint(search_target)


func _format_debug_vector(value: Vector3) -> String:
	return "%.1f, %.1f, %.1f" % [value.x, value.y, value.z]


func _emit_signal_lost_once() -> void:
	if signal_lost_emitted:
		return
	signal_lost_emitted = true
	target_player = null
	velocity = Vector3.ZERO
	signal_link_lost.emit()


func _update_evasion(delta: float) -> void:
	evasion_remaining = maxf(0.0, evasion_remaining - delta)
	var speed_multiplier := GameAuthority.get_chain_link_fence_speed_multiplier(
		global_position,
		team_id,
		"remote"
	)
	var evasion_target := evasion_start_position + evasion_direction * evasion_lateral_distance
	var horizontal_target := evasion_target - global_position
	horizontal_target.y = 0.0
	# 前段横向脱离命中位置，末段刹车；同时向上抬升到规避高度。
	if evasion_remaining > 0.55 and horizontal_target.length() > 0.5:
		var horizontal_velocity := horizontal_target.normalized() * evasion_lateral_speed * speed_multiplier
		velocity.x = horizontal_velocity.x
		velocity.z = horizontal_velocity.z
	else:
		velocity.x = move_toward(velocity.x, 0.0, braking_acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, braking_acceleration * delta)
	if global_position.y < evasion_target_height - 0.2:
		velocity.y = minf(
			(evasion_target_height - global_position.y) * 4.0,
			ascend_speed * speed_multiplier
		)
	else:
		velocity.y = move_toward(velocity.y, 0.0, braking_acceleration * delta)
	if evasion_direction.length_squared() > 0.001:
		look_at(global_position + evasion_direction, Vector3.UP)
	move_and_slide()
	if evasion_remaining <= 0.0:
		target_refresh_timer = 0.0
		evasion_direction = Vector3.ZERO


func _find_visible_enemy_player() -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	for group_name in [&"human_players", &"combat_characters"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D or node == ai_controller:
				continue
			var candidate := node as CharacterBody3D
			if _is_target_player_dead(candidate):
				continue
			if _get_combat_team(candidate) == team_id:
				continue
			var distance := global_position.distance_to(candidate.global_position)
			if distance > target_scan_range or not _has_line_of_sight(candidate):
				continue
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func _is_target_player_dead(candidate: CharacterBody3D) -> bool:
	if not is_instance_valid(candidate):
		return true
	if candidate.has_method("get_network_state"):
		var network_state := candidate.call("get_network_state") as Dictionary
		if bool(network_state.get("dead", false)):
			return true
	if candidate is GamePlayer:
		var player := candidate as GamePlayer
		if player.is_respawning:
			return true
		var peer_id := int(player.authority_peer_id)
		if GameAuthority.player_states.has(peer_id):
			var player_state: Dictionary = GameAuthority.player_states[peer_id]
			return float(player_state.get("hp", player.server_hp)) <= 0.0 \
				or float(player_state.get("respawn_left", 0.0)) > 0.0
		return player.server_hp <= 0.0
	return false


func _has_line_of_sight(candidate: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(
		global_position, candidate.global_position + Vector3.UP, 65535, [get_rid()]
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var cursor := hit.get("collider") as Node
	while cursor != null:
		if cursor == candidate:
			return true
		cursor = cursor.get_parent()
	return false


func get_combat_team() -> String:
	return team_id


func _get_combat_team(node: Node) -> String:
	if node.has_method("get_combat_team"):
		return str(node.call("get_combat_team"))
	for property_name in ["team", "team_id", "tool_owner"]:
		for property_info: Dictionary in node.get_property_list():
			if str(property_info.get("name", "")) == property_name:
				return str(node.get(property_name))
	return ""


func impact(effect: String, strength: float, attacker_team: String = "") -> bool:
	var applied := super.impact(effect, strength, attacker_team)
	if applied and strength > 0.0 and current_hp > 0.0:
		_reset_movement_stall()
		evasion_remaining = evasion_seconds
		evasion_start_position = global_position
		evasion_target_height = maxf(
			evasion_altitude,
			global_position.y + evasion_vertical_clearance
		)
		var angle := randf_range(0.0, TAU)
		evasion_direction = Vector3(cos(angle), 0.0, sin(angle)).normalized()
		if console_debug_enabled:
			print(
				"[AIDrone] hit name=%s team=%s effect=%s damage=%.1f -> evade %.1fs lateral=(%s)" % [
					name,
					team_id,
					effect,
					strength,
					evasion_seconds,
					_format_debug_vector(evasion_direction),
				]
			)
	if applied and current_hp <= 0.0:
		_emit_destroyed_once()
	return applied


func _emit_destroyed_once() -> void:
	if destroyed_emitted:
		return
	destroyed_emitted = true
	destroyed.emit()


func get_network_state() -> Dictionary:
	return {
		"ai_drone_id": str(get_meta("network_ai_drone_id", get_path())),
		"team": team_id,
		"position": global_position,
		"yaw": rotation.y,
		"velocity": velocity,
		"hp": current_hp,
		"attack_mode": int(attack_mode),
		"evasion_remaining": evasion_remaining,
	}


func apply_network_state(data: Dictionary) -> void:
	var position_value: Variant = data.get("position", global_position)
	if position_value is Vector3:
		global_position = global_position.lerp(position_value as Vector3, 0.55)
	rotation.y = lerp_angle(rotation.y, float(data.get("yaw", rotation.y)), 0.55)
	var velocity_value: Variant = data.get("velocity", velocity)
	if velocity_value is Vector3:
		velocity = velocity_value as Vector3
	current_hp = maxf(0.0, float(data.get("hp", current_hp)))
	attack_mode = int(data.get("attack_mode", attack_mode))
	evasion_remaining = maxf(0.0, float(data.get("evasion_remaining", evasion_remaining)))
	_update_health_label()
