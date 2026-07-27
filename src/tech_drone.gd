extends NormalDrone
class_name TechDrone

const REPAIR_LASER_SCENE := preload("res://character/weapons/RepairLaser.tscn")

@export_group("Flight")
@export var tech_move_speed := 10.0
@export var tech_ascend_speed := 7.0

@export_group("Repair Pulse")
@export var repair_pulse_cooldown := 6.0
@export var repair_pulse_range := 25.0
@export var repair_pulse_visual_speed := 60.0

@onready var action_point: Marker3D = $ActionPoint

var _repair_pulse_cooldown_left := 0.0


func _ready() -> void:
	SET_HP = CombatBalance.get_tool_max_hp("tech_drone")
	use_distance = CombatBalance.get_float("tech_drone", "signal_range")
	tech_move_speed = CombatBalance.get_float("tech_drone", "move_speed")
	tech_ascend_speed = CombatBalance.get_float("tech_drone", "ascend_speed")
	repair_pulse_cooldown = CombatBalance.get_float("tech_drone", "primary_cooldown")
	repair_pulse_range = CombatBalance.get_float("tech_drone", "repair_range")
	repair_pulse_visual_speed = CombatBalance.get_float("tech_drone", "visual_speed")
	move_speed = tech_move_speed
	ascend_speed = tech_ascend_speed
	super._ready()
	if not is_instance_valid(action_point):
		push_error("TechDrone: missing ActionPoint marker.")


func emit() -> Dictionary:
	var user_node := get_node_or_null("../../../") as Node3D
	if user_node == null or tool_owner.is_empty():
		return {}
	var raycast := user_node.find_child("LookAtTarget", true, false) as RayCast3D
	if raycast == null or not raycast.is_colliding() or GlobalVar.gameworld == null:
		return {}
	var drone := load("res://character/weapons/TechDrone.tscn").instantiate() as TechDrone
	if drone == null:
		return {}
	GlobalVar.gameworld.add_child(drone)
	drone.global_position = raycast.get_collision_point() + Vector3.UP * 0.3
	drone.tool_owner = tool_owner
	drone.activate_tool()
	return {"remote_node": drone}


func _process(delta: float) -> void:
	super._process(delta)
	_repair_pulse_cooldown_left = maxf(0.0, _repair_pulse_cooldown_left - delta)


func request_primary_action() -> void:
	if not _placed or not _remote_control_active or is_electronics_disabled() or _repair_pulse_cooldown_left > 0.0:
		return
	if get_signal_strength(_remote_receiver) < REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL:
		return
	_repair_pulse_cooldown_left = repair_pulse_cooldown
	primary_action_requested.emit()
	if _submit_repair_pulse_authority_action():
		# Local authority has no client replicator to receive the server visual.
		if GameAuthority.is_local_authority():
			_spawn_repair_laser_visual()
		return
	if GameAuthority.is_local_authority():
		_repair_pulse_cooldown_left = 0.0


func _allows_secondary_remote_actions() -> bool:
	return false


func get_primary_action_cooldown_remaining() -> float:
	return _repair_pulse_cooldown_left


func get_primary_action_cooldown_duration() -> float:
	return repair_pulse_cooldown


func _update_flight(delta: float) -> void:
	super._update_flight(delta)


func simulate_authoritative_remote_input(input_frame: Dictionary, delta: float) -> void:
	super.simulate_authoritative_remote_input(input_frame, delta)


func _apply_authoritative_snapshot(snapshot: Dictionary) -> void:
	super._apply_authoritative_snapshot(snapshot)
	var authoritative_cooldown := float(snapshot.get("primary_action_cooldown", 0.0))
	if authoritative_cooldown > 0.0:
		repair_pulse_cooldown = authoritative_cooldown
	_repair_pulse_cooldown_left = maxf(
		_repair_pulse_cooldown_left,
		float(snapshot.get("primary_action_cooldown_left", 0.0))
	)


func _electronics_balance_id() -> String:
	return "tech_drone"




func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (
		body is BoomBullet or body is RubberBullet or body is ColorBullet
		or body is NailBullet or body is DetectLaserBullet
	):
		return
	var attacker_team := str(body.call("get_bullet_owner"))
	if attacker_team == tool_owner:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = str(body.bullet_effect)
	if impact(effect, float(body.bullet_strength), attacker_team):
		body.queue_free()


func _submit_repair_pulse_authority_action() -> bool:
	var device_id := ""
	if has_meta("network_device_id"):
		device_id = str(get_meta("network_device_id"))
	elif is_inside_tree():
		device_id = str(get_path())
	if device_id.is_empty():
		return false
	var action := {
		"device_id": device_id,
		"device_path": device_id,
		"device_type": "tech_drone",
		"action": "primary",
		"position": global_position,
		"velocity": velocity,
		"yaw": rotation.y,
		"direction": _get_repair_pulse_direction(),
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_remote_action(action)
		return true
	if GameAuthority.is_local_authority():
		var result: Dictionary = GameAuthority.local_remote_action(
			GameAuthority.LOCAL_PLAYER_ID,
			action
		)
		return bool(result.get("ok", false))
	return false


func _get_repair_pulse_direction() -> Vector3:
	if not is_instance_valid(drone_camera) or not is_instance_valid(action_point):
		return -global_transform.basis.z.normalized()
	var viewport := drone_camera.get_viewport()
	if viewport == null:
		return -global_transform.basis.z.normalized()
	var screen_center := viewport.get_visible_rect().size * 0.5
	var origin := drone_camera.project_ray_origin(screen_center)
	var direction := drone_camera.project_ray_normal(screen_center).normalized()
	var query := PhysicsRayQueryParameters3D.create(
		origin,
		origin + direction * repair_pulse_range
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	query.exclude = [get_rid()]
	if is_instance_valid(hit_area):
		query.exclude.append(hit_area.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var target := origin + direction * repair_pulse_range
	if not hit.is_empty():
		target = hit.get("position", target)
	var pulse_direction := (target - action_point.global_position).normalized()
	return pulse_direction if pulse_direction.length_squared() > 0.001 else direction


func _spawn_repair_laser_visual() -> void:
	if not is_instance_valid(action_point) or GlobalVar.gameworld == null:
		return
	var laser := REPAIR_LASER_SCENE.instantiate() as RepairLaser
	if laser == null:
		return
	GlobalVar.gameworld.add_child(laser)
	laser.visual_only = true
	laser.collision_layer = 0
	laser.collision_mask = 0
	laser.run(action_point.global_position, _get_repair_pulse_direction(), tool_owner)
