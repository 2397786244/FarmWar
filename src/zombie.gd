extends CharacterBody3D
class_name Zombie

## Zombie is intentionally independent from the Squad/AI-player system. Its
## authoritative state machine uses the shared navigation map but never runs on
## visual network proxies.

const PLAYER_SPEED_REFERENCE := GamePlayer.SPEED
const MALE_HP := 120.0
const FEMALE_HP := 80.0
const MALE_SPEED := PLAYER_SPEED_REFERENCE * 0.80
const FEMALE_SPEED := PLAYER_SPEED_REFERENCE * 0.90
const DEFAULT_DEATH_CLEANUP_SECONDS := 10.0
const DEFAULT_FLAME_DURATION := 3.0
const DEFAULT_FLAME_DAMAGE_PER_SECOND := 15.0
const DEFAULT_FREEZE_DURATION := 2.0
const DEFAULT_LIGHTNING_STUN_DURATION := 2.0
const RIGHT_EYE_GLOW_COLOR := Color(1.0, 0.0, 0.0, 1.0)
const RIGHT_EYE_GLOW_ENERGY := 4.0
const RIGHT_EYE_GLOW_RANGE := 0.7
## Temporary combat diagnostics: prints HEAD/BODY and the resolved collider path
## on every authoritative zombie hit so host-side headshot routing is visible.
const DEBUG_HIT_LOG := true
## The visual scan is a full 3D sphere.  Targets in the front 120 degree
## sector are identified immediately; targets elsewhere build awareness.
const VISION_DISTANCE := 20.0
const VISION_HALF_ANGLE_DEGREES := 60.0
const TARGET_LOSE_DISTANCE := 60.0
const OCCLUDED_TARGET_DISTANCE := 40.0
const ATTACK_DISTANCE := 2.3
const ATTACK_DAMAGE := 20.0
const TARGET_SCAN_INTERVAL := 0.20
const NAVIGATION_REFRESH_INTERVAL := 0.25
const NAVIGATION_REPATH_DISTANCE := 0.5
const CHASE_PATH_WAIT_SECONDS := 0.75
const WANDER_MIN_DISTANCE := 5.0
const WANDER_MAX_DISTANCE := 10.0
const WANDER_ARRIVAL_DISTANCE := 0.8
const STUCK_JUMP_DELAY := 0.35
const JUMP_COOLDOWN := 1.5
const JUMP_VELOCITY := GamePlayer.JUMP_VELOCITY
const TARGET_RAY_MASK := GameAuthority.COLLISION_LAYER_WALL \
	| GameAuthority.COLLISION_LAYER_CHARACTER \
	| GameAuthority.COLLISION_LAYER_TOOL \
	| GameAuthority.COLLISION_LAYER_BUILDING \
	| GameAuthority.COLLISION_LAYER_VEHICLES \
	| GameAuthority.COLLISION_LAYER_NATURE_RESOURCE \
	| GameAuthority.COLLISION_LAYER_WILD_ANIMAL

enum State {
	IDLE,
	WANDER,
	CHASE,
	ATTACK,
	ATTACK_FINISH,
	JUMP,
	DEAD,
}

const STATE_NAMES := {
	State.IDLE: "idle", State.WANDER: "wander", State.CHASE: "chase",
	State.ATTACK: "attack", State.ATTACK_FINISH: "attack_finish",
	State.JUMP: "jump", State.DEAD: "dead",
}

@export_enum("male", "female") var zombie_gender := "male"
@export var male_visual_scene_path := "res://assets/characters/ZombieMale.glb"
@export var female_visual_scene_path := "res://assets/characters/ZombieFemale.glb"
@export_range(0.0, 10000.0, 1.0) var male_max_hp := MALE_HP
@export_range(0.0, 10000.0, 1.0) var female_max_hp := FEMALE_HP
@export_range(0.0, 60.0, 0.1) var death_cleanup_seconds := DEFAULT_DEATH_CLEANUP_SECONDS
@export_range(0.0, 30.0, 0.1) var flame_duration := DEFAULT_FLAME_DURATION
@export_range(0.0, 1000.0, 0.1) var flame_damage_per_second := DEFAULT_FLAME_DAMAGE_PER_SECOND
@export_range(0.0, 30.0, 0.1) var freeze_duration := DEFAULT_FREEZE_DURATION
@export_range(0.0, 30.0, 0.1) var lightning_stun_duration := DEFAULT_LIGHTNING_STUN_DURATION
@export_category("Vision Awareness")
@export_range(0.01, 1.0, 0.01) var peripheral_awareness_far_per_second := 0.08
@export_range(0.1, 4.0, 0.05) var peripheral_awareness_near_per_second := 1.20
@export_range(0.05, 1.0, 0.05) var rear_awareness_multiplier := 0.35
@export_range(0.0, 10.0, 0.1) var awareness_memory_seconds := 1.5
@export_range(0.05, 4.0, 0.05) var awareness_decay_per_second := 0.60
@export_category("Navigation Diagnostics")
## Temporarily enabled by default while Zombie locomotion is being integrated.
## It is throttled and can be disabled per scene once cooptest is confirmed.
@export var navigation_debug_enabled := true
@export_range(0.2, 5.0, 0.1) var navigation_debug_interval := 0.75
@export var network_proxy := false

var zombie_id := ""
## The wild-animal replicator uses this common field when it creates a proxy.
var animal_id := ""
var home_generator: Node = null
var max_hp := MALE_HP
var current_hp := MALE_HP
var movement_speed := MALE_SPEED
var destroyed := false
var interest_sleeping := false
var freeze_remaining := 0.0
var flame_remaining := 0.0
var stun_remaining := 0.0
var state: State = State.IDLE

var _death_remaining := 0.0
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0
var _pending_attacker_node: Node3D = null
var _pending_weapon_bullet := false
var _flame_attacker_peer_id := 0
var _processed_projectiles: Dictionary = {}
var _processed_projectile_headshots: Dictionary = {}
var _pending_headshot := false
var _pending_hit_collider: Node = null
var _visual_gender := ""
var _mesh_root: Node3D
var _animation_player: AnimationPlayer
var _hit_area: Area3D
var _head_area: Area3D
var _right_eye_light: OmniLight3D
var _right_eye_glow_material: StandardMaterial3D
var _right_eye_meshes: Array[MeshInstance3D] = []
var _navigation_agent: NavigationAgent3D
var _jump_lower_probe: RayCast3D
var _jump_upper_probe: RayCast3D
var _target_node: Node3D = null
var _target_player_peer_id := 0
var _wander_target := Vector3.ZERO
var _idle_remaining := 0.0
var _target_scan_remaining := 0.0
var _navigation_refresh_remaining := 0.0
var _wander_path_wait_remaining := 0.0
var _chase_path_wait_remaining := 0.0
var _last_navigation_goal := Vector3.INF
var _using_direct_chase_fallback := false
var _navigation_debug_remaining := 0.0
var _target_awareness: Dictionary = {}
var _target_awareness_last_seen_msec: Dictionary = {}
var _stuck_remaining := 0.0
var _jump_cooldown_remaining := 0.0
var _attack_hit_applied := false
var _attack_animation_length := 0.0
var _attack_elapsed := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_configure_gender_stats()
	_ensure_visual_for_gender()
	_cache_collision_nodes()
	_configure_collision()
	add_to_group("wild_animals")
	add_to_group("zombies")
	if zombie_id.is_empty():
		zombie_id = animal_id if not animal_id.is_empty() else str(get_path())
	if animal_id.is_empty():
		animal_id = zombie_id
	if _hit_area != null and not _hit_area.body_entered.is_connected(_on_hit_area_body_entered):
		_hit_area.body_entered.connect(_on_hit_area_body_entered)
	if _head_area != null and not _head_area.body_entered.is_connected(_on_head_area_body_entered):
		_head_area.body_entered.connect(_on_head_area_body_entered)
	_configure_animation_loops()
	_ensure_runtime_navigation_nodes()
	_rng.seed = hash(zombie_id) if not zombie_id.is_empty() else get_instance_id()
	_begin_idle()
	_set_collision_enabled(not network_proxy and not GameAuthority.is_client_proxy())
	_play_idle_animation()
	_debug_navigation("ready", false)


func _process(delta: float) -> void:
	_prune_projectile_contacts()
	if not destroyed:
		return
	if network_proxy:
		_death_remaining = maxf(0.0, _death_remaining - delta)
		if _death_remaining <= 0.0:
			queue_free()


func _physics_process(delta: float) -> void:
	if network_proxy or GameAuthority.is_client_proxy():
		return
	if destroyed:
		_death_remaining = maxf(0.0, _death_remaining - delta)
		if _death_remaining <= 0.0:
			queue_free()
		return
	_tick_status_effects(delta)
	_jump_cooldown_remaining = maxf(0.0, _jump_cooldown_remaining - delta)
	if interest_sleeping:
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("interest-sleep", false)
		return
	if _is_immobilized():
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("immobilized", false)
		return
	_tick_target_scan(delta)
	_tick_state(delta)
	_debug_navigation("physics", _navigation_agent != null and not _navigation_agent.is_navigation_finished())


func can_enter_interest_sleep() -> bool:
	return not destroyed


func set_interest_sleeping(value: bool) -> void:
	if destroyed:
		return
	interest_sleeping = value
	velocity = Vector3.ZERO
	if value:
		_clear_target()
		state = State.IDLE
		_play_idle_animation()
		_debug_navigation("interest-sleep-enter", false, true)
	else:
		_debug_navigation("interest-sleep-leave", false, true)


func get_combat_team() -> String:
	return "zombie"


func get_speed() -> float:
	return movement_speed


func is_dead() -> bool:
	return destroyed


func impact(effect: String, strength: float, attacker_team: String = "") -> bool:
	if network_proxy or destroyed or strength <= 0.0:
		_pending_attacker_peer_id = 0
		_pending_attacker_node = null
		_pending_weapon_bullet = false
		return false
	if attacker_team.to_lower() == "zombie":
		_pending_attacker_peer_id = 0
		_pending_attacker_node = null
		_pending_weapon_bullet = false
		return false
	if not attacker_team.is_empty():
		_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
			attacker_team, _pending_attacker_peer_id
		)
	_pending_attacker_peer_id = 0
	var retaliation_node := _pending_attacker_node
	var retaliation_peer_id := _last_attacker_peer_id
	var should_retaliate := _pending_weapon_bullet
	_pending_attacker_node = null
	_pending_weapon_bullet = false

	var normalized_effect := effect.strip_edges().to_lower()
	match normalized_effect:
		"freeze", "ice":
			freeze_remaining = maxf(freeze_remaining, freeze_duration)
		"flame", "fire":
			flame_remaining = maxf(flame_remaining, flame_duration)
			_flame_attacker_peer_id = _last_attacker_peer_id
		"lightening", "lightning":
			stun_remaining = maxf(stun_remaining, lightning_stun_duration)
		"tranquilizer", "sleep":
			freeze_remaining = maxf(freeze_remaining, freeze_duration)
		"bug", "bug_storm":
			pass
		_:
			pass
	var headshot := _pending_headshot
	var hit_collider := _pending_hit_collider
	_pending_headshot = false
	_pending_hit_collider = null
	_debug_log_hit(hit_collider, headshot, normalized_effect, strength, attacker_team)
	if headshot:
		# A valid Head3D hit is an immediate fatal hit, independent of the
		# projectile's numeric damage. Body hits continue through normal HP
		# subtraction below.
		_begin_death(true)
	else:
		var damage := strength
		if normalized_effect == "bug_storm":
			damage = CombatBalance.get_bug_storm_impact_damage(strength)
		_apply_damage(damage)
	if not destroyed and should_retaliate:
		_try_set_retaliation_target(retaliation_node, retaliation_peer_id)
	return true


func impact_from_peer(
	effect: String, strength: float, attacker_team: String, attacker_peer_id: int
) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	_pending_weapon_bullet = _pending_weapon_bullet or _is_weapon_hit_effect(effect)
	return impact(effect, strength, attacker_team)


func get_network_state() -> Dictionary:
	return {
		"animal_id": animal_id if not animal_id.is_empty() else zombie_id,
		"scene_path": "res://character/Zombie.tscn",
		"zombie_gender": zombie_gender,
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"hp": current_hp,
		"max_hp": max_hp,
		"destroyed": destroyed,
		"state": STATE_NAMES.get(State.DEAD if destroyed else state, "idle"),
		"animation": "Death" if destroyed else _network_animation_name(),
		"flame_remaining": flame_remaining,
		"freeze_remaining": freeze_remaining,
		"stun_remaining": stun_remaining,
		"death_remaining": _death_remaining,
	}


func apply_network_state(data: Dictionary) -> void:
	network_proxy = true
	var incoming_gender := str(data.get("zombie_gender", zombie_gender)).to_lower()
	if incoming_gender in ["male", "female"] and incoming_gender != zombie_gender:
		zombie_gender = incoming_gender
		_configure_gender_stats()
		_ensure_visual_for_gender()
		_cache_collision_nodes()
		_configure_animation_loops()

	var position_value: Variant = data.get("position", global_position)
	if position_value is Vector3:
		global_position = position_value as Vector3
	rotation.y = float(data.get("yaw", rotation.y))
	var velocity_value: Variant = data.get("velocity", Vector3.ZERO)
	if velocity_value is Vector3:
		velocity = velocity_value
	max_hp = maxf(0.0, float(data.get("max_hp", max_hp)))
	current_hp = clampf(float(data.get("hp", current_hp)), 0.0, max_hp)
	flame_remaining = maxf(0.0, float(data.get("flame_remaining", 0.0)))
	freeze_remaining = maxf(0.0, float(data.get("freeze_remaining", 0.0)))
	stun_remaining = maxf(0.0, float(data.get("stun_remaining", 0.0)))
	var incoming_destroyed := bool(data.get("destroyed", false))
	if incoming_destroyed and not destroyed:
		_begin_death(false)
	if incoming_destroyed:
		_death_remaining = maxf(0.0, float(data.get("death_remaining", _death_remaining)))
		_play_death_animation()
	else:
		var incoming_state := str(data.get("state", "idle"))
		_apply_proxy_animation(incoming_state, str(data.get("animation", "Idle")))


func _configure_gender_stats() -> void:
	if zombie_gender.to_lower() == "female":
		zombie_gender = "female"
		max_hp = maxf(0.0, female_max_hp)
		movement_speed = FEMALE_SPEED
	else:
		zombie_gender = "male"
		max_hp = maxf(0.0, male_max_hp)
		movement_speed = MALE_SPEED
	if current_hp <= 0.0 or _visual_gender.is_empty():
		current_hp = max_hp
	else:
		current_hp = clampf(current_hp, 0.0, max_hp)


func _ensure_visual_for_gender() -> void:
	var requested_gender := "female" if zombie_gender.to_lower() == "female" else "male"
	if _visual_gender == requested_gender and is_instance_valid(_mesh_root):
		_setup_right_eye_glow()
		return
	var current_mesh := find_child("Mesh", true, false) as Node3D
	var parent := current_mesh.get_parent() if current_mesh != null else self
	var saved_transform := current_mesh.transform if current_mesh != null else Transform3D.IDENTITY
	if current_mesh != null:
		current_mesh.free()
	var visual_path := female_visual_scene_path if requested_gender == "female" else male_visual_scene_path
	var packed := load(visual_path) as PackedScene
	if packed == null:
		_mesh_root = null
		_animation_player = null
		_visual_gender = requested_gender
		_setup_right_eye_glow()
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		_mesh_root = null
		_animation_player = null
		_visual_gender = requested_gender
		_setup_right_eye_glow()
		return
	visual.name = "Mesh"
	parent.add_child(visual)
	visual.transform = saved_transform
	_mesh_root = visual
	_animation_player = visual.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_visual_gender = requested_gender
	_setup_right_eye_glow()


func _setup_right_eye_glow() -> void:
	# RightEye belongs to the imported gender-specific model. Always resolve it
	# recursively from that model so both ZombieMale and ZombieFemale are
	# supported without changing the GLB files.
	for old_mesh in _right_eye_meshes:
		if is_instance_valid(old_mesh) and old_mesh.material_overlay == _right_eye_glow_material:
			old_mesh.material_overlay = null
	_right_eye_meshes.clear()
	_right_eye_light = null
	if _mesh_root == null or not is_instance_valid(_mesh_root):
		return
	var right_eye := _mesh_root.find_child("RightEye", true, false) as Node3D
	if right_eye == null:
		push_warning("Zombie: could not find RightEye recursively in %s." % _mesh_root.name)
		return

	if _right_eye_glow_material == null or not is_instance_valid(_right_eye_glow_material):
		_right_eye_glow_material = StandardMaterial3D.new()
		_right_eye_glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_right_eye_glow_material.albedo_color = RIGHT_EYE_GLOW_COLOR
		_right_eye_glow_material.emission_enabled = true
		_right_eye_glow_material.emission = RIGHT_EYE_GLOW_COLOR
		_right_eye_glow_material.emission_energy_multiplier = RIGHT_EYE_GLOW_ENERGY

	var eye_meshes: Array[MeshInstance3D] = []
	if right_eye is MeshInstance3D:
		eye_meshes.append(right_eye as MeshInstance3D)
	for child_value in right_eye.find_children("*", "MeshInstance3D", true, false):
		if child_value is MeshInstance3D:
			eye_meshes.append(child_value as MeshInstance3D)
	for eye_mesh in eye_meshes:
		eye_mesh.material_overlay = _right_eye_glow_material
		_right_eye_meshes.append(eye_mesh)

	var glow_light := right_eye.find_child("ZombieRightEyeGlow", true, false) as OmniLight3D
	if glow_light == null:
		glow_light = OmniLight3D.new()
		glow_light.name = "ZombieRightEyeGlow"
		right_eye.add_child(glow_light)
	glow_light.position = Vector3.ZERO
	glow_light.light_color = RIGHT_EYE_GLOW_COLOR
	glow_light.light_energy = 1.6
	glow_light.light_indirect_energy = 0.0
	glow_light.omni_range = RIGHT_EYE_GLOW_RANGE
	glow_light.shadow_enabled = false
	glow_light.visible = not destroyed
	_right_eye_light = glow_light


func _cache_collision_nodes() -> void:
	_hit_area = find_child("Hit3D", true, false) as Area3D
	_head_area = find_child("Head3D", true, false) as Area3D


func _configure_collision() -> void:
	# The root and Head3D use the regular character/AI layer for authoritative
	# raycasts. Hit3D remains a projectile-monitoring area only; both areas listen
	# for projectile bodies on layer 32 through their collision mask.
	collision_layer = GameAuthority.COLLISION_LAYER_CHARACTER
	collision_mask = 647 | GameAuthority.COLLISION_LAYER_VEHICLES
	for area in [_hit_area, _head_area]:
		if area == null:
			continue
		# Hit3D is a projectile-monitoring Area only. Head3D also exposes the
		# character layer so authoritative hitscan/raycast weapons can tell a
		# head hit from the root body collider. Both still listen for projectile
		# bodies through the bullet mask below.
		area.collision_layer = (
			GameAuthority.COLLISION_LAYER_CHARACTER
			if area == _head_area else 0
		)
		area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET
		area.monitoring = true
		area.monitorable = true


func _set_collision_enabled(enabled: bool) -> void:
	collision_layer = GameAuthority.COLLISION_LAYER_CHARACTER if enabled else 0
	collision_mask = (647 | GameAuthority.COLLISION_LAYER_VEHICLES) if enabled else 0
	for shape_value in find_children("*", "CollisionShape3D", true, false):
		var shape := shape_value as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", not enabled)
	for area in [_hit_area, _head_area]:
		if area == null:
			continue
		area.collision_layer = (
			GameAuthority.COLLISION_LAYER_CHARACTER
			if enabled and area == _head_area else 0
		)
		area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET if enabled else 0
		area.set_deferred("monitoring", enabled)
		area.set_deferred("monitorable", enabled)


func _on_hit_area_body_entered(body: Node3D) -> void:
	_on_hit_body_entered(body, false)


func _on_head_area_body_entered(body: Node3D) -> void:
	_on_hit_body_entered(body, true)


func _on_hit_body_entered(body: Node3D, headshot := false) -> void:
	if network_proxy or destroyed or GameAuthority.should_send_network_requests():
		return
	if body == null or not body.has_method("get_bullet_owner"):
		return
	var projectile_id := body.get_instance_id()
	var now := Time.get_ticks_msec()
	var previous_contact_time := int(_processed_projectiles.get(projectile_id, -1000000))
	if previous_contact_time + 250 > now:
		# Hit3D and Head3D can overlap at the neck. Do not apply the body hit a
		# second time, but allow a later Head3D callback from the same projectile
		# to upgrade that contact to the intended fatal headshot.
		if not headshot or bool(_processed_projectile_headshots.get(projectile_id, false)):
			return
	_processed_projectiles[projectile_id] = now
	_processed_projectile_headshots[projectile_id] = headshot
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
	# Autonomous-device laser contacts are intentionally excluded. Physical
	# firearm projectiles retain their team/peer provenance for retaliation.
	_pending_weapon_bullet = not (body is DetectLaserBullet)
	_pending_headshot = headshot
	_pending_hit_collider = _head_area if headshot else _hit_area
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, attacker_team, -1, attacker_peer_id
	))
	_pending_headshot = false
	_pending_hit_collider = null
	if applied:
		GameAuthority.show_local_hit_marker_for_team(attacker_team)


## Called by the shared authoritative collider path. Keeping the head/body
## distinction here means hitscan and physical projectiles still use the same
## impact() entry point and the same hit-confirmation event.
func impact_from_collider(
	collider: Node,
	effect: String,
	strength: float,
	attacker_team: String = "",
	attacker_peer_id: int = 0,
	attacker_node: Node3D = null
) -> bool:
	# Physical projectile callbacks already mark the pending head hit before
	# they enter _apply_hit_to_collider with the Zombie root. Raycasts arrive
	# here with Head3D itself, so preserve either source of that information.
	var collider_is_head := _is_head_collider(collider)
	_pending_headshot = _pending_headshot or collider_is_head
	if collider_is_head or _pending_hit_collider == null:
		_pending_hit_collider = collider
	_pending_attacker_node = attacker_node
	_pending_weapon_bullet = _pending_weapon_bullet or _is_weapon_hit_effect(effect)
	var applied := false
	if attacker_peer_id > 0 and has_method("impact_from_peer"):
		applied = bool(impact_from_peer(effect, strength, attacker_team, attacker_peer_id))
	else:
		applied = impact(effect, strength, attacker_team)
	_pending_headshot = false
	_pending_hit_collider = null
	return applied


func _is_head_collider(collider: Node) -> bool:
	if collider == null or _head_area == null:
		return false
	return collider == _head_area or _head_area.is_ancestor_of(collider)


func _debug_log_hit(
	collider: Node,
	headshot: bool,
	effect: String,
	strength: float,
	attacker_team: String
) -> void:
	if not DEBUG_HIT_LOG:
		return
	var collider_path := "<callback>"
	if collider != null and is_instance_valid(collider):
		collider_path = str(collider.get_path())
	print(
		"[ZombieHitDebug] zombie=%s gender=%s part=%s collider=%s "
		+ "effect=%s damage=%.2f attacker_team=%s attacker_peer=%d hp_before=%.2f",
		zombie_id,
		zombie_gender,
		"HEAD" if headshot else "BODY",
		collider_path,
		effect,
		strength,
		attacker_team,
		_last_attacker_peer_id,
		current_hp
	)


func _ensure_runtime_navigation_nodes() -> void:
	_navigation_agent = get_node_or_null("ZombieNavigationAgent") as NavigationAgent3D
	if _navigation_agent == null:
		_navigation_agent = NavigationAgent3D.new()
		_navigation_agent.name = "ZombieNavigationAgent"
		add_child(_navigation_agent)
	_navigation_agent.radius = 0.34
	_navigation_agent.height = 1.7
	_navigation_agent.path_desired_distance = 0.45
	_navigation_agent.target_desired_distance = WANDER_ARRIVAL_DISTANCE
	_navigation_agent.avoidance_enabled = true
	_navigation_agent.neighbor_distance = 4.0
	_navigation_agent.max_speed = movement_speed

	_jump_lower_probe = _ensure_ray_probe("ZombieJumpLowerProbe", Vector3(0.0, 0.45, 0.0))
	_jump_upper_probe = _ensure_ray_probe("ZombieJumpUpperProbe", Vector3(0.0, 1.25, 0.0))


func _ensure_ray_probe(node_name: String, local_origin: Vector3) -> RayCast3D:
	var probe := get_node_or_null(node_name) as RayCast3D
	if probe == null:
		probe = RayCast3D.new()
		probe.name = node_name
		probe.exclude_parent = true
		add_child(probe)
	probe.position = local_origin
	probe.target_position = Vector3(0.0, 0.0, -0.9)
	probe.collision_mask = TARGET_RAY_MASK
	probe.enabled = true
	return probe


func _begin_idle() -> void:
	state = State.IDLE
	_wander_target = Vector3.ZERO
	_wander_path_wait_remaining = 0.0
	_idle_remaining = _rng.randf_range(3.0, 7.0)
	velocity = Vector3.ZERO
	_play_idle_animation()


func _tick_state(delta: float) -> void:
	if state == State.ATTACK or state == State.ATTACK_FINISH:
		_tick_attack(delta)
		return
	if state == State.JUMP:
		_tick_jump(delta)
		return
	if _has_valid_target():
		state = State.CHASE
		_tick_navigation_move(delta, _target_position(), true)
		return
	if state == State.CHASE:
		_begin_idle()
	if state == State.IDLE:
		_idle_remaining -= delta
		if _idle_remaining <= 0.0:
			_begin_wander()
		return
	if state == State.WANDER:
		if _wander_target == Vector3.ZERO:
			_begin_idle()
			return
		_tick_navigation_move(delta, _wander_target, false)


func _begin_wander() -> void:
	if not _navigation_is_ready():
		_begin_idle()
		return
	for attempt in range(12):
		var angle := _rng.randf_range(0.0, TAU)
		var distance := _rng.randf_range(WANDER_MIN_DISTANCE, WANDER_MAX_DISTANCE)
		var candidate := global_position + Vector3(cos(angle) * distance, 0.0, sin(angle) * distance)
		var closest := NavigationServer3D.map_get_closest_point(_navigation_agent.get_navigation_map(), candidate)
		if closest.distance_to(candidate) > 2.0:
			continue
		_navigation_agent.target_position = closest
		# NavigationAgent3D builds its first path on a later physics update.
		# Calling is_navigation_finished() immediately here always reports the
		# freshly-reset path as finished and previously kept every zombie idle.
		_wander_target = closest
		_wander_path_wait_remaining = 0.5
		state = State.WANDER
		return
	_begin_idle()


func _tick_target_scan(delta: float) -> void:
	_target_scan_remaining -= delta
	if _target_scan_remaining > 0.0:
		return
	_target_scan_remaining = TARGET_SCAN_INTERVAL
	if _has_valid_target():
		if _should_drop_target():
			_clear_target()
		return
	var best_target: Node3D = null
	var best_peer_id := 0
	var best_distance := INF
	var now_msec := Time.get_ticks_msec()
	for candidate in _target_candidates():
		var node := candidate.get("node", null) as Node3D
		var peer_id := int(candidate.get("peer_id", 0))
		var position := _candidate_position(node, peer_id)
		if position == Vector3.INF:
			continue
		# Vision is intentionally a sphere: a target above or below a zombie
		# still consumes the same 20m detection budget.
		var distance := global_position.distance_to(position)
		if distance > VISION_DISTANCE or distance >= best_distance:
			continue
		if not _has_clear_line_to(position, node, false, peer_id):
			continue
		if not _is_candidate_aware(node, peer_id, position, now_msec):
			continue
		best_target = node
		best_peer_id = peer_id
		best_distance = distance
	_decay_unseen_target_awareness(now_msec)
	if best_target != null or best_peer_id > 0:
		_set_target(best_target, best_peer_id)


func _target_candidates() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is Node3D and _is_alive_player_candidate(node as Node3D):
			result.append({"node": node, "peer_id": _player_peer_id(node as Node)})
	for group_name in [&"future_warrior_ai", &"farmer_ai", &"assistant_ai", &"wild_animals"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D and _is_valid_node_target(node as Node3D):
				result.append({"node": node, "peer_id": 0})
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		var close_to_chassis := vehicle.get_horizontal_distance_to_chassis(
			global_position
		) <= ATTACK_DISTANCE + 1.0
		if vehicle.current_hp > 0.0 and not vehicle.is_spawn_drop_active() \
				and (absf(vehicle.current_speed) > 0.15 or close_to_chassis):
			result.append({"node": vehicle, "peer_id": 0})
	return result


func _is_valid_node_target(node: Node3D) -> bool:
	if node == self or not is_instance_valid(node) or node.is_in_group("zombies"):
		return false
	if node is AINormalDrone:
		return false
	if node is VehicleBase:
		# Only moving vehicles can be acquired from the ordinary vision scan, but
		# a vehicle already locked by the zombie remains a valid melee target.
		return node == _target_node and float((node as VehicleBase).current_hp) > 0.0
	if node is BlackBear:
		return not bool((node as BlackBear).destroyed)
	if node is FarmLivestock:
		return not bool((node as FarmLivestock).destroyed)
	if node is FutureWarriorAI:
		return int((node as FutureWarriorAI).state) != FutureWarriorAI.AIState.DEAD
	if node is FarmerAI:
		return int((node as FarmerAI).state) != FarmerAI.AIState.DEAD
	if node is AssistantAI:
		return not bool((node as AssistantAI).is_dead)
	return node.has_method("impact") and node is CharacterBody3D


func _is_alive_player_candidate(node: Node3D) -> bool:
	var peer_id := _player_peer_id(node)
	if peer_id <= 0:
		return false
	var player_state: Dictionary = GameAuthority.player_states.get(peer_id, {})
	return float(player_state.get("hp", 0.0)) > 0.0 and float(player_state.get("respawn_left", 0.0)) <= 0.0


func _player_peer_id(node: Node) -> int:
	if node is GamePlayer:
		return int((node as GamePlayer).authority_peer_id)
	if node is ServerPlayerPhysicsBody:
		return int((node as ServerPlayerPhysicsBody).peer_id)
	return int(node.get_meta("authority_peer_id", 0))


func _candidate_position(node: Node3D, peer_id: int) -> Vector3:
	if peer_id > 0:
		var player_position: Variant = GameAuthority.get_authoritative_player_position(peer_id)
		return player_position as Vector3 if player_position is Vector3 else Vector3.INF
	return node.global_position if is_instance_valid(node) else Vector3.INF


func _set_target(node: Node3D, peer_id := 0) -> void:
	var changed_target := node != _target_node or peer_id != _target_player_peer_id
	_target_node = node
	_target_player_peer_id = peer_id
	if changed_target:
		# NavigationAgent3D produces a path only after a later physics update.
		# Do not query its reset path during the same frame a target is assigned.
		_navigation_refresh_remaining = 0.0
		_chase_path_wait_remaining = CHASE_PATH_WAIT_SECONDS
		_last_navigation_goal = Vector3.INF
		_using_direct_chase_fallback = false


func _clear_target() -> void:
	_target_node = null
	_target_player_peer_id = 0
	_navigation_refresh_remaining = 0.0
	_chase_path_wait_remaining = 0.0
	_last_navigation_goal = Vector3.INF
	_using_direct_chase_fallback = false


func _candidate_awareness_key(node: Node3D, peer_id: int) -> String:
	return "peer:%d" % peer_id if peer_id > 0 else "node:%d" % node.get_instance_id()


func _is_candidate_aware(node: Node3D, peer_id: int, position: Vector3, now_msec: int) -> bool:
	var candidate_key := _candidate_awareness_key(node, peer_id)
	_target_awareness_last_seen_msec[candidate_key] = now_msec
	var direction := position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.0001:
		_target_awareness[candidate_key] = 1.0
		return true
	direction = direction.normalized()
	# Zombie assets use local +Z as their authored front direction.
	var facing_dot := _forward_direction().dot(direction)
	var direct_view_threshold := cos(deg_to_rad(VISION_HALF_ANGLE_DEGREES))
	if facing_dot >= direct_view_threshold:
		_target_awareness[candidate_key] = 1.0
		return true

	var distance_ratio := clampf(global_position.distance_to(position) / VISION_DISTANCE, 0.0, 1.0)
	var proximity := 1.0 - distance_ratio
	var rear_amount := clampf(
		(direct_view_threshold - facing_dot) / maxf(0.01, direct_view_threshold + 1.0),
		0.0,
		1.0
	)
	var awareness_rate := lerpf(
		peripheral_awareness_far_per_second,
		peripheral_awareness_near_per_second,
		proximity
	)
	awareness_rate *= lerpf(1.0, rear_awareness_multiplier, rear_amount)
	awareness_rate *= _rng.randf_range(0.75, 1.25)
	var awareness := clampf(
		float(_target_awareness.get(candidate_key, 0.0)) + awareness_rate * TARGET_SCAN_INTERVAL,
		0.0,
		1.0
	)
	_target_awareness[candidate_key] = awareness
	return awareness >= 1.0


func _decay_unseen_target_awareness(now_msec: int) -> void:
	var stale_keys: Array[String] = []
	for value in _target_awareness.keys():
		var candidate_key := str(value)
		var last_seen_msec := int(_target_awareness_last_seen_msec.get(candidate_key, 0))
		if now_msec - last_seen_msec <= roundi(awareness_memory_seconds * 1000.0):
			continue
		var awareness := maxf(
			0.0,
			float(_target_awareness.get(candidate_key, 0.0))
			- awareness_decay_per_second * TARGET_SCAN_INTERVAL
		)
		if awareness <= 0.0:
			stale_keys.append(candidate_key)
		else:
			_target_awareness[candidate_key] = awareness
	for candidate_key in stale_keys:
		_target_awareness.erase(candidate_key)
		_target_awareness_last_seen_msec.erase(candidate_key)


func _has_valid_target() -> bool:
	if _target_player_peer_id > 0:
		return _candidate_position(null, _target_player_peer_id) != Vector3.INF
	return _target_node != null and _is_valid_node_target(_target_node)


func _target_position() -> Vector3:
	return _candidate_position(_target_node, _target_player_peer_id)


func _should_drop_target() -> bool:
	var target_position := _target_position()
	if target_position == Vector3.INF:
		return true
	var horizontal_offset := target_position - global_position
	horizontal_offset.y = 0.0
	var distance := horizontal_offset.length()
	if distance > TARGET_LOSE_DISTANCE:
		return true
	return distance > OCCLUDED_TARGET_DISTANCE and not _has_clear_line_to(target_position, _target_node, true, _target_player_peer_id)


func _try_set_retaliation_target(node: Node3D, peer_id: int) -> void:
	if node == self or (node == null and peer_id <= 0):
		return
	var attacker_position := _candidate_position(node, peer_id)
	if attacker_position == Vector3.INF:
		return
	var offset := attacker_position - global_position
	offset.y = 0.0
	if offset.length() > TARGET_LOSE_DISTANCE:
		return
	if _has_clear_line_to(attacker_position, node, true, peer_id):
		_set_target(node, peer_id)


func _is_weapon_hit_effect(effect: String) -> bool:
	return effect.strip_edges().to_lower() in ["nail", "rubber", "flame", "freeze"]


func _has_clear_line_to(
	target_position: Vector3,
	target_node: Node3D = null,
	hard_only := false,
	target_peer_id := 0
) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * 1.2, target_position + Vector3.UP * 0.9)
	query.collision_mask = TARGET_RAY_MASK
	query.exclude = [get_rid()]
	query.collide_with_areas = true
	query.collide_with_bodies = true
	var hit := world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider: Variant = hit.get("collider", null)
	if _collider_belongs_to_target(collider, target_node, target_peer_id):
		return true
	if not hard_only:
		return false
	return not _is_hard_target_blocker(collider)


func _collider_belongs_to_target(collider: Variant, target_node: Node3D, peer_id: int) -> bool:
	var cursor := collider as Node
	while cursor != null:
		if target_node != null and cursor == target_node:
			return true
		if peer_id > 0 and _player_peer_id(cursor) == peer_id:
			return true
		cursor = cursor.get_parent()
	return false


func _is_hard_target_blocker(collider: Variant) -> bool:
	var cursor := collider as Node
	while cursor != null:
		if cursor is VehicleBase or cursor is MapDefenseFacility:
			return true
		if cursor.is_in_group("ai_demolition_target") or cursor.is_in_group("ai_navigation_obstacle"):
			return true
		cursor = cursor.get_parent()
	return collider is StaticBody3D


func _tick_navigation_move(delta: float, goal: Vector3, chase_target: bool) -> void:
	if chase_target and _is_target_in_attack_range():
		_begin_attack()
		return
	if not chase_target and _horizontal_distance_to(goal) <= WANDER_ARRIVAL_DISTANCE:
		_begin_idle()
		return
	if not _navigation_is_ready():
		if chase_target:
			_tick_direct_chase_fallback(delta, goal, "nav-map-wait")
		else:
			velocity = Vector3.ZERO
			_play_idle_animation()
		_debug_navigation("nav-map-unavailable", false)
		return
	_navigation_refresh_remaining -= delta
	var needs_repath := _last_navigation_goal == Vector3.INF \
		or _last_navigation_goal.distance_to(goal) > NAVIGATION_REPATH_DISTANCE
	if needs_repath and _navigation_refresh_remaining <= 0.0:
		_navigation_agent.target_position = goal
		_navigation_refresh_remaining = NAVIGATION_REFRESH_INTERVAL
		_last_navigation_goal = goal
		if chase_target:
			_chase_path_wait_remaining = CHASE_PATH_WAIT_SECONDS
			_using_direct_chase_fallback = false
		# The navigation server updates its route after this physics tick.  Querying
		# now would return the just-reset current position and falsely look like an
		# unreachable target.
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("path-requested", false)
		return
	var next_position := _navigation_agent.get_next_path_position()
	var direction := next_position - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		if not chase_target and _wander_path_wait_remaining > 0.0:
			_wander_path_wait_remaining = maxf(0.0, _wander_path_wait_remaining - delta)
			velocity = Vector3.ZERO
			_play_idle_animation()
			return
		if not chase_target:
			# The sampled point belongs to an unreachable island. Retry after the
			# normal idle delay instead of remaining in a permanent Walk state.
			_begin_idle()
			return
		_tick_direct_chase_fallback(delta, goal, "no-local-path")
		return
	_chase_path_wait_remaining = 0.0
	_using_direct_chase_fallback = false
	_debug_navigation("navigation-path", true)
	_face_direction(direction)
	if _should_attempt_jump(direction.normalized(), delta):
		_begin_jump()
		return
	velocity.x = direction.normalized().x * movement_speed
	velocity.z = direction.normalized().z * movement_speed
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") as float * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if _promote_blocking_vehicle_target(true):
		return
	_play_animation(&"Walk")


func _tick_direct_chase_fallback(delta: float, goal: Vector3, diagnostic_reason: String) -> void:
	# The chunk containing this zombie can be waiting for its bake while another
	# chunk has already advanced the shared navigation-map iteration.  Preserve a
	# short grace period for a normal path before making the clear-line fallback.
	if _chase_path_wait_remaining > 0.0:
		_chase_path_wait_remaining = maxf(0.0, _chase_path_wait_remaining - delta)
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("%s-wait" % diagnostic_reason, false)
		return
	# This fallback is forbidden only by hard world blockers.  Other zombies,
	# animals or players may be standing in the line immediately after several
	# generators fire; they must not make every nearby zombie remain permanently
	# idle while normal navigation is still rebuilding.
	if not _has_clear_line_to(goal, _target_node, true, _target_player_peer_id):
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("%s-blocked" % diagnostic_reason, false)
		return
	var direction := goal - global_position
	direction.y = 0.0
	if direction.length_squared() <= 0.001:
		velocity = Vector3.ZERO
		_play_idle_animation()
		return
	direction = direction.normalized()
	var next_position := global_position + direction * movement_speed * delta
	# Water has no ordinary body collision because players are allowed to enter
	# it.  The shared navigation guard closes that gap for zombie fallback motion.
	if WaterBody3D.is_navigation_blocked(next_position):
		velocity = Vector3.ZERO
		_play_idle_animation()
		_debug_navigation("%s-water" % diagnostic_reason, false)
		return
	_using_direct_chase_fallback = true
	_debug_navigation("%s-direct" % diagnostic_reason, false)
	_face_direction(direction)
	if _should_attempt_jump(direction, delta):
		_begin_jump()
		return
	velocity.x = direction.x * movement_speed
	velocity.z = direction.z * movement_speed
	if not is_on_floor():
		velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") as float * delta
	else:
		velocity.y = -0.1
	move_and_slide()
	if _promote_blocking_vehicle_target(true):
		return
	_play_animation(&"Walk")


func _navigation_is_ready() -> bool:
	return _navigation_agent != null and _navigation_agent.get_navigation_map().is_valid() \
		and NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map()) > 0


func _debug_navigation(reason: String, has_path: bool, force := false) -> void:
	if not navigation_debug_enabled:
		return
	if not force:
		_navigation_debug_remaining -= get_physics_process_delta_time()
		if _navigation_debug_remaining > 0.0:
			return
	_navigation_debug_remaining = navigation_debug_interval
	var iteration := 0
	var map_valid := false
	var navigation_finished := true
	var navigation_goal := Vector3.INF
	if _navigation_agent != null and _navigation_agent.get_navigation_map().is_valid():
		map_valid = true
		iteration = NavigationServer3D.map_get_iteration_id(_navigation_agent.get_navigation_map())
		navigation_finished = _navigation_agent.is_navigation_finished()
		navigation_goal = _navigation_agent.target_position
	var target_text := "none"
	var target_distance := -1.0
	if _has_valid_target():
		target_text = str(_target_player_peer_id) if _target_player_peer_id > 0 else str(_target_node.get_instance_id())
		target_distance = _horizontal_distance_to(_target_position())
	var collision_names: Array[String] = []
	for collision_index in get_slide_collision_count():
		var collision := get_slide_collision(collision_index)
		var collider := collision.get_collider() if collision != null else null
		if collider is Node:
			collision_names.append(str((collider as Node).get_path()))
		else:
			collision_names.append(str(collider))
	print(
		("[ZombieNav] id=%s state=%s reason=%s target=%s dist=%.2f "
		+ "pos=%s sleep=%s freeze=%.2f stun=%.2f map=%s iter=%d finished=%s path=%s "
		+ "fallback=%s goal=%s velocity=%s last_motion=%s floor=%s collisions=%s process=%s") % [
			zombie_id,
			STATE_NAMES.get(state, "unknown"),
			reason,
			target_text,
			target_distance,
			global_position,
			interest_sleeping,
			freeze_remaining,
			stun_remaining,
			map_valid,
			iteration,
			navigation_finished,
			has_path,
			_using_direct_chase_fallback,
			navigation_goal,
			velocity,
			get_last_motion(),
			is_on_floor(),
			", ".join(collision_names),
			is_physics_processing(),
		]
	)


func _should_attempt_jump(direction: Vector3, delta: float) -> bool:
	if _jump_cooldown_remaining > 0.0 or not is_on_floor() or _jump_lower_probe == null or _jump_upper_probe == null:
		return false
	_jump_lower_probe.force_raycast_update()
	_jump_upper_probe.force_raycast_update()
	if not _jump_lower_probe.is_colliding() or _jump_upper_probe.is_colliding():
		_stuck_remaining = 0.0
		return false
	_stuck_remaining += delta
	return _stuck_remaining >= STUCK_JUMP_DELAY


func _begin_jump() -> void:
	state = State.JUMP
	_stuck_remaining = 0.0
	_jump_cooldown_remaining = JUMP_COOLDOWN
	velocity.y = JUMP_VELOCITY
	_play_animation(&"JumpStart")


func _tick_jump(delta: float) -> void:
	velocity.y -= ProjectSettings.get_setting("physics/3d/default_gravity") as float * delta
	move_and_slide()
	_promote_blocking_vehicle_target(false)
	if is_on_floor() and velocity.y <= 0.0:
		_play_animation(&"JumpLand")
		state = State.CHASE if _has_valid_target() else State.WANDER
		return
	_play_animation(&"JumpLoop")


func _begin_attack() -> void:
	state = State.ATTACK
	velocity = Vector3.ZERO
	_attack_elapsed = 0.0
	_attack_hit_applied = false
	_attack_animation_length = _animation_length(&"Attack")
	_play_animation(&"Attack")


func _tick_attack(delta: float) -> void:
	velocity = Vector3.ZERO
	var target_position := _target_position()
	if target_position != Vector3.INF:
		_face_direction(target_position - global_position)
	if state == State.ATTACK:
		_attack_elapsed += delta
		if not _attack_hit_applied and _attack_elapsed >= _attack_animation_length * 0.55:
			_attack_hit_applied = true
			if _has_valid_target() and _is_target_in_attack_range():
				_apply_attack_damage()
		if _attack_elapsed >= _attack_animation_length:
			state = State.ATTACK_FINISH
			_attack_elapsed = 0.0
			_attack_animation_length = _animation_length(&"AttackFinish")
			_play_animation(&"AttackFinish")
		return
	_attack_elapsed += delta
	if _attack_elapsed >= _attack_animation_length:
		state = State.CHASE if _has_valid_target() else State.IDLE
		if state == State.IDLE:
			_begin_idle()


func _apply_attack_damage() -> void:
	if _target_player_peer_id > 0:
		var direction := _target_position() - global_position
		GameAuthority.damage_player_from_wild_animal(_target_player_peer_id, global_position, ATTACK_DAMAGE, ATTACK_DISTANCE, direction)
		return
	if _target_node != null and is_instance_valid(_target_node) and _target_node.has_method("impact"):
		var damaged := bool(_target_node.call(
			"impact", "zombie_melee", ATTACK_DAMAGE, "zombie"
		))
		if damaged and _target_node is VehicleBase:
			(_target_node as VehicleBase).receive_melee_push(
				global_position,
				ATTACK_DAMAGE,
				get_instance_id()
			)


func _is_target_in_attack_range() -> bool:
	if not _has_valid_target():
		return false
	if _target_node is VehicleBase:
		return (_target_node as VehicleBase).get_horizontal_distance_to_chassis(
			global_position
		) <= ATTACK_DISTANCE
	return _horizontal_distance_to(_target_position()) <= ATTACK_DISTANCE


## A parked vehicle is intentionally not a long-range vision target, but it
## must become the target when it physically blocks a zombie that is walking.
## This prevents the zombie from endlessly pressing against the chassis while
## continuing to chase something on the other side.
func _promote_blocking_vehicle_target(begin_attack_when_close: bool) -> bool:
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var vehicle := _vehicle_from_collider(collision.get_collider())
		if vehicle == null or vehicle.current_hp <= 0.0 or vehicle.is_spawn_drop_active():
			continue
		_set_target(vehicle, 0)
		if begin_attack_when_close and _is_target_in_attack_range():
			_begin_attack()
		return true
	return false


func _vehicle_from_collider(collider: Variant) -> VehicleBase:
	var cursor := collider as Node
	while cursor != null:
		if cursor is VehicleBase:
			return cursor as VehicleBase
		cursor = cursor.get_parent()
	return null


func _horizontal_distance_to(position: Vector3) -> float:
	var offset := position - global_position
	offset.y = 0.0
	return offset.length()


func _forward_direction() -> Vector3:
	# Zombie model assets are authored with +Z as the face direction.
	var forward := global_transform.basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.001 else Vector3.FORWARD


func _face_direction(direction: Vector3) -> void:
	direction.y = 0.0
	if direction.length_squared() > 0.001:
		look_at(global_position + direction, Vector3.UP, true)


func _animation_length(requested: StringName) -> float:
	var animation_name := _resolve_animation_name(requested)
	if _animation_player == null or animation_name.is_empty():
		return 0.5
	var animation := _animation_player.get_animation(animation_name)
	return maxf(0.1, animation.length) if animation != null else 0.5


func _network_animation_name() -> String:
	match state:
		State.WANDER, State.CHASE: return "Walk"
		State.ATTACK: return "Attack"
		State.ATTACK_FINISH: return "AttackFinish"
		State.JUMP: return "JumpLoop"
		_: return "Idle"


func _apply_proxy_animation(incoming_state: String, animation: String) -> void:
	if incoming_state == "dead":
		_play_death_animation()
		return
	_play_animation(StringName(animation if not animation.is_empty() else "Idle"))


func _tick_status_effects(delta: float) -> void:
	var flame_tick := minf(maxf(0.0, delta), flame_remaining)
	flame_remaining = maxf(0.0, flame_remaining - delta)
	freeze_remaining = maxf(0.0, freeze_remaining - delta)
	stun_remaining = maxf(0.0, stun_remaining - delta)
	if flame_tick > 0.0:
		_last_attacker_peer_id = _flame_attacker_peer_id
		_apply_damage(flame_damage_per_second * flame_tick)
	if flame_remaining <= 0.0:
		_flame_attacker_peer_id = 0


func _is_immobilized() -> bool:
	return freeze_remaining > 0.0 or stun_remaining > 0.0


func _apply_damage(amount: float) -> void:
	if destroyed or amount <= 0.0:
		return
	current_hp = maxf(0.0, current_hp - amount)
	if current_hp <= 0.0:
		_begin_death(true)


func _begin_death(_reward_kill: bool) -> void:
	if destroyed:
		return
	destroyed = true
	state = State.DEAD
	_clear_target()
	current_hp = 0.0
	velocity = Vector3.ZERO
	freeze_remaining = 0.0
	flame_remaining = 0.0
	stun_remaining = 0.0
	_flame_attacker_peer_id = 0
	_death_remaining = maxf(0.0, death_cleanup_seconds)
	_set_collision_enabled(false)
	_play_death_animation()


func _play_idle_animation() -> void:
	_play_animation(&"Idle")


func _play_death_animation() -> void:
	_play_animation(&"Death")


func _play_animation(requested: StringName) -> void:
	if _animation_player == null:
		return
	var animation_name := _resolve_animation_name(requested)
	if animation_name.is_empty():
		return
	if _animation_player.current_animation == animation_name and _animation_player.is_playing():
		return
	_animation_player.play(animation_name, 0.12)


func _configure_animation_loops() -> void:
	if _animation_player == null:
		return
	for requested in [&"Idle", &"Walk", &"JumpLoop"]:
		var animation_name := _resolve_animation_name(requested)
		if animation_name.is_empty():
			continue
		var animation := _animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
	for requested in [&"Attack", &"AttackFinish", &"JumpStart", &"JumpLand", &"Death"]:
		var animation_name := _resolve_animation_name(requested)
		if animation_name.is_empty():
			continue
		var animation := _animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_NONE


func _resolve_animation_name(requested: StringName) -> StringName:
	if _animation_player == null:
		return &""
	if _animation_player.has_animation(requested):
		return requested
	var requested_lower := str(requested).to_lower()
	for candidate in _animation_player.get_animation_list():
		var candidate_lower := str(candidate).to_lower()
		if candidate_lower == requested_lower or candidate_lower.ends_with("/" + requested_lower):
			return candidate
	return &""


func _prune_projectile_contacts() -> void:
	var now := Time.get_ticks_msec()
	for id_value in _processed_projectiles.keys():
		if int(_processed_projectiles[id_value]) + 1000 < now:
			_processed_projectiles.erase(id_value)
			_processed_projectile_headshots.erase(id_value)
