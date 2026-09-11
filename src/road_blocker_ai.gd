extends CharacterBody3D
class_name RoadBlockerAI

## Stationary checkpoint guard.  It deliberately owns no NavigationAgent: a
## RoadBlocker only turns in place and fires after its checkpoint alarms.
signal died(blocker: RoadBlockerAI)

enum State { IDLE, ATTACK, DEATH }

const WEAPONS := {
	"remington870": "res://character/weapons/Remington870.tscn",
	"shotgun": "res://character/weapons/Shotgun.tscn",
	"remington870_rusted": "res://character/weapons/Remington870Rusted.tscn",
	"shotgun_rusted": "res://character/weapons/ShotgunRusted.tscn",
}
const DEATH_CLEANUP_SECONDS := 10.0
const TOOL_CONFIG_PATH := "res://data/tool_definitions.json"

@export var max_hp := 100.0
@export var detection_range := 40.0
@export var fire_interval := 0.85
@export_range(15.0, 360.0, 1.0) var turn_speed_degrees := 90.0
@export_range(1.0, 45.0, 1.0) var fire_alignment_tolerance_degrees := 10.0
## Stationary checkpoint guard spread; kept independently tunable from Warrior.
@export_range(0.0, 30.0, 0.1) var aim_spread_degrees := 5.0
@export var body_collision_layer := 8
@export var body_collision_mask := 647 | GameAuthority.COLLISION_LAYER_VEHICLES
@export var hit_area_collision_layer := 0
@export var hit_area_collision_mask := 32
@export var road_blocker_id := ""

var current_hp := 100.0
var state := State.IDLE
var weapon_id := ""
var hostile_team := ""
var attack_enabled := false
var checkpoint_id := ""
var interest_sleeping := false
var _fire_left := 0.0
var magazine_capacity := 6
var ammo_in_mag := 6
var reload_remaining := 0.0
var reload_duration := 0.0
var _death_left := 0.0
var _dropped_weapon := false
var _rng := RandomNumberGenerator.new()
var _checkpoint: Node
var _retaliation_target: Node3D
var _held_weapon: Node3D
var _head: Node3D
var _weapon_pivot: Node3D
var _hit_area: Area3D
var _skeleton: Skeleton3D
var _appearance_player: AnimationPlayer
var _right_hand_socket: BoneAttachment3D
var _left_target: Marker3D
var _right_target: Marker3D
var _left_elbow_pole: Marker3D
var _right_elbow_pole: Marker3D
var _left_ik: TwoBoneIK3D
var _right_ik: TwoBoneIK3D

func _ready() -> void:
	_rng.randomize()
	current_hp = max_hp
	add_to_group("road_blockers")
	add_to_group("combat_characters")
	collision_layer = body_collision_layer
	collision_mask = body_collision_mask
	_create_runtime_nodes()
	_load_appearance()
	_choose_weapon()

func _create_runtime_nodes() -> void:
	var shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		shape = CollisionShape3D.new(); shape.name = "CollisionShape3D"; add_child(shape)
	# RoadBlocker is a taller checkpoint guard: use one 3m capsule for both
	# physical collision and Hit3D so torso and head are continuously covered.
	var capsule := CapsuleShape3D.new(); capsule.radius = 0.42; capsule.height = 3.0
	shape.shape = capsule; shape.position = Vector3(0, 1.50, 0)
	# Match the Player/FutureWarrior aiming frame.  The collision capsule remains
	# 3m tall, while held-tool IK uses the character rig's normal chest height.
	_head = Node3D.new(); _head.name = "Head"; _head.position = Vector3(0.0, 1.7080579, -0.45418245); add_child(_head)
	_weapon_pivot = Node3D.new(); _weapon_pivot.name = "WeaponPivot"; _head.add_child(_weapon_pivot)
	_right_target = Marker3D.new(); _right_target.name = "RightHandIKTarget"; _right_target.position = Vector3(0.28, -0.28, -0.42); _head.add_child(_right_target)
	_left_target = Marker3D.new(); _left_target.name = "LeftHandIKTarget"; _left_target.position = Vector3(-0.28, -0.28, -0.42); _head.add_child(_left_target)
	_right_elbow_pole = Marker3D.new(); _right_elbow_pole.name = "RightElbowPole"; _right_elbow_pole.position = Vector3(0.65, 1.2, -0.1); add_child(_right_elbow_pole)
	_left_elbow_pole = Marker3D.new(); _left_elbow_pole.name = "LeftElbowPole"; _left_elbow_pole.position = Vector3(-0.65, -0.35, -0.35); _head.add_child(_left_elbow_pole)
	_hit_area = Area3D.new(); _hit_area.name = "Hit3D"; _hit_area.collision_layer = hit_area_collision_layer; _hit_area.collision_mask = hit_area_collision_mask; add_child(_hit_area)
	var hit_shape := CollisionShape3D.new(); hit_shape.name = "CollisionShape3D"; hit_shape.shape = capsule.duplicate(); hit_shape.position = Vector3(0, 1.50, 0); _hit_area.add_child(hit_shape)

func _load_appearance() -> void:
	var scene := load("res://assets/characters/RoadBlocker.glb") as PackedScene
	if scene == null: return
	var appearance := scene.instantiate() as Node3D
	if appearance == null: return
	appearance.name = "Appearance"
	# Imported player-compatible character rigs face the opposite model axis.
	# FutureWarrior and Player apply this same correction so root -Z is forward.
	appearance.rotation.y = PI
	add_child(appearance)
	_skeleton = appearance.find_child("Skeleton3D", true, false) as Skeleton3D
	_appearance_player = appearance.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _appearance_player != null:
		var idle_animation: StringName = &"IdleTool" if _appearance_player.has_animation(&"IdleTool") else &"IdleAim" if _appearance_player.has_animation(&"IdleAim") else &"Idle"
		if _appearance_player.has_animation(idle_animation):
			_appearance_player.play(idle_animation, 0.0)
	if _skeleton == null: return
	# Keep the socket at the character root and bind it through external_skeleton,
	# exactly like Player/FutureWarrior.  This lets ToolPivot compensate the
	# animated Hand.R basis without inheriting an extra model-space rotation.
	_right_hand_socket = BoneAttachment3D.new()
	_right_hand_socket.name = "RightHandSocket"
	add_child(_right_hand_socket)
	_right_hand_socket.use_external_skeleton = true
	_right_hand_socket.external_skeleton = _right_hand_socket.get_path_to(_skeleton)
	_right_hand_socket.bone_name = "Hand.R"
	_right_hand_socket.override_pose = false
	if _weapon_pivot.get_parent() != null:
		_weapon_pivot.get_parent().remove_child(_weapon_pivot)
	_right_hand_socket.add_child(_weapon_pivot)
	_weapon_pivot.transform = Transform3D.IDENTITY
	# The imported characters share these canonical bone names.  Missing bones
	# simply leave the weapon visible rather than failing the whole AI.
	_right_ik = _make_arm_ik("RightArmIK", "UpperArm.R", "Forearm.R", "Hand.R", _right_target, _right_elbow_pole, SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X)
	_left_ik = _make_arm_ik("LeftArmIK", "UpperArm.L", "Forearm.L", "Hand.L", _left_target, _left_elbow_pole, SkeletonModifier3D.SECONDARY_DIRECTION_MINUS_X)

func _make_arm_ik(name_: String, root_bone: String, middle_bone: String, end_bone: String, target: Node3D, pole: Node3D, pole_direction: int) -> TwoBoneIK3D:
	if _skeleton == null or _skeleton.find_bone(root_bone) < 0 or _skeleton.find_bone(middle_bone) < 0 or _skeleton.find_bone(end_bone) < 0: return null
	var ik := TwoBoneIK3D.new()
	ik.name = name_
	_skeleton.add_child(ik)
	ik.setting_count = 1
	ik.set_root_bone_name(0, root_bone)
	ik.set_middle_bone_name(0, middle_bone)
	ik.set_end_bone_name(0, end_bone)
	ik.set_use_virtual_end(0, false)
	ik.set_extend_end_bone(0, false)
	ik.set_pole_direction(0, pole_direction)
	ik.set_target_node(0, ik.get_path_to(target))
	ik.set_pole_node(0, ik.get_path_to(pole))
	ik.active = true
	ik.influence = 0.0
	return ik

func _choose_weapon() -> void:
	var roll := _rng.randf()
	weapon_id = "remington870" if roll < 0.4 else "shotgun" if roll < 0.8 else "remington870_rusted" if roll < 0.9 else "shotgun_rusted"
	_reset_weapon_ammo()
	_equip_weapon()

func _reset_weapon_ammo() -> void:
	var definition := _weapon_definition()
	magazine_capacity = maxi(1, int(definition.get("magazine_size", 6)))
	ammo_in_mag = magazine_capacity
	reload_remaining = 0.0
	reload_duration = 0.0

func _weapon_definition() -> Dictionary:
	var file := FileAccess.open(TOOL_CONFIG_PATH, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	var tools: Array = []
	if parsed is Dictionary:
		var tools_value: Variant = (parsed as Dictionary).get("tools", [])
		if tools_value is Array: tools = tools_value as Array
	elif parsed is Array:
		tools = parsed as Array
	else:
		return {}
	for value in tools:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == weapon_id:
			return value as Dictionary
	return {}

func _equip_weapon() -> void:
	if is_instance_valid(_held_weapon): _held_weapon.queue_free()
	var packed := load(str(WEAPONS.get(weapon_id, ""))) as PackedScene
	if packed == null: return
	_held_weapon = packed.instantiate() as Node3D
	if _held_weapon == null: return
	_weapon_pivot.add_child(_held_weapon)
	var definition := _weapon_definition()
	_held_weapon.position = _definition_vector3(definition.get("grip_position", []), Vector3.ZERO)
	_held_weapon.rotation_degrees = _definition_vector3(definition.get("grip_rotation", []), Vector3.ZERO)
	_held_weapon.scale = _definition_vector3(definition.get("grip_scale", []), Vector3.ONE)
	var left_grip := _held_weapon.get_node_or_null("LeftHandGrip") as Marker3D
	if left_grip != null:
		left_grip.position = _definition_vector3(definition.get("left_hand_grip_offset", []), left_grip.position)
	_set_weapon_owner(_held_weapon, "road_blocker")
	call_deferred("_align_weapon_to_basis", global_transform.basis.orthonormalized())

func _definition_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if not value is Array or (value as Array).size() < 3: return fallback
	var data := value as Array
	return Vector3(float(data[0]), float(data[1]), float(data[2]))

func _set_weapon_owner(weapon: Node, owner_team: String) -> void:
	for property in ["tool_owner", "team", "team_id", "owner_team"]:
		for info in weapon.get_property_list():
			if str(info.get("name", "")) == property: weapon.set(property, owner_team)

func _process(delta: float) -> void:
	if state == State.DEATH or interest_sleeping: return
	if is_instance_valid(_held_weapon):
		var grip := _held_weapon.get_node_or_null("LeftHandGrip") as Marker3D
		if grip != null and _left_target != null:
			var left_target_position := _head.to_local(grip.global_position)
			_left_target.position = _left_target.position.lerp(left_target_position, minf(delta * 18.0, 1.0))
	if is_instance_valid(_right_ik):
		_right_ik.influence = move_toward(_right_ik.influence, 0.88 if is_instance_valid(_held_weapon) else 0.0, delta * 5.0)
	if is_instance_valid(_left_ik):
		_left_ik.influence = move_toward(_left_ik.influence, 0.85 if is_instance_valid(_held_weapon) else 0.0, delta * 12.0)
	# FutureWarrior performs this after its IK update on every visual frame.  It
	# must also run in IDLE because the hand animation changes the socket basis
	# even while the stationary guard is not firing.
	_align_weapon_to_basis(global_transform.basis.orthonormalized())

func _physics_process(delta: float) -> void:
	if state == State.DEATH:
		_death_left -= delta
		if _death_left <= 0.0: queue_free()
		return
	if interest_sleeping or not _is_authority(): return
	_fire_left = maxf(0.0, _fire_left - delta)
	if not attack_enabled:
		state = State.IDLE; return
	state = State.ATTACK
	if reload_remaining > 0.0:
		reload_remaining = maxf(0.0, reload_remaining - delta)
		if reload_remaining <= 0.0:
			ammo_in_mag = magazine_capacity
			reload_duration = 0.0
		return
	if ammo_in_mag <= 0:
		_start_reload()
		return
	var target := _select_target()
	if target == null: return
	var flat := target.global_position - global_position
	flat.y = 0.0
	var aligned_to_target := false
	if flat.length_squared() > 0.01:
		var desired_yaw := atan2(-flat.x, -flat.z)
		rotation.y = rotate_toward(rotation.y, desired_yaw, deg_to_rad(turn_speed_degrees) * delta)
		aligned_to_target = absf(wrapf(desired_yaw - rotation.y, -PI, PI)) <= deg_to_rad(fire_alignment_tolerance_degrees)
	# The body follows the target only around Y; applying that same horizontal
	# frame to the ToolPivot keeps the muzzle level and forward, exactly as a
	# player-held shotgun rather than pitching the gun up/down at the target.
	_align_weapon_to_basis(global_transform.basis.orthonormalized())
	if aligned_to_target and _fire_left <= 0.0: _fire_at(target)

## Exact same full-basis compensation used by Player: preserve the authored
## grip transform, then solve ToolPivot from the muzzle's real forward frame.
func _align_weapon_to_basis(desired_aim_basis: Basis) -> void:
	if not is_instance_valid(_held_weapon) or not is_instance_valid(_weapon_pivot): return
	var muzzle := _held_weapon.get_node_or_null("Muzzle") as Node3D
	if muzzle == null: return
	var weapon_aim_basis := muzzle.global_transform.basis.orthonormalized()
	if is_zero_approx(weapon_aim_basis.determinant()): return
	var pivot_basis := _weapon_pivot.global_transform.basis.orthonormalized()
	var aim_from_pivot := (pivot_basis.inverse() * weapon_aim_basis).orthonormalized()
	var desired_pivot_basis := (desired_aim_basis.orthonormalized() * aim_from_pivot.inverse()).orthonormalized()
	_weapon_pivot.global_transform = Transform3D(desired_pivot_basis, _weapon_pivot.global_position)

func _start_reload() -> void:
	if reload_remaining > 0.0 or ammo_in_mag >= magazine_capacity: return
	var definition := _weapon_definition()
	reload_duration = maxf(0.05, float(definition.get("reload_time", 1.0)))
	reload_remaining = reload_duration

func _select_target() -> Node3D:
	# An independent blocker is neutral: retaliate against the actual source
	# first, then defend itself against any visible combat actor.
	if _is_independent() and is_instance_valid(_retaliation_target) \
			and _is_visible_target(_retaliation_target):
		return _retaliation_target
	if _is_independent():
		return _select_independent_target()
	if hostile_team not in ["red", "blue"]: return null
	var best_player: Node3D
	var best_vehicle: Node3D
	var player_distance := INF; var vehicle_distance := INF
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is Node3D and _target_team(node as Node) == hostile_team and _is_visible_target(node as Node3D):
			var d := global_position.distance_squared_to((node as Node3D).global_position)
			if d < player_distance: best_player = node; player_distance = d
	if best_player != null: return best_player
	for node in get_tree().get_nodes_in_group("vehicles"):
		if node is Node3D and _target_team(node as Node) == hostile_team and _is_visible_target(node as Node3D):
			var d := global_position.distance_squared_to((node as Node3D).global_position)
			if d < vehicle_distance: best_vehicle = node; vehicle_distance = d
	return best_vehicle

func _select_independent_target() -> Node3D:
	var best_player: Node3D
	var best_ai: Node3D
	var best_vehicle: Node3D
	var player_distance := INF; var ai_distance := INF; var vehicle_distance := INF
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is Node3D and _is_visible_target(node as Node3D):
			var distance := global_position.distance_squared_to((node as Node3D).global_position)
			if distance < player_distance: best_player = node; player_distance = distance
	if best_player != null: return best_player
	for group_name in ["ai_players", "farmer_ai", "future_warrior_ai", "assistant_ai"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node == self or not node is Node3D or not _is_visible_target(node as Node3D): continue
			var distance := global_position.distance_squared_to((node as Node3D).global_position)
			if distance < ai_distance: best_ai = node; ai_distance = distance
	if best_ai != null: return best_ai
	for node in get_tree().get_nodes_in_group("vehicles"):
		if node is Node3D and _is_visible_target(node as Node3D):
			var distance := global_position.distance_squared_to((node as Node3D).global_position)
			if distance < vehicle_distance: best_vehicle = node; vehicle_distance = distance
	return best_vehicle

func _is_independent() -> bool:
	if is_instance_valid(_checkpoint): return false
	for checkpoint in get_tree().get_nodes_in_group("road_checkpoints"):
		if checkpoint is RoadCheckpoint and (checkpoint as RoadCheckpoint).contains_world_position(global_position):
			return false
	return true

func _target_team(node: Node) -> String:
	for property in ["team", "team_id", "owner_team"]:
		for info in node.get_property_list():
			if str(info.get("name", "")) == property:
				var value := str(node.get(property)).to_lower()
				if value in ["red", "blue"]: return value
	return ""

func _is_visible_target(target: Node3D) -> bool:
	if not is_instance_valid(target) or target.global_position.distance_to(global_position) > detection_range: return false
	var query := PhysicsRayQueryParameters3D.create(_head.global_position, target.global_position + Vector3.UP, 138, [get_rid()])
	query.collide_with_bodies = true; query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return true
	var cursor := hit.get("collider") as Node
	while cursor != null:
		if cursor == target: return true
		cursor = cursor.get_parent()
	return false

func _fire_at(target: Node3D) -> void:
	if not is_instance_valid(_held_weapon) or not GameAuthority.has_method("server_ai_pellet_hitscan"): return
	var origin := _held_weapon.call("get_fire_origin") as Vector3
	var direction := _apply_aim_spread(origin, target.global_position + Vector3.UP)
	var result := GameAuthority.server_ai_pellet_hitscan(self, "road_blocker", weapon_id, origin, direction)
	if bool(result.get("ok", false)):
		_fire_left = fire_interval
		ammo_in_mag = maxi(0, ammo_in_mag - 1)
		if ammo_in_mag <= 0: _start_reload()
		if GameAuthority.is_local_authority() and _held_weapon.has_method("emit_visual_only_pellets"):
			_held_weapon.call("emit_visual_only_pellets", result.get("pellet_results", []))
		elif _held_weapon.has_method("play_muzzle_visual"):
			# Dedicated/listen server already broadcasts every authoritative pellet;
			# only the local muzzle flash must be added here.
			_held_weapon.call("play_muzzle_visual")

func _apply_aim_spread(origin: Vector3, target_position: Vector3) -> Vector3:
	var to_target := target_position - origin
	var target_distance := to_target.length()
	if target_distance <= 0.001 or aim_spread_degrees <= 0.0:
		return to_target.normalized()
	var direction := to_target / target_distance
	var reference_up := Vector3.UP if absf(direction.dot(Vector3.UP)) <= 0.98 else Vector3.RIGHT
	var right := direction.cross(reference_up).normalized()
	var up := right.cross(direction).normalized()
	var angle := _rng.randf_range(0.0, TAU)
	# Uniform cone-disk samples, identical to FutureWarrior/Assistant aim spread.
	var radius := tan(deg_to_rad(aim_spread_degrees)) * sqrt(_rng.randf())
	return (direction + (right * cos(angle) + up * sin(angle)) * radius).normalized()

func bind_checkpoint(checkpoint: RoadCheckpoint) -> void:
	_checkpoint = checkpoint; checkpoint_id = checkpoint.checkpoint_id

func set_checkpoint_attack_permission(enabled: bool, _reason := StringName()) -> void:
	attack_enabled = enabled
	if state != State.DEATH: state = State.ATTACK if enabled else State.IDLE

func set_checkpoint_attack_team(team: String) -> void:
	hostile_team = team.to_lower()

func impact(effect: String, strength: float, _attacker_team := "") -> bool:
	if state == State.DEATH: return false
	current_hp = maxf(0.0, current_hp - maxf(0.0, strength))
	if current_hp <= 0.0: _die(_attacker_team)
	elif _is_independent():
		# Explosions without a recoverable source still put a neutral guard into
		# retaliation mode; target selection then finds the nearest visible actor.
		attack_enabled = true
		state = State.ATTACK
	return true

func impact_from_peer(effect: String, strength: float, attacker_team: String, _peer_id: int) -> bool:
	return impact_from_source(effect, strength, attacker_team, _peer_id)

func impact_from_source(effect: String, strength: float, attacker_team := "", attacker_peer_id := 0, attacker_node: Node3D = null) -> bool:
	var applied := impact(effect, strength, attacker_team)
	if not applied or not _is_independent(): return applied
	if not is_instance_valid(attacker_node) and attacker_peer_id > 0:
		attacker_node = _human_player_for_peer(attacker_peer_id)
	if is_instance_valid(attacker_node):
		_retaliation_target = attacker_node
	attack_enabled = true
	if state != State.DEATH: state = State.ATTACK
	return applied

func _human_player_for_peer(peer_id: int) -> Node3D:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is Node3D and int(node.get("authority_peer_id")) == peer_id: return node as Node3D
	return null

func _die(attacker_team := "") -> void:
	if state == State.DEATH: return
	state = State.DEATH; attack_enabled = false; _death_left = DEATH_CLEANUP_SECONDS
	if attacker_team in ["red", "blue"] and _is_authority():
		GameAuthority.award_road_blocker_defeat(attacker_team)
	_play_death_animation()
	collision_layer = 0; collision_mask = GameAuthority.COLLISION_LAYER_GROUND | GameAuthority.COLLISION_LAYER_WALL
	if is_instance_valid(_hit_area): _hit_area.set_deferred("monitoring", false)
	_drop_weapon()
	died.emit(self)

func _play_death_animation() -> void:
	if _appearance_player == null: return
	var animation: StringName = &"Death"
	if not _appearance_player.has_animation(animation): animation = &"DeathFallForward"
	if _appearance_player.has_animation(animation):
		_appearance_player.process_mode = Node.PROCESS_MODE_ALWAYS
		_appearance_player.play(animation, 0.08)

func _drop_weapon() -> void:
	if _dropped_weapon or not _is_authority() or not GameAuthority.has_method("spawn_road_blocker_weapon_drop"): return
	_dropped_weapon = true
	GameAuthority.spawn_road_blocker_weapon_drop(global_position, weapon_id)

func _is_authority() -> bool:
	return GameAuthority.is_local_authority() or GameAuthority.is_server_authority()

func get_network_state() -> Dictionary:
	return {"ai_id": str(get_meta("network_ai_id", road_blocker_id if not road_blocker_id.is_empty() else name)), "ai_type": "road_blocker", "position": global_position, "yaw": rotation.y, "hp": current_hp, "max_hp": max_hp, "dead": state == State.DEATH, "death_cleanup_left": _death_left, "state": state, "weapon_id": weapon_id, "hostile_team": hostile_team, "attack_enabled": attack_enabled, "checkpoint_id": checkpoint_id, "ammo_in_mag": ammo_in_mag, "magazine_capacity": magazine_capacity, "reload_remaining": reload_remaining, "reload_duration": reload_duration}

func apply_network_state(data: Dictionary) -> void:
	var was_dead := state == State.DEATH
	global_position = data.get("position", global_position) as Vector3; rotation.y = float(data.get("yaw", rotation.y)); current_hp = float(data.get("hp", current_hp)); hostile_team = str(data.get("hostile_team", hostile_team)); attack_enabled = bool(data.get("attack_enabled", attack_enabled)); checkpoint_id = str(data.get("checkpoint_id", checkpoint_id))
	var incoming_weapon := str(data.get("weapon_id", weapon_id))
	if incoming_weapon != weapon_id and WEAPONS.has(incoming_weapon): weapon_id = incoming_weapon; _reset_weapon_ammo(); _equip_weapon()
	var dead := bool(data.get("dead", false)); state = State.DEATH if dead else int(data.get("state", state)); _death_left = float(data.get("death_cleanup_left", _death_left))
	if dead and not was_dead: _play_death_animation()
	magazine_capacity = maxi(1, int(data.get("magazine_capacity", magazine_capacity)))
	ammo_in_mag = clampi(int(data.get("ammo_in_mag", ammo_in_mag)), 0, magazine_capacity)
	reload_remaining = maxf(0.0, float(data.get("reload_remaining", reload_remaining)))
	reload_duration = maxf(0.0, float(data.get("reload_duration", reload_duration)))

func can_enter_interest_sleep() -> bool: return state != State.DEATH
func set_interest_sleeping(value: bool) -> void: interest_sleeping = value
