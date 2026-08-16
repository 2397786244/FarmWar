extends Node3D

const CROP_ID := "wheat"
const VALIDATION_TEAM := "red"

var failures := 0
var _large_field: FarmFieldGenerator
var _large_generator: NeutralCropGenerator
var _rotated_field: FarmFieldGenerator
var _rotated_generator: NeutralCropGenerator


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "NeutralCropGeneratorChunkValidation",
		"team": VALIDATION_TEAM,
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self

	await _run_large_area_validation()
	await _run_rotated_area_validation()
	await _run_budget_validation()
	_finish()


func _run_large_area_validation() -> void:
	_large_field = FarmFieldGenerator.new()
	_large_field.name = "NeutralCropChunkValidationField"
	_large_field.field_label = "neutral_crop_chunk_validation"
	_large_field.length_tiles = 12
	_large_field.width_tiles = 12
	_large_field.tile_spacing = 2.0
	_large_field.generate_on_ready = false
	add_child(_large_field)
	var tiles := _large_field.generate_field()
	_check(tiles.size() == 144, "large validation field creates 12x12 FarmTiles")
	_check(
		_large_field.get_collision_chunk_count() == 1,
		"FarmFieldGenerator keeps its original 16-FarmTile collision chunking"
	)
	_check(
		_large_field.get_collision_shape_count() == tiles.size(),
		"FarmFieldGenerator collision shape count still matches every FarmTile"
	)
	if tiles.size() < 3:
		_finish()
		return

	var owned_tile := tiles[0] as FarmTile
	var occupied_tile := tiles[1] as FarmTile
	Farmlandmanager.change_land_owner(owned_tile, VALIDATION_TEAM)
	_check(
		occupied_tile.apply_authoritative_plant(CROP_ID, "", 0, false),
		"one FarmTile is preoccupied before generator scanning"
	)

	_large_generator = NeutralCropGenerator.new()
	_large_generator.name = "NeutralCropChunkValidationGenerator"
	_large_generator.generator_id = "neutral_crop_chunk_validation_generator"
	_large_generator.crop_id = CROP_ID
	_large_generator.area_size = Vector2(32.0, 32.0)
	_large_generator.position = Vector3(16.0, 0.0, 16.0)
	_large_generator.initial_spawn_delay = 3600.0
	_large_generator.respawn_interval_seconds = 3600.0
	add_child(_large_generator)
	await get_tree().process_frame
	_large_generator.refresh_after_world_restore()
	await get_tree().process_frame

	var first_count := _count_planted(tiles)
	_check(first_count > 0 and first_count < tiles.size() - 1,
		"32x32m generator does not plant the whole area in one frame")
	var first_progress := _large_generator.get_generation_progress()
	_check(
		int(first_progress.get("chunk_count", 0)) > 1,
		"large generator creates multiple world-space 16m chunks"
	)

	# Repeated restore/contact requests while the job is active must be coalesced.
	_large_generator.refresh_after_world_restore()
	_large_generator.refresh_after_world_restore()
	var guard_frames := 0
	while (
		_large_generator.is_generation_in_progress()
			or _large_generator.has_pending_generation_request()
	) and guard_frames < 120:
		await get_tree().process_frame
		guard_frames += 1

	var final_count := _count_planted(tiles)
	_check(
		final_count == tiles.size() - 1,
		"large generator eventually plants every eligible FarmTile exactly once"
	)
	_check(
		owned_tile.land_owner == VALIDATION_TEAM and owned_tile.is_empty(),
		"owned FarmTile is not overwritten by neutral generation"
	)
	_check(
		occupied_tile.seed_record == CROP_ID,
		"occupied FarmTile is not replanted"
	)
	_check(
		not tiles[2].plant_children.is_empty()
			and tiles[2].plant_children[0] is StaticBody3D
			and tiles[2].plant_children[0].find_child("CollisionShape3D", true, false) is CollisionShape3D,
		"generated crop keeps its StaticBody3D and CollisionShape3D"
	)
	var visual_manager := FarmCropVisualManager.find_for_node(tiles[2])
	_check(visual_manager != null, "generated crops remain registered with FarmCropVisualManager")
	_check(not _large_generator.is_generation_in_progress(), "large generation job finishes")

	await _dispose_nodes([_large_generator, _large_field])


func _run_rotated_area_validation() -> void:
	_rotated_field = FarmFieldGenerator.new()
	_rotated_field.name = "NeutralCropRotatedValidationField"
	_rotated_field.field_label = "neutral_crop_rotated_validation"
	_rotated_field.length_tiles = 3
	_rotated_field.width_tiles = 2
	_rotated_field.tile_spacing = 2.0
	_rotated_field.generate_on_ready = false
	add_child(_rotated_field)
	var tiles := _rotated_field.generate_field()
	_rotated_generator = NeutralCropGenerator.new()
	_rotated_generator.name = "NeutralCropRotatedValidationGenerator"
	_rotated_generator.generator_id = "neutral_crop_rotated_validation_generator"
	_rotated_generator.crop_id = CROP_ID
	_rotated_generator.area_size = Vector2(4.0, 2.0)
	_rotated_generator.position = Vector3(2.0, 0.0, 1.0)
	_rotated_generator.rotation.y = PI * 0.5
	_rotated_generator.initial_spawn_delay = 3600.0
	_rotated_generator.respawn_interval_seconds = 3600.0
	add_child(_rotated_generator)
	await get_tree().process_frame
	_rotated_generator.refresh_after_world_restore()
	await get_tree().process_frame
	var guard_frames := 0
	while _rotated_generator.is_generation_in_progress() and guard_frames < 30:
		await get_tree().process_frame
		guard_frames += 1
	_check(
		_count_planted(tiles) == 2,
		"rotated generator uses local-space bounds after world 16m chunk lookup"
	)
	await _dispose_nodes([_rotated_generator, _rotated_field])


func _run_budget_validation() -> void:
	# No generator is active here, so the calls below isolate the shared world
	# budget and verify that a 33rd planting attempt in one frame is rejected.
	await get_tree().process_frame
	var accepted := 0
	for _index in range(32):
		if Farmlandmanager.try_consume_crop_generation_budget():
			accepted += 1
	_check(accepted == 32, "world crop generation budget accepts 32 attempts per frame")
	_check(
		not Farmlandmanager.try_consume_crop_generation_budget(),
		"world crop generation budget rejects the 33rd attempt in the same frame"
	)
	var usage := Farmlandmanager.get_crop_generation_budget_usage()
	_check(
		int(usage.get("used", -1)) == 32 and int(usage.get("limit", -1)) == 32,
		"world crop generation budget reports its usage and limit"
	)


func _count_planted(tiles: Array[FarmTile]) -> int:
	var count := 0
	for tile in tiles:
		if is_instance_valid(tile) and not tile.is_empty():
			count += 1
	return count


func _dispose_nodes(nodes: Array) -> void:
	for node_value: Variant in nodes:
		if is_instance_valid(node_value):
			(node_value as Node).queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if failures == 0:
		print("[NeutralCropGeneratorChunkValidation] PASS all checks")
	else:
		push_error("[NeutralCropGeneratorChunkValidation] FAIL count=%d" % failures)
	if is_instance_valid(GameAuthority):
		GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[NeutralCropGeneratorChunkValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[NeutralCropGeneratorChunkValidation] FAIL: %s" % description)
