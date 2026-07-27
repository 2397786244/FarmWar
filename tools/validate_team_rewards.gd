extends Node

var _failed := false
var _reward_events: Array[Dictionary] = []


func _ready() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var original_mode := GameAuthority.mode
	var original_storage := GlobalVar.team_storage.duplicate(true)
	var original_players := GameAuthority.player_states.duplicate(true)
	GameAuthority.mode = GameAuthority.MODE_LOCAL
	GlobalVar.team_storage = {
		"red": {"money": 100.0, "tomato": 999.0},
		"blue": {"money": 200.0, "iron": 999.0},
	}
	GameAuthority.player_states = {
		101: {"peer_id": 101, "team": "red", "hp": 200.0, "respawn_left": 0.0},
		202: {"peer_id": 202, "team": "blue", "hp": 200.0, "respawn_left": 0.0},
	}
	GameAuthority.reliable_world_event_ready.connect(_capture_event)

	_check(GlobalVar.get_team_score("red") == 100, "team score equals money and ignores inventory")
	GameAuthority._damage_player(202, 250.0, 0.0, Vector3.ZERO, "red", "test", 101)
	_check(GlobalVar.get_team_score("red") == 200, "enemy player final hit awards 100 money")
	_check(_has_reward(101, 100, "击杀对方玩家"), "player-kill reward event targets the killer")
	GameAuthority._damage_player(202, 250.0, 0.0, Vector3.ZERO, "red", "test", 101)
	_check(GlobalVar.get_team_score("red") == 200, "dead player cannot award money twice")

	var bear_scene := load("res://items/BlackBear.tscn") as PackedScene
	var bear := bear_scene.instantiate() as BlackBear
	add_child(bear)
	await get_tree().process_frame
	bear.impact_from_peer("test", bear.current_hp, "red", 101)
	_check(GlobalVar.get_team_score("red") == 250, "BlackBear final hit awards 50 money")
	_check(_has_reward(101, 50, "击杀黑熊"), "wild-animal reward uses its display name")

	var ore_scene := load("res://items/IronOre.tscn") as PackedScene
	var ore := ore_scene.instantiate() as HarvestOre
	add_child(ore)
	await get_tree().process_frame
	ore.impact_from_peer("test", ore.current_hp, "red", 101)
	_check(GlobalVar.get_team_score("red") == 300, "mining ore awards 50 money")
	_check(_has_reward(101, 50, "开采了铁矿"), "ore reward uses its display name")

	var tree_scene := load("res://buildings/nature/Oak.tscn") as PackedScene
	var tree := tree_scene.instantiate() as HarvestTree
	add_child(tree)
	await get_tree().process_frame
	tree.impact_from_peer("test", tree.current_hp, "red", 101)
	_check(GlobalVar.get_team_score("red") == 350, "chopping a tree awards 50 money")
	_check(_has_reward(101, 50, "砍伐了「橡树」"), "tree reward uses its localized display name")

	_check(GameAuthority.award_completed_dish_collection(101, "garden_salad"), "valid completed dish receives a reward")
	_check(GlobalVar.get_team_score("red") == 450, "completed dish collection awards 100 money")
	_check(_has_reward(101, 100, "领取成品菜"), "dish reward targets its collector")
	_check(not GameAuthority.award_completed_dish_collection(101, "burnt_plate"), "burnt dish receives no reward")
	_check(not GameAuthority.award_completed_dish_collection(101, "ruined_soup"), "ruined soup receives no reward")
	_check(GlobalVar.get_team_score("red") == 450, "failed dishes do not change team money")

	if GameAuthority.reliable_world_event_ready.is_connected(_capture_event):
		GameAuthority.reliable_world_event_ready.disconnect(_capture_event)
	GameAuthority.mode = original_mode
	GlobalVar.team_storage = original_storage
	GameAuthority.player_states = original_players
	print("Team reward validation: %s" % ("FAILED" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _capture_event(event: Dictionary) -> void:
	if str(event.get("type", "")) == "action_reward":
		_reward_events.append(event.duplicate(true))


func _has_reward(peer_id: int, amount: int, description: String) -> bool:
	for event: Dictionary in _reward_events:
		if int(event.get("peer_id", 0)) == peer_id \
				and int(event.get("amount", 0)) == amount \
				and str(event.get("description", "")) == description:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failed = true
		push_error("[FAIL] %s" % message)
