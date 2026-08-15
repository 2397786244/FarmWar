extends Area3D
class_name VehiclePlatformInteractionArea

## Platform areas share one interaction path, but FarmBaseVehicle can expose
## different modules from the same rear platform.  The default keeps existing
## machine-gun scenes backward compatible.
@export var interaction_kind := "machine_gun"


func _ready() -> void:
	add_to_group("vehicle_platform_interaction_areas")
	collision_layer = 512
	collision_mask = GameAuthority.COLLISION_LAYER_CHARACTER
	monitoring = true
	monitorable = true


func get_vehicle() -> FarmBaseVehicle:
	var cursor := get_parent()
	while cursor != null:
		if cursor is FarmBaseVehicle:
			return cursor as FarmBaseVehicle
		cursor = cursor.get_parent()
	return null


func get_platform_module() -> VehicleBaseMachineGun:
	var vehicle := get_vehicle()
	return vehicle.get_platform_machine_gun() if vehicle != null else null


func get_interaction_kind() -> String:
	return interaction_kind
