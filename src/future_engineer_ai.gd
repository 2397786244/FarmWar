extends FutureWarriorAI
class_name FutureEngineerAI

## FutureEngineer 是 FutureWarrior 的工程爆破变体。
## 普通移动、玩家发现、FutureMPX 射击、受伤、死亡和复活继续由父类提供；
## 这里只增加工程师装备限制、战略 target Node3D 和 RemoteBomb 状态流。

enum DemolitionPhase {
	NONE,
	MOVE_TO_TARGET,
	PLANT_EXPLOSIVE,
	RETREAT_FROM_EXPLOSIVE,
	MOVE_TO_ENTRY,
}


const REMOTE_BOMB_SCENE := preload("res://items/RemoteBomb.tscn")
const DEMOLITION_TARGET_GROUP := "ai_demolition_target"
const ENGINEER_WEAPON_ID := "future_mpx"
const ENGINEER_WEAPON_SCENE := "res://character/weapons/FutureMPX.tscn"


@export_category("Engineer Loadout")

@export_range(0, 10, 1)
var starting_explosive_count := 10

@export_range(0, 10, 1)
var max_explosive_count := 10

@export var remote_bomb_damage := 3000.0
@export var remote_bomb_radius := 8.0
## 放置者自身不接收自己的撤退广播，因此也使用同样的 10m 安全距离。
@export var remote_bomb_safe_distance := 10.0
@export var remote_bomb_hp := 50.0
## Engineer 自身撤退被墙体或队员挡住时，先执行随机方向脱困。
@export var remote_bomb_retreat_stuck_after_seconds := 1.5
@export var remote_bomb_retreat_escape_duration := 3.0
@export var remote_bomb_retreat_min_progress := 0.12


@export_category("Engineer Demolition")

@export var demolition_detection_distance := 3.0
@export var demolition_plant_distance := 1.15
@export var demolition_bomb_offset := 0.48
@export var demolition_bomb_height_offset := 0.18
@export var demolition_speed_multiplier := 0.92
@export var demolition_entry_arrival_distance := 0.8


@export_category("Engineer Debug")

## 这是命令行日志开关，不依赖 Godot 编辑器调试面板。
@export var console_debug_enabled := true
@export_range(0.2, 10.0, 0.1)
var console_debug_interval := 1.0


var demolition_phase := DemolitionPhase.NONE
var demolition_target: Node3D
var demolition_position := INVALID_POSITION
var demolition_surface_normal := Vector3.UP
## 炸药成功引爆后，Engineer 必须先走到这个入口点确认通路。
var demolition_entry_position := INVALID_POSITION

var active_remote_bomb: RemoteBomb
var explosives_remaining := 10
## 当前频道内的 canonical 爆破任务；自主发现也会占用一个内部任务。
var squad_demolition_request_id := ""

var _fallback_target: Node3D
var _console_debug_timer := 0.0
var _last_demolition_detection_log := ""
var _remote_bomb_retreat_anchor := INVALID_POSITION
var _remote_bomb_retreat_no_progress_elapsed := 0.0
var _remote_bomb_retreat_escape_direction := Vector3.ZERO
var _remote_bomb_retreat_escape_timer := 0.0


func _ready() -> void:
	## 父类仍然负责创建运行时节点和外观；工程师只保留 FutureMPX。
	starting_grenade_count = 0
	ar15_tool_id = ENGINEER_WEAPON_ID
	ar15_scene_path = ENGINEER_WEAPON_SCENE
	suppressed_pistol_tool_id = ""
	grenade_tool_id = ""
	super._ready()
	explosives_remaining = clampi(
		starting_explosive_count,
		0,
		maxi(0, max_explosive_count)
	)
	_update_health_label()


## FutureWarrior 的父类钩子。返回 true 时，工程师接管本帧移动。
func _update_role_specific_behavior(delta: float) -> bool:
	_ensure_strategic_target()
	_emit_console_debug(delta)

	if state == AIState.DEAD:
		return true

	## 成功爆破后的入口确认优先级高于普通 target 推进。
	if demolition_phase == DemolitionPhase.MOVE_TO_ENTRY:
		_update_move_to_demolition_entry(delta)
		return true

	if demolition_phase == DemolitionPhase.RETREAT_FROM_EXPLOSIVE:
		_update_retreat_from_explosive(delta)
		return true

	if not _is_valid_demolition_target(demolition_target):
		if demolition_phase != DemolitionPhase.NONE:
			_clear_demolition_target("target_invalid")
		if explosives_remaining <= 0:
			return false
		if _is_valid_target(target_player):
			return false
		var detected := _detect_forward_demolition_target()
		if detected.is_empty():
			return false
		_assign_self_detected_demolition(detected)

	if demolition_phase == DemolitionPhase.NONE:
		return false

	match demolition_phase:
		DemolitionPhase.MOVE_TO_TARGET:
			_update_move_to_demolition_target(delta)
		DemolitionPhase.PLANT_EXPLOSIVE:
			_update_plant_explosive(delta)
		DemolitionPhase.RETREAT_FROM_EXPLOSIVE:
			_update_retreat_from_explosive(delta)

	return true


func _squad_stuck_tracking_allowed() -> bool:
	## 安装炸药、携带已安装炸药撤退和自身入口确认必须保持原有优先级，
	## 不能被普通 Squad 随机脱困动作打断。
	return (
		not is_instance_valid(active_remote_bomb)
		and demolition_phase not in [
			DemolitionPhase.PLANT_EXPLOSIVE,
			DemolitionPhase.RETREAT_FROM_EXPLOSIVE,
			DemolitionPhase.MOVE_TO_ENTRY,
		]
	)


func _squad_warning_can_override_role_behavior() -> bool:
	## 自己的 RemoteBomb 已经放下后，必须先撤到 10m 并引爆；
	## 其他 Engineer 的警告在自己的炸弹处理完成后再消费。
	return not is_instance_valid(active_remote_bomb)


# ------------------------------------------------------------------
# Equipment restrictions
# ------------------------------------------------------------------

func _load_starting_loadout() -> void:
	weapon_data.clear()
	weapon_data[WeaponSlot.AR15] = _load_item_data(
		ENGINEER_WEAPON_ID,
		ENGINEER_WEAPON_SCENE,
		ar15_grip_position,
		ar15_grip_rotation,
		ar15_grip_scale,
		ar15_fire_interval
	)
	## Engineer 不加载副武器和手雷数据，避免父类的普通敌人装备回退逻辑。
	weapon_data.erase(WeaponSlot.SUPPRESSED_PISTOL)
	grenade_data.clear()
	grenades_remaining = 0


func _equip_weapon(slot: int) -> bool:
	if slot != WeaponSlot.AR15:
		return false
	return super._equip_weapon(slot)


func _try_fire_at_target(distance: float) -> void:
	if not _is_valid_target(target_player):
		return
	if distance < ar15_min_range or distance > ar15_max_range:
		return
	## Engineer 没有副武器；FutureMPX 空仓后直接按玩家同配置执行换弹。
	if not _weapon_has_loaded_rounds(WeaponSlot.AR15):
		_start_weapon_reload(WeaponSlot.AR15)
		return
	_try_fire_weapon(WeaponSlot.AR15)


func _try_throw_grenade(_distance: float) -> void:
	## 工程师没有手雷，显式覆盖父类投掷入口。
	return


func _update_flee_state() -> Vector3:
	## 父类负责撤退航点；工程师撤退时仍然使用 FutureMPX 自卫。
	var direction := super._update_flee_state()
	if _is_valid_target(target_player):
		var distance := _horizontal_distance(global_position, target_player.global_position)
		if distance <= ar15_max_range and _has_clear_line_to(target_player):
			_aim_at(_get_predicted_aim_position(target_player))
			## FLEE 阶段也必须沿用 FutureMPX 的弹匣状态；空仓时启动换弹，
			## 不能只调用 emit 尝试而永久保持空仓。
			if _weapon_has_loaded_rounds(WeaponSlot.AR15):
				_try_fire_weapon(WeaponSlot.AR15)
			else:
				_start_weapon_reload(WeaponSlot.AR15)
	return direction


func _update_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = show_health_label and state != AIState.DEAD
	health_label.text = "Future Engineer  %d / %d\nFutureMPX %d/%d · Explosive %d / %d\n状态: %s\n困住状态: %s\n最近消息: %s" % [
		roundi(current_hp),
		roundi(max_hp),
		_weapon_ammo_in_mag(WeaponSlot.AR15),
		_weapon_reserve_ammo(WeaponSlot.AR15),
		explosives_remaining,
		max_explosive_count,
		_status_label_text(),
		_squad_stuck_label_text(),
		_last_squad_message_label(),
	]
	var ratio := clampf(current_hp / maxf(max_hp, 0.001), 0.0, 1.0)
	health_label.modulate = Color(
		lerpf(1.0, 0.35, ratio),
		lerpf(0.30, 1.0, ratio),
		0.35,
		1.0
	)


# ------------------------------------------------------------------
# Strategic target
# ------------------------------------------------------------------

## Squad 以后可以直接调用这个入口改变工程师的战略目标。
## target 始终是 Node3D；传入 null 时下一帧重新选择敌方出生点。
func set_strategic_target(value: Node3D) -> void:
	if is_instance_valid(_fallback_target) and _fallback_target != value:
		_fallback_target.queue_free()
		_fallback_target = null
	target = value
	_debug_engineer("strategic target changed to %s" % _target_name(value))


func set_target(value: Node3D) -> void:
	set_strategic_target(value)


func get_strategic_target() -> Node3D:
	return target if is_instance_valid(target) else null


func _ensure_strategic_target() -> void:
	if is_instance_valid(target):
		if is_instance_valid(_fallback_target) and target != _fallback_target:
			_fallback_target.queue_free()
			_fallback_target = null
		return

	var game_world := _get_game_world()
	if not is_instance_valid(game_world):
		return

	var spawn_position := INVALID_POSITION
	if game_world.has_method("get_random_enemy_spawn_position"):
		var value: Variant = game_world.call(
			"get_random_enemy_spawn_position",
			team_id,
			get_instance_id() + int(Time.get_ticks_msec() / 1000.0),
			0
		)
		if value is Vector3:
			spawn_position = value as Vector3

	if spawn_position == INVALID_POSITION:
		return

	var fallback := Node3D.new()
	fallback.name = "%s_Target_EnemySpawn" % name
	fallback.set_meta("future_engineer_target_source", "enemy_spawn")
	fallback.set_meta("future_engineer_target_owner", get_instance_id())
	game_world.add_child(fallback)
	fallback.global_position = spawn_position
	_fallback_target = fallback
	target = fallback
	_debug_engineer(
		"target fallback selected enemy_spawn position=%s" % _format_position(spawn_position)
	)


# ------------------------------------------------------------------
# Demolition target discovery and assignment
# ------------------------------------------------------------------

func assign_demolition_target(
	value: Node3D,
	hit_position := INVALID_POSITION,
	hit_normal := Vector3.UP
) -> bool:
	if not is_available_for_demolition():
		return false
	var resolved := _resolve_demolition_target_root(value)
	if not _is_valid_demolition_target(resolved):
		return false
	demolition_target = resolved
	demolition_entry_position = INVALID_POSITION
	demolition_surface_normal = hit_normal.normalized() if hit_normal.length_squared() > 0.001 else Vector3.UP
	if hit_position != INVALID_POSITION:
		demolition_position = _make_demolition_position(hit_position, demolition_surface_normal)
	else:
		demolition_position = _resolve_demolition_position(resolved)
	demolition_phase = DemolitionPhase.MOVE_TO_TARGET
	_debug_engineer(
		"demolition assigned target=%s position=%s explosives=%d" % [
			_target_name(demolition_target),
			_format_position(demolition_position),
			explosives_remaining,
		]
	)
	return true


func is_available_for_demolition() -> bool:
	return (
		state != AIState.DEAD
		and explosives_remaining > 0
		and demolition_phase == DemolitionPhase.NONE
		and not is_instance_valid(demolition_target)
		and not is_instance_valid(active_remote_bomb)
		and demolition_entry_position == INVALID_POSITION
	)


func set_squad(value: Node) -> void:
	super.set_squad(value)


func _uses_squad_demolition_requests() -> bool:
	## Engineer 自主发现障碍时直接在频道中占用任务，不广播“这里需要爆破”。
	return false


func _can_accept_squad_support() -> bool:
	return is_available_for_demolition() and super._can_accept_squad_support()


func accept_squad_demolition_task(request_id: String, task: Dictionary) -> bool:
	if not is_available_for_demolition():
		return false
	squad_demolition_request_id = request_id
	var accepted := assign_demolition_target(
		task.get("target") as Node3D,
		task.get("position", INVALID_POSITION),
		task.get("normal", Vector3.UP)
	)
	if not accepted:
		_release_squad_demolition_task("assignment_failed")
	return accepted


func _assign_self_detected_demolition(detected: Dictionary) -> bool:
	var obstacle := detected.get("target") as Node3D
	var position: Vector3 = detected.get("position", INVALID_POSITION)
	var normal: Vector3 = detected.get("normal", Vector3.UP)
	if not is_instance_valid(squad_communicator) or not is_instance_valid(squad_communicator.channel):
		return assign_demolition_target(obstacle, position, normal)
	var result: Dictionary = squad_communicator.channel.reserve_self_detected_demolition(
		squad_member_id,
		obstacle,
		position,
		normal
	)
	if not bool(result.get("accepted", false)):
		return false
	squad_demolition_request_id = str(result.get("request_id", ""))
	var task: Dictionary = result.get("task", {})
	var accepted := assign_demolition_target(
		task.get("target") as Node3D,
		task.get("position", position),
		task.get("normal", normal)
	)
	if not accepted:
		_release_squad_demolition_task("self_assignment_failed")
	return accepted


func _detect_forward_demolition_target() -> Dictionary:
	if not is_instance_valid(target) or demolition_detection_distance <= 0.0:
		return {}
	if state not in [AIState.SEARCH, AIState.CHASE]:
		return {}
	var route_direction := _direction_to_goal(target.global_position)
	if route_direction.length_squared() <= 0.001:
		return {}
	var origin := global_position + Vector3.UP * 0.82
	var destination := origin + route_direction.normalized() * demolition_detection_distance
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		destination,
		body_collision_mask,
		[get_rid()]
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.hit_from_inside = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var root := _resolve_demolition_target_root(hit.get("collider") as Node3D)
	if not _is_valid_demolition_target(root):
		return {}
	var hit_position: Variant = hit.get("position", destination)
	var hit_normal: Variant = hit.get("normal", Vector3.UP)
	var key := "%s:%s" % [_target_name(root), _format_position(hit_position as Vector3)]
	if key != _last_demolition_detection_log:
		_last_demolition_detection_log = key
		_debug_engineer("forward demolition obstacle=%s hit=%s" % [
			_target_name(root), _format_position(hit_position as Vector3)
		])
	return {
		"target": root,
		"position": hit_position as Vector3,
		"normal": hit_normal as Vector3,
	}


func _resolve_demolition_target_root(value: Node3D) -> Node3D:
	var cursor: Node = value
	var depth := 0
	while cursor != null and depth < 16:
		if cursor.is_in_group(DEMOLITION_TARGET_GROUP):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


func _is_valid_demolition_target(value: Node3D) -> bool:
	if not is_instance_valid(value) or value.is_queued_for_deletion():
		return false
	if not value.is_in_group(DEMOLITION_TARGET_GROUP):
		return false
	if _has_property(value, "destroyed") and bool(value.get("destroyed")):
		return false
	if _has_property(value, "is_open") and bool(value.get("is_open")):
		return false
	if _has_property(value, "active") and not bool(value.get("active")):
		return false
	return true


func _resolve_demolition_position(value: Node3D) -> Vector3:
	if value.has_method("get_demolition_position"):
		var provided: Variant = value.call("get_demolition_position")
		if provided is Vector3 and provided != INVALID_POSITION:
			return provided as Vector3
	var marker := value.get_node_or_null("DemolitionPoint") as Node3D
	if is_instance_valid(marker):
		return marker.global_position
	var away_from_target := _horizontal_direction(value.global_position, global_position)
	if away_from_target.length_squared() <= 0.001:
		away_from_target = -global_transform.basis.z
	return value.global_position + away_from_target.normalized() * demolition_bomb_offset + Vector3.UP * demolition_bomb_height_offset


func _make_demolition_position(hit_position: Vector3, hit_normal: Vector3) -> Vector3:
	var normal := hit_normal.normalized()
	if normal.length_squared() <= 0.001:
		normal = _horizontal_direction(demolition_target.global_position, global_position)
	if normal.length_squared() <= 0.001:
		normal = -global_transform.basis.z
	var result := hit_position + normal.normalized() * demolition_bomb_offset
	result.y += demolition_bomb_height_offset
	return result


func _clear_demolition_target(reason: String) -> void:
	if demolition_phase != DemolitionPhase.NONE or is_instance_valid(demolition_target):
		_debug_engineer("demolition cleared reason=%s target=%s" % [reason, _target_name(demolition_target)])
	demolition_phase = DemolitionPhase.NONE
	demolition_target = null
	demolition_position = INVALID_POSITION
	demolition_surface_normal = Vector3.UP
	_release_squad_demolition_task(reason)


func _queue_demolition_entry(position: Vector3) -> void:
	if position == INVALID_POSITION:
		_clear_demolition_target("entry_position_invalid")
		return

	## 爆破点取炸药的实际引爆位置；保留水平位置，随后用直接方向确认入口。
	demolition_entry_position = position
	demolition_target = null
	demolition_position = INVALID_POSITION
	demolition_surface_normal = Vector3.UP
	demolition_phase = DemolitionPhase.MOVE_TO_ENTRY
	navigation_refresh_timer = 0.0
	_debug_engineer(
		"demolition entry queued position=%s; confirm before target advance"
		% _format_position(demolition_entry_position)
	)


func _clear_demolition_entry(reason: String) -> void:
	var completed_position := demolition_entry_position
	if demolition_entry_position != INVALID_POSITION:
		_debug_engineer(
			"demolition entry cleared reason=%s position=%s"
			% [reason, _format_position(demolition_entry_position)]
		)
	if reason in ["entry_confirmed", "blocked_by_new_obstacle"]:
		_complete_squad_demolition_task(completed_position)
	else:
		_release_squad_demolition_task(reason)
	demolition_entry_position = INVALID_POSITION
	if demolition_phase == DemolitionPhase.MOVE_TO_ENTRY:
		demolition_phase = DemolitionPhase.NONE
	navigation_refresh_timer = 0.0


func _release_squad_demolition_task(reason: String) -> void:
	if squad_demolition_request_id.is_empty():
		return
	if is_instance_valid(squad_communicator) and is_instance_valid(squad_communicator.channel):
		squad_communicator.channel.release_demolition(
			squad_demolition_request_id,
			squad_member_id,
			reason
		)
	squad_demolition_request_id = ""


func _complete_squad_demolition_task(entry_position: Vector3) -> void:
	if squad_demolition_request_id.is_empty():
		return
	if is_instance_valid(squad) and squad.has_method("report_entry_found"):
		squad.report_entry_found(self, entry_position)
	elif is_instance_valid(squad_communicator) and is_instance_valid(squad_communicator.channel):
		squad_communicator.channel.complete_demolition(
			squad_demolition_request_id,
			squad_member_id,
			entry_position
		)
	squad_demolition_request_id = ""


# ------------------------------------------------------------------
# Demolition state flow
# ------------------------------------------------------------------

func _update_move_to_demolition_target(delta: float) -> void:
	if not _is_valid_demolition_target(demolition_target):
		_clear_demolition_target("target_destroyed_before_plant")
		return
	if explosives_remaining <= 0:
		_clear_demolition_target("explosives_empty")
		return
	if demolition_position == INVALID_POSITION:
		demolition_position = _resolve_demolition_position(demolition_target)
	var distance := _horizontal_distance(global_position, demolition_position)
	_perform_demolition_combat()
	if distance <= demolition_plant_distance:
		demolition_phase = DemolitionPhase.PLANT_EXPLOSIVE
		_apply_character_movement(Vector3.ZERO, 0.0, delta)
		return
	var direction := _direction_to_goal(demolition_position)
	_apply_character_movement(direction, chase_speed * demolition_speed_multiplier, delta)


func _update_move_to_demolition_entry(delta: float) -> void:
	if demolition_entry_position == INVALID_POSITION:
		_clear_demolition_entry("entry_position_missing")
		return

	## 新障碍可能在爆破后被敌对玩家补放到入口处；有炸药时立即转回同一套爆破流程。
	if explosives_remaining > 0:
		var detected := _detect_forward_demolition_target()
		if not detected.is_empty():
			_debug_engineer(
				"demolition entry blocked by %s; reassign demolition"
				% _target_name(detected.get("target") as Node3D)
			)
			var entry_position := demolition_entry_position
			_clear_demolition_entry("blocked_by_new_obstacle")
			_assign_self_detected_demolition({
				"target": detected.get("target") as Node3D,
				"position": detected.get("position", entry_position) as Vector3,
				"normal": detected.get("normal", Vector3.UP) as Vector3,
			})
			return

	var distance := _horizontal_distance(global_position, demolition_entry_position)
	if distance <= demolition_entry_arrival_distance:
		_clear_demolition_entry("entry_confirmed")
		return

	## 这里故意不使用 NavigationAgent3D 的 next path position：
	## 爆破后需要先确认真实碰撞入口，而不是沿旧的绕行路径继续走。
	var direction := _horizontal_direction(global_position, demolition_entry_position)
	_perform_demolition_combat()
	_apply_character_movement(direction, chase_speed, delta)


func _update_plant_explosive(delta: float) -> void:
	_apply_character_movement(Vector3.ZERO, 0.0, delta)
	if _is_grenade_avoidance_active():
		## 手雷靠近时暂停安装；共享移动覆盖层会让 Engineer 离开手雷，
		## 同时保留原来的目标、状态和 FutureMPX 反击能力。
		_perform_demolition_combat()
		return
	if not _is_valid_demolition_target(demolition_target):
		_clear_demolition_target("target_destroyed_before_plant")
		return
	if explosives_remaining <= 0:
		_clear_demolition_target("explosives_empty")
		return
	if active_remote_bomb == null:
		_plant_remote_bomb()
	if active_remote_bomb != null:
		demolition_phase = DemolitionPhase.RETREAT_FROM_EXPLOSIVE


func _update_retreat_from_explosive(delta: float) -> void:
	if not is_instance_valid(active_remote_bomb):
		active_remote_bomb = null
		_reset_remote_bomb_retreat_tracking()
		if _is_valid_demolition_target(demolition_target) and explosives_remaining > 0:
			demolition_phase = DemolitionPhase.MOVE_TO_TARGET
		else:
			_clear_demolition_target("bomb_destroyed_or_target_invalid")
		return
	var bomb_position := active_remote_bomb.global_position
	var distance := _horizontal_distance(global_position, bomb_position)
	if distance >= remote_bomb_safe_distance:
		if _is_grenade_avoidance_active():
			## 自身炸弹已经达到 10m，但活动手雷仍要求同时规避；
			## 等手雷安全保持完成后再引爆，避免 Engineer 回到炸弹旁。
			_perform_demolition_combat()
			_apply_character_movement(Vector3.ZERO, flee_speed, delta)
			return
		_reset_remote_bomb_retreat_tracking()
		_detonate_remote_bomb()
		return
	var away := _horizontal_direction(bomb_position, global_position)
	if away.length_squared() <= 0.001:
		away = -global_transform.basis.z
	var retreat_direction := away
	var bypass_avoidance := false
	if _remote_bomb_retreat_escape_timer > 0.0:
		_remote_bomb_retreat_escape_timer = maxf(
			0.0,
			_remote_bomb_retreat_escape_timer - delta
		)
		retreat_direction = _remote_bomb_retreat_escape_direction
		bypass_avoidance = true
	else:
		## 自身炸药的安全撤退不能被同队 RVO 速度限制卡住；碰撞体仍然
		## 保留，_avoid_immediate_obstacle 会在墙前选择侧向/跳跃方向。
		retreat_direction = _find_open_movement_direction(away)
		retreat_direction = _avoid_immediate_obstacle(retreat_direction)
	if _movement_direction_is_blocked(retreat_direction, 0.8):
		_try_jump_over_obstacle()
	var previous_distance := _horizontal_distance(global_position, bomb_position)
	_apply_character_movement(
		retreat_direction,
		flee_speed,
		delta,
		not bypass_avoidance or _is_grenade_avoidance_active()
	)
	var progress := _horizontal_distance(global_position, bomb_position) - previous_distance
	if progress >= remote_bomb_retreat_min_progress:
		_remote_bomb_retreat_anchor = global_position
		_remote_bomb_retreat_no_progress_elapsed = 0.0
	elif _remote_bomb_retreat_escape_timer <= 0.0:
		_remote_bomb_retreat_no_progress_elapsed += delta
		if _remote_bomb_retreat_no_progress_elapsed >= remote_bomb_retreat_stuck_after_seconds:
			_start_remote_bomb_retreat_escape(away)


func _start_remote_bomb_retreat_escape(away: Vector3) -> void:
	var direction := away
	direction.y = 0.0
	if direction.length_squared() <= 0.01:
		direction = -global_transform.basis.z
	if direction.length_squared() <= 0.01:
		direction = Vector3.FORWARD
	direction = direction.normalized().rotated(
		Vector3.UP,
		rng.randf_range(-PI * 0.8, PI * 0.8)
	).normalized()
	direction = _find_open_movement_direction(direction)
	_remote_bomb_retreat_escape_direction = direction
	_remote_bomb_retreat_escape_timer = maxf(0.5, remote_bomb_retreat_escape_duration)
	_remote_bomb_retreat_no_progress_elapsed = 0.0
	_debug_engineer(
		"bomb retreat escape started direction=%s duration=%.1fs"
		% [_format_position(direction), _remote_bomb_retreat_escape_timer]
	)


func _reset_remote_bomb_retreat_tracking() -> void:
	_remote_bomb_retreat_anchor = INVALID_POSITION
	_remote_bomb_retreat_no_progress_elapsed = 0.0
	_remote_bomb_retreat_escape_direction = Vector3.ZERO
	_remote_bomb_retreat_escape_timer = 0.0


func _perform_demolition_combat() -> void:
	if not _is_valid_target(target_player):
		return
	var distance := _horizontal_distance(global_position, target_player.global_position)
	if not _has_clear_line_to(target_player):
		return
	_aim_at(_get_predicted_aim_position(target_player))
	_try_fire_at_target(distance)


func _get_additional_movement_hazard_direction() -> Vector3:
	if not is_instance_valid(active_remote_bomb):
		return Vector3.ZERO
	var distance := _horizontal_distance(global_position, active_remote_bomb.global_position)
	if distance >= remote_bomb_safe_distance:
		return Vector3.ZERO
	var away := _horizontal_direction(active_remote_bomb.global_position, global_position)
	if away.length_squared() <= 0.001:
		away = -global_transform.basis.z
	return away.normalized()


func _plant_remote_bomb() -> void:
	if active_remote_bomb != null or explosives_remaining <= 0:
		return
	var game_world := _get_game_world()
	var world: Node = game_world if is_instance_valid(game_world) else get_tree().current_scene
	if not is_instance_valid(world):
		return
	var bomb := REMOTE_BOMB_SCENE.instantiate() as RemoteBomb
	if bomb == null:
		push_error("[FutureEngineer] Cannot instantiate RemoteBomb.")
		return
	world.add_child(bomb)
	bomb.global_position = demolition_position if demolition_position != INVALID_POSITION else global_position
	bomb.setup(self, team_id, remote_bomb_hp)
	if not bomb.destroyed.is_connected(_on_remote_bomb_destroyed):
		bomb.destroyed.connect(_on_remote_bomb_destroyed)
	active_remote_bomb = bomb
	explosives_remaining = maxi(0, explosives_remaining - 1)
	_remote_bomb_retreat_anchor = global_position
	_remote_bomb_retreat_no_progress_elapsed = 0.0
	_remote_bomb_retreat_escape_direction = Vector3.ZERO
	_remote_bomb_retreat_escape_timer = 0.0
	_update_health_label()
	_debug_engineer("bomb planted position=%s remaining=%d; retreat %.1fm" % [
		_format_position(bomb.global_position),
		explosives_remaining, remote_bomb_safe_distance,
	])
	if not squad_demolition_request_id.is_empty():
		if is_instance_valid(squad) and squad.has_method("report_demolition_warning"):
			squad.report_demolition_warning(self, bomb.global_position, remote_bomb_safe_distance)
		elif is_instance_valid(squad_communicator):
			send_squad_message(
				SquadMessageTypes.Type.DEMOLITION_WARNING,
				{"position": bomb.global_position, "radius": remote_bomb_safe_distance},
				squad_demolition_request_id
			)


func _detonate_remote_bomb() -> void:
	if not is_instance_valid(active_remote_bomb):
		active_remote_bomb = null
		_reset_remote_bomb_retreat_tracking()
		return
	var bomb := active_remote_bomb
	var explosion_position := bomb.global_position
	active_remote_bomb = null
	_reset_remote_bomb_retreat_tracking()
	bomb.consume_for_detonation()
	var exploded := false
	var authority := _get_authority()
	if authority != null and authority.has_method("detonate_engineer_remote_bomb"):
		exploded = bool(authority.call(
			"detonate_engineer_remote_bomb",
			explosion_position,
			team_id,
			remote_bomb_damage,
			remote_bomb_radius,
			get_instance_id(),
		))
	_debug_engineer("bomb detonated position=%s authority_result=%s" % [
		_format_position(explosion_position), exploded
	])
	if exploded:
		## 炸药没有被摧毁且权威爆炸成功：先把实际爆破点作为入口确认点。
		_queue_demolition_entry(explosion_position)
	elif _is_valid_demolition_target(demolition_target) and explosives_remaining > 0:
		demolition_phase = DemolitionPhase.MOVE_TO_TARGET
	else:
		_clear_demolition_target("explosion_complete")


func _on_remote_bomb_destroyed(bomb: Node3D) -> void:
	if bomb != active_remote_bomb:
		return
	active_remote_bomb = null
	_reset_remote_bomb_retreat_tracking()
	_debug_engineer("bomb destroyed before detonation")
	if state == AIState.DEAD:
		return
	if _is_valid_demolition_target(demolition_target) and explosives_remaining > 0:
		demolition_phase = DemolitionPhase.MOVE_TO_TARGET
	else:
		_clear_demolition_target("bomb_destroyed_no_retry")


# ------------------------------------------------------------------
# Squad and lifecycle
# ------------------------------------------------------------------

func _die(attacker_team: String, effect: String) -> void:
	if is_instance_valid(active_remote_bomb):
		active_remote_bomb.disarm()
		active_remote_bomb = null
	demolition_phase = DemolitionPhase.NONE
	demolition_target = null
	demolition_entry_position = INVALID_POSITION
	_release_squad_demolition_task("engineer_dead")
	super._die(attacker_team, effect)


func _respawn_at_team_spawn() -> void:
	super._respawn_at_team_spawn()
	explosives_remaining = clampi(max_explosive_count, 0, maxi(0, max_explosive_count))
	demolition_phase = DemolitionPhase.NONE
	demolition_target = null
	demolition_position = INVALID_POSITION
	demolition_entry_position = INVALID_POSITION
	squad_demolition_request_id = ""
	_ensure_strategic_target()
	_update_health_label()
	_debug_engineer("respawned explosives=%d target=%s" % [
		explosives_remaining, _target_name(target)
	])


func get_network_state() -> Dictionary:
	var result := super.get_network_state()
	result["ai_type"] = "futureengineer"
	result["engineer_phase"] = int(demolition_phase)
	result["explosives_remaining"] = explosives_remaining
	result["max_explosives"] = max_explosive_count
	result["target_position"] = target.global_position if is_instance_valid(target) else INVALID_POSITION
	result["demolition_target"] = _target_name(demolition_target)
	result["demolition_entry_position"] = demolition_entry_position
	return result


func apply_network_state(data: Dictionary) -> void:
	super.apply_network_state(data)
	if data.has("engineer_phase"):
		demolition_phase = int(data.get("engineer_phase", demolition_phase))
	if data.has("explosives_remaining"):
		explosives_remaining = int(data.get("explosives_remaining", explosives_remaining))
	if data.has("demolition_entry_position"):
		var entry_value: Variant = data.get("demolition_entry_position", INVALID_POSITION)
		if entry_value is Vector3:
			demolition_entry_position = entry_value as Vector3
	_update_health_label()


# ------------------------------------------------------------------
# Command-line debug output
# ------------------------------------------------------------------

func _emit_console_debug(delta: float) -> void:
	if not console_debug_enabled:
		return
	_console_debug_timer -= delta
	if _console_debug_timer > 0.0:
		return
	_console_debug_timer = maxf(0.2, console_debug_interval)
	var weapon_name := "none"
	if is_instance_valid(held_weapon):
		weapon_name = held_weapon.name
	var player_name := "none"
	if _is_valid_target(target_player):
		player_name = target_player.name
	var route_mode := "direct"
	if use_navigation_agent:
		route_mode = "navigation" if _navigation_map_is_ready() else "direct_fallback"
	print((
		"[FutureEngineer] name=%s team=%s state=%s phase=%s pos=(%s) "
		+ "target=%s target_pos=(%s) target_source=%s "
		+ "route=%s demolition_target=%s entry=(%s) "
		+ "bomb=%d/%d active_bomb=%s player=%s weapon=%s squad_member=%s squad_task=%s"
	) % [
			name,
			team_id,
			_state_name(state),
			_demolition_phase_name(demolition_phase),
			_format_position(global_position),
			_target_name(target),
			_format_position(target.global_position if is_instance_valid(target) else INVALID_POSITION),
			_target_source(),
			route_mode,
			_target_name(demolition_target),
			_format_position(demolition_entry_position),
			explosives_remaining,
			max_explosive_count,
			"yes" if is_instance_valid(active_remote_bomb) else "no",
			player_name,
			weapon_name,
			squad_member_id if not squad_member_id.is_empty() else "none",
			squad_demolition_request_id if not squad_demolition_request_id.is_empty() else "none",
		])


func _debug_engineer(message: String) -> void:
	if console_debug_enabled:
		print("[FutureEngineer] ", message)


func _state_name(value: int) -> String:
	match value:
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


func _status_label_text() -> String:
	var base_state := _state_name(state)
	if demolition_phase == DemolitionPhase.NONE:
		return base_state
	return "%s / %s" % [base_state, _demolition_phase_name(demolition_phase)]


func _demolition_phase_name(value: int) -> String:
	match value:
		DemolitionPhase.NONE:
			return "NONE"
		DemolitionPhase.MOVE_TO_TARGET:
			return "MOVE_TO_DEMOLITION_TARGET"
		DemolitionPhase.PLANT_EXPLOSIVE:
			return "PLANT_EXPLOSIVE"
		DemolitionPhase.RETREAT_FROM_EXPLOSIVE:
			return "RETREAT_FROM_EXPLOSIVE"
		DemolitionPhase.MOVE_TO_ENTRY:
			return "MOVE_TO_ENTRY"
	return "UNKNOWN"


func _target_name(value: Node3D) -> String:
	return value.name if is_instance_valid(value) else "none"


func _target_source() -> String:
	if not is_instance_valid(target):
		return "none"
	return str(target.get_meta("future_engineer_target_source", "configured_or_squad"))


func _format_position(value: Vector3) -> String:
	if value == INVALID_POSITION:
		return "none"
	return "%.1f, %.1f, %.1f" % [value.x, value.y, value.z]


func _get_game_world() -> Node:
	var globals := get_node_or_null("/root/GlobalVar")
	if globals != null:
		var value: Variant = globals.get("gameworld")
		if value is Node and is_instance_valid(value):
			return value as Node
	return null


func _get_authority() -> Node:
	return get_node_or_null("/root/GameAuthority")
