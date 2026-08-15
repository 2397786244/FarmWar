extends Node3D

const FARM_VEHICLE_SCENE := preload("res://vehicles/farm_base_vehicle.tscn")
const FARM_TILE_COLLISION_MASK := GameAuthority.COLLISION_LAYER_FARM_TILE
const EXPECTED_REEL_LAYER := GameAuthority.COLLISION_LAYER_TOOL | GameAuthority.COLLISION_LAYER_BULLET
const EXPECTED_REEL_MASK := GameAuthority.FREE_PLACEMENT_BLOCKING_MASK
const VALIDATION_DRIVER_PEER_ID := 1
const VALIDATION_TEAM := "blue"
const VEHICLE_POSITION := Vector3(0.0, 0.0, 4.2037881)
const FIELD_POSITION := Vector3(0.0, 1.3317081, 0.0)

var failures := 0
var _field: FarmFieldGenerator
var _vehicle: FarmBaseVehicle


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "HarvestReelValidation",
		"team": VALIDATION_TEAM,
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self

	_field = FarmFieldGenerator.new()
	_field.name = "HarvestReelValidationField"
	_field.field_label = "harvest_reel_validation"
	_field.length_tiles = 1
	_field.width_tiles = 1
	_field.tile_spacing = 2.2
	_field.generate_on_ready = false
	_field.position = FIELD_POSITION
	add_child(_field)
	var generated_tiles := _field.generate_field()
	_check(generated_tiles.size() == 1, "validation field creates one FarmTile")
	await get_tree().process_frame

	_vehicle = FARM_VEHICLE_SCENE.instantiate() as FarmBaseVehicle
	_check(_vehicle != null, "FarmBaseVehicle scene loads")
	if _vehicle == null or generated_tiles.is_empty():
		_finish()
		return
	# Keep the test vehicle out of the authority vehicle registry. The reel still
	# runs in local authority mode and its authored physics/query nodes remain
	# active, which isolates this test from vehicle driving physics.
	_vehicle.vehicle_deployed = false
	_vehicle.position = VEHICLE_POSITION
	_vehicle.set_harvest_reel_installed(true)
	add_child(_vehicle)
	await get_tree().process_frame
	_vehicle.set_physics_process(false)
	_vehicle.current_hp = _vehicle.get_max_hp()
	_check(_vehicle.enter_driver(VALIDATION_DRIVER_PEER_ID), "validation driver occupies the FarmBase seat")

	var reel := _vehicle.get_harvest_reel()
	_check(reel != null, "HarvestReel installs at HarvestReelPos")
	if reel == null:
		_finish()
		return

	var visual := reel.find_child("HarvestReel", true, false) as Node3D
	var pivot := visual.find_child("HarvestReelPivot", true, false) as Node3D if visual != null else null
	var shape_cast := reel.find_child("ShapeCast3D", true, false) as ShapeCast3D
	_check(visual != null, "HarvestReel visual is found recursively")
	_check(pivot != null, "HarvestReelPivot is found recursively below the visual")
	_check(shape_cast != null, "HarvestReel ShapeCast3D is found recursively")
	_check(reel.collision_layer == EXPECTED_REEL_LAYER, "HarvestReel root collision layer uses TOOL and BULLET")
	_check(reel.collision_mask == EXPECTED_REEL_MASK, "HarvestReel root collision mask uses free-placement blockers")
	_check(
		shape_cast != null
			and shape_cast.collision_mask == FARM_TILE_COLLISION_MASK
			and shape_cast.collide_with_bodies
			and not shape_cast.collide_with_areas
			and shape_cast.exclude_parent
			and shape_cast.max_results == 64,
		"ShapeCast uses FarmTile body-only detection with 64 results"
	)
	_check(
		reel.get_collision_exceptions().has(_vehicle)
			and _vehicle.get_collision_exceptions().has(reel),
		"HarvestReel and FarmBaseVehicle have mutual collision exceptions"
	)

	if pivot != null:
		var stationary_rotation := pivot.rotation
		_vehicle.current_speed = 0.0
		reel._process(0.5)
		_check(pivot.rotation.is_equal_approx(stationary_rotation), "stationary vehicle does not rotate the reel")
		var moving_rotation := pivot.rotation
		_vehicle.current_speed = 1.0
		reel._process(0.5)
		_check(not is_equal_approx(pivot.rotation.x, moving_rotation.x), "moving vehicle rotates the reel")
		_check(is_equal_approx(pivot.rotation.y, moving_rotation.y), "reel rotation does not change local Y")
		_check(is_equal_approx(pivot.rotation.z, moving_rotation.z), "reel rotation does not change local Z")

	var tile := generated_tiles[0] as FarmTile
	_check(tile != null, "generated collision resolves to a FarmTile")
	if tile == null:
		_finish()
		return

	_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 20, false), "immature crop is planted for validation")
	var immature_before := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
	_vehicle.current_speed = 0.0
	reel._physics_process(0.016)
	_check(not tile.can_harvest, "immature crop is not harvestable")
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato"), immature_before),
		"stationary reel does not harvest an immature crop"
	)

	_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 100, true), "mature crop is planted for validation")
	var mature_before := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
	_vehicle.current_speed = 1.0
	reel._physics_process(0.016)
	var mature_after := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
	_check(mature_after > mature_before, "moving reel harvests a mature crop")
	_check(tile.seed_record.is_empty() and not tile.can_harvest, "harvested crop is cleared through FarmTile.harvest")

	_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 100, true), "mature crop is replanted for duplicate validation")
	var duplicate_before := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
	var duplicate_count := reel._harvest_detected_tiles([tile, tile], VALIDATION_TEAM)
	var duplicate_after := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
	_check(duplicate_count == 1, "the same FarmTile is harvested once after duplicate detections")
	_check(is_equal_approx(duplicate_after - duplicate_before, 1.0), "duplicate FarmTile detection adds one crop result")

	var state := _vehicle.get_network_state()
	_check(bool(state.get("harvest_reel_installed", false)), "vehicle snapshot includes HarvestReel installation")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("[HarvestReelValidation] PASS all checks")
	else:
		push_error("[HarvestReelValidation] FAIL count=%d" % failures)
	if is_instance_valid(_vehicle):
		_vehicle.queue_free()
	if is_instance_valid(_field):
		_field.queue_free()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[HarvestReelValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[HarvestReelValidation] FAIL: %s" % description)
