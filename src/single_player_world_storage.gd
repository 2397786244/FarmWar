extends Node
class_name SinglePlayerWorldStorageService

const DEFAULT_WORLD_ROOT := "user://singleplayer_worlds"
const SAVE_VERSION := 2

var world_root := DEFAULT_WORLD_ROOT
var active_world: Dictionary = {}


func list_worlds() -> Array[Dictionary]:
	var worlds: Array[Dictionary] = []
	var directory := DirAccess.open(world_root)
	if directory == null:
		return worlds
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir() and not entry.begins_with("."):
			var world := load_world(entry)
			if not world.is_empty():
				worlds.append(world)
		entry = directory.get_next()
	directory.list_dir_end()
	worlds.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		return int(left.get("updated_unix", 0)) > int(right.get("updated_unix", 0))
	)
	return worlds


func create_world(config: Dictionary, selection: Dictionary) -> Dictionary:
	var display_name := str(config.get("display_name", "")).strip_edges()
	if display_name.is_empty() or selection.is_empty():
		return {}
	var map_id := str(config.get("map_id", "")).strip_edges()
	var map_scene_path := str(config.get("map_scene_path", "")).strip_edges()
	if map_id.is_empty() or map_scene_path.is_empty():
		return {}
	var world_id := "single_%d_%06d" % [Time.get_unix_time_from_system(), randi_range(0, 999999)]
	var now := Time.get_unix_time_from_system()
	var lock := _normalize_loadout(selection)
	if not _loadout_is_valid(lock):
		return {}
	var player_state := lock.duplicate(true)
	player_state.merge({
		"peer_id": GameAuthority.LOCAL_PLAYER_ID,
		"display_name": "LocalPlayer",
		"team": "red",
		"ready": true,
		"current_hp": 200.0,
		"max_hp": 200.0,
		"respawn_left": 0.0,
	}, true)
	var world := {
		"save_version": SAVE_VERSION,
		"world_id": world_id,
		"display_name": display_name.left(40),
		"map_id": map_id,
		"map_name": str(config.get("map_name", map_id)),
		"map_icon_path": str(config.get("map_icon_path", "")),
		"map_scene_path": map_scene_path,
		"loading_images_directory": str(config.get("loading_images_directory", "")),
		"map_version": str(config.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(config.get("map_hash", "")),
		"map_source": str(config.get("map_source", "builtin")),
		"max_players": 1,
		"death_drop_mode": "save",
		"team_storage": WorldPersistence.make_initial_team_storage(),
		"team_money": float(GlobalVar.INITIAL_MONEY),
		"game_day": 1,
		"world_elapsed_seconds": 0.0,
		"world_clock": {
			"schema_version": 1,
			"elapsed_seconds": 0.0,
			"total_hours": 8.0,
			"day_index": 0,
			"hour": 8.0,
			"game_day": 1,
		},
		"loadout_lock": lock,
		"player_state": player_state,
		"world_state": {},
		"created_unix": now,
		"updated_unix": now,
	}
	if not save_world(world):
		return {}
	active_world = world.duplicate(true)
	return active_world.duplicate(true)


func load_world(world_id: String) -> Dictionary:
	var normalized_id := _normalize_world_id(world_id)
	if normalized_id.is_empty():
		return {}
	var path := _world_path(normalized_id)
	if not FileAccess.file_exists(path):
		return {}
	var world := _read_json(path)
	if world.is_empty() or str(world.get("world_id", "")) != normalized_id:
		return {}
	var version := int(world.get("save_version", 0))
	if version <= 0 or version > SAVE_VERSION:
		return {}
	if str(world.get("display_name", "")).strip_edges().is_empty() \
			or str(world.get("map_id", "")).strip_edges().is_empty():
		return {}
	world["max_players"] = 1
	world["death_drop_mode"] = "save"
	return world


func select_world(world_id: String) -> Dictionary:
	var world := load_world(world_id)
	if not world.is_empty():
		active_world = world.duplicate(true)
	return world.duplicate(true)


func save_world(world: Dictionary) -> bool:
	var world_id := _normalize_world_id(str(world.get("world_id", "")))
	if world_id.is_empty():
		return false
	var copy: Dictionary = json_safe(world.duplicate(true))
	copy["save_version"] = SAVE_VERSION
	copy["world_id"] = world_id
	# The first character and starter loadout belong to the world identity. A
	# runtime state save may update inventory and ammo, but never this lock.
	var existing := load_world(world_id)
	if not existing.is_empty():
		copy["loadout_lock"] = get_loadout_lock(existing)
	copy["updated_unix"] = Time.get_unix_time_from_system()
	var absolute_root := ProjectSettings.globalize_path(world_root)
	if not DirAccess.dir_exists_absolute(absolute_root):
		if DirAccess.make_dir_recursive_absolute(absolute_root) != OK:
			return false
	var folder := world_root.path_join(world_id)
	var absolute_folder := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(absolute_folder):
		if DirAccess.make_dir_recursive_absolute(absolute_folder) != OK:
			return false
	var saved := _write_json_atomic(_world_path(world_id), copy)
	if saved:
		active_world = copy.duplicate(true)
	return saved


func delete_world(world_id: String) -> bool:
	var normalized_id := _normalize_world_id(world_id)
	if normalized_id.is_empty():
		return false
	var folder := world_root.path_join(normalized_id)
	var absolute_folder := ProjectSettings.globalize_path(folder)
	if not DirAccess.dir_exists_absolute(absolute_folder) or not _remove_directory_recursive(absolute_folder):
		return false
	if str(active_world.get("world_id", "")) == normalized_id:
		active_world.clear()
	return true


func get_loadout_lock(world: Dictionary) -> Dictionary:
	var value: Variant = world.get("loadout_lock", {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func json_safe(value: Variant) -> Variant:
	if value is Vector3:
		var vector := value as Vector3
		return [vector.x, vector.y, vector.z]
	if value is Vector2:
		var vector := value as Vector2
		return [vector.x, vector.y]
	if value is Color:
		var color := value as Color
		return [color.r, color.g, color.b, color.a]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			result[str(key)] = json_safe((value as Dictionary)[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(json_safe(item))
		return result
	return value


func _normalize_loadout(selection: Dictionary) -> Dictionary:
	return {
		"hero_id": str(selection.get("hero_id", "farmer")),
		"primary_weapon_ids": (selection.get("primary_weapon_ids", []) as Array).duplicate(true) \
			if selection.get("primary_weapon_ids", []) is Array else [],
		"special_tool_ids": (selection.get("special_tool_ids", []) as Array).duplicate(true) \
			if selection.get("special_tool_ids", []) is Array else [],
		"locked_unix": Time.get_unix_time_from_system(),
	}


func _loadout_is_valid(loadout: Dictionary) -> bool:
	var hero_id := str(loadout.get("hero_id", ""))
	var primary_value: Variant = loadout.get("primary_weapon_ids", [])
	var special_value: Variant = loadout.get("special_tool_ids", [])
	if hero_id.is_empty() or not primary_value is Array or not special_value is Array:
		return false
	var primary := primary_value as Array
	var special := special_value as Array
	if primary.size() != 3 or special.size() != 2:
		return false
	var unique_primary: Dictionary = {}
	var hero_definitions := _read_json_dictionary("res://data/hero_definitions.json")
	var known_heroes: Dictionary = {}
	for hero_value: Variant in hero_definitions.get("heroes", []):
		if hero_value is Dictionary:
			known_heroes[str((hero_value as Dictionary).get("id", ""))] = true
	if not known_heroes.has(hero_id):
		return false
	var weapon_definitions := _read_json_dictionary("res://data/primary_weapon_definitions.json")
	var known_primary: Dictionary = {}
	for weapon_value: Variant in weapon_definitions.get("weapons", []):
		if weapon_value is Dictionary and bool((weapon_value as Dictionary).get("loadout_selectable", true)):
			known_primary[str((weapon_value as Dictionary).get("id", ""))] = true
	for item: Variant in primary:
		var item_id := str(item).strip_edges()
		if item_id.is_empty() or unique_primary.has(item_id) or not known_primary.has(item_id):
			return false
		unique_primary[item_id] = true
	var special_mapping := _read_json_dictionary("res://data/hero_special_tools.json")
	var hero_mapping_value: Variant = special_mapping.get("heroes", {})
	var allowed_special: Array = (hero_mapping_value as Dictionary).get(hero_id, []) \
		if hero_mapping_value is Dictionary else []
	var unique_special: Dictionary = {}
	for item: Variant in special:
		var item_id := str(item).strip_edges()
		if item_id.is_empty() or unique_special.has(item_id) or not allowed_special.has(item_id):
			return false
		unique_special[item_id] = true
	return true


func _read_json_dictionary(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value: Variant = JSON.parse_string(file.get_as_text())
	return value as Dictionary if value is Dictionary else {}


func _normalize_world_id(world_id: String) -> String:
	var normalized := world_id.strip_edges()
	if normalized.is_empty() or normalized in [".", ".."] \
			or normalized.contains("/") or normalized.contains("\\"):
		return ""
	return normalized


func _world_path(world_id: String) -> String:
	return world_root.path_join(world_id).path_join("world.json")


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.flush()
	file.close()
	return DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path), ProjectSettings.globalize_path(path)
	) == OK


func _remove_directory_recursive(path: String) -> bool:
	var directory := DirAccess.open(path)
	if directory == null:
		return false
	directory.list_dir_begin()
	var entry := directory.get_next()
	var success := true
	while not entry.is_empty():
		if not entry.begins_with("."):
			var entry_path := path.path_join(entry)
			if directory.current_is_dir():
				success = _remove_directory_recursive(entry_path)
			else:
				success = DirAccess.remove_absolute(entry_path) == OK
			if not success:
				break
		entry = directory.get_next()
	directory.list_dir_end()
	return success and DirAccess.remove_absolute(path) == OK
