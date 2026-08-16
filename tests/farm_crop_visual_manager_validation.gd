extends Node3D

var failures := 0
var _field: FarmFieldGenerator


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "FarmCropVisualManagerValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self

	_field = FarmFieldGenerator.new()
	_field.name = "FarmCropVisualValidationField"
	_field.field_label = "farm_crop_visual_validation"
	_field.length_tiles = 1
	_field.width_tiles = 1
	_field.tile_spacing = 2.2
	_field.generate_on_ready = false
	add_child(_field)
	var tiles := _field.generate_field()
	_check(tiles.size() == 1, "validation field creates one FarmTile")
	if tiles.is_empty():
		_finish()
		return
	await get_tree().process_frame

	var tile := tiles[0] as FarmTile
	var manager := FarmCropVisualManager.find_for_node(tile)
	_check(manager != null, "FarmCropVisualManager is created for the world")
	if manager == null:
		_finish()
		return

	var observed_multi_mesh_crop := false
	for crop_id: String in IngredientCatalog.get_plantable_ids():
		_check(
			tile.apply_authoritative_plant(crop_id, "red", 0, false),
			"plantable crop can be registered: %s" % crop_id
		)
		var expected_instances := 0
		for crop_value: Variant in tile.plant_children:
			var crop := crop_value as Node3D
			if crop == null:
				continue
			var mesh_parts := crop.find_children("*", "MeshInstance3D", true, false)
			expected_instances += mesh_parts.size()
			if mesh_parts.size() > 1:
				observed_multi_mesh_crop = true
			for visual_value: Variant in mesh_parts:
				var visual := visual_value as MeshInstance3D
				_check(visual != null and not visual.visible, "%s original visual is hidden" % crop_id)
			_check(
				crop is StaticBody3D,
				"%s keeps its StaticBody3D" % crop_id
			)
			_check(
				crop.find_child("CollisionShape3D", true, false) is CollisionShape3D,
				"%s keeps its CollisionShape3D" % crop_id
			)
		var stats := manager.get_batch_stats()
		_check(
			int(stats.get("active_instance_count", -1)) == expected_instances,
			"%s registers every MeshInstance3D as a MultiMesh instance" % crop_id
		)
		tile._clear_crop()

	print(
		"[FarmCropVisualManagerValidation] multi-Mesh crop observed=%s"
		% observed_multi_mesh_crop
	)
	_check(
		int(manager.get_batch_stats().get("active_instance_count", -1)) == 0,
		"clearing FarmTile removes all MultiMesh instances"
	)
	_finish()


func _finish() -> void:
	if failures == 0:
		print("[FarmCropVisualManagerValidation] PASS all checks")
	else:
		push_error("[FarmCropVisualManagerValidation] FAIL count=%d" % failures)
	if is_instance_valid(_field):
		_field.queue_free()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[FarmCropVisualManagerValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[FarmCropVisualManagerValidation] FAIL: %s" % description)
