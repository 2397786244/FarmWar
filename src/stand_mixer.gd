extends KitchenAppliance
class_name StandMixer

const PROGRESS_SYNC_INTERVAL := 0.25
const MIXER_ROTATION_SPEED := TAU * 2.5

var recipe_id := ""
var staged_inputs: Array[Dictionary] = []
var output_ingredient_id := ""
var output_weight_kg := 0.0
var cooking := false
var complete := false
var started_msec := 0
var duration_seconds := 0.0
var _last_progress_sync_msec := 0

@onready var status_label: Label3D = $StatusLabel
@onready var progress_back: MeshInstance3D = $ProgressBack
@onready var progress_fill: MeshInstance3D = $ProgressFill
@onready var mixer_bowl_pivot: Node3D = find_child("MixerBowlPivot", true, false) as Node3D


func _ready() -> void:
	add_to_group("stand_mixers")
	_refresh_visual()


func _process(delta: float) -> void:
	if not GameAuthority.is_client_proxy() and cooking:
		var now_msec := Time.get_ticks_msec()
		if get_progress(now_msec) >= 1.0:
			cooking = false
			complete = true
			if active_user_peer_id != 0:
				release_user(active_user_peer_id)
			_refresh_visual()
			_emit_authoritative_state()
		elif now_msec - _last_progress_sync_msec >= int(PROGRESS_SYNC_INTERVAL * 1000.0):
			_last_progress_sync_msec = now_msec
			_refresh_visual()
			_emit_authoritative_state()
	if cooking and is_instance_valid(mixer_bowl_pivot):
		mixer_bowl_pivot.rotate_y(MIXER_ROTATION_SPEED * delta)


func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player):
		return "敌方立式搅拌机"
	if complete:
		return "[E] 拿取搅拌产物"
	if cooking:
		return "正在搅拌"
	if is_in_use_by_other(player.authority_peer_id):
		return "队友正在使用立式搅拌机"
	return "[E] 使用立式搅拌机"


func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player):
		return false
	if complete:
		return _request_take_output(player)
	if cooking:
		return false
	var page := player.get_node_or_null("SubViewport/StandMixerPage")
	if page == null or not page.has_method("open_for"):
		return false
	page.call("open_for", self, player)
	return true


func can_start_mixing(next_recipe_id: String) -> bool:
	return recipe_id.is_empty() and not cooking and not complete \
			and not MixerRecipeCatalog.get_recipe(next_recipe_id).is_empty()


func start_mixing(next_recipe_id: String) -> bool:
	if not can_start_mixing(next_recipe_id):
		return false
	var recipe := MixerRecipeCatalog.get_recipe(next_recipe_id)
	recipe_id = next_recipe_id
	staged_inputs.clear()
	for input: Dictionary in MixerRecipeCatalog.get_inputs(next_recipe_id):
		staged_inputs.append({
			"ingredient_id": str(input.get("ingredient_id", "")),
			"weight_kg": float(input.get("weight_kg", 0.0)),
			"placed": true,
		})
	output_ingredient_id = str(recipe.get("output_ingredient_id", ""))
	output_weight_kg = float(recipe.get("output_weight_kg", 0.0))
	duration_seconds = float(recipe.get("duration_seconds", 0.0))
	started_msec = Time.get_ticks_msec()
	cooking = true
	_last_progress_sync_msec = 0
	_refresh_visual()
	return true


func can_take_output() -> bool:
	return complete and not output_ingredient_id.is_empty() and output_weight_kg > 0.0


func take_output() -> Dictionary:
	if not can_take_output():
		return {}
	var output := {"ingredient_id": output_ingredient_id, "weight_kg": output_weight_kg}
	clear_mixer()
	return output


func clear_mixer() -> void:
	recipe_id = ""
	staged_inputs.clear()
	output_ingredient_id = ""
	output_weight_kg = 0.0
	cooking = false
	complete = false
	started_msec = 0
	duration_seconds = 0.0
	_refresh_visual()


func get_mixer_state() -> Dictionary:
	var state := {
		"station_path": str(get_path()),
		"station_position": global_position,
		"recipe_id": recipe_id,
		"staged_inputs": staged_inputs.duplicate(true),
		"output_ingredient_id": output_ingredient_id,
		"output_weight_kg": output_weight_kg,
		"cooking": cooking,
		"complete": complete,
		"duration_seconds": duration_seconds,
		"progress": get_progress(),
	}
	state.merge(get_user_lock_state(), true)
	return state


func apply_authoritative_mixer_state(state: Dictionary) -> void:
	apply_user_lock_state(state)
	recipe_id = str(state.get("recipe_id", ""))
	staged_inputs.clear()
	var inputs_value: Variant = state.get("staged_inputs", [])
	if inputs_value is Array:
		for input_value: Variant in inputs_value:
			if input_value is Dictionary:
				staged_inputs.append((input_value as Dictionary).duplicate(true))
	output_ingredient_id = str(state.get("output_ingredient_id", ""))
	output_weight_kg = maxf(0.0, float(state.get("output_weight_kg", 0.0)))
	cooking = bool(state.get("cooking", false))
	complete = bool(state.get("complete", false))
	duration_seconds = maxf(0.0, float(state.get("duration_seconds", 0.0)))
	var progress := clampf(float(state.get("progress", 0.0)), 0.0, 1.0)
	if cooking and duration_seconds > 0.0:
		started_msec = Time.get_ticks_msec() - int(progress * duration_seconds * 1000.0)
	_refresh_visual()


func get_progress(now_msec := Time.get_ticks_msec()) -> float:
	if complete:
		return 1.0
	if not cooking or duration_seconds <= 0.0:
		return 0.0
	return clampf(float(now_msec - started_msec) / (duration_seconds * 1000.0), 0.0, 1.0)


func _request_take_output(player: GamePlayer) -> bool:
	if not can_take_output() or not player.can_add_personal_ingredient(output_ingredient_id, output_weight_kg):
		return false
	var action := _make_action("take")
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return true
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	if bool(result.get("ok", false)):
		player.apply_authoritative_mixer_action_result(result)
	return bool(result.get("ok", false))


func _make_action(action_name: String) -> Dictionary:
	return {
		"station_kind": "mixer",
		"action": action_name,
		"station_path": str(get_path()),
		"station_position": global_position,
	}


func _emit_authoritative_state() -> void:
	GameAuthority.reliable_world_event_ready.emit({
		"type": "stand_mixer_state",
		"station_state": get_mixer_state(),
		"tick": GameAuthority.server_tick,
	})


func _refresh_visual() -> void:
	var progress := get_progress()
	if is_instance_valid(progress_back):
		progress_back.visible = cooking
	if is_instance_valid(progress_fill):
		progress_fill.visible = cooking
		progress_fill.scale.x = maxf(0.001, progress)
		progress_fill.position.x = -0.72 * (1.0 - progress)
	if not is_instance_valid(status_label):
		return
	if complete:
		status_label.text = "按 [E] 拿取搅拌产物"
	elif cooking:
		status_label.text = "搅拌中 %d%%" % roundi(progress * 100.0)
	else:
		status_label.text = "按 [E] 使用立式搅拌机"


func _should_keep_user_lock() -> bool:
	return cooking
