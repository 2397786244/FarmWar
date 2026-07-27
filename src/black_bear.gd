extends CharacterBody3D
class_name BlackBear

const CombatBalance = preload("res://src/combat_balance.gd")

enum State {
	IDLE,
	WANDER,
	CHASE,
	ATTACK,
	REST,
	FLEE,
	DEAD,
}

const STATE_NAMES := {
	State.IDLE: "idle",
	State.WANDER: "wander",
	State.CHASE: "chase",
	State.ATTACK: "attack",
	State.REST: "rest",
	State.FLEE: "flee",
	State.DEAD: "dead",
}
const STATE_ANIMATIONS := {
	State.IDLE: &"Idle",
	State.WANDER: &"Walk",
	State.CHASE: &"Walk",
	State.ATTACK: &"Attack",
	State.REST: &"Idle",
	State.FLEE: &"Walk",
	State.DEAD: &"Death",
}
const NETWORK_STATES := {
	"idle": State.IDLE,
	"wander": State.WANDER,
	"chase": State.CHASE,
	"attack": State.ATTACK,
	"rest": State.REST,
	"flee": State.FLEE,
	"dead": State.DEAD,
}
const BEAR_HIDE_DROP_COUNT := 5

@export var animal_id := ""
@export var display_name := "黑熊"
@export var max_hp := 1000.0
@export var network_proxy := false

var current_hp := 1000.0
var home_position := Vector3.ZERO
var home_generator: Node = null
var state: State = State.IDLE
var target_peer_id := 0
var target_livestock: FarmLivestock = null
var destroyed := false
var flame_remaining := 0.0
var freeze_remaining := 0.0
var tranquilizer_remaining := 0.0
var trap_remaining := 0.0
var labeled_remaining := 0.0

var _state_elapsed := 0.0
var _chase_elapsed := 0.0
var _target_scan_left := 0.0
var _idle_left := 0.0
var _rest_left := 0.0
var _flee_left := 0.0
var _attack_applied := false
var _damage_since_last_flee := 0.0
var _wander_target := Vector3.ZERO
var _avoidance_direction := Vector3.ZERO
var _avoidance_left := 0.0
var _knockback_velocity := Vector3.ZERO
var _was_immobilized := false
var _labeled_outline_material: StandardMaterial3D = null
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0
var _flame_attacker_peer_id := 0
var _rng := RandomNumberGenerator.new()

@onready var mesh_root: Node3D = get_node_or_null("Mesh") as Node3D
@onready var animation_player: AnimationPlayer = (
	mesh_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if mesh_root != null else null
)
@onready var hit_area: Area3D = get_node_or_null("Hit3D") as Area3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	_rng.seed = hash(animal_id) if not animal_id.is_empty() else get_instance_id()
	max_hp = CombatBalance.get_float("black_bear", "max_hp", max_hp)
	current_hp = max_hp
	if home_position == Vector3.ZERO:
		home_position = global_position
	add_to_group("wild_animals")
	if hit_area != null and not hit_area.body_entered.is_connected(_on_hit_body_entered):
		hit_area.body_entered.connect(_on_hit_body_entered)
	_configure_animation_loops()
	_set_collision_enabled(not network_proxy and not GameAuthority.is_client_proxy())
	_update_health_label()
	_idle_left = _rng.randf_range(2.0, 5.0)
	_set_state(State.IDLE, true)
	if network_proxy or GameAuthority.is_client_proxy():
		network_proxy = true
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if network_proxy or not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	_state_elapsed += delta
	_target_scan_left -= delta
	_avoidance_left = maxf(0.0, _avoidance_left - delta)
	if state == State.DEAD:
		velocity = Vector3.ZERO
		if _state_elapsed >= CombatBalance.get_float("black_bear", "death_visible_seconds", 4.0):
			queue_free()
		return
	_tick_status_effects(delta)
	if destroyed:
		return
	if _is_immobilized():
		_stop_horizontal(delta, true)
		_play_animation(&"Idle")
		_was_immobilized = true
		_update_health_label()
		return
	if _was_immobilized:
		_was_immobilized = false
		_set_state(state, true)

	if state != State.FLEE and state != State.REST and _target_scan_left <= 0.0:
		_target_scan_left = 0.25
		_acquire_target()

	match state:
		State.IDLE:
			_update_idle(delta)
		State.WANDER:
			_update_wander(delta)
		State.CHASE:
			_update_chase(delta)
		State.ATTACK:
			_update_attack(delta)
		State.REST:
			_update_rest(delta)
		State.FLEE:
			_update_flee(delta)


func impact(effect: String, strength: float, _attacker_team: String = "") -> bool:
	if network_proxy or destroyed or strength < 0.0:
		_pending_attacker_peer_id = 0
		return false
	if strength > 0.0:
		_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
			_attacker_team, _pending_attacker_peer_id
		)
	_pending_attacker_peer_id = 0
	var normalized_effect := effect.strip_edges().to_lower()
	match normalized_effect:
		"flame", "fire":
			flame_remaining = maxf(
				flame_remaining,
				CombatBalance.get_float("black_bear", "flame_duration", 3.0)
			)
			_flame_attacker_peer_id = _last_attacker_peer_id
		"freeze", "ice":
			freeze_remaining = maxf(
				freeze_remaining,
				CombatBalance.get_float("black_bear", "freeze_duration", 2.0)
			)
		TranquilizerBullet.EFFECT_TRANQUILIZER:
			tranquilizer_remaining = maxf(
				tranquilizer_remaining,
				CombatBalance.get_float("black_bear", "tranquilizer_duration", 8.0)
			)
		"trap":
			trap_remaining = maxf(
				trap_remaining,
				CombatBalance.get_float("black_bear", "trap_duration", 2.0)
			)
		"labeled", "labelled":
			labeled_remaining = maxf(
				labeled_remaining,
				CombatBalance.get_float("black_bear", "labeled_duration", 6.0)
			)
		# Lightning is an immediate high-damage impact. It deliberately leaves
		# no lingering stun because wild-animal lightning damage is strength.
		"lightening", "lightning":
			pass
		_:
			pass
	_apply_damage(strength)
	_update_labeled_outline()
	return true


func impact_from_peer(effect: String, strength: float, attacker_team: String, attacker_peer_id: int) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	return impact(effect, strength, attacker_team)


func apply_knockback(direction: Vector3, strength: float) -> void:
	if network_proxy or destroyed or strength <= 0.0:
		return
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.001:
		return
	var effective_strength := strength * CombatBalance.get_float(
		"black_bear", "knockback_multiplier", 0.3
	)
	var next_velocity := _knockback_velocity + horizontal.normalized() * effective_strength
	var max_speed := CombatBalance.get_float("black_bear", "max_knockback_speed", 4.0)
	_knockback_velocity = next_velocity.limit_length(max_speed)


func get_network_state() -> Dictionary:
	return {
		"animal_id": animal_id,
		"scene_path": scene_file_path if not scene_file_path.is_empty() else "res://items/BlackBear.tscn",
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"hp": current_hp,
		"max_hp": max_hp,
		"state": STATE_NAMES.get(state, "idle"),
		"animation": "Idle" if _is_immobilized() else str(STATE_ANIMATIONS.get(state, &"Idle")),
		"animation_speed": 1.0 if _is_immobilized() else _animation_speed_for_state(state),
		"flame_remaining": flame_remaining,
		"freeze_remaining": freeze_remaining,
		"tranquilizer_remaining": tranquilizer_remaining,
		"trap_remaining": trap_remaining,
		"labeled_remaining": labeled_remaining,
	}


func apply_network_state(data: Dictionary) -> void:
	network_proxy = true
	var position_value: Variant = data.get("position", global_position)
	if position_value is Vector3:
		global_position = global_position.lerp(position_value as Vector3, 0.55)
	rotation.y = lerp_angle(rotation.y, float(data.get("yaw", rotation.y)), 0.55)
	var velocity_value: Variant = data.get("velocity", Vector3.ZERO)
	if velocity_value is Vector3:
		velocity = velocity_value
	max_hp = float(data.get("max_hp", max_hp))
	current_hp = clampf(float(data.get("hp", current_hp)), 0.0, max_hp)
	flame_remaining = maxf(0.0, float(data.get("flame_remaining", 0.0)))
	freeze_remaining = maxf(0.0, float(data.get("freeze_remaining", 0.0)))
	tranquilizer_remaining = maxf(0.0, float(data.get("tranquilizer_remaining", 0.0)))
	trap_remaining = maxf(0.0, float(data.get("trap_remaining", 0.0)))
	labeled_remaining = maxf(0.0, float(data.get("labeled_remaining", 0.0)))
	destroyed = current_hp <= 0.0
	state = int(NETWORK_STATES.get(str(data.get("state", "idle")).to_lower(), State.IDLE)) as State
	if animation_player != null:
		animation_player.speed_scale = maxf(0.1, float(data.get("animation_speed", _animation_speed_for_state(state))))
	_play_animation(StringName(str(data.get("animation", "Idle"))))
	_update_labeled_outline()
	_update_health_label()


func _tick_status_effects(delta: float) -> void:
	var flame_tick := minf(maxf(0.0, delta), flame_remaining)
	flame_remaining = maxf(0.0, flame_remaining - delta)
	freeze_remaining = maxf(0.0, freeze_remaining - delta)
	tranquilizer_remaining = maxf(0.0, tranquilizer_remaining - delta)
	trap_remaining = maxf(0.0, trap_remaining - delta)
	labeled_remaining = maxf(0.0, labeled_remaining - delta)
	if flame_tick > 0.0:
		_last_attacker_peer_id = _flame_attacker_peer_id
		_apply_damage(
			CombatBalance.get_float("black_bear", "flame_damage_per_second", 15.0) * flame_tick
		)
	if flame_remaining <= 0.0:
		_flame_attacker_peer_id = 0
	_update_labeled_outline()


func _is_immobilized() -> bool:
	return freeze_remaining > 0.0 or tranquilizer_remaining > 0.0 or trap_remaining > 0.0


func _apply_damage(amount: float) -> void:
	var applied_damage := maxf(0.0, amount)
	if destroyed or applied_damage <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - applied_damage)
	_damage_since_last_flee += applied_damage
	_update_health_label()
	if current_hp <= 0.0:
		_die()
	elif _damage_since_last_flee >= CombatBalance.get_float("black_bear", "flee_damage_threshold", 200.0):
		_damage_since_last_flee = 0.0
		target_peer_id = 0
		target_livestock = null
		_flee_left = CombatBalance.get_float("black_bear", "flee_duration", 6.0)
		_set_state(State.FLEE)


func _update_idle(delta: float) -> void:
	_stop_horizontal(delta)
	if _has_valid_target():
		_begin_chase()
		return
	_idle_left -= delta
	if _idle_left <= 0.0:
		_choose_wander_target()
		_set_state(State.WANDER)


func _update_wander(delta: float) -> void:
	if _has_valid_target():
		_begin_chase()
		return
	var direction := _horizontal_direction_to(_wander_target)
	if direction.length_squared() <= 0.01 or global_position.distance_to(_wander_target) <= 1.0:
		_idle_left = _rng.randf_range(2.0, 5.0)
		_set_state(State.IDLE)
		return
	_move_horizontal(direction, CombatBalance.get_float("black_bear", "wander_speed", 2.4), delta)


func _update_chase(delta: float) -> void:
	_chase_elapsed += delta
	if _chase_elapsed >= CombatBalance.get_float("black_bear", "chase_duration", 10.0):
		_begin_rest()
		return
	var target_position_value: Variant = _target_position()
	if target_position_value == null:
		_clear_target_and_idle()
		return
	var target_position := target_position_value as Vector3
	var distance := _horizontal_distance_to(target_position)
	if distance > CombatBalance.get_float("black_bear", "detection_range", 40.0):
		_clear_target_and_idle()
		return
	# Center-to-center distance cannot reliably fall below ~2 m because the
	# bear and player collision bodies touch first. Keep a small entry margin.
	var attack_range := CombatBalance.get_float("black_bear", "attack_range", 2.2) + _livestock_range_bonus()
	if distance <= attack_range:
		_face_direction(_horizontal_direction_to(target_position), delta, true)
		_set_state(State.ATTACK)
		return
	var chase_speed := CombatBalance.get_float("black_bear", "chase_speed", 12.0)
	var approach_range := CombatBalance.get_float("black_bear", "attack_approach_range", 3.5) + _livestock_range_bonus()
	if distance < approach_range:
		var approach_speed := CombatBalance.get_float("black_bear", "attack_approach_speed", 3.0)
		var approach_ratio := clampf(
			(distance - attack_range) / maxf(approach_range - attack_range, 0.01),
			0.0,
			1.0
		)
		chase_speed = lerpf(approach_speed, chase_speed, approach_ratio)
	_move_horizontal(_horizontal_direction_to(target_position), chase_speed, delta)


func _update_attack(delta: float) -> void:
	_chase_elapsed += delta
	_stop_horizontal(delta)
	var target_position_value: Variant = _target_position()
	if target_position_value == null:
		_clear_target_and_idle()
		return
	var target_position := target_position_value as Vector3
	var distance := _horizontal_distance_to(target_position)
	var exit_range := CombatBalance.get_float("black_bear", "attack_exit_range", 2.65) + _livestock_range_bonus()
	if distance > exit_range:
		_set_state(State.CHASE)
		return
	_face_direction(_horizontal_direction_to(target_position), delta, true)
	var hit_range := CombatBalance.get_float("black_bear", "attack_hit_range", 2.25) + _livestock_range_bonus()
	if not _attack_applied and _state_elapsed >= CombatBalance.get_float("black_bear", "attack_windup", 0.42):
		_attack_applied = true
		if distance <= hit_range:
			if _livestock_target_is_valid():
				target_livestock.receive_wildlife_attack(
					CombatBalance.get_float("black_bear", "attack_damage", 50.0),
					global_position
				)
			else:
				GameAuthority.damage_player_from_wild_animal(
					target_peer_id,
					global_position,
					CombatBalance.get_float("black_bear", "attack_damage", 50.0),
					hit_range,
					_horizontal_direction_to(target_position)
				)
	if _state_elapsed >= CombatBalance.get_float("black_bear", "attack_interval", 1.25):
		if _chase_elapsed >= CombatBalance.get_float("black_bear", "chase_duration", 10.0):
			_begin_rest()
		elif distance <= exit_range:
			_set_state(State.ATTACK, true)
		else:
			_set_state(State.CHASE)


func _update_rest(delta: float) -> void:
	_stop_horizontal(delta)
	_rest_left -= delta
	if _rest_left > 0.0:
		return
	if _has_valid_target():
		var target_position_value: Variant = _target_position()
		if target_position_value != null and _horizontal_distance_to(target_position_value as Vector3) <= CombatBalance.get_float("black_bear", "detection_range", 40.0):
			_begin_chase()
			return
	_clear_target_and_idle()


func _update_flee(delta: float) -> void:
	_flee_left -= delta
	var distance_home := _horizontal_distance_to(home_position)
	if distance_home > 1.5:
		var flee_speed := CombatBalance.get_float("black_bear", "flee_speed", 12.0)
		_move_horizontal(_horizontal_direction_to(home_position), flee_speed, delta)
	else:
		_stop_horizontal(delta)
	if _flee_left <= 0.0:
		_idle_left = _rng.randf_range(3.0, 6.0)
		_set_state(State.IDLE)


func _acquire_target() -> void:
	if _has_valid_target():
		return
	target_peer_id = 0
	target_livestock = null
	var detection_range := CombatBalance.get_float("black_bear", "detection_range", 40.0)
	var best_distance := detection_range
	for raw_peer_id: Variant in GameAuthority.player_states.keys():
		var peer_id := int(raw_peer_id)
		if not _target_is_valid(peer_id):
			continue
		var position_value: Variant = GameAuthority.get_authoritative_player_position(peer_id)
		if not position_value is Vector3:
			continue
		var distance := _horizontal_distance_to(position_value as Vector3)
		if distance <= best_distance:
			best_distance = distance
			target_peer_id = peer_id
			target_livestock = null
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if not node is FarmLivestock:
			continue
		var livestock := node as FarmLivestock
		if not livestock.can_be_attacked_by_wildlife():
			continue
		var distance := _horizontal_distance_to(livestock.global_position)
		if distance <= best_distance:
			best_distance = distance
			target_peer_id = 0
			target_livestock = livestock


func _target_is_valid(peer_id: int) -> bool:
	if peer_id <= 0 or not GameAuthority.player_states.has(peer_id):
		return false
	var player_state: Dictionary = GameAuthority.player_states[peer_id]
	return float(player_state.get("hp", 0.0)) > 0.0 \
		and float(player_state.get("respawn_left", 0.0)) <= 0.0


func _target_position() -> Variant:
	if _livestock_target_is_valid():
		return target_livestock.global_position
	if not _target_is_valid(target_peer_id):
		return null
	return GameAuthority.get_authoritative_player_position(target_peer_id)


func _livestock_target_is_valid() -> bool:
	return is_instance_valid(target_livestock) and target_livestock.can_be_attacked_by_wildlife()


func _has_valid_target() -> bool:
	return _livestock_target_is_valid() or _target_is_valid(target_peer_id)


func _livestock_range_bonus() -> float:
	if not _livestock_target_is_valid():
		return 0.0
	match target_livestock.species_id:
		"angus_cow":
			return 1.4
		"pig":
			return 0.7
		_:
			return 0.2


func _begin_chase() -> void:
	_chase_elapsed = 0.0
	# Do not carry a wall-avoidance tangent from wandering/fleeing into a new
	# chase; it can otherwise initially steer away from the acquired player.
	_avoidance_direction = Vector3.ZERO
	_avoidance_left = 0.0
	_set_state(State.CHASE)


func _begin_rest() -> void:
	_rest_left = CombatBalance.get_float("black_bear", "rest_duration", 3.0)
	_set_state(State.REST)


func _clear_target_and_idle() -> void:
	target_peer_id = 0
	target_livestock = null
	_chase_elapsed = 0.0
	_idle_left = _rng.randf_range(2.0, 5.0)
	_set_state(State.IDLE)


func _choose_wander_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := _rng.randf_range(3.0, CombatBalance.get_float("black_bear", "wander_radius", 12.0))
	_wander_target = home_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	_wander_target.y = global_position.y


func _move_horizontal(direction: Vector3, speed: float, delta: float) -> void:
	var move_direction := direction
	var suppress_close_avoidance := false
	if state == State.CHASE:
		var target_position_value: Variant = _target_position()
		if target_position_value is Vector3:
			suppress_close_avoidance = _horizontal_distance_to(target_position_value as Vector3) \
					<= CombatBalance.get_float("black_bear", "attack_approach_range", 3.5)
	if not suppress_close_avoidance and _avoidance_left > 0.0 \
			and _avoidance_direction.length_squared() > 0.001:
		var avoidance_weight := 0.65 if state == State.CHASE else 1.5
		var avoided_direction := (direction + _avoidance_direction * avoidance_weight).normalized()
		# Chase avoidance may bend around an obstacle, but it must never overpower
		# the target vector and send the bear toward the map boundary.
		move_direction = direction if state == State.CHASE \
				and avoided_direction.dot(direction) < 0.35 else avoided_direction
	_face_direction(move_direction, delta)
	velocity.x = move_direction.x * speed + _knockback_velocity.x
	velocity.z = move_direction.z * speed + _knockback_velocity.z
	_apply_gravity(delta)
	move_and_slide()
	_decay_knockback(delta)
	for index in range(get_slide_collision_count() if not suppress_close_avoidance else 0):
		var normal := get_slide_collision(index).get_normal()
		normal.y = 0.0
		if normal.length_squared() <= 0.01:
			continue
		var tangent := Vector3(-normal.z, 0.0, normal.x).normalized()
		if tangent.dot(direction) < 0.0:
			tangent = -tangent
		_avoidance_direction = tangent
		_avoidance_left = 0.8
		break


func _stop_horizontal(delta: float, immobilized := false) -> void:
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_apply_gravity(delta)
	move_and_slide()
	_decay_knockback(
		delta,
		CombatBalance.get_float("black_bear", "immobilized_knockback_decay", 60.0)
		if immobilized else -1.0
	)


func _apply_gravity(delta: float) -> void:
	velocity.y = -1.0 if is_on_floor() else velocity.y - 24.0 * delta


func _decay_knockback(delta: float, override_decay := -1.0) -> void:
	var decay := override_decay if override_decay >= 0.0 else CombatBalance.get_float(
		"black_bear", "knockback_decay", 18.0
	)
	_knockback_velocity = _knockback_velocity.move_toward(
		Vector3.ZERO,
		decay * delta
	)


func _face_direction(direction: Vector3, delta: float, immediate := false) -> void:
	if direction.length_squared() <= 0.001:
		return
	# The BlackBear model's head faces local +Z, unlike character models that
	# use -Z as their visual forward direction.
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = target_yaw if immediate else lerp_angle(
		rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0)
	)


func _horizontal_direction_to(target: Vector3) -> Vector3:
	var direction := target - global_position
	direction.y = 0.0
	return direction.normalized() if direction.length_squared() > 0.001 else Vector3.ZERO


func _horizontal_distance_to(target: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(target.x, target.z))


func _set_state(next_state: State, force := false) -> void:
	if state == next_state and not force:
		return
	state = next_state
	_state_elapsed = 0.0
	_attack_applied = false
	if animation_player != null:
		animation_player.speed_scale = _animation_speed_for_state(state)
	_play_animation(STATE_ANIMATIONS.get(state, &"Idle"))
	_update_health_label()


func _play_animation(requested: StringName) -> void:
	if animation_player == null:
		return
	var animation_name := _resolve_animation_name(requested)
	if animation_name.is_empty():
		return
	if animation_player.current_animation == animation_name and animation_player.is_playing():
		return
	animation_player.play(animation_name, 0.12)


func _configure_animation_loops() -> void:
	if animation_player == null:
		return
	for requested in [&"Idle", &"Walk"]:
		var animation_name := _resolve_animation_name(requested)
		if animation_name.is_empty():
			continue
		var animation := animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
	for requested in [&"Attack", &"Death"]:
		var animation_name := _resolve_animation_name(requested)
		if animation_name.is_empty():
			continue
		var animation := animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_NONE


func _animation_speed_for_state(value: State) -> float:
	return 2.0 if value in [State.CHASE, State.FLEE] else 1.0


func _resolve_animation_name(requested: StringName) -> StringName:
	if animation_player.has_animation(requested):
		return requested
	var requested_lower := str(requested).to_lower()
	for candidate in animation_player.get_animation_list():
		var candidate_lower := str(candidate).to_lower()
		if candidate_lower == requested_lower or candidate_lower.ends_with("/" + requested_lower):
			return candidate
	return &""


func _die() -> void:
	destroyed = true
	flame_remaining = 0.0
	_flame_attacker_peer_id = 0
	freeze_remaining = 0.0
	tranquilizer_remaining = 0.0
	trap_remaining = 0.0
	labeled_remaining = 0.0
	_update_labeled_outline()
	_damage_since_last_flee = 0.0
	target_peer_id = 0
	target_livestock = null
	velocity = Vector3.ZERO
	_set_collision_enabled(false)
	_set_state(State.DEAD)
	_update_health_label()
	if GameAuthority.is_server_authority() or GameAuthority.is_local_authority():
		GameAuthority.award_action_reward(
			_last_attacker_peer_id,
			CombatBalance.get_int("team_rewards", "wild_animal_kill", 50),
			"击杀%s" % display_name
		)
		GameAuthority.spawn_nature_resource_drops(global_position, [{
			"item_id": "bear_hide",
			"count": BEAR_HIDE_DROP_COUNT,
			"weight_kg": IngredientCatalog.get_pickup_unit_kg("bear_hide"),
		}])


func _on_hit_body_entered(body: Node3D) -> void:
	if network_proxy or GameAuthority.should_send_network_requests() or destroyed:
		return
	if not body.has_method("get_bullet_owner"):
		return
	var strength := float(body.get("bullet_strength"))
	if strength <= 0.0:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = str(body.get("bullet_effect"))
	elif body is TranquilizerBullet:
		effect = TranquilizerBullet.EFFECT_TRANQUILIZER
	var attacker_team := str(body.call("get_bullet_owner"))
	var attacker_peer_id := GameAuthority.resolve_attacker_peer_id(attacker_team)
	if bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, attacker_team, -1, attacker_peer_id
	)):
		var direction_value: Variant = _property_value(body, "direction", Vector3.ZERO)
		var knockback_value := float(_property_value(body, "knockback_force", 0.0))
		if direction_value is Vector3:
			apply_knockback(direction_value as Vector3, knockback_value)
		GameAuthority.show_local_hit_marker_for_team(attacker_team)


func _property_value(object: Object, property_name: String, fallback: Variant) -> Variant:
	for property in object.get_property_list():
		if str((property as Dictionary).get("name", "")) == property_name:
			return object.get(property_name)
	return fallback


func _set_collision_enabled(enabled: bool) -> void:
	collision_layer = GameAuthority.COLLISION_LAYER_WILD_ANIMAL if enabled else 0
	collision_mask = GameAuthority.WILD_ANIMAL_BODY_MASK if enabled else 0
	for shape in find_children("*", "CollisionShape3D", true, false):
		(shape as CollisionShape3D).set_deferred("disabled", not enabled)
	if hit_area != null:
		hit_area.collision_layer = GameAuthority.COLLISION_LAYER_WILD_ANIMAL if enabled else 0
		hit_area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET if enabled else 0
		hit_area.set_deferred("monitoring", enabled)
		hit_area.set_deferred("monitorable", enabled)


func _update_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = true
	var status := "IMMOBILIZED" if _is_immobilized() else str(STATE_NAMES.get(state, "idle")).to_upper()
	health_label.text = "BlackBear [%s]\nHP: %d / %d" % [
		status,
		ceili(current_hp),
		ceili(max_hp),
	]


func _update_labeled_outline() -> void:
	var visible := not destroyed and labeled_remaining > 0.0
	var overlay: Material = _get_labeled_outline_material() if visible else null
	if mesh_root == null:
		return
	for child in mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		mesh_instance.material_overlay = overlay
		mesh_instance.ignore_occlusion_culling = visible


func _get_labeled_outline_material() -> StandardMaterial3D:
	if is_instance_valid(_labeled_outline_material):
		return _labeled_outline_material
	_labeled_outline_material = StandardMaterial3D.new()
	_labeled_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_labeled_outline_material.no_depth_test = true
	_labeled_outline_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_labeled_outline_material.albedo_color = Color(0.0, 0.0, 0.0, 0.94)
	_labeled_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_labeled_outline_material.grow = true
	_labeled_outline_material.grow_amount = 0.055
	_labeled_outline_material.render_priority = 120
	return _labeled_outline_material


func _exit_tree() -> void:
	if is_instance_valid(home_generator) and home_generator.has_method("on_animal_removed"):
		home_generator.call("on_animal_removed", self)
