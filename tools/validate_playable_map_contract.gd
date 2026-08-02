extends SceneTree

const MAPS := [
	"res://worlds/creston_town/creston_town.tscn",
	"res://worlds/redpine_county/redpine_county.tscn",
]


func _initialize() -> void:
	var registry := GameMapRegistryService.new()
	root.add_child(registry)
	var registered_maps := registry.list_singleplayer_maps()
	if registered_maps.size() < MAPS.size():
		_fail("GameMapRegistry did not list both built-in maps")
		return
	for definition: Dictionary in registered_maps:
		if str(definition.get("source", "")) == "builtin" and not bool(definition.get("is_compatible", false)):
			_fail("GameMapRegistry rejected %s: %s" % [
				str(definition.get("map_id", "")), str(definition.get("validation_errors", [])),
			])
			return
	for scene_path: String in MAPS:
		var packed := load(scene_path) as PackedScene
		var root := packed.instantiate() as Node3D if packed != null else null
		if root == null:
			_fail("Cannot instantiate %s" % scene_path)
			return
		for node_path: String in [
			"CloudSystem", "DayNightSystem", "WeatherSystem", "Ground",
			"SurfaceAreas", "TerrainSurfaceBaker", "Roads", "TreeForestManager",
			"SpawnPoints/RedTeamSpawn", "SpawnPoints/BlueTeamSpawn",
		]:
			if root.get_node_or_null(NodePath(node_path)) == null:
				_fail("%s is missing %s" % [scene_path, node_path])
				return
		if not root.has_method("get_team_spawn_position"):
			_fail("%s does not use FarmWorldInitializer" % scene_path)
			return
		var red := root.get_node_or_null("SpawnPoints/RedTeamSpawn") as TeamSpawnPoint
		var blue := root.get_node_or_null("SpawnPoints/BlueTeamSpawn") as TeamSpawnPoint
		if red == null or blue == null or red.team != "red" or blue.team != "blue":
			_fail("%s has invalid independent team spawn points" % scene_path)
			return
		root.free()
	print("PLAYABLE_MAP_CONTRACT_VALIDATION_OK: %d maps" % MAPS.size())
	quit(0)


func _fail(message: String) -> void:
	push_error("PLAYABLE_MAP_CONTRACT_VALIDATION_FAILED: " + message)
	quit(1)
