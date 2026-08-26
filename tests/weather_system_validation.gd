extends SceneTree

const WeatherSystemScript := preload("res://src/environment/weather_system_3d.gd")


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	GameAuthority.start_local_mode({
		"display_name": "WeatherValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	var weather := WeatherSystemScript.new() as WeatherSystem3D
	weather.clear_weather_probability = 0.0
	weather.rain_weather_probability = 0.0
	weather.eclipse_weather_probability = 1.0
	root.add_child(weather)
	await process_frame

	var first_state := weather.get_weather_app_state()
	var first_days := first_state.get("forecast_days", []) as Array
	assert(first_days.size() == 7)
	assert(int(first_days[0].get("day_index", -1)) == int(first_state.get("world_day", -2)))
	for index in range(first_days.size()):
		var entry := first_days[index] as Dictionary
		assert(int(entry.get("day_index", -1)) == int(first_state.get("world_day", 0)) + index)
		assert(str(entry.get("weather_type", "")) == "eclipse")
		assert(not entry.has("rain_intensity"))
		var eclipse := entry.get("eclipse", {}) as Dictionary
		assert(bool(eclipse.get("enabled", false)))
		assert(float(eclipse.get("start_hour", 0.0)) >= 9.0)
		assert(float(eclipse.get("start_hour", 0.0)) <= 12.0)
		assert(float(eclipse.get("end_hour", 0.0)) <= 18.0)

	var first_revision := int(first_state.get("forecast_revision", 0))
	var first_start_day := int(first_state.get("forecast_start_day", -1))
	# One full in-game day is 1440 real seconds. Advance the local authority's
	# clock so the public API observes the same rollover path as gameplay.
	GameAuthority.server_tick = int(1440.0 * 60.0)
	weather._ensure_forecast_for_current_day()
	var second_state := weather.get_weather_app_state()
	var second_days := second_state.get("forecast_days", []) as Array
	assert(second_days.size() == 7)
	assert(int(second_state.get("forecast_start_day", -1)) == first_start_day + 1)
	assert(int(second_state.get("forecast_revision", 0)) == first_revision + 1)
	assert(int((second_days[0] as Dictionary).get("day_index", -1)) == first_start_day + 1)
	var low_frequency := GameAuthority.call("_build_low_frequency_snapshot") as Dictionary
	var synced_forecast := low_frequency.get("weather_forecast", {}) as Dictionary
	assert((synced_forecast.get("forecast_days", []) as Array).size() == 7)

	var saved_state := weather.get_persistent_state()
	var restored := WeatherSystemScript.new() as WeatherSystem3D
	root.add_child(restored)
	restored.apply_persistent_state(saved_state)
	var restored_forecast := restored.get_weather_forecast_state()
	assert(restored_forecast.get("forecast_days", []) == saved_state.get("forecast_days", []))
	assert(int(restored_forecast.get("forecast_revision", 0)) == int(saved_state.get("forecast_revision", 0)))

	print("Weather validation: persistent seven-day forecast, daily rollover, eclipse schedule, and app filtering passed.")
	GameAuthority.stop_authority()
	quit(0)
