extends StaticBody3D
class_name IndustrialWorkbench

## Independent industrial-workbench base.  It deliberately does not inherit
## KitchenAppliance: industrial jobs have their own recipe, output and save
## contract while reusing only the same lock semantics at the API level.

const USER_LOCK_TIMEOUT_MSEC := 30000
const STATE_SYNC_INTERVAL_MSEC := 250

@export_enum("red", "blue") var owner_team := "red"
@export var workbench_id := ""
@export var display_name := ""

var active_user_peer_id := 0
var active_user_last_activity_msec := 0
var recipe_id := ""
var processing := false
var complete := false
var processing_started_msec := 0
var duration_seconds := 0.0
var completed_msec := 0
var output_result: Dictionary = {}
var revision := 0

var _last_state_emit_msec := 0
var _client_progress := 0.0


func _ready() -> void:
	if workbench_id.is_empty():
		workbench_id = str(get_meta("workbench_id", ""))
	if display_name.is_empty():
		display_name = str(get_meta("display_name", name))
	add_to_group("industrial_workbenches")
	var group_name := get_group_name_for_workbench(workbench_id)
	if not group_name.is_empty():
		add_to_group(group_name)
	set_process(true)


func _process(_delta: float) -> void:
	if GameAuthority.is_client_proxy():
		return
	if not processing:
		return
	var now_msec := Time.get_ticks_msec()
	if get_progress(now_msec) >= 1.0:
		processing = false
		complete = true
		completed_msec = now_msec
		_client_progress = 1.0
		# A completed output is public to the owning team.  The lock must be
		# released after the processing flag is cleared because release_user
		# intentionally refuses to release a processing job.
		if active_user_peer_id != 0:
			var previous_peer_id := active_user_peer_id
			force_release_user(previous_peer_id)
		revision += 1
		_emit_authoritative_state()
		return
	if now_msec - _last_state_emit_msec >= STATE_SYNC_INTERVAL_MSEC:
		_last_state_emit_msec = now_msec
		_emit_authoritative_state()


func get_group_name_for_workbench(id: String) -> String:
	match id:
		"industrial_furnace":
			return "industrial_furnaces"
		"comprehensive_material_processing_station":
			return "comprehensive_material_processing_stations"
		"electronic_assembly_station":
			return "electronic_assembly_stations"
		"wood_processing_table":
			return "wood_processing_tables"
	return ""


func get_workbench_id() -> String:
	return workbench_id


func get_workbench_display_name() -> String:
	return display_name if not display_name.is_empty() else str(name)


func get_interaction_position() -> Vector3:
	var marker := get_node_or_null("InteractionPoint") as Node3D
	return marker.global_position if marker != null else global_position


func can_player_interact(player: GamePlayer) -> bool:
	return is_instance_valid(player) and player.team == owner_team


func try_acquire_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0:
		return false
	_refresh_user_lock()
	if active_user_peer_id != 0 and active_user_peer_id != peer_id:
		return false
	active_user_peer_id = peer_id
	active_user_last_activity_msec = Time.get_ticks_msec()
	return true


func release_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy():
		return false
	_refresh_user_lock()
	if active_user_peer_id != peer_id:
		return false
	if _should_keep_user_lock():
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	revision += 1
	return true


func force_release_user(peer_id := 0) -> bool:
	if GameAuthority.is_client_proxy():
		return false
	if active_user_peer_id == 0 or (peer_id > 0 and active_user_peer_id != peer_id):
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	revision += 1
	return true


func is_in_use_by_other(peer_id: int) -> bool:
	_refresh_user_lock()
	return active_user_peer_id != 0 and active_user_peer_id != peer_id


func refresh_user_lock() -> void:
	_refresh_user_lock()


func _refresh_user_lock() -> void:
	if GameAuthority.is_client_proxy():
		return
	if active_user_peer_id != 0 and not _should_keep_user_lock() \
			and Time.get_ticks_msec() - active_user_last_activity_msec > USER_LOCK_TIMEOUT_MSEC:
		active_user_peer_id = 0
		active_user_last_activity_msec = 0
		revision += 1


func _should_keep_user_lock() -> bool:
	return processing


func get_user_lock_state() -> Dictionary:
	_refresh_user_lock()
	return {"active_user_peer_id": active_user_peer_id}


func apply_user_lock_state(state: Dictionary) -> void:
	active_user_peer_id = int(state.get("active_user_peer_id", active_user_peer_id))
	active_user_last_activity_msec = Time.get_ticks_msec() if active_user_peer_id != 0 else 0


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方工业工作台"
	if complete:
		return "[E] 领取成品"
	if processing:
		return "加工中"
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用%s" % get_workbench_display_name()
	return "[E] 使用%s" % get_workbench_display_name()


func can_start_recipe(next_recipe_id: String) -> bool:
	return recipe_id.is_empty() and not processing and not complete \
		and not IndustrialRecipeCatalog.get_recipe(next_recipe_id).is_empty() \
		and str(IndustrialRecipeCatalog.get_recipe(next_recipe_id).get("workbench_id", "")) == workbench_id


func start_processing(next_recipe_id: String, next_output: Dictionary, next_duration_seconds: float) -> bool:
	if not can_start_recipe(next_recipe_id) or next_output.is_empty() or next_duration_seconds <= 0.0:
		return false
	recipe_id = next_recipe_id
	processing = true
	complete = false
	processing_started_msec = Time.get_ticks_msec()
	duration_seconds = clampf(next_duration_seconds, 8.0, 90.0)
	completed_msec = 0
	output_result = next_output.duplicate(true)
	_client_progress = 0.0
	_last_state_emit_msec = 0
	revision += 1
	return true


func get_progress(now_msec := Time.get_ticks_msec()) -> float:
	if complete:
		return 1.0
	if not processing or duration_seconds <= 0.0:
		return 0.0
	if GameAuthority.is_client_proxy() and processing_started_msec <= 0:
		return _client_progress
	return clampf(float(now_msec - processing_started_msec) / (duration_seconds * 1000.0), 0.0, 1.0)


func can_take_output() -> bool:
	return complete and not output_result.is_empty()


func get_output_result() -> Dictionary:
	return output_result.duplicate(true)


func take_output() -> Dictionary:
	if not can_take_output():
		return {}
	var result := output_result.duplicate(true)
	clear_workbench()
	return result


func clear_workbench() -> void:
	recipe_id = ""
	processing = false
	complete = false
	processing_started_msec = 0
	duration_seconds = 0.0
	completed_msec = 0
	output_result.clear()
	_client_progress = 0.0
	revision += 1


func get_workbench_state() -> Dictionary:
	var state := {
		"station_path": str(get_path()),
		"station_position": global_position,
		"workbench_id": workbench_id,
		"display_name": get_workbench_display_name(),
		"recipe_id": recipe_id,
		"processing": processing,
		"complete": complete,
		"progress": get_progress(),
		"duration_seconds": duration_seconds,
		"output_result": output_result.duplicate(true),
		"completed_msec": completed_msec,
		"revision": revision,
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_workbench_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	workbench_id = str(state.get("workbench_id", workbench_id))
	display_name = str(state.get("display_name", display_name))
	recipe_id = str(state.get("recipe_id", ""))
	processing = bool(state.get("processing", false))
	complete = bool(state.get("complete", false))
	duration_seconds = maxf(0.0, float(state.get("duration_seconds", 0.0)))
	var progress := clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	_client_progress = progress
	if processing and duration_seconds > 0.0:
		processing_started_msec = Time.get_ticks_msec() - int(progress * duration_seconds * 1000.0)
	else:
		processing_started_msec = 0
	completed_msec = int(state.get("completed_msec", 0))
	var output_value: Variant = state.get("output_result", {})
	output_result = output_value.duplicate(true) if output_value is Dictionary else {}
	revision = int(state.get("revision", revision))


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player) or complete or processing:
		return false
	var page := player.get_node_or_null("SubViewport/IndustrialWorkbenchPage")
	if page == null or not page.has_method("open_for"):
		return false
	page.call("open_for", self, player)
	return true


func _emit_authoritative_state() -> void:
	GameAuthority.reliable_world_event_ready.emit({
		"type": "industrial_workbench_state",
		"station_state": get_workbench_state(),
		"tick": GameAuthority.server_tick,
	})
