extends Node3D

const PLAYER_SCENE := preload("res://character/player.tscn")
const AUTOMATIC_IDS := [
	"m4", "m4_hardenedsteel", "m4_ruralcamo", "m4_snowcamo",
	"ar15", "ar15_hardenedsteel", "ar15_ruralcamo", "ar15_snowcamo",
	"ak47", "ak47_golden", "ak47_rusted", "ak47_hardenedsteel",
	"ak47_ruralcamo", "ak47_snowcamo",
	"mpx", "mpx_hardenedsteel", "mpx_ruralcamo", "mpx_snowcamo",
	"p90", "p90_ruralcamo", "p90_snowcamo",
	"future_m4", "future_mpx",
]
const RECOIL_IDS := [
	"rubber_revolver", "nail_gun", "suppressed_pistol", "m17",
	"m4", "ar15", "ak47", "mpx", "p90", "future_m4", "future_mpx",
	"hunting_rifle", "shotgun", "remington870", "crossbow",
	"m4_ruralcamo", "ak47_rusted", "remington870_snowcamo",
]
const EXCLUDED_RECOIL_IDS := [
	"flame_gun", "freeze_gun", "tranquilizer_pistol",
	"medicine_pistol", "spicy_blaster",
]

var failures: Array[String] = []
var player: GamePlayer


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_weapon_classification()
	_validate_cooldowns_are_fire_intervals()
	await _validate_player_recoil_and_modes()
	_finish()


func _validate_weapon_classification() -> void:
	for tool_id: String in AUTOMATIC_IDS:
		_check(CombatBalance.is_automatic_fire_weapon(tool_id), "%s is classified as automatic" % tool_id)
		_check(CombatBalance.is_player_recoil_weapon(tool_id), "%s keeps player recoil" % tool_id)
	for tool_id: String in RECOIL_IDS:
		_check(CombatBalance.is_player_recoil_weapon(tool_id), "%s receives player recoil" % tool_id)
	for tool_id: String in EXCLUDED_RECOIL_IDS:
		_check(not CombatBalance.is_player_recoil_weapon(tool_id), "%s is excluded from player recoil" % tool_id)
		_check(not CombatBalance.is_automatic_fire_weapon(tool_id), "%s is not automatic" % tool_id)
	_check(not CombatBalance.is_automatic_fire_weapon("shotgun"), "shotgun stays single shot")
	_check(not CombatBalance.is_automatic_fire_weapon("hunting_rifle"), "hunting rifle stays single shot")
	_check(CombatBalance.is_automatic_fire_weapon("m4_ruralcamo"), "M4 camouflage resolves to automatic fire")
	_check(CombatBalance.is_automatic_fire_weapon("ak47_golden"), "AK47 camouflage resolves to automatic fire")


func _validate_cooldowns_are_fire_intervals() -> void:
	var definitions := _read_json("res://data/tool_definitions.json")
	var by_id := _definitions_by_id(definitions.get("tools", []))
	for tool_id: String in ["m4", "ar15", "ak47", "mpx", "p90", "future_m4", "future_mpx"]:
		var definition: Dictionary = by_id.get(tool_id, {})
		var cooldown := float(definition.get("cooldown", 0.0))
		_check(cooldown > 0.0, "%s has a positive cooldown for automatic fire" % tool_id)
		_check(is_equal_approx(float(CombatBalance.get_float(tool_id, "range")), CombatBalance.get_float(tool_id, "range")), "%s combat profile remains readable" % tool_id)


func _validate_player_recoil_and_modes() -> void:
	player = PLAYER_SCENE.instantiate() as GamePlayer
	_check(player != null, "player scene instantiates for recoil validation")
	if player == null:
		return
	add_child(player)
	await get_tree().process_frame
	await get_tree().process_frame

	player.call("_reset_weapon_recoil_state")
	player.Head.rotation.x = 0.0
	_check(str(player.call("_get_fire_mode", "m4")) == "auto", "an unseen automatic weapon starts in automatic mode")
	player.fire_modes_by_tool_id["m4"] = "single"
	player.call("_apply_weapon_recoil_pitch", "m4", 0.04)
	var single_pitch := rad_to_deg(float(player.Head.rotation.x))
	var single_reticle_offset := float(player.crosshair_recoil_offset_pixels)
	_check(single_pitch > 0.0 and single_pitch <= 0.75, "single-shot recoil moves the view slightly upward")
	_check(single_reticle_offset > 0.0, "single-shot recoil moves the crosshair upward")

	player.call("_reset_weapon_recoil_state")
	player.Head.rotation.x = 0.0
	player.fire_modes_by_tool_id["m4"] = "auto"
	player.call("_apply_weapon_recoil_pitch", "m4", 0.04)
	var auto_pitch := rad_to_deg(float(player.Head.rotation.x))
	_check(auto_pitch > single_pitch, "automatic mode has stronger per-shot upward recoil")
	var auto_logical_pitch := rad_to_deg(float(player.weapon_recoil_pitch))
	_check(
		is_equal_approx(auto_logical_pitch, CombatBalance.get_float("m4", "auto_recoil_kick_degrees")),
		"automatic recoil uses the configured kick bounds"
	)
	var accumulated_pitch := auto_pitch
	for _shot in range(8):
		player.call("_apply_weapon_recoil_pitch", "m4", 0.04)
		accumulated_pitch = rad_to_deg(float(player.Head.rotation.x))
	_check(accumulated_pitch > auto_pitch, "automatic fire visibly accumulates recoil")
	_check(
		rad_to_deg(float(player.weapon_recoil_pitch)) <= CombatBalance.get_float("m4", "auto_recoil_vertical_cap_degrees") + 0.001,
		"automatic recoil has a bounded accumulation"
	)

	var before_recovery := float(player.weapon_recoil_pitch)
	player.call("_update_weapon_recoil", 0.1)
	_check(float(player.weapon_recoil_pitch) < before_recovery, "recoil smoothly recovers after firing")
	_check(float(player.crosshair_recoil_offset_pixels) < CROSSHAIR_RECOIL_MAX_PIXELS(), "crosshair offset follows recoil recovery")

	player.call("_reset_weapon_recoil_state")
	player.Head.rotation.x = 0.0
	player.call("trigger_weapon_camera_recoil", "flame_gun")
	_check(is_zero_approx(float(player.weapon_recoil_pitch)), "flame gun does not receive conventional recoil pitch")
	player.call("trigger_weapon_camera_recoil", "crossbow")
	_check(float(player.weapon_recoil_pitch) > 0.0, "crossbow receives a visible single-shot recoil pitch")

	# Exercise the same mode-toggle helper used by second_action without relying on
	# platform input synthesis in a headless run.
	player.current_tool_index = 0
	player.tool_definitions[0] = player.all_tool_definitions_by_id["m4"].duplicate(true)
	_check(bool(player.call("_current_tool_is_automatic")), "current M4 is eligible for mode switching")
	player.fire_modes_by_tool_id.erase("m4")
	player.call("_toggle_current_tool_fire_mode")
	_check(str(player.call("_get_fire_mode", "m4")) == "single", "mode toggle changes M4 to single shot")
	player.tool_definitions[0] = player.all_tool_definitions_by_id["m4_ruralcamo"].duplicate(true)
	player.fire_modes_by_tool_id.erase("m4_ruralcamo")
	_check(str(player.call("_get_fire_mode", "m4_ruralcamo")) == "auto", "a camouflage ID has an independent automatic default")
	player.call("_toggle_current_tool_fire_mode")
	_check(str(player.call("_get_fire_mode", "m4_ruralcamo")) == "single", "camouflage mode toggles independently")
	_check(str(player.call("_get_fire_mode", "m4")) == "single", "base M4 mode is not merged with camouflage mode")

	player.backpack_items.clear()
	player.backpack_items.append({
		"kind": "tool",
		"tool_id": "m4",
		"ammo_in_mag": 30,
		"reserve_ammo": 0,
	})
	player.current_tool_index = 0
	player.fire_modes_by_tool_id["m4"] = "single"
	var single_weapon_info := str(player.call("_get_selected_item_info_text"))
	_check(
		single_weapon_info.split("\n")[0].ends_with(" | 单发"),
		"left HUD shows single-shot mode beside the automatic weapon name"
	)
	player.fire_modes_by_tool_id["m4"] = "auto"
	var automatic_weapon_info := str(player.call("_get_selected_item_info_text"))
	_check(
		automatic_weapon_info.split("\n")[0].ends_with(" | 连发"),
		"left HUD shows automatic mode beside the automatic weapon name"
	)
	_validate_recoil_direction_and_strength()
	_validate_single_fire_recoil_tuning()

	player.queue_free()
	await get_tree().process_frame


func _validate_recoil_direction_and_strength() -> void:
	if player == null or not is_instance_valid(player):
		return
	player.call("_reset_weapon_recoil_state")
	player.Head.rotation.x = 0.0
	player.current_tool_index = 0
	player.tool_definitions[0] = player.all_tool_definitions_by_id["ak47"].duplicate(true)
	var muzzle_position: Vector3 = player.camera.global_position
	var direction_before: Vector3 = player.call(
		"get_shooting_aim_direction",
		muzzle_position,
		120.0
	)
	player.fire_modes_by_tool_id["ak47"] = "auto"
	player.call(
		"_apply_weapon_recoil_pitch",
		"ak47",
		CombatBalance.get_float("ak47", "camera_recoil_strength")
	)
	var direction_after: Vector3 = player.call(
		"get_shooting_aim_direction",
		muzzle_position,
		120.0
	)
	_check(
		direction_after.distance_to(direction_before) > 0.0001,
		"recoil changes the actual shooting direction"
	)
	_check(direction_after.y > direction_before.y, "recoil moves the shooting direction upward")
	var request: Dictionary = player.call("_make_tool_request", false)
	var request_direction: Variant = request.get("direction", Vector3.ZERO)
	_check(
		request_direction is Vector3 \
			and (request_direction as Vector3).distance_to(direction_after) < 0.0001,
		"tool request uses the same direction as the reticle ray"
	)
	var saw_positive_lateral_recoil := false
	var saw_negative_lateral_recoil := false
	player.call("_reset_weapon_recoil_state")
	for _shot in range(80):
		player.call(
			"_apply_weapon_recoil_pitch",
			"ak47",
			CombatBalance.get_float("ak47", "camera_recoil_strength")
		)
		var lateral_recoil := float(player.weapon_recoil_offset_degrees.x)
		saw_positive_lateral_recoil = saw_positive_lateral_recoil or lateral_recoil > 0.001
		saw_negative_lateral_recoil = saw_negative_lateral_recoil or lateral_recoil < -0.001
	_check(saw_positive_lateral_recoil and saw_negative_lateral_recoil, "automatic recoil randomly walks in both horizontal directions")
	var ak47_cap := CombatBalance.get_float("ak47", "auto_recoil_vertical_cap_degrees")
	_check(
		is_equal_approx(float(player.weapon_recoil_offset_degrees.y), ak47_cap),
		"AK47 recoil reaches but does not exceed its vertical cap"
	)
	var full_load_scale: float
	var empty_load_scale: float
	player.call("_reset_weapon_recoil_state")
	empty_load_scale = float(player.call("_get_weapon_recoil_input_scale"))
	player.weapon_recoil_offset_degrees = Vector2(0.0, ak47_cap)
	player.call("_sync_weapon_recoil_visual")
	full_load_scale = float(player.call("_get_weapon_recoil_input_scale"))
	_check(empty_load_scale > full_load_scale, "automatic recoil adds progressive mouse resistance")
	_check(
		is_equal_approx(full_load_scale, CombatBalance.get_float("ak47", "auto_recoil_input_min_scale")),
		"AK47 recoil reaches its configured minimum mouse input scale"
	)
	player.call("_reset_weapon_recoil_state")
	player.look_pitch_without_recoil = 0.0
	player.weapon_recoil_offset_degrees = Vector2(0.0, 2.0)
	player.call("_sync_weapon_recoil_visual")
	player.call("_consume_recoil_look_input", Vector2(0.0, -2.0))
	player.call("_sync_weapon_recoil_visual")
	player.call("_update_weapon_recoil", 1.0)
	_check(
		is_zero_approx(float(player.weapon_recoil_offset_degrees.y))
			and absf(float(player.look_pitch_without_recoil)) < 0.0001
			and absf(float(player.Head.rotation.x)) < 0.0001,
		"counter-steering recoil does not cause recovery to overshoot downward"
	)
	_check(
		CombatBalance.get_float("ak47", "auto_recoil_kick_degrees") \
			> CombatBalance.get_float("m4", "auto_recoil_kick_degrees"),
		"AK47 has stronger configured automatic recoil than M4"
	)
	_check(
		CombatBalance.get_float("m4", "auto_recoil_kick_degrees") \
			> CombatBalance.get_float("mpx", "auto_recoil_kick_degrees") \
			and CombatBalance.get_float("m4", "auto_recoil_kick_degrees") \
			> CombatBalance.get_float("p90", "auto_recoil_kick_degrees"),
		"rifle automatic recoil is stronger than compact SMG recoil"
	)
	for automatic_id: String in ["m4", "ar15", "ak47", "mpx", "p90", "future_m4", "future_mpx"]:
		_check(
			CombatBalance.get_float(automatic_id, "auto_recoil_kick_degrees") > 0.0,
			"%s has an explicit automatic recoil kick" % automatic_id
		)
	_check(
		is_equal_approx(
			CombatBalance.get_float("ak47_golden", "auto_recoil_kick_degrees"),
			CombatBalance.get_float("ak47", "auto_recoil_kick_degrees")
		),
		"AK47 skins reuse the base automatic recoil tuning"
	)


func _validate_single_fire_recoil_tuning() -> void:
	var pistol_kick_values: Array[float] = []
	for pistol_id: String in ["suppressed_pistol", "m17"]:
		var pistol_kick := CombatBalance.get_float(pistol_id, "single_recoil_kick_degrees")
		pistol_kick_values.append(pistol_kick)
		_check(pistol_kick > 0.0, "%s has a visible single-shot recoil kick" % pistol_id)
	var revolver_kick := CombatBalance.get_float("rubber_revolver", "single_recoil_kick_degrees")
	var crossbow_kick := CombatBalance.get_float("crossbow", "single_recoil_kick_degrees")
	var hunting_rifle_kick := CombatBalance.get_float("hunting_rifle", "single_recoil_kick_degrees")
	var shotgun_kick := CombatBalance.get_float("shotgun", "single_recoil_kick_degrees")
	var remington_kick := CombatBalance.get_float("remington870", "single_recoil_kick_degrees")
	_check(
		pistol_kick_values.max() < crossbow_kick,
		"pistols remain the weakest visible single-shot recoil tier"
	)
	_check(
		crossbow_kick < revolver_kick and revolver_kick < hunting_rifle_kick,
		"crossbow, revolver, and hunting rifle recoil tiers increase appropriately"
	)
	_check(
		hunting_rifle_kick < shotgun_kick and shotgun_kick <= remington_kick,
		"shotgun recoil remains stronger than hunting rifle recoil"
	)
	_check(
		is_equal_approx(revolver_kick, 5.0),
		"rubber revolver uses the requested five-degree kick"
	)
	_check(
		is_equal_approx(hunting_rifle_kick, 6.0),
		"hunting rifle uses the requested six-degree kick"
	)
	_check(
		shotgun_kick >= 5.0 and shotgun_kick <= 8.0 \
			and remington_kick >= 5.0 and remington_kick <= 8.0,
		"both shotguns stay within the requested five-to-eight-degree range"
	)
	for single_id: String in [
		"rubber_revolver", "suppressed_pistol", "m17", "crossbow",
		"hunting_rifle", "shotgun", "remington870",
	]:
		player.call("_reset_weapon_recoil_state")
		player.Head.rotation.x = 0.0
		player.call("_apply_weapon_recoil_pitch", single_id, CombatBalance.get_float(single_id, "camera_recoil_strength"))
		_check(
			float(player.weapon_recoil_pitch) > 0.0
				and float(player.crosshair_recoil_offset_pixels) > 0.0,
			"%s moves both view recoil and reticle upward" % single_id
		)


func CROSSHAIR_RECOIL_MAX_PIXELS() -> float:
	return 180.0


func _definitions_by_id(values: Variant) -> Dictionary:
	var result := {}
	if not values is Array:
		return result
	for value: Variant in values:
		if value is Dictionary:
			var definition := value as Dictionary
			var tool_id := str(definition.get("id", ""))
			if not tool_id.is_empty():
				result[tool_id] = definition
	return result


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PlayerFireModeRecoilValidation] PASS: %s" % message)
	else:
		failures.append(message)
		push_error("[PlayerFireModeRecoilValidation] FAIL: %s" % message)


func _finish() -> void:
	if failures.is_empty():
		print("[PlayerFireModeRecoilValidation] PASS all checks")
	else:
		print("[PlayerFireModeRecoilValidation] FAIL count=%d" % failures.size())
	get_tree().quit(0 if failures.is_empty() else 1)
