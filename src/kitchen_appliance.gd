extends StaticBody3D
class_name KitchenAppliance

signal interaction_requested(player: GamePlayer)

const USER_LOCK_TIMEOUT_MSEC := 30000

@export_enum("red", "blue") var owner_team := "red"
@export var display_name := ""

var active_user_peer_id := 0
var active_user_last_activity_msec := 0


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
	return true


func force_release_user(peer_id := 0) -> bool:
	if GameAuthority.is_client_proxy():
		return false
	if active_user_peer_id == 0 or (peer_id > 0 and active_user_peer_id != peer_id):
		return false
	active_user_peer_id = 0
	active_user_last_activity_msec = 0
	return true


func is_in_use_by_other(peer_id: int) -> bool:
	_refresh_user_lock()
	return active_user_peer_id != 0 and active_user_peer_id != peer_id


func _refresh_user_lock() -> void:
	# Client proxies only mirror authoritative lock state for presentation.
	# They must never acquire, release, or expire the lock locally.
	if GameAuthority.is_client_proxy():
		return
	if active_user_peer_id != 0 and not _should_keep_user_lock() \
			and Time.get_ticks_msec() - active_user_last_activity_msec > USER_LOCK_TIMEOUT_MSEC:
		active_user_peer_id = 0
		active_user_last_activity_msec = 0


func _should_keep_user_lock() -> bool:
	return false


func get_user_lock_state() -> Dictionary:
	_refresh_user_lock()
	return {"active_user_peer_id": active_user_peer_id}


func apply_user_lock_state(state: Dictionary) -> void:
	active_user_peer_id = int(state.get("active_user_peer_id", active_user_peer_id))
	active_user_last_activity_msec = Time.get_ticks_msec() if active_user_peer_id != 0 else 0


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方厨房用具"
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用"
	var label: String = display_name if not display_name.is_empty() else str(name)
	return "[E] 使用 %s" % label


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player):
		return false
	if not try_acquire_user(player.authority_peer_id):
		return false
	interaction_requested.emit(player)
	return true
