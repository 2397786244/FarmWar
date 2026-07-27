extends VehicleBase
class_name TwoWheelVehicleBase

## A stable motorcycle/bicycle base. It inherits VehicleBase's authority,
## seats, camera, collision, durability, cargo, and multiplayer state; only
## the wheel presentation is two-wheel specific.

var front_wheel: Node3D
var rear_wheel: Node3D
var _front_wheel_rest_basis := Basis.IDENTITY
var _rear_wheel_rest_basis := Basis.IDENTITY
var _body_visual_rest_basis := Basis.IDENTITY
var _visual_lean_angle := 0.0
var _driver_only_seat: VehicleSeatConfig


func _physics_process(delta: float) -> void:
	# The server owns movement. Clients still need to advance visual-only wheel
	# spin and lean between snapshots, otherwise their delta=0 state updates
	# leave the rider permanently upright.
	if not vehicle_deployed or vehicle_config == null or not GameAuthority.is_client_proxy():
		return
	_update_vehicle_visuals(delta)


func _seat_definitions() -> Array[VehicleSeatConfig]:
	if _driver_only_seat == null:
		if vehicle_config != null and not vehicle_config.seats.is_empty():
			_driver_only_seat = vehicle_config.seats[0].duplicate() as VehicleSeatConfig
		else:
			_driver_only_seat = VehicleSeatConfig.new()
		_driver_only_seat.can_drive = true
	return [_driver_only_seat]


func get_cargo_capacity_kg() -> float:
	return 0.0


func _cache_visual_nodes() -> void:
	super._cache_visual_nodes()
	if vehicle_config == null:
		return
	front_wheel = _find_visual_node(vehicle_config.two_wheel_front_node_name)
	rear_wheel = _find_visual_node(vehicle_config.two_wheel_rear_node_name)
	if is_instance_valid(front_wheel):
		_front_wheel_rest_basis = front_wheel.basis
	else:
		push_warning("Two-wheel vehicle is missing front wheel node: %s." % vehicle_config.two_wheel_front_node_name)
	if is_instance_valid(rear_wheel):
		_rear_wheel_rest_basis = rear_wheel.basis
	else:
		push_warning("Two-wheel vehicle is missing rear wheel node: %s." % vehicle_config.two_wheel_rear_node_name)
	if is_instance_valid(body_visual):
		_body_visual_rest_basis = body_visual.basis


func _update_vehicle_visuals(delta: float) -> void:
	if vehicle_config == null:
		return
	wheel_spin_angle += current_speed / maxf(vehicle_config.wheel_radius, 0.01) * delta
	_apply_two_wheel_visual(front_wheel, _front_wheel_rest_basis, _vehicle_turn_angle())
	_apply_two_wheel_visual(rear_wheel, _rear_wheel_rest_basis, 0.0)
	_update_body_visual_lean(delta)
	if vehicle_config.open_cabin and vehicle_config.animate_steering_wheel and is_instance_valid(steering_wheel):
		steering_wheel.basis = _steering_wheel_rest_basis
		steering_wheel.rotate_object_local(
			vehicle_config.steering_wheel_axis.normalized(), _vehicle_turn_angle() * 3.0
		)
	_update_driving_camera_fov(delta)


func _apply_two_wheel_visual(wheel: Node3D, rest_basis: Basis, steering_angle: float) -> void:
	if not is_instance_valid(wheel):
		return
	wheel.basis = rest_basis
	wheel.rotate_object_local(Vector3.UP, steering_angle)
	wheel.rotate_object_local(vehicle_config.wheel_spin_axis.normalized(), -wheel_spin_angle)


func _update_body_visual_lean(delta: float) -> void:
	if not is_instance_valid(body_visual):
		return
	var steering_ratio := 0.0
	var max_steering := deg_to_rad(maxf(vehicle_config.max_steering_angle_degrees, 0.01))
	if max_steering > 0.0:
		steering_ratio = _vehicle_turn_angle() / max_steering
	var speed_ratio := clampf(absf(current_speed) / maxf(vehicle_config.max_forward_speed, 0.01), 0.0, 1.0)
	var direction_sign := signf(current_speed)
	var target_lean := deg_to_rad(vehicle_config.two_wheel_max_lean_degrees) \
		* steering_ratio * speed_ratio * direction_sign * vehicle_config.two_wheel_lean_sign
	_visual_lean_angle = move_toward(
		_visual_lean_angle,
		target_lean,
		vehicle_config.two_wheel_lean_response * delta
	)
	body_visual.basis = _body_visual_rest_basis
	body_visual.rotate_object_local(Vector3.FORWARD, _visual_lean_angle)


func _update_driving_camera_fov(delta: float) -> void:
	var speed_ratio := clampf(absf(current_speed) / maxf(vehicle_config.camera_speed_for_max_fov, 0.01), 0.0, 1.0)
	var target_fov := lerpf(vehicle_config.camera_base_fov, vehicle_config.camera_max_fov, speed_ratio)
	vehicle_camera.fov = lerpf(
		vehicle_camera.fov,
		target_fov,
		1.0 - exp(-vehicle_config.camera_fov_response * maxf(delta, 0.0))
	)
