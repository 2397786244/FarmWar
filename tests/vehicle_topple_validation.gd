extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const GROUND_LAYER := 1
const SAFE_GROUND_CLEARANCE := 0.06
const TOPPLE_ANGLE := deg_to_rad(82.0)

var failures := 0


func _ready() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "VehicleToppleValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GameAuthority.set_physics_process(false)
	GlobalVar.gameworld = self
	var ground := _add_box_body(
		"VehicleToppleValidationGround",
		Vector3(0.0, -0.5, 0.0),
		Vector3(80.0, 1.0, 80.0),
		GROUND_LAYER
	)
	_check(ground != null, "validation ground is available")

	var vehicle := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(vehicle != null, "FarmBaseVehicle scene loads")
	if vehicle == null:
		_finish()
		return
	vehicle.name = "VehicleToppleValidationFarm"
	vehicle.position = Vector3(0.0, 0.55, 0.0)
	add_child(vehicle)
	await get_tree().process_frame
	_check(vehicle.vehicle_config != null, "FarmBaseVehicle has a vehicle config")

	vehicle.set_platform_passenger_seat_count(2)
	vehicle.set_platform_machine_gun_installed(true)
	vehicle.set_harvest_reel_installed(true)
	vehicle.set_nitro_boost_installed(true)
	vehicle.set_roof_headlights_installed(true)
	await get_tree().process_frame

	var tracked_nodes: Array[Node3D] = []
	for candidate: Node in [
		vehicle.get_node_or_null("PlatformSeat1"),
		vehicle.get_node_or_null("PlatformSeat2"),
		vehicle.get_platform_machine_gun(),
		vehicle.get_harvest_reel(),
		vehicle.get_roof_headlights(),
		vehicle.get_node_or_null("NitroBoostPos"),
		vehicle.get_node_or_null("CollisionShape3D12"),
	]:
		if candidate is Node3D and not tracked_nodes.has(candidate as Node3D):
			tracked_nodes.append(candidate as Node3D)
	_check(tracked_nodes.size() >= 6, "FarmBaseVehicle exposes mounted modules and collision nodes")

	var relative_transforms: Dictionary = {}
	for node in tracked_nodes:
		relative_transforms[node.get_instance_id()] = \
			vehicle.global_transform.affine_inverse() * node.global_transform

	var selected_axes := {
		"right_push": {
			"push": Vector3.RIGHT,
			"axis": Vector3(0.0, 0.0, -1.0),
		},
		"left_push": {
			"push": Vector3.LEFT,
			"axis": Vector3(0.0, 0.0, 1.0),
		},
		"rear_push": {
			"push": Vector3(0.0, 0.0, 1.0),
			"axis": Vector3.RIGHT,
		},
		"front_push": {
			"push": Vector3(0.0, 0.0, -1.0),
			"axis": Vector3.LEFT,
		},
	}
	for label: String in selected_axes:
		var direction_data := selected_axes[label] as Dictionary
		var selected_axis := vehicle._topple_axis_from_local_push(direction_data["push"] as Vector3)
		_check(
			selected_axis.is_equal_approx(direction_data["axis"] as Vector3),
			"%s selects the expected local topple axis" % label
		)
		vehicle.set_toppled(false, selected_axis, -1.0, false)
		vehicle._update_topple_pose(1.0)
		vehicle.set_toppled(true, selected_axis, TOPPLE_ANGLE, false)
		vehicle._update_topple_pose(1.0)
		_check(vehicle.toppled, "%s enters toppled state" % label)
		_check(
			vehicle.tip_axis.is_equal_approx(selected_axis)
				and is_equal_approx(vehicle.topple_current_angle, TOPPLE_ANGLE),
			"%s stores the selected axis and current angle" % label
		)
		_check_root_pose(vehicle, "%s reconstructs the complete root pose" % label)
		_check_descendants_follow_root(vehicle, tracked_nodes, relative_transforms, label)
		# A second pose update must not zero X/Z rotation or detach the modules.
		var pose_before := vehicle.global_transform
		vehicle._update_topple_pose(0.0)
		_check(
			_transform_close(vehicle.global_transform, pose_before),
			"%s remains toppled across later physics frames" % label
		)

	vehicle.set_toppled(false, vehicle.tip_axis, -1.0, false)
	vehicle._update_topple_pose(1.0)
	_check(
		vehicle.global_transform.basis.y.dot(Vector3.UP) > 0.99,
		"upright_vehicle transition restores a horizontal root"
	)

	vehicle.position = Vector3(0.0, 0.55, 0.0)
	vehicle.set_toppled(true, Vector3(0.0, 0.0, 1.0), TOPPLE_ANGLE, false)
	vehicle._update_topple_pose(1.0)
	var y_before_correction := vehicle.global_position.y
	vehicle._correct_topple_ground_penetration()
	var lowest_support_y := INF
	for local_point: Vector3 in vehicle._vehicle_topple_support_points():
		lowest_support_y = minf(lowest_support_y, (vehicle.global_transform * local_point).y)
	_check(
		vehicle.global_position.y >= y_before_correction,
		"topple ground correction only lifts the vehicle"
	)
	_check(
		lowest_support_y >= SAFE_GROUND_CLEARANCE - 0.01,
		"toppled physical support points stay above the ground"
	)
	var corrected_pose := vehicle.global_transform
	vehicle._update_topple_pose(0.0)
	_check(
		_transform_close(vehicle.global_transform, corrected_pose),
		"ground correction preserves the complete toppled orientation"
	)
	var physics_pose := vehicle.global_transform
	for _frame in range(30):
		vehicle.simulate_authority(1.0 / 60.0)
	_check(
		vehicle.toppled and _transform_close(vehicle.global_transform, physics_pose),
		"multiple authority physics frames keep the root toppled"
	)
	var lowest_after_physics := INF
	for local_point: Vector3 in vehicle._vehicle_topple_support_points():
		lowest_after_physics = minf(
			lowest_after_physics,
			(vehicle.global_transform * local_point).y
		)
	_check(
		lowest_after_physics >= SAFE_GROUND_CLEARANCE - 0.01,
		"multiple authority physics frames do not embed the toppled vehicle"
	)

	var network_state := vehicle.get_network_state()
	_check(network_state.has("yaw"), "network state includes upright yaw")
	_check(network_state.has("topple_current_angle"), "network state includes current topple angle")
	_check(
		(network_state.get("tip_axis", Vector3.ZERO) as Vector3).is_equal_approx(vehicle.tip_axis),
		"network state includes the local topple axis"
	)
	var replica := FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(replica != null, "network replica scene loads")
	if replica != null:
		replica.name = "VehicleToppleValidationReplica"
		add_child(replica)
		await get_tree().process_frame
		replica.apply_network_state(network_state)
		_check(
			_transform_close(replica.global_transform, vehicle.global_transform),
			"network state rebuilds the same root position and orientation"
		)
		_check(
			is_equal_approx(replica.topple_current_angle, vehicle.topple_current_angle),
			"network replica keeps the current transition angle"
		)
		var legacy_state := network_state.duplicate(true)
		legacy_state.erase("topple_current_angle")
		legacy_state["tip_angle"] = TOPPLE_ANGLE
		replica.apply_network_state(legacy_state)
		_check(
			is_equal_approx(replica.topple_current_angle, TOPPLE_ANGLE),
			"legacy network state falls back to tip_angle"
		)

	_finish()


func _check_root_pose(vehicle: VehicleBase, message: String) -> void:
	var expected := Basis(Vector3.UP, vehicle.upright_yaw) \
		* Basis(Quaternion(vehicle.tip_axis, vehicle.topple_current_angle))
	_check(
		_basis_close(vehicle.global_transform.basis, expected.scaled(vehicle.scale)),
		message
	)


func _check_descendants_follow_root(
	vehicle: VehicleBase,
	nodes: Array[Node3D],
	relative_transforms: Dictionary,
	label: String
) -> void:
	var moved_count := 0
	for node in nodes:
		if not is_instance_valid(node):
			continue
		var relative_value: Variant = relative_transforms.get(node.get_instance_id(), null)
		if not relative_value is Transform3D:
			continue
		var expected := vehicle.global_transform * (relative_value as Transform3D)
		_check(
			_transform_close(node.global_transform, expected),
			"%s keeps %s attached to the root" % [label, node.name]
		)
		if node.global_position.distance_to(vehicle.global_position) > 0.05:
			moved_count += 1
	_check(moved_count > 0, "%s visibly rotates mounted descendants with the root" % label)


func _transform_close(first: Transform3D, second: Transform3D) -> bool:
	return first.origin.distance_to(second.origin) <= 0.01 \
		and _basis_close(first.basis, second.basis)


func _basis_close(first: Basis, second: Basis) -> bool:
	return first.x.distance_to(second.x) <= 0.01 \
		and first.y.distance_to(second.y) <= 0.01 \
		and first.z.distance_to(second.z) <= 0.01


func _add_box_body(
	node_name: String,
	position: Vector3,
	size: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = position
	body.collision_layer = layer
	body.collision_mask = 0
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	add_child(body)
	return body


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[VehicleToppleValidation] PASS: %s" % message)
	else:
		failures += 1
		push_error("[VehicleToppleValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures == 0:
		print("[VehicleToppleValidation] PASS all checks")
	else:
		push_error("[VehicleToppleValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
