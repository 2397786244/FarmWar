extends VehicleBase
class_name KitchenCar

const KITCHEN_INTERACTION_POINT_NAME := "KitchenInteractionPoint"
const FALLBACK_KITCHEN_POSITION := Vector3(0.0, 1.2, 2.05)

@export_enum("red", "blue") var kitchen_team := "red"

@onready var kitchen_station: MobileInductionCounter = $MobileInductionCounter


func _ready() -> void:
	if not vehicle_deployed:
		_disable_handheld_kitchen_station()
	super._ready()
	if not vehicle_deployed:
		return
	_configure_kitchen_station()


func set_kitchen_team(next_team: String) -> void:
	if next_team != "red" and next_team != "blue":
		return
	kitchen_team = next_team
	if is_instance_valid(kitchen_station):
		kitchen_station.owner_team = kitchen_team


func _configure_kitchen_station() -> void:
	if not is_instance_valid(kitchen_station):
		return
	kitchen_station.owner_team = kitchen_team
	var interaction_point := _find_visual_node(KITCHEN_INTERACTION_POINT_NAME)
	if is_instance_valid(interaction_point):
		kitchen_station.position = to_local(interaction_point.global_position)
	else:
		kitchen_station.position = FALLBACK_KITCHEN_POSITION


func _disable_handheld_kitchen_station() -> void:
	if not is_instance_valid(kitchen_station):
		return
	kitchen_station.remove_from_group("induction_counters")
	kitchen_station.set_process(false)
	kitchen_station.collision_layer = 0
	kitchen_station.collision_mask = 0
	var interaction_shape := kitchen_station.get_node_or_null("InteractionShape") as CollisionShape3D
	if interaction_shape != null:
		interaction_shape.set_deferred("disabled", true)
	var status_label := kitchen_station.get_node_or_null("StatusLabel") as Label3D
	if status_label != null:
		status_label.visible = false
