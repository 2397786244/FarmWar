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
@export var evasion_altitude := 20.0
@export var player_hunt_seconds := 14.0
@export var farm_bombard_seconds := 14.0
@export var farm_bomb_interval := 2.0

var target_player: CharacterBody3D
var target_refresh_timer := 0.0
var destroyed_emitted := false
var signal_lost_emitted := false
var ai_controller: Node3D
var operator_defensive_hold := false
var evasion_remaining := 0.0
var evasion_target_height := 0.0
var attack_mode := AttackMode.HUNT_PLAYERS
var phase_remaining := 0.0
var farm_bomb_timer := 0.0
var farm_bomb_target := Vector3.INF


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
	if operator_defensive_hold:
		return "防御悬停"
	if evasion_remaining > 0.0:
		return "受击规避 %.1fs" % evasion_remaining
	if not is_instance_valid(ai_controller):
		return "控制端丢失"
	var signal_percent := roundi(get_effective_signal_strength(ai_controller) * 100.0)
	if not has_attack_link():
		return "弱信号悬停 %d%%" % signal_percent
	var mode_text := "猎杀玩家" if attack_mode == AttackMode.HUNT_PLAYERS else "轰炸农田"
	return "%s %.1fs  信号 %d%%" % [mode_text, phase_remaining, signal_percent]


func _physics_process(delta: float) -> void:
	if destroyed_emitted:
		return
	# AI 不读取遥控输入，但保持与 NormalDrone 一致的电子状态与旋翼更新。
	if _bomb_cooldown_left > 0.0:
		_bomb_cooldown_left = maxf(0.0, _bomb_cooldown_left - delta)
	_tick_electronic_status(delta)
	_update_health_label()
	if is_electronics_disabled():
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	if operator_defensive_hold:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	if not is_instance_valid(ai_controller):
		_emit_signal_lost_once()
		return
	if not has_attack_link():
		# Weak signal is recoverable. Hover in place while the Assistant closes the gap.
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
		move_and_slide()
		return
	if evasion_remaining > 0.0:
		_update_evasion(delta)
		return
	_update_rotors(delta)
	match attack_mode:
		AttackMode.HUNT_PLAYERS:
			_update_player_hunt(delta)
		AttackMode.BOMBARD_ENEMY_FARM:
			_update_farm_bombardment(delta)


func _update_player_hunt(delta: float) -> void:
	target_refresh_timer = maxf(0.0, target_refresh_timer - delta)
	if target_refresh_timer <= 0.0:
		target_refresh_timer = target_refresh_interval
		target_player = _find_visible_enemy_player()
	if not is_instance_valid(target_player):
		# 无人机始终朝敌方农场推进；进入攻击范围的玩家会优先被锁定。
		_fly_toward(_get_enemy_farm_position(), false, cruise_altitude)
		return
	phase_remaining += delta
	_fly_toward(target_player.global_position + Vector3.UP * 1.2, true, bombing_altitude)
	if phase_remaining >= player_hunt_seconds:
		attack_mode = AttackMode.BOMBARD_ENEMY_FARM
		phase_remaining = 0.0
		farm_bomb_timer = 0.0
		farm_bomb_target = Vector3.INF
		target_player = null


func _update_farm_bombardment(delta: float) -> void:
	phase_remaining += delta
	farm_bomb_timer = maxf(0.0, farm_bomb_timer - delta)
	if farm_bomb_target == Vector3.INF or _horizontal_distance_to(farm_bomb_target) < 3.0:
		farm_bomb_target = _get_enemy_farm_bomb_point()
	var can_bomb := farm_bomb_timer <= 0.0
	_fly_toward(farm_bomb_target + Vector3.UP * 0.5, can_bomb, bombing_altitude)
	if can_bomb and _horizontal_distance_to(farm_bomb_target) <= attack_standoff_distance + 3.0 \
		and _bomb_cooldown_left > 0.0:
		farm_bomb_timer = farm_bomb_interval
		farm_bomb_target = Vector3.INF
	if phase_remaining >= farm_bombard_seconds:
		attack_mode = AttackMode.HUNT_PLAYERS
		phase_remaining = 0.0
		target_refresh_timer = 0.0


func _fly_toward(target_position: Vector3, allow_bomb: bool, desired_altitude: float) -> void:
	if target_position == Vector3.INF:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * get_physics_process_delta_time())
		move_and_slide()
		return
	var horizontal := target_position - global_position
	horizontal.y = 0.0
	var distance := horizontal.length()
	if distance > attack_standoff_distance:
		velocity = horizontal.normalized() * ai_move_speed
	else:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * get_physics_process_delta_time())
	velocity.y = clampf((desired_altitude - global_position.y) * 4.0, -ascend_speed, ascend_speed)
	look_at(target_position, Vector3.UP)
	move_and_slide()
	if allow_bomb and distance <= attack_standoff_distance + 3.0 and _bomb_cooldown_left <= 0.0:
		_drop_bomb()


func _get_enemy_farm_position() -> Vector3:
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return Vector3.INF
	var farm_name := "RedFarm" if team_id == "blue" else "BlueFarm"
	var farm := game_world.get_node_or_null(farm_name) as Node3D
	return farm.global_position if farm != null else Vector3.INF


func _get_enemy_farm_bomb_point() -> Vector3:
	var enemy_team := "red" if team_id == "blue" else "blue"
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null and manager.has_method("get_team_plots"):
		var value: Variant = manager.call("get_team_plots", enemy_team)
		if value is Array and not (value as Array).is_empty():
			var plots := value as Array
			var selected := plots[randi() % plots.size()] as Node3D
			if is_instance_valid(selected):
				return selected.global_position
	var fallback := _get_enemy_farm_position()
	if fallback != Vector3.INF:
		return fallback + Vector3(randf_range(-18.0, 18.0), 0.0, randf_range(-12.0, 12.0))
	return fallback


func _horizontal_distance_to(target_position: Vector3) -> float:
	var offset := target_position - global_position
	offset.y = 0.0
	return offset.length()


func _emit_signal_lost_once() -> void:
	if signal_lost_emitted:
		return
	signal_lost_emitted = true
	target_player = null
	velocity = Vector3.ZERO
	signal_link_lost.emit()


func _update_evasion(delta: float) -> void:
	evasion_remaining = maxf(0.0, evasion_remaining - delta)
	target_player = null
	if global_position.y < evasion_target_height - 0.2:
		velocity = Vector3.UP * ai_move_speed
	else:
		velocity = velocity.move_toward(Vector3.ZERO, braking_acceleration * delta)
	move_and_slide()
	if evasion_remaining <= 0.0:
		target_refresh_timer = 0.0


func _find_visible_enemy_player() -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	for group_name in [&"human_players", &"combat_characters"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D or node == ai_controller:
				continue
			var candidate := node as CharacterBody3D
			if candidate.has_method("get_network_state"):
				var network_state := candidate.call("get_network_state") as Dictionary
				if bool(network_state.get("dead", false)):
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
		evasion_remaining = evasion_seconds
		evasion_target_height = maxf(evasion_altitude, global_position.y)
		target_player = null
	if applied and current_hp <= 0.0:
		_emit_destroyed_once()
	return applied


func _emit_destroyed_once() -> void:
	if destroyed_emitted:
		return
	destroyed_emitted = true
	destroyed.emit()
