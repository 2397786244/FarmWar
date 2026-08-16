extends CharacterBody3D
class_name Zombie

## Zombie is intentionally independent from the Squad/AI-player system.
## It currently stays in place and only exposes the common impact() entry point
## used by hitscan, projectiles, explosions and status-effect tools.

const PLAYER_SPEED_REFERENCE := GamePlayer.SPEED
const MALE_HP := 200.0
const FEMALE_HP := 100.0
const MALE_SPEED := PLAYER_SPEED_REFERENCE * 0.40
const FEMALE_SPEED := PLAYER_SPEED_REFERENCE * 0.80
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

var _death_remaining := 0.0
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0
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
	_set_collision_enabled(not network_proxy and not GameAuthority.is_client_proxy())
	_play_idle_animation()


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
	velocity = Vector3.ZERO
	# Zombies currently have no locomotion. Freeze/stun still records and
	# exposes the immobilized state so future movement can use the same gate.
	if not _is_immobilized():
		_play_idle_animation()


func can_enter_interest_sleep() -> bool:
	return not destroyed


func set_interest_sleeping(value: bool) -> void:
	if destroyed:
		return
	interest_sleeping = value
	velocity = Vector3.ZERO
	if value:
		_play_idle_animation()


func get_combat_team() -> String:
	return "zombie"


func get_speed() -> float:
	return movement_speed


func is_dead() -> bool:
	return destroyed


func impact(effect: String, strength: float, attacker_team: String = "") -> bool:
	if network_proxy or destroyed or strength <= 0.0:
		_pending_attacker_peer_id = 0
		return false
	if attacker_team.to_lower() == "zombie":
		_pending_attacker_peer_id = 0
		return false
	if not attacker_team.is_empty():
		_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
			attacker_team, _pending_attacker_peer_id
		)
	_pending_attacker_peer_id = 0

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
	return true


func impact_from_peer(
	effect: String, strength: float, attacker_team: String, attacker_peer_id: int
) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
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
		"state": "dead" if destroyed else "idle",
		"animation": "Death" if destroyed else "Idle",
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
		_play_idle_animation()


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
	collision_mask = 647
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
	collision_mask = 647 if enabled else 0
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
	for requested in [&"Idle", &"Walk"]:
		var animation_name := _resolve_animation_name(requested)
		if animation_name.is_empty():
			continue
		var animation := _animation_player.get_animation(animation_name)
		if animation != null:
			animation.loop_mode = Animation.LOOP_LINEAR
	var death_name := _resolve_animation_name(&"Death")
	if not death_name.is_empty():
		var death_animation := _animation_player.get_animation(death_name)
		if death_animation != null:
			death_animation.loop_mode = Animation.LOOP_NONE


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
