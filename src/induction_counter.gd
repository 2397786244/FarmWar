extends RecipeCookingStation
class_name InductionCounter

@onready var pot_smoke: GPUParticles3D = find_child("PotCookingSmoke", true, false) as GPUParticles3D

func get_station_group_name() -> String:
	return "induction_counters"

func get_state_event_type() -> String:
	return "induction_counter_state"

func get_recipe_station_key() -> String:
	return "induction_counter"

func get_station_display_name() -> String:
	return "电磁炉"

func get_cooking_verb() -> String:
	return "烹煮"


func get_spoiled_dish_id() -> String:
	return "ruined_soup"

func _refresh_station_visual() -> void:
	super._refresh_station_visual()
	if is_instance_valid(pot_smoke):
		pot_smoke.emitting = cooking
