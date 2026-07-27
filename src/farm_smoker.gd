extends RecipeCookingStation
class_name FarmSmoker

@onready var working_glow: Node3D = find_child("SmokerWorkingGlow", true, false) as Node3D

func get_station_group_name() -> String:
	return "smoker_stations"


func get_state_event_type() -> String:
	return "smoker_state"


func get_recipe_station_key() -> String:
	return "farm_smoker"


func get_station_display_name() -> String:
	return "烟熏炉"


func get_cooking_verb() -> String:
	return "烟熏"


func _refresh_station_visual() -> void:
	super._refresh_station_visual()
	if is_instance_valid(working_glow):
		working_glow.visible = cooking
