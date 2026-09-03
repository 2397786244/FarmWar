extends MapDefenseFacility
class_name RoadBarrier

## A left-side road barrier with an independently damageable arm.
##
## The control box remains the authoritative MapDefenseFacility health target.
## The arm is deliberately kept as a second component so bullets and vehicle
## contacts can resolve the actual part that was hit without changing the
## collision behaviour of the rest of the map-defense system.

signal barrier_state_changed(raised: bool)

const CONTROL_COMPONENT := "control"
const ARM_COMPONENT := "arm"
const TEST_ENTER_AREA_LAYER := 512
const TEST_ENTER_AREA_MASK := 8 | 8192
const EMPTY_TEST_ENTER_AREA_LOWER_DELAY := 10.0
const TEST_ENTER_AREA_RECONCILE_INTERVAL := 0.25
const TEST_ENTER_OUTLINE_COLOR := Color(1.0, 1.0, 1.0, 0.96)
const TEST_ENTER_OUTLINE_WIDTH := 0.055
const TEST_ENTER_OUTLINE_HEIGHT := 0.035
const TEST_ENTER_OUTLINE_Y_OFFSET := 0.012
const BARRIER_MOTION_DURATION := 2.5

@export var arm_max_hp := 100.0
@export var starts_raised := false
@export_range(-180.0, 180.0, 1.0) var arm_rotation_degrees := 90.0

var arm_current_hp := 0.0
var arm_destroyed := false
var is_raised := false

var _mesh_root: Node3D
var _barrier_arm: Node3D
var _arm_shape: CollisionShape3D
var _control_hit_area: Area3D
var _arm_hit_area: Area3D
var _test_enter_area: Area3D
var _navigation_obstacle: NavigationObstacle3D
var _test_enter_occupants: Dictionary = {}
var _test_enter_empty_elapsed := 0.0
var _test_enter_reconcile_elapsed := 0.0
var _test_enter_outline_root: Node3D

var _initial_arm_visual_transform := Transform3D.IDENTITY
var _initial_arm_shape_transform := Transform3D.IDENTITY
var _initial_arm_hit_transform := Transform3D.IDENTITY
var _arm_pivot := Vector3.ZERO
var _arm_transforms_cached := false
var _arm_current_angle_degrees := 0.0
var _barrier_motion_tween: Tween


func _ready() -> void:
	# A map road barrier is deliberately neutral.  Its empty owner is also used
	# by hit filtering to distinguish it from a team-owned defensive structure.
	tool_owner = ""
	_resolve_barrier_nodes()
	arm_current_hp = maxf(0.0, arm_max_hp)
	arm_destroyed = false
	# MapDefenseFacility._ready() calls _set_defense_active(). Keep the initial
	# pose down until all original transforms have been cached below.
	is_raised = false
	super._ready()
	_cache_arm_transforms()
	is_raised = starts_raised and not arm_destroyed and not destroyed
	_apply_barrier_pose()
	_set_defense_active(not destroyed)
	add_to_group("road_barriers")
	add_to_group("ai_demolition_target")
	set_meta("road_barrier", true)
	set_meta("ai_demolition_target", true)
	_connect_component_hit_areas()
	_setup_test_enter_area()


func _process(delta: float) -> void:
	if not _is_test_enter_authority() or not is_instance_valid(_test_enter_area):
		return
	_test_enter_reconcile_elapsed += delta
	if _test_enter_reconcile_elapsed >= TEST_ENTER_AREA_RECONCILE_INTERVAL:
		_test_enter_reconcile_elapsed = 0.0
		_reconcile_test_enter_occupants()
	if _test_enter_occupants.is_empty():
		if is_raised:
			_test_enter_empty_elapsed += delta
			if _test_enter_empty_elapsed >= EMPTY_TEST_ENTER_AREA_LOWER_DELAY:
				lower_barrier()
		else:
			_test_enter_empty_elapsed = 0.0
	else:
		_test_enter_empty_elapsed = 0.0
		if not is_raised:
			raise_barrier()


func _resolve_barrier_nodes() -> void:
	_mesh_root = get_node_or_null("Mesh") as Node3D
	if is_instance_valid(_mesh_root):
		_barrier_arm = _mesh_root.find_child("BarrierArm", true, false) as Node3D
	_arm_shape = get_node_or_null("ArmShape") as CollisionShape3D
	_control_hit_area = get_node_or_null("ControlHit3D") as Area3D
	_arm_hit_area = get_node_or_null("ArmHit3D") as Area3D
	_test_enter_area = get_node_or_null("TestEnterArea") as Area3D
	_navigation_obstacle = get_node_or_null("NavigationObstacle3D") as NavigationObstacle3D


func _cache_arm_transforms() -> void:
	if not is_instance_valid(_arm_shape) or not (_arm_shape.shape is BoxShape3D):
		push_error("RoadBarrier requires a BoxShape3D child named ArmShape")
		return
	_initial_arm_shape_transform = _arm_shape.transform
	_initial_arm_hit_transform = _arm_hit_area.transform if is_instance_valid(_arm_hit_area) \
		else Transform3D.IDENTITY
	_initial_arm_visual_transform = _barrier_arm.transform if is_instance_valid(_barrier_arm) \
		else Transform3D.IDENTITY
	var arm_box := _arm_shape.shape as BoxShape3D
	_arm_pivot = _initial_arm_shape_transform * Vector3(-arm_box.size.x * 0.5, 0.0, 0.0)
	_arm_transforms_cached = true


func _connect_component_hit_areas() -> void:
	if is_instance_valid(_control_hit_area):
		if not _control_hit_area.body_entered.is_connected(_on_control_hit_body_entered):
			_control_hit_area.body_entered.connect(_on_control_hit_body_entered)
		if not _control_hit_area.area_entered.is_connected(_on_control_hit_area_entered):
			_control_hit_area.area_entered.connect(_on_control_hit_area_entered)
	if is_instance_valid(_arm_hit_area):
		if not _arm_hit_area.body_entered.is_connected(_on_arm_hit_body_entered):
			_arm_hit_area.body_entered.connect(_on_arm_hit_body_entered)
		if not _arm_hit_area.area_entered.is_connected(_on_arm_hit_area_entered):
			_arm_hit_area.area_entered.connect(_on_arm_hit_area_entered)


func _setup_test_enter_area() -> void:
	if not is_instance_valid(_test_enter_area):
		push_warning("RoadBarrier: TestEnterArea is missing on %s." % name)
		return
	_test_enter_area.collision_layer = TEST_ENTER_AREA_LAYER
	_test_enter_area.collision_mask = TEST_ENTER_AREA_MASK
	_test_enter_area.monitoring = true
	_test_enter_area.monitorable = true
	if not _test_enter_area.body_entered.is_connected(_on_test_enter_body_entered):
		_test_enter_area.body_entered.connect(_on_test_enter_body_entered)
	if not _test_enter_area.body_exited.is_connected(_on_test_body_exited):
		_test_enter_area.body_exited.connect(_on_test_body_exited)
	_create_test_enter_area_outline()
	# A barrier can be loaded with a player or vehicle already overlapping it.
	# Reconcile after the first physics update so the initial body cache is valid.
	call_deferred("_reconcile_test_enter_occupants")


func _is_test_enter_authority() -> bool:
	if _network_visual_only or destroyed:
		return false
	if is_instance_valid(GameAuthority) and GameAuthority.is_client_proxy():
		return false
	return true


func _resolve_test_enter_entrant(body: Node) -> Node:
	var cursor := body
	var hops := 0
	while cursor != null and hops < 16:
		if cursor is GamePlayer or cursor is VehicleBase \
			or cursor.is_in_group("human_players") \
			or cursor.is_in_group("server_human_players"):
			return cursor
		cursor = cursor.get_parent()
		hops += 1
	return null


func _reconcile_test_enter_occupants() -> void:
	if not _is_test_enter_authority() or not is_instance_valid(_test_enter_area):
		return
	var current_occupants: Dictionary = {}
	for body in _test_enter_area.get_overlapping_bodies():
		var entrant := _resolve_test_enter_entrant(body)
		if is_instance_valid(entrant):
			current_occupants[entrant.get_instance_id()] = entrant
	_test_enter_occupants = current_occupants


func _on_test_enter_body_entered(body: Node3D) -> void:
	if not _is_test_enter_authority():
		return
	var entrant := _resolve_test_enter_entrant(body)
	if not is_instance_valid(entrant):
		return
	_test_enter_occupants[entrant.get_instance_id()] = entrant
	_test_enter_empty_elapsed = 0.0
	if not is_raised:
		raise_barrier()


func _on_test_body_exited(body: Node3D) -> void:
	if not _is_test_enter_authority():
		return
	var entrant := _resolve_test_enter_entrant(body)
	if not is_instance_valid(entrant):
		return
	_test_enter_occupants.erase(entrant.get_instance_id())
	_test_enter_empty_elapsed = 0.0


func _create_test_enter_area_outline() -> void:
	var collision_shape := _test_enter_area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null or not collision_shape.shape is BoxShape3D:
		push_warning("RoadBarrier: TestEnterArea requires a BoxShape3D for its outline.")
		return
	var box := collision_shape.shape as BoxShape3D
	_test_enter_outline_root = Node3D.new()
	_test_enter_outline_root.name = "TestEnterAreaOutline"
	collision_shape.add_child(_test_enter_outline_root)

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = TEST_ENTER_OUTLINE_COLOR
	material.emission_enabled = true
	material.emission = Color.WHITE
	material.emission_energy_multiplier = 1.35
	_add_test_enter_outline_line(
		Vector3(0.0, TEST_ENTER_OUTLINE_Y_OFFSET, -box.size.z * 0.5),
		Vector3(box.size.x, TEST_ENTER_OUTLINE_HEIGHT, TEST_ENTER_OUTLINE_WIDTH),
		material
	)
	_add_test_enter_outline_line(
		Vector3(0.0, TEST_ENTER_OUTLINE_Y_OFFSET, box.size.z * 0.5),
		Vector3(box.size.x, TEST_ENTER_OUTLINE_HEIGHT, TEST_ENTER_OUTLINE_WIDTH),
		material
	)
	_add_test_enter_outline_line(
		Vector3(-box.size.x * 0.5, TEST_ENTER_OUTLINE_Y_OFFSET, 0.0),
		Vector3(TEST_ENTER_OUTLINE_WIDTH, TEST_ENTER_OUTLINE_HEIGHT, box.size.z),
		material
	)
	_add_test_enter_outline_line(
		Vector3(box.size.x * 0.5, TEST_ENTER_OUTLINE_Y_OFFSET, 0.0),
		Vector3(TEST_ENTER_OUTLINE_WIDTH, TEST_ENTER_OUTLINE_HEIGHT, box.size.z),
		material
	)


func _add_test_enter_outline_line(
	line_position: Vector3,
	line_size: Vector3,
	material: Material
) -> void:
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = line_size
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.position = line_position
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_test_enter_outline_root.add_child(mesh_instance)


func _on_control_hit_body_entered(body: Node3D) -> void:
	_handle_component_hit(_control_hit_area, body)


func _on_control_hit_area_entered(area: Area3D) -> void:
	_handle_component_hit(_control_hit_area, area)


func _on_arm_hit_body_entered(body: Node3D) -> void:
	_handle_component_hit(_arm_hit_area, body)


func _on_arm_hit_area_entered(area: Area3D) -> void:
	_handle_component_hit(_arm_hit_area, area)


func _handle_component_hit(source_area: Area3D, contact: Node) -> void:
	if GameAuthority.should_send_network_requests() or destroyed:
		return
	var bullet := _find_bullet_root(contact)
	if bullet == null:
		return
	var strength := float(bullet.get("bullet_strength")) if _has_property( \
		bullet, "bullet_strength") else 0.0
	if strength <= 0.0:
		return
	var attacker_team := str(bullet.call("get_bullet_owner"))
	var effect := "Explosion" if bullet is BoomBullet else "None"
	if bullet is ColorBullet:
		effect = str(bullet.get("bullet_effect"))
	var attacker_peer_id := 0
	if bullet.has_method("get_bullet_shooter"):
		var shooter: Variant = bullet.call("get_bullet_shooter")
		if shooter is Node:
			attacker_peer_id = GameAuthority.get_authority_player_peer_id(shooter as Node)
	attacker_peer_id = GameAuthority.resolve_attacker_peer_id(attacker_team, attacker_peer_id)
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider",
		source_area,
		effect,
		strength,
		attacker_team,
		-1,
		attacker_peer_id
	))
	if applied:
		GameAuthority.notify_player_hit_confirmation(
			attacker_peer_id,
			attacker_team,
			tool_owner,
			strength,
			effect
		)
		if is_instance_valid(bullet) and bullet.has_method("queue_free"):
			bullet.queue_free()


func _find_bullet_root(contact: Node) -> Node3D:
	var cursor := contact
	var hops := 0
	while cursor != null and hops < 16:
		if cursor is Node3D and cursor.has_method("get_bullet_owner"):
			return cursor as Node3D
		cursor = cursor.get_parent()
		hops += 1
	return null


func _has_property(object: Object, property_name: String) -> bool:
	for info in object.get_property_list():
		if str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func impact(effect: String, strength: float, attacker_team := "") -> bool:
	return _apply_component_damage(CONTROL_COMPONENT, effect, strength, attacker_team)


func impact_with_friendly_fire(effect: String, strength: float, attacker_team := "") -> bool:
	return _apply_component_damage(CONTROL_COMPONENT, effect, strength, attacker_team, true)


## Called by GameAuthority for hits that retain their source collider and shape.
## Root StaticBody3D shape indices are mapped to ArmShape here; the two Area3D
## hitboxes are mapped by their parent area and their child shape is not rotated
## a second time.
func impact_from_collider(
	collider: Variant,
	effect: String,
	strength: float,
	attacker_team := "",
	shape_index := -1,
	_attacker_peer_id := 0,
	_attacker_node: Node3D = null
) -> bool:
	var component := _component_for_collider(collider, shape_index)
	return _apply_component_damage(component, effect, strength, attacker_team)


func _component_for_collider(collider: Variant, shape_index: int) -> String:
	if collider is Node:
		var cursor := collider as Node
		while cursor != null:
			if cursor == _arm_hit_area or (is_instance_valid(_arm_hit_area) \
				and _arm_hit_area.is_ancestor_of(cursor)):
				return ARM_COMPONENT
			if cursor == _control_hit_area or (is_instance_valid(_control_hit_area) \
				and _control_hit_area.is_ancestor_of(cursor)):
				return CONTROL_COMPONENT
			cursor = cursor.get_parent()
	if shape_index >= 0 and is_instance_valid(_arm_shape):
		var owner_id := shape_find_owner(shape_index)
		if owner_id >= 0 and shape_owner_get_owner(owner_id) == _arm_shape:
			return ARM_COMPONENT
	return CONTROL_COMPONENT


func _apply_component_damage(
	component: String,
	_effect: String,
	strength: float,
	attacker_team := "",
	allow_friendly_fire := false
) -> bool:
	if strength <= 0.0 or destroyed:
		return false
	if not allow_friendly_fire and not attacker_team.is_empty() \
		and not tool_owner.is_empty() and attacker_team == tool_owner:
		return false
	if component == ARM_COMPONENT:
		if arm_destroyed or arm_current_hp <= 0.0:
			return false
		arm_current_hp = maxf(0.0, arm_current_hp - strength)
		if arm_current_hp <= 0.0:
			arm_destroyed = true
			_stop_barrier_motion()
		_set_defense_active(true)
	else:
		if current_hp <= 0.0:
			return false
		current_hp = maxf(0.0, current_hp - strength)
		if current_hp <= 0.0:
			destroyed = true
			arm_current_hp = 0.0
			arm_destroyed = true
			is_raised = false
			_stop_barrier_motion()
			_set_defense_active(false)
			defense_destroyed.emit()
		else:
			_set_defense_active(true)
	barrier_state_changed.emit(is_raised)
	return true


func set_barrier_raised(value: bool, notify_network := true) -> bool:
	if destroyed or arm_destroyed or not _arm_transforms_cached:
		return false
	var next_value := bool(value)
	if is_raised == next_value:
		return true
	_stop_barrier_motion()
	var start_angle_degrees := _arm_current_angle_degrees
	var target_angle_degrees := arm_rotation_degrees if next_value else 0.0
	is_raised = next_value
	if is_equal_approx(start_angle_degrees, target_angle_degrees):
		_apply_barrier_pose_at_angle(target_angle_degrees)
	else:
		_barrier_motion_tween = create_tween()
		_barrier_motion_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		_barrier_motion_tween.tween_method(
			_apply_barrier_pose_at_angle,
			start_angle_degrees,
			target_angle_degrees,
			BARRIER_MOTION_DURATION
		)
		_barrier_motion_tween.tween_callback(_on_barrier_motion_finished)
	_refresh_navigation_obstacle(true)
	barrier_state_changed.emit(is_raised)
	if notify_network:
		_notify_authority_state_changed()
	return true


func raise_barrier() -> bool:
	return set_barrier_raised(true)


func lower_barrier() -> bool:
	return set_barrier_raised(false)


func toggle_barrier() -> bool:
	return set_barrier_raised(not is_raised)


func is_barrier_raised() -> bool:
	return is_raised


func _apply_barrier_pose() -> void:
	_apply_barrier_pose_at_angle(arm_rotation_degrees if is_raised else 0.0)


func _apply_barrier_pose_at_angle(angle_degrees: float) -> void:
	if not _arm_transforms_cached:
		return
	_arm_current_angle_degrees = angle_degrees
	var angle := deg_to_rad(angle_degrees)
	_arm_shape.transform = _rotate_transform_about_pivot(
		_initial_arm_shape_transform, _arm_pivot, angle
	)
	if is_instance_valid(_arm_hit_area):
		_arm_hit_area.transform = _rotate_transform_about_pivot(
			_initial_arm_hit_transform, _arm_pivot, angle
		)
	# ArmHit3D/ArmShape keeps its original local transform. Only the parent area
	# rotates, so the hitbox is transformed exactly once.
	if is_instance_valid(_barrier_arm):
		var visual_parent := _barrier_arm.get_parent() as Node3D
		if is_instance_valid(visual_parent):
			var pivot_global := global_transform * _arm_pivot
			var pivot_parent := visual_parent.to_local(pivot_global)
			_barrier_arm.transform = _rotate_transform_about_pivot(
				_initial_arm_visual_transform, pivot_parent, angle
			)


func _stop_barrier_motion() -> void:
	if is_instance_valid(_barrier_motion_tween):
		_barrier_motion_tween.kill()
	_barrier_motion_tween = null


func _on_barrier_motion_finished() -> void:
	_barrier_motion_tween = null
	_apply_barrier_pose_at_angle(arm_rotation_degrees if is_raised else 0.0)
	_refresh_navigation_obstacle(true)


func _rotate_transform_about_pivot(
	initial_transform: Transform3D,
	pivot: Vector3,
	angle: float
) -> Transform3D:
	if is_zero_approx(angle):
		return initial_transform
	# The arm extends along local +X. Positive Z rotates +X toward +Y, which is
	# the raised direction; using Vector3.FORWARD would lower it underground.
	var rotation := Transform3D(Basis(Vector3.BACK, angle), Vector3.ZERO)
	return Transform3D(
		rotation.basis * initial_transform.basis,
		pivot + rotation * (initial_transform.origin - pivot)
	)


func _set_defense_active(value: bool) -> void:
	var gameplay_active := value and not _network_visual_only and not destroyed
	visible = value and not destroyed
	var active_layer := _initial_collision_layer
	var active_mask := _initial_collision_mask
	collision_layer = active_layer if gameplay_active else 0
	collision_mask = active_mask if gameplay_active else 0
	for child in get_children():
		if not child is CollisionShape3D:
			continue
		var shape_node := child as CollisionShape3D
		var shape_active := gameplay_active and (shape_node != _arm_shape or not arm_destroyed)
		shape_node.set_deferred("disabled", not shape_active)
	if is_instance_valid(_control_hit_area):
		_set_hit_area_active(_control_hit_area, gameplay_active)
	if is_instance_valid(_arm_hit_area):
		_set_hit_area_active(_arm_hit_area, gameplay_active and not arm_destroyed)
	if is_instance_valid(_barrier_arm):
		# Network-only replicas disable gameplay collision, but must still render
		# the arm. Visibility follows the facility state, not gameplay_active.
		_barrier_arm.visible = value and not destroyed and not arm_destroyed
	var placement_footprint := get_node_or_null("PlacementFootprint") as CollisionObject3D
	if is_instance_valid(placement_footprint):
		# The footprint is query-only. Keep it for live network replicas so local
		# placement previews still respect the authoritative map layout, but remove
		# it when the whole barrier is destroyed.
		var footprint_active := value and not destroyed
		placement_footprint.set_deferred("collision_layer", 16 if footprint_active else 0)
		placement_footprint.set_deferred("collision_mask", 0)
		for child in placement_footprint.get_children():
			if child is CollisionShape3D:
				(child as CollisionShape3D).set_deferred("disabled", not footprint_active)
	_refresh_navigation_obstacle(gameplay_active)


func _set_hit_area_active(area: Area3D, value: bool) -> void:
	area.set_deferred("collision_layer", 128 if value else 0)
	area.set_deferred("collision_mask", 32 if value else 0)
	area.set_deferred("monitoring", value)
	area.set_deferred("monitorable", value)
	for child in area.get_children():
		if child is CollisionShape3D:
			(child as CollisionShape3D).set_deferred("disabled", not value)


func _refresh_navigation_obstacle(active: bool) -> void:
	if not is_instance_valid(_navigation_obstacle):
		return
	var include_arm := not is_raised and not arm_destroyed and not destroyed
	var bounds := _collect_root_collision_bounds(include_arm)
	if bool(bounds.get("valid", false)):
		var min_corner: Vector3 = bounds["min"]
		var max_corner: Vector3 = bounds["max"]
		_navigation_obstacle.position = Vector3(0.0, min_corner.y, 0.0)
		_navigation_obstacle.height = maxf(0.1, max_corner.y - min_corner.y)
		_navigation_obstacle.vertices = PackedVector3Array([
			Vector3(min_corner.x, 0.0, min_corner.z),
			Vector3(max_corner.x, 0.0, min_corner.z),
			Vector3(max_corner.x, 0.0, max_corner.z),
			Vector3(min_corner.x, 0.0, max_corner.z),
		])
	else:
		_navigation_obstacle.vertices = PackedVector3Array()
		_navigation_obstacle.height = 0.1
	_navigation_obstacle.affect_navigation_mesh = active
	_navigation_obstacle.carve_navigation_mesh = true
	_navigation_obstacle.avoidance_enabled = active
	var navigation_grid := get_tree().get_first_node_in_group(
		"dynamic_navigation_chunk_grids"
	)
	if navigation_grid != null and navigation_grid.has_method("request_dynamic_obstacle_rebuild"):
		navigation_grid.call("request_dynamic_obstacle_rebuild", self, active)
	elif navigation_grid != null and navigation_grid.has_method("register_dynamic_obstacle"):
		navigation_grid.call("register_dynamic_obstacle", self, active)


func _collect_root_collision_bounds(include_arm: bool) -> Dictionary:
	var valid := false
	var min_corner := Vector3.ZERO
	var max_corner := Vector3.ZERO
	var root_inverse := global_transform.affine_inverse()
	for child in get_children():
		if not child is CollisionShape3D:
			continue
		var shape_node := child as CollisionShape3D
		if shape_node == _arm_shape and not include_arm:
			continue
		if shape_node.disabled or not (shape_node.shape is BoxShape3D):
			continue
		var box := shape_node.shape as BoxShape3D
		var half := box.size * 0.5
		var local_transform := root_inverse * shape_node.global_transform
		var shape_bounds := _transformed_box_aabb(half, local_transform)
		if not valid:
			min_corner = shape_bounds.position
			max_corner = shape_bounds.end
			valid = true
		else:
			min_corner = min_corner.min(shape_bounds.position)
			max_corner = max_corner.max(shape_bounds.end)
	return {"valid": valid, "min": min_corner, "max": max_corner}


func _transformed_box_aabb(half: Vector3, transform: Transform3D) -> AABB:
	var corners := [
		Vector3(-half.x, -half.y, -half.z),
		Vector3(half.x, -half.y, -half.z),
		Vector3(-half.x, half.y, -half.z),
		Vector3(half.x, half.y, -half.z),
		Vector3(-half.x, -half.y, half.z),
		Vector3(half.x, -half.y, half.z),
		Vector3(-half.x, half.y, half.z),
		Vector3(half.x, half.y, half.z),
	]
	var result := AABB(transform * corners[0], Vector3.ZERO)
	for index in range(1, corners.size()):
		result = result.expand(transform * corners[index])
	return result


func apply_network_health(value: float) -> void:
	current_hp = clampf(value, 0.0, maxf(max_hp, 0.0))
	if current_hp <= 0.0:
		_stop_barrier_motion()
		destroyed = true
		arm_current_hp = 0.0
		arm_destroyed = true
		is_raised = false
	_set_defense_active(not destroyed)


func apply_network_destroyed() -> void:
	_stop_barrier_motion()
	current_hp = 0.0
	destroyed = true
	arm_current_hp = 0.0
	arm_destroyed = true
	is_raised = false
	_set_defense_active(false)


func apply_network_respawned(value: float = -1.0) -> void:
	_stop_barrier_motion()
	current_hp = maxf(0.0, max_hp if value < 0.0 else value)
	arm_current_hp = maxf(0.0, arm_max_hp)
	arm_destroyed = false
	is_raised = false
	destroyed = false
	respawn_left = 0.0
	_apply_barrier_pose()
	_set_defense_active(true)
	defense_respawned.emit()


func apply_network_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	arm_max_hp = maxf(0.0, float(state.get("arm_max_hp", arm_max_hp)))
	current_hp = clampf(float(state.get("hp", current_hp)), 0.0, maxf(max_hp, 0.0))
	arm_current_hp = clampf(
		float(state.get("arm_hp", arm_current_hp)), 0.0, maxf(arm_max_hp, 0.0)
	)
	arm_destroyed = bool(state.get("arm_destroyed", arm_current_hp <= 0.0))
	destroyed = bool(state.get("destroyed", current_hp <= 0.0)) or current_hp <= 0.0
	var target_raised := false
	if destroyed:
		arm_current_hp = 0.0
		arm_destroyed = true
		target_raised = false
	else:
		target_raised = bool(state.get("raised", false)) and not arm_destroyed
	if destroyed or arm_destroyed or not _arm_transforms_cached:
		_stop_barrier_motion()
		is_raised = target_raised
		_apply_barrier_pose()
	elif target_raised != is_raised:
		# Network snapshots carry the target state. Let the local visual and
		# collision arm travel to that state instead of teleporting it.
		set_barrier_raised(target_raised, false)
	_set_defense_active(not destroyed)


func get_network_state() -> Dictionary:
	var state := super.get_network_state()
	state["raised"] = is_raised
	state["arm_hp"] = arm_current_hp
	state["arm_destroyed"] = arm_destroyed
	state["arm_max_hp"] = arm_max_hp
	return state


func _notify_authority_state_changed() -> void:
	if _network_visual_only or not is_instance_valid(GameAuthority):
		return
	if GameAuthority.has_method("notify_road_barrier_state_changed"):
		GameAuthority.call("notify_road_barrier_state_changed", self)
