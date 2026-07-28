extends FoodCarShop
class_name LivestockMarket

const TEAM_LOCK_TIMEOUT_MSEC := 30000

var _active_user_by_team := {"red": 0, "blue": 0}
var _last_activity_by_team := {"red": 0, "blue": 0}


func _ready() -> void:
	super._ready()
	add_to_group("livestock_markets")


func try_acquire_team_user(team: String, peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0 or not _active_user_by_team.has(team):
		return false
	_refresh_team_lock(team)
	var active_peer_id := int(_active_user_by_team.get(team, 0))
	if active_peer_id != 0 and active_peer_id != peer_id:
		return false
	_active_user_by_team[team] = peer_id
	_last_activity_by_team[team] = Time.get_ticks_msec()
	return true


func touch_team_user(team: String, peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0 or not _active_user_by_team.has(team):
		return false
	_refresh_team_lock(team)
	if int(_active_user_by_team.get(team, 0)) != peer_id:
		return false
	_last_activity_by_team[team] = Time.get_ticks_msec()
	return true


func release_team_user(team: String, peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0 or not _active_user_by_team.has(team):
		return false
	if int(_active_user_by_team.get(team, 0)) != peer_id:
		return false
	_active_user_by_team[team] = 0
	_last_activity_by_team[team] = 0
	return true


func force_release_user(peer_id: int) -> bool:
	if GameAuthority.is_client_proxy() or peer_id <= 0:
		return false
	var released := false
	for team: String in _active_user_by_team.keys():
		if int(_active_user_by_team.get(team, 0)) == peer_id:
			_active_user_by_team[team] = 0
			_last_activity_by_team[team] = 0
			released = true
	return released


func refresh_team_locks() -> void:
	if GameAuthority.is_client_proxy():
		return
	for team: String in _active_user_by_team.keys():
		_refresh_team_lock(team)


func get_team_user(team: String) -> int:
	_refresh_team_lock(team)
	return int(_active_user_by_team.get(team, 0))


func get_interaction_position() -> Vector3:
	var shop_area := find_child("ShopArea", true, false) as Area3D
	if shop_area != null:
		var collision_shape := shop_area.find_child("CollisionShape3D", true, false) as CollisionShape3D
		return collision_shape.global_position if collision_shape != null else shop_area.global_position
	return global_position


func _refresh_team_lock(team: String) -> void:
	if GameAuthority.is_client_proxy() or not _active_user_by_team.has(team):
		return
	var active_peer_id := int(_active_user_by_team.get(team, 0))
	if active_peer_id != 0 and Time.get_ticks_msec() - int(_last_activity_by_team.get(team, 0)) \
			> TEAM_LOCK_TIMEOUT_MSEC:
		_active_user_by_team[team] = 0
		_last_activity_by_team[team] = 0
