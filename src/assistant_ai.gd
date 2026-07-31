extends CharacterBody3D
class_name AssistantAI

## 蓝方辅助角色：优先部署投弹无人机；无人机失效期间才使用 Nailgun 自卫。

enum OperationState {
	ADVANCE_TO_DEPLOYMENT,
	CONTROLLING_DRONE,
	DEFENSIVE_PATROL,
}

@export var team_id := "blue"
@export var max_hp := 200.0
@export var respawn_seconds := 10.0
@export var drone_respawn_time := 45.0
@export var vision_distance := 50.0
@export var nailgun_cooldown := 0.45
@export var defensive_patrol_radius := 6.0
@export var defensive_patrol_speed := 2.5
@export var advance_speed := 2.6
@export var deployment_advance_distance := 30.0
@export var own_farm_advance_radius := 45.0
@export var navigation_refresh_interval := 0.25
@export_range(0.0, 1.0, 0.01) var signal_advance_threshold := 0.20
@export_range(0.0, 1.0, 0.01) var signal_recover_threshold := 0.60
@export_file("*.tscn") var drone_scene_path := "res://character/AIDevices/AINormalDrone.tscn"
@export_file("*.tscn") var nailgun_scene_path := "res://character/weapons/Nailgun.tscn"

var current_hp := 0.0
var drone: AINormalDrone
var nailgun: Node3D
var target_player: CharacterBody3D
var respawn_timer := 0.0
var fire_timer := 0.0
var is_dead := false
var head: Node3D
var right_hand_socket: BoneAttachment3D
var tool_pivot: Node3D
var aim_marker: Marker3D
var upper_body_look_target: Marker3D
var right_hand_ik_target: Marker3D
var right_elbow_pole: Marker3D
var appearance_player: AnimationPlayer
var skeleton: Skeleton3D
var right_arm_ik: TwoBoneIK3D
var upper_body_look_modifiers: Array[LookAtModifier3D] = []
var upper_body_look_weights: Array[float] = []
var action_animation_locked := false
var patrol_anchor := Vector3.INF
var patrol_destination := Vector3.INF
var patrol_refresh_timer := 0.0
var navigation_agent: NavigationAgent3D
var navigation_refresh_timer := 0.0
var operation_state := OperationState.ADVANCE_TO_DEPLOYMENT
var deployment_origin := Vector3.INF
var deployment_position := Vector3.INF
var knockback_velocity := Vector3.ZERO
var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var debug_label: Label3D
var advancing_for_signal_recovery := false

@onready var hit_3d := get_node_or_null("Hit3D") as Area3D
@onready var body_collision := get_node_or_null("CollisionShape3D") as CollisionShape3D
@onready var hit_collision := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D
@onready var health_label := get_node_or_null("HealthLabel3D") as Label3D


func _ready() -> void:
	current_hp = max_hp
	collision_layer = 8
	collision_mask = 519
	add_to_group("assistant_ai")
	add_to_group("combat_characters")
	_create_hand_mount()
	_load_assistant_appearance()
	_create_nailgun()
	_create_navigation_agent()
	_create_debug_label()
	_update_label()
	_update_debug_label()
	if hit_3d != null:
		if not hit_3d.body_entered.is_connected(_on_hit_3d_body_entered):
			hit_3d.body_entered.connect(_on_hit_3d_body_entered)
		if not hit_3d.area_entered.is_connected(_on_hit_3d_area_entered):
			hit_3d.area_entered.connect(_on_hit_3d_area_entered)
	call_deferred("_initialize_deployment_advance")


func _process(delta: float) -> void:
	if is_dead:
		return
	_update_aim_reference()
	_update_upper_body_aim(delta)
	_update_weapon_alignment()


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	if is_dead:
		respawn_timer = maxf(0.0, respawn_timer - delta)
		if respawn_timer <= 0.0:
			_respawn()
		_update_debug_label()
		return
	match operation_state:
		OperationState.ADVANCE_TO_DEPLOYMENT:
			if deployment_position == Vector3.INF:
				_initialize_deployment_advance()
			if deployment_position != Vector3.INF:
				_move_toward_position(deployment_position, advance_speed, delta)
				if _horizontal_distance_to(deployment_position) <= 1.2:
					operation_state = OperationState.CONTROLLING_DRONE
					_spawn_drone()
		OperationState.CONTROLLING_DRONE:
			if not is_instance_valid(drone):
				_enter_defensive_mode()
			else:
				_update_signal_recovery_state()
				if _is_in_own_farm_area() or advancing_for_signal_recovery:
					# 信号低于 20% 后持续推进，直到恢复到 60% 以上。
					_advance_toward_enemy_farm(delta)
				else:
					_hold_position(delta)
		OperationState.DEFENSIVE_PATROL:
			_defensive_patrol(delta)
	_update_character_animation()
	_update_debug_label()


func _spawn_drone() -> void:
	var scene := load(drone_scene_path) as PackedScene
	if scene == null:
		push_error("[AssistantAI] Cannot load AI drone: %s" % drone_scene_path)
		return
	var spawned := scene.instantiate() as AINormalDrone
	if spawned == null:
		push_error("[AssistantAI] AINormalDrone scene root is invalid.")
		return
	spawned.team_id = team_id
	spawned.tool_owner = team_id
	spawned.set_ai_controller(self)
	GlobalVar.gameworld.add_child(spawned)
	spawned.global_position = global_position + Vector3.UP * spawned.cruise_altitude
	spawned.destroyed.connect(_on_drone_destroyed)
	spawned.signal_link_lost.connect(_on_drone_signal_lost)
	drone = spawned


func _on_drone_destroyed() -> void:
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	respawn_timer = drone_respawn_time
	_enter_defensive_mode()


func _on_drone_signal_lost() -> void:
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	respawn_timer = drone_respawn_time
	_enter_defensive_mode()


func _create_nailgun() -> void:
	var scene := load(nailgun_scene_path) as PackedScene
	if scene == null:
		return
	nailgun = scene.instantiate() as Node3D
	if nailgun == null:
		return
	tool_pivot.add_child(nailgun)
	nailgun.position = Vector3.ZERO
	# 与 tool_definitions.json 的 nail_gun 握持参数保持一致。
	nailgun.rotation_degrees = Vector3(0.0, 180.0, 180.0)
	nailgun.scale = Vector3(0.5, 0.5, 0.5)
	if _has_property(nailgun, "tool_owner"):
		nailgun.set("tool_owner", team_id)


func _search_and_fire(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	target_player = _find_visible_enemy_player()
	if not is_instance_valid(target_player) or fire_timer > 0.0 or nailgun == null:
		return
	look_at(target_player.global_position, Vector3.UP)
	aim_marker.global_position = target_player.global_position + Vector3.UP
	_update_weapon_alignment()
	if nailgun.has_method("emit"):
		nailgun.call("emit")
		if appearance_player != null and appearance_player.has_animation(&"ShootOneHand"):
			action_animation_locked = true
			appearance_player.play(&"ShootOneHand", 0.05)
		fire_timer = nailgun_cooldown


func _defensive_patrol(delta: float) -> void:
	patrol_refresh_timer = maxf(0.0, patrol_refresh_timer - delta)
	if patrol_refresh_timer <= 0.0:
		patrol_refresh_timer = 1.5
		target_player = _find_visible_defensive_threat()
	if is_instance_valid(target_player):
		_hold_position(delta)
		_fire_at_target(delta)
		return
	if is_instance_valid(drone):
		drone.set_operator_defensive_hold(false)
		operation_state = OperationState.CONTROLLING_DRONE
		return
	respawn_timer = maxf(0.0, respawn_timer - delta)
	if respawn_timer <= 0.0:
		operation_state = OperationState.CONTROLLING_DRONE
		_spawn_drone()
		return
	if patrol_anchor == Vector3.INF:
		_capture_patrol_anchor()
	if patrol_destination == Vector3.INF or global_position.distance_to(patrol_destination) < 0.8:
		var angle := randf_range(0.0, TAU)
		patrol_destination = patrol_anchor + Vector3(cos(angle), 0.0, sin(angle)) * randf_range(1.5, defensive_patrol_radius)
	var offset := patrol_destination - global_position
	offset.y = 0.0
	if offset.length_squared() > 0.01:
		_move_with_horizontal_velocity(offset.normalized() * defensive_patrol_speed, delta)
	else:
		_hold_position(delta)


func _enter_defensive_mode() -> void:
	operation_state = OperationState.DEFENSIVE_PATROL
	patrol_anchor = global_position
	patrol_destination = Vector3.INF
	patrol_refresh_timer = 0.0
	if is_instance_valid(drone):
		drone.set_operator_defensive_hold(true)


func _initialize_deployment_advance() -> void:
	var enemy_farm := _get_enemy_farm()
	if enemy_farm == null:
		return
	deployment_origin = global_position
	var direction := enemy_farm.global_position - deployment_origin
	direction.y = 0.0
	if direction.length_squared() <= 0.01:
		return
	deployment_position = deployment_origin + direction.normalized() * deployment_advance_distance
	patrol_anchor = deployment_origin
	patrol_destination = Vector3.INF


func _get_enemy_farm() -> Node3D:
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return null
	var enemy_farm_name := "RedFarm" if team_id == "blue" else "BlueFarm"
	return game_world.get_node_or_null(enemy_farm_name) as Node3D


func _is_in_own_farm_area() -> bool:
	var game_world: Node = GlobalVar.gameworld
	if not is_instance_valid(game_world):
		return false
	var own_farm_name := "BlueFarm" if team_id == "blue" else "RedFarm"
	var own_farm := game_world.get_node_or_null(own_farm_name) as Node3D
	return own_farm != null and _horizontal_distance_to(own_farm.global_position) <= own_farm_advance_radius


func _advance_toward_enemy_farm(delta: float) -> void:
	var enemy_farm := _get_enemy_farm()
	if enemy_farm == null:
		return
	_move_toward_position(enemy_farm.global_position, advance_speed, delta)


func _update_signal_recovery_state() -> void:
	if not is_instance_valid(drone):
		advancing_for_signal_recovery = false
		return
	var signal_strength := drone.get_effective_signal_strength(self)
	if signal_strength < signal_advance_threshold:
		advancing_for_signal_recovery = true
	if advancing_for_signal_recovery:
		if signal_strength >= signal_recover_threshold:
			advancing_for_signal_recovery = false
			drone.set_operator_defensive_hold(false)
		else:
			# 20%-60% is a recovery-only band: do not let the drone resume its
			# hunt/bombard loop until the Assistant has restored a strong link.
			drone.set_operator_defensive_hold(true)
	else:
		drone.set_operator_defensive_hold(false)


func _move_toward_position(goal: Vector3, speed: float, delta: float) -> void:
	var direct_direction := goal - global_position
	direct_direction.y = 0.0
	direct_direction = direct_direction.normalized()
	var movement_direction := direct_direction
	navigation_refresh_timer = maxf(0.0, navigation_refresh_timer - delta)
	if navigation_agent != null and _navigation_map_is_ready():
		if navigation_refresh_timer <= 0.0:
			navigation_agent.target_position = goal
			navigation_refresh_timer = navigation_refresh_interval
		var next_position := navigation_agent.get_next_path_position()
		var routed_direction := next_position - global_position
		routed_direction.y = 0.0
		if routed_direction.length_squared() > 0.001:
			movement_direction = routed_direction.normalized()
	if _horizontal_distance_to(goal) <= 0.5:
		_hold_position(delta)
		return
	_move_with_horizontal_velocity(movement_direction * speed, delta)


func _hold_position(delta: float) -> void:
	_move_with_horizontal_velocity(Vector3.ZERO, delta)


func _move_with_horizontal_velocity(desired: Vector3, delta: float) -> void:
	knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, 18.0 * delta)
	velocity.x = desired.x + knockback_velocity.x
	velocity.z = desired.z + knockback_velocity.z
	if desired.length_squared() > 0.01:
		var facing := Vector3(desired.x, 0.0, desired.z)
		look_at(global_position + facing, Vector3.UP)
	move_and_slide()


func _apply_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = -0.1


func _horizontal_distance_to(position: Vector3) -> float:
	var offset := position - global_position
	offset.y = 0.0
	return offset.length()


func _create_navigation_agent() -> void:
	navigation_agent = get_node_or_null("NavigationAgent3D") as NavigationAgent3D
	if navigation_agent == null:
		navigation_agent = NavigationAgent3D.new()
		navigation_agent.name = "NavigationAgent3D"
		add_child(navigation_agent)
	navigation_agent.radius = 0.34
	navigation_agent.height = 1.7
	navigation_agent.path_desired_distance = 0.55
	navigation_agent.target_desired_distance = 1.0
	navigation_agent.avoidance_enabled = false


func _navigation_map_is_ready() -> bool:
	if navigation_agent == null:
		return false
	var navigation_map := navigation_agent.get_navigation_map()
	return navigation_map.is_valid() and NavigationServer3D.map_get_iteration_id(navigation_map) > 0


func _fire_at_target(delta: float) -> void:
	fire_timer = maxf(0.0, fire_timer - delta)
	if not is_instance_valid(target_player) or fire_timer > 0.0 or nailgun == null:
		return
	look_at(target_player.global_position, Vector3.UP)
	aim_marker.global_position = target_player.global_position + Vector3.UP
	_update_weapon_alignment()
	if nailgun.has_method("emit"):
		nailgun.call("emit")
		if appearance_player != null and appearance_player.has_animation(&"ShootOneHand"):
			action_animation_locked = true
			appearance_player.play(&"ShootOneHand", 0.05)
		fire_timer = nailgun_cooldown


func _capture_patrol_anchor() -> void:
	patrol_anchor = global_position
	patrol_destination = Vector3.INF


func _find_visible_enemy_player() -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("human_players"):
		if not node is CharacterBody3D or _get_combat_team(node as Node) == team_id:
			continue
		var candidate := node as CharacterBody3D
		var distance := global_position.distance_to(candidate.global_position)
		if distance > vision_distance or not _has_line_of_sight(candidate):
			continue
		if distance < best_distance:
			best = candidate
			best_distance = distance
	return best


func _find_visible_defensive_threat() -> CharacterBody3D:
	var best: CharacterBody3D
	var best_distance := INF
	for group_name in [&"human_players", &"wild_animals"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is CharacterBody3D:
				continue
			var candidate := node as CharacterBody3D
			if group_name == &"human_players" and _get_combat_team(candidate) == team_id:
				continue
			var distance := global_position.distance_to(candidate.global_position)
			if distance > vision_distance or not _has_line_of_sight(candidate):
				continue
			if distance < best_distance:
				best = candidate
				best_distance = distance
	return best


func _has_line_of_sight(candidate: CharacterBody3D) -> bool:
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP, candidate.global_position + Vector3.UP, 65535, [get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var cursor := hit.get("collider", null) as Node
	while cursor != null:
		if cursor == candidate:
			return true
		cursor = cursor.get_parent()
	return false


func _on_hit_3d_body_entered(body: Node3D) -> void:
	_handle_hit3d_contact(body)


func _on_hit_3d_area_entered(area: Area3D) -> void:
	_handle_hit3d_contact(area)


func _handle_hit3d_contact(contact: Node) -> void:
	var projectile := _find_projectile_root(contact)
	if projectile == null:
		return
	var attacker_team := str(projectile.call("get_bullet_owner"))
	if attacker_team.is_empty() or attacker_team == team_id:
		return
	var damage := 20.0
	if _has_property(projectile, "bullet_strength"):
		damage = float(projectile.get("bullet_strength"))
	elif _has_property(projectile, "damage"):
		damage = float(projectile.get("damage"))
	elif _has_property(projectile, "bullet_damage"):
		damage = float(projectile.get("bullet_damage"))
	var effect := str(projectile.get("bullet_effect")) if _has_property(projectile, "bullet_effect") else "bullet"
	impact(effect, damage, attacker_team)
	var hit_direction := projectile.global_position.direction_to(global_position)
	if _has_property(projectile, "direction") and projectile.get("direction") is Vector3:
		hit_direction = projectile.get("direction") as Vector3
	if _has_property(projectile, "knockback_force"):
		receive_bullet_hit(hit_direction, float(projectile.get("knockback_force")), attacker_team)
	projectile.queue_free()


func _find_projectile_root(contact: Node) -> Node3D:
	var cursor: Node = contact
	var depth := 0
	while cursor != null and depth < 12:
		if cursor is Node3D and cursor.has_method("get_bullet_owner"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		depth += 1
	return null


func impact(_effect: String, strength: float, attacker_team: String = "") -> bool:
	if is_dead or strength <= 0.0 or attacker_team == team_id:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	_update_label()
	if current_hp > 0.0 and operation_state == OperationState.CONTROLLING_DRONE:
		_enter_defensive_mode()
	if current_hp <= 0.0:
		_die(attacker_team)
	return true


func receive_bullet_hit(hit_direction: Vector3, force: float, attacker_team: String) -> void:
	if attacker_team == team_id or force <= 0.0:
		return
	var horizontal := Vector3(hit_direction.x, 0.0, hit_direction.z)
	if horizontal.length_squared() > 0.001:
		knockback_velocity += horizontal.normalized() * force


func _die(attacker_team: String) -> void:
	if is_dead:
		return
	is_dead = true
	if not attacker_team.is_empty():
		GameAuthority.award_team_ai_defeat(attacker_team, team_id, "Assistant AI")
	collision_layer = 0
	collision_mask = 0
	if body_collision != null:
		body_collision.set_deferred("disabled", true)
	if hit_collision != null:
		hit_collision.set_deferred("disabled", true)
	if health_label != null:
		health_label.visible = false
	if is_instance_valid(drone):
		drone.queue_free()
	drone = null
	respawn_timer = respawn_seconds


func _respawn() -> void:
	var world: Node = GlobalVar.gameworld
	if is_instance_valid(world) and world.has_method("get_team_spawn_position"):
		global_position = world.call("get_team_spawn_position", team_id, 3, get_instance_id())
	current_hp = max_hp
	is_dead = false
	collision_layer = 8
	collision_mask = 519
	if body_collision != null:
		body_collision.set_deferred("disabled", false)
	if hit_collision != null:
		hit_collision.set_deferred("disabled", false)
	_update_label()
	operation_state = OperationState.ADVANCE_TO_DEPLOYMENT
	deployment_origin = Vector3.INF
	deployment_position = Vector3.INF
	advancing_for_signal_recovery = false
	knockback_velocity = Vector3.ZERO
	call_deferred("_initialize_deployment_advance")


func get_combat_team() -> String:
	return team_id


func _get_combat_team(node: Node) -> String:
	if node.has_method("get_combat_team"):
		return str(node.call("get_combat_team"))
	return str(node.get("team")) if _has_property(node, "team") else str(node.get("team_id")) if _has_property(node, "team_id") else ""


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _update_label() -> void:
	if health_label != null:
		health_label.visible = not is_dead
		health_label.text = "Assistant AI  %d / %d" % [roundi(current_hp), roundi(max_hp)]


func _create_debug_label() -> void:
	debug_label = get_node_or_null("DebugStatus3D") as Label3D
	if debug_label == null:
		debug_label = Label3D.new()
		debug_label.name = "DebugStatus3D"
		add_child(debug_label)
	debug_label.position = Vector3(0.0, 3.35, 0.0)
	debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	debug_label.font_size = 34
	debug_label.outline_size = 7
	debug_label.modulate = Color("#FFD166")
	debug_label.outline_modulate = Color("#18120A")


func _update_debug_label() -> void:
	if debug_label == null:
		return
	if is_dead:
		debug_label.visible = true
		debug_label.text = "DEBUG: 死亡复活 %.1fs" % respawn_timer
		return
	var state_text := ""
	match operation_state:
		OperationState.ADVANCE_TO_DEPLOYMENT:
			var remaining := _horizontal_distance_to(deployment_position) if deployment_position != Vector3.INF else -1.0
			state_text = "部署推进  %.1fm" % remaining if remaining >= 0.0 else "部署推进: 等待农场目标"
		OperationState.CONTROLLING_DRONE:
			state_text = "信号恢复推进" if advancing_for_signal_recovery else "无人机操控"
		OperationState.DEFENSIVE_PATROL:
			state_text = "防御警戒"
	var navigation_text := "导航: 已连接" if _navigation_map_is_ready() else "导航: 直线回退"
	var drone_text := "无人机: 未部署"
	if is_instance_valid(drone):
		drone_text = "无人机: " + drone.get_debug_status()
	elif operation_state == OperationState.DEFENSIVE_PATROL:
		drone_text = "无人机重建: %.1fs" % respawn_timer
	debug_label.visible = true
	debug_label.text = "DEBUG  %s\n%s\n%s" % [state_text, navigation_text, drone_text]


func _create_hand_mount() -> void:
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 1.7, 0.0)
	add_child(head)
	aim_marker = Marker3D.new()
	aim_marker.name = "AimMarker"
	head.add_child(aim_marker)
	upper_body_look_target = Marker3D.new()
	upper_body_look_target.name = "UpperBodyLookTarget"
	head.add_child(upper_body_look_target)
	right_hand_ik_target = Marker3D.new()
	right_hand_ik_target.name = "RightHandIKTarget"
	right_hand_ik_target.position = Vector3(0.28, -0.28, -0.42)
	head.add_child(right_hand_ik_target)
	right_elbow_pole = Marker3D.new()
	right_elbow_pole.name = "RightElbowPole"
	right_elbow_pole.position = Vector3(0.65, 1.2, -0.1)
	add_child(right_elbow_pole)
	right_hand_socket = BoneAttachment3D.new()
	right_hand_socket.name = "RightHandSocket"
	right_hand_socket.bone_name = "Hand.R"
	add_child(right_hand_socket)
	tool_pivot = Node3D.new()
	tool_pivot.name = "ToolPivot"
	right_hand_socket.add_child(tool_pivot)


func _load_assistant_appearance() -> void:
	var scene := load("res://character/hero_skeleton/assistant_%s.tscn" % team_id) as PackedScene
	if scene == null:
		return
	var appearance := scene.instantiate() as Node3D
	if appearance == null:
		return
	appearance.name = "AppearanceNode"
	appearance.rotation.y = deg_to_rad(180.0)
	add_child(appearance)
	appearance_player = appearance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	skeleton = appearance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton == null:
		return
	right_hand_socket.use_external_skeleton = true
	right_hand_socket.external_skeleton = right_hand_socket.get_path_to(skeleton)
	right_hand_socket.bone_name = "Hand.R"
	right_hand_socket.override_pose = false
	_setup_upper_body_aim()
	if appearance_player != null and not appearance_player.animation_finished.is_connected(_on_skeleton_animation_finished):
		appearance_player.animation_finished.connect(_on_skeleton_animation_finished)
	if appearance_player != null and appearance_player.has_animation(&"Idle"):
		appearance_player.play(&"Idle")


func _update_weapon_alignment() -> void:
	if nailgun == null or tool_pivot == null or aim_marker == null:
		return
	var muzzle := nailgun.get_node_or_null("Muzzle") as Node3D
	if muzzle == null:
		return
	var weapon_aim_basis := muzzle.global_transform.basis.orthonormalized()
	if weapon_aim_basis.determinant() == 0.0:
		return
	var pivot_basis := tool_pivot.global_transform.basis.orthonormalized()
	var aim_from_pivot := (pivot_basis.inverse() * weapon_aim_basis).orthonormalized()
	var desired_pivot_basis := (aim_marker.global_transform.basis.orthonormalized() * aim_from_pivot.inverse()).orthonormalized()
	tool_pivot.global_transform = Transform3D(desired_pivot_basis, tool_pivot.global_position)


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


func _add_upper_body_look(node_name: String, bone_name: String, weight: float, limit_degrees: float) -> void:
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
	upper_body_look_weights.append(weight)


func _update_aim_reference() -> void:
	if head == null or aim_marker == null or upper_body_look_target == null:
		return
	var target_position := head.global_position - global_transform.basis.z * 40.0
	if is_instance_valid(target_player):
		target_position = target_player.global_position + Vector3.UP
	upper_body_look_target.global_position = target_position
	aim_marker.global_position = head.global_position
	if target_position.distance_squared_to(aim_marker.global_position) > 0.001:
		aim_marker.look_at(target_position, Vector3.UP)


func _update_upper_body_aim(delta: float) -> void:
	for index in range(upper_body_look_modifiers.size()):
		var modifier := upper_body_look_modifiers[index]
		if is_instance_valid(modifier):
			var desired := upper_body_look_weights[index] * (0.7 if action_animation_locked else 1.0)
			modifier.influence = move_toward(modifier.influence, desired, delta * 3.5)
	if is_instance_valid(right_arm_ik):
		var desired_ik := 0.62 if action_animation_locked else 0.82
		right_arm_ik.influence = move_toward(right_arm_ik.influence, desired_ik, delta * 5.0)


func _on_skeleton_animation_finished(animation_name: StringName) -> void:
	if animation_name == &"ShootOneHand":
		action_animation_locked = false


func _update_character_animation() -> void:
	if appearance_player == null or action_animation_locked:
		return
	var horizontal_velocity := Vector3(velocity.x, 0.0, velocity.z)
	var animation_name: StringName = &"Walk" if horizontal_velocity.length_squared() > 0.04 else &"IdleTool"
	if appearance_player.has_animation(animation_name) \
		and (appearance_player.current_animation != animation_name or not appearance_player.is_playing()):
		appearance_player.play(animation_name, 0.08)
