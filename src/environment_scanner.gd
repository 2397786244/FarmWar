extends Node3D
class_name EnvironmentScanner

## Hand-held Prospector scanner. Gameplay authority only approves the use and
## cooldown; the scan itself is intentionally presentation-only for its owner.


func emit() -> Dictionary:
	var player := _find_owner_player()
	if is_instance_valid(player) and player.has_method("start_environment_scan"):
		player.call("start_environment_scan")
	return {"ok": is_instance_valid(player)}


func _find_owner_player() -> Node:
	var candidate := get_parent()
	while is_instance_valid(candidate):
		if candidate is GamePlayer:
			return candidate
		candidate = candidate.get_parent()
	return null
