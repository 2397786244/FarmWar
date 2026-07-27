extends StaticBody3D
class_name BigMouthTool

const CombatBalance = preload("res://src/combat_balance.gd")

@export var tool_owner := ""
@export var activate_on_ready := false
@export var network_device_id := ""

var detection_length := 0.0
var detection_width := 0.0
var capture_seconds := 0.0
var rearm_cooldown := 0.0
var tongue_extend_seconds := 0.0
var tongue_retract_seconds := 0.0
var max_hp := 0.0

var activated := false
var triggered := false
var current_hp := 0.0
var tongue_root: Node3D
var victim_anchor: Node3D
var detection_cast: ShapeCast3D
var capture_ray: RayCast3D
var health_label: Label3D
var tongue_rest_scale := Vector3.ONE
var tongue_tween: Tween
var rearm_generation := 0
var captured_peer_id := 0
var captured_body: Node
var captured_body_exit_callable := Callable()


func _ready() -> void:
	detection_length = CombatBalance.get_float("big_mouth", "detection_length")
	detection_width = CombatBalance.get_float("big_mouth", "detection_width")
	capture_seconds = CombatBalance.get_float("big_mouth", "capture_seconds")
	rearm_cooldown = CombatBalance.get_float("big_mouth", "rearm_cooldown")
	tongue_extend_seconds = CombatBalance.get_float("big_mouth", "tongue_extend_seconds")
	tongue_retract_seconds = CombatBalance.get_float("big_mouth", "tongue_retract_seconds")
	max_hp = CombatBalance.get_tool_max_hp("big_mouth")
	current_hp = max_hp
	tongue_root = find_child("TongueRoot", true, false) as Node3D
	victim_anchor = find_child("VictimAnchor", true, false) as Node3D
	detection_cast = get_node_or_null("DetectionCast") as ShapeCast3D
	capture_ray = get_node_or_null("CaptureRay") as RayCast3D
	health_label = get_node_or_null("HealthLabel") as Label3D
	if is_instance_valid(tongue_root):
		tongue_rest_scale = tongue_root.scale
	_set_detection_enabled(false)
	_update_health_label()
	if not network_device_id.is_empty():
		add_to_group("network_map_devices")
		set_meta("network_device_id", network_device_id)
	if activate_on_ready:
		activate_tool()
		if not GameAuthority.is_client_proxy() and not network_device_id.is_empty():
			GameAuthority.register_map_placed_tool(self, "big_mouth", network_device_id, tool_owner)

func activate_tool() -> void:
	activated = true
	collision_layer = 128
	var body_shape := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if body_shape != null:
		body_shape.set_deferred("disabled", false)
	_set_detection_enabled(not GameAuthority.is_client_proxy() and not triggered)


func set_server_authority_simulation(enabled: bool) -> void:
	_set_detection_enabled(activated and enabled and not triggered)


func _physics_process(_delta: float) -> void:
	if not activated or triggered or GameAuthority.is_client_proxy() \
			or not is_instance_valid(detection_cast) or not detection_cast.enabled:
		return
	detection_cast.force_shapecast_update()
	for collision_index in range(detection_cast.get_collision_count()):
		var collider := detection_cast.get_collider(collision_index)
		if collider is Node3D and _try_capture_body(collider as Node3D):
			return


func apply_network_triggered() -> void:
	_play_tongue_attack()


func release_capture_early() -> void:
	rearm_generation += 1
	_clear_captured_body_watch()
	captured_peer_id = 0
	if is_instance_valid(tongue_tween):
		tongue_tween.kill()
	if is_instance_valid(tongue_root):
		tongue_root.scale = tongue_rest_scale
	triggered = false
	_set_detection_enabled(activated and not GameAuthority.is_client_proxy() and current_hp > 0.0)


func finish_capture_hold() -> void:
	_clear_captured_body_watch()
	captured_peer_id = 0


func get_victim_anchor_position() -> Vector3:
	if is_instance_valid(victim_anchor):
		return victim_anchor.global_position
	return global_position + Vector3.UP * 1.2


func impact(_effect: String, strength: float, attacker_team: String = "") -> bool:
	if GameAuthority.should_send_network_requests() or strength <= 0.0 or current_hp <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == str(tool_owner):
		return false
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	return true


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_update_health_label()


func _try_capture_body(body: Node3D) -> bool:
	if not activated or triggered or GameAuthority.is_client_proxy():
		return false
	if not _is_live_node(body):
		return false
	var peer_id := GameAuthority.get_authority_player_peer_id(body)
	if peer_id <= 0 or not _is_candidate_in_capture_lane(body):
		return false
	if not _ray_confirms_candidate(body):
		return false
	if not _is_live_node(body):
		release_capture_early()
		return false
	if GameAuthority.capture_player_with_big_mouth(
		self,
		peer_id,
		get_victim_anchor_position(),
		capture_seconds
	):
		captured_peer_id = peer_id
		_watch_captured_body(body, peer_id)
		_play_tongue_attack()
		return true
	return false


func _is_candidate_in_capture_lane(body: Node3D) -> bool:
	var local_position := to_local(body.global_position)
	return local_position.z <= 0.25 and local_position.z >= -detection_length \
		and absf(local_position.x) <= detection_width * 0.5 \
		and absf(local_position.y) <= 3.0


func _ray_confirms_candidate(body: Node3D) -> bool:
	if not _is_live_node(body) \
			or not is_instance_valid(capture_ray):
		return false
	var local_target := capture_ray.to_local(body.global_position + Vector3.UP * 0.9)
	if local_target.length() > detection_length + 1.0:
		return false
	capture_ray.target_position = local_target
	capture_ray.force_raycast_update()
	if not capture_ray.is_colliding():
		return false
	var collider := capture_ray.get_collider()
	if not collider is Node or not _is_live_node(collider as Node):
		return false
	return collider == body or GameAuthority.get_authority_player_peer_id(collider as Node) \
		== GameAuthority.get_authority_player_peer_id(body)


func _play_tongue_attack() -> void:
	if triggered:
		return
	triggered = true
	rearm_generation += 1
	var generation := rearm_generation
	_set_detection_enabled(false)
	if is_instance_valid(tongue_root):
		var extended_scale := tongue_rest_scale
		extended_scale.z = detection_length
		tongue_tween = create_tween()
		tongue_tween.tween_property(tongue_root, "scale", extended_scale, tongue_extend_seconds) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		tongue_tween.tween_property(tongue_root, "scale", tongue_rest_scale, tongue_retract_seconds) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_IN)
	get_tree().create_timer(rearm_cooldown).timeout.connect(_finish_rearm_cooldown.bind(generation))


func _finish_rearm_cooldown(generation: int) -> void:
	if not is_instance_valid(self) or generation != rearm_generation or current_hp <= 0.0:
		return
	triggered = false
	_clear_captured_body_watch()
	captured_peer_id = 0
	if is_instance_valid(tongue_root):
		tongue_root.scale = tongue_rest_scale
	_set_detection_enabled(activated and not GameAuthority.is_client_proxy())


func _set_detection_enabled(enabled: bool) -> void:
	if is_instance_valid(detection_cast):
		detection_cast.enabled = enabled
	if is_instance_valid(capture_ray):
		capture_ray.enabled = enabled


func _on_captured_body_tree_exiting(peer_id: int) -> void:
	if peer_id != captured_peer_id or not triggered or GameAuthority.is_client_proxy():
		return
	# The signal is currently being emitted, so clear the stored watch without
	# trying to disconnect it from the exiting node.
	captured_body = null
	captured_body_exit_callable = Callable()
	if not GameAuthority.release_big_mouth_capture(peer_id, "target_removed"):
		release_capture_early()


func _exit_tree() -> void:
	if captured_peer_id > 0 and not GameAuthority.is_client_proxy():
		GameAuthority.release_big_mouth_capture(captured_peer_id, "device_removed")
	_clear_captured_body_watch()
	captured_peer_id = 0


func _is_live_node(node: Node) -> bool:
	return is_instance_valid(node) and node.is_inside_tree() and not node.is_queued_for_deletion()


func _watch_captured_body(body: Node, peer_id: int) -> void:
	_clear_captured_body_watch()
	captured_body = body
	captured_body_exit_callable = _on_captured_body_tree_exiting.bind(peer_id)
	if not body.tree_exiting.is_connected(captured_body_exit_callable):
		body.tree_exiting.connect(captured_body_exit_callable, CONNECT_ONE_SHOT)


func _clear_captured_body_watch() -> void:
	if is_instance_valid(captured_body) and captured_body_exit_callable.is_valid() \
			and captured_body.tree_exiting.is_connected(captured_body_exit_callable):
		captured_body.tree_exiting.disconnect(captured_body_exit_callable)
	captured_body = null
	captured_body_exit_callable = Callable()


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.text = "HP: %d / %d" % [ceili(current_hp), ceili(max_hp)]
