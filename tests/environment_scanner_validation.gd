extends Node

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_registration()
	_validate_visual_resources()
	await _validate_target_collection()
	_finish()


func _validate_registration() -> void:
	var scene := load("res://character/weapons/EnvironmentScanner.tscn") as PackedScene
	_check(scene != null, "environment scanner scene loads")
	if scene != null:
		var scanner := scene.instantiate()
		_check(scanner is EnvironmentScanner and scanner.has_method("emit"), "scanner exposes the standard emit interface")
		scanner.free()

	var runtime := _read_json("res://data/tool_definitions.json")
	var runtime_definition := _definition_by_id(runtime.get("tools", []), "environment_scanner")
	_check(not runtime_definition.is_empty(), "runtime tool definition is registered")
	_check(is_equal_approx(float(runtime_definition.get("cooldown", 0.0)), 45.0), "runtime cooldown is 45 seconds")
	_check(str(runtime_definition.get("path", "")) == "res://character/weapons/EnvironmentScanner.tscn", "runtime scene path is correct")

	var specials := _read_json("res://data/special_tool_definitions.json")
	var special_definition := _definition_by_id(specials.get("tools", []), "environment_scanner")
	_check(not special_definition.is_empty(), "special-tool definition is registered")
	_check(FileAccess.file_exists(str(special_definition.get("icon", ""))), "rendered scanner icon exists")

	var heroes := _read_json("res://data/hero_special_tools.json")
	var prospector: Array = heroes.get("heroes", {}).get("prospector", [])
	_check(prospector == ["signal_augment", "environment_scanner", "survey_rider"], "Prospector has the intended three candidates")
	var dedicated_source := FileAccess.get_file_as_string("res://src/server_src/DedicatedServerManager.gd")
	_check(dedicated_source.contains('"prospector": ["signal_augment", "environment_scanner", "survey_rider"]'), "dedicated-server whitelist mirrors the loadout config")
	var authority_source := FileAccess.get_file_as_string("res://src/game_authority.gd")
	_check(authority_source.contains('"environment_scanner":') and authority_source.contains('result["local_presentation_only"] = true'), "authority accepts scanner without a replicated world effect")


func _validate_visual_resources() -> void:
	_check(is_equal_approx(EnvironmentScanPresentation.SCAN_RADIUS, 100.0), "scan radius is 100 meters")
	_check(is_equal_approx(EnvironmentScanPresentation.WAVE_DURATION, 1.5), "grid wave lasts 1.5 seconds")
	_check(is_equal_approx(EnvironmentScanPresentation.OUTLINE_DURATION, 8.0), "detected outline lasts 8 seconds")
	var outline_source := FileAccess.get_file_as_string("res://src/environment_scan_outline.gdshader")
	_check(outline_source.contains("thickness_pixels") and outline_source.contains("= 4.0"), "scanner outline is configured as a thick edge")
	_check(not outline_source.contains("depth_texture"), "scanner outline deliberately ignores scene occlusion")
	var interaction_source := FileAccess.get_file_as_string("res://src/vehicle_interaction_outline.gdshader")
	_check(interaction_source.contains("depth_texture") and interaction_source.contains("vec4(1.0, 1.0, 1.0, 0.94)"), "existing white vehicle interaction outline remains depth-aware")
	_check(load("res://src/environment_scan_grid.gdshader") is Shader, "blue grid scan shader loads")
	_check(load("res://src/environment_scan_outline.gdshader") is Shader, "red union-outline shader loads")


func _validate_target_collection() -> void:
	var origin := Vector3.ZERO
	var pickup_near := _make_pickup("PickupNear", Vector3(99.0, 0.0, 0.0))
	var pickup_far := _make_pickup("PickupFar", Vector3(101.0, 0.0, 0.0))
	pickup_near.add_to_group("harvest_mushrooms") # Verify cross-group instance deduplication.
	var ore := _make_ore(Vector3(20.0, 0.0, 0.0))
	var giant := _make_giant_plant(Vector3(30.0, 0.0, 0.0))
	var vehicle_scene := load("res://vehicles/mini_car.tscn") as PackedScene
	var vehicle := vehicle_scene.instantiate() as VehicleBase if vehicle_scene != null else null
	if vehicle != null:
		vehicle.name = "ScannerVehicle"
		vehicle.position = Vector3(40.0, 0.0, 0.0)
		add_child(vehicle)
	var cargo_crate := Node3D.new()
	cargo_crate.name = "ExcludedCargoCrate"
	cargo_crate.position = Vector3(10.0, 0.0, 0.0)
	cargo_crate.add_to_group("cargo_crates")
	add_child(cargo_crate)
	await get_tree().process_frame

	var targets := EnvironmentScanPresentation.collect_scan_targets(get_tree(), origin, 100.0)
	var detected_ids: Dictionary = {}
	for target_data: Dictionary in targets:
		var target := target_data.get("target", null) as Node3D
		if is_instance_valid(target):
			detected_ids[target.get_instance_id()] = true
	_check(detected_ids.has(pickup_near.get_instance_id()), "PickupItem inside 100 meters is detected")
	_check(not detected_ids.has(pickup_far.get_instance_id()), "PickupItem outside 100 meters is excluded")
	_check(detected_ids.has(ore.get_instance_id()), "ore is detected")
	_check(detected_ids.has(giant.get_instance_id()), "giant crop is detected")
	_check(vehicle == null or detected_ids.has(vehicle.get_instance_id()), "living drivable vehicle is detected")
	_check(not detected_ids.has(cargo_crate.get_instance_id()), "cargo-crate containers are excluded")
	var pickup_occurrences := 0
	for target_data: Dictionary in targets:
		if target_data.get("target", null) == pickup_near:
			pickup_occurrences += 1
	_check(pickup_occurrences == 1, "targets appearing in multiple groups are deduplicated")

	ore.destroyed = true
	var after_destroy := EnvironmentScanPresentation.collect_scan_targets(get_tree(), origin, 100.0)
	var destroyed_ore_present := false
	for target_data: Dictionary in after_destroy:
		if target_data.get("target", null) == ore:
			destroyed_ore_present = true
	_check(not destroyed_ore_present, "destroyed resources are excluded")


func _make_pickup(node_name: String, position: Vector3) -> PickupItem:
	var pickup := PickupItem.new()
	pickup.name = node_name
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	pickup.add_child(visual_root)
	var model_pivot := Node3D.new()
	model_pivot.name = "ModelPivot"
	visual_root.add_child(model_pivot)
	var fallback := MeshInstance3D.new()
	fallback.name = "FallbackVisual"
	fallback.mesh = BoxMesh.new()
	model_pivot.add_child(fallback)
	var glow := MeshInstance3D.new()
	glow.name = "GlowRing"
	glow.mesh = TorusMesh.new()
	visual_root.add_child(glow)
	var label := Label3D.new()
	label.name = "PickupLabel"
	visual_root.add_child(label)
	add_child(pickup)
	pickup.global_position = position
	return pickup


func _make_ore(position: Vector3) -> HarvestOre:
	var ore := HarvestOre.new()
	ore.name = "ScannerOre"
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = BoxMesh.new()
	ore.add_child(visual)
	add_child(ore)
	ore.global_position = position
	return ore


func _make_giant_plant(position: Vector3) -> GiantPlants:
	var giant := GiantPlants.new()
	giant.name = "ScannerGiantPlant"
	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	visual.mesh = CapsuleMesh.new()
	giant.add_child(visual)
	add_child(giant)
	giant.global_position = position
	return giant


func _definition_by_id(definitions: Variant, wanted_id: String) -> Dictionary:
	if not definitions is Array:
		return {}
	for value in definitions as Array:
		if value is Dictionary and str((value as Dictionary).get("id", "")) == wanted_id:
			return value as Dictionary
	return {}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[EnvironmentScannerValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[EnvironmentScannerValidation] FAIL: %s" % description)


func _finish() -> void:
	if failures == 0:
		print("[EnvironmentScannerValidation] PASS all checks")
	else:
		push_error("[EnvironmentScannerValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)
