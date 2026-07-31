extends SceneTree


func _init() -> void:
	call_deferred("_run_validation")


func _run_validation() -> void:
	var map_scene := load("res://worlds/creston_town/creston_town.tscn") as PackedScene
	assert(map_scene != null)
	var map := map_scene.instantiate()
	var system := map.get_node("DayNightSystem")
	system.initial_hour = 19.0
	root.add_child(map)
	for _frame in range(4):
		await process_frame
	assert(float(system.current_hour) >= 19.0)
	assert(float(system.get_street_light_factor()) > 0.0)
	var lamps := get_nodes_in_group("day_night_lamps")
	assert(not lamps.is_empty())
	var lit_count := 0
	var visible_beam_count := 0
	for lamp_value: Variant in lamps:
		var lamp := lamp_value as Node
		var light := lamp.find_child("NightLight", true, false) as Light3D
		if light != null and light.visible and light.light_energy > 0.0:
			lit_count += 1
			var beam := lamp.find_child("LightBeam", true, false) as GeometryInstance3D
			if beam != null and beam.visible:
				visible_beam_count += 1
			print(
				"Street lamp: %s energy=%.2f range=%.2f position=%s"
				% [
					str(lamp.get_path()),
					light.light_energy,
					light.get("omni_range") if light is OmniLight3D else light.get("spot_range"),
					str(light.global_position),
				]
			)
	assert(lit_count == lamps.size())
	assert(visible_beam_count == 5)
	print(
		"Creston street lamp validation: %.2f hours, %d/%d lamps lit, %d beams visible."
		% [float(system.current_hour), lit_count, lamps.size(), visible_beam_count]
	)
	quit()
