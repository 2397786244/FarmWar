extends Node
class_name GameMapRegistryService

## Central registry for playable maps.  Built-in maps live under res://worlds;
## runtime-editor packages live under user://maps and are discovered locally.
const USER_MAP_ROOT := "user://maps"

const REQUIRED_ROOT_NODES := [
	"Sun",
	"WorldEnvironment",
	"NavigationRegion3D",
	"Ground",
	"MapBoundaryWalls",
	"CloudSystem",
	"DayNightSystem",
	"WeatherSystem",
	"SurfaceAreas",
	"TerrainSurfaceBaker",
	"Roads",
	"TreeForestManager",
	"SpawnPoints/RedTeamSpawn",
	"SpawnPoints/BlueTeamSpawn",
]

const BUILTIN_MAPS: Array[Dictionary] = [
	{
		"map_id": "creston_town",
		"display_name": "Creston Town",
		"scene_path": "res://worlds/creston_town/creston_town.tscn",
		"icon_path": "res://worlds/creston_town/map_icon.svg",
		"loading_images_directory": "res://assets/loading/creston_town",
		"size": Vector2i(256, 256),
		"source": "builtin",
	},
	{
		"map_id": "redpine_county",
		"display_name": "Redpine County",
		"scene_path": "res://worlds/redpine_county/redpine_county.tscn",
		"icon_path": "res://worlds/redpine_county/map_icon.svg",
		"loading_images_directory": "res://assets/loading/redpine_county",
		"size": Vector2i(1024, 1024),
		"source": "builtin",
	},
]


func list_singleplayer_maps() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for definition_value: Dictionary in BUILTIN_MAPS:
		maps.append(_validated_map(definition_value.duplicate(true)))
	for definition: Dictionary in _discover_user_maps():
		maps.append(_validated_map(definition))
	return maps


func get_map_by_id(map_id: String) -> Dictionary:
	for definition: Dictionary in list_singleplayer_maps():
		if str(definition.get("map_id", "")) == map_id:
			return definition
	return {}


func _discover_user_maps() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(USER_MAP_ROOT)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with("."):
			var folder := USER_MAP_ROOT.path_join(entry)
			var manifest_path := folder.path_join("map.json")
			var manifest := _read_manifest(manifest_path)
			if not manifest.is_empty():
				var size_value: Variant = manifest.get("size", {})
				var size := size_value as Dictionary if size_value is Dictionary else {}
				var icon_name := str(manifest.get("icon", ""))
				result.append({
					"map_id": str(manifest.get("map_id", entry)),
					"display_name": str(manifest.get("display_name", entry)),
					"scene_path": folder.path_join(str(manifest.get("scene", "%s.tscn" % entry))),
					"icon_path": folder.path_join(icon_name) if not icon_name.is_empty() else "",
					"loading_images_directory": "",
					"size": Vector2i(int(size.get("width", 0)), int(size.get("depth", 0))),
					"source": "runtime_editor",
					"manifest_path": manifest_path,
				})
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _read_manifest(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _validated_map(definition: Dictionary) -> Dictionary:
	var scene_path := str(definition.get("scene_path", ""))
	var errors: Array[String] = []
	if scene_path.is_empty() or not ResourceLoader.exists(scene_path):
		errors.append("找不到地图场景")
	else:
		var scene := load(scene_path) as PackedScene
		var root := scene.instantiate() as Node3D if scene != null else null
		if root == null:
			errors.append("地图根节点不是 Node3D")
		else:
			if not root.has_method("get_team_spawn_position"):
				errors.append("未挂载 FarmWorldInitializer")
			for node_name: String in REQUIRED_ROOT_NODES:
				if root.get_node_or_null(NodePath(node_name)) == null:
					errors.append("缺少 %s" % node_name)
			if root.get_node_or_null("GrassScatter") == null and root.get_node_or_null("ManualGrass") == null:
				errors.append("缺少 GrassScatter 或 ManualGrass")
			root.free()
	definition["is_compatible"] = errors.is_empty()
	definition["validation_errors"] = errors
	return definition
