extends Node3D

const VehicleSpawnCatalogScript = preload("res://src/vehicle_spawn_catalog.gd")
const PlacementQueryScript = preload("res://src/placement_query.gd")

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_catalog_and_profiles()
	var root := Node3D.new()
	root.name = "VehicleSpawnPlacementValidationWorld"
	add_child(root)
	var ground := _add_box_body(
		root,
		"Ground",
		Vector3(0.0, -0.5, 0.0),
		Vector3(80.0, 1.0, 80.0),
		1
	)
	_check(ground != null, "validation ground is created")
	await get_tree().physics_frame

	var empty_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		Vector3(24.0, 0.0, 0.0),
		"mini_car",
		{"max_search_radius": 0.0}
	)
	_check(bool(empty_result.get("ok", false)), "empty ground accepts a MiniCar")
	_check(str(empty_result.get("spawn_mode", "")) == "ground", "empty ground uses ground spawn")
	_check(empty_result.get("position", Vector3.ZERO) is Vector3, "spawn result has a landing position")

	var dynamic_blocker := _add_box_body(
		root,
		"MovingActorPlaceholder",
		Vector3(0.0, 0.75, 0.0),
		Vector3(10.0, 2.0, 10.0),
		8
	)
	_check(dynamic_blocker != null, "validation dynamic actor is created")
	await get_tree().physics_frame
	var dynamic_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		Vector3(0.0, 0.0, 0.0),
		"mini_car",
		{"max_search_radius": 0.0}
	)
	_check(bool(dynamic_result.get("ok", false)), "dynamic blocker enters airdrop fallback")
	_check(str(dynamic_result.get("spawn_mode", "")) == "airdrop", "dynamic blocker selects airdrop mode")
	_check(bool(dynamic_result.get("used_dynamic_fallback", false)), "airdrop result records dynamic fallback")
	_check(
		float((dynamic_result.get("drop_start_position", Vector3.ZERO) as Vector3).y)
			> float((dynamic_result.get("position", Vector3.ZERO) as Vector3).y),
		"airdrop starts above the landing point"
	)
	_check(not (dynamic_result.get("dynamic_blockers", []) as Array).is_empty(), "airdrop reports dynamic blockers")

	var excluded_dynamic_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		Vector3(0.0, 0.0, 0.0),
		"mini_car",
		{
			"max_search_radius": 0.0,
			"exclude_rids": [(dynamic_blocker as CollisionObject3D).get_rid()],
		}
	)
	_check(bool(excluded_dynamic_result.get("ok", false)), "excluded dynamic actor no longer blocks placement")
	_check(str(excluded_dynamic_result.get("spawn_mode", "")) == "ground", "excluded actor uses ground spawn")

	var single_rid_exclusion_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		Vector3(0.0, 0.0, 0.0),
		"mini_car",
		{
			"max_search_radius": 0.0,
			"exclude_rid": (dynamic_blocker as CollisionObject3D).get_rid(),
		}
	)
	_check(bool(single_rid_exclusion_result.get("ok", false)), "single RID exclusion is accepted")

	var hard_blocker := _add_box_body(
		root,
		"HardObstacle",
		Vector3(16.0, 0.75, 0.0),
		Vector3(4.0, 2.0, 4.0),
		4096
	)
	_check(hard_blocker != null, "validation hard obstacle is created")
	await get_tree().physics_frame
	var hard_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		Vector3(16.0, 0.0, 0.0),
		"mini_car",
		{"max_search_radius": 0.0}
	)
	_check(not bool(hard_result.get("ok", false)), "hard obstacle rejects ground and airdrop placement")

	var target_marker := Marker3D.new()
	target_marker.position = Vector3(24.0, 0.0, 12.0)
	target_marker.rotation.y = 0.75
	root.add_child(target_marker)
	await get_tree().process_frame
	var marker_result := PlacementQueryScript.resolve_vehicle_spawn(
		get_world_3d(),
		target_marker,
		"mini_car",
		{"max_search_radius": 0.0}
	)
	_check(bool(marker_result.get("ok", false)), "Node3D target is accepted")
	_check(is_equal_approx(float(marker_result.get("yaw", 0.0)), 0.75), "Node3D target preserves yaw")

	_finish(root)


func _validate_catalog_and_profiles() -> void:
	for vehicle_id_value: Variant in VehicleSpawnCatalogScript.VEHICLE_DEFINITIONS.keys():
		var vehicle_id := str(vehicle_id_value)
		var resolved := VehicleSpawnCatalogScript.resolve_scene_path(vehicle_id)
		_check(bool(resolved.get("ok", false)), "%s resolves from vehicle catalog" % vehicle_id)
		var scene_path := str(resolved.get("scene_path", ""))
		_check(ResourceLoader.exists(scene_path), "%s scene exists" % vehicle_id)
		var profile := PlacementQueryScript._get_vehicle_profile(scene_path)
		_check(bool(profile.get("ok", false)), "%s has a collision profile" % vehicle_id)
		_check(float(profile.get("height", 0.0)) > 0.0, "%s collision profile has height" % vehicle_id)
	var red_cargo := VehicleSpawnCatalogScript.resolve_scene_path("cargo_car", "red")
	var blue_cargo := VehicleSpawnCatalogScript.resolve_scene_path("cargo_car", "blue")
	_check(str(red_cargo.get("scene_path", "")).ends_with("red_cargo_car.tscn"), "CargoCar red variant resolves")
	_check(str(blue_cargo.get("scene_path", "")).ends_with("blue_cargo_car.tscn"), "CargoCar blue variant resolves")
	var direct_path := VehicleSpawnCatalogScript.resolve_scene_path("res://vehicles/mini_car.tscn")
	_check(str(direct_path.get("vehicle_id", "")) == "mini_car", "direct scene path resolves to a vehicle id")


func _add_box_body(
	parent: Node,
	body_name: String,
	position: Vector3,
	size: Vector3,
	layer: int
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = body_name
	body.collision_layer = layer
	body.collision_mask = 0
	body.position = position
	var shape_node := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	shape_node.shape = shape
	body.add_child(shape_node)
	parent.add_child(body)
	return body


func _finish(root: Node) -> void:
	root.queue_free()
	if failures.is_empty():
		print("[VehicleSpawnPlacementValidation] PASS")
		get_tree().quit(0)
	else:
		for failure: String in failures:
			push_error("[VehicleSpawnPlacementValidation] " + failure)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
