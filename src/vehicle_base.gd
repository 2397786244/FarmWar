extends CharacterBody3D
class_name VehicleBase

signal vehicle_destroyed()
signal vehicle_damaged(current_hp: float, max_hp: float)
signal cargo_manifest_changed(manifest: Array[Dictionary])
signal spawn_drop_finished(success: bool)
signal topple_state_changed(toppled: bool)

const GROUND_COLLISION_LAYER := 1
const BULLET_COLLISION_LAYER := 32
const COMBAT_BALANCE := preload("res://src/combat_balance.gd")
const VEHICLE_EXPLOSION_SCENE := preload("res://character/weapons/VehicleExplosion.tscn")
const VEHICLE_SHIELD_SCENE := preload("res://character/weapons/VehicleShieldBubble.tscn")
const CARGO_CAR_DEBUG := preload("res://src/cargo_car_debug.gd")
const NETWORK_INTERPOLATION_RATE := 18.0
const NETWORK_SNAP_DISTANCE := 6.0
const CARGO_SLOT_COUNT := 12
const WILD_ANIMAL_COLLISION_LAYER := 32768
const TOOL_COLLISION_LAYER := 128
const NATURE_RESOURCE_COLLISION_LAYER := 16384
const DEFAULT_SPAWN_DROP_TIMEOUT := 3.0
const NAVIGATION_ONLY_OBSTACLE_GROUP := "ai_navigation_obstacle"
## DynamicNavigationChunkGrid intentionally discovers this canonical node
## name on every registered owner. Keep vehicles on the same convention as
## buildings and defense facilities so their AABBs enter the bake queue.
const VEHICLE_NAVIGATION_OBSTACLE_NAME := "NavigationObstacle3D"
const NAVIGATION_IDLE_SPEED_EPSILON := 0.08
const NAVIGATION_OBSTACLE_MARGIN := 0.10
## A faster vehicle earns a wider top-speed view. The configured camera_max_fov
## remains an optional per-vehicle ceiling, while the actual maximum forward
## speed determines how much of that ceiling can be reached.
const CAMERA_FOV_DEGREES_PER_MAX_SPEED := 1.5

@export var vehicle_config: VehicleConfig
@export var network_id := ""
@export var owner_team := ""
## Hand-held placement previews disable vehicle physics and world registration.
@export var vehicle_deployed := true
## Map instances can start loaded without making the mutable cargo weight a resource setting.
@export_range(0.0, 500.0, 1.0, "suffix:kg") var initial_cargo_weight_kg := 0.0

## Older vehicle scenes use one configurable box named VehicleShape. Custom
## vehicles may instead provide several direct CollisionShape3D children, so
## this node is intentionally optional.
@onready var vehicle_shape := get_node_or_null("VehicleShape") as CollisionShape3D
@onready var ground_probe := $GroundProbe as RayCast3D
@onready var driver_seat := $DriverSeat as Node3D
@onready var camera_orbit_yaw := $CameraOrbitYaw as Node3D
@onready var camera_orbit_pitch := $CameraOrbitYaw/CameraOrbitPitch as Node3D
@onready var vehicle_camera := $CameraOrbitYaw/CameraOrbitPitch/VehicleCamera as Camera3D
@onready var exit_point := $ExitPoint as Marker3D
@onready var hit_area := $Hit3D as Area3D
## Custom hit areas may contain several shapes and omit the legacy primary
## CollisionShape3D. Keep the legacy shape optional as well.
@onready var hit_shape := get_node_or_null("Hit3D/CollisionShape3D") as CollisionShape3D

var body_visual: Node3D
var driver_seat_point: Node3D
var steering_wheel: Node3D
var wheel_fl: Node3D
var wheel_fr: Node3D
var wheel_rl: Node3D
var wheel_rr: Node3D
var seat_anchors: Array[Node3D] = []
var seat_occupants: Dictionary = {}

var driver_peer_id := 0
var current_hp := 0.0
var shield_hp := 0.0
var shield_max_hp := 0.0
var shield_remaining := 0.0
var current_speed := 0.0
var current_steering := 0.0
var drive_throttle := 0.0
var drive_steering := 0.0
var drive_brake := 0.0
var wheel_spin_angle := 0.0
var cargo_weight_kg := 0.0
var cargo_manifest: Array[Dictionary] = []
var cargo_user_peer_id := 0
var toppled := false
var tip_axis := Vector3.FORWARD
var tip_angle := 0.0

var _wheel_rest_bases: Dictionary = {}
var _steering_wheel_rest_basis := Basis.IDENTITY
var _camera_orbit_yaw := 0.0
var _camera_orbit_pitch := 0.0
var _cargo_container: Node3D
var _cargo_crates: Array[Node3D] = []
var _network_has_target := false
var _network_target_position := Vector3.ZERO
var _network_target_yaw := 0.0
var _network_target_speed := 0.0
var _network_target_steering := 0.0
var _shield_visual: VehicleShieldBubble
var _last_available_cargo_slots := CARGO_SLOT_COUNT
var _network_cargo_occupied_slots: Array[int] = []
var _spawn_drop_active := false
var _spawn_drop_elapsed := 0.0
var _spawn_drop_timeout := DEFAULT_SPAWN_DROP_TIMEOUT
var _spawn_drop_landing_position := Vector3.ZERO
var _spawn_drop_collision_layer_before := 0
var _spawn_drop_collision_mask_before := 0
var _vehicle_navigation_obstacle: NavigationObstacle3D
var _vehicle_navigation_obstacle_active := false
var _external_push_velocity := Vector3.ZERO
var _active_impact_contacts: Dictionary = {}
var _topple_sources: Dictionary = {}
var _topple_force_accumulator := 0.0
var _visual_tip_angle := 0.0
var _topple_visual_applied := false
var _body_visual_unrotated_basis := Basis.IDENTITY
var _cargo_visual_unrotated_basis := Basis.IDENTITY


func _ready() -> void:
	if not vehicle_deployed:
		collision_layer = 0
		collision_mask = 0
		_set_direct_body_collision_shapes_disabled(true)
		hit_area.monitoring = false
		hit_area.monitorable = false
		return
	add_to_group("vehicle_bases")
	# All deployed VehicleBase subclasses use the same AI target path, including
	# CargoCar, SurveyRider, KitchenCar and FarmBaseVehicle.
	add_to_group("ai_combat_targets")
	_configure_physics_nodes()
	_apply_vehicle_config()
	# Vehicle scenes may use one chassis collider or multiple body colliders.
	# Build their combined navigation footprint after the config has applied its
	# final dimensions, so every drivable vehicle follows the same rule.
	call_deferred("_initialize_vehicle_navigation_obstacle")
	_create_cargo_interaction_areas()
	if not hit_area.body_entered.is_connected(_on_hit_3d_body_entered):
		hit_area.body_entered.connect(_on_hit_3d_body_entered)


func _physics_process(delta: float) -> void:
	if vehicle_config == null:
		return
	if GameAuthority.is_client_proxy():
		_tick_vehicle_shield(delta)
		_interpolate_network_state(delta)
		return
	if GameAuthority.is_local_authority() or GameAuthority.is_server_authority():
		return
	simulate_authority(delta)


func _exit_tree() -> void:
	# The navigation grid keeps a separate registry. Explicitly remove this
	# vehicle before its node is released so the old affected chunks are rebuilt.
	_unregister_vehicle_navigation_obstacle()


func set_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
	drive_throttle = clampf(throttle, -1.0, 1.0)
	drive_steering = clampf(steering, -1.0, 1.0)
	drive_brake = clampf(brake, 0.0, 1.0)


## Subclasses can override these accessors for temporary vehicle modules such
## as FarmBaseVehicle's NitroBoost without mutating the shared VehicleConfig.
func get_max_forward_speed() -> float:
	return vehicle_config.max_forward_speed if vehicle_config != null else 0.0


func get_max_reverse_speed() -> float:
	return vehicle_config.max_reverse_speed if vehicle_config != null else 0.0


## Visual destruction variants are selected here so every VehicleBase subclass
## gets the same one-shot explosion path. TwoWheelVehicleBase overrides this
## with a shorter plume and a smaller ground shockwave.
func get_destruction_effect_variant() -> String:
	return "four_wheel"


func get_destruction_effect_radius() -> float:
	return COMBAT_BALANCE.get_float("vehicle_explosion", "radius_four_wheel", 8.5)


func get_destruction_effect_damage() -> float:
	return COMBAT_BALANCE.get_float("vehicle_explosion", "damage", 500.0)


func get_destruction_effect_knockback() -> float:
	return COMBAT_BALANCE.get_float("vehicle_explosion", "knockback", 30.0)


## Returns the speed-dependent driving FOV used by every VehicleBase subclass.
## Forward maximum speed is intentionally read through get_max_forward_speed()
## so temporary upgrades such as NitroBoost affect the view immediately.
func get_camera_fov_for_speed(speed: float) -> float:
	if vehicle_config == null:
		return 72.0
	var base_fov := vehicle_config.camera_base_fov
	var configured_max_fov := maxf(vehicle_config.camera_max_fov, base_fov)
	var speed_based_max_fov := base_fov + maxf(get_max_forward_speed(), 0.0) \
		* CAMERA_FOV_DEGREES_PER_MAX_SPEED
	var max_fov := minf(configured_max_fov, speed_based_max_fov)
	var speed_ratio := clampf(absf(speed) / maxf(get_max_forward_speed(), 0.01), 0.0, 1.0)
	return lerpf(base_fov, max_fov, speed_ratio)


func simulate_authority(delta: float) -> void:
	if not vehicle_deployed or vehicle_config == null or not is_inside_tree() \
			or is_queued_for_deletion() or get_world_3d() == null:
		return
	if _spawn_drop_active:
		_simulate_spawn_drop(delta)
		_refresh_vehicle_navigation_obstacle()
		return
	_tick_vehicle_shield(delta)
	_tick_external_push(delta)
	if toppled:
		drive_throttle = 0.0
		drive_steering = 0.0
		drive_brake = 1.0
	var target_speed := get_max_forward_speed() * maxf(drive_throttle, 0.0)
	if drive_throttle < 0.0:
		target_speed = get_max_reverse_speed() * drive_throttle
	if drive_brake > 0.01:
		current_speed = move_toward(
			current_speed,
			0.0,
			vehicle_config.brake_deceleration * drive_brake * delta
		)
	else:
		var speed_change := vehicle_config.acceleration if absf(target_speed) > absf(current_speed) else vehicle_config.rolling_deceleration
		current_speed = move_toward(current_speed, target_speed, speed_change * delta)

	var speed_ratio := clampf(absf(current_speed) / maxf(get_max_forward_speed(), 0.01), 0.0, 1.0)
	var max_steering: float = lerpf(
		deg_to_rad(vehicle_config.max_steering_angle_degrees),
		deg_to_rad(vehicle_config.min_steering_angle_degrees),
		speed_ratio
	)
	current_steering = move_toward(
		current_steering,
		drive_steering * max_steering,
		vehicle_config.steering_response * delta
	)
	var turn_angle := _vehicle_turn_angle()
	# Preserve the signed longitudinal speed: reverse steering must mirror the
	# vehicle yaw so S/A reverses left and S/D reverses right.
	var yaw_rate := current_speed / maxf(vehicle_config.wheel_base, 0.01) * tan(turn_angle)
	rotation.y += yaw_rate * delta

	var forward := global_transform.basis * vehicle_config.forward_axis
	forward.y = 0.0
	forward = forward.normalized()
	var drive_velocity := forward * current_speed
	velocity.x = drive_velocity.x + _external_push_velocity.x
	velocity.z = drive_velocity.z + _external_push_velocity.z
	ground_probe.force_raycast_update()
	if ground_probe.is_colliding():
		velocity.y = -vehicle_config.ground_stick_speed
	else:
		var gravity_strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var gravity_direction_value: Variant = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
		var gravity_direction := gravity_direction_value as Vector3 if gravity_direction_value is Vector3 else Vector3.DOWN
		velocity += gravity_direction.normalized() * gravity_strength * delta
	move_and_slide()
	_process_vehicle_slide_impacts(drive_velocity)
	rotation.x = 0.0
	rotation.z = 0.0
	_update_vehicle_presentation(delta)
	_refresh_vehicle_navigation_obstacle()


func _process_vehicle_slide_impacts(drive_velocity: Vector3) -> void:
	var now_msec := Time.get_ticks_msec()
	var rearm_msec := int(COMBAT_BALANCE.get_float(
		"vehicle_impact", "contact_rearm_seconds", 0.30
	) * 1000.0)
	for contact_key_value: Variant in _active_impact_contacts.keys():
		if now_msec - int(_active_impact_contacts[contact_key_value]) > rearm_msec:
			_active_impact_contacts.erase(contact_key_value)
	if toppled or _spawn_drop_active or current_hp <= 0.0:
		return
	var minimum_speed := COMBAT_BALANCE.get_float("vehicle_impact", "minimum_speed", 2.0)
	var processed_this_frame: Dictionary = {}
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var collider := collision.get_collider()
		if collider == null or not is_instance_valid(collider):
			continue
		var impact_target := _vehicle_impact_target_node(collider)
		var normal := collision.get_normal()
		# Only an upward contact with a non-damageable world body is floor support.
		# Capsule-shaped actors and animals often produce an upward-slanted normal
		# when struck by a bumper, so they must keep a horizontal impact normal.
		if normal.y > 0.55 and impact_target == null:
			continue
		if impact_target != null:
			normal.y = 0.0
			if normal.length_squared() <= 0.001 and impact_target is Node3D:
				normal = global_position - (impact_target as Node3D).global_position
				normal.y = 0.0
		if normal.length_squared() <= 0.001:
			continue
		normal = normal.normalized()
		var contact_key := _vehicle_impact_contact_key(collider)
		if contact_key <= 0 or processed_this_frame.has(contact_key):
			continue
		processed_this_frame[contact_key] = true
		if _active_impact_contacts.has(contact_key):
			continue
		var collider_velocity := collision.get_collider_velocity()
		if impact_target is CharacterBody3D:
			collider_velocity = (impact_target as CharacterBody3D).velocity
		var closing_speed := maxf(
			0.0,
			-(drive_velocity - collider_velocity).dot(normal)
		)
		if closing_speed < minimum_speed:
			continue
		_active_impact_contacts[contact_key] = now_msec
		var result := GameAuthority.apply_authoritative_vehicle_impact(
			self,
			impact_target if impact_target != null else collider,
			collision.get_position(),
			normal,
			closing_speed
		)
		if bool(result.get("accepted", false)):
			current_speed *= COMBAT_BALANCE.get_float(
				"vehicle_impact", "impact_speed_retention", 0.35
			)


func _vehicle_impact_contact_key(collider: Variant) -> int:
	if not collider is Node:
		return 0
	var best := _vehicle_impact_target_node(collider)
	if best == null:
		best = collider as Node
	if best == self or is_ancestor_of(best):
		return 0
	var peer_id := GameAuthority.get_authority_player_peer_id(best)
	if peer_id > 0:
		if seat_occupants.values().has(peer_id):
			return 0
		return 1000000000 + peer_id
	return best.get_instance_id()


func _vehicle_impact_target_node(collider: Variant) -> Node:
	if not collider is Node:
		return null
	var cursor := collider as Node
	var resolved: Node = null
	while cursor != null and cursor != self:
		if cursor is VehicleBase or cursor is CharacterBody3D \
				or cursor.has_method("impact") or cursor.has_method("impact_from_peer") \
				or cursor.is_in_group("wild_animals"):
			resolved = cursor
		cursor = cursor.get_parent()
	return resolved


func receive_melee_push(attacker_position: Vector3, force: float, source_instance_id: int) -> void:
	if GameAuthority.should_send_network_requests() or current_hp <= 0.0 \
			or _spawn_drop_active or force <= 0.0:
		return
	var push_direction := global_position - attacker_position
	push_direction.y = 0.0
	if push_direction.length_squared() <= 0.001:
		push_direction = global_transform.basis.x
	push_direction = push_direction.normalized()
	var occupied := not seat_occupants.is_empty()
	var multiplier := COMBAT_BALANCE.get_float(
		"vehicle_impact", "occupied_push_multiplier", 0.20
	) if occupied else 1.0
	var max_push_speed := COMBAT_BALANCE.get_float(
		"vehicle_impact", "occupied_push_max_speed", 0.25
	) if occupied else COMBAT_BALANCE.get_float(
		"vehicle_impact", "empty_push_max_speed", 1.2
	)
	_external_push_velocity += push_direction * force \
		* COMBAT_BALANCE.get_float("vehicle_impact", "push_velocity_per_force", 0.02) \
		* multiplier
	_external_push_velocity.y = 0.0
	_external_push_velocity = _external_push_velocity.limit_length(max_push_speed)
	if occupied or toppled or absf(current_speed) >= 0.2 or source_instance_id <= 0:
		return
	var now_msec := Time.get_ticks_msec()
	var source_state: Dictionary = _topple_sources.get(source_instance_id, {})
	source_state["last_msec"] = now_msec
	source_state["force"] = float(source_state.get("force", 0.0)) + force
	_topple_sources[source_instance_id] = source_state
	_prune_topple_sources(now_msec)
	var required_sources := COMBAT_BALANCE.get_int(
		"vehicle_impact", "topple_required_sources", 3
	)
	var required_force := COMBAT_BALANCE.get_float(
		"vehicle_impact", "topple_required_force", 60.0
	)
	if _topple_sources.size() < required_sources or _topple_force_accumulator < required_force:
		return
	var local_push := global_transform.basis.inverse() * push_direction
	var axis := Vector3(local_push.z, 0.0, -local_push.x)
	if axis.length_squared() <= 0.001:
		axis = Vector3.FORWARD
	set_toppled(true, axis.normalized())


func _tick_external_push(delta: float) -> void:
	_external_push_velocity = _external_push_velocity.move_toward(
		Vector3.ZERO,
		COMBAT_BALANCE.get_float("vehicle_impact", "push_decay", 2.5) * maxf(delta, 0.0)
	)
	_prune_topple_sources(Time.get_ticks_msec())


func _prune_topple_sources(now_msec: int) -> void:
	var window_msec := int(COMBAT_BALANCE.get_float(
		"vehicle_impact", "topple_window_seconds", 3.0
	) * 1000.0)
	_topple_force_accumulator = 0.0
	for source_value: Variant in _topple_sources.keys():
		var source_state: Dictionary = _topple_sources[source_value]
		if now_msec - int(source_state.get("last_msec", 0)) > window_msec:
			_topple_sources.erase(source_value)
		else:
			_topple_force_accumulator += float(source_state.get("force", 0.0))


func set_toppled(
	value: bool,
	axis := Vector3.FORWARD,
	angle := -1.0,
	notify_authority := true
) -> bool:
	if value and (_spawn_drop_active or current_hp <= 0.0 or not seat_occupants.is_empty()):
		return false
	var changed := toppled != value
	toppled = value
	if axis.length_squared() > 0.001:
		tip_axis = axis.normalized()
	if angle >= 0.0:
		tip_angle = maxf(0.0, angle)
	else:
		tip_angle = deg_to_rad(COMBAT_BALANCE.get_float(
			"vehicle_impact", "topple_angle_degrees", 82.0
		)) if value else 0.0
	if value:
		current_speed = 0.0
		drive_throttle = 0.0
		drive_steering = 0.0
		drive_brake = 1.0
		_external_push_velocity = Vector3.ZERO
	else:
		_topple_sources.clear()
		_topple_force_accumulator = 0.0
	if changed:
		topple_state_changed.emit(toppled)
		_refresh_vehicle_navigation_obstacle(true)
		if notify_authority and (GameAuthority.is_local_authority() \
				or GameAuthority.is_server_authority()):
			GameAuthority.notify_vehicle_topple_state(self)
	return true


func can_be_uprighted() -> bool:
	return toppled and current_hp > 0.0 and not _spawn_drop_active \
		and seat_occupants.is_empty() and absf(current_speed) < 0.2


func upright_vehicle() -> bool:
	if not can_be_uprighted():
		return false
	return set_toppled(false, tip_axis)


func _update_vehicle_presentation(delta: float) -> void:
	_remove_topple_visual_transform()
	_update_vehicle_visuals(delta)
	var target_angle := tip_angle if toppled else 0.0
	var response_key := "topple_response" if toppled else "upright_response"
	var response := COMBAT_BALANCE.get_float("vehicle_impact", response_key, 7.0)
	_visual_tip_angle = move_toward(
		_visual_tip_angle,
		target_angle,
		response * maxf(delta, 0.0)
	)
	_apply_topple_visual_transform()


func _remove_topple_visual_transform() -> void:
	if not _topple_visual_applied:
		return
	if is_instance_valid(body_visual):
		body_visual.basis = _body_visual_unrotated_basis
	if is_instance_valid(_cargo_container):
		_cargo_container.basis = _cargo_visual_unrotated_basis
	_topple_visual_applied = false


func _apply_topple_visual_transform() -> void:
	if absf(_visual_tip_angle) <= 0.0001:
		return
	if is_instance_valid(body_visual):
		_body_visual_unrotated_basis = body_visual.basis
		body_visual.rotate_object_local(tip_axis, _visual_tip_angle)
	if is_instance_valid(_cargo_container):
		_cargo_visual_unrotated_basis = _cargo_container.basis
		_cargo_container.rotate_object_local(tip_axis, _visual_tip_angle)
	_topple_visual_applied = true


## Start an authority-owned delivery drop. The placement resolver has already
## checked the landing point and the hard-obstacle path; this method owns the
## short-lived physics state until the vehicle reaches the ground.
func begin_spawn_drop(landing_position: Vector3, timeout := DEFAULT_SPAWN_DROP_TIMEOUT) -> void:
	if _spawn_drop_active:
		return
	_spawn_drop_active = true
	_spawn_drop_elapsed = 0.0
	_spawn_drop_timeout = maxf(0.5, timeout)
	_spawn_drop_landing_position = landing_position
	_spawn_drop_collision_layer_before = collision_layer
	_spawn_drop_collision_mask_before = collision_mask
	# The normal vehicle mask already includes characters. Add wild animals
	# only during the drop so the fallback cannot silently pass through them.
	collision_mask = collision_mask | WILD_ANIMAL_COLLISION_LAYER
	drive_throttle = 0.0
	drive_steering = 0.0
	drive_brake = 1.0
	current_speed = 0.0
	current_steering = 0.0
	velocity = Vector3.ZERO
	_refresh_vehicle_navigation_obstacle(true)


func is_spawn_drop_active() -> bool:
	return _spawn_drop_active


func get_spawn_drop_landing_position() -> Vector3:
	return _spawn_drop_landing_position


func get_spawn_drop_remaining() -> float:
	if not _spawn_drop_active:
		return 0.0
	return maxf(0.0, _spawn_drop_timeout - _spawn_drop_elapsed)


func _simulate_spawn_drop(delta: float) -> void:
	_spawn_drop_elapsed += maxf(0.0, delta)
	_tick_vehicle_shield(delta)
	current_speed = 0.0
	current_steering = 0.0
	drive_throttle = 0.0
	drive_steering = 0.0
	drive_brake = 1.0
	velocity.x = 0.0
	velocity.z = 0.0
	var gravity_strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
	var gravity_direction_value: Variant = ProjectSettings.get_setting(
		"physics/3d/default_gravity_vector",
		Vector3.DOWN
	)
	var gravity_direction := gravity_direction_value as Vector3 \
		if gravity_direction_value is Vector3 else Vector3.DOWN
	velocity += gravity_direction.normalized() * gravity_strength * delta
	move_and_slide()
	rotation.x = 0.0
	rotation.z = 0.0
	_update_vehicle_presentation(delta)

	# Do not consider landing on the top of an AI to be a completed drop. The
	# resolver's ground height is the only valid resting height; if the dynamic
	# actor moves away, the vehicle continues falling naturally.
	var reached_ground_height := global_position.y <= _spawn_drop_landing_position.y + 0.12
	if reached_ground_height and is_on_floor():
		global_position.y = _spawn_drop_landing_position.y
		_finish_spawn_drop(true)
	elif _spawn_drop_elapsed >= _spawn_drop_timeout:
		_finish_spawn_drop(false)


func _finish_spawn_drop(success: bool) -> void:
	if not _spawn_drop_active:
		return
	_spawn_drop_active = false
	collision_layer = _spawn_drop_collision_layer_before
	collision_mask = _spawn_drop_collision_mask_before
	_spawn_drop_collision_layer_before = 0
	_spawn_drop_collision_mask_before = 0
	velocity = Vector3.ZERO
	current_speed = 0.0
	drive_throttle = 0.0
	drive_steering = 0.0
	drive_brake = 1.0
	_refresh_vehicle_navigation_obstacle(true)
	spawn_drop_finished.emit(success)


## A parked vehicle is a true navigation obstacle, while a driven, moving or
## falling vehicle must never trigger repeated navmesh rebuilds. The dynamic
## grid receives the whole vehicle footprint and determines every 64m chunk
## intersected by it (including vehicles crossing a chunk boundary).
func _initialize_vehicle_navigation_obstacle() -> void:
	if not vehicle_deployed or not is_inside_tree() or is_queued_for_deletion():
		return
	var existing := get_node_or_null(VEHICLE_NAVIGATION_OBSTACLE_NAME) as NavigationObstacle3D
	if existing != null:
		_vehicle_navigation_obstacle = existing
	else:
		var bounds_data := _vehicle_navigation_collision_bounds()
		if not bool(bounds_data.get("found", false)):
			return
		var bounds := bounds_data.get("bounds", AABB()) as AABB
		if bounds.size.x <= 0.01 or bounds.size.z <= 0.01:
			return
		var obstacle := NavigationObstacle3D.new()
		obstacle.name = VEHICLE_NAVIGATION_OBSTACLE_NAME
		obstacle.carve_navigation_mesh = true
		obstacle.position = Vector3(0.0, bounds.position.y, 0.0)
		obstacle.height = maxf(0.1, bounds.size.y)
		var min_x := bounds.position.x - NAVIGATION_OBSTACLE_MARGIN
		var max_x := bounds.end.x + NAVIGATION_OBSTACLE_MARGIN
		var min_z := bounds.position.z - NAVIGATION_OBSTACLE_MARGIN
		var max_z := bounds.end.z + NAVIGATION_OBSTACLE_MARGIN
		obstacle.vertices = PackedVector3Array([
			Vector3(min_x, 0.0, min_z),
			Vector3(max_x, 0.0, min_z),
			Vector3(max_x, 0.0, max_z),
			Vector3(min_x, 0.0, max_z),
		])
		# Start disabled: the state refresh below registers it only if the
		# vehicle is genuinely parked.
		obstacle.affect_navigation_mesh = false
		obstacle.avoidance_enabled = false
		add_child(obstacle)
		_vehicle_navigation_obstacle = obstacle
	add_to_group(NAVIGATION_ONLY_OBSTACLE_GROUP)
	_refresh_vehicle_navigation_obstacle(true)


func _vehicle_navigation_collision_bounds() -> Dictionary:
	var result := {"found": false, "bounds": AABB()}
	if vehicle_config != null and vehicle_config.collision_size.length_squared() > 0.0001:
		_merge_vehicle_navigation_bounds(
			result,
			AABB(
				vehicle_config.collision_offset - vehicle_config.collision_size * 0.5,
				vehicle_config.collision_size
			)
		)
	_collect_vehicle_navigation_collision_bounds(self, Transform3D.IDENTITY, result)
	return result


func _collect_vehicle_navigation_collision_bounds(
	node: Node,
	parent_transform: Transform3D,
	result: Dictionary
) -> void:
	if node == null or not is_instance_valid(node):
		return
	# Hit3D and attached accessories have their own CollisionObject3D roots;
	# they are combat/interaction volumes, not vehicle chassis geometry.
	if node != self and (node is Area3D or node is CollisionObject3D):
		return
	var node_transform := parent_transform
	if node is Node3D and node != self:
		node_transform = parent_transform * (node as Node3D).transform
	if node is CollisionShape3D:
		var collision_shape := node as CollisionShape3D
		if not collision_shape.disabled and collision_shape.shape != null:
			_merge_vehicle_navigation_bounds(
				result,
				_vehicle_navigation_shape_bounds(collision_shape.shape, node_transform)
			)
	elif node is CollisionPolygon3D:
		var collision_polygon := node as CollisionPolygon3D
		if not collision_polygon.disabled and not collision_polygon.polygon.is_empty() \
				and collision_polygon.depth > 0.0:
			var minimum := Vector3(INF, INF, INF)
			var maximum := Vector3(-INF, -INF, -INF)
			var half_depth := collision_polygon.depth * 0.5
			for point_2d: Vector2 in collision_polygon.polygon:
				for local_z: float in [-half_depth, half_depth]:
					var point := node_transform * Vector3(point_2d.x, point_2d.y, local_z)
					minimum = minimum.min(point)
					maximum = maximum.max(point)
			_merge_vehicle_navigation_bounds(result, AABB(minimum, maximum - minimum))
	for child: Node in node.get_children():
		_collect_vehicle_navigation_collision_bounds(child, node_transform, result)


func _vehicle_navigation_shape_bounds(shape: Shape3D, transform: Transform3D) -> AABB:
	var points: Array[Vector3] = []
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		for x: float in [-half_size.x, half_size.x]:
			for y: float in [-half_size.y, half_size.y]:
				for z: float in [-half_size.z, half_size.z]:
					points.append(transform * Vector3(x, y, z))
	elif shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		for x: float in [-radius, radius]:
			for y: float in [-radius, radius]:
				for z: float in [-radius, radius]:
					points.append(transform * Vector3(x, y, z))
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var capsule_radius := capsule.radius
		var half_capsule_height := capsule.height * 0.5
		for x: float in [-capsule_radius, capsule_radius]:
			for y: float in [-half_capsule_height, half_capsule_height]:
				for z: float in [-capsule_radius, capsule_radius]:
					points.append(transform * Vector3(x, y, z))
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var half_cylinder_height := cylinder.height * 0.5
		for x: float in [-cylinder.radius, cylinder.radius]:
			for y: float in [-half_cylinder_height, half_cylinder_height]:
				for z: float in [-cylinder.radius, cylinder.radius]:
					points.append(transform * Vector3(x, y, z))
	elif shape is ConvexPolygonShape3D:
		for point: Vector3 in (shape as ConvexPolygonShape3D).points:
			points.append(transform * point)
	elif shape is ConcavePolygonShape3D:
		for point: Vector3 in (shape as ConcavePolygonShape3D).get_faces():
			points.append(transform * point)
	if points.is_empty():
		return AABB()
	var bounds := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		bounds = bounds.expand(point)
	return bounds


func _merge_vehicle_navigation_bounds(result: Dictionary, candidate: AABB) -> void:
	if candidate.size.length_squared() <= 0.0001:
		return
	if not bool(result.get("found", false)):
		result["found"] = true
		result["bounds"] = candidate
		return
	var current := result.get("bounds", AABB()) as AABB
	result["bounds"] = current.merge(candidate)


func _should_vehicle_navigation_obstacle_be_active() -> bool:
	if not vehicle_deployed or not is_inside_tree() or is_queued_for_deletion():
		return false
	if current_hp <= 0.0 or _spawn_drop_active or driver_peer_id > 0:
		return false
	return absf(current_speed) <= NAVIGATION_IDLE_SPEED_EPSILON \
		and Vector2(velocity.x, velocity.z).length() <= NAVIGATION_IDLE_SPEED_EPSILON


func _refresh_vehicle_navigation_obstacle(force := false) -> void:
	if not is_instance_valid(_vehicle_navigation_obstacle):
		return
	var active := _should_vehicle_navigation_obstacle_be_active()
	# Clients receive replicated vehicle transforms and never bake navigation.
	if GameAuthority.is_client_proxy():
		active = false
	if not force and active == _vehicle_navigation_obstacle_active:
		return
	_vehicle_navigation_obstacle_active = active
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var navigation_grid := scene_tree.get_first_node_in_group("dynamic_navigation_chunk_grids")
	if navigation_grid != null and navigation_grid.has_method("request_dynamic_obstacle_rebuild"):
		navigation_grid.call("request_dynamic_obstacle_rebuild", self, active)
	else:
		_vehicle_navigation_obstacle.set_deferred("affect_navigation_mesh", active)
		_vehicle_navigation_obstacle.set_deferred("avoidance_enabled", active)


func _unregister_vehicle_navigation_obstacle() -> void:
	if not is_instance_valid(_vehicle_navigation_obstacle):
		return
	_vehicle_navigation_obstacle_active = false
	var scene_tree := get_tree()
	if scene_tree == null:
		return
	var navigation_grid := scene_tree.get_first_node_in_group("dynamic_navigation_chunk_grids")
	if navigation_grid != null and navigation_grid.has_method("unregister_dynamic_obstacle"):
		navigation_grid.call("unregister_dynamic_obstacle", self)


func get_network_state() -> Dictionary:
	return {
		"position": global_position,
		"yaw": rotation.y,
		"speed": current_speed,
		"steering": current_steering,
		"hp": current_hp,
		"shield_hp": shield_hp,
		"shield_max_hp": shield_max_hp,
		"shield_remaining": shield_remaining,
		"driver_peer_id": driver_peer_id,
		"seat_occupants": get_seat_occupants(),
		"cargo_weight_kg": cargo_weight_kg,
		"cargo_manifest": get_cargo_manifest(),
		"cargo_occupied_slots": get_cargo_occupied_slots(),
		"cargo_available_slots": get_available_cargo_slot_count(),
		"owner_team": owner_team,
		"spawn_drop_active": _spawn_drop_active,
		"spawn_drop_landing_position": _spawn_drop_landing_position,
		"spawn_drop_remaining": get_spawn_drop_remaining(),
		"toppled": toppled,
		"tip_axis": tip_axis,
		"tip_angle": tip_angle,
	}


func apply_network_state(state: Dictionary) -> void:
	var previous_hp := current_hp
	var position: Variant = state.get("position", global_position)
	var next_yaw := float(state.get("yaw", rotation.y))
	var next_speed := float(state.get("speed", current_speed))
	var next_steering := float(state.get("steering", current_steering))
	var next_toppled := bool(state.get("toppled", toppled))
	var next_tip_axis_value: Variant = state.get("tip_axis", tip_axis)
	var next_tip_axis := next_tip_axis_value as Vector3 \
		if next_tip_axis_value is Vector3 else tip_axis
	var next_tip_angle := float(state.get("tip_angle", tip_angle))
	var network_drop_active := bool(state.get("spawn_drop_active", false))
	var network_drop_remaining := maxf(0.0, float(state.get("spawn_drop_remaining", 0.0)))
	var network_drop_landing: Variant = state.get(
		"spawn_drop_landing_position",
		_spawn_drop_landing_position
	)
	if network_drop_landing is Vector3:
		_spawn_drop_landing_position = network_drop_landing as Vector3
	var was_spawn_drop_active := _spawn_drop_active
	if network_drop_active:
		if not was_spawn_drop_active:
			_spawn_drop_collision_layer_before = collision_layer
			_spawn_drop_collision_mask_before = collision_mask
		_spawn_drop_active = true
		collision_mask = collision_mask | WILD_ANIMAL_COLLISION_LAYER
		_spawn_drop_timeout = maxf(DEFAULT_SPAWN_DROP_TIMEOUT, network_drop_remaining)
		_spawn_drop_elapsed = _spawn_drop_timeout - network_drop_remaining
	else:
		_spawn_drop_active = false
		if was_spawn_drop_active:
			collision_layer = _spawn_drop_collision_layer_before
			collision_mask = _spawn_drop_collision_mask_before
			_spawn_drop_collision_layer_before = 0
			_spawn_drop_collision_mask_before = 0
		_spawn_drop_elapsed = 0.0
		_spawn_drop_timeout = DEFAULT_SPAWN_DROP_TIMEOUT
	if GameAuthority.is_client_proxy() and position is Vector3:
		_network_target_position = position as Vector3
		_network_target_yaw = next_yaw
		_network_target_speed = next_speed
		_network_target_steering = next_steering
		if not _network_has_target or global_position.distance_to(_network_target_position) > NETWORK_SNAP_DISTANCE:
			global_position = _network_target_position
			rotation.y = _network_target_yaw
			current_speed = _network_target_speed
			current_steering = _network_target_steering
		_network_has_target = true
	else:
		if position is Vector3:
			global_position = position
		rotation.y = next_yaw
		current_speed = next_speed
		current_steering = next_steering
	current_hp = float(state.get("hp", current_hp))
	shield_hp = maxf(0.0, float(state.get("shield_hp", shield_hp)))
	shield_max_hp = maxf(0.0, float(state.get("shield_max_hp", shield_max_hp)))
	shield_remaining = maxf(0.0, float(state.get("shield_remaining", shield_remaining)))
	_update_vehicle_shield_visual()
	if current_hp < previous_hp and vehicle_config != null:
		vehicle_damaged.emit(current_hp, vehicle_config.max_hp)
	owner_team = str(state.get("owner_team", owner_team))
	var manifest_value: Variant = state.get("cargo_manifest", null)
	if manifest_value is Array:
		_network_cargo_occupied_slots.clear()
		set_cargo_manifest(manifest_value as Array)
	else:
		set_cargo_weight_kg(float(state.get("cargo_weight_kg", cargo_weight_kg)))
		var occupied_value: Variant = state.get("cargo_occupied_slots", null)
		if occupied_value is Array:
			_network_cargo_occupied_slots.clear()
			for index_value: Variant in occupied_value:
				var index := int(index_value)
				if index >= 0 and index < CARGO_SLOT_COUNT:
					_network_cargo_occupied_slots.append(index)
			_refresh_cargo_visuals()
	var occupants_value: Variant = state.get("seat_occupants", [])
	if occupants_value is Array:
		seat_occupants.clear()
		for seat_index in range((occupants_value as Array).size()):
			var peer_id := int((occupants_value as Array)[seat_index])
			if peer_id > 0:
				seat_occupants[seat_index] = peer_id
	set_toppled(next_toppled, next_tip_axis, next_tip_angle, false)
	_refresh_driver_peer_id()
	_refresh_vehicle_navigation_obstacle()
	_update_vehicle_presentation(0.0)


func _interpolate_network_state(delta: float) -> void:
	if not _network_has_target:
		return
	if global_position.distance_to(_network_target_position) > NETWORK_SNAP_DISTANCE:
		global_position = _network_target_position
		rotation.y = _network_target_yaw
	else:
		var weight := 1.0 - exp(-NETWORK_INTERPOLATION_RATE * delta)
		global_position = global_position.lerp(_network_target_position, weight)
		rotation.y = lerp_angle(rotation.y, _network_target_yaw, weight)
		current_speed = lerpf(current_speed, _network_target_speed, weight)
		current_steering = lerpf(current_steering, _network_target_steering, weight)
	_update_vehicle_presentation(delta)


func can_team_enter(player_team: String) -> bool:
	return owner_team.is_empty() or owner_team == player_team


func can_enter_driver(peer_id: int) -> bool:
	var driver_index := get_driver_seat_index()
	return driver_index >= 0 and can_enter_seat(peer_id, driver_index)


func enter_driver(peer_id: int) -> bool:
	return enter_seat(peer_id, get_driver_seat_index())


func exit_driver(peer_id: int) -> void:
	if get_seat_index_for_peer(peer_id) == get_driver_seat_index():
		exit_seat(peer_id)
		set_drive_input(0.0, 0.0, 1.0)


func get_driver_anchor() -> Node3D:
	return get_seat_anchor(get_driver_seat_index())


func get_vehicle_id() -> String:
	return network_id if not network_id.is_empty() else name


func get_seat_count() -> int:
	return _seat_definitions().size()


## Seats inside the normal cabin. FarmBaseVehicle overrides this view so its
## dynamically added side/platform seats remain available to their own entry
## interaction, but are not shown as in-cabin seats in the vehicle HUD.
func get_cabin_seat_count() -> int:
	return _base_seat_definitions().size()


func get_cabin_seat_occupants() -> Array[int]:
	var occupants: Array[int] = []
	occupants.resize(get_cabin_seat_count())
	for seat_index in range(occupants.size()):
		occupants[seat_index] = int(seat_occupants.get(seat_index, 0))
	return occupants


func is_cabin_seat(seat_index: int) -> bool:
	return seat_index >= 0 and seat_index < get_cabin_seat_count()


func is_full() -> bool:
	return seat_occupants.size() >= get_seat_count()


func get_available_seat_index(prefer_driver := true) -> int:
	if prefer_driver:
		var driver_index := get_driver_seat_index()
		if driver_index >= 0 and not seat_occupants.has(driver_index):
			return driver_index
	for seat_index in range(get_seat_count()):
		if not seat_occupants.has(seat_index):
			return seat_index
	return -1


func get_driver_seat_index() -> int:
	var definitions := _seat_definitions()
	for seat_index in range(definitions.size()):
		if definitions[seat_index].can_drive:
			return seat_index
	return -1


func can_enter_seat(peer_id: int, seat_index: int = -1) -> bool:
	if _spawn_drop_active or toppled or peer_id <= 0 or current_hp <= 0.0 \
			or get_seat_index_for_peer(peer_id) >= 0:
		return false
	var requested_index := get_available_seat_index() if seat_index < 0 else seat_index
	return requested_index >= 0 and requested_index < get_seat_count() and not seat_occupants.has(requested_index)


func enter_seat(peer_id: int, seat_index: int = -1) -> bool:
	var requested_index := get_available_seat_index() if seat_index < 0 else seat_index
	if not can_enter_seat(peer_id, requested_index):
		return false
	seat_occupants[requested_index] = peer_id
	_refresh_driver_peer_id()
	return true


func can_switch_seat(peer_id: int, target_seat_index: int) -> bool:
	if _spawn_drop_active or toppled or peer_id <= 0 or current_hp <= 0.0:
		return false
	var current_seat_index := get_seat_index_for_peer(peer_id)
	return current_seat_index >= 0 \
			and target_seat_index >= 0 \
			and target_seat_index < get_seat_count() \
			and target_seat_index != current_seat_index \
			and not seat_occupants.has(target_seat_index)


func switch_seat(peer_id: int, target_seat_index: int) -> bool:
	if not can_switch_seat(peer_id, target_seat_index):
		return false
	var current_seat_index := get_seat_index_for_peer(peer_id)
	seat_occupants.erase(current_seat_index)
	seat_occupants[target_seat_index] = peer_id
	_refresh_driver_peer_id()
	return true


func exit_seat(peer_id: int) -> int:
	var seat_index := get_seat_index_for_peer(peer_id)
	if seat_index < 0:
		return -1
	seat_occupants.erase(seat_index)
	_refresh_driver_peer_id()
	return seat_index


func get_seat_index_for_peer(peer_id: int) -> int:
	for raw_seat_index in seat_occupants.keys():
		if int(seat_occupants[raw_seat_index]) == peer_id:
			return int(raw_seat_index)
	return -1


func get_seat_occupants() -> Array[int]:
	var occupants: Array[int] = []
	occupants.resize(get_seat_count())
	for seat_index in range(occupants.size()):
		occupants[seat_index] = int(seat_occupants.get(seat_index, 0))
	return occupants


func seat_can_drive(seat_index: int) -> bool:
	var definitions := _seat_definitions()
	return seat_index >= 0 and seat_index < definitions.size() and definitions[seat_index].can_drive


func should_show_occupant(seat_index: int) -> bool:
	if vehicle_config == null or not vehicle_config.open_cabin:
		return false
	var definitions := _seat_definitions()
	return seat_index >= 0 and seat_index < definitions.size() and definitions[seat_index].show_occupant


func get_seat_anchor(seat_index: int) -> Node3D:
	if should_show_occupant(seat_index) and seat_index < seat_anchors.size() and is_instance_valid(seat_anchors[seat_index]):
		return seat_anchors[seat_index]
	return driver_seat


func get_seat_world_transform(seat_index: int) -> Transform3D:
	return get_seat_anchor(seat_index).global_transform


func get_occupant_world_transform(seat_index: int) -> Transform3D:
	# Closed vehicles do not expose a visible seat anchor. Keep the hidden
	# authoritative player proxy attached to the vehicle body instead of moving
	# it to an arbitrary logical DriverSeat marker. Open vehicles retain the
	# authored seat/hip offsets below.
	if not should_show_occupant(seat_index):
		return Transform3D(global_transform.basis.orthonormalized(), global_position)
	var seat_transform := get_seat_world_transform(seat_index)
	var definitions := _seat_definitions()
	if seat_index < 0 or seat_index >= definitions.size():
		return seat_transform
	var seat := definitions[seat_index]
	var occupant_rotation := Vector3(
		deg_to_rad(seat.occupant_rotation_degrees.x),
		deg_to_rad(seat.occupant_rotation_degrees.y),
		deg_to_rad(seat.occupant_rotation_degrees.z)
	)
	# Do not inherit an imported visual's scale into the player. The seat basis
	# still supplies the vehicle's world orientation, while the offset is applied
	# in that normalized seat-local frame so all open vehicles place the player's
	# hips consistently.
	var seat_basis := seat_transform.basis.orthonormalized()
	var occupant_basis := seat_basis * Basis.from_euler(occupant_rotation)
	var occupant_offset := seat.occupant_offset + seat.seated_position_offset
	var occupant_origin := seat_transform.origin + seat_basis * occupant_offset
	return Transform3D(occupant_basis, occupant_origin)


func get_exit_position(seat_index: int = -1) -> Vector3:
	if is_instance_valid(exit_point):
		return exit_point.global_position
	var definitions := _seat_definitions()
	if seat_index >= 0 and seat_index < definitions.size():
		return to_global(definitions[seat_index].exit_offset)
	return to_global(Vector3(1.8, 0.1, 0.0))


func get_driving_camera() -> Camera3D:
	return vehicle_camera


## World point used by player/server vehicle-entry validation. Large custom
## vehicles can override the range without changing the shared interaction
## pipeline.
func get_player_interaction_position() -> Vector3:
	return global_position


func get_player_interaction_range() -> float:
	return 4.0


## Horizontal distance from a world point to the chassis footprint. AI melee
## uses this instead of the vehicle origin because long vehicles can be touched
## at a bumper while their root remains several metres away.
func get_horizontal_distance_to_chassis(world_point: Vector3) -> float:
	var bounds_data := _vehicle_navigation_collision_bounds()
	if not bool(bounds_data.get("initialized", false)):
		var root_offset := world_point - global_position
		root_offset.y = 0.0
		return root_offset.length()
	var bounds: AABB = bounds_data.get("bounds", AABB())
	var local_point := to_local(world_point)
	var closest_x := clampf(local_point.x, bounds.position.x, bounds.end.x)
	var closest_z := clampf(local_point.z, bounds.position.z, bounds.end.z)
	return Vector2(local_point.x - closest_x, local_point.z - closest_z).length()


func get_cargo_capacity_kg() -> float:
	return maxf(0.0, vehicle_config.cargo_capacity_kg) if vehicle_config != null else 0.0


func supports_cargo() -> bool:
	return get_cargo_capacity_kg() > 0.0


func get_cargo_weight_kg() -> float:
	return cargo_weight_kg


func get_cargo_manifest() -> Array[Dictionary]:
	_ensure_cargo_manifest_size()
	var result: Array[Dictionary] = []
	for crate: Dictionary in cargo_manifest:
		result.append(crate.duplicate(true))
	return result


func get_cargo_crate_count() -> int:
	if GameAuthority.is_client_proxy() and not _network_cargo_occupied_slots.is_empty():
		return _network_cargo_occupied_slots.size()
	var count := 0
	for crate: Dictionary in cargo_manifest:
		if not crate.is_empty():
			count += 1
	return count


func get_cargo_occupied_slots() -> Array[int]:
	var result: Array[int] = []
	for index in range(cargo_manifest.size()):
		if not cargo_manifest[index].is_empty():
			result.append(index)
	return result


func get_available_cargo_slot_count() -> int:
	if not supports_cargo() or vehicle_config == null or current_hp <= 0.0:
		return 0
	return clampi(ceili(current_hp / maxf(vehicle_config.max_hp, 0.01) * CARGO_SLOT_COUNT), 1, CARGO_SLOT_COUNT)


func is_valid_cargo_crate(crate: Dictionary) -> bool:
	var normalized := CargoCrateData.normalize(crate)
	return not normalized.is_empty() \
		and not str(normalized.get("crate_instance_id", "")).is_empty() \
		and float(normalized.get("total_weight_kg", 0.0)) > 0.0 \
		and float(normalized.get("content_weight_kg", 0.0)) \
			<= float(normalized.get("capacity_kg", 0.0)) + 0.001


func set_cargo_manifest(value: Array) -> void:
	cargo_manifest.clear()
	for index in range(CARGO_SLOT_COUNT):
		var crate: Dictionary = value[index] as Dictionary if index < value.size() and value[index] is Dictionary else {}
		cargo_manifest.append(crate.duplicate(true) if crate.is_empty() or is_valid_cargo_crate(crate) else {})
	_recalculate_cargo_weight()
	_refresh_cargo_visuals()
	cargo_manifest_changed.emit(get_cargo_manifest())


func try_load_cargo_crate(crate: Dictionary, slot_index := -1) -> int:
	if not is_valid_cargo_crate(crate):
		return -1
	_ensure_cargo_manifest_size()
	var available := get_available_cargo_slot_count()
	if cargo_weight_kg + float(crate.get("total_weight_kg", crate.get("weight_kg", 0.0))) > get_cargo_capacity_kg() + 0.001:
		return -1
	var target := slot_index
	if target < 0:
		for index in range(available):
			if cargo_manifest[index].is_empty():
				target = index
				break
	if target < 0 or target >= available or not cargo_manifest[target].is_empty():
		return -1
	cargo_manifest[target] = crate.duplicate(true)
	_recalculate_cargo_weight()
	_refresh_cargo_visuals()
	cargo_manifest_changed.emit(get_cargo_manifest())
	return target


func take_cargo_crate(slot_index: int) -> Dictionary:
	_ensure_cargo_manifest_size()
	if slot_index < 0 or slot_index >= cargo_manifest.size() or cargo_manifest[slot_index].is_empty():
		return {}
	var crate := cargo_manifest[slot_index].duplicate(true)
	cargo_manifest[slot_index] = {}
	_recalculate_cargo_weight()
	_refresh_cargo_visuals()
	cargo_manifest_changed.emit(get_cargo_manifest())
	return crate


func update_cargo_crate(slot_index: int, crate: Dictionary) -> bool:
	_ensure_cargo_manifest_size()
	if slot_index < 0 or slot_index >= CARGO_SLOT_COUNT:
		return false
	if not crate.is_empty() and not is_valid_cargo_crate(crate):
		return false
	cargo_manifest[slot_index] = crate.duplicate(true)
	_recalculate_cargo_weight()
	_refresh_cargo_visuals()
	cargo_manifest_changed.emit(get_cargo_manifest())
	return true


func try_acquire_cargo_user(peer_id: int) -> bool:
	if peer_id <= 0 or (cargo_user_peer_id > 0 and cargo_user_peer_id != peer_id):
		return false
	cargo_user_peer_id = peer_id
	return true


func release_cargo_user(peer_id: int) -> bool:
	if cargo_user_peer_id != peer_id:
		return false
	cargo_user_peer_id = 0
	return true


func is_cargo_storage_interaction_available_to(world_position: Vector3) -> bool:
	# Cargo interaction areas are grouped under CargoInteractionAreas so that
	# they do not become direct vehicle children. Search recursively; checking
	# only get_children() made every server-side range check fail.
	for child: Node in find_children("*", "CargoCarInteractionArea", true, false):
		var area := child as CargoCarInteractionArea
		if area.interaction_kind != "cargo":
			continue
		var shape_nodes := area.find_children("*", "CollisionShape3D", true, false)
		var shape_node := shape_nodes[0] as CollisionShape3D if not shape_nodes.is_empty() else null
		var shape := shape_node.shape as BoxShape3D if shape_node != null else null
		if shape == null:
			CARGO_CAR_DEBUG.log("range check area=%s has no BoxShape3D" % area.get_path())
			continue
		var local := area.to_local(world_position)
		var half := shape.size * 0.5 + Vector3(0.55, 0.35, 0.55)
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	CARGO_CAR_DEBUG.log(
		"range check vehicle=%s id=%s position=%s -> false (cargo areas=%d)"
		% [name, network_id, str(world_position), find_children("*", "CargoCarInteractionArea", true, false).size()]
	)
	return false


func get_available_cargo_capacity_kg() -> float:
	return maxf(0.0, get_cargo_capacity_kg() - cargo_weight_kg)


## Authority-side API for loading cargo. Returns the weight that fit in the vehicle.
func add_cargo_weight_kg(weight_kg: float) -> float:
	if GameAuthority.should_send_network_requests() or weight_kg <= 0.0 or get_cargo_capacity_kg() <= 0.0:
		return 0.0
	var added_weight := minf(weight_kg, get_available_cargo_capacity_kg())
	set_cargo_weight_kg(cargo_weight_kg + added_weight)
	return added_weight


## Authority-side API for unloading, dropped cargo, or damage losses.
func remove_cargo_weight_kg(weight_kg: float) -> float:
	if GameAuthority.should_send_network_requests() or weight_kg <= 0.0 or cargo_weight_kg <= 0.0:
		return 0.0
	var removed_weight := minf(weight_kg, cargo_weight_kg)
	set_cargo_weight_kg(cargo_weight_kg - removed_weight)
	return removed_weight


func set_cargo_weight_kg(weight_kg: float) -> void:
	var next_weight := clampf(weight_kg, 0.0, get_cargo_capacity_kg())
	if is_equal_approx(cargo_weight_kg, next_weight):
		return
	cargo_weight_kg = next_weight
	_update_cargo_hit_shape()
	_refresh_cargo_visuals()


func _ensure_cargo_manifest_size() -> void:
	while cargo_manifest.size() < CARGO_SLOT_COUNT:
		cargo_manifest.append({})
	if cargo_manifest.size() > CARGO_SLOT_COUNT:
		cargo_manifest.resize(CARGO_SLOT_COUNT)


func _recalculate_cargo_weight() -> void:
	cargo_weight_kg = 0.0
	for crate: Dictionary in cargo_manifest:
		if not crate.is_empty():
			cargo_weight_kg += maxf(0.0, float(crate.get("total_weight_kg", crate.get("weight_kg", 0.0))))
	cargo_weight_kg = minf(cargo_weight_kg, get_cargo_capacity_kg())
	_update_cargo_hit_shape()


func reset_driving_camera_orbit() -> void:
	if vehicle_config == null:
		return
	_camera_orbit_yaw = deg_to_rad(vehicle_config.camera_orbit_yaw_degrees)
	_camera_orbit_pitch = deg_to_rad(vehicle_config.camera_orbit_pitch_degrees)
	_apply_driving_camera_orbit()


func rotate_driving_camera(mouse_delta: Vector2, sensitivity: float) -> void:
	if vehicle_config == null:
		return
	_camera_orbit_yaw -= mouse_delta.x * sensitivity
	_camera_orbit_pitch -= mouse_delta.y * sensitivity
	_camera_orbit_pitch = clampf(
		_camera_orbit_pitch,
		deg_to_rad(vehicle_config.camera_orbit_min_pitch_degrees),
		deg_to_rad(vehicle_config.camera_orbit_max_pitch_degrees)
	)
	_apply_driving_camera_orbit()


func _apply_driving_camera_orbit() -> void:
	if not is_instance_valid(camera_orbit_yaw) or not is_instance_valid(camera_orbit_pitch) \
			or not is_instance_valid(vehicle_camera):
		return
	camera_orbit_yaw.rotation.y = _camera_orbit_yaw
	camera_orbit_pitch.rotation.x = _camera_orbit_pitch
	vehicle_camera.look_at(
		global_position + Vector3.UP * vehicle_config.camera_orbit_target_height,
		Vector3.UP
	)


func _base_seat_definitions() -> Array[VehicleSeatConfig]:
	if vehicle_config != null and not vehicle_config.seats.is_empty():
		return vehicle_config.seats
	var fallback := VehicleSeatConfig.new()
	return [fallback]


func _seat_definitions() -> Array[VehicleSeatConfig]:
	return _base_seat_definitions()


func _refresh_driver_peer_id() -> void:
	driver_peer_id = int(seat_occupants.get(get_driver_seat_index(), 0))
	# Disable the obstacle as soon as a driver sits down, before acceleration.
	_refresh_vehicle_navigation_obstacle()


func impact(_effect: String, strength: float, _attacker_team: String = "") -> bool:
	if GameAuthority.should_send_network_requests() or strength <= 0.0 or current_hp <= 0.0:
		return false
	if shield_remaining > 0.0 and shield_hp > 0.0:
		var absorbed := minf(shield_hp, strength)
		shield_hp = maxf(0.0, shield_hp - absorbed)
		strength = maxf(0.0, strength - absorbed)
		if is_instance_valid(_shield_visual):
			_shield_visual.pulse_impact()
		if shield_hp <= 0.0:
			shield_remaining = 0.0
		_update_vehicle_shield_visual()
		if strength <= 0.0:
			return true
	var previous_available_slots := get_available_cargo_slot_count()
	current_hp = maxf(0.0, current_hp - strength)
	var lost_slots := maxi(0, previous_available_slots - get_available_cargo_slot_count())
	_destroy_cargo_for_lost_slots(lost_slots)
	vehicle_damaged.emit(current_hp, vehicle_config.max_hp)
	GameAuthority.notify_vehicle_damaged(self, strength)
	if current_hp <= 0.0:
		_refresh_vehicle_navigation_obstacle(true)
		GameAuthority.destroy_vehicle_with_occupants(self)
		vehicle_destroyed.emit()
		if GameAuthority.is_local_authority() or GameAuthority.is_server_authority():
			_apply_destruction_explosion_damage()
		if GameAuthority.is_local_authority():
			_spawn_destruction_effect()
		queue_free()
	return true


func apply_vehicle_shield(duration: float, max_hp: float) -> bool:
	if GameAuthority.should_send_network_requests() or current_hp <= 0.0 \
			or duration <= 0.0 or max_hp <= 0.0:
		return false
	if shield_remaining > 0.0 and shield_hp > 0.0:
		return false
	shield_remaining = duration
	shield_max_hp = max_hp
	shield_hp = max_hp
	_update_vehicle_shield_visual()
	return true


func apply_network_shield(remaining: float, current_shield_hp: float, maximum_shield_hp: float) -> void:
	shield_remaining = maxf(0.0, remaining)
	shield_max_hp = maxf(0.0, maximum_shield_hp)
	shield_hp = clampf(current_shield_hp, 0.0, shield_max_hp)
	_update_vehicle_shield_visual()


func _tick_vehicle_shield(delta: float) -> void:
	if shield_remaining <= 0.0 or shield_hp <= 0.0:
		return
	shield_remaining = maxf(0.0, shield_remaining - delta)
	if shield_remaining <= 0.0:
		shield_hp = 0.0
	_update_vehicle_shield_visual()


func _update_vehicle_shield_visual() -> void:
	var active := shield_remaining > 0.0 and shield_hp > 0.0
	if active and not is_instance_valid(_shield_visual):
		_shield_visual = VEHICLE_SHIELD_SCENE.instantiate() as VehicleShieldBubble
		if _shield_visual != null:
			add_child(_shield_visual)
			var coverage_size := vehicle_config.hitbox_size if vehicle_config != null else Vector3(3.0, 2.0, 5.0)
			var center_offset := vehicle_config.hitbox_offset if vehicle_config != null else Vector3.UP
			_shield_visual.configure(coverage_size, center_offset)
	if is_instance_valid(_shield_visual):
		_shield_visual.set_state(shield_remaining, shield_hp, shield_max_hp)


func repair(amount: float) -> float:
	if GameAuthority.should_send_network_requests() or vehicle_config == null \
			or amount <= 0.0 or current_hp <= 0.0:
		return 0.0
	var previous_hp := current_hp
	current_hp = minf(vehicle_config.max_hp, current_hp + amount)
	if is_equal_approx(previous_hp, current_hp):
		return 0.0
	_last_available_cargo_slots = get_available_cargo_slot_count()
	_refresh_cargo_visuals()
	return current_hp - previous_hp


func _apply_destruction_explosion_damage() -> void:
	GameAuthority.apply_authoritative_vehicle_explosion(
		global_position,
		owner_team,
		get_destruction_effect_damage(),
		get_destruction_effect_radius(),
		"VehicleExplosion",
		get_destruction_effect_knockback()
	)


func _spawn_destruction_effect() -> void:
	var world_root: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world_root == null:
		return
	var effect := VEHICLE_EXPLOSION_SCENE.instantiate() as Node3D
	if effect == null:
		return
	effect.set("vehicle_variant", get_destruction_effect_variant())
	world_root.add_child(effect)
	effect.global_position = global_position


func _configure_physics_nodes() -> void:
	collision_layer = 8192
	# Vehicles must physically meet all damageable world bodies. Tool is already
	# part of the legacy mask; nature resources and wild animals are added here.
	collision_mask = 12427 | TOOL_COLLISION_LAYER | NATURE_RESOURCE_COLLISION_LAYER \
		| WILD_ANIMAL_COLLISION_LAYER
	ground_probe.enabled = true
	ground_probe.collision_mask = GROUND_COLLISION_LAYER
	ground_probe.exclude_parent = true
	hit_area.collision_layer = 0
	hit_area.collision_mask = BULLET_COLLISION_LAYER


func _apply_vehicle_config() -> void:
	if vehicle_config == null:
		push_warning("VehicleBase requires a VehicleConfig resource.")
		return
	current_hp = vehicle_config.max_hp
	_last_available_cargo_slots = get_available_cargo_slot_count()
	if is_instance_valid(vehicle_shape):
		var body_shape := vehicle_shape.shape as BoxShape3D
		if body_shape != null:
			body_shape.size = vehicle_config.collision_size
		vehicle_shape.position = vehicle_config.collision_offset
	if is_instance_valid(hit_shape):
		var damage_shape := hit_shape.shape as BoxShape3D
		if damage_shape != null:
			damage_shape.size = vehicle_config.hitbox_size
		hit_shape.position = vehicle_config.hitbox_offset
	vehicle_camera.position = vehicle_config.camera_offset
	vehicle_camera.fov = vehicle_config.camera_base_fov
	cargo_weight_kg = clampf(initial_cargo_weight_kg, 0.0, get_cargo_capacity_kg())
	_ensure_cargo_manifest_size()
	_update_cargo_hit_shape()
	reset_driving_camera_orbit()
	_load_body_visual()
	_refresh_cargo_visuals()


func _load_body_visual() -> void:
	if vehicle_config.visual_scene == null:
		# Tool vehicles can keep their visual and animation nodes directly in the
		# gameplay scene instead of requiring a second visual-only resource. Mesh
		# is the name used by the imported farm vehicle scene, while BodyVisual is
		# retained for the older tool vehicle scenes.
		body_visual = get_node_or_null("BodyVisual") as Node3D
		if not is_instance_valid(body_visual):
			body_visual = get_node_or_null("Mesh") as Node3D
		if is_instance_valid(body_visual):
			_cache_visual_nodes()
			return
		push_warning("VehicleConfig is missing its visual tscn scene and BodyVisual node.")
		return
	if is_instance_valid(body_visual):
		body_visual.queue_free()
	body_visual = null
	body_visual = vehicle_config.visual_scene.instantiate() as Node3D
	if body_visual == null:
		push_warning("Vehicle visual scene must instantiate a Node3D.")
		return
	body_visual.name = "BodyVisual"
	add_child(body_visual)
	body_visual.position = vehicle_config.visual_offset
	body_visual.rotation = vehicle_config.visual_rotation
	_cache_visual_nodes()


func _refresh_cargo_visuals() -> void:
	if not is_instance_valid(_cargo_container):
		_cargo_container = Node3D.new()
		_cargo_container.name = "CargoCrates"
		add_child(_cargo_container)
	if vehicle_config == null or not vehicle_config.open_cabin or get_cargo_capacity_kg() <= 0.0:
		_clear_cargo_crates()
		return
	var visual_slots := _network_cargo_occupied_slots if GameAuthority.is_client_proxy() \
		and not _network_cargo_occupied_slots.is_empty() else get_cargo_occupied_slots()
	if visual_slots.is_empty():
		_clear_cargo_crates()
		return
	var crate_count := _get_cargo_crate_total()
	if crate_count <= 0 or vehicle_config.cargo_crate_scene_path.is_empty():
		_clear_cargo_crates()
		return
	if _cargo_crates.size() != crate_count:
		_clear_cargo_crates()
		if not ResourceLoader.exists(vehicle_config.cargo_crate_scene_path):
			return
		var crate_scene := load(vehicle_config.cargo_crate_scene_path) as PackedScene
		if crate_scene == null:
			return
		for crate_index in range(crate_count):
			var crate := crate_scene.instantiate() as Node3D
			if crate == null:
				continue
			crate.name = "CargoCrate%02d" % (crate_index + 1)
			crate.position = _get_cargo_crate_position(crate_index)
			_cargo_container.add_child(crate)
			_cargo_crates.append(crate)
	for crate_index in range(_cargo_crates.size()):
		var crate := _cargo_crates[crate_index]
		if is_instance_valid(crate):
			crate.visible = visual_slots.has(crate_index)


func _update_cargo_hit_shape() -> void:
	if vehicle_config == null or not is_instance_valid(hit_shape):
		return
	var has_upper_cargo_layer := false
	var visual_slots := _network_cargo_occupied_slots if GameAuthority.is_client_proxy() \
		and not _network_cargo_occupied_slots.is_empty() else get_cargo_occupied_slots()
	for index in visual_slots:
		if index >= 6:
			has_upper_cargo_layer = true
			break
	hit_shape.position = vehicle_config.hitbox_offset + (Vector3.UP if has_upper_cargo_layer else Vector3.ZERO)


func _set_direct_body_collision_shapes_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", disabled)


func _clear_cargo_crates() -> void:
	for crate in _cargo_crates:
		if is_instance_valid(crate):
			crate.queue_free()
	_cargo_crates.clear()


func _get_visible_cargo_crate_count() -> int:
	return get_cargo_crate_count()


func _get_cargo_crate_total() -> int:
	return CARGO_SLOT_COUNT if vehicle_config != null and supports_cargo() else 0


func _destroy_cargo_for_lost_slots(count: int) -> void:
	_ensure_cargo_manifest_size()
	var remaining := count
	for index in range(cargo_manifest.size() - 1, -1, -1):
		if remaining <= 0:
			break
		if cargo_manifest[index].is_empty():
			continue
		cargo_manifest[index] = {}
		remaining -= 1
	_compact_cargo_manifest()
	_recalculate_cargo_weight()
	_refresh_cargo_visuals()
	if count > 0:
		cargo_manifest_changed.emit(get_cargo_manifest())


func _compact_cargo_manifest() -> void:
	var crates: Array[Dictionary] = []
	for crate: Dictionary in cargo_manifest:
		if not crate.is_empty():
			crates.append(crate)
	cargo_manifest.clear()
	for crate: Dictionary in crates:
		cargo_manifest.append(crate)
	_ensure_cargo_manifest_size()


func _create_cargo_interaction_areas() -> void:
	if not supports_cargo():
		CARGO_CAR_DEBUG.log(
			"skip cargo areas vehicle=%s id=%s capacity=%.1f config=%s"
			% [name, network_id, get_cargo_capacity_kg(), vehicle_config.resource_path if vehicle_config != null else "<null>"]
		)
		return
	if find_child("CargoInteractionAreas", false, false) != null:
		CARGO_CAR_DEBUG.log("cargo areas already exist vehicle=%s id=%s" % [name, network_id])
		return
	var root := Node3D.new()
	root.name = "CargoInteractionAreas"
	add_child(root)
	# Current CargoCar configs use +Z as forward and -Z as the cargo/rear direction.
	_add_cargo_interaction_area(root, "DriverAreaLeft", "driver", Vector3(-2.45, 1.0, 2.55), Vector3(1.25, 2.0, 2.4))
	_add_cargo_interaction_area(root, "DriverAreaRight", "driver", Vector3(2.45, 1.0, 2.55), Vector3(1.25, 2.0, 2.4))
	_add_cargo_interaction_area(root, "CargoAreaLeft", "cargo", Vector3(-2.45, 1.0, -1.15), Vector3(1.25, 2.0, 4.6))
	_add_cargo_interaction_area(root, "CargoAreaRight", "cargo", Vector3(2.45, 1.0, -1.15), Vector3(1.25, 2.0, 4.6))
	_add_cargo_interaction_area(root, "CargoAreaRear", "cargo", Vector3(0.0, 1.0, -4.35), Vector3(3.8, 2.0, 1.15))
	CARGO_CAR_DEBUG.log(
		"created cargo areas vehicle=%s id=%s capacity=%.1f areas=%d"
		% [name, network_id, get_cargo_capacity_kg(), find_children("*", "CargoCarInteractionArea", true, false).size()]
	)


func _add_cargo_interaction_area(root: Node3D, area_name: String, kind: String, position_value: Vector3, size: Vector3) -> void:
	var area := CargoCarInteractionArea.new()
	area.name = area_name
	area.interaction_kind = kind
	area.position = position_value
	root.add_child(area)
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	area.add_child(shape)


func _get_cargo_crate_position(crate_index: int) -> Vector3:
	# Lower-layer crates are indexed before upper-layer crates, so the top layer
	# disappears first as cargo weight is removed.
	var crate_size := vehicle_config.cargo_crate_size
	var crates_per_layer := vehicle_config.cargo_columns * vehicle_config.cargo_rows
	var layer := crate_index / crates_per_layer
	var within_layer := crate_index % crates_per_layer
	var column := within_layer % vehicle_config.cargo_columns
	var row := within_layer / vehicle_config.cargo_columns
	var x := (float(column) - (float(vehicle_config.cargo_columns - 1) * 0.5)) * crate_size.x
	var z := -float(row) * crate_size.z
	var y := float(layer) * crate_size.y
	return vehicle_config.cargo_placement_origin + Vector3(x, y, z)


func _cache_visual_nodes() -> void:
	driver_seat_point = _find_visual_node("DriverSeatPoint")
	steering_wheel = _find_visual_node("SteeringWheel")
	wheel_fl = _find_visual_node("Wheel_FL")
	wheel_fr = _find_visual_node("Wheel_FR")
	wheel_rl = _find_visual_node("Wheel_RL")
	wheel_rr = _find_visual_node("Wheel_RR")
	_cache_seat_anchors()
	_wheel_rest_bases.clear()
	for wheel in [wheel_fl, wheel_fr, wheel_rl, wheel_rr]:
		if is_instance_valid(wheel):
			_wheel_rest_bases[wheel.get_instance_id()] = wheel.basis
	if is_instance_valid(steering_wheel):
		_steering_wheel_rest_basis = steering_wheel.basis
	if vehicle_config.open_cabin and (seat_anchors.is_empty() or not is_instance_valid(seat_anchors[0])):
		var driver_anchor_name := _seat_definitions()[0].anchor_name
		push_warning("Open vehicle is missing driver seat anchor: %s." % driver_anchor_name)


func _cache_seat_anchors() -> void:
	seat_anchors.clear()
	var definitions := _seat_definitions()
	for seat_index in range(definitions.size()):
		var seat := definitions[seat_index]
		var anchor: Node3D = null
		if vehicle_config.open_cabin:
			var default_anchor_name := "DriverSeatPoint" if seat_index == 0 else "SeatPoint_%d" % seat_index
			var anchor_name := default_anchor_name if seat.anchor_name.is_empty() else seat.anchor_name
			# Open vehicles may author the seat marker directly on the gameplay
			# scene root (for example an ATV's DriverSeat) instead of embedding a
			# marker inside the imported Mesh scene. Prefer that authored root
			# marker, then fall back to the visual scene for existing vehicles.
			anchor = get_node_or_null(anchor_name) as Node3D
			if anchor == null:
				anchor = _find_visual_node(anchor_name)
			if anchor == null:
				push_warning("Open vehicle is missing seat anchor %s." % anchor_name)
		seat_anchors.append(anchor)


func _find_visual_node(node_name: String) -> Node3D:
	if not is_instance_valid(body_visual):
		return null
	return body_visual.find_child(node_name, true, false) as Node3D


func _update_vehicle_visuals(delta: float) -> void:
	if vehicle_config == null:
		return
	wheel_spin_angle += current_speed / maxf(vehicle_config.wheel_radius, 0.01) * delta
	var front_angles := _front_wheel_steering_angles(_vehicle_turn_angle())
	_apply_wheel_visual(wheel_fl, front_angles.x)
	_apply_wheel_visual(wheel_fr, front_angles.y)
	_apply_wheel_visual(wheel_rl, 0.0)
	_apply_wheel_visual(wheel_rr, 0.0)
	if vehicle_config.open_cabin and vehicle_config.animate_steering_wheel and is_instance_valid(steering_wheel):
		steering_wheel.basis = _steering_wheel_rest_basis
		var axis := vehicle_config.steering_wheel_axis.normalized()
		steering_wheel.rotate_object_local(axis, _vehicle_turn_angle() * 3.0)
	var target_fov := get_camera_fov_for_speed(current_speed)
	vehicle_camera.fov = lerpf(vehicle_camera.fov, target_fov, 1.0 - exp(-vehicle_config.camera_fov_response * maxf(delta, 0.0)))


func _apply_wheel_visual(wheel: Node3D, steering_angle: float) -> void:
	if not is_instance_valid(wheel):
		return
	var rest_basis: Basis = _wheel_rest_bases.get(wheel.get_instance_id(), wheel.basis)
	wheel.basis = rest_basis
	wheel.rotate_object_local(Vector3.UP, steering_angle)
	wheel.rotate_object_local(vehicle_config.wheel_spin_axis.normalized(), -wheel_spin_angle)


func _vehicle_turn_angle() -> float:
	return current_steering * vehicle_config.steering_turn_sign


func _front_wheel_steering_angles(turn_angle: float) -> Vector2:
	if absf(turn_angle) <= 0.0001:
		return Vector2.ZERO
	var wheel_base := maxf(vehicle_config.wheel_base, 0.01)
	var half_track := maxf(vehicle_config.wheel_track, 0.01) * 0.5
	var turn_radius := wheel_base / tan(absf(turn_angle))
	var inner_angle := atan(wheel_base / maxf(0.01, turn_radius - half_track))
	var outer_angle := atan(wheel_base / (turn_radius + half_track))
	if turn_angle > 0.0:
		# +X is the vehicle's right side: Wheel_FR is inside a right turn.
		return Vector2(outer_angle, inner_angle)
	# Wheel_FL is inside a left turn.
	return Vector2(-inner_angle, -outer_angle)


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if body == self or GameAuthority.should_send_network_requests():
		return
	var strength_value: Variant = body.get("bullet_strength")
	if strength_value == null:
		return
	var strength := float(strength_value) if strength_value != null else 10.0
	var attacker_team := str(body.get("bullet_owner"))
	var effect := str(body.get("bullet_effect"))
	var target_team := owner_team
	if GameAuthority.has_method("_vehicle_team"):
		var resolved_team: Variant = GameAuthority.call("_vehicle_team", self)
		if resolved_team is String:
			target_team = resolved_team as String
	var attacker_peer_id := 0
	if body.has_method("get_bullet_shooter"):
		var shooter: Variant = body.call("get_bullet_shooter")
		if shooter is Node:
			attacker_peer_id = GameAuthority.get_authority_player_peer_id(shooter as Node)
	attacker_peer_id = GameAuthority.resolve_attacker_peer_id(attacker_team, attacker_peer_id)
	if impact(effect, strength, attacker_team):
		if attacker_peer_id > 0 and GameAuthority.should_show_player_hit_confirmation(
			attacker_team, target_team
		):
			GameAuthority.call(
				"_emit_hit_confirmed", attacker_peer_id, 1, strength, effect
			)
		body.queue_free()
