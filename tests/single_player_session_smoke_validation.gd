extends Node

const CONTROLLER_META := "singleplayer_smoke_controller"
const TIMEOUT_SECONDS := 120.0

var failures: Array[String] = []
var elapsed := 0.0
var test_root := ""
var original_root := ""
var world_id := ""
var completed := false
var phase := 0
var expected_elapsed_seconds := 0.0
var expected_hour := 0.0
var expected_day_index := 0
var expected_game_day := 1
var expected_weather_type := ""
var expected_weather_intensity := 0.0
var expected_forecast: Array = []
var expected_forecast_revision := 0
var expected_forecast_start_day := -1


func _ready() -> void:
	if not bool(get_meta(CONTROLLER_META, false)):
		var controller := Node.new()
		controller.name = "SinglePlayerSessionSmokeController"
		controller.set_meta(CONTROLLER_META, true)
		controller.set_script(get_script())
		get_tree().root.call_deferred("add_child", controller)
		return
	call_deferred("_start")


func _process(delta: float) -> void:
	if completed or world_id.is_empty():
		return
	elapsed += delta
	if SinglePlayerSession.authority_ready:
		completed = true
		if phase == 0:
			call_deferred("_verify_running_session")
		else:
			call_deferred("_verify_restored_session")
	elif elapsed >= TIMEOUT_SECONDS:
		completed = true
		_fail_and_finish("单人世界在超时前未完成地图与玩家初始化")


func _start() -> void:
	original_root = SinglePlayerWorldStorage.world_root
	test_root = "/private/tmp/food-war-singleplayer-session-%d" % Time.get_ticks_usec()
	SinglePlayerWorldStorage.world_root = test_root
	var map_definition := GameMapRegistry.get_map_by_id("coop_test")
	var world := SinglePlayerWorldStorage.create_world({
		"display_name": "Session Smoke",
		"map_id": str(map_definition.get("map_id", "coop_test")),
		"map_name": str(map_definition.get("display_name", "coop test")),
		"map_icon_path": str(map_definition.get("icon_path", "")),
		"map_scene_path": str(map_definition.get("scene_path", "")),
		"loading_images_directory": str(map_definition.get("loading_images_directory", "")),
		"map_version": str(map_definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(map_definition.get("map_hash", "")),
		"map_source": str(map_definition.get("source", "builtin")),
	}, {
		"hero_id": "farmer",
		"primary_weapon_ids": ["rubber_revolver", "flame_gun", "freeze_gun"],
		"special_tool_ids": ["plant_protector", "fertilizer"],
	})
	world_id = str(world.get("world_id", ""))
	if world_id.is_empty() or not SinglePlayerSession.start_world(world_id):
		_fail_and_finish("无法创建并启动单人测试世界")


func _verify_running_session() -> void:
	_check(SinglePlayerSession.is_active(), "single-player session remains active after bootstrap")
	_check(GameAuthority.is_local_authority(), "single-player session uses local authority")
	var player: GamePlayer = null
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			player = node as GamePlayer
			break
	_check(player != null, "single-player session spawns one local player")
	GlobalVar.team_storage["red"]["money"] = 4321.0
	GameAuthority.set_world_elapsed_seconds(720.0)
	var weather := get_tree().get_first_node_in_group("weather_systems")
	if weather != null and weather.has_method("set_weather_override"):
		weather.call("set_weather_override", "rain")
	# Allow the environment process to apply the override before sampling the
	# state that is meant to represent the save point.
	for _frame in range(3):
		await get_tree().process_frame
	var expected_clock := WorldPersistence.capture_world_clock_state()
	expected_elapsed_seconds = float(expected_clock.get("elapsed_seconds", 0.0))
	expected_hour = float(expected_clock.get("hour", 0.0))
	expected_day_index = int(expected_clock.get("day_index", 0))
	expected_game_day = int(expected_clock.get("game_day", expected_day_index + 1))
	if weather != null and weather.has_method("get_persistent_state"):
		var expected_weather := weather.call("get_persistent_state") as Dictionary
		expected_weather_type = str(expected_weather.get("current_weather_type", ""))
		expected_weather_intensity = float(expected_weather.get("current_intensity", 0.0))
		expected_forecast = (expected_weather.get("forecast_days", []) as Array).duplicate(true)
		expected_forecast_revision = int(expected_weather.get("forecast_revision", 0))
		expected_forecast_start_day = int(expected_weather.get("forecast_start_day", -1))
	# The authority tick mirrors the physics body's health, so set this after
	# the weather sampling frames and immediately before the save point.
	if player != null:
		player.server_hp = 123.0
	_check(SinglePlayerSession.save_game(), "manual single-player save succeeds after bootstrap")
	SinglePlayerSession.stop_session()
	var saved := SinglePlayerWorldStorage.load_world(world_id)
	var player_state := saved.get("player_state", {}) as Dictionary
	var world_state := saved.get("world_state", {}) as Dictionary
	_check(is_equal_approx(float(player_state.get("current_hp", 0.0)), 123.0), \
		"manual save captures the visible local player HP")
	_check(is_equal_approx(float(saved.get("team_money", 0.0)), 4321.0), \
		"manual save captures team funds")
	_check(world_state.has("farm_tiles") and world_state.has("vehicles") and world_state.has("weather"), \
		"manual save writes the complete shared world-state schema")
	_check(world_state.has("world_clock"), "manual save writes the persistent world clock")
	var saved_clock := WorldPersistence.get_saved_world_clock_state(saved)
	_check(absf(float(saved_clock.get("elapsed_seconds", 0.0)) - expected_elapsed_seconds) < 0.1, \
		"manual save captures the current simulation elapsed time")
	_check(absf(float(saved_clock.get("hour", 0.0)) - expected_hour) < 0.1, \
		"manual save captures the current in-game hour")
	_check(int(saved_clock.get("day_index", -1)) == expected_day_index \
		and int(saved_clock.get("game_day", -1)) == expected_game_day, \
		"manual save captures the current in-game date")
	var saved_weather := world_state.get("weather", {}) as Dictionary
	_check(str(saved_weather.get("current_weather_type", "")) == expected_weather_type, \
		"manual save captures the current weather type")
	_check(_forecast_signature(saved_weather.get("forecast_days", [])) == _forecast_signature(expected_forecast), \
		"manual save captures the complete seven-day forecast")
	_check(int(saved_weather.get("forecast_revision", -1)) == expected_forecast_revision \
		and int(saved_weather.get("forecast_start_day", -1)) == expected_forecast_start_day, \
		"manual save captures the forecast revision and start date")
	phase = 1
	elapsed = 0.0
	completed = false
	if not SinglePlayerSession.start_world(world_id):
		_fail_and_finish("保存后无法重新进入单人世界")


func _verify_restored_session() -> void:
	var player: GamePlayer = null
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy:
			player = node as GamePlayer
			break
	_check(player != null and is_equal_approx(player.server_hp, 123.0), \
		"re-entering the world restores local player HP")
	_check(is_equal_approx(GlobalVar.check_team_item_amount("red", "money"), 4321.0), \
		"re-entering the world restores team funds")
	_check(str(SinglePlayerSession.local_selection.get("hero_id", "")) == "farmer", \
		"re-entering the world keeps the permanently locked character")
	var restored_clock := WorldPersistence.capture_world_clock_state()
	_check(absf(float(restored_clock.get("elapsed_seconds", 0.0)) - expected_elapsed_seconds) < 0.1, \
		"re-entering the world restores simulation elapsed time")
	_check(absf(float(restored_clock.get("hour", 0.0)) - expected_hour) < 0.1, \
		"re-entering the world restores the in-game hour")
	_check(int(restored_clock.get("day_index", -1)) == expected_day_index \
		and int(restored_clock.get("game_day", -1)) == expected_game_day, \
		"re-entering the world restores the in-game date")
	var restored_weather := get_tree().get_first_node_in_group("weather_systems")
	if restored_weather != null:
		_check(str(restored_weather.get("current_weather")) == expected_weather_type, \
			"re-entering the world restores the current weather type")
		var restored_intensity := float(restored_weather.get("current_intensity"))
		_check(absf(restored_intensity - expected_weather_intensity) < 0.1, \
			"re-entering the world restores the current weather intensity (expected %.3f, got %.3f)" % [expected_weather_intensity, restored_intensity])
		var restored_forecast := restored_weather.call("get_weather_forecast_state") as Dictionary
		_check(_forecast_signature(restored_forecast.get("forecast_days", [])) == _forecast_signature(expected_forecast), \
			"re-entering the world restores the seven-day forecast")
		_check(int(restored_forecast.get("forecast_revision", -1)) == expected_forecast_revision \
			and int(restored_forecast.get("forecast_start_day", -1)) == expected_forecast_start_day, \
			"re-entering the world restores the forecast revision and start date")
	_finish()


func _forecast_signature(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if not value is Array:
		return result
	for item: Variant in value:
		if not item is Dictionary:
			continue
		var entry := item as Dictionary
		var eclipse_value: Variant = entry.get("eclipse", {})
		var eclipse := eclipse_value as Dictionary if eclipse_value is Dictionary else {}
		result.append("%d|%s|%.4f|%s|%.4f|%.4f" % [
			int(entry.get("day_index", -1)),
			str(entry.get("weather_type", "clear")),
			float(entry.get("rain_intensity", 0.0)),
			str(bool(eclipse.get("enabled", false))),
			float(eclipse.get("start_hour", 0.0)),
			float(eclipse.get("end_hour", 0.0)),
		])
	return result


func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: ", description)
	else:
		failures.append(description)
		push_error("FAIL: " + description)


func _fail_and_finish(message: String) -> void:
	failures.append(message)
	push_error("FAIL: " + message)
	_finish()


func _finish() -> void:
	if SinglePlayerSession.is_active():
		SinglePlayerSession.stop_session()
	if not world_id.is_empty():
		SinglePlayerWorldStorage.delete_world(world_id)
	SinglePlayerWorldStorage.world_root = original_root
	if failures.is_empty():
		print("Single-player session smoke validation passed")
		get_tree().quit(0)
	else:
		push_error("Single-player session smoke validation failed: %s" % ", ".join(failures))
		get_tree().quit(1)
