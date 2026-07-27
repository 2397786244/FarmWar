extends RecipeCookingStation
class_name Oven

@onready var working_glow: Node3D = find_child("OvenWorkingGlow", true, false) as Node3D

func get_station_group_name() -> String:
	return "oven_stations"

func get_state_event_type() -> String:
	return "oven_state"

func get_recipe_station_key() -> String:
	return "oven"

func get_station_display_name() -> String:
	return "烤箱"

func get_cooking_verb() -> String:
	return "烘烤"


func _refresh_station_visual() -> void:
	super._refresh_station_visual()
	if is_instance_valid(working_glow):
		working_glow.visible = cooking
