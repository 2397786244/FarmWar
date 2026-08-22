extends StaticBody3D
class_name VehicleBaseMachineGun

signal destroyed(machine_gun: VehicleBaseMachineGun, operator_peer_id: int)

const MAX_HP := 1000.0
const DAMAGE := 35.0
const RANGE_METERS := 120.0
const FIRE_COOLDOWN_SECONDS := 0.2
const MAX_YAW_DEGREES := 120.0
const MIN_ELEVATION_DEGREES := -25.0
const MAX_ELEVATION_DEGREES := 45.0
const VISUAL_SPEED_MULTIPLIER := 2.0

@export var current_hp := MAX_HP

var yaw_degrees := 0.0
var elevation_degrees := 0.0
var operator_peer_id := 0
var destroyed_state := false
var last_fire_msec := -1000000
var shot_sequence := 0

var _mesh: Node3D
var _yaw_pivot: Node3D
var _pitch_pivot: Node3D
var _base_hit_area: Area3D
var _gun_hit_area: Area3D
var _stand_pos: Marker3D
var _muzzle: Marker3D
var _muzzle_flash: GPUParticles3D
var _muzzle_flash_visual: Node
var _right_hand_grip: Marker3D
var _pitch_follow_offsets: Dictionary = {}
var _stand_offset := Transform3D.IDENTITY


func _ready() -> void:
	add_to_group("mounted_vehicle_machine_guns")
	_cache_nodes()
	_configure_collision()
	_capture_follow_offsets()
	set_aim(yaw_degrees, elevation_degrees)
	_apply_destroyed_visuals()


func _cache_nodes() -> void:
	_mesh = find_child("Mesh", true, false) as Node3D
	_yaw_pivot = find_child("MachineGunYawPivot", true, false) as Node3D
	_pitch_pivot = find_child("MachineGunPitchPivot", true, false) as Node3D
	_base_hit_area = find_child("BaseHit3D", true, false) as Area3D
	_gun_hit_area = find_child("GunHit3D", true, false) as Area3D
	_stand_pos = find_child("StandPos", true, false) as Marker3D
	_muzzle = find_child("Muzzle", true, false) as Marker3D
	_muzzle_flash = find_child("MuzzleFlash", true, false) as GPUParticles3D
	_muzzle_flash_visual = find_child("MuzzleFlashVisual", true, false)
	_right_hand_grip = find_child("RightHandGrip", true, false) as Marker3D
	for required: Node in [_mesh, _yaw_pivot, _pitch_pivot, _base_hit_area, _gun_hit_area, _stand_pos, _muzzle, _muzzle_flash, _right_hand_grip]:
		if required == null:
			push_error("VehicleBaseMachineGun: missing required recursive child in %s." % get_path())


func _configure_collision() -> void:
	# This StaticBody3D is mounted below a moving VehicleBase. It must never be
	# part of world body collision, otherwise the vehicle (whose mask includes
	# TOOL) continuously collides with its own child and starts jumping. The two
	# Hit3D areas below are the complete combat hitboxes.
	collision_layer = 0
	collision_mask = 0
	for hit_area: Area3D in [_base_hit_area, _gun_hit_area]:
		if hit_area == null:
			continue
		hit_area.collision_layer = GameAuthority.COLLISION_LAYER_TOOL
		hit_area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET
		hit_area.monitoring = true
		hit_area.monitorable = true


func _capture_follow_offsets() -> void:
	_pitch_follow_offsets.clear()
	if _pitch_pivot != null:
		for follower: Node3D in [_gun_hit_area, _muzzle, _right_hand_grip]:
			if follower != null:
				_pitch_follow_offsets[follower] = _pitch_pivot.global_transform.affine_inverse() * follower.global_transform
	if _yaw_pivot != null and _stand_pos != null:
		_stand_offset = _yaw_pivot.global_transform.affine_inverse() * _stand_pos.global_transform


func set_aim(next_yaw_degrees: float, next_elevation_degrees: float) -> void:
	yaw_degrees = clampf(next_yaw_degrees, -MAX_YAW_DEGREES, MAX_YAW_DEGREES)
	elevation_degrees = clampf(
		next_elevation_degrees,
		MIN_ELEVATION_DEGREES,
		MAX_ELEVATION_DEGREES
	)
	if _yaw_pivot != null:
		_yaw_pivot.rotation.y = deg_to_rad(yaw_degrees)
	if _pitch_pivot != null:
		# The barrel points along local +Z. In Godot, rotating +X negatively
		# raises +Z, so logical positive elevation maps to negative pivot X.
		_pitch_pivot.rotation.x = deg_to_rad(-elevation_degrees)
	_sync_followers()


func _sync_followers() -> void:
	if _pitch_pivot != null:
		for follower_value: Variant in _pitch_follow_offsets.keys():
			var follower := follower_value as Node3D
			if is_instance_valid(follower):
				follower.global_transform = _pitch_pivot.global_transform * (_pitch_follow_offsets[follower] as Transform3D)
	if _yaw_pivot != null and _stand_pos != null:
		_stand_pos.global_transform = _yaw_pivot.global_transform * _stand_offset


func get_stand_transform() -> Transform3D:
	return _stand_pos.global_transform if _stand_pos != null else global_transform


func get_right_hand_grip() -> Marker3D:
	return _right_hand_grip


func get_muzzle_origin() -> Vector3:
	return _muzzle.global_position if _muzzle != null else global_position + global_basis.z * 2.0


func get_fire_direction() -> Vector3:
	var direction := _muzzle.global_basis.z.normalized() if _muzzle != null else global_basis.z.normalized()
	return direction if direction.length_squared() > 0.001 else Vector3.BACK


func get_visual_speed() -> float:
	return maxf(
		0.01,
		CombatBalance.get_float("nail_gun", "visual_speed", 90.0) * VISUAL_SPEED_MULTIPLIER
	)


func can_fire(now_msec := Time.get_ticks_msec()) -> bool:
	return not destroyed_state and operator_peer_id > 0 \
		and now_msec - last_fire_msec >= roundi(FIRE_COOLDOWN_SECONDS * 1000.0)


func mark_fired(now_msec := Time.get_ticks_msec()) -> void:
	last_fire_msec = now_msec
	shot_sequence += 1
	play_muzzle_flash()


func play_muzzle_flash() -> void:
	if destroyed_state:
		return
	if is_instance_valid(_muzzle_flash_visual) and _muzzle_flash_visual.has_method("play"):
		_muzzle_flash_visual.call("play", DAMAGE)
	elif _muzzle_flash != null:
		_muzzle_flash.restart()
		_muzzle_flash.emitting = true


func impact(_effect: String, damage: float, attacker_team: String) -> bool:
	if destroyed_state or damage <= 0.0:
		return false
	var vehicle := get_parent_vehicle()
	if vehicle != null and not attacker_team.is_empty() and vehicle.owner_team == attacker_team:
		return false
	current_hp = maxf(0.0, current_hp - damage)
	if current_hp <= 0.0:
		_destroy()
	return true


func _destroy() -> void:
	if destroyed_state:
		return
	destroyed_state = true
	current_hp = 0.0
	var former_operator := operator_peer_id
	operator_peer_id = 0
	_apply_destroyed_visuals()
	destroyed.emit(self, former_operator)
	var vehicle := get_parent_vehicle()
	if vehicle != null:
		vehicle.on_platform_machine_gun_destroyed(former_operator)


func set_destroyed_state(value: bool) -> void:
	destroyed_state = value
	if destroyed_state:
		current_hp = 0.0
		operator_peer_id = 0
	_apply_destroyed_visuals()


func _apply_destroyed_visuals() -> void:
	if _mesh != null:
		_mesh.visible = not destroyed_state
	for collision_object: CollisionObject3D in [_base_hit_area, _gun_hit_area]:
		if collision_object == null:
			continue
		collision_object.collision_layer = 0 if destroyed_state else GameAuthority.COLLISION_LAYER_TOOL
		collision_object.collision_mask = 0 if destroyed_state else GameAuthority.COLLISION_LAYER_BULLET
	for child in find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred("disabled", destroyed_state)
	# Keep the mounted StaticBody out of body collision in both alive and broken
	# states. Combat detection is exclusively owned by BaseHit3D/GunHit3D.
	collision_layer = 0
	collision_mask = 0


func get_parent_vehicle() -> FarmBaseVehicle:
	var cursor := get_parent()
	while cursor != null:
		if cursor is FarmBaseVehicle:
			return cursor as FarmBaseVehicle
		cursor = cursor.get_parent()
	return null


func get_raycast_exclusions() -> Array[RID]:
	var exclusions: Array[RID] = []
	for node: Node in find_children("*", "CollisionObject3D", true, false):
		var collision_object := node as CollisionObject3D
		if collision_object != null:
			exclusions.append(collision_object.get_rid())
	exclusions.append(get_rid())
	var vehicle := get_parent_vehicle()
	if vehicle != null:
		exclusions.append(vehicle.get_rid())
		for node: Node in vehicle.find_children("*", "CollisionObject3D", true, false):
			var collision_object := node as CollisionObject3D
			if collision_object != null and not exclusions.has(collision_object.get_rid()):
				exclusions.append(collision_object.get_rid())
	return exclusions


func get_network_state() -> Dictionary:
	return {
		"installed": true,
		"hp": current_hp,
		"destroyed": destroyed_state,
		"yaw": yaw_degrees,
		"elevation": elevation_degrees,
		"operator_peer_id": operator_peer_id,
		"shot_sequence": shot_sequence,
	}


func apply_network_state(state: Dictionary) -> void:
	current_hp = clampf(float(state.get("hp", current_hp)), 0.0, MAX_HP)
	operator_peer_id = int(state.get("operator_peer_id", operator_peer_id))
	set_aim(float(state.get("yaw", yaw_degrees)), float(state.get("elevation", elevation_degrees)))
	var next_shot_sequence := int(state.get("shot_sequence", shot_sequence))
	if next_shot_sequence > shot_sequence:
		play_muzzle_flash()
	shot_sequence = next_shot_sequence
	set_destroyed_state(bool(state.get("destroyed", current_hp <= 0.0)))
