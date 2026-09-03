extends Node

const PLACEMENT_QUERY := preload("res://src/placement_query.gd")
const DEFENSE_SCENES := [
	"res://character/weapons/TallBrick.tscn",
	"res://character/weapons/TallLogWall.tscn",
	"res://character/weapons/TallMeshWall.tscn",
	"res://character/weapons/WireMeshGate.tscn",
	"res://character/weapons/ChainLinkFence.tscn",
]
var failures: Array[String] = []
var skipped_without_entity_collision: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var paths: Array[String] = []
	_collect_scenes("res://buildings", paths, true)
	_collect_scenes("res://facilities", paths, false)
	for scene_path in DEFENSE_SCENES:
		paths.append(scene_path)
	paths.sort()
	for scene_path in paths:
		_validate_scene(scene_path)
	print("[PlacementFootprintValidation] skipped_without_entity_collision=", skipped_without_entity_collision)
	_validate_key_footprints()
	_finish()


func _collect_scenes(directory_path: String, paths: Array[String], skip_nature: bool) -> void:
	for entry_value in ResourceLoader.list_directory(directory_path):
		var entry := str(entry_value)
		if entry.ends_with("/"):
			var child_directory := directory_path.path_join(entry.trim_suffix("/"))
			if skip_nature and child_directory == "res://buildings/nature":
				continue
			_collect_scenes(child_directory, paths, skip_nature)
		elif entry.get_extension().to_lower() == "tscn":
			paths.append(directory_path.path_join(entry))


func _validate_scene(scene_path: String) -> void:
	var packed := load(scene_path) as PackedScene
	_check(packed != null, "%s loads" % scene_path)
	if packed == null:
		return
	var instance := packed.instantiate() as Node3D
	_check(instance != null, "%s instantiates" % scene_path)
	if instance == null:
		return
	var footprint := PLACEMENT_QUERY.placement_footprint_for_node(instance)
	if scene_path.contains("/GroundDecorations/"):
		_check(bool(instance.get_meta("map_ground_decoration", false)), "%s is marked as a ground decoration" % scene_path)
		_check(footprint.is_empty(), "%s remains a collision-free ground decoration" % scene_path)
		instance.free()
		return
	if footprint.is_empty():
		skipped_without_entity_collision.append(scene_path)
	else:
		_check(not footprint.is_empty(), "%s has a placement footprint" % scene_path)
		_check(footprint.get("shape", null) is BoxShape3D, "%s footprint is a BoxShape3D" % scene_path)
		_check(is_equal_approx(float(footprint.get("clearance", 0.0)), 0.02), "%s uses 2 cm placement clearance" % scene_path)
	instance.free()
func _validate_key_footprints() -> void:
	var tower := (load("res://buildings/checkpoint_tower.tscn") as PackedScene).instantiate() as Node3D
	var tower_footprint := PLACEMENT_QUERY.placement_footprint_for_node(tower)
	var tower_box := tower_footprint.get("shape", null) as BoxShape3D
	_check(tower_box != null and tower_box.size.is_equal_approx(Vector3(5.2, 9.82, 5.2)), "checkpoint tower footprint matches its 5.2 m base")
	tower.free()
	var fence := (load("res://character/weapons/ChainLinkFence.tscn") as PackedScene).instantiate() as Node3D
	var fence_footprint := PLACEMENT_QUERY.placement_footprint_for_node(fence)
	var fence_box := fence_footprint.get("shape", null) as BoxShape3D
	_check(fence_box != null and fence_box.size.x > 3.9 and fence_box.size.z <= 1.01, "chain-link fence footprint stays long and narrow")
	fence.free()


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[PlacementFootprintValidation] PASS skipped_without_entity_collision=%d" % skipped_without_entity_collision.size())
		get_tree().quit(0)
		return
	for failure in failures:
		push_error("[PlacementFootprintValidation] " + failure)
	get_tree().quit(1)
