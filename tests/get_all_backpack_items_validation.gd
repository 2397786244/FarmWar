extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var authority := get_root().get_node_or_null("GameAuthority")
	_check(authority != null, "GameAuthority autoload exists")
	if authority == null:
		_finish()
		return
	var ids: Array[String] = []
	ids.append_array(_ids_from_array_config("res://data/tool_definitions.json", "tools"))
	ids.append_array(_ids_from_array_config("res://data/equipment_definitions.json", "equipment"))
	ids.append_array(_ids_from_dictionary_config("res://data/ingredient_definitions.json", "ingredients"))
	ids.append_array(_ids_from_dictionary_config("res://data/dish_definitions.json", "dishes"))
	ids.append_array(["cargo_crate_small", "cargo_crate_medium", "cargo_crate_large"])
	_check(ids.size() == 123, "all 123 configured backpack item IDs are discovered")
	for index in range(ids.size()):
		var peer_id := 20000 + index
		authority.call("register_or_update_player", peer_id, {
			"display_name": "GetValidation_%d" % index, "team": "red",
			"primary_weapon_ids": [], "special_tool_ids": [],
		})
		var state: Dictionary = authority.get("player_states").get(peer_id, {})
		var result: Dictionary = authority.call(
			"_server_debug_get_tool", peer_id, state, "[get] %s" % ids[index]
		)
		_check(bool(result.get("ok", false)), "[get] supports %s" % ids[index])

	_finish()


func _ids_from_array_config(path: String, key: String) -> Array[String]:
	var parsed := _read_json(path)
	var result: Array[String] = []
	for value: Variant in parsed.get(key, []):
		if value is Dictionary:
			result.append(str((value as Dictionary).get("id", "")))
	return result


func _ids_from_dictionary_config(path: String, key: String) -> Array[String]:
	var parsed := _read_json(path)
	var result: Array[String] = []
	var values: Variant = parsed.get(key, {})
	if values is Dictionary:
		for id_value: Variant in (values as Dictionary).keys():
			result.append(str(id_value))
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[GetAllBackpackItemsValidation] PASS")
		quit(0)
		return
	for failure: String in failures:
		push_error("[GetAllBackpackItemsValidation] " + failure)
	quit(1)
