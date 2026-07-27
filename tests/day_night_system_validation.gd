extends SceneTree

const DayNightScript := preload("res://src/environment/day_night_system.gd")


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var system: Node = DayNightScript.new()
	root.add_child(system)
	var daylight_hours: float = system.get_daylight_game_hours()
	assert(is_equal_approx(system.real_day_duration_seconds, 1440.0))
	assert(daylight_hours > 14.5 and daylight_hours < 15.0)
	assert(system._is_hour_in_wrapped_range(19.0, 19.0, 5.0))
	assert(system._is_hour_in_wrapped_range(0.0, 19.0, 5.0))
	assert(not system._is_hour_in_wrapped_range(18.99, 19.0, 5.0))
	assert(not system._is_hour_in_wrapped_range(5.0, 19.0, 5.0))

	var lamp_scene := load("res://buildings/StreetLampStraight.tscn") as PackedScene
	assert(lamp_scene != null)
	system.current_hour = 19.0
	var lamp: Node = lamp_scene.instantiate()
	root.add_child(lamp)
	assert(lamp.find_child("LightPos", true, false) == null)
	var light := lamp.find_child("NightLight", true, false) as Light3D
	assert(light != null)
	assert(light.light_energy > 0.0)
	lamp.set_night_factor(1.0)
	assert(light.light_energy > 0.0)
	lamp.set_night_factor(0.0)
	assert(is_zero_approx(light.light_energy))

	print(
		"Day/night validation: %.2f daylight hours, %.2f night hours, 1440s full cycle."
		% [daylight_hours, 24.0 - daylight_hours]
	)
	quit()
