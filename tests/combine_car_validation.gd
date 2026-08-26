extends Node3D

const COMBINE_SCENE := preload("res://vehicles/combine_car.tscn")
const PLAYER_SCENE := preload("res://character/player.tscn")
const FARM_TILE_COLLISION_MASK := GameAuthority.COLLISION_LAYER_FARM_TILE
const VALIDATION_DRIVER_PEER_ID := 1
const VALIDATION_TEAM := "blue"
const HEADER_POSITION := Vector3(0.0, 1.0, 5.764908)

var failures := 0
var _vehicle: CombineCar
var _field: FarmFieldGenerator
var _interaction_player: GamePlayer


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "CombineCarValidation",
		"team": VALIDATION_TEAM,
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self

	_vehicle = COMBINE_SCENE.instantiate() as CombineCar
	_check(_vehicle != null, "CombineCar scene loads as CombineCar")
	if _vehicle == null:
		_finish()
		return
	_vehicle.position = Vector3.ZERO
	_vehicle.owner_team = VALIDATION_TEAM
	add_child(_vehicle)
	await get_tree().process_frame

	_check(_vehicle.vehicle_config != null, "VehicleConfig is assigned")
	_check(_vehicle.vehicle_config != null and not _vehicle.vehicle_config.open_cabin, "cab is closed")
	_check(_vehicle.get_seat_count() == 1, "CombineCar has one seat")
	var headlight := _vehicle.get_node_or_null("HeadLightPos/Light3D") as Light3D
	_check(headlight != null, "HeadLightPos has a Light3D")
	var headlight_forward := -headlight.global_transform.basis.z.normalized() if headlight != null else Vector3.ZERO
	_check(headlight != null and headlight_forward.dot(_vehicle.global_transform.basis.z.normalized()) > 0.99, "headlight projects along the vehicle forward axis")
	_check(headlight != null and not headlight.visible and not _vehicle.headlights_on, "headlight starts off")
	_vehicle.toggle_headlights()
	_check(_vehicle.headlights_on and headlight != null and headlight.visible, "headlight toggle turns on the Light3D")
	var headlight_state := _vehicle.get_network_state()
	_check(bool(headlight_state.get("headlights_on", false)), "headlight state is in the vehicle snapshot")
	_vehicle.toggle_headlights()
	_check(not _vehicle.headlights_on and headlight != null and not headlight.visible, "headlight toggle turns off the Light3D")
	_check(_vehicle.collision_layer == GameAuthority.COLLISION_LAYER_VEHICLES, "vehicle layer matches VehicleBase")
	_check(_vehicle.collision_mask == 12427, "vehicle mask matches CargoCar/FarmBaseVehicle")
	_check(_vehicle.is_in_group("vehicle_bases"), "vehicle is registered in vehicle_bases")
	var hit_area := _vehicle.get_node_or_null("Hit3D") as Area3D
	_check(hit_area != null, "Hit3D exists")
	_check(
		hit_area != null
			and hit_area.collision_layer == 0
			and hit_area.collision_mask == GameAuthority.COLLISION_LAYER_BULLET
			and hit_area.monitoring
			and hit_area.monitorable,
		"Hit3D uses bullet detection settings"
	)
	var camera := _vehicle.get_node_or_null("CameraOrbitYaw/CameraOrbitPitch/VehicleCamera") as Camera3D
	_check(camera != null, "third-person vehicle camera exists")
	_check(_vehicle.get_node_or_null("ExitPoint") != null, "ExitPoint exists")
	_interaction_player = PLAYER_SCENE.instantiate() as GamePlayer
	_check(_interaction_player != null, "player scene loads for vehicle interaction validation")
	if _interaction_player != null:
		_interaction_player.authority_peer_id = VALIDATION_DRIVER_PEER_ID
		_interaction_player.team = VALIDATION_TEAM
		add_child(_interaction_player)
		await get_tree().process_frame
		_interaction_player.set_process(false)
		_interaction_player.set_physics_process(false)
		_interaction_player.global_position = Vector3(0.0, 0.6, -3.8)
		_interaction_player.rotation.y = PI
		_interaction_player._set_interaction_detectors_enabled(true)
		var interaction_target := _interaction_player._get_best_interaction_target(true)
		_check(
			str(interaction_target.get("kind", "")) == "vehicle"
				and interaction_target.get("vehicle", interaction_target.get("body", null)) == _vehicle,
			"player interaction ShapeCast detects CombineCar"
		)
	_check(_vehicle._header_reel != null, "HeaderReel is found recursively below Mesh")
	var shape_cast := _vehicle.get_node_or_null("ShapeCast3D") as ShapeCast3D
	_check(shape_cast != null, "harvest ShapeCast3D exists")
	_check(
		shape_cast != null
			and shape_cast.collision_mask == FARM_TILE_COLLISION_MASK
			and shape_cast.collide_with_bodies
			and not shape_cast.collide_with_areas
			and shape_cast.exclude_parent
			and shape_cast.max_results == 64
			and shape_cast.enabled,
		"harvest ShapeCast uses FarmTile settings"
	)
	_check(shape_cast != null and is_equal_approx(shape_cast.position.y, 0.35), "harvest ShapeCast is positioned at crop height")
	_check(is_equal_approx(_vehicle.get_max_forward_speed(), 3.0), "forward speed is 3 m/s")
	_check(is_equal_approx(_vehicle.get_max_reverse_speed(), 3.0), "reverse speed is 3 m/s")
	_check(is_equal_approx(_vehicle.vehicle_config.max_hp, 7000.0), "HP is configured to 7000")
	var hp_before_explosion := _vehicle.current_hp
	var explosion_damage_count := GameAuthority._damage_vehicles_in_radius(
		_vehicle.global_position,
		4.0,
		10.0,
		"red",
		"combine_car_validation"
	)
	_check(explosion_damage_count == 1 and _vehicle.current_hp < hp_before_explosion, "explosion radius damages CombineCar")
	_vehicle.current_hp = _vehicle.vehicle_config.max_hp

	_check(_vehicle.enter_driver(VALIDATION_DRIVER_PEER_ID), "driver enters the only seat")
	_check(not _vehicle.can_enter_driver(2), "second player cannot enter a full CombineCar")
	var closed_transform := _vehicle.get_occupant_world_transform(0)
	_check(closed_transform.origin.is_equal_approx(_vehicle.global_position), "closed occupant uses vehicle root transform")
	_check(not _vehicle.should_show_occupant(0), "closed occupant is hidden")

	var editor := HarvestOperationRuntimeMapEditor.new()
	var has_combine_asset := false
	for asset_value: Variant in HarvestOperationRuntimeMapEditor.VEHICLE_ASSETS:
		var asset := asset_value as Dictionary
		if str(asset.get("path", "")) == "res://vehicles/combine_car.tscn":
			has_combine_asset = true
			break
	_check(has_combine_asset, "map editor vehicle catalog contains CombineCar")
	var has_police_asset := false
	for asset_value: Variant in HarvestOperationRuntimeMapEditor.VEHICLE_ASSETS:
		var asset := asset_value as Dictionary
		if str(asset.get("path", "")) == "res://vehicles/police_car.tscn":
			has_police_asset = true
			break
	_check(has_police_asset, "map editor vehicle catalog contains PoliceCar")
	var has_fire_pickup_asset := false
	for asset_value: Variant in HarvestOperationRuntimeMapEditor.VEHICLE_ASSETS:
		var asset := asset_value as Dictionary
		if str(asset.get("path", "")) == "res://vehicles/fire_pickup.tscn":
			has_fire_pickup_asset = true
			break
	_check(has_fire_pickup_asset, "map editor vehicle catalog contains FirePickup")
	var has_mini_car_asset := false
	for asset_value: Variant in HarvestOperationRuntimeMapEditor.VEHICLE_ASSETS:
		var asset := asset_value as Dictionary
		if str(asset.get("path", "")) == "res://vehicles/mini_car.tscn":
			has_mini_car_asset = true
			break
	_check(has_mini_car_asset, "map editor vehicle catalog contains MiniCar")
	var fire_pickup := load("res://vehicles/fire_pickup.tscn").instantiate() as VehicleBase
	_check(fire_pickup != null, "FirePickup is available for FOV comparison")
	if fire_pickup != null:
		_check(
			fire_pickup.get_camera_fov_for_speed(fire_pickup.get_max_forward_speed())
				> _vehicle.get_camera_fov_for_speed(_vehicle.get_max_forward_speed()),
			"higher maximum speed reaches a wider driving FOV"
		)
		fire_pickup.free()
	var legacy_node := Node3D.new()
	legacy_node.set_meta("map_editor_category", "building")
	legacy_node.set_meta("map_editor_asset_path", "res://buildings/CombineCar.tscn")
	var normalized_metadata := editor._normalize_vehicle_asset_metadata(legacy_node)
	_check(str(normalized_metadata.get("category", "")) == "vehicle", "legacy CombineCar metadata becomes vehicle")
	_check(
		str(normalized_metadata.get("asset_path", "")) == "res://vehicles/combine_car.tscn",
		"legacy CombineCar path migrates to vehicles/combine_car.tscn"
	)
	legacy_node.free()
	var legacy_police_node := Node3D.new()
	legacy_police_node.set_meta("map_editor_category", "building")
	legacy_police_node.set_meta("map_editor_asset_path", "res://buildings/PoliceCar.tscn")
	var normalized_police_metadata := editor._normalize_vehicle_asset_metadata(legacy_police_node)
	_check(str(normalized_police_metadata.get("category", "")) == "vehicle", "legacy PoliceCar metadata becomes vehicle")
	_check(
		str(normalized_police_metadata.get("asset_path", "")) == "res://vehicles/police_car.tscn",
		"legacy PoliceCar path migrates to vehicles/police_car.tscn"
	)
	legacy_police_node.free()
	editor.free()

	if _vehicle._header_reel != null:
		var initial_rotation := _vehicle._header_reel.rotation
		_vehicle.current_speed = 0.0
		_vehicle._process(0.5)
		_check(_vehicle._header_reel.rotation.is_equal_approx(initial_rotation), "stopped vehicle does not rotate HeaderReel")
		_vehicle.current_speed = 1.0
		_vehicle._process(0.5)
		var moving_rotation := _vehicle._header_reel.rotation
		_check(not is_equal_approx(moving_rotation.x, initial_rotation.x), "moving vehicle rotates HeaderReel")
		_check(is_equal_approx(moving_rotation.y, initial_rotation.y), "HeaderReel Y rotation is preserved")
		_check(is_equal_approx(moving_rotation.z, initial_rotation.z), "HeaderReel Z rotation is preserved")

	_field = FarmFieldGenerator.new()
	_field.name = "CombineCarValidationField"
	_field.field_label = "combine_car_validation"
	_field.length_tiles = 1
	_field.width_tiles = 1
	_field.tile_spacing = 2.2
	_field.generate_on_ready = false
	_field.position = HEADER_POSITION
	add_child(_field)
	var generated_tiles := _field.generate_field()
	_check(generated_tiles.size() == 1, "validation field creates one tile")
	await get_tree().physics_frame
	if not generated_tiles.is_empty():
		var tile := generated_tiles[0] as FarmTile
		_check(tile != null, "generated object is FarmTile")
		if tile != null:
			_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 100, true), "mature crop is planted")
			var before_stationary := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
			_vehicle.current_speed = 0.0
			_vehicle._physics_process(0.016)
			_check(
				is_equal_approx(GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato"), before_stationary),
				"stationary CombineCar does not harvest"
			)
			_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 100, true), "mature crop is replanted")
			var before_moving := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
			_vehicle.current_speed = 1.0
			_vehicle._physics_process(0.016)
			var after_moving := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
			_check(after_moving > before_moving, "moving CombineCar harvests a mature crop")

			_check(tile.apply_authoritative_plant("potato", VALIDATION_TEAM, 100, true), "mature crop is replanted for deduplication")
			var before_duplicate := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
			var duplicate_count := _vehicle._harvest_detected_tiles([tile, tile], VALIDATION_TEAM)
			var after_duplicate := GlobalVar.check_team_item_amount(VALIDATION_TEAM, "potato")
			_check(duplicate_count == 1, "duplicate FarmTile detections harvest once")
			_check(is_equal_approx(after_duplicate - before_duplicate, 1.0), "duplicate detection produces one crop result")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("[CombineCarValidation] PASS all checks")
	else:
		push_error("[CombineCarValidation] FAIL count=%d" % failures)
	if is_instance_valid(_vehicle):
		_vehicle.queue_free()
	if is_instance_valid(_field):
		_field.queue_free()
	if is_instance_valid(_interaction_player):
		_interaction_player.queue_free()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[CombineCarValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[CombineCarValidation] FAIL: %s" % description)
