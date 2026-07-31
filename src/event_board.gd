extends Node
class_name EventBoardService

signal global_events_changed(events: Array[Dictionary])
signal team_tasks_changed(team: String, tasks: Array[Dictionary])

const MAX_GLOBAL_EVENTS := 6
const MAX_TEAM_TASKS := 6
const TEAM_ALL := "all"
const VALID_TEAMS := ["red", "blue"]

var global_events: Array[Dictionary] = []
var team_tasks := {"red": [], "blue": []}
var next_event_id := 1
var next_task_id := 1
var emitters_enabled := true


func set_emitters_enabled(enabled: bool) -> void:
	emitters_enabled = enabled
	if not emitters_enabled:
		reset()


func are_emitters_enabled() -> bool:
	return emitters_enabled


func reset() -> void:
	global_events.clear()
	team_tasks = {"red": [], "blue": []}
	next_event_id = 1
	next_task_id = 1
	_emit_all_changed()


func add_global_event(title: String, description := "", event_type := "info") -> Dictionary:
	if not emitters_enabled or not _can_mutate():
		return {}
	if title.is_empty():
		return {}
	var event := {
		"event_id": next_event_id,
		"title": title,
		"description": description,
		"event_type": event_type,
		"created_msec": Time.get_ticks_msec(),
	}
	next_event_id += 1
	global_events.push_front(event)
	if global_events.size() > MAX_GLOBAL_EVENTS:
		global_events.resize(MAX_GLOBAL_EVENTS)
	global_events_changed.emit(global_events.duplicate(true))
	_broadcast_state()
	return event.duplicate(true)


func remove_global_event(event_id: int) -> bool:
	if not emitters_enabled or not _can_mutate() or event_id <= 0:
		return false
	for index in range(global_events.size()):
		if int(global_events[index].get("event_id", 0)) != event_id:
			continue
		global_events.remove_at(index)
		global_events_changed.emit(global_events.duplicate(true))
		_broadcast_state()
		return true
	return false


func add_team_task(target_team: String, task: Dictionary) -> Array[Dictionary]:
	if not emitters_enabled or not _can_mutate() or not _is_valid_task(task):
		return []
	var target_teams := _resolve_target_teams(target_team)
	if target_teams.is_empty():
		return []
	var created: Array[Dictionary] = []
	for team: String in target_teams:
		var entry := task.duplicate(true)
		entry["task_id"] = next_task_id
		entry["team"] = team
		entry["created_msec"] = Time.get_ticks_msec()
		next_task_id += 1
		var list: Array = team_tasks.get(team, [])
		list.push_front(entry)
		if list.size() > MAX_TEAM_TASKS:
			list.resize(MAX_TEAM_TASKS)
		team_tasks[team] = list
		team_tasks_changed.emit(team, _copy_task_list(list))
		created.append(entry.duplicate(true))
	_broadcast_state()
	return created


func get_global_events() -> Array[Dictionary]:
	if not emitters_enabled:
		return []
	return _copy_event_list(global_events)


func get_team_tasks(team: String) -> Array[Dictionary]:
	if not emitters_enabled:
		return []
	return _copy_task_list(team_tasks.get(team, []))


func update_team_task(team: String, task_id: int, changes: Dictionary) -> Dictionary:
	if not emitters_enabled or not _can_mutate() or team not in VALID_TEAMS or task_id <= 0:
		return {}
	var list: Array = team_tasks.get(team, [])
	for index in range(list.size()):
		var task: Dictionary = list[index] if list[index] is Dictionary else {}
		if int(task.get("task_id", 0)) != task_id:
			continue
		task.merge(changes.duplicate(true), true)
		list[index] = task
		team_tasks[team] = list
		team_tasks_changed.emit(team, _copy_task_list(list))
		_broadcast_state()
		return task.duplicate(true)
	return {}


func get_latest_recipe_order(team: String) -> Dictionary:
	for task: Dictionary in get_team_tasks(team):
		if str(task.get("task_type", "")) == "recipe_order" and bool(task.get("active", true)):
			return task
	return {}


func get_state_for_team(team: String) -> Dictionary:
	return {
		"global_events": get_global_events(),
		"team": team,
		"team_tasks": get_team_tasks(team),
	}


func apply_state(state: Dictionary) -> void:
	if not emitters_enabled:
		return
	var events_value: Variant = state.get("global_events", [])
	if events_value is Array:
		global_events = _sanitize_dictionary_array(events_value as Array)
		if global_events.size() > MAX_GLOBAL_EVENTS:
			global_events.resize(MAX_GLOBAL_EVENTS)
		global_events_changed.emit(global_events.duplicate(true))
	var team := str(state.get("team", ""))
	var tasks_value: Variant = state.get("team_tasks", [])
	if team in VALID_TEAMS and tasks_value is Array:
		var tasks := _sanitize_dictionary_array(tasks_value as Array)
		if tasks.size() > MAX_TEAM_TASKS:
			tasks.resize(MAX_TEAM_TASKS)
		team_tasks[team] = tasks
		team_tasks_changed.emit(team, _copy_task_list(tasks))


func _broadcast_state() -> void:
	if GameAuthority.is_server_authority():
		GameAuthority.reliable_world_event_ready.emit({
			"type": "event_board_state",
			"tick": GameAuthority.server_tick,
		})


func _can_mutate() -> bool:
	if GameAuthority.is_client_proxy():
		push_warning("Client proxy cannot create events or team tasks.")
		return false
	return true


func _is_valid_task(task: Dictionary) -> bool:
	return not str(task.get("title", "")).is_empty() and not str(task.get("task_type", "")).is_empty()


func _resolve_target_teams(target_team: String) -> Array[String]:
	if target_team == TEAM_ALL:
		var all_teams: Array[String] = []
		for team_value: Variant in VALID_TEAMS:
			all_teams.append(str(team_value))
		return all_teams
	if target_team in VALID_TEAMS:
		return [target_team]
	return []


func _emit_all_changed() -> void:
	global_events_changed.emit(get_global_events())
	for team: String in VALID_TEAMS:
		team_tasks_changed.emit(team, get_team_tasks(team))


func _copy_event_list(events: Array) -> Array[Dictionary]:
	return _sanitize_dictionary_array(events)


func _copy_task_list(tasks: Array) -> Array[Dictionary]:
	return _sanitize_dictionary_array(tasks)


func _sanitize_dictionary_array(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in values:
		if value is Dictionary:
			result.append((value as Dictionary).duplicate(true))
	return result
