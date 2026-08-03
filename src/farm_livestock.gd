extends CharacterBody3D
class_name FarmLivestock

const CombatBalance = preload("res://src/combat_balance.gd")

enum State { IDLE, WALK, EAT, FLEE, DEAD }

const STATE_NAMES := {
	State.IDLE: "idle",
	State.WALK: "walk",
	State.EAT: "eat",
	State.FLEE: "flee",
	State.DEAD: "dead",
}
const STATE_ANIMATIONS := {
	State.IDLE: &"Idle",
	State.WALK: &"Walk",
	State.EAT: &"Eat",
	State.FLEE: &"Walk",
	State.DEAD: &"Death",
}
const NETWORK_STATES := {
	"idle": State.IDLE,
	"walk": State.WALK,
	"eat": State.EAT,
	"flee": State.FLEE,
	"dead": State.DEAD,
}

@export var animal_id := ""
@export var species_id := "chicken"
@export var display_name := "鸡"
@export var owner_team := ""
@export var max_hp := 200.0
@export var meat_item_id := "chicken"
@export var meat_drop_count := 5
@export var walk_speed := 2.0
@export var flee_speed := 5.0
@export var roaming_radius := 12.0
@export var marker_height := 1.6
@export var lays_eggs := false
@export var egg_interval_seconds := 30.0
@export_range(0.0, 1.0, 0.01) var golden_egg_chance := 0.10
@export var produces_milk := false
@export var milk_interval_seconds := 60.0
@export_range(0, 3, 1) var initial_milk_charges := -1
@export_range(-1.0, 60.0, 0.1) var initial_milk_countdown := -1.0
@export var network_proxy := false
@export var naturally_spawned := false
@export var initial_hp := -1.0
@export_range(0.0, 100.0, 0.1) var initial_growth_progress := 0.0

@export var housed_in_chop: bool:
	get:
		return _housed_in_chop
	set(value):
		_housed_in_chop = value
		if is_node_ready():
			_apply_housing_state()

var current_hp := 0.0
var home_position := Vector3.ZERO
var home_generator: Node = null
var state: State = State.IDLE
var destroyed := false
var flame_remaining := 0.0
var freeze_remaining := 0.0
var tranquilizer_remaining := 0.0
var trap_remaining := 0.0
var labeled_remaining := 0.0
var maturity_seconds := 180.0
var growth_elapsed_seconds := 0.0

var _housed_in_chop := false
var _state_elapsed := 0.0
var _state_duration := 0.0
var _eat_countdown := 0.0
var _egg_countdown := 0.0
var milk_charges_remaining := 0
var milk_countdown := 60.0
var _milk_cycle_initialized := false
var _move_target := Vector3.ZERO
var _knockback_velocity := Vector3.ZERO
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0
var _rng := RandomNumberGenerator.new()
var _team_marker: MeshInstance3D
var _labeled_outline_material: StandardMaterial3D
var _interaction_area: Area3D

@onready var mesh_root: Node3D = get_node_or_null("Mesh") as Node3D
@onready var animation_player: AnimationPlayer = (
	mesh_root.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if mesh_root != null else null
)
@onready var hit_area: Area3D = get_node_or_null("Hit3D") as Area3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	_rng.seed = hash(animal_id) if not animal_id.is_empty() else get_instance_id()
	match species_id:
		"pig":
			max_hp = CombatBalance.get_float("farm_livestock", "pig_hp", max_hp)
			meat_drop_count = CombatBalance.get_int(
				"farm_livestock", "pig_meat_drop_count", meat_drop_count
			)
			maturity_seconds = CombatBalance.get_float(
				"farm_livestock", "pig_maturity_seconds", maturity_seconds
			)
		"angus_cow":
			max_hp = CombatBalance.get_float("farm_livestock", "angus_cow_hp", max_hp)
			meat_drop_count = CombatBalance.get_int(
				"farm_livestock", "angus_cow_meat_drop_count", meat_drop_count
			)
			maturity_seconds = CombatBalance.get_float(
				"farm_livestock", "angus_cow_maturity_seconds", maturity_seconds
			)
			produces_milk = true
			milk_interval_seconds = CombatBalance.get_float(
				"farm_livestock", "angus_cow_milk_interval_seconds", milk_interval_seconds
			)
		_:
			max_hp = CombatBalance.get_float("farm_livestock", "chicken_hp", max_hp)
			meat_drop_count = CombatBalance.get_int(
				"farm_livestock", "chicken_meat_drop_count", meat_drop_count
			)
			maturity_seconds = CombatBalance.get_float(
				"farm_livestock", "chicken_maturity_seconds", maturity_seconds
			)
	egg_interval_seconds = CombatBalance.get_float(
		"farm_livestock", "egg_interval_seconds", egg_interval_seconds
	)
	golden_egg_chance = CombatBalance.get_float(
		"farm_livestock", "golden_egg_chance", golden_egg_chance
	)
	current_hp = clampf(initial_hp, 0.0, max_hp) if initial_hp >= 0.0 else max_hp
	growth_elapsed_seconds = clampf(initial_growth_progress, 0.0, 100.0) * maturity_seconds / 100.0
	if home_position == Vector3.ZERO:
		home_position = global_position
	if animal_id.is_empty():
		animal_id = "%s:%d" % [species_id, get_instance_id()]
	add_to_group("wild_animals")
	add_to_group("farm_livestock")
	_create_interaction_area()
	if hit_area != null and not hit_area.body_entered.is_connected(_on_hit_body_entered):
		hit_area.body_entered.connect(_on_hit_body_entered)
	_configure_animation_loops()
	_create_team_marker()
	_eat_countdown = _rng.randf_range(8.0, 16.0)
	_egg_countdown = egg_interval_seconds
	milk_countdown = maxf(1.0, initial_milk_countdown) if initial_milk_countdown >= 0.0 else milk_interval_seconds
	milk_charges_remaining = clampi(initial_milk_charges, 0, 3) if initial_milk_charges >= 0 else 0
	_milk_cycle_initialized = not produces_milk or is_mature()
	if produces_milk and is_mature() and initial_milk_charges < 0:
		milk_charges_remaining = 3
	_set_state(State.IDLE, true)
	_apply_housing_state()
	if network_proxy or GameAuthority.is_client_proxy():
		network_proxy = true
		set_physics_process(false)


func _physics_process(delta: float) -> void:
	if network_proxy or not (GameAuthority.is_server_authority() or GameAuthority.is_local_authority()):
		return
	_state_elapsed += delta
	if state == State.DEAD:
		velocity = Vector3.ZERO
		if _state_elapsed >= CombatBalance.get_float("farm_livestock", "death_visible_seconds", 4.0):
			queue_free()
		return
	_tick_effects(delta)
	_tick_growth(delta)
	_tick_egg_laying(delta)
	_tick_milk_production(delta)
	if destroyed:
		return
	if _is_immobilized():
		_stop_horizontal(delta)
		_play_animation(&"Idle")
		_update_team_marker()
		_update_health_label()
		return
	_eat_countdown -= delta
	if state in [State.IDLE, State.WALK] and _eat_countdown <= 0.0:
		_set_state(State.EAT)
		return
	match state:
		State.IDLE:
			_update_idle(delta)
		State.WALK:
			_update_walk(delta)
		State.EAT:
			_update_eat(delta)
		State.FLEE:
			_update_flee(delta)
	_update_team_marker()
	_update_health_label()


func impact(effect: String, strength: float, attacker_team: String = "") -> bool:
	if network_proxy or destroyed or housed_in_chop or strength < 0.0:
		_pending_attacker_peer_id = 0
		return false
	if not owner_team.is_empty() and attacker_team == owner_team:
		_pending_attacker_peer_id = 0
		return false
	if strength > 0.0:
		_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
			attacker_team, _pending_attacker_peer_id
		)
	_pending_attacker_peer_id = 0
	var normalized_effect := effect.strip_edges().to_lower()
	match normalized_effect:
		"flame", "fire":
			flame_remaining = maxf(flame_remaining, 3.0)
		"freeze", "ice":
			freeze_remaining = maxf(freeze_remaining, 2.0)
		TranquilizerBullet.EFFECT_TRANQUILIZER:
			tranquilizer_remaining = maxf(tranquilizer_remaining, 8.0)
		"trap":
			trap_remaining = maxf(
				trap_remaining,
				CombatBalance.get_float("farm_livestock", "trap_duration", 2.0)
			)
		"labeled", "labelled":
			labeled_remaining = maxf(labeled_remaining, 6.0)
	_apply_damage(strength)
	_update_labeled_outline()
	return true


func impact_from_peer(effect: String, strength: float, attacker_team: String, attacker_peer_id: int) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	return impact(effect, strength, attacker_team)


func apply_knockback(direction: Vector3, strength: float) -> void:
	if network_proxy or destroyed or housed_in_chop or strength <= 0.0:
		return
	var horizontal := Vector3(direction.x, 0.0, direction.z)
	if horizontal.length_squared() <= 0.001:
		return
	_knockback_velocity = (_knockback_velocity + horizontal.normalized() * strength * 0.18).limit_length(3.5)


func can_be_attacked_by_wildlife() -> bool:
	return not destroyed and not housed_in_chop and current_hp > 0.0


func get_growth_progress() -> float:
	if maturity_seconds <= 0.0:
		return 100.0
	return clampf(growth_elapsed_seconds / maturity_seconds * 100.0, 0.0, 100.0)


func is_mature() -> bool:
	return get_growth_progress() >= 99.999


func can_be_milked() -> bool:
	return produces_milk and not destroyed and current_hp > 0.0 and is_mature() \
		and milk_charges_remaining > 0


func consume_milk_charge() -> bool:
	if not can_be_milked():
		return false
	milk_charges_remaining = maxi(0, milk_charges_remaining - 1)
	return true


func can_be_slaughtered() -> bool:
	return not destroyed and current_hp > 0.0 and is_mature()


func can_player_pick_up(player: Node) -> bool:
	if destroyed or housed_in_chop or current_hp <= 0.0 or owner_team.is_empty():
		return false
	return is_instance_valid(player) and str(player.get("team")) == owner_team


func get_interaction_hint(_player: Node = null) -> String:
	return "[E] 抱起%s" % display_name


func _create_interaction_area() -> void:
	_interaction_area = Area3D.new()
	_interaction_area.name = "LivestockInteractionArea"
	_interaction_area.collision_layer = 0
	_interaction_area.collision_mask = GameAuthority.COLLISION_LAYER_CHARACTER
	_interaction_area.monitoring = true
	_interaction_area.monitorable = false
	_interaction_area.add_to_group("livestock_interaction_areas")
	var shape_node := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 3.0
	shape_node.shape = shape
	_interaction_area.add_child(shape_node)
	add_child(_interaction_area)


func receive_wildlife_attack(damage: float, attacker_position: Vector3) -> bool:
	if not can_be_attacked_by_wildlife() or damage <= 0.0:
		return false
	_apply_damage(damage)
	_begin_flee(attacker_position)
	return true


func get_network_state() -> Dictionary:
	return {
		"animal_id": animal_id,
		"scene_path": scene_file_path,
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"hp": current_hp,
		"max_hp": max_hp,
		"state": STATE_NAMES.get(state, "idle"),
		"animation": "Idle" if _is_immobilized() else str(STATE_ANIMATIONS.get(state, &"Idle")),
		"animation_speed": 1.0 if _is_immobilized() else 1.35 if state == State.FLEE else 1.0,
		"owner_team": owner_team,
		"housed_in_chop": housed_in_chop,
		"flame_remaining": flame_remaining,
		"freeze_remaining": freeze_remaining,
		"tranquilizer_remaining": tranquilizer_remaining,
		"trap_remaining": trap_remaining,
		"labeled_remaining": labeled_remaining,
		"milk_charges_remaining": milk_charges_remaining,
		"milk_countdown": milk_countdown,
	}


func get_low_frequency_growth_state() -> Dictionary:
	return {
		"animal_id": animal_id,
		"growth_progress": roundi(get_growth_progress()),
		"mature": is_mature(),
		"milk_charges_remaining": milk_charges_remaining,
		"milk_countdown": milk_countdown,
	}


func get_persistent_state() -> Dictionary:
	return {
		"animal_id": animal_id,
		"scene_path": scene_file_path,
		"species_id": species_id,
		"owner_team": owner_team,
		"position": global_position,
		"yaw": rotation.y,
		"home_position": home_position,
		"current_hp": current_hp,
		"max_hp": max_hp,
		"growth_progress": get_growth_progress(),
		"maturity_seconds": maturity_seconds,
		"milk_charges_remaining": milk_charges_remaining,
		"milk_countdown": milk_countdown,
		"naturally_spawned": naturally_spawned,
	}


func apply_network_growth_state(data: Dictionary) -> void:
	if not network_proxy:
		return
	var progress := clampf(float(data.get("growth_progress", get_growth_progress())), 0.0, 100.0)
	growth_elapsed_seconds = progress * maturity_seconds / 100.0
	if produces_milk:
		milk_charges_remaining = clampi(int(data.get("milk_charges_remaining", milk_charges_remaining)), 0, 3)
		milk_countdown = maxf(0.0, float(data.get("milk_countdown", milk_countdown)))
	_update_health_label()


func apply_network_state(data: Dictionary) -> void:
	network_proxy = true
	var position_value: Variant = data.get("position", global_position)
	if position_value is Vector3:
		global_position = global_position.lerp(position_value as Vector3, 0.55)
	rotation.y = lerp_angle(rotation.y, float(data.get("yaw", rotation.y)), 0.55)
	var velocity_value: Variant = data.get("velocity", Vector3.ZERO)
	if velocity_value is Vector3:
		velocity = velocity_value
	owner_team = str(data.get("owner_team", owner_team))
	max_hp = float(data.get("max_hp", max_hp))
	current_hp = clampf(float(data.get("hp", current_hp)), 0.0, max_hp)
	housed_in_chop = bool(data.get("housed_in_chop", false))
	flame_remaining = maxf(0.0, float(data.get("flame_remaining", 0.0)))
	freeze_remaining = maxf(0.0, float(data.get("freeze_remaining", 0.0)))
	tranquilizer_remaining = maxf(0.0, float(data.get("tranquilizer_remaining", 0.0)))
	trap_remaining = maxf(0.0, float(data.get("trap_remaining", 0.0)))
	labeled_remaining = maxf(0.0, float(data.get("labeled_remaining", 0.0)))
	if produces_milk:
		milk_charges_remaining = clampi(int(data.get("milk_charges_remaining", milk_charges_remaining)), 0, 3)
		milk_countdown = maxf(0.0, float(data.get("milk_countdown", milk_countdown)))
	destroyed = current_hp <= 0.0
	state = int(NETWORK_STATES.get(str(data.get("state", "idle")), State.IDLE)) as State
	if animation_player != null:
		animation_player.speed_scale = float(data.get("animation_speed", 1.0))
	_play_animation(StringName(str(data.get("animation", "Idle"))))
	_update_team_marker()
	_update_labeled_outline()
	_update_health_label()


func _update_idle(delta: float) -> void:
	_stop_horizontal(delta)
	if housed_in_chop:
		return
	if _state_elapsed >= _state_duration:
		_choose_roam_target()
		_set_state(State.WALK)


func _update_walk(delta: float) -> void:
	if housed_in_chop:
		_set_state(State.IDLE)
		return
	if _horizontal_distance_to(_move_target) <= 0.6 or _state_elapsed >= _state_duration:
		_set_state(State.IDLE)
		return
	_move_horizontal(_horizontal_direction_to(_move_target), walk_speed, delta)


func _update_eat(delta: float) -> void:
	_stop_horizontal(delta)
	current_hp = minf(max_hp, current_hp + max_hp * 0.04 * delta)
	if _state_elapsed >= _state_duration:
		_eat_countdown = _rng.randf_range(12.0, 24.0)
		_set_state(State.IDLE)


func _update_flee(delta: float) -> void:
	if housed_in_chop:
		_set_state(State.IDLE)
		return
	if _horizontal_distance_to(_move_target) <= 0.8 or _state_elapsed >= _state_duration:
		_set_state(State.IDLE)
		return
	_move_horizontal(_horizontal_direction_to(_move_target), flee_speed, delta)


func _tick_effects(delta: float) -> void:
	var flame_tick := minf(delta, flame_remaining)
	flame_remaining = maxf(0.0, flame_remaining - delta)
	freeze_remaining = maxf(0.0, freeze_remaining - delta)
	tranquilizer_remaining = maxf(0.0, tranquilizer_remaining - delta)
	trap_remaining = maxf(0.0, trap_remaining - delta)
	labeled_remaining = maxf(0.0, labeled_remaining - delta)
	if flame_tick > 0.0:
		_apply_damage(10.0 * flame_tick)
	if _is_immobilized():
		velocity.x = 0.0
		velocity.z = 0.0
	_update_labeled_outline()


func _is_immobilized() -> bool:
	return freeze_remaining > 0.0 or tranquilizer_remaining > 0.0 or trap_remaining > 0.0


func _tick_growth(delta: float) -> void:
	if destroyed or maturity_seconds <= 0.0 or growth_elapsed_seconds >= maturity_seconds:
		return
	growth_elapsed_seconds = minf(maturity_seconds, growth_elapsed_seconds + delta)


func _tick_milk_production(delta: float) -> void:
	if not produces_milk or destroyed:
		return
	if not is_mature():
		_milk_cycle_initialized = false
		milk_charges_remaining = 0
		milk_countdown = milk_interval_seconds
		return
	if not _milk_cycle_initialized:
		_milk_cycle_initialized = true
		milk_charges_remaining = 3
		milk_countdown = milk_interval_seconds
		return
	milk_countdown = maxf(0.0, milk_countdown - delta)
	if milk_countdown > 0.0:
		return
	milk_charges_remaining = 3
	milk_countdown = milk_interval_seconds


func _tick_egg_laying(delta: float) -> void:
	if not lays_eggs or destroyed or not is_mature():
		return
	_egg_countdown -= delta
	if _egg_countdown > 0.0:
		return
	_egg_countdown = maxf(1.0, egg_interval_seconds)
	var egg_id := "golden_egg" if _rng.randf() < golden_egg_chance else "egg"
	if housed_in_chop and not owner_team.is_empty():
		GlobalVar.add_item(
			owner_team, egg_id, IngredientCatalog.get_pickup_unit_kg(egg_id)
		)
		return
	GameAuthority.spawn_nature_resource_drops(global_position, [{
		"item_id": egg_id,
		"count": 1,
		"weight_kg": IngredientCatalog.get_pickup_unit_kg(egg_id),
	}])


func _apply_damage(amount: float) -> void:
	if destroyed or housed_in_chop or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	if current_hp <= 0.0:
		_die()
	else:
		var attacker_position := _attacker_position()
		_begin_flee(attacker_position)
	_update_health_label()


func _attacker_position() -> Vector3:
	if _last_attacker_peer_id > 0:
		var value: Variant = GameAuthority.get_authoritative_player_position(_last_attacker_peer_id)
		if value is Vector3:
			return value as Vector3
	return global_position - Vector3(cos(rotation.y), 0.0, sin(rotation.y))


func _begin_flee(threat_position: Vector3) -> void:
	if housed_in_chop or destroyed:
		return
	var away := global_position - threat_position
	away.y = 0.0
	if away.length_squared() <= 0.001:
		var angle := _rng.randf_range(0.0, TAU)
		away = Vector3(cos(angle), 0.0, sin(angle))
	var requested := global_position + away.normalized() * _rng.randf_range(5.0, 8.0)
	_move_target = _clamp_to_home(requested)
	_set_state(State.FLEE)


func _choose_roam_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var radius := sqrt(_rng.randf()) * roaming_radius
	_move_target = home_position + Vector3(cos(angle), 0.0, sin(angle)) * radius
	_move_target.y = global_position.y


func _clamp_to_home(target: Vector3) -> Vector3:
	var offset := target - home_position
	offset.y = 0.0
	if offset.length() > roaming_radius:
		offset = offset.normalized() * roaming_radius
	return Vector3(home_position.x + offset.x, global_position.y, home_position.z + offset.z)


func _move_horizontal(direction: Vector3, speed: float, delta: float) -> void:
	if freeze_remaining > 0.0 or tranquilizer_remaining > 0.0:
		_stop_horizontal(delta)
		return
	var horizontal_step := direction * speed + _knockback_velocity
	var proposed := global_position + Vector3(horizontal_step.x, 0.0, horizontal_step.z) * delta
	if WaterBody3D.is_navigation_blocked(proposed):
		# Livestock cannot navigate into water; players can still carry them.
		direction = Vector3.ZERO
		_knockback_velocity.x = 0.0
		_knockback_velocity.z = 0.0
	_face_direction(direction, delta)
	velocity.x = direction.x * speed + _knockback_velocity.x
	velocity.z = direction.z * speed + _knockback_velocity.z
	_apply_gravity(delta)
	move_and_slide()
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 14.0 * delta)


func _stop_horizontal(delta: float) -> void:
	velocity.x = _knockback_velocity.x
	velocity.z = _knockback_velocity.z
	_apply_gravity(delta)
	move_and_slide()
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, 14.0 * delta)


func _apply_gravity(delta: float) -> void:
	velocity.y = -1.0 if is_on_floor() else velocity.y - 24.0 * delta


func _face_direction(direction: Vector3, delta: float) -> void:
	if direction.length_squared() <= 0.001:
		return
	var target_yaw := atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0))


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
	match state:
		State.IDLE:
			_state_duration = _rng.randf_range(2.5, 6.0)
		State.WALK:
			_state_duration = _rng.randf_range(4.0, 9.0)
		State.EAT:
			_state_duration = _rng.randf_range(3.0, 5.0)
		State.FLEE:
			_state_duration = 3.5
		State.DEAD:
			_state_duration = CombatBalance.get_float("farm_livestock", "death_visible_seconds", 4.0)
	if animation_player != null:
		animation_player.speed_scale = 1.35 if state == State.FLEE else 1.0
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


func _resolve_animation_name(requested: StringName) -> StringName:
	if animation_player.has_animation(requested):
		return requested
	var requested_lower := str(requested).to_lower()
	for candidate in animation_player.get_animation_list():
		var candidate_lower := str(candidate).to_lower()
		if candidate_lower == requested_lower or candidate_lower.ends_with("/" + requested_lower):
			return candidate
	return &""


func _configure_animation_loops() -> void:
	if animation_player == null:
		return
	for requested in [&"Idle", &"Walk", &"Eat"]:
		var animation_name := _resolve_animation_name(requested)
		if not animation_name.is_empty():
			var animation := animation_player.get_animation(animation_name)
			if animation != null:
				animation.loop_mode = Animation.LOOP_LINEAR
	var death_name := _resolve_animation_name(&"Death")
	if not death_name.is_empty():
		var death_animation := animation_player.get_animation(death_name)
		if death_animation != null:
			death_animation.loop_mode = Animation.LOOP_NONE


func _die() -> void:
	destroyed = true
	velocity = Vector3.ZERO
	_set_collision_enabled(false)
	_set_state(State.DEAD)
	_update_labeled_outline()
	# Maturity gates deliberate slaughter, but combat deaths must still produce meat.
	if GameAuthority.is_server_authority() or GameAuthority.is_local_authority():
		GameAuthority.spawn_nature_resource_drops(global_position, [{
			"item_id": meat_item_id,
			"count": meat_drop_count,
			"weight_kg": IngredientCatalog.get_pickup_unit_kg(meat_item_id),
		}])


func _on_hit_body_entered(body: Node3D) -> void:
	if network_proxy or GameAuthority.should_send_network_requests() or destroyed or housed_in_chop:
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
		GameAuthority.show_local_hit_marker_for_team(attacker_team)


func _apply_housing_state() -> void:
	if housed_in_chop and state in [State.WALK, State.FLEE, State.DEAD]:
		_set_state(State.IDLE)
	var authoritative_body := not destroyed and not network_proxy and not GameAuthority.is_client_proxy()
	_set_collision_enabled(authoritative_body and not housed_in_chop, authoritative_body and housed_in_chop)


func _set_collision_enabled(enabled: bool, ground_only := false) -> void:
	collision_layer = GameAuthority.COLLISION_LAYER_WILD_ANIMAL if enabled else 0
	collision_mask = GameAuthority.WILD_ANIMAL_BODY_MASK if enabled \
		else GameAuthority.COLLISION_LAYER_GROUND if ground_only else 0
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", not enabled and not ground_only)
	if hit_area != null:
		hit_area.collision_layer = GameAuthority.COLLISION_LAYER_WILD_ANIMAL if enabled else 0
		hit_area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET if enabled else 0
		hit_area.set_deferred("monitoring", enabled)
		hit_area.set_deferred("monitorable", enabled)


func _update_health_label() -> void:
	if health_label == null:
		return
	health_label.visible = not housed_in_chop
	if housed_in_chop:
		return
	var housing := " | CHOP" if housed_in_chop else ""
	health_label.text = "%s [%s%s]\n成长: %d%% %s\nHP: %d / %d" % [
		display_name,
		str(STATE_NAMES.get(state, "idle")).to_upper(),
		housing,
		roundi(get_growth_progress()),
		"(已成熟)" if is_mature() else "",
		ceili(current_hp),
		ceili(max_hp),
	]


func _create_team_marker() -> void:
	_team_marker = MeshInstance3D.new()
	_team_marker.name = "LivestockTeamMarker"
	_team_marker.position = Vector3.UP * marker_height
	_team_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_team_marker.ignore_occlusion_culling = true
	var box := BoxMesh.new()
	box.size = Vector3(0.24, 0.24, 0.24)
	_team_marker.mesh = box
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.emission_enabled = true
	material.emission_energy_multiplier = 2.5
	_team_marker.material_override = material
	add_child(_team_marker)
	_update_team_marker()


func _update_team_marker() -> void:
	if not is_instance_valid(_team_marker):
		return
	var viewer_team := ""
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			viewer_team = str((node as GamePlayer).team)
			break
	_team_marker.visible = not destroyed and not owner_team.is_empty() and viewer_team == owner_team
	var color := Color("#F04455") if owner_team == "red" else Color("#398CFF")
	var material := _team_marker.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = color
		material.emission = color


func _update_labeled_outline() -> void:
	if mesh_root == null:
		return
	var visible := not destroyed and labeled_remaining > 0.0
	var overlay: Material = _get_labeled_outline_material() if visible else null
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
	_labeled_outline_material.albedo_color = Color(0.0, 0.0, 0.0, 0.94)
	_labeled_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_labeled_outline_material.grow = true
	_labeled_outline_material.grow_amount = 0.04
	_labeled_outline_material.render_priority = 120
	return _labeled_outline_material


func _exit_tree() -> void:
	if is_instance_valid(home_generator) and home_generator.has_method("on_animal_removed"):
		home_generator.call("on_animal_removed", self)
