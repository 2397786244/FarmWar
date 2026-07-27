extends StaticBody3D
class_name GarageUpgradeTerminal

@export_enum("red", "blue") var owner_team := "red"
var garage: TeamGarage


func can_player_interact(player: GamePlayer) -> bool:
	return is_instance_valid(player) and player.team == owner_team


func get_interaction_hint(_player: GamePlayer) -> String:
	return "[E] 升级载具"


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player) or not is_instance_valid(garage):
		return false
	var page := player.get_node_or_null("SubViewport/VehicleUpgradePage")
	if page == null or not page.has_method("open_for"):
		return false
	page.call("open_for", garage, player)
	return true
