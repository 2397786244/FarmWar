extends RecipeCookingStation
class_name Freezer


func get_station_group_name() -> String:
	return "freezer_stations"


func get_state_event_type() -> String:
	return "freezer_state"


func get_recipe_station_key() -> String:
	return "freezer"


func get_station_display_name() -> String:
	return "冷冻柜"


func get_cooking_verb() -> String:
	return "冷冻"


func should_spoil_output() -> bool:
	return false
