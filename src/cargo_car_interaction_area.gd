extends Area3D
class_name CargoCarInteractionArea

@export_enum("driver", "cargo") var interaction_kind := "cargo"

const CARGO_CAR_DEBUG := preload("res://src/cargo_car_debug.gd")


func _ready() -> void:
	add_to_group("cargo_car_interaction_areas")
	collision_layer = 512
	collision_mask = 8
	monitoring = true
	monitorable = true
	CARGO_CAR_DEBUG.log(
		"area ready path=%s kind=%s layer=%d mask=%d"
		% [get_path(), interaction_kind, collision_layer, collision_mask]
	)


func get_cargo_car() -> VehicleBase:
	var node := get_parent()
	while node != null:
		if node is VehicleBase:
			return node as VehicleBase
		node = node.get_parent()
	return null
