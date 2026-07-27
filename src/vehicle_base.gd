extends CharacterBody3D
class_name VehicleBase

signal vehicle_destroyed()
signal vehicle_damaged(current_hp: float, max_hp: float)
signal cargo_manifest_changed(manifest: Array[Dictionary])

const GROUND_COLLISION_LAYER := 1
const BULLET_COLLISION_LAYER := 32
const BOOM_EFFECT_SCENE := preload("res://character/weapons/BoomEffect.tscn")
const VEHICLE_SHIELD_SCENE := preload("res://character/weapons/VehicleShieldBubble.tscn")
const NETWORK_INTERPOLATION_RATE := 18.0
const NETWORK_SNAP_DISTANCE := 6.0
const CARGO_SLOT_COUNT := 12

@export var vehicle_config: VehicleConfig
@export var network_id := ""
@export var owner_team := ""
## Hand-held placement previews disable vehicle physics and world registration.
@export var vehicle_deployed := true
## Map instances can start loaded without making the mutable cargo weight a resource setting.
@export_range(0.0, 500.0, 1.0, "suffix:kg") var initial_cargo_weight_kg := 0.0

@onready var vehicle_shape := $VehicleShape as CollisionShape3D
@onready var ground_probe := $GroundProbe as RayCast3D
@onready var driver_seat := $DriverSeat as Node3D
@onready var camera_orbit_yaw := $CameraOrbitYaw as Node3D
@onready var camera_orbit_pitch := $CameraOrbitYaw/CameraOrbitPitch as Node3D
@onready var vehicle_camera := $CameraOrbitYaw/CameraOrbitPitch/VehicleCamera as Camera3D
@onready var exit_point := $ExitPoint as Marker3D
@onready var hit_area := $Hit3D as Area3D
@onready var hit_shape := $Hit3D/CollisionShape3D as CollisionShape3D

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


func _ready() -> void:
	if not vehicle_deployed:
		collision_layer = 0
		collision_mask = 0
		vehicle_shape.set_deferred("disabled", true)
		hit_area.monitoring = false
		hit_area.monitorable = false
		return
	add_to_group("vehicle_bases")
	_configure_physics_nodes()
	_apply_vehicle_config()
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


func set_drive_input(throttle: float, steering: float, brake: float = 0.0) -> void:
	drive_throttle = clampf(throttle, -1.0, 1.0)
	drive_steering = clampf(steering, -1.0, 1.0)
	drive_brake = clampf(brake, 0.0, 1.0)


func simulate_authority(delta: float) -> void:
	if not vehicle_deployed or vehicle_config == null or not is_inside_tree() \
			or is_queued_for_deletion() or get_world_3d() == null:
		return
	_tick_vehicle_shield(delta)
	var target_speed := vehicle_config.max_forward_speed * maxf(drive_throttle, 0.0)
	if drive_throttle < 0.0:
		target_speed = vehicle_config.max_reverse_speed * drive_throttle
	if drive_brake > 0.01:
		current_speed = move_toward(
			current_speed,
			0.0,
			vehicle_config.brake_deceleration * drive_brake * delta
		)
	else:
		var speed_change := vehicle_config.acceleration if absf(target_speed) > absf(current_speed) else vehicle_config.rolling_deceleration
		current_speed = move_toward(current_speed, target_speed, speed_change * delta)

	var speed_ratio := clampf(absf(current_speed) / maxf(vehicle_config.max_forward_speed, 0.01), 0.0, 1.0)
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
	velocity.x = forward.x * current_speed
	velocity.z = forward.z * current_speed
	ground_probe.force_raycast_update()
	if ground_probe.is_colliding():
		velocity.y = -vehicle_config.ground_stick_speed
	else:
		var gravity_strength := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		var gravity_direction_value: Variant = ProjectSettings.get_setting("physics/3d/default_gravity_vector", Vector3.DOWN)
		var gravity_direction := gravity_direction_value as Vector3 if gravity_direction_value is Vector3 else Vector3.DOWN
		velocity += gravity_direction.normalized() * gravity_strength * delta
	move_and_slide()
	rotation.x = 0.0
	rotation.z = 0.0
	_update_vehicle_visuals(delta)


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
	}


func apply_network_state(state: Dictionary) -> void:
	var previous_hp := current_hp
	var position: Variant = state.get("position", global_position)
	var next_yaw := float(state.get("yaw", rotation.y))
	var next_speed := float(state.get("speed", current_speed))
	var next_steering := float(state.get("steering", current_steering))
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
	_refresh_driver_peer_id()
	_update_vehicle_visuals(0.0)


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
	_update_vehicle_visuals(delta)


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
	if peer_id <= 0 or current_hp <= 0.0 or get_seat_index_for_peer(peer_id) >= 0:
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
	return seat_transform * Transform3D(
		Basis.from_euler(occupant_rotation),
		seat.occupant_offset
	)


func get_exit_position(seat_index: int = -1) -> Vector3:
	if is_instance_valid(exit_point):
		return exit_point.global_position
	var definitions := _seat_definitions()
	if seat_index >= 0 and seat_index < definitions.size():
		return to_global(definitions[seat_index].exit_offset)
	return to_global(Vector3(1.8, 0.1, 0.0))


func get_driving_camera() -> Camera3D:
	return vehicle_camera


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


func _seat_definitions() -> Array[VehicleSeatConfig]:
	if vehicle_config != null and not vehicle_config.seats.is_empty():
		return vehicle_config.seats
	var fallback := VehicleSeatConfig.new()
	return [fallback]


func _refresh_driver_peer_id() -> void:
	driver_peer_id = int(seat_occupants.get(get_driver_seat_index(), 0))


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
		GameAuthority.destroy_vehicle_with_occupants(self)
		vehicle_destroyed.emit()
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


func _spawn_destruction_effect() -> void:
	var world_root: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world_root == null:
		return
	var effect := BOOM_EFFECT_SCENE.instantiate() as Node3D
	if effect == null:
		return
	world_root.add_child(effect)
	effect.global_position = global_position


func _configure_physics_nodes() -> void:
	collision_layer = 8192
	collision_mask = 12427
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
	var body_shape := vehicle_shape.shape as BoxShape3D
	if body_shape != null:
		body_shape.size = vehicle_config.collision_size
	vehicle_shape.position = vehicle_config.collision_offset
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
		# gameplay scene instead of requiring a second visual-only resource.
		body_visual = get_node_or_null("BodyVisual") as Node3D
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
	if not supports_cargo() or find_child("CargoInteractionAreas", false, false) != null:
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


func _add_cargo_interaction_area(root: Node3D, area_name: String, kind: String, position_value: Vector3, size: Vector3) -> void:
	var area := CargoCarInteractionArea.new()
	area.name = area_name
	area.interaction_kind = kind
	area.position = position_value
	root.add_child(area)
	var shape := CollisionShape3D.new()
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
	var speed_ratio := clampf(absf(current_speed) / maxf(vehicle_config.camera_speed_for_max_fov, 0.01), 0.0, 1.0)
	var target_fov := lerpf(vehicle_config.camera_base_fov, vehicle_config.camera_max_fov, speed_ratio)
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
	if impact(str(body.get("bullet_effect")), strength, attacker_team):
		body.queue_free()
