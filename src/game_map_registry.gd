extends Node
class_name GameMapRegistryService

## Central registry for playable maps. Built-in maps live under res://worlds;
## manually installed packages live in maps/ beside the executable. Runtime
## editor saves under user://maps are local source packages and must be
## exported before they become playable maps.
const USER_MAP_ROOT := "user://maps"
const PORTABLE_MAP_FOLDER_NAME := "maps"
const DEFAULT_MAP_VERSION := "1.0.0"

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
		"map_version": DEFAULT_MAP_VERSION,
		"map_hash": "builtin:creston_town:%s" % DEFAULT_MAP_VERSION,
	},
	{
		"map_id": "redpine_county",
		"display_name": "Redpine County",
		"scene_path": "res://worlds/redpine_county/redpine_county.tscn",
		"icon_path": "res://worlds/redpine_county/map_icon.svg",
		"loading_images_directory": "res://assets/loading/redpine_county",
		"size": Vector2i(1024, 1024),
		"source": "builtin",
		"map_version": DEFAULT_MAP_VERSION,
		"map_hash": "builtin:redpine_county:%s" % DEFAULT_MAP_VERSION,
	},
	{
		"map_id": "multiplayer_test",
		"display_name": "multiplayer test",
		"scene_path": "res://worlds/multiplayer_test/multiplayer_test.tscn",
		"icon_path": "res://worlds/multiplayer_test/map_icon.png",
		"loading_images_directory": "",
		"size": Vector2i(256, 256),
		"source": "builtin",
		"map_version": DEFAULT_MAP_VERSION,
		"map_hash": "builtin:multiplayer_test:%s" % DEFAULT_MAP_VERSION,
	},
]


func list_singleplayer_maps() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for definition_value: Dictionary in BUILTIN_MAPS:
		maps.append(_validated_map(definition_value.duplicate(true)))
	for definition: Dictionary in _discover_portable_maps():
		maps.append(_validated_map(definition))
	return maps


## Used by editor tooling and diagnostics; these packages are intentionally not
## exposed as playable maps until the user exports them to the portable maps
## directory (or packages them as res:// content).
func list_local_saved_maps() -> Array[Dictionary]:
	var maps: Array[Dictionary] = []
	for definition: Dictionary in _discover_user_maps():
		maps.append(_validated_map(definition))
	return maps


func get_map_by_id(map_id: String) -> Dictionary:
	for definition: Dictionary in list_singleplayer_maps():
		if str(definition.get("map_id", "")) == map_id:
			return definition
	return {}


## Dedicated servers use the package directory name in server_config.json.
## For user-created packages this is normally the same as manifest.map_id, but
## keeping both identifiers lets a published folder retain a stable filename.
func get_map_by_package_name(package_name: String) -> Dictionary:
	var requested := package_name.strip_edges()
	if requested.is_empty():
		return {}
	for definition: Dictionary in list_singleplayer_maps():
		if str(definition.get("package_name", "")) == requested:
			return definition
		if str(definition.get("map_id", "")) == requested:
			return definition
	return {}


func get_server_map_by_package_name(package_name: String) -> Dictionary:
	# Dedicated servers must never depend on an operator's user:// editor
	# saves; only built-in and executable-adjacent packages are authoritative.
	return get_map_by_package_name(package_name)


func get_portable_maps_root() -> String:
	if OS.has_feature("editor"):
		# While developing, the editor binary is Godot itself, not the future
		# FarmWar executable. Use the project-level maps folder as its portable
		# equivalent; exported builds switch automatically to the executable dir.
		return ProjectSettings.globalize_path("res://maps")
	var executable_path := OS.get_executable_path()
	if executable_path.is_empty():
		return ""
	var executable_dir := executable_path.get_base_dir()
	# A macOS .app stores its executable in App.app/Contents/MacOS.  The
	# portable maps folder belongs next to App.app, not inside the bundle.
	if OS.get_name() == "macOS" and executable_dir.ends_with("Contents/MacOS"):
		executable_dir = executable_dir.get_base_dir().get_base_dir().get_base_dir()
	return executable_dir.path_join(PORTABLE_MAP_FOLDER_NAME)


## Resolves and validates a map advertised by a cooperative-world save or Steam
## Lobby. The scene path is deliberately not compared: external absolute paths
## differ per installation, so package name/id, version and hash are portable.
func validate_world_map(world: Dictionary) -> Dictionary:
	var map_id := str(world.get("map_id", "")).strip_edges()
	if map_id.is_empty():
		return {"valid": false, "error": "Lobby 没有提供地图 ID。"}
	var definition := get_map_by_id(map_id)
	if definition.is_empty():
		definition = get_map_by_package_name(map_id)
	if definition.is_empty():
		return {
			"valid": false,
			"error": "本地没有地图“%s”，请先安装相同的地图包。" % str(world.get("map_name", map_id)),
		}
	if not bool(definition.get("is_compatible", false)):
		return {
			"valid": false,
			"error": "本地地图“%s”缺少可运行的基础系统：%s" % [
				str(definition.get("display_name", map_id)),
				"、".join(definition.get("validation_errors", [])),
			],
		}
	var local_version := str(definition.get("map_version", DEFAULT_MAP_VERSION)).strip_edges()
	var advertised_version := str(world.get("map_version", "")).strip_edges()
	if not advertised_version.is_empty() and advertised_version != local_version:
		return {
			"valid": false,
			"error": "地图“%s”版本不一致（房主 %s，本地 %s）。" % [
				str(definition.get("display_name", map_id)), advertised_version, local_version,
			],
		}
	var local_hash := str(definition.get("map_hash", "")).strip_edges()
	var advertised_hash := str(world.get("map_hash", "")).strip_edges()
	if not advertised_hash.is_empty() and not local_hash.is_empty() and advertised_hash != local_hash:
		return {
			"valid": false,
			"error": "地图“%s”的本地包校验值与房主不一致，请安装相同版本。" % str(definition.get("display_name", map_id)),
		}
	return {"valid": true, "map": definition.duplicate(true)}


func _discover_user_maps() -> Array[Dictionary]:
	return _discover_map_packages(USER_MAP_ROOT, "runtime_editor")


func _discover_portable_maps() -> Array[Dictionary]:
	var root := get_portable_maps_root()
	if root.is_empty():
		return []
	return _discover_map_packages(root, "portable")


func _discover_map_packages(root: String, source: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var directory := DirAccess.open(root)
	if directory == null:
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with("."):
			var folder := root.path_join(entry)
			var manifest_path := folder.path_join("map.json")
			var manifest := _read_manifest(manifest_path)
			if not manifest.is_empty():
				var size_value: Variant = manifest.get("size", {})
				var size := size_value as Dictionary if size_value is Dictionary else {}
				var icon_name := str(manifest.get("icon", ""))
				var map_version := str(manifest.get("version", DEFAULT_MAP_VERSION)).strip_edges()
				if map_version.is_empty():
					map_version = DEFAULT_MAP_VERSION
				result.append({
					"map_id": str(manifest.get("map_id", entry)),
					"display_name": str(manifest.get("display_name", entry)),
					"scene_path": folder.path_join(str(manifest.get("scene", "%s.tscn" % entry))),
					"icon_path": folder.path_join(icon_name) if not icon_name.is_empty() else "",
					"loading_images_directory": "",
					"size": Vector2i(int(size.get("width", 0)), int(size.get("depth", 0))),
					"source": source,
					"package_name": entry,
					"manifest_path": manifest_path,
					"map_version": map_version,
					"map_hash": _manifest_hash(manifest_path),
				})
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _manifest_hash(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	while not file.eof_reached():
		var chunk := file.get_buffer(65536)
		if chunk.is_empty():
			break
		context.update(chunk)
	return context.finish().hex_encode()


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
