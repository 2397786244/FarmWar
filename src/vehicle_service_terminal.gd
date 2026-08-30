extends StaticBody3D
class_name VehicleServiceTerminal

## The terminal owns the short-lived interaction locks.  Money, vehicle state,
## and all service mutations still live in GameAuthority; this node only knows
## which local vehicle/player is currently standing at the terminal.
const PLAYER_INTERACTION_LAYER := 512
const PLAYER_COLLISION_LAYER := 8
const VEHICLE_COLLISION_LAYER := 8192
const PLAYER_LOCK_TIMEOUT_MSEC := 15000
const VEHICLE_EXIT_GRACE_MSEC := 1000
const PLAYER_INTERACTION_RANGE := 4.0
const OUTLINE_WIDTH := 0.035
const OUTLINE_HEIGHT := 0.035
const PLAYER_OUTLINE_COLOR := Color("ffd33d")
const VEHICLE_OUTLINE_COLOR := Color("f4f7ff")
const SERVICE_VIEW_HORIZONTAL_POSITION := 0.70
const SERVICE_VIEW_MARGIN := 1.15
const SERVICE_VIEW_MIN_DISTANCE := 3.5
const SERVICE_VIEW_MAX_DISTANCE := 24.0
const SERVICE_EFFECT_DURATION := 0.85

var active_vehicle_id := ""
var active_user_peer_id := 0
var active_user_last_activity_msec := 0
var revision := 0
var _last_empty_area_scan_msec := 0
var _vehicle_exit_recheck_pending := false
var _vehicle_overlap_missing_since_msec := 0

var _active_vehicle: VehicleBase
var _player_interact: Area3D
var _vehicle_interact: Area3D
var _outline_root: Node3D
var _service_camera: Camera3D
var _service_camera_authored_transform := Transform3D.IDENTITY
var _service_camera_view_direction_local := Vector3(-0.5, 0.35, -0.8).normalized()


func _ready() -> void:
	add_to_group("vehicle_service_facilities")
	add_to_group("vehicle_service_terminals")
	set_meta("facility_kind", "vehicle_service")
	set_meta("facility_id", "repair_terminal")
	set_meta("display_name", "升级维修终端")
	set_meta("interaction_enabled", true)
	collision_layer = 128
	collision_mask = 0
	_player_interact = get_node_or_null("PlayerInteract") as Area3D
	_vehicle_interact = get_node_or_null("VehicleInteract") as Area3D
	_service_camera = get_node_or_null("Camera3D") as Camera3D
	_initialize_service_camera()
	_configure_interaction_area(_player_interact, PLAYER_INTERACTION_LAYER, PLAYER_COLLISION_LAYER)
	_configure_interaction_area(
		_vehicle_interact,
		PLAYER_INTERACTION_LAYER,
		VEHICLE_COLLISION_LAYER | PLAYER_COLLISION_LAYER
	)
	if _player_interact != null and not _player_interact.body_entered.is_connected(_on_player_body_entered):
		_player_interact.body_entered.connect(_on_player_body_entered)
	if _vehicle_interact != null and not _vehicle_interact.body_entered.is_connected(_on_vehicle_body_entered):
		_vehicle_interact.body_entered.connect(_on_vehicle_body_entered)
	if _vehicle_interact != null and not _vehicle_interact.body_exited.is_connected(_on_vehicle_body_exited):
		_vehicle_interact.body_exited.connect(_on_vehicle_body_exited)
	_build_interaction_outlines()
	# A vehicle can be placed before the terminal enters the tree (for example
	# when a saved map restores vehicles and facilities in the same frame).  Area3D
	# does not replay body_entered for bodies that were already overlapping, so do
	# one authoritative deferred scan as well as listening for future callbacks.
	call_deferred("_scan_vehicle_interaction_area")


func _initialize_service_camera() -> void:
	if not is_instance_valid(_service_camera):
		return
	_service_camera.current = false
	_service_camera_authored_transform = _service_camera.transform
	var target_local := Vector3.ZERO
	if is_instance_valid(_vehicle_interact):
		var shape_node := _vehicle_interact.get_node_or_null("CollisionShape3D") as CollisionShape3D
		target_local = to_local(shape_node.global_position) if shape_node != null \
				else to_local(_vehicle_interact.global_position)
	var authored_offset := _service_camera.position - target_local
	if authored_offset.length_squared() > 0.001:
		_service_camera_view_direction_local = authored_offset.normalized()


func get_service_camera() -> Camera3D:
	return _service_camera if is_instance_valid(_service_camera) else null


func prepare_service_camera(vehicle: VehicleBase, viewport_size: Vector2) -> bool:
	if not is_instance_valid(_service_camera) or not _is_valid_service_vehicle(vehicle):
		deactivate_service_camera()
		return false
	refresh_service_camera(vehicle, viewport_size)
	return true


func refresh_service_camera(vehicle: VehicleBase, viewport_size: Vector2) -> void:
	if not is_instance_valid(_service_camera) or not _is_valid_service_vehicle(vehicle):
		return
	var bounds := _service_vehicle_world_bounds(vehicle)
	if bounds.size.length_squared() <= 0.001:
		return
	var center := bounds.position + bounds.size * 0.5
	var viewport_aspect := maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0)
	var vertical_half_angle := deg_to_rad(_service_camera.fov) * 0.5
	var horizontal_half_angle := atan(tan(vertical_half_angle) * viewport_aspect)
	var horizontal_half_extent := maxf(bounds.size.x, bounds.size.z) * 0.5
	var vertical_half_extent := maxf(bounds.size.y * 0.5, 0.5)
	# The left-side UI occupies roughly 38% of the viewport and the vehicle is
	# composed at 70%.  Only the smaller right-hand allowance is used for fitting
	# so wide vehicles cannot be clipped by the screen edge.
	var usable_horizontal_tangent := maxf(0.1, tan(horizontal_half_angle) * 0.55)
	var usable_vertical_tangent := maxf(0.1, tan(vertical_half_angle) * 0.82)
	var depth_padding := maxf(bounds.size.x, bounds.size.z) * 0.35
	var distance := maxf(
		horizontal_half_extent / usable_horizontal_tangent,
		vertical_half_extent / usable_vertical_tangent
	)
	distance = clampf((distance + depth_padding) * SERVICE_VIEW_MARGIN, SERVICE_VIEW_MIN_DISTANCE, SERVICE_VIEW_MAX_DISTANCE)
	var view_from_target := (global_transform.basis * _service_camera_view_direction_local).normalized()
	if view_from_target.length_squared() <= 0.001:
		view_from_target = Vector3(-0.5, 0.35, -0.8).normalized()
	_service_camera.global_position = center + view_from_target * distance
	var forward_to_center := (center - _service_camera.global_position).normalized()
	var screen_right := forward_to_center.cross(Vector3.UP).normalized()
	if screen_right.length_squared() <= 0.001:
		screen_right = global_transform.basis.x.normalized()
	var desired_ndc_x := SERVICE_VIEW_HORIZONTAL_POSITION * 2.0 - 1.0
	var composition_offset := tan(horizontal_half_angle) * desired_ndc_x * distance
	_service_camera.look_at(center - screen_right * composition_offset, Vector3.UP)
	_service_camera.far = maxf(_service_camera.far, distance + bounds.size.length() * 2.0 + 10.0)


func deactivate_service_camera() -> void:
	if not is_instance_valid(_service_camera):
		return
	_service_camera.current = false
	_service_camera.transform = _service_camera_authored_transform


func play_service_effect(action_name: String, vehicle: VehicleBase) -> void:
	if not _is_valid_service_vehicle(vehicle) or not is_inside_tree():
		return
	var bounds := _service_vehicle_world_bounds(vehicle)
	if bounds.size.length_squared() <= 0.001:
		return
	var effect_color := Color("55e6c1")
	match action_name:
		"change_color":
			effect_color = Color("e8f8ff")
		"install_module":
			effect_color = Color("74b9ff")
		"uninstall_module":
			effect_color = Color("f6b65e")
	var effect_root := Node3D.new()
	effect_root.name = "VehicleServiceEffect"
	var effect_host: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) \
			else get_tree().current_scene
	if effect_host == null:
		effect_host = get_parent()
	effect_host.add_child(effect_root)
	var center := bounds.position + bounds.size * 0.5
	effect_root.global_position = center
	var scan_root := Node3D.new()
	scan_root.name = "ScanFrame"
	scan_root.position.y = -bounds.size.y * 0.5
	effect_root.add_child(scan_root)
	var scan_material := _service_effect_material(effect_color, 0.9)
	_add_service_scan_frame(scan_root, scan_material, bounds.size)
	var particles := _make_service_particles(effect_color, bounds.size)
	effect_root.add_child(particles)
	particles.restart()
	particles.emitting = true
	var pulse_light := OmniLight3D.new()
	pulse_light.light_color = effect_color
	pulse_light.light_energy = 2.8
	pulse_light.omni_range = clampf(bounds.size.length() * 0.8, 3.0, 9.0)
	pulse_light.shadow_enabled = false
	effect_root.add_child(pulse_light)
	var tween := effect_root.create_tween()
	tween.set_parallel(true)
	tween.tween_property(scan_root, "position:y", bounds.size.y * 0.5, SERVICE_EFFECT_DURATION) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(scan_material, "albedo_color:a", 0.0, SERVICE_EFFECT_DURATION)
	tween.tween_property(pulse_light, "light_energy", 0.0, SERVICE_EFFECT_DURATION)
	get_tree().create_timer(SERVICE_EFFECT_DURATION + 0.25).timeout.connect(effect_root.queue_free)


func _is_valid_service_vehicle(vehicle: VehicleBase) -> bool:
	return vehicle != null and is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() \
			and vehicle.vehicle_deployed and vehicle.current_hp > 0.0


func _service_vehicle_world_bounds(vehicle: VehicleBase) -> AABB:
	var bounds_state := {"found": false, "bounds": AABB()}
	_collect_service_visual_bounds(vehicle, bounds_state)
	if bool(bounds_state.get("found", false)):
		return bounds_state.get("bounds", AABB()) as AABB
	if vehicle.vehicle_config != null and vehicle.vehicle_config.collision_size.length_squared() > 0.001:
		return _transformed_aabb(
			AABB(
				vehicle.vehicle_config.collision_offset - vehicle.vehicle_config.collision_size * 0.5,
				vehicle.vehicle_config.collision_size
			),
			vehicle.global_transform
		)
	return AABB(vehicle.global_position - Vector3(1.0, 0.5, 1.0), Vector3(2.0, 1.0, 2.0))


func _collect_service_visual_bounds(node: Node, bounds_state: Dictionary) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.is_visible_in_tree():
			var world_bounds := _transformed_aabb(mesh_node.get_aabb(), mesh_node.global_transform)
			if world_bounds.size.length_squared() > 0.0001:
				if bool(bounds_state.get("found", false)):
					bounds_state["bounds"] = (bounds_state.get("bounds", AABB()) as AABB).merge(world_bounds)
				else:
					bounds_state["found"] = true
					bounds_state["bounds"] = world_bounds
	for child_value: Variant in node.get_children():
		if child_value is Node:
			_collect_service_visual_bounds(child_value as Node, bounds_state)


func _transformed_aabb(local_bounds: AABB, transform_value: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	for x: float in [local_bounds.position.x, local_bounds.end.x]:
		for y: float in [local_bounds.position.y, local_bounds.end.y]:
			for z: float in [local_bounds.position.z, local_bounds.end.z]:
				var point := transform_value * Vector3(x, y, z)
				if not found:
					result = AABB(point, Vector3.ZERO)
					found = true
				else:
					result = result.expand(point)
	return result


func _service_effect_material(color_value: Color, alpha: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(color_value.r, color_value.g, color_value.b, alpha)
	material.emission_enabled = true
	material.emission = color_value
	material.emission_energy_multiplier = 4.0
	return material


func _add_service_scan_frame(parent: Node3D, material: Material, bounds_size: Vector3) -> void:
	var width := maxf(bounds_size.x, 1.2) * 1.08
	var depth := maxf(bounds_size.z, 1.2) * 1.08
	var thickness := 0.035
	for definition: Dictionary in [
		{"size": Vector3(width, thickness, thickness), "position": Vector3(0.0, 0.0, -depth * 0.5)},
		{"size": Vector3(width, thickness, thickness), "position": Vector3(0.0, 0.0, depth * 0.5)},
		{"size": Vector3(thickness, thickness, depth), "position": Vector3(-width * 0.5, 0.0, 0.0)},
		{"size": Vector3(thickness, thickness, depth), "position": Vector3(width * 0.5, 0.0, 0.0)},
	]:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = definition.get("size", Vector3.ONE) as Vector3
		mesh_instance.mesh = box
		mesh_instance.material_override = material
		mesh_instance.position = definition.get("position", Vector3.ZERO) as Vector3
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mesh_instance)


func _make_service_particles(color_value: Color, bounds_size: Vector3) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.name = "ServiceSparks"
	particles.amount = 30
	particles.lifetime = 0.55
	particles.one_shot = true
	particles.explosiveness = 0.85
	particles.randomness = 0.55
	particles.visibility_aabb = AABB(-bounds_size, bounds_size * 2.0)
	var process_material := ParticleProcessMaterial.new()
	process_material.direction = Vector3.UP
	process_material.spread = 75.0
	process_material.gravity = Vector3(0.0, -3.5, 0.0)
	process_material.initial_velocity_min = 1.2
	process_material.initial_velocity_max = 2.8
	process_material.scale_min = 0.55
	process_material.scale_max = 1.15
	process_material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process_material.emission_box_extents = Vector3(
		maxf(bounds_size.x * 0.42, 0.5),
		maxf(bounds_size.y * 0.35, 0.35),
		maxf(bounds_size.z * 0.42, 0.5)
	)
	particles.process_material = process_material
	var spark_mesh := BoxMesh.new()
	spark_mesh.size = Vector3(0.025, 0.025, 0.18)
	spark_mesh.material = _service_effect_material(color_value, 1.0)
	particles.draw_pass_1 = spark_mesh
	return particles


func _configure_interaction_area(area: Area3D, layer: int, mask: int) -> void:
	if area == null:
		return
	area.collision_layer = layer
	area.collision_mask = mask
	area.monitoring = true
	area.monitorable = true


func _scan_vehicle_interaction_area() -> void:
	if _vehicle_interact == null or not is_instance_valid(_vehicle_interact):
		return
	for body_value: Variant in _vehicle_interact.get_overlapping_bodies():
		if body_value is Node3D:
			_on_vehicle_body_entered(body_value as Node3D)


func has_vehicle_in_interaction_area() -> bool:
	# The authoritative lock normally tells us immediately which vehicle is in
	# the bay.  Keep the physical-area fallback as well so the player prompt
	# cannot briefly reappear while the first body-entered callback or a world
	# restore is still being processed.
	var active_vehicle := get_active_vehicle()
	if active_vehicle != null and _vehicle_is_in_interaction_area(active_vehicle):
		return true
	if _vehicle_interact == null or not is_instance_valid(_vehicle_interact):
		return false
	for body_value: Variant in _vehicle_interact.get_overlapping_bodies():
		if not body_value is Node:
			continue
		var vehicle := _vehicle_from_node(body_value as Node)
		if vehicle != null and is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion() \
				and vehicle.vehicle_deployed and vehicle.current_hp > 0.0:
			return true
	return false


## Called by the authoritative tick instead of relying on a client-owned timer.
func authority_tick(_delta: float) -> void:
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		return
	var now_msec := Time.get_ticks_msec()
	if active_vehicle_id.is_empty():
		# World restore can finish after this node's _ready() callback.  Re-scan
		# periodically while empty so a vehicle that was already inside the zone
		# cannot bypass the exclusive lock just because signal ordering differed.
		if now_msec - _last_empty_area_scan_msec >= 250:
			_last_empty_area_scan_msec = now_msec
			_scan_vehicle_interaction_area()
		if active_vehicle_id.is_empty():
			return
	var vehicle := get_active_vehicle()
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion() \
			or not vehicle.vehicle_deployed or vehicle.current_hp <= 0.0:
		_clear_lock(true)
		return
	if active_user_peer_id > 0:
		if now_msec - active_user_last_activity_msec > PLAYER_LOCK_TIMEOUT_MSEC \
				or not _peer_is_in_player_range(active_user_peer_id):
			_clear_user_lock()
	# Vehicle occupancy is a physical-area lock, not a lease. A parked vehicle
	# remains valid indefinitely; timeout recovery applies only to the player who
	# owns the UI session. Missing/invalid vehicles are handled above, and a real
	# area exit clears the lock without affecting the vehicle lifecycle.
	_update_vehicle_overlap_lock(vehicle, now_msec)


func _on_vehicle_body_entered(body: Node3D) -> void:
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		return
	var vehicle := _vehicle_from_node(body)
	if vehicle == null or not vehicle.vehicle_deployed or vehicle.current_hp <= 0.0 \
			or vehicle.is_queued_for_deletion():
		return
	var state := vehicle.get_network_state()
	if bool(state.get("spawn_drop_active", false)):
		return
	if not active_vehicle_id.is_empty():
		return
	_active_vehicle = vehicle
	active_vehicle_id = vehicle.get_vehicle_id()
	_vehicle_overlap_missing_since_msec = 0
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	_bump_revision_and_emit()


func _on_vehicle_body_exited(body: Node3D) -> void:
	var vehicle := _vehicle_from_node(body)
	if vehicle == null or active_vehicle_id.is_empty() \
			or vehicle.get_vehicle_id() != active_vehicle_id:
		return
	# FarmBaseVehicle modules can contribute child physics bodies. One module
	# leaving the Area3D must not release the whole vehicle while another body is
	# still overlapping, so reconcile after the physics overlap list settles.
	if _vehicle_exit_recheck_pending:
		return
	_vehicle_exit_recheck_pending = true
	call_deferred("_reconcile_vehicle_exit", active_vehicle_id)


func _reconcile_vehicle_exit(expected_vehicle_id: String) -> void:
	_vehicle_exit_recheck_pending = false
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()) \
			or expected_vehicle_id.is_empty() or active_vehicle_id != expected_vehicle_id:
		return
	var vehicle := get_active_vehicle()
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion() \
			or not vehicle.vehicle_deployed or vehicle.current_hp <= 0.0:
		# Leaving the bay only releases terminal state. Vehicle destruction remains
		# exclusively owned by normal HP/combat lifecycle code.
		_clear_lock(true)
		return
	_update_vehicle_overlap_lock(vehicle, Time.get_ticks_msec())


func _update_vehicle_overlap_lock(vehicle: VehicleBase, now_msec: int) -> void:
	if _vehicle_is_in_interaction_area(vehicle):
		_vehicle_overlap_missing_since_msec = 0
		return
	# Dynamic FarmBaseVehicle modules can make Area3D's overlap cache briefly
	# report no bodies while shapes are being rebuilt. Require a continuous miss
	# before treating it as a real bay exit; this lock never owns vehicle motion,
	# HP or destruction.
	if _vehicle_overlap_missing_since_msec <= 0:
		_vehicle_overlap_missing_since_msec = now_msec
		return
	if now_msec - _vehicle_overlap_missing_since_msec >= VEHICLE_EXIT_GRACE_MSEC:
		_clear_lock(true)


func _vehicle_is_in_interaction_area(vehicle: VehicleBase) -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or vehicle.is_queued_for_deletion() \
			or _vehicle_interact == null or not is_instance_valid(_vehicle_interact):
		return false
	for body_value: Variant in _vehicle_interact.get_overlapping_bodies():
		if body_value is Node and _vehicle_from_node(body_value as Node) == vehicle:
			return true
	return false


func _on_player_body_entered(_body: Node3D) -> void:
	# PlayerInteract is intentionally passive. The player scans this area and
	# requests the exclusive user lock through shop_transaction.acquire.
	pass


func _vehicle_from_node(node: Node) -> VehicleBase:
	var current := node
	while current != null:
		if current is VehicleBase:
			return current as VehicleBase
		current = current.get_parent()
	return null


func get_terminal_id() -> String:
	for key in ["network_map_facility_id", "network_device_id", "facility_id"]:
		var value := str(get_meta(key, ""))
		if not value.is_empty():
			return value
	return str(get_path())


func get_interaction_position() -> Vector3:
	var marker := find_child("PlayerInteractionPosition", true, false) as Node3D
	return marker.global_position if marker != null else global_position


func get_active_vehicle() -> VehicleBase:
	if is_instance_valid(_active_vehicle) and not _active_vehicle.is_queued_for_deletion() \
			and _active_vehicle.get_vehicle_id() == active_vehicle_id:
		return _active_vehicle
	if active_vehicle_id.is_empty():
		return null
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).get_vehicle_id() == active_vehicle_id:
			_active_vehicle = node as VehicleBase
			return _active_vehicle
	_active_vehicle = null
	return null


func is_vehicle_active(vehicle_id: String) -> bool:
	return not vehicle_id.is_empty() and vehicle_id == active_vehicle_id \
		and get_active_vehicle() != null


func can_player_interact(player: GamePlayer) -> bool:
	if not is_instance_valid(player) or player.is_remote_proxy or active_vehicle_id.is_empty():
		return false
	var vehicle := get_active_vehicle()
	if vehicle == null or vehicle.current_hp <= 0.0 or vehicle.is_queued_for_deletion():
		return false
	if not vehicle.owner_team.is_empty() and vehicle.owner_team != player.team:
		return false
	return is_player_in_player_area(player)


func is_player_in_player_area(player: GamePlayer) -> bool:
	if not is_instance_valid(player):
		return false
	if _player_interact != null:
		return _player_interact.overlaps_body(player)
	return player.global_position.distance_to(get_interaction_position()) <= PLAYER_INTERACTION_RANGE


func _peer_is_in_player_range(peer_id: int) -> bool:
	if peer_id <= 0 or not is_instance_valid(GameAuthority):
		return false
	var state: Variant = GameAuthority.player_states.get(peer_id, {})
	if not state is Dictionary:
		return false
	if float((state as Dictionary).get("respawn_left", 0.0)) > 0.0:
		return false
	var position_value: Variant = (state as Dictionary).get("position", null)
	if not position_value is Vector3:
		return false
	return (position_value as Vector3).distance_to(get_interaction_position()) <= PLAYER_INTERACTION_RANGE + 0.75


func can_peer_access_active_vehicle(peer_id: int) -> bool:
	if not is_instance_valid(GameAuthority) or not GameAuthority.player_states.has(peer_id):
		return false
	var state: Dictionary = GameAuthority.player_states[peer_id]
	var vehicle := get_active_vehicle()
	if vehicle == null:
		return false
	var team := str(state.get("team", ""))
	return (vehicle.owner_team.is_empty() or vehicle.owner_team == team) and _peer_is_in_player_range(peer_id)


func is_player_lock_owner(peer_id: int) -> bool:
	return peer_id > 0 and active_user_peer_id == peer_id


func try_acquire_user(peer_id: int) -> bool:
	if not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()) \
			or not can_peer_access_active_vehicle(peer_id):
		return false
	if active_user_peer_id > 0 and active_user_peer_id != peer_id:
		return false
	active_user_peer_id = peer_id
	var now_msec := Time.get_ticks_msec()
	active_user_last_activity_msec = now_msec
	_bump_revision_and_emit()
	return true


func release_user(peer_id: int) -> bool:
	if active_user_peer_id != peer_id:
		return active_user_peer_id == 0
	_clear_user_lock()
	return true


func touch_user(peer_id: int) -> bool:
	if active_user_peer_id != peer_id or not can_peer_access_active_vehicle(peer_id):
		return false
	var now_msec := Time.get_ticks_msec()
	active_user_last_activity_msec = now_msec
	return true


func get_interaction_hint(player: GamePlayer) -> String:
	if active_vehicle_id.is_empty() or get_active_vehicle() == null:
		return "把载具开到这个区域中"
	if active_user_peer_id > 0 and active_user_peer_id != player.authority_peer_id:
		return "队友正在操作升级维修终端"
	return "按「E」打开升级和维修终端"


func get_network_state() -> Dictionary:
	return {
		"terminal_id": get_terminal_id(),
		"active_vehicle_id": active_vehicle_id,
		"active_user_peer_id": active_user_peer_id,
		"locked": not active_vehicle_id.is_empty() or active_user_peer_id > 0,
		"revision": revision,
	}


func apply_network_state(state: Dictionary) -> void:
	var incoming_revision := int(state.get("revision", revision))
	if incoming_revision < revision:
		return
	revision = incoming_revision
	active_vehicle_id = str(state.get("active_vehicle_id", ""))
	active_user_peer_id = int(state.get("active_user_peer_id", 0))
	_active_vehicle = null


func on_vehicle_destroyed(vehicle_id: String) -> void:
	if vehicle_id == active_vehicle_id:
		_clear_lock(true)


func reset_runtime_state() -> void:
	# Terminal locks are runtime-only.  Never carry a vehicle/user lock across a
	# match restart or a cooperative world reload, and do not emit a stale event
	# while the authority is rebuilding its state.
	active_vehicle_id = ""
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	_active_vehicle = null
	_last_empty_area_scan_msec = 0
	_vehicle_exit_recheck_pending = false
	_vehicle_overlap_missing_since_msec = 0
	revision = 0


func _clear_user_lock() -> void:
	if active_user_peer_id == 0:
		return
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	_bump_revision_and_emit()


func _clear_lock(emit_state: bool) -> void:
	var changed := not active_vehicle_id.is_empty() or active_user_peer_id > 0
	active_vehicle_id = ""
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	_active_vehicle = null
	_vehicle_overlap_missing_since_msec = 0
	if changed and emit_state:
		_bump_revision_and_emit()


func _bump_revision_and_emit() -> void:
	revision += 1
	if not is_instance_valid(GameAuthority):
		return
	GameAuthority.reliable_world_event_ready.emit({
		"type": "vehicle_service_state",
		"terminal_id": get_terminal_id(),
		"owner_team": str(get_active_vehicle().owner_team) if get_active_vehicle() != null else "",
		"state": get_network_state(),
		"active_vehicle_id": active_vehicle_id,
		"active_user_peer_id": active_user_peer_id,
		"locked": not active_vehicle_id.is_empty() or active_user_peer_id > 0,
		"revision": revision,
		"tick": GameAuthority.server_tick,
	})


func _build_interaction_outlines() -> void:
	if _outline_root != null:
		return
	_outline_root = Node3D.new()
	_outline_root.name = "InteractionOutlines"
	add_child(_outline_root)
	_add_area_outline(_player_interact, PLAYER_OUTLINE_COLOR, "PlayerInteractOutline")
	_add_area_outline(_vehicle_interact, VEHICLE_OUTLINE_COLOR, "VehicleInteractOutline")


func _add_area_outline(area: Area3D, color: Color, outline_name: String) -> void:
	if area == null:
		return
	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	var box := shape_node.shape as BoxShape3D if shape_node != null else null
	if box == null:
		return
	var root := Node3D.new()
	root.name = outline_name
	area.add_child(root)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.95
	var half := box.size * 0.5
	var y := shape_node.position.y + half.y + 0.025
	_add_outline_bar(root, material, Vector3(box.size.x, OUTLINE_HEIGHT, OUTLINE_WIDTH), Vector3(shape_node.position.x, y, shape_node.position.z - half.z))
	_add_outline_bar(root, material, Vector3(box.size.x, OUTLINE_HEIGHT, OUTLINE_WIDTH), Vector3(shape_node.position.x, y, shape_node.position.z + half.z))
	_add_outline_bar(root, material, Vector3(OUTLINE_WIDTH, OUTLINE_HEIGHT, box.size.z), Vector3(shape_node.position.x - half.x, y, shape_node.position.z))
	_add_outline_bar(root, material, Vector3(OUTLINE_WIDTH, OUTLINE_HEIGHT, box.size.z), Vector3(shape_node.position.x + half.x, y, shape_node.position.z))


func _add_outline_bar(parent: Node3D, material: Material, size: Vector3, position: Vector3) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	mesh_instance.position = position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mesh_instance)
