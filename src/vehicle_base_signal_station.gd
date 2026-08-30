extends SignalAugment
class_name VehicleBaseSignalStation

signal destroyed(station: VehicleBaseSignalStation)

const MAX_HP := VehicleBaseMachineGun.MAX_HP
const AUGMENT_RADIUS := 50.0

var destroyed_state := false


func _ready() -> void:
	set_hp = MAX_HP
	augment_dist = AUGMENT_RADIUS
	max_augment_ratio = 100.0
	super()
	add_to_group("mounted_vehicle_signal_stations")
	_sync_mounted_vehicle_owner()
	_configure_mounted_collision()
	activate_tool()


func _physics_process(delta: float) -> void:
	# The vehicle can receive its team from a restored/network state after this
	# child has entered the tree. Keep the attachment's team in step with the
	# parent before SignalAugment refreshes its overlap cache.
	_sync_mounted_vehicle_owner()
	super._physics_process(delta)


func activate_tool() -> void:
	if destroyed_state:
		return
	if not is_placed:
		current_hp = set_hp
	is_placed = true
	is_active = true
	_update_health_label()
	augment_counter = maxf(augment_detect_tick, 0.0)
	_configure_mounted_collision()
	if not is_instance_valid(augment_3d):
		return
	var augment_shape := augment_collision_shape.shape as SphereShape3D
	if augment_shape != null:
		augment_shape.radius = AUGMENT_RADIUS
	augment_3d.monitoring = true
	augment_3d.monitorable = false
	call_deferred("_refresh_augmented_devices")


func set_destroyed_state(value: bool) -> void:
	destroyed_state = value
	if destroyed_state:
		current_hp = 0.0
		is_active = false
		augmented_devices.clear()
	else:
		current_hp = clampf(current_hp, 0.0, MAX_HP)
		is_active = current_hp > 0.0
	is_placed = true
	_update_health_label()
	_apply_destroyed_visuals()


func apply_network_state(state: Dictionary) -> void:
	current_hp = clampf(float(state.get("hp", current_hp)), 0.0, MAX_HP)
	is_placed = bool(state.get("installed", true))
	var next_destroyed := bool(state.get("destroyed", current_hp <= 0.0))
	destroyed_state = next_destroyed or current_hp <= 0.0
	is_active = is_placed and not destroyed_state
	_update_health_label()
	_apply_destroyed_visuals()
	if is_active:
		call_deferred("_refresh_augmented_devices")


func get_network_state() -> Dictionary:
	return {
		"installed": true,
		"hp": current_hp,
		"destroyed": destroyed_state,
	}


func _destroy_augment() -> void:
	if destroyed_state:
		return
	destroyed_state = true
	is_active = false
	current_hp = 0.0
	augmented_devices.clear()
	burn_remaining = 0.0
	burn_dps = 0.0
	_update_health_label()
	_apply_destroyed_visuals()
	destroyed.emit(self)
	var vehicle := get_parent_vehicle()
	if vehicle != null:
		vehicle.on_platform_signal_station_destroyed()


func _configure_mounted_collision() -> void:
	# The station is a child of a moving VehicleBase. Its root body must never
	# participate in body collision; Hit3D is the only combat hitbox.
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(hit_3d):
		hit_3d.collision_layer = GameAuthority.COLLISION_LAYER_TOOL
		hit_3d.collision_mask = GameAuthority.COLLISION_LAYER_BULLET
		hit_3d.monitoring = not destroyed_state
		hit_3d.monitorable = not destroyed_state
	if is_instance_valid(augment_3d):
		augment_3d.collision_layer = 0
		augment_3d.collision_mask = GameAuthority.COLLISION_LAYER_TOOL
		augment_3d.monitoring = not destroyed_state
		augment_3d.monitorable = false

func _apply_destroyed_visuals() -> void:
	var mesh := find_child("Mesh", true, false) as Node3D
	if mesh != null:
		mesh.visible = not destroyed_state
	_configure_mounted_collision()
	for child in find_children("*", "CollisionShape3D", true, false):
		(child as CollisionShape3D).set_deferred("disabled", destroyed_state)


func get_parent_vehicle() -> FarmBaseVehicle:
	var cursor := get_parent()
	while cursor != null:
		if cursor is FarmBaseVehicle:
			return cursor as FarmBaseVehicle
		cursor = cursor.get_parent()
	return null


func _sync_mounted_vehicle_owner() -> void:
	var vehicle := get_parent_vehicle()
	if vehicle != null:
		tool_owner = vehicle.owner_team


func _can_augment_device(target: Node3D) -> bool:
	_sync_mounted_vehicle_owner()
	if target == null or target == self:
		return false
	# A map vehicle with no owner is a neutral signal source. This is important
	# for authored coop maps and old saves whose FarmBaseVehicle owner_team was
	# left empty; it must not silently disable the mounted signal station.
	if tool_owner.is_empty():
		return true
	return str(target.get("tool_owner")) == tool_owner
