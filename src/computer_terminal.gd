extends StaticBody3D
class_name ComputerTerminal

signal interaction_requested(player: GamePlayer)
signal state_changed(state: Dictionary)

const USER_LOCK_TIMEOUT_MSEC := 30000
const GRID_COLUMNS := 13
const GRID_ROWS := 6

@export_enum("laptop", "desktop") var computer_kind := "laptop"
@export_enum("OS08", "OS26") var os_id := "OS08"
@export var display_name := "笔记本电脑"
@export var interaction_point_path := NodePath("InteractionPoint")

var powered_on := false
var active_user_peer_id := 0
var active_user_last_activity_msec := 0
var state_revision := 1
var installed_app_ids: Array[String] = []
var desktop_layout: Dictionary = {}
var app_data: Dictionary = {}


func _ready() -> void:
	add_to_group("computer_terminals")
	_ensure_default_state()


func _ensure_default_state() -> void:
	if installed_app_ids.is_empty():
		installed_app_ids = ChocolateOSCatalog.get_default_installed_app_ids(os_id)
	desktop_layout = ChocolateOSCatalog.normalize_layout(desktop_layout, installed_app_ids, os_id)


func get_computer_id() -> String:
	var id := str(get_meta("network_device_id", ""))
	if id.is_empty():
		id = str(get_meta("network_map_facility_id", ""))
	if id.is_empty() and is_inside_tree():
		id = str(get_path())
	return id


func can_player_interact(player: GamePlayer) -> bool:
	return is_instance_valid(player)


func try_acquire_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0:
		return false
	refresh_user_lock()
	if active_user_peer_id != 0 and active_user_peer_id != peer_id:
		return false
	active_user_peer_id = peer_id
	active_user_last_activity_msec = Time.get_ticks_msec()
	powered_on = true
	return true


func touch_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or active_user_peer_id != peer_id:
		return false
	active_user_last_activity_msec = Time.get_ticks_msec()
	return true


func release_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or active_user_peer_id != peer_id:
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	return true


func force_release_user(peer_id := 0) -> bool:
	if GameAuthority.is_client_proxy():
		return false
	if active_user_peer_id == 0 or (peer_id > 0 and active_user_peer_id != peer_id):
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	return true


func refresh_user_lock() -> bool:
	if GameAuthority.is_client_proxy() or active_user_peer_id == 0:
		return false
	if Time.get_ticks_msec() - active_user_last_activity_msec <= USER_LOCK_TIMEOUT_MSEC:
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	return true


func is_in_use_by_other(peer_id: int) -> bool:
	refresh_user_lock()
	return active_user_peer_id != 0 and active_user_peer_id != peer_id


func install_app(app_id: String) -> Dictionary:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null:
		return {"ok": false, "reason": "unknown_app"}
	if manifest.system_app:
		return {"ok": false, "reason": "system_app"}
	if not manifest.supports_os(os_id):
		return {"ok": false, "reason": "incompatible_os"}
	if installed_app_ids.has(app_id):
		return {"ok": false, "reason": "already_installed"}
	for dependency: String in manifest.dependencies:
		if not installed_app_ids.has(dependency):
			return {"ok": false, "reason": "missing_dependency", "dependency": dependency}
	installed_app_ids.append(app_id)
	var cell := ChocolateOSCatalog.get_first_free_grid_cell(desktop_layout, GRID_COLUMNS, GRID_ROWS)
	desktop_layout[app_id] = [cell.x, cell.y]
	state_revision += 1
	return {"ok": true}


func uninstall_app(app_id: String) -> Dictionary:
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null or manifest.system_app or not manifest.removable:
		return {"ok": false, "reason": "app_not_removable"}
	if not installed_app_ids.has(app_id):
		return {"ok": false, "reason": "not_installed"}
	for other_id: String in installed_app_ids:
		var other := ChocolateOSCatalog.get_manifest(other_id)
		if other != null and other.dependencies.has(app_id):
			return {"ok": false, "reason": "required_by_app", "dependent_app": other_id}
	installed_app_ids.erase(app_id)
	desktop_layout.erase(app_id)
	app_data.erase(app_id)
	state_revision += 1
	return {"ok": true}


func move_app(app_id: String, requested_cell: Vector2i) -> Dictionary:
	if not installed_app_ids.has(app_id):
		return {"ok": false, "reason": "not_installed"}
	var target := Vector2i(
		clampi(requested_cell.x, 0, GRID_COLUMNS - 1),
		clampi(requested_cell.y, 0, GRID_ROWS - 1)
	)
	var previous := ChocolateOSCatalog._as_grid_cell(desktop_layout.get(app_id, [0, 0]))
	var occupying_app := ""
	for other_id: String in installed_app_ids:
		if other_id != app_id and ChocolateOSCatalog._as_grid_cell(desktop_layout.get(other_id, [-1, -1])) == target:
			occupying_app = other_id
			break
	desktop_layout[app_id] = [target.x, target.y]
	if not occupying_app.is_empty():
		desktop_layout[occupying_app] = [previous.x, previous.y]
	state_revision += 1
	return {"ok": true}


func write_app_data(app_id: String, payload: Dictionary, expected_revision: int) -> Dictionary:
	if not installed_app_ids.has(app_id):
		return {"ok": false, "reason": "not_installed"}
	var manifest := ChocolateOSCatalog.get_manifest(app_id)
	if manifest == null or not manifest.permissions.has("app_storage.write"):
		return {"ok": false, "reason": "permission_denied"}
	var previous_value: Variant = app_data.get(app_id, {})
	var previous: Dictionary = previous_value as Dictionary if previous_value is Dictionary else {}
	var revision := int(previous.get("revision", 0))
	if expected_revision != revision:
		return {"ok": false, "reason": "revision_conflict", "app_state": previous.duplicate(true)}
	app_data[app_id] = {
		"revision": revision + 1,
		"data_version": manifest.data_version,
		"payload": payload.duplicate(true),
	}
	state_revision += 1
	return {"ok": true, "app_state": (app_data[app_id] as Dictionary).duplicate(true)}


func get_computer_state() -> Dictionary:
	_ensure_default_state()
	var saved_app_data := app_data.duplicate(true)
	# Embedded Lab research is team-shared.  Older saves may still contain its
	# former per-computer payload; never serialize that legacy copy again.
	saved_app_data.erase("embedded_lab")
	return {
		"computer_id": get_computer_id(),
		"station_path": str(get_path()) if is_inside_tree() else "",
		"station_position": global_position,
		"computer_kind": computer_kind,
		"os_id": os_id,
		"powered_on": powered_on,
		"active_user_peer_id": active_user_peer_id,
		"state_revision": state_revision,
		"installed_app_ids": installed_app_ids.duplicate(),
		"desktop_layout": desktop_layout.duplicate(true),
		"app_data": saved_app_data,
	}


func get_computer_summary_state() -> Dictionary:
	var state := get_computer_state()
	var data_revisions := {}
	for app_id: Variant in app_data.keys():
		if str(app_id) == "embedded_lab":
			continue
		var value: Variant = app_data[app_id]
		if value is Dictionary:
			data_revisions[str(app_id)] = int((value as Dictionary).get("revision", 0))
	state.erase("app_data")
	state["app_data_revisions"] = data_revisions
	return state


func apply_computer_state(state: Dictionary) -> void:
	if state.has("os_id"):
		os_id = str(state.get("os_id", os_id))
	powered_on = bool(state.get("powered_on", powered_on))
	active_user_peer_id = int(state.get("active_user_peer_id", active_user_peer_id))
	active_user_last_activity_msec = Time.get_ticks_msec() if active_user_peer_id != 0 else 0
	state_revision = maxi(1, int(state.get("state_revision", state_revision)))
	var installed_value: Variant = state.get("installed_app_ids", installed_app_ids)
	if installed_value is Array:
		installed_app_ids.clear()
		for value: Variant in installed_value:
			var app_id := str(value)
			var manifest := ChocolateOSCatalog.get_manifest(app_id)
			if manifest != null and manifest.supports_os(os_id) and not installed_app_ids.has(app_id):
				installed_app_ids.append(app_id)
	for default_id: String in ChocolateOSCatalog.get_default_installed_app_ids(os_id):
		var default_manifest := ChocolateOSCatalog.get_manifest(default_id)
		if default_manifest != null and default_manifest.system_app and not installed_app_ids.has(default_id):
			installed_app_ids.append(default_id)
	desktop_layout = ChocolateOSCatalog.normalize_layout(state.get("desktop_layout", desktop_layout), installed_app_ids, os_id)
	var app_data_value: Variant = state.get("app_data", null)
	if app_data_value is Dictionary:
		app_data = (app_data_value as Dictionary).duplicate(true)
	# Do not restore the old per-computer Embedded Lab payload.  The authority
	# restores the team-level state separately from the world save.
	app_data.erase("embedded_lab")
	state_changed.emit(get_computer_state())


func get_interaction_position() -> Vector3:
	var interaction_point := get_node_or_null(interaction_point_path) as Node3D
	if interaction_point != null and is_instance_valid(interaction_point):
		return interaction_point.global_position
	return global_position


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "无法使用电脑"
	if is_in_use_by_other(player.authority_peer_id):
		return "其他玩家正在使用"
	return "[E] 使用 %s" % display_name


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player):
		return false
	interaction_requested.emit(player)
	return true
