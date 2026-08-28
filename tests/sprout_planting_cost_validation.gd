extends Node3D

const FARM_TILE_SCENE := preload("res://items/farm_tile.tscn")

var failures := 0
var tile_serial := 0
var tiles: Array[FarmTile] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "SproutPlantingCostValidation",
		"team": "red",
		"position": Vector3.ZERO,
		"special_tool_ids": ["sprout_blaster"],
		"current_tool_index": 0,
		"current_tool_id": "sprout_blaster",
	})
	GlobalVar.gameworld = self
	await get_tree().process_frame

	_check(IngredientCatalog.get_planting_cost("potato") == 1, "potato planting cost is 1")
	_check(IngredientCatalog.get_planting_cost("tomato") == 2, "tomato planting cost is 2")
	_check(IngredientCatalog.get_planting_cost("pepper") == 4, "pepper planting cost is 4")
	_check(IngredientCatalog.get_planting_cost("tobacco") == 8, "tobacco planting cost is 8")
	_check(is_equal_approx(IngredientCatalog.get_growth_time_seconds("potato"), 45.0), "potato growth time is 45 seconds")
	_check(is_equal_approx(IngredientCatalog.get_growth_time_seconds("grape", true), 120.0), "grape regrowth time is 120 seconds")

	var potato_tile := _make_tile()
	var money_before := GlobalVar.check_team_item_amount("red", "money")
	var potato_result := GameAuthority.local_try_use_tool(1, _plant_request(potato_tile, "potato"))
	_check(bool(potato_result.get("ok", false)), "SproutBlaster plants the selected potato")
	_check(potato_tile.seed_record == "potato", "selected crop reaches the FarmTile")
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), money_before - 1.0),
		"successful potato planting charges exactly once"
	)

	_reset_sprout_cooldown()
	var occupied_money := GlobalVar.check_team_item_amount("red", "money")
	var occupied_result := GameAuthority.local_try_use_tool(1, _plant_request(potato_tile, "tobacco"))
	_check(not bool(occupied_result.get("ok", false)), "occupied FarmTile rejects a second planting")
	_check(str(occupied_result.get("reason", "")) == "farm_tile_occupied", "occupied FarmTile reports the correct reason")
	_check(
		is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), occupied_money),
		"rejected occupied planting does not charge money"
	)

	var insufficient_tile := _make_tile()
	var all_money := GlobalVar.check_team_item_amount("red", "money")
	if all_money > 0.0:
		GlobalVar.remove_item("red", "money", all_money)
	_reset_sprout_cooldown()
	var insufficient_result := GameAuthority.local_try_use_tool(1, _plant_request(insufficient_tile, "tobacco"))
	_check(not bool(insufficient_result.get("ok", false)), "insufficient team money rejects planting")
	_check(str(insufficient_result.get("reason", "")) == "insufficient_money", "insufficient money reports the correct reason")
	_check(insufficient_tile.is_empty(), "insufficient money leaves the FarmTile empty")
	_check(is_zero_approx(GlobalVar.check_team_item_amount("red", "money")), "insufficient planting does not create negative money")

	var growth_tile := _make_tile()
	_check(growth_tile.apply_authoritative_plant("potato", "red", 0, false), "potato growth test plants a crop")
	for _index in range(44):
		growth_tile.step()
	_check(not growth_tile.can_harvest, "potato is not mature after 44 seconds")
	growth_tile.step()
	_check(growth_tile.can_harvest, "potato matures after 45 seconds")

	var regrowth_tile := _make_tile()
	_check(regrowth_tile.apply_authoritative_plant("grape", "red", 0, false), "grape regrowth test plants a crop")
	regrowth_tile._reset_crop_for_regrowth()
	for _index in range(119):
		regrowth_tile.step()
	_check(not regrowth_tile.can_harvest, "grape is not mature after 119 regrowth seconds")
	regrowth_tile.step()
	_check(regrowth_tile.can_harvest, "grape matures after 120 regrowth seconds")

	_finish()


func _make_tile() -> FarmTile:
	tile_serial += 1
	var tile := FARM_TILE_SCENE.instantiate() as FarmTile
	tile.name = "FarmTile_%d" % tile_serial
	add_child(tile)
	tiles.append(tile)
	return tile


func _plant_request(tile: FarmTile, seed_id: String) -> Dictionary:
	return {
		"tool_id": "sprout_blaster",
		"tool_index": 0,
		"seed_id": seed_id,
		"target_tile_path": str(tile.get_path()),
		"target_position": tile.global_position,
		"player_position": Vector3.ZERO,
		"origin": Vector3(0.0, 2.0, 0.0),
		"direction": Vector3.DOWN,
	}


func _reset_sprout_cooldown() -> void:
	var state: Dictionary = GameAuthority.player_states.get(1, {})
	var cooldowns: Dictionary = state.get("tool_cooldowns", {})
	cooldowns["sprout_blaster"] = 0.0
	state["tool_cooldowns"] = cooldowns
	GameAuthority.player_states[1] = state


func _finish() -> void:
	if failures == 0:
		print("[SproutPlantingCostValidation] PASS all checks")
	else:
		push_error("[SproutPlantingCostValidation] FAIL count=%d" % failures)
	for tile in tiles:
		if is_instance_valid(tile):
			tile.queue_free()
	GameAuthority.stop_authority()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[SproutPlantingCostValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[SproutPlantingCostValidation] FAIL: %s" % description)
