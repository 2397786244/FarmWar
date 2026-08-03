extends Node
class_name CooperativeWorldStorageService

const WORLD_ROOT := "user://pve_worlds"
const PROFILE_ROOT := "user://pve_player_profiles"
const SAVE_VERSION := 1
const REDPINE_MAP_ICON := "res://worlds/redpine_county/map_icon.svg"
const REDPINE_MAP_SCENE := "res://worlds/redpine_county/redpine_county.tscn"

var active_world: Dictionary = {}


func list_worlds() -> Array[Dictionary]:
	var worlds: Array[Dictionary] = []
	var directory := DirAccess.open(WORLD_ROOT)
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


func create_world(config: Dictionary) -> Dictionary:
	var world_id := "pve_%d_%06d" % [Time.get_unix_time_from_system(), randi_range(0, 999999)]
	var now := Time.get_unix_time_from_system()
	var world := {
		"save_version": SAVE_VERSION,
		"world_id": world_id,
		"display_name": str(config.get("display_name", "合作农场")),
		"map_id": str(config.get("map_id", "redpine_county")),
		"map_name": str(config.get("map_name", "Redpine County")),
		"map_icon_path": str(config.get("map_icon_path", REDPINE_MAP_ICON)),
		"map_scene_path": str(config.get("map_scene_path", REDPINE_MAP_SCENE)),
		"map_version": str(config.get("map_version", "1.0.0")),
		"map_hash": str(config.get("map_hash", "")),
		"map_source": str(config.get("map_source", "builtin")),
		"max_players": clampi(int(config.get("max_players", 4)), 1, 4),
		"death_drop_mode": _normalize_death_drop_mode(str(config.get("death_drop_mode", "save"))),
		"team_money": 0.0,
		"game_day": 1,
		"world_elapsed_seconds": 0.0,
		"host_steam_id": int(config.get("host_steam_id", 0)),
		"host_summary": {
			"display_name": str(config.get("host_display_name", "房主")),
			"current_hp": 200.0,
			"max_hp": 200.0,
			"location_label": "农场（尚未进入世界）",
			"last_position": [],
		},
		"players": {},
		"created_unix": now,
		"updated_unix": now,
	}
	if save_world(world):
		active_world = world.duplicate(true)
		return active_world.duplicate(true)
	return {}


func load_world(world_id: String) -> Dictionary:
	var path := _world_path(world_id)
	if not FileAccess.file_exists(path):
		return {}
	var world := _read_json(path)
	if world.is_empty() or str(world.get("world_id", "")) != world_id:
		return {}
	world["death_drop_mode"] = _normalize_death_drop_mode(str(world.get("death_drop_mode", "save")))
	_apply_map_defaults(world)
	return world


func select_world(world_id: String) -> Dictionary:
	var world := load_world(world_id)
	if not world.is_empty():
		active_world = world.duplicate(true)
	return active_world.duplicate(true)


func save_world(world: Dictionary) -> bool:
	var world_id := str(world.get("world_id", ""))
	if world_id.is_empty():
		return false
	var copy: Dictionary = _json_safe(world.duplicate(true))
	copy["save_version"] = SAVE_VERSION
	copy["updated_unix"] = Time.get_unix_time_from_system()
	if not DirAccess.dir_exists_absolute(WORLD_ROOT):
		DirAccess.make_dir_recursive_absolute(WORLD_ROOT)
	var folder := "%s/%s" % [WORLD_ROOT, world_id]
	if not DirAccess.dir_exists_absolute(folder):
		DirAccess.make_dir_recursive_absolute(folder)
	return _write_json(_world_path(world_id), copy)


func has_local_profile(world_id: String, steam_id: int) -> bool:
	return not get_local_profile(world_id, steam_id).is_empty()


func get_local_profile(world_id: String, steam_id: int) -> Dictionary:
	if world_id.is_empty() or steam_id <= 0:
		return {}
	return _read_json(_profile_path(world_id, steam_id))


func save_local_profile(world_id: String, steam_id: int, selection: Dictionary) -> bool:
	if world_id.is_empty() or steam_id <= 0:
		return false
	# First-choice-only: a local UI must not be able to overwrite a character
	# already committed for this cooperative world.
	if has_local_profile(world_id, steam_id):
		return true
	if not DirAccess.dir_exists_absolute(PROFILE_ROOT):
		DirAccess.make_dir_recursive_absolute(PROFILE_ROOT)
	var profile := {
		"world_id": world_id,
		"steam_id": steam_id,
		"hero_id": str(selection.get("hero_id", "")),
		"primary_weapon_ids": selection.get("primary_weapon_ids", []).duplicate(),
		"special_tool_ids": selection.get("special_tool_ids", []).duplicate(),
		"created_unix": Time.get_unix_time_from_system(),
	}
	return _write_json(_profile_path(world_id, steam_id), profile)


func save_host_initial_profile(world_id: String, steam_id: int, selection: Dictionary) -> bool:
	var world := load_world(world_id)
	if world.is_empty() or steam_id <= 0:
		return false
	var profile := {
		"steam_id": steam_id,
		"hero_id": str(selection.get("hero_id", "")),
		"primary_weapon_ids": selection.get("primary_weapon_ids", []).duplicate(),
		"special_tool_ids": selection.get("special_tool_ids", []).duplicate(),
		"backpack": [],
		"current_hp": 200.0,
		"max_hp": 200.0,
		"last_position": [],
		"location_label": "农场（尚未进入世界）",
	}
	var players: Dictionary = world.get("players", {})
	players[str(steam_id)] = profile
	world["players"] = players
	var loadout_locks: Dictionary = world.get("loadout_locks", {})
	if not loadout_locks.has(str(steam_id)):
		loadout_locks[str(steam_id)] = _loadout_lock_from_selection(selection, steam_id)
	world["loadout_locks"] = loadout_locks
	world["host_steam_id"] = steam_id
	var host_summary: Dictionary = world.get("host_summary", {})
	host_summary["hero_id"] = profile["hero_id"]
	host_summary["current_hp"] = profile["current_hp"]
	host_summary["max_hp"] = profile["max_hp"]
	host_summary["location_label"] = profile["location_label"]
	world["host_summary"] = host_summary
	var saved := save_world(world)
	if saved:
		active_world = world.duplicate(true)
	return saved


func get_host_loadout_lock(world_id: String, steam_id: int) -> Dictionary:
	if world_id.is_empty() or steam_id <= 0:
		return {}
	var world := load_world(world_id)
	if world.is_empty():
		return {}
	var locks: Variant = world.get("loadout_locks", {})
	if not locks is Dictionary:
		return {}
	var lock: Variant = (locks as Dictionary).get(str(steam_id), {})
	return (lock as Dictionary).duplicate(true) if lock is Dictionary else {}


func save_host_loadout_lock(world_id: String, steam_id: int, selection: Dictionary) -> Dictionary:
	if world_id.is_empty() or steam_id <= 0:
		return {}
	var world := load_world(world_id)
	if world.is_empty():
		return {}
	var locks: Dictionary = world.get("loadout_locks", {})
	var existing: Variant = locks.get(str(steam_id), {})
	if existing is Dictionary and not (existing as Dictionary).is_empty():
		return (existing as Dictionary).duplicate(true)
	var lock := _loadout_lock_from_selection(selection, steam_id)
	locks[str(steam_id)] = lock
	world["loadout_locks"] = locks
	if not save_world(world):
		return {}
	active_world = world.duplicate(true)
	return lock.duplicate(true)


func _loadout_lock_from_selection(selection: Dictionary, steam_id: int) -> Dictionary:
	return {
		"steam_id": steam_id,
		"hero_id": str(selection.get("hero_id", "farmer")),
		"primary_weapon_ids": selection.get("primary_weapon_ids", []).duplicate(true),
		"special_tool_ids": selection.get("special_tool_ids", []).duplicate(true),
		"locked_unix": Time.get_unix_time_from_system(),
	}


func save_host_player_state(world_id: String, peer_id: int, state: Dictionary) -> bool:
	var world := load_world(world_id)
	if world.is_empty() or peer_id <= 0:
		return false
	var players: Dictionary = world.get("players", {})
	players[str(peer_id)] = state.duplicate(true)
	world["players"] = players
	return save_world(world)


func _world_path(world_id: String) -> String:
	return "%s/%s/world.json" % [WORLD_ROOT, world_id]


func _profile_path(world_id: String, steam_id: int) -> String:
	return "%s/%s_%d.json" % [PROFILE_ROOT, world_id, steam_id]


func _normalize_death_drop_mode(mode: String) -> String:
	var normalized := mode.strip_edges().to_lower()
	if normalized in ["all", "random", "save"]:
		return normalized
	return "save"


func _map_icon_for_id(map_id: String) -> String:
	var definition := GameMapRegistry.get_map_by_id(map_id)
	if not definition.is_empty():
		return str(definition.get("icon_path", ""))
	match map_id:
		"creston_town":
			return "res://worlds/creston_town/map_icon.svg"
		_:
			return REDPINE_MAP_ICON


func _map_scene_for_id(map_id: String) -> String:
	var definition := GameMapRegistry.get_map_by_id(map_id)
	if not definition.is_empty():
		return str(definition.get("scene_path", ""))
	match map_id:
		"creston_town":
			return "res://worlds/creston_town/creston_town.tscn"
		_:
			return REDPINE_MAP_SCENE


func _apply_map_defaults(world: Dictionary) -> void:
	var map_id := str(world.get("map_id", ""))
	var definition := GameMapRegistry.get_map_by_id(map_id)
	if definition.is_empty():
		definition = GameMapRegistry.get_map_by_package_name(map_id)
	if definition.is_empty():
		if str(world.get("map_icon_path", "")).is_empty():
			world["map_icon_path"] = _map_icon_for_id(map_id)
		if str(world.get("map_scene_path", "")).is_empty():
			world["map_scene_path"] = _map_scene_for_id(map_id)
		return
	if str(world.get("map_name", "")).is_empty():
		world["map_name"] = str(definition.get("display_name", map_id))
	if str(world.get("map_icon_path", "")).is_empty():
		world["map_icon_path"] = str(definition.get("icon_path", ""))
	if str(world.get("map_scene_path", "")).is_empty():
		world["map_scene_path"] = str(definition.get("scene_path", ""))
	if str(world.get("map_version", "")).is_empty():
		world["map_version"] = str(definition.get("map_version", "1.0.0"))
	if str(world.get("map_hash", "")).is_empty():
		world["map_hash"] = str(definition.get("map_hash", ""))
	if str(world.get("map_source", "")).is_empty():
		world["map_source"] = str(definition.get("source", "builtin"))


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _write_json(path: String, data: Dictionary) -> bool:
	var temporary_path := path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return DirAccess.rename_absolute(temporary_path, path) == OK


func _json_safe(value: Variant) -> Variant:
	if value is Vector3:
		var vector := value as Vector3
		return [vector.x, vector.y, vector.z]
	if value is Vector2:
		var vector := value as Vector2
		return [vector.x, vector.y]
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in (value as Dictionary).keys():
			result[str(key)] = _json_safe((value as Dictionary)[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value as Array:
			result.append(_json_safe(item))
		return result
	return value
