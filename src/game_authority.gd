extends Node
class_name GameAuthorityService

const CombatBalance = preload("res://src/combat_balance.gd")

# GameAuthority 是“多人服务端权威”和“单人本地权威”的统一战局层。
# 多人模式：客户端只提交输入/请求，Dedicated Server 在这里执行移动、伤害、放置、农田、商店等真实逻辑。
# 单人模式：不创建 ENet，但仍调用同一批 server_* 业务函数，避免本地玩法和多人玩法规则分叉。
signal world_snapshot_ready(snapshot: Dictionary)
signal reliable_world_event_ready(event: Dictionary)
signal visual_world_event_ready(event: Dictionary)
signal inventory_state_ready(state: Dictionary)
signal player_correction_ready(peer_id: int, correction: Dictionary)
signal team_chat_message_ready(message: Dictionary)

const MODE_DISABLED := "disabled"
const MODE_LOCAL := "local"
const MODE_CLIENT := "client"
const MODE_SERVER := "server"
const LOCAL_PLAYER_ID := 1
const TARGET_TICK_RATE := 60.0
const TARGET_TICK_INTERVAL := 1.0 / TARGET_TICK_RATE
const WORLD_SNAPSHOT_TICK_INTERVAL := 2
const METRICS_SAMPLE_LIMIT := 120
const LOW_FREQ_SNAPSHOT_INTERVAL := 1.0
const NATURE_RESOURCE_RECONCILE_INTERVAL := 10.0
const FARM_RECONCILE_INTERVAL := 7.0
const FARM_RECONCILE_CHUNK_SIZE := 32
const PLAYER_CORRECTION_TICK_INTERVAL := 1
const PLAYER_JUMP_GRACE_TICKS := 3
const PLAYER_MAX_HP := 200.0
const PLAYER_RESPAWN_SECONDS := 10.0
const LOCAL_MATCH_DURATION_SECONDS := 48.0 * 60.0
const PLAYER_KNOCKBACK_DECELERATION := 18.0
const PLAYER_PRONE_SPEED_MULTIPLIER := 0.4
const PLAYER_PRONE_MAX_PITCH_DEGREES := 16.0
const PLAYER_PRONE_COLLISION_POSITION := Vector3(0.0, 0.5, -0.2)
const PLAYER_CROP_INTERACTION_RANGE := 4.0
const PLAYER_VEHICLE_INTERACTION_RANGE := 4.0
const BASE_PERSONAL_BAG_WEIGHT_KG := 30.0
const BASE_PLAYER_BAG_SLOTS := 12
const BAG_SLOTS_PER_ROW := 6
const PLAYER_HOTBAR_SLOT_COUNT := 6
const MAX_EQUIPMENT_EXTRA_SLOTS := 60
const MAX_CHAT_MESSAGE_CHARACTERS := 256
const MAX_CHAT_MESSAGES_PER_SECOND := 5
const CHAT_RATE_WINDOW_MSEC := 1000
const HANDHELD_INGREDIENT_PREFIX := "ingredient:"
const PLAYER_INTERACTION_MIN_FORWARD_DOT := -0.15
const PLAYER_PHYSICS_BODY_SCENE := preload("res://character/player_physics_body.tscn")
const BUG_STORM_SCENE := preload("res://character/weapons/BugStorm.tscn")
const MEDICINE_STORM_SCENE := preload("res://character/weapons/MedicineStorm.tscn")
const SPICY_AREA_SCENE := preload("res://character/weapons/SpicyArea.tscn")
const BOOM_BULLET_SCENE := preload("res://character/weapons/boom.tscn")
const BOOM_EFFECT_SCENE := preload("res://character/weapons/BoomEffect.tscn")
const GRENADE_VISUAL_SCENE := preload("res://character/weapons/Grenade.tscn")
const SHIELD_LASER_VISUAL_SCENE := preload("res://character/weapons/ShieldLaser.tscn")
const GRENADE_EXPLOSION_SCENE := preload("res://character/weapons/GrenadeExplosion.tscn")
const PICKUP_ITEM_SCENE := preload("res://items/pickup_item.tscn")
const RED_CARGO_CAR_SCENE := preload("res://vehicles/red_cargo_car.tscn")
const BLUE_CARGO_CAR_SCENE := preload("res://vehicles/blue_cargo_car.tscn")
const RIFT_ANCHOR_SCENE := preload("res://character/weapons/RiftAnchor.tscn")
const LOG_DROP_MODEL := "res://assets/other_items/Material/Log_Drop.glb"
const TOOL_DEFINITIONS_PATH := "res://data/tool_definitions.json"
const FINITE_AMMO_WEAPON_IDS := {
	"nail_gun": true,
	"rubber_revolver": true,
	"suppressed_pistol": true,
	"shotgun": true,
	"hunting_rifle": true,
	"m4": true,
	"ar15": true,
}
# Server combat queries hit only meaningful gameplay targets and blockers.
# River (4), shops (512), and other non-combat layers intentionally stay out.
const COLLISION_LAYER_GROUND := 1
const COLLISION_LAYER_WALL := 2
const COLLISION_LAYER_CHARACTER := 8
const COLLISION_LAYER_BULLET := 32
const COLLISION_LAYER_FARM_TILE := 64
const COLLISION_LAYER_TOOL := 128
const COLLISION_LAYER_BUILDING := 4096
const COLLISION_LAYER_VEHICLES := 8192
const COLLISION_LAYER_NATURE_RESOURCE := 16384
const COLLISION_LAYER_WILD_ANIMAL := 32768
const WILD_ANIMAL_BODY_MASK := (
	COLLISION_LAYER_GROUND | COLLISION_LAYER_WALL | COLLISION_LAYER_CHARACTER
	| COLLISION_LAYER_TOOL | COLLISION_LAYER_BUILDING | COLLISION_LAYER_VEHICLES
	| COLLISION_LAYER_NATURE_RESOURCE | COLLISION_LAYER_WILD_ANIMAL
)
const EXPLOSION_WALL_DAMAGE_MULTIPLIER := 0.20
const EXPLOSION_TOOL_DAMAGE_MULTIPLIER := 0.50
const EXPLOSION_OCCLUSION_MASK := (
	COLLISION_LAYER_WALL
	| COLLISION_LAYER_TOOL
	| COLLISION_LAYER_BUILDING
	| COLLISION_LAYER_VEHICLES
	| COLLISION_LAYER_NATURE_RESOURCE
	| COLLISION_LAYER_WILD_ANIMAL
)
const FREE_PLACEMENT_BLOCKING_MASK := (
	COLLISION_LAYER_WALL
	| COLLISION_LAYER_CHARACTER
	| COLLISION_LAYER_TOOL
	| COLLISION_LAYER_BUILDING
	| COLLISION_LAYER_VEHICLES
	| COLLISION_LAYER_WILD_ANIMAL
)
const FREE_PLACEMENT_MAX_SLOPE_DEGREES := 5.0
# The clearance shape expands 0.15 m beyond the source CollisionShape on every side.
const FREE_PLACEMENT_CLEARANCE := 0.15
const FREE_PLACEMENT_GROUND_RAY_ABOVE := 20.0
const FREE_PLACEMENT_GROUND_RAY_BELOW := 48.0
const REMOTE_CONTROL_LOST_EFFECTIVE_SIGNAL := 0.20
const REMOTE_RECONNECT_MIN_EFFECTIVE_SIGNAL := 0.25
const REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL := 0.20
const REMOTE_CONTROLLED_DEVICE_TYPES := {
	"action_drone": true,
	"normal_drone": true,
	"tech_drone": true,
	"small_mouse": true,
	"boom_buggy": true,
}
const DEFAULT_COMBAT_RAYCAST_MASK := (
	COLLISION_LAYER_GROUND
	| COLLISION_LAYER_WALL
	| COLLISION_LAYER_CHARACTER
	| COLLISION_LAYER_FARM_TILE
	| COLLISION_LAYER_TOOL
	| COLLISION_LAYER_BUILDING
	| COLLISION_LAYER_VEHICLES
	| COLLISION_LAYER_NATURE_RESOURCE
	| COLLISION_LAYER_WILD_ANIMAL
)
const PROJECTILE_COLLISION_MASK_BY_TYPE := {
	# These values mirror the collision_mask on the corresponding editor scenes.
	"boom": 20481 | COLLISION_LAYER_WILD_ANIMAL,
	"drone_bomb": 20481 | COLLISION_LAYER_WILD_ANIMAL,
	"auto_shooter_boom": 20481 | COLLISION_LAYER_WILD_ANIMAL,
	"bug_boom": 16387,
	"medicine_boom": 16387,
	"spicy_bullet": COLLISION_LAYER_GROUND,
	"wheat_sentry_bullet": 20480 | COLLISION_LAYER_WILD_ANIMAL,
	"grenade": COLLISION_LAYER_GROUND | COLLISION_LAYER_WALL | COLLISION_LAYER_FARM_TILE \
		| COLLISION_LAYER_TOOL | COLLISION_LAYER_BUILDING | COLLISION_LAYER_VEHICLES \
		| COLLISION_LAYER_NATURE_RESOURCE | COLLISION_LAYER_WILD_ANIMAL,
	"vehicle_shield_laser": DEFAULT_COMBAT_RAYCAST_MASK,
}

var mode := MODE_DISABLED
var server_manager: Node
var local_player_id := LOCAL_PLAYER_ID
var tick_accumulator := 0.0
var server_tick := 0
var low_freq_snapshot_accumulator := 0.0
var nature_resource_reconcile_accumulator := 0.0
var farm_reconcile_accumulator := 0.0
var low_freq_snapshot_cache: Dictionary = {}
var player_physics_nodes: Dictionary = {}
var authoritative_tool_cooldowns: Dictionary = {}
var authoritative_tool_definitions: Dictionary = {}
var free_placement_debug_enabled := true

# 高频状态：30Hz 快照同步，主要用于插值/校正。
var player_states: Dictionary = {}
var latest_inputs: Dictionary = {}
var projectile_states: Dictionary = {}
var local_projectile_visual_nodes: Dictionary = {}
var medicine_storm_states: Dictionary = {}
var next_projectile_id := 1
var next_medicine_storm_id := 1
var next_visual_projectile_id := 1
var next_absorption_visual_id := 1
var next_hit_confirmation_id := 1
var next_dynamic_vehicle_id := 1
var next_dropped_item_id := 1
var next_livestock_id := 1
var remote_device_states: Dictionary = {}
var placed_tool_states: Dictionary = {}
var rift_anchor_by_peer: Dictionary = {}
var dropped_item_nodes: Dictionary = {}
var chat_submission_times_msec: Dictionary = {}
var vehicle_states: Dictionary = {}
var cargo_car_respawn_states: Dictionary = {}
var pending_farm_tile_deltas: Dictionary = {}
var pending_farm_reconcile_chunks: Array = []
var farm_reconcile_states: Dictionary = {}
var farm_reconcile_cycle := 0
var local_match_elapsed_seconds := 0.0
var local_match_finished := false

# 低频/可靠状态：农田、库存、比分、工具放置等更适合事件同步或低频纠偏。
var authoritative_farm_events: Array[Dictionary] = []

# 性能指标：DedicatedServerManager 和 StatusQueryServer 都可以读取这里的统计。
var tick_samples_ms: Array[float] = []
var ticks_this_second := 0
var snapshots_this_second := 0
var bytes_sent_this_second := 0
var bytes_received_this_second := 0
var measured_tick_rate := 0.0
var measured_snapshot_rate := 0.0
var measured_bytes_sent_per_second := 0
var measured_bytes_received_per_second := 0
var metrics_second_accumulator := 0.0
var last_snapshot: Dictionary = {}
var debug_print_metrics_interval := 10.0
var debug_print_metrics_left := 10.0


func _ready() -> void:
	# CharacterBody3D.move_and_slide() must run from the engine physics loop.
	# Running a 30 Hz custom loop from _process made the server body advance using
	# the engine's 60 Hz physics delta only every other frame.
	set_process(false)
	set_physics_process(true)
	_load_authoritative_tool_cooldowns()
	if not GlobalVar.team_money_changed.is_connected(_on_team_money_changed):
		GlobalVar.team_money_changed.connect(_on_team_money_changed)
	if not GlobalVar.team_score_changed.is_connected(_on_team_score_changed):
		GlobalVar.team_score_changed.connect(_on_team_score_changed)


func _on_team_money_changed(team: String, delta: float, new_amount: float) -> void:
	if (not is_server_authority() and not is_local_authority()) or is_zero_approx(delta):
		return
	reliable_world_event_ready.emit({
		"type": "team_money_changed",
		"team": team,
		"delta": delta,
		"new_amount": new_amount,
		"tick": server_tick,
	})


func _on_team_score_changed(team: String, delta: float, new_score: float) -> void:
	if (not is_server_authority() and not is_local_authority()) or is_zero_approx(delta):
		return
	reliable_world_event_ready.emit({
		"type": "team_score_changed",
		"team": team,
		"delta": delta,
		"new_score": new_score,
		"tick": server_tick,
	})


func _load_authoritative_tool_cooldowns() -> void:
	authoritative_tool_cooldowns.clear()
	authoritative_tool_definitions.clear()
	var file := FileAccess.open(TOOL_DEFINITIONS_PATH, FileAccess.READ)
	if file == null:
		push_error("Unable to load authoritative tool definitions: " + TOOL_DEFINITIONS_PATH)
		return
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not json.data is Dictionary:
		push_error("Invalid authoritative tool definitions: " + TOOL_DEFINITIONS_PATH)
		return
	var tools_value: Variant = (json.data as Dictionary).get("tools", [])
	if not tools_value is Array:
		push_error("Tool definitions must contain a tools array.")
		return
	for tool_value: Variant in tools_value:
		if not tool_value is Dictionary:
			continue
		var tool := tool_value as Dictionary
		var tool_id := str(tool.get("id", ""))
		if tool_id.is_empty():
			continue
		authoritative_tool_cooldowns[tool_id] = maxf(0.0, float(tool.get("cooldown", 1.0)))
		authoritative_tool_definitions[tool_id] = tool.duplicate(true)


func start_server_mode(manager: Node = null) -> void:
	mode = MODE_SERVER
	server_manager = manager
	GlobalVar.reset_team_storage()
	_reset_runtime_state()


func start_local_mode(selection: Dictionary = {}) -> void:
	mode = MODE_LOCAL
	server_manager = null
	GlobalVar.reset_team_storage()
	_reset_runtime_state()
	if not selection.is_empty():
		register_or_update_player(LOCAL_PLAYER_ID, selection)


func start_client_mode() -> void:
	mode = MODE_CLIENT
	server_manager = null
	GlobalVar.apply_team_scores({"red": 0, "blue": 0}, true)
	_reset_runtime_state(false)


func stop_authority() -> void:
	mode = MODE_DISABLED
	server_manager = null
	_reset_runtime_state()


func is_server_authority() -> bool:
	return mode == MODE_SERVER


func is_local_authority() -> bool:
	return mode == MODE_LOCAL


func is_client_proxy() -> bool:
	return mode == MODE_CLIENT


func should_send_network_requests() -> bool:
	return mode == MODE_CLIENT and (
		MultiplayerNetwork.is_connected_to_game_server() or CooperativeSession.is_client()
	)


func set_metrics_print_interval(seconds: float) -> void:
	debug_print_metrics_interval = maxf(0.0, seconds)
	debug_print_metrics_left = debug_print_metrics_interval


func enable_metrics_periodic_log(enabled: bool, seconds: float = 10.0) -> void:
	if enabled:
		set_metrics_print_interval(seconds)
	else:
		set_metrics_print_interval(0.0)


func _reset_runtime_state(clear_players := true) -> void:
	tick_accumulator = 0.0
	server_tick = 0
	low_freq_snapshot_accumulator = 0.0
	nature_resource_reconcile_accumulator = 0.0
	farm_reconcile_accumulator = 0.0
	low_freq_snapshot_cache.clear()
	_clear_player_physics_nodes()
	latest_inputs.clear()
	for visual_value: Variant in local_projectile_visual_nodes.values():
		if is_instance_valid(visual_value):
			(visual_value as Node).queue_free()
	local_projectile_visual_nodes.clear()
	projectile_states.clear()
	medicine_storm_states.clear()
	next_projectile_id = 1
	next_medicine_storm_id = 1
	next_visual_projectile_id = 1
	next_absorption_visual_id = 1
	next_hit_confirmation_id = 1
	next_dropped_item_id = 1
	next_livestock_id = 1
	_clear_dropped_items()
	chat_submission_times_msec.clear()
	remote_device_states.clear()
	placed_tool_states.clear()
	rift_anchor_by_peer.clear()
	vehicle_states.clear()
	cargo_car_respawn_states.clear()
	pending_farm_tile_deltas.clear()
	pending_farm_reconcile_chunks.clear()
	farm_reconcile_states.clear()
	farm_reconcile_cycle = 0
	local_match_elapsed_seconds = 0.0
	local_match_finished = false
	authoritative_farm_events.clear()
	last_snapshot.clear()
	tick_samples_ms.clear()
	ticks_this_second = 0
	snapshots_this_second = 0
	bytes_sent_this_second = 0
	bytes_received_this_second = 0
	measured_tick_rate = 0.0
	measured_snapshot_rate = 0.0
	measured_bytes_sent_per_second = 0
	measured_bytes_received_per_second = 0
	metrics_second_accumulator = 0.0
	debug_print_metrics_left = debug_print_metrics_interval
	var event_board := get_node_or_null("/root/EventBoard")
	if event_board != null and event_board.has_method("reset"):
		event_board.call("reset")
	if clear_players:
		player_states.clear()


func _physics_process(delta: float) -> void:
	if mode != MODE_SERVER and mode != MODE_LOCAL:
		return
	low_freq_snapshot_accumulator += delta
	nature_resource_reconcile_accumulator += delta
	farm_reconcile_accumulator += delta
	metrics_second_accumulator += delta
	if mode == MODE_LOCAL and not local_match_finished:
		local_match_elapsed_seconds += delta
		if local_match_elapsed_seconds >= LOCAL_MATCH_DURATION_SECONDS:
			_finish_local_match_due_to_time_limit()
			return
	if local_match_finished:
		return
	_run_authority_tick(delta)
	if metrics_second_accumulator >= 1.0:
		_roll_metrics_second()
	if mode == MODE_SERVER and debug_print_metrics_interval > 0.0:
		debug_print_metrics_left -= delta
		if debug_print_metrics_left <= 0.0:
			debug_print_metrics_left = debug_print_metrics_interval
			print_server_metrics()


func _finish_local_match_due_to_time_limit() -> void:
	if local_match_finished:
		return
	local_match_finished = true
	reliable_world_event_ready.emit({
		"type": "match_ended",
		"reason": "time_limit",
		"settlement": {
			"scores": GlobalVar.get_team_scores(),
			"money": {
				"red": int(round(GlobalVar.check_team_item_amount("red", "money"))),
				"blue": int(round(GlobalVar.check_team_item_amount("blue", "money"))),
			},
			"stats": GlobalVar.get_all_team_match_stats(),
		},
		"tick": server_tick,
	})
func _run_authority_tick(delta: float) -> void:
	var simulation_delta := TARGET_TICK_INTERVAL
	var tick_start := Time.get_ticks_usec()
	server_tick += 1
	_register_world_vehicles()
	_simulate_cargo_garages(simulation_delta)
	_simulate_vehicles(simulation_delta)
	_simulate_players(simulation_delta)
	_simulate_remote_devices(simulation_delta)
	_update_remote_device_link_quality()
	_simulate_projectiles(simulation_delta)
	_simulate_medicine_storms(simulation_delta)
	_simulate_placed_tools(simulation_delta)
	_reserve_ready_ingredient_pickups()
	_release_invalid_kitchen_users()
	_flush_farm_tile_deltas()
	_flush_next_farm_reconcile_chunk()
	if low_freq_snapshot_accumulator >= LOW_FREQ_SNAPSHOT_INTERVAL:
		low_freq_snapshot_accumulator = 0.0
		var include_nature_resources := nature_resource_reconcile_accumulator >= NATURE_RESOURCE_RECONCILE_INTERVAL
		if include_nature_resources:
			nature_resource_reconcile_accumulator = 0.0
		low_freq_snapshot_cache = _build_low_frequency_snapshot(include_nature_resources)
		reliable_world_event_ready.emit({
			"type": "low_frequency_snapshot",
			"data": low_freq_snapshot_cache,
			"tick": server_tick,
		})
	if farm_reconcile_accumulator >= FARM_RECONCILE_INTERVAL:
		farm_reconcile_accumulator = 0.0
		_queue_farm_reconcile_chunks()
	if server_tick % WORLD_SNAPSHOT_TICK_INTERVAL == 0:
		var snapshot := _build_world_snapshot()
		last_snapshot = snapshot
		snapshots_this_second += 1
		bytes_sent_this_second += _estimate_world_snapshot_bytes(snapshot)
		world_snapshot_ready.emit(snapshot)
	ticks_this_second += 1
	var tick_ms := float(Time.get_ticks_usec() - tick_start) / 1000.0
	tick_samples_ms.append(tick_ms)
	if tick_samples_ms.size() > METRICS_SAMPLE_LIMIT:
		tick_samples_ms.pop_front()


func _simulate_players(delta: float) -> void:
	for raw_peer_id in player_states.keys():
		var peer_id := int(raw_peer_id)
		var state: Dictionary = player_states[peer_id]
		_tick_weapon_reloads(peer_id, state, delta)
		state["labeled_remaining"] = maxf(
			0.0, float(state.get("labeled_remaining", 0.0)) - delta
		)
		var respawn_left := float(state.get("respawn_left", 0.0))
		if respawn_left > 0.0:
			respawn_left = maxf(0.0, respawn_left - delta)
			state["respawn_left"] = respawn_left
			state["velocity"] = Vector3.ZERO
			state["knockback_velocity"] = Vector3.ZERO
			player_states[peer_id] = state
			if respawn_left <= 0.0:
				_respawn_player(peer_id)
			continue
		var capture_remaining := float(state.get("big_mouth_capture_remaining", 0.0))
		if capture_remaining > 0.0:
			var anchor := _vector3_from_value(state.get("big_mouth_anchor", state.get("position", Vector3.ZERO)))
			var pull_remaining := maxf(0.0, float(state.get("big_mouth_pull_remaining", 0.0)) - delta)
			var position := _vector3_from_value(state.get("position", anchor))
			if pull_remaining > 0.0:
				position = position.lerp(anchor, clampf(delta * 16.0, 0.0, 1.0))
			else:
				position = anchor
			capture_remaining = maxf(0.0, capture_remaining - delta)
			state["big_mouth_capture_remaining"] = capture_remaining
			state["big_mouth_pull_remaining"] = pull_remaining
			state["position"] = position
			state["velocity"] = Vector3.ZERO
			state["knockback_velocity"] = Vector3.ZERO
			state["locomotion_state"] = "idle"
			player_states[peer_id] = state
			if mode == MODE_SERVER:
				var proxy := _ensure_player_physics_node(peer_id, position)
				proxy.global_position = position
				proxy.velocity = Vector3.ZERO
			if capture_remaining <= 0.0:
				release_big_mouth_capture(peer_id, "timeout")
			continue
		var vehicle_id := str(state.get("vehicle_id", ""))
		if not vehicle_id.is_empty():
			var vehicle := _find_vehicle(vehicle_id)
			var seat_index := int(state.get("vehicle_seat_index", -1))
			if vehicle != null and vehicle.get_seat_index_for_peer(peer_id) == seat_index:
				_sync_occupied_player_state(peer_id, state, vehicle)
				continue
			state["vehicle_id"] = ""
			state["vehicle_seat_index"] = -1
			_set_server_player_vehicle_collision(peer_id, false)
		var spicy_remaining := float(state.get("spicy_remaining", 0.0))
		if mode == MODE_SERVER and spicy_remaining > 0.0:
			var spicy_tick := minf(delta, spicy_remaining)
			var spicy_damage := maxf(0.0, float(state.get("spicy_dps", 0.0))) * spicy_tick
			state["spicy_remaining"] = maxf(0.0, spicy_remaining - delta)
			state["hp"] = maxf(0.0, float(state.get("hp", PLAYER_MAX_HP)) - spicy_damage)
			if spicy_damage > 0.0:
				reliable_world_event_ready.emit({
					"type": "player_damaged",
					"peer_id": peer_id,
					"damage": spicy_damage,
					"hp": state["hp"],
					"knockback": 0.0,
					"direction": Vector3.ZERO,
					"effect": "spicy",
					"tick": server_tick,
				})
			if float(state["hp"]) <= 0.0:
				player_states[peer_id] = state
				_begin_player_respawn(peer_id)
				continue
		var input: Dictionary = latest_inputs.get(peer_id, {})
		var move := _vector2_from_value(input.get("move", Vector2.ZERO))
		var prone := bool(input.get("prone", state.get("prone", false)))
		state["prone"] = prone
		var yaw := wrapf(float(input.get("yaw", state.get("yaw", 0.0))), -PI, PI)
		var pitch_limit := PLAYER_PRONE_MAX_PITCH_DEGREES if prone else 50.0
		var pitch := clampf(float(input.get("pitch", state.get("pitch", 0.0))), deg_to_rad(-pitch_limit), deg_to_rad(pitch_limit))
		var speed := float(state.get("speed", 5.0)) * EquipmentCatalog.get_movement_speed_multiplier(
			str(state.get("equipped_legwear_id", ""))
		)
		speed *= PLAYER_PRONE_SPEED_MULTIPLIER if prone else 1.0
		var position := _vector3_from_value(state.get("position", Vector3.ZERO))
		var velocity := _vector3_from_value(state.get("velocity", Vector3.ZERO))
		var knockback_velocity := _vector3_from_value(state.get("knockback_velocity", Vector3.ZERO))
		knockback_velocity.y = 0.0
		var was_grounded := bool(state.get("grounded", true))
		var grounded := velocity.y == 0.0
		if move.length() > 1.0:
			move = move.normalized()
		if mode == MODE_SERVER:
			var proxy := _ensure_player_physics_node(peer_id, position)
			if proxy == null:
				player_states[peer_id] = state
				continue
			_set_server_player_prone_collision(proxy, prone)
			var basis := Basis(Vector3.UP, yaw)
			var direction := (basis * Vector3(move.x, 0.0, move.y)).normalized()
			if not proxy.is_on_floor():
				proxy.velocity += proxy.get_gravity() * delta
			proxy.rotation.y = yaw
			var jump_sequence := int(input.get("jump_seq", state.get("last_jump_seq", 0)))
			var last_jump_sequence := int(state.get("last_jump_seq", 0))
			var jump_requested := jump_sequence > last_jump_sequence
			if jump_requested and int(state.get("pending_jump_seq", -1)) != jump_sequence:
				state["pending_jump_seq"] = jump_sequence
				state["pending_jump_until_tick"] = server_tick + PLAYER_JUMP_GRACE_TICKS
			# is_on_floor() can briefly become false when the input and server physics
			# ticks straddle the floor-contact update. The previous authoritative
			# grounded state provides one tick of jump grace without trusting clients.
			var jump_accepted := jump_requested and not prone \
				and (proxy.is_on_floor() or was_grounded)
			if jump_accepted:
				proxy.velocity.y = 3.0
			proxy.velocity.x = direction.x * speed + knockback_velocity.x
			proxy.velocity.z = direction.z * speed + knockback_velocity.z
			proxy.move_and_slide()
			position = proxy.global_position
			velocity = proxy.velocity
			grounded = proxy.is_on_floor()
			# Consume a jump only after it was actually applied. Otherwise the client
			# predicts a jump that the next correction incorrectly erases mid-air.
			if jump_accepted:
				state["last_jump_seq"] = jump_sequence
				state.erase("pending_jump_seq")
				state.erase("pending_jump_until_tick")
			elif jump_requested and server_tick >= int(state.get("pending_jump_until_tick", server_tick)):
				state["last_jump_seq"] = jump_sequence
				state.erase("pending_jump_seq")
				state.erase("pending_jump_until_tick")
		else:
			var basis := Basis(Vector3.UP, yaw)
			var direction := (basis * Vector3(move.x, 0.0, move.y)).normalized()
			velocity.x = direction.x * speed + knockback_velocity.x
			velocity.z = direction.z * speed + knockback_velocity.z
			position += velocity * delta
		knockback_velocity = knockback_velocity.move_toward(Vector3.ZERO, PLAYER_KNOCKBACK_DECELERATION * delta)
		state["position"] = position
		state["velocity"] = velocity
		state["knockback_velocity"] = knockback_velocity
		state["yaw"] = yaw
		state["pitch"] = pitch
		state["grounded"] = grounded
		state["locomotion_state"] = _locomotion_state_for(state, move)
		state["last_input_seq"] = int(input.get("input_seq", state.get("last_input_seq", 0)))
		var cooldowns: Dictionary = state.get("tool_cooldowns", {})
		for tool_id in cooldowns.keys():
			cooldowns[tool_id] = maxf(0.0, float(cooldowns[tool_id]) - delta)
		state["tool_cooldowns"] = cooldowns
		player_states[peer_id] = state
		if server_tick % PLAYER_CORRECTION_TICK_INTERVAL == 0:
			player_correction_ready.emit(peer_id, _make_player_correction(peer_id))


func apply_spicy_shape_cast_hit(collider: Variant, source_team: String, damage: float) -> void:
	if not is_server_authority():
		return
	var peer_id := _peer_id_for_player_physics_collider(collider)
	if peer_id == 0 or not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0 or str(state.get("team", "")) == source_team:
		return
	state["spicy_remaining"] = maxf(0.0, CombatBalance.get_float("spicy_blaster", "spicy_duration"))
	state["spicy_dps"] = maxf(0.0, damage)
	player_states[peer_id] = state


func _peer_id_for_player_physics_collider(collider: Variant) -> int:
	if not collider is Node:
		return 0
	var cursor := collider as Node
	for _depth in range(6):
		if cursor == null:
			return 0
		for raw_peer_id in player_physics_nodes.keys():
			if player_physics_nodes[raw_peer_id] == cursor:
				return int(raw_peer_id)
		cursor = cursor.get_parent()
	return 0


func register_or_update_player(peer_id: int, selection: Dictionary) -> void:
	var existing: Dictionary = player_states.get(peer_id, {})
	existing["peer_id"] = peer_id
	existing["display_name"] = selection.get("display_name", existing.get("display_name", "Player_%d" % peer_id))
	existing["team"] = selection.get("team", existing.get("team", ""))
	existing["hero_id"] = selection.get("hero_id", selection.get("character_id", existing.get("hero_id", "")))
	existing["primary_weapon_ids"] = selection.get("primary_weapon_ids", existing.get("primary_weapon_ids", []))
	existing["special_tool_ids"] = selection.get("special_tool_ids", existing.get("special_tool_ids", []))
	existing["position"] = selection.get("position", existing.get("position", Vector3.ZERO))
	existing["velocity"] = existing.get("velocity", Vector3.ZERO)
	existing["knockback_velocity"] = existing.get("knockback_velocity", Vector3.ZERO)
	existing["yaw"] = float(existing.get("yaw", 0.0))
	existing["pitch"] = float(existing.get("pitch", 0.0))
	existing["prone"] = bool(existing.get("prone", false))
	existing["hp"] = float(existing.get("hp", PLAYER_MAX_HP))
	existing["current_tool_index"] = int(existing.get("current_tool_index", 0))
	existing["current_tool_id"] = str(existing.get("current_tool_id", ""))
	existing["personal_ingredients"] = existing.get("personal_ingredients", {})
	existing["personal_dishes"] = existing.get("personal_dishes", {})
	existing["personal_dish_weights"] = existing.get("personal_dish_weights", {})
	existing["personal_cargo_crates"] = existing.get("personal_cargo_crates", [])
	existing["owned_equipment_ids"] = existing.get("owned_equipment_ids", [])
	existing["equipment_hp"] = _initialize_equipment_hp(
		existing.get("equipment_hp", {}),
		existing["owned_equipment_ids"]
	)
	existing["equipped_backpack_id"] = str(existing.get("equipped_backpack_id", ""))
	existing["equipped_chest_armor_id"] = str(existing.get("equipped_chest_armor_id", ""))
	existing["equipped_legwear_id"] = str(existing.get("equipped_legwear_id", ""))
	if not existing.has("backpack_slot_items"):
		existing["backpack_slot_items"] = _build_initial_backpack_layout(existing)
	existing["backpack_layout_valid"] = bool(existing.get("backpack_layout_valid", true))
	existing["tool_cooldowns"] = existing.get("tool_cooldowns", {})
	existing["weapon_ammo_states"] = _initialize_weapon_ammo_states(
		existing.get("weapon_ammo_states", {}),
		existing.get("primary_weapon_ids", []),
		existing.get("special_tool_ids", [])
	)
	existing["last_input_seq"] = int(existing.get("last_input_seq", 0))
	existing["last_received_input_seq"] = int(existing.get("last_received_input_seq", 0))
	existing["last_jump_seq"] = int(existing.get("last_jump_seq", 0))
	existing["speed"] = float(existing.get("speed", 5.0))
	existing["spawn_position"] = selection.get(
		"position",
		existing.get("spawn_position", existing["position"])
	)
	existing["respawn_left"] = float(existing.get("respawn_left", 0.0))
	existing["labeled_remaining"] = float(existing.get("labeled_remaining", 0.0))
	existing["vehicle_id"] = str(existing.get("vehicle_id", ""))
	existing["vehicle_seat_index"] = int(existing.get("vehicle_seat_index", -1))
	player_states[peer_id] = existing
	if mode == MODE_SERVER:
		var proxy := _ensure_player_physics_node(peer_id, _vector3_from_value(existing.get("position", Vector3.ZERO)))
		if selection.has("position") and is_instance_valid(proxy):
			proxy.global_position = _vector3_from_value(existing.get("position", Vector3.ZERO))
			proxy.velocity = _vector3_from_value(existing.get("velocity", Vector3.ZERO))


func unregister_player(peer_id: int) -> void:
	if player_states.has(peer_id):
		_force_release_kitchen_user(peer_id)
		release_big_mouth_capture(peer_id, "disconnected")
	_destroy_rift_anchor_for_peer(peer_id)
	_remove_player_from_vehicle(peer_id, false)
	player_states.erase(peer_id)
	latest_inputs.erase(peer_id)
	chat_submission_times_msec.erase(peer_id)
	var proxy: Node = player_physics_nodes.get(peer_id, null)
	if is_instance_valid(proxy):
		proxy.queue_free()
	player_physics_nodes.erase(peer_id)


func grant_test_backpack_entries_to_all(entries: Array) -> bool:
	if not is_local_authority() and not is_server_authority():
		return false
	if entries.is_empty() or player_states.is_empty():
		return false
	for peer_id_value in player_states.keys():
		var peer_id := int(peer_id_value)
		var state: Dictionary = player_states[peer_id]
		var granted_entries: Array[Dictionary] = []
		for entry_value: Variant in entries:
			if not entry_value is Dictionary:
				continue
			var granted := _grant_test_backpack_entry(state, entry_value as Dictionary)
			if not granted.is_empty():
				granted_entries.append(granted)
		player_states[peer_id] = state
		if granted_entries.is_empty():
			continue
		if mode == MODE_LOCAL:
			_apply_test_backpack_grant_to_local_player(peer_id, granted_entries)
		else:
			reliable_world_event_ready.emit({
				"type": "backpack_test_grant",
				"peer_id": peer_id,
				"entries": granted_entries,
				"tick": server_tick,
			})
	return true


func local_team_chat(peer_id: int, message: String, scope := "team") -> Dictionary:
	return server_team_chat(peer_id, message, scope)


func server_team_chat(peer_id: int, raw_message: String, requested_scope := "team") -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	if team.is_empty():
		result["reason"] = "missing_team"
		return result
	var message := raw_message.strip_edges().substr(0, MAX_CHAT_MESSAGE_CHARACTERS)
	if message.is_empty():
		result["reason"] = "empty_message"
		return result
	if not _consume_chat_rate_slot(peer_id):
		result["reason"] = "chat_rate_limited"
		_emit_team_chat_system(peer_id, state, "发送过快：1 秒内最多发送 5 条消息。")
		return result
	if message.begins_with("[get]"):
		return _server_debug_get_tool(peer_id, state, message)
	var scope := "all" if requested_scope == "all" else "team"
	var chat_message := {
		"scope": scope,
		"team": team,
		"sender_peer_id": peer_id,
		"sender_name": str(state.get("display_name", "Player_%d" % peer_id)),
		"text": message,
		"system": false,
		"tick": server_tick,
	}
	team_chat_message_ready.emit(chat_message)
	result["ok"] = true
	result["message"] = chat_message
	return result


func _consume_chat_rate_slot(peer_id: int) -> bool:
	var now_msec := Time.get_ticks_msec()
	var timestamps: Array = chat_submission_times_msec.get(peer_id, [])
	var oldest_allowed := now_msec - CHAT_RATE_WINDOW_MSEC
	while not timestamps.is_empty() and int(timestamps.front()) <= oldest_allowed:
		timestamps.pop_front()
	if timestamps.size() >= MAX_CHAT_MESSAGES_PER_SECOND:
		chat_submission_times_msec[peer_id] = timestamps
		return false
	timestamps.append(now_msec)
	chat_submission_times_msec[peer_id] = timestamps
	return true


func _server_debug_get_tool(peer_id: int, state: Dictionary, command: String) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "command": "get", "tick": server_tick}
	var arguments := command.trim_prefix("[get]").strip_edges().trim_suffix(".").strip_edges()
	var parts := arguments.split(" ", false)
	if parts.size() != 2 or not str(parts[1]).is_valid_int():
		result["reason"] = "invalid_get_syntax"
		_emit_team_chat_system(peer_id, state, "用法：[get] <item_id> <item_count>，数量必须是正整数")
		return result
	var requested_id := str(parts[0]).strip_edges()
	var item_count := int(parts[1])
	if requested_id.is_empty() or item_count <= 0:
		result["reason"] = "invalid_get_count"
		_emit_team_chat_system(peer_id, state, "item_count 必须是大于 0 的整数")
		return result
	result["item_id"] = requested_id
	result["item_count"] = item_count
	var crate_size := CargoCrateData.get_size_for_item_id(requested_id)
	if not crate_size.is_empty():
		var sample_crate := CargoCrateData.create_empty(crate_size)
		var total_crate_weight := float(sample_crate.get("total_weight_kg", 0.0)) * float(item_count)
		if _server_backpack_entry_count(state) + item_count > _server_bag_capacity(state):
			result["reason"] = "personal_bag_full"
			_emit_team_chat_system(peer_id, state, "背包格子不足，无法添加 %d 个 %s" % [item_count, requested_id], true)
			return result
		if _personal_ingredient_total_weight(state) + total_crate_weight \
				> _server_bag_weight_capacity_kg(state) + 0.001:
			result["reason"] = "personal_bag_overweight"
			_emit_team_chat_system(peer_id, state, "背包载重不足，无法添加 %d 个 %s" % [item_count, requested_id], true)
			return result
		var crates: Array[Dictionary] = []
		for _index in range(item_count):
			var crate := CargoCrateData.create_empty(crate_size)
			_add_personal_cargo_crate(state, crate)
			_server_layout_add_item(state, crate)
			crates.append(crate)
		player_states[peer_id] = state
		_emit_debug_backpack_grant(peer_id, crates)
		_emit_team_chat_system(peer_id, state, "已获得 %s × %d（%s）" % [
			str(sample_crate.get("display_name", requested_id)), item_count, requested_id,
		])
		result["ok"] = true
		result["crates"] = crates.duplicate(true)
		return result
	var equipment_definition := EquipmentCatalog.get_definition(requested_id)
	var ingredient_definition := IngredientCatalog.get_definition(requested_id)
	if not ingredient_definition.is_empty():
		var unit_weight_kg := IngredientCatalog.get_pickup_unit_kg(requested_id)
		var weight_kg := unit_weight_kg * float(item_count)
		if not _server_can_add_personal_ingredient(state, requested_id, weight_kg, false):
			var overweight := _personal_ingredient_total_weight(state) + weight_kg \
					> _server_bag_weight_capacity_kg(state) + 0.001
			result["reason"] = "personal_bag_overweight" if overweight else "personal_bag_full"
			_emit_team_chat_system(peer_id, state, (
				"背包载重不足，无法添加 %s" if overweight else "背包已满，无法添加 %s"
			) % requested_id, true)
			return result
		var ingredient_entry := {
			"kind": "ingredient", "ingredient_id": requested_id,
			"weight_kg": weight_kg, "is_chopped": false,
		}
		_server_add_personal_ingredient(state, requested_id, weight_kg, false)
		player_states[peer_id] = state
		_emit_debug_backpack_grant(peer_id, [ingredient_entry])
		_emit_team_chat_system(peer_id, state, "已获得 %s %.2f kg（%d × %.2f kg，%s）" % [
			str(ingredient_definition.get("display_name", requested_id)), weight_kg,
			item_count, unit_weight_kg, requested_id,
		])
		result["ok"] = true
		result["item_id"] = requested_id
		result["ingredient"] = ingredient_entry.duplicate(true)
		return result
	var dish_definition := DishCatalog.get_definition(requested_id)
	if not dish_definition.is_empty():
		var serving_unit_weight := float(dish_definition.get("serving_weight_kg", 0.0))
		var serving_weight := serving_unit_weight * float(item_count)
		if not _server_can_add_personal_dish(state, requested_id, item_count, serving_weight):
			var overweight := _personal_ingredient_total_weight(state) + serving_weight \
					> _server_bag_weight_capacity_kg(state) + 0.001
			result["reason"] = "personal_bag_overweight" if overweight else "personal_bag_full"
			_emit_team_chat_system(peer_id, state, (
				"背包载重不足，无法添加 %s" if overweight else "背包已满，无法添加 %s"
			) % requested_id, true)
			return result
		var dish_entry := {
			"kind": "dish", "dish_id": requested_id,
			"servings": item_count, "weight_kg": serving_weight,
		}
		_server_add_personal_dish(state, requested_id, item_count, serving_weight)
		player_states[peer_id] = state
		_emit_debug_backpack_grant(peer_id, [dish_entry])
		_emit_team_chat_system(peer_id, state, "已获得 %s %d份（%s）" % [
			str(dish_definition.get("display_name", requested_id)), item_count, requested_id,
		])
		result["ok"] = true
		result["item_id"] = requested_id
		result["dish"] = dish_entry.duplicate(true)
		return result
	if not authoritative_tool_definitions.has(requested_id) and equipment_definition.is_empty():
		result["reason"] = "unknown_tool"
		_emit_team_chat_system(peer_id, state, "未找到物品：%s" % requested_id)
		return result
	if not equipment_definition.is_empty():
		var owned_equipment: Array = state.get("owned_equipment_ids", [])
		if item_count != 1 or owned_equipment.has(requested_id):
			result["reason"] = "already_owned"
			_emit_team_chat_system(peer_id, state, "该装备只能拥有一个：%s" % requested_id)
			return result
		if _server_backpack_entry_count(state) >= _server_bag_capacity(state):
			result["reason"] = "personal_bag_full"
			_emit_team_chat_system(peer_id, state, "背包已满，无法添加 %s" % requested_id, true)
			return result
		owned_equipment.append(requested_id)
		state["owned_equipment_ids"] = owned_equipment
		_set_server_equipment_hp(state, requested_id, EquipmentCatalog.get_max_hp(requested_id))
		var equipment_entry := _server_equipment_item(state, requested_id)
		_server_layout_add_item(state, equipment_entry)
		player_states[peer_id] = state
		_emit_debug_backpack_grant(peer_id, [equipment_entry])
		_emit_team_chat_system(peer_id, state, "已获得 %s（%s）" % [str(equipment_definition.get("name", requested_id)), requested_id])
		result["ok"] = true
		result["equipment_id"] = requested_id
		return result
	var allows_multiple := _tool_allows_multiple(requested_id)
	if not allows_multiple and (item_count > 1 or _player_has_tool(state, requested_id)):
		result["reason"] = "already_owned"
		_emit_team_chat_system(peer_id, state, "该道具只能拥有一个：%s" % requested_id)
		return result
	if _server_backpack_entry_count(state) + item_count > _server_bag_capacity(state):
		result["reason"] = "personal_bag_full"
		_emit_team_chat_system(peer_id, state, "背包格子不足，无法添加 %d 个 %s" % [item_count, requested_id], true)
		return result
	var definition: Dictionary = authoritative_tool_definitions[requested_id]
	var requested_weight := float(definition.get("weight_kg", 0.0)) * float(item_count)
	if _personal_ingredient_total_weight(state) + requested_weight > _server_bag_weight_capacity_kg(state) + 0.001:
		result["reason"] = "personal_bag_overweight"
		_emit_team_chat_system(peer_id, state, "背包载重不足，无法添加 %d 个 %s" % [item_count, requested_id], true)
		return result
	var entries: Array[Dictionary] = []
	var tool_ids: Array = state.get("special_tool_ids", [])
	for _index in range(item_count):
		var entry := {
			"kind": "tool",
			"tool_id": requested_id,
			"weight_kg": float(definition.get("weight_kg", 0.0)),
		}
		if requested_id.begins_with("animal_"):
			entry["current_hp"] = 400.0 if requested_id != "animal_chicken" else 200.0
			entry["max_hp"] = entry["current_hp"]
			entry["growth_progress"] = 0.0
			entry["maturity_seconds"] = float(definition.get("maturity_seconds", 0.0))
			entry["livestock_instance_id"] = "stored:%d" % next_livestock_id
			next_livestock_id += 1
		if _uses_finite_ammo(requested_id):
			entry.merge(_default_weapon_ammo_state(requested_id), true)
		tool_ids.append(requested_id)
		_server_layout_add_item(state, entry)
		entries.append(entry)
	state["special_tool_ids"] = tool_ids
	if _uses_finite_ammo(requested_id):
		var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
		ammo_states[requested_id] = _default_weapon_ammo_state(requested_id)
		state["weapon_ammo_states"] = ammo_states
	player_states[peer_id] = state
	_emit_debug_backpack_grant(peer_id, entries)
	_emit_team_chat_system(
		peer_id,
		state,
		"已获得 %s × %d（%s）" % [str(definition.get("name", requested_id)), item_count, requested_id]
	)
	result["ok"] = true
	result["tool_id"] = requested_id
	return result


func _emit_debug_backpack_grant(peer_id: int, entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		return
	if mode == MODE_LOCAL:
		_apply_test_backpack_grant_to_local_player(peer_id, entries)
	else:
		reliable_world_event_ready.emit({
			"type": "backpack_test_grant", "peer_id": peer_id,
			"entries": entries, "tick": server_tick,
		})


func _server_backpack_entry_count(state: Dictionary) -> int:
	var entries := 0
	for bucket in ["primary_weapon_ids", "special_tool_ids"]:
		var values: Variant = state.get(bucket, [])
		if values is Array:
			for value: Variant in values:
				var tool_id := str(value)
				if not tool_id.is_empty():
					entries += 1
	var ingredients: Variant = state.get("personal_ingredients", {})
	if ingredients is Dictionary:
		for key: Variant in (ingredients as Dictionary).keys():
			if float((ingredients as Dictionary).get(key, 0.0)) > 0.0001:
				entries += 1
	var dishes: Variant = state.get("personal_dishes", {})
	if dishes is Dictionary:
		for key: Variant in (dishes as Dictionary).keys():
			if int((dishes as Dictionary).get(key, 0)) > 0:
				entries += 1
	var cargo_crates: Variant = state.get("personal_cargo_crates", [])
	if cargo_crates is Array:
		for crate: Variant in cargo_crates:
			if crate is Dictionary and not (crate as Dictionary).is_empty():
				entries += 1
	var equipped_ids := {
		str(state.get("equipped_backpack_id", "")): true,
		str(state.get("equipped_chest_armor_id", "")): true,
		str(state.get("equipped_legwear_id", "")): true,
	}
	equipped_ids.erase("")
	var equipment_ids: Variant = state.get("owned_equipment_ids", [])
	if equipment_ids is Array:
		for equipment_id_value: Variant in equipment_ids:
			if not equipped_ids.has(str(equipment_id_value)):
				entries += 1
	return entries


func _server_bag_capacity(state: Dictionary) -> int:
	var extra_slots := EquipmentCatalog.get_extra_slots(str(state.get("equipped_backpack_id", "")))
	if extra_slots < 0 or extra_slots > MAX_EQUIPMENT_EXTRA_SLOTS or extra_slots % BAG_SLOTS_PER_ROW != 0:
		extra_slots = 0
	return BASE_PLAYER_BAG_SLOTS + extra_slots


func _server_bag_weight_capacity_kg(state: Dictionary) -> float:
	return BASE_PERSONAL_BAG_WEIGHT_KG + EquipmentCatalog.get_extra_weight_kg(
		str(state.get("equipped_backpack_id", ""))
	)


func _build_initial_backpack_layout(state: Dictionary) -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	slots.resize(_server_bag_capacity(state))
	for index in range(slots.size()):
		slots[index] = {}
	var next_index := 0
	var seen := {}
	for bucket in ["primary_weapon_ids", "special_tool_ids"]:
		var values: Variant = state.get(bucket, [])
		if not values is Array:
			continue
		for value: Variant in values:
			var tool_id := str(value)
			if tool_id.is_empty() or (seen.has(tool_id) and not _tool_allows_multiple(tool_id)) \
					or next_index >= slots.size():
				continue
			slots[next_index] = {"kind": "tool", "tool_id": tool_id}
			seen[tool_id] = true
			next_index += 1
	return slots


func _server_layout_add_item(state: Dictionary, item: Dictionary) -> void:
	if not bool(state.get("backpack_layout_valid", false)):
		return
	var slots_value: Variant = state.get("backpack_slot_items", [])
	if not slots_value is Array or (slots_value as Array).size() != _server_bag_capacity(state):
		state["backpack_layout_valid"] = false
		return
	var slots: Array = (slots_value as Array).duplicate(true)
	var kind := str(item.get("kind", ""))
	if kind == "ingredient":
		for index in range(slots.size()):
			var existing: Dictionary = slots[index] if slots[index] is Dictionary else {}
			if str(existing.get("kind", "")) == "ingredient" \
					and str(existing.get("ingredient_id", "")) == str(item.get("ingredient_id", "")) \
					and bool(existing.get("is_chopped", false)) == bool(item.get("is_chopped", false)):
				existing["weight_kg"] = float(existing.get("weight_kg", 0.0)) + float(item.get("weight_kg", 0.0))
				slots[index] = existing
				state["backpack_slot_items"] = slots
				return
	elif kind == "dish":
		for index in range(slots.size()):
			var existing: Dictionary = slots[index] if slots[index] is Dictionary else {}
			if str(existing.get("kind", "")) == "dish" and str(existing.get("dish_id", "")) == str(item.get("dish_id", "")):
				existing["servings"] = int(existing.get("servings", 0)) + int(item.get("servings", 0))
				existing["weight_kg"] = float(existing.get("weight_kg", 0.0)) + float(item.get("weight_kg", 0.0))
				slots[index] = existing
				state["backpack_slot_items"] = slots
				return
	for index in range(slots.size()):
		if slots[index] is Dictionary and (slots[index] as Dictionary).is_empty():
			slots[index] = item.duplicate(true)
			state["backpack_slot_items"] = slots
			return
	state["backpack_layout_valid"] = false


func _server_layout_remove_item(state: Dictionary, item: Dictionary) -> void:
	if not bool(state.get("backpack_layout_valid", false)):
		return
	var slots_value: Variant = state.get("backpack_slot_items", [])
	if not slots_value is Array:
		state["backpack_layout_valid"] = false
		return
	var slots: Array = (slots_value as Array).duplicate(true)
	for index in range(slots.size()):
		var existing: Dictionary = slots[index] if slots[index] is Dictionary else {}
		if not _server_layout_items_match(existing, item):
			continue
		match str(item.get("kind", "")):
			"ingredient":
				var remaining_weight := float(existing.get("weight_kg", 0.0)) - float(item.get("weight_kg", 0.0))
				if remaining_weight > 0.001:
					existing["weight_kg"] = remaining_weight
					slots[index] = existing
				else:
					slots[index] = {}
			"dish":
				var remaining_servings := int(existing.get("servings", 0)) - int(item.get("servings", 0))
				var remaining_weight := float(existing.get("weight_kg", 0.0)) - float(item.get("weight_kg", 0.0))
				if remaining_servings > 0 and remaining_weight > 0.001:
					existing["servings"] = remaining_servings
					existing["weight_kg"] = remaining_weight
					slots[index] = existing
				else:
					slots[index] = {}
			_:
				slots[index] = {}
		state["backpack_slot_items"] = slots
		return
	state["backpack_layout_valid"] = false


func _server_layout_items_match(first: Dictionary, second: Dictionary) -> bool:
	var kind := str(second.get("kind", ""))
	if str(first.get("kind", "")) != kind and not (kind == "weapon" and str(first.get("kind", "")) == "tool"):
		return false
	match kind:
		"tool", "weapon": return str(first.get("tool_id", "")) == str(second.get("tool_id", ""))
		"equipment": return str(first.get("equipment_id", "")) == str(second.get("equipment_id", ""))
		"ingredient":
			return str(first.get("ingredient_id", "")) == str(second.get("ingredient_id", "")) \
					and bool(first.get("is_chopped", false)) == bool(second.get("is_chopped", false))
		"dish": return str(first.get("dish_id", "")) == str(second.get("dish_id", ""))
		"cargo_crate": return str(first.get("crate_instance_id", "")) == str(second.get("crate_instance_id", ""))
	return false


func _emit_team_chat_system(peer_id: int, state: Dictionary, text: String, show_notice := false) -> void:
	team_chat_message_ready.emit({
		"recipient_peer_id": peer_id,
		"team": str(state.get("team", "")),
		"text": text,
		"system": true,
		"show_notice": show_notice,
		"tick": server_tick,
	})


func _grant_test_backpack_entry(state: Dictionary, entry: Dictionary) -> Dictionary:
	var kind := str(entry.get("kind", "")).strip_edges().to_lower()
	match kind:
		"tool":
			var tool_id := str(entry.get("tool_id", entry.get("id", "")))
			if not authoritative_tool_definitions.has(tool_id):
				return {}
			if _player_has_tool(state, tool_id) and not _tool_allows_multiple(tool_id):
				return {}
			var tool_ids: Array = state.get("special_tool_ids", [])
			tool_ids.append(tool_id)
			state["special_tool_ids"] = tool_ids
			_server_layout_add_item(state, {"kind": "tool", "tool_id": tool_id})
			var granted := {"kind": "tool", "tool_id": tool_id}
			if _uses_finite_ammo(tool_id):
				var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
				if not ammo_states.has(tool_id):
					ammo_states[tool_id] = _default_weapon_ammo_state(tool_id)
				state["weapon_ammo_states"] = ammo_states
				granted.merge(ammo_states[tool_id] as Dictionary, true)
			return granted
		"ingredient":
			var ingredient_id := str(entry.get("ingredient_id", entry.get("id", "")))
			var weight_kg := float(entry.get("weight_kg", 0.0))
			var is_chopped := bool(entry.get("is_chopped", false))
			if IngredientCatalog.get_definition(ingredient_id).is_empty() \
					or not _server_can_add_personal_ingredient(state, ingredient_id, weight_kg, is_chopped):
				return {}
			_server_add_personal_ingredient(state, ingredient_id, weight_kg, is_chopped)
			return {
				"kind": "ingredient",
				"ingredient_id": ingredient_id,
				"weight_kg": weight_kg,
				"is_chopped": is_chopped,
			}
		"dish":
			var dish_id := str(entry.get("dish_id", entry.get("id", "")))
			var dish_definition := DishCatalog.get_definition(dish_id)
			if dish_definition.is_empty():
				return {}
			var serving_weight := float(dish_definition.get("serving_weight_kg", 0.0))
			var servings := int(entry.get("servings", 0))
			if servings <= 0 and float(entry.get("weight_kg", 0.0)) > 0.0 and serving_weight > 0.0:
				servings = maxi(1, roundi(float(entry.get("weight_kg", 0.0)) / serving_weight))
			if servings <= 0:
				return {}
			var dish_weight := serving_weight * servings
			if dish_weight <= 0.0 or _personal_ingredient_total_weight(state) + dish_weight > _server_bag_weight_capacity_kg(state) + 0.001:
				return {}
			_server_add_personal_dish(state, dish_id, servings)
			return {"kind": "dish", "dish_id": dish_id, "servings": servings}
		"equipment":
			var equipment_id := str(entry.get("equipment_id", entry.get("id", "")))
			var equipment_definition := EquipmentCatalog.get_definition(equipment_id)
			if equipment_definition.is_empty():
				return {}
			var equipment_ids: Array = state.get("owned_equipment_ids", [])
			if not equipment_ids.has(equipment_id):
				equipment_ids.append(equipment_id)
				state["owned_equipment_ids"] = equipment_ids
				_set_server_equipment_hp(state, equipment_id, float(entry.get("current_hp", EquipmentCatalog.get_max_hp(equipment_id))))
				_server_layout_add_item(state, _server_equipment_item(state, equipment_id))
			return _server_equipment_item(state, equipment_id)
	return {}


func _apply_test_backpack_grant_to_local_player(peer_id: int, entries: Array) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_test_backpack_grant(entries)
			return


func _ensure_player_physics_node(peer_id: int, position: Vector3) -> CharacterBody3D:
	var existing: Node = player_physics_nodes.get(peer_id, null)
	if existing is CharacterBody3D and is_instance_valid(existing) \
			and existing.is_inside_tree() and not existing.is_queued_for_deletion():
		return existing as CharacterBody3D
	player_physics_nodes.erase(peer_id)
	var body := PLAYER_PHYSICS_BODY_SCENE.instantiate() as CharacterBody3D
	if body == null:
		push_error("Unable to create the shared player physics body.")
		return null
	body.name = "ServerPlayerProxy_%d" % peer_id
	var parent := GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if parent != null:
		parent.add_child(body)
		body.global_position = position
	else:
		push_error("Unable to attach the shared player physics body to a world.")
		body.queue_free()
		return null
	player_physics_nodes[peer_id] = body
	return body


func _clear_player_physics_nodes() -> void:
	for peer_id in player_physics_nodes.keys():
		var proxy: Node = player_physics_nodes[peer_id]
		if is_instance_valid(proxy):
			proxy.queue_free()
	player_physics_nodes.clear()


func prepare_world_transition() -> void:
	_clear_player_physics_nodes()


func local_receive_player_input(peer_id: int, input_frame: Dictionary) -> void:
	server_receive_player_input(peer_id, input_frame)


func server_receive_player_input(peer_id: int, input_frame: Dictionary) -> void:
	if not player_states.has(peer_id):
		register_or_update_player(peer_id, {"display_name": "Player_%d" % peer_id})
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return
	var input_seq := int(input_frame.get("input_seq", -1))
	if input_seq <= int(state.get("last_received_input_seq", 0)):
		return
	var move := _vector2_from_value(input_frame.get("move", Vector2.ZERO))
	if float(state.get("big_mouth_capture_remaining", 0.0)) > 0.0:
		move = Vector2.ZERO
	if bool(state.get("cargo_delivery_modal", false)):
		move = Vector2.ZERO
	if move.length() > 1.0:
		move = move.normalized()
	var requested_prone := bool(input_frame.get("prone", state.get("prone", false)))
	var pitch_limit := PLAYER_PRONE_MAX_PITCH_DEGREES if requested_prone else 50.0
	var sanitized_input := {
		"input_seq": input_seq,
		"client_time_msec": int(input_frame.get("client_time_msec", 0)),
		"move": move,
		"jump_seq": maxi(0, int(input_frame.get("jump_seq", 0))),
		"yaw": wrapf(float(input_frame.get("yaw", state.get("yaw", 0.0))), -PI, PI),
		"pitch": clampf(float(input_frame.get("pitch", state.get("pitch", 0.0))), deg_to_rad(-pitch_limit), deg_to_rad(pitch_limit)),
		"prone": requested_prone,
	}
	state["last_received_input_seq"] = input_seq
	player_states[peer_id] = state
	latest_inputs[peer_id] = sanitized_input
	bytes_received_this_second += len(JSON.stringify(input_frame).to_utf8_buffer())


func local_vehicle_session(peer_id: int, vehicle_id: String, connected: bool, seat_index := -1) -> Dictionary:
	_sync_local_player_interaction_state(peer_id)
	return server_vehicle_session(peer_id, vehicle_id, connected, seat_index)


func server_vehicle_session(peer_id: int, vehicle_id: String, connected: bool, seat_index := -1) -> Dictionary:
	var result := {
		"ok": false,
		"peer_id": peer_id,
		"vehicle_id": vehicle_id,
		"connected": connected,
		"seat_index": seat_index,
		"tick": server_tick,
	}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
	elif float(player_states[peer_id].get("respawn_left", 0.0)) > 0.0:
		result["reason"] = "player_respawning"
	else:
		var state: Dictionary = player_states[peer_id]
		var vehicle := _find_vehicle(vehicle_id)
		if vehicle == null:
			result["reason"] = "unknown_vehicle"
		elif connected:
			var player_team := str(state.get("team", ""))
			if not vehicle.can_team_enter(player_team):
				result["reason"] = "wrong_team"
				print("[VehicleSession] rejected peer=%d team=%s vehicle=%s owner_team=%s" % [
					peer_id, player_team, vehicle_id, vehicle.owner_team,
				])
			elif not str(state.get("vehicle_id", "")).is_empty():
				result["reason"] = "already_seated"
			elif not _can_server_interact_with_position(state, vehicle.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
				result["reason"] = "vehicle_out_of_range"
			else:
				var requested_seat := vehicle.get_available_seat_index(true) if seat_index < 0 else seat_index
				if vehicle.enter_seat(peer_id, requested_seat):
					state["prone"] = false
					state["vehicle_id"] = vehicle.get_vehicle_id()
					state["vehicle_seat_index"] = requested_seat
					player_states[peer_id] = state
					_sync_occupied_player_state(peer_id, state, vehicle)
					result["ok"] = true
					result["seat_index"] = requested_seat
					result["open_cabin"] = vehicle.should_show_occupant(requested_seat)
				else:
					result["reason"] = "vehicle_full"
		else:
			var occupied_vehicle_id := str(state.get("vehicle_id", ""))
			var occupied_vehicle := _find_vehicle(occupied_vehicle_id)
			if occupied_vehicle == null or occupied_vehicle_id != vehicle_id:
				result["reason"] = "not_vehicle_occupant"
			else:
				var former_seat := occupied_vehicle.exit_seat(peer_id)
				if former_seat < 0:
					result["reason"] = "not_vehicle_occupant"
				else:
					var exit_position := occupied_vehicle.get_exit_position(former_seat)
					state["vehicle_id"] = ""
					state["vehicle_seat_index"] = -1
					state["position"] = exit_position
					state["velocity"] = Vector3.ZERO
					player_states[peer_id] = state
					_set_server_player_vehicle_collision(peer_id, false, exit_position)
					result["ok"] = true
					result["seat_index"] = former_seat
					result["exit_position"] = exit_position
		if result["ok"]:
			_apply_local_player_vehicle_session(result)
	reliable_world_event_ready.emit({"type": "vehicle_session", "data": result, "tick": server_tick})
	return result


func local_vehicle_input(peer_id: int, input_frame: Dictionary) -> void:
	server_vehicle_input(peer_id, input_frame)


func server_vehicle_input(peer_id: int, input_frame: Dictionary) -> void:
	if not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	var vehicle_id := str(input_frame.get("vehicle_id", ""))
	if vehicle_id.is_empty() or vehicle_id != str(state.get("vehicle_id", "")):
		return
	var vehicle := _find_vehicle(vehicle_id)
	if vehicle == null or vehicle.driver_peer_id != peer_id:
		return
	var input_seq := int(input_frame.get("input_seq", -1))
	var vehicle_state: Dictionary = vehicle_states.get(vehicle_id, {})
	if input_seq <= int(vehicle_state.get("last_input_seq", 0)):
		return
	vehicle_state["last_input_seq"] = input_seq
	vehicle_state["input"] = {"throttle": 0.0, "steering": 0.0, "brake": 1.0} \
		if bool(state.get("cargo_delivery_modal", false)) else {
			"throttle": clampf(float(input_frame.get("throttle", 0.0)), -1.0, 1.0),
			"steering": clampf(float(input_frame.get("steering", 0.0)), -1.0, 1.0),
			"brake": clampf(float(input_frame.get("brake", 0.0)), 0.0, 1.0),
		}
	vehicle_states[vehicle_id] = vehicle_state
	bytes_received_this_second += len(JSON.stringify(input_frame).to_utf8_buffer())


func _register_world_vehicles() -> void:
	var seen := {}
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		if not vehicle.vehicle_deployed or not vehicle.is_inside_tree() or vehicle.is_queued_for_deletion():
			continue
		var vehicle_id := vehicle.get_vehicle_id()
		seen[vehicle_id] = true
		var state: Dictionary = vehicle_states.get(vehicle_id, {})
		state.merge(vehicle.get_network_state(), true)
		state["vehicle_id"] = vehicle_id
		state["last_input_seq"] = int(state.get("last_input_seq", 0))
		state["input"] = state.get("input", {})
		vehicle_states[vehicle_id] = state
	for vehicle_id in vehicle_states.keys():
		if not seen.has(str(vehicle_id)):
			vehicle_states.erase(vehicle_id)


func _simulate_vehicles(delta: float) -> void:
	for raw_vehicle_id in vehicle_states.keys():
		var vehicle_id := str(raw_vehicle_id)
		var vehicle := _find_vehicle(vehicle_id)
		if vehicle == null or not is_instance_valid(vehicle) or not vehicle.vehicle_deployed or not vehicle.is_inside_tree() \
				or vehicle.is_queued_for_deletion() or vehicle.get_world_3d() == null:
			vehicle_states.erase(vehicle_id)
			continue
		var state: Dictionary = vehicle_states[vehicle_id]
		if vehicle.cargo_user_peer_id > 0:
			var cargo_user_state: Dictionary = player_states.get(vehicle.cargo_user_peer_id, {})
			if cargo_user_state.is_empty() or not bool(cargo_user_state.get("cargo_storage_open", false)) \
					or not vehicle.is_cargo_storage_interaction_available_to(_vector3_from_value(cargo_user_state.get("position", Vector3.ZERO))):
				vehicle.cargo_user_peer_id = 0
		var input: Dictionary = state.get("input", {})
		if vehicle.driver_peer_id == 0:
			input = {}
		vehicle.set_drive_input(
			float(input.get("throttle", 0.0)),
			float(input.get("steering", 0.0)),
			float(input.get("brake", 1.0 if vehicle.driver_peer_id == 0 else 0.0))
		)
		vehicle.simulate_authority(delta)
		state.merge(vehicle.get_network_state(), true)
		vehicle_states[vehicle_id] = state


## Vehicles are authoritative hazards: an occupied vehicle's destruction is an
## immediate death for every seated player, not an ejection at the wreck site.
func destroy_vehicle_with_occupants(vehicle: VehicleBase) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or should_send_network_requests():
		return
	var vehicle_id := vehicle.get_vehicle_id()
	var occupant_peer_ids := vehicle.get_seat_occupants()
	for peer_id in occupant_peer_ids:
		if peer_id > 0:
			_begin_player_respawn(peer_id)
	vehicle_states.erase(vehicle_id)
	reliable_world_event_ready.emit({
		"type": "vehicle_destroyed",
		"vehicle_id": vehicle_id,
		"position": vehicle.global_position,
		"tick": server_tick,
	})


func _find_vehicle(vehicle_id: String) -> VehicleBase:
	if vehicle_id.is_empty():
		return null
	var direct := get_node_or_null(NodePath(vehicle_id))
	if direct is VehicleBase and (direct as VehicleBase).vehicle_deployed:
		return direct as VehicleBase
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if node is VehicleBase and (node as VehicleBase).vehicle_deployed \
				and (node as VehicleBase).get_vehicle_id() == vehicle_id:
			return node as VehicleBase
	return null


func get_team_cargo_car(team: String) -> VehicleBase:
	var expected_id := "%s_cargo_car" % team
	var expected := _find_vehicle(expected_id)
	if expected != null and not expected.is_queued_for_deletion():
		return expected
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		if vehicle.is_queued_for_deletion() or not vehicle.vehicle_deployed:
			continue
		if vehicle.owner_team == team and vehicle.get_vehicle_id().to_lower().contains("cargo_car"):
			return vehicle
	return null


func _get_team_garage(team: String) -> TeamGarage:
	for node in get_tree().get_nodes_in_group("team_garages"):
		if node is TeamGarage and (node as TeamGarage).owner_team == team:
			return node as TeamGarage
	return null


func _simulate_cargo_garages(delta: float) -> void:
	for team in ["red", "blue"]:
		var garage := _get_team_garage(team)
		if garage == null:
			continue
		var cargo_car := get_team_cargo_car(team)
		if cargo_car != null:
			if cargo_car_respawn_states.has(team):
				cargo_car_respawn_states.erase(team)
				garage.set_respawn_state(false, 0.0)
				_emit_cargo_car_respawn_state(team, false, 0.0)
			else:
				garage.set_respawn_state(false, 0.0)
			continue
		var state: Dictionary = cargo_car_respawn_states.get(team, {})
		if state.is_empty():
			state = {"remaining": garage.cargo_car_respawn_seconds}
			_emit_cargo_car_respawn_state(team, true, float(state["remaining"]))
		state["remaining"] = maxf(0.0, float(state.get("remaining", 0.0)) - delta)
		cargo_car_respawn_states[team] = state
		garage.set_respawn_state(true, float(state["remaining"]))
		if float(state["remaining"]) <= 0.0:
			var spawned := _spawn_team_cargo_car(team, garage)
			if spawned != null:
				cargo_car_respawn_states.erase(team)
				garage.set_respawn_state(false, 0.0)
				_emit_cargo_car_respawn_state(team, false, 0.0)


func _spawn_team_cargo_car(team: String, garage: TeamGarage) -> VehicleBase:
	if garage == null or get_team_cargo_car(team) != null:
		return null
	var packed := RED_CARGO_CAR_SCENE if team == "red" else BLUE_CARGO_CAR_SCENE
	var vehicle := packed.instantiate() as VehicleBase
	if vehicle == null:
		return null
	var vehicle_id := "%s_cargo_car" % team
	vehicle.name = "RedCargoCar" if team == "red" else "BlueCargoCar"
	vehicle.network_id = vehicle_id
	vehicle.owner_team = team
	var world_root: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else garage.get_parent()
	if world_root == null:
		vehicle.queue_free()
		return null
	world_root.add_child(vehicle)
	vehicle.global_transform = garage.get_cargo_car_spawn_transform()
	var scene_path := "res://vehicles/red_cargo_car.tscn" if team == "red" else "res://vehicles/blue_cargo_car.tscn"
	var state := vehicle.get_network_state()
	state["vehicle_id"] = vehicle_id
	state["scene_path"] = scene_path
	state["owner_team"] = team
	vehicle_states[vehicle_id] = state
	reliable_world_event_ready.emit({
		"type": "vehicle_placed",
		"vehicle_id": vehicle_id,
		"scene_path": scene_path,
		"owner_team": team,
		"position": vehicle.global_position,
		"yaw": vehicle.rotation.y,
		"tick": server_tick,
	})
	return vehicle


func _emit_cargo_car_respawn_state(team: String, active: bool, remaining: float) -> void:
	reliable_world_event_ready.emit({
		"type": "cargo_car_respawn_state",
		"team": team,
		"active": active,
		"remaining": remaining,
		"duration": 60.0,
		"tick": server_tick,
	})


func _sync_occupied_player_state(peer_id: int, state: Dictionary, vehicle: VehicleBase) -> void:
	var seat_index := int(state.get("vehicle_seat_index", -1))
	var occupant_transform := vehicle.get_occupant_world_transform(seat_index)
	state["position"] = occupant_transform.origin
	state["velocity"] = vehicle.velocity
	state["yaw"] = occupant_transform.basis.get_euler().y
	state["grounded"] = true
	state["prone"] = false
	state["locomotion_state"] = "idle"
	player_states[peer_id] = state
	_set_server_player_vehicle_collision(peer_id, true, occupant_transform.origin)


func _set_server_player_vehicle_collision(peer_id: int, seated: bool, position := Vector3.ZERO) -> void:
	if mode != MODE_SERVER:
		return
	var proxy := _ensure_player_physics_node(peer_id, position)
	if proxy == null:
		return
	if seated:
		proxy.global_position = position
		proxy.velocity = Vector3.ZERO
		proxy.collision_layer = 0
		proxy.collision_mask = 0
		var shape := proxy.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", true)
	else:
		if position != Vector3.ZERO:
			proxy.global_position = position
		proxy.collision_layer = COLLISION_LAYER_CHARACTER
		proxy.collision_mask = 12943
		var shape := proxy.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if shape != null:
			shape.set_deferred("disabled", false)
		_set_server_player_prone_collision(
			proxy,
			bool((player_states.get(peer_id, {}) as Dictionary).get("prone", false))
		)


func _set_server_player_prone_collision(proxy: CharacterBody3D, prone: bool) -> void:
	if not is_instance_valid(proxy):
		return
	var shape := proxy.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape == null:
		return
	if not shape.has_meta("standing_transform"):
		shape.set_meta("standing_transform", shape.transform)
	if shape.has_meta("prone_state") and bool(shape.get_meta("prone_state")) == prone:
		return
	shape.set_meta("prone_state", prone)
	var standing_transform: Variant = shape.get_meta("standing_transform")
	if not standing_transform is Transform3D:
		return
	var target := standing_transform as Transform3D
	if prone:
		target = Transform3D(
			Basis(Vector3.RIGHT, deg_to_rad(90.0)),
			PLAYER_PRONE_COLLISION_POSITION
		)
	shape.set_deferred("transform", target)


func _apply_local_player_vehicle_session(result: Dictionary) -> void:
	if mode != MODE_LOCAL:
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == int(result.get("peer_id", 0)):
			node.call("apply_vehicle_session_result", result, _find_vehicle(str(result.get("vehicle_id", ""))))
			return


func local_select_tool(peer_id: int, tool_index: int, tool_id := "") -> void:
	server_select_tool(peer_id, tool_index, tool_id)


func server_select_tool(peer_id: int, tool_index: int, tool_id := "") -> void:
	if not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return
	var held_ingredient := _ingredient_from_selection_id(tool_id)
	var held_dish_id := _dish_from_selection_id(tool_id)
	var held_cargo_crate := tool_id.begins_with("cargo_crate:")
	if not held_ingredient.is_empty() and not _server_has_personal_ingredient(state, str(held_ingredient.get("ingredient_id", "")), 0.001, bool(held_ingredient.get("is_chopped", false))):
		return
	if not held_dish_id.is_empty() and not _server_has_personal_dish(state, held_dish_id):
		return
	if held_cargo_crate:
		var slots_value: Variant = state.get("backpack_slot_items", [])
		if not slots_value is Array or tool_index < 0 or tool_index >= (slots_value as Array).size():
			return
		var selected_value: Variant = (slots_value as Array)[tool_index]
		if not selected_value is Dictionary or str((selected_value as Dictionary).get("kind", "")) != "cargo_crate":
			return
	if held_ingredient.is_empty() and held_dish_id.is_empty() and not held_cargo_crate \
			and not tool_id.is_empty() and not _player_has_tool(state, tool_id):
		return
	state["current_tool_index"] = clampi(tool_index, -1, PLAYER_HOTBAR_SLOT_COUNT - 1)
	state["current_tool_id"] = tool_id
	player_states[peer_id] = state
	reliable_world_event_ready.emit({
		"type": "tool_selected",
		"peer_id": peer_id,
		"tool_index": int(state["current_tool_index"]),
		"tool_id": tool_id,
		"tick": server_tick,
	})


func local_try_use_tool(peer_id: int, tool_request: Dictionary) -> Dictionary:
	return server_try_use_tool(peer_id, tool_request)


func server_try_use_tool(peer_id: int, tool_request: Dictionary) -> Dictionary:
	if not player_states.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return {"ok": false, "reason": "player_respawning"}
	if bool(state.get("prone", false)):
		return {"ok": false, "reason": "player_prone"}
	var tool_id := str(tool_request.get("tool_id", ""))
	if tool_id.is_empty():
		tool_id = _tool_id_from_index(state, int(tool_request.get("tool_index", state.get("current_tool_index", 0))))
	if tool_id == "fist":
		state["action_sequence"] = int(state.get("action_sequence", 0)) + 1
		player_states[peer_id] = state
		var fist_result := {
			"ok": true,
			"peer_id": peer_id,
			"tool_id": "fist",
			"tool_index": int(tool_request.get("tool_index", -1)),
			"animation_action": "melee",
			"action_sequence": state["action_sequence"],
		}
		reliable_world_event_ready.emit({
			"type": "tool_used",
			"data": fist_result,
			"tick": server_tick,
		})
		return fist_result
	if not _player_has_tool(state, tool_id):
		return {"ok": false, "reason": "tool_not_in_loadout"}
	if _uses_finite_ammo(tool_id):
		var ammo_state := _get_or_create_weapon_ammo_state(state, tool_id)
		if float(ammo_state.get("reload_remaining", 0.0)) > 0.0:
			_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
			return {"ok": false, "reason": "reloading"}
		if int(ammo_state.get("ammo_in_mag", 0)) <= 0:
			_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
			return {"ok": false, "reason": "empty_magazine"}
	var cooldowns: Dictionary = state.get("tool_cooldowns", {})
	var cooldown_left := float(cooldowns.get(tool_id, 0.0))
	var rift_teleport_ready := false
	if tool_id == "rift_book":
		var rift_id := str(rift_anchor_by_peer.get(peer_id, ""))
		if not rift_id.is_empty():
			var rift_node: Variant = _node_for_tool_ref({"kind": "placed", "id": rift_id})
			rift_teleport_ready = rift_node is RiftAnchor \
				and is_instance_valid(rift_node) \
				and (rift_node as RiftAnchor).landed \
				and (rift_node as RiftAnchor).current_hp > 0.0
	if cooldown_left > 0.0 and not rift_teleport_ready:
		if _uses_finite_ammo(tool_id):
			_emit_weapon_ammo_state(peer_id, tool_id, _get_or_create_weapon_ammo_state(state, tool_id))
		return {"ok": false, "reason": "cooldown", "cooldown_left": cooldown_left}
	var resolved_request := tool_request.duplicate(true)
	var requested_slot := int(tool_request.get("tool_index", state.get("current_tool_index", -1)))
	var slots_value: Variant = state.get("backpack_slot_items", [])
	if slots_value is Array and requested_slot >= 0 and requested_slot < (slots_value as Array).size():
		var slot_value: Variant = (slots_value as Array)[requested_slot]
		if slot_value is Dictionary and str((slot_value as Dictionary).get("tool_id", "")) == tool_id:
			resolved_request["inventory_item"] = (slot_value as Dictionary).duplicate(true)
	if tool_id.begins_with("animal_") and not resolved_request.has("inventory_item"):
		return {"ok": false, "reason": "invalid_livestock_inventory_slot"}
	var result := _execute_tool(peer_id, tool_id, resolved_request)
	if bool(result.get("ok", false)):
		if _uses_finite_ammo(tool_id):
			var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
			var ammo_state: Dictionary = ammo_states.get(tool_id, _default_weapon_ammo_state(tool_id))
			ammo_state["ammo_in_mag"] = maxi(0, int(ammo_state.get("ammo_in_mag", 0)) - 1)
			ammo_states[tool_id] = ammo_state
			state["weapon_ammo_states"] = ammo_states
			_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
		var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
		var consumed_on_use := bool(definition.get("consumed_on_use", false))
		if consumed_on_use:
			var consumed_item := _consume_dropped_item_from_player(state, {
				"kind": "tool",
				"tool_id": tool_id,
				"slot_index": requested_slot,
			})
			if not consumed_item.is_empty():
				state["current_tool_id"] = ""
				result["consumed_tool_id"] = tool_id
				result["consumed_tool_index"] = int(tool_request.get("tool_index", -1))
		# RiftBook cooldown is a launch/re-arm cooldown, not a teleport delay.
		var starts_tool_cooldown := tool_id != "rift_book" \
				or str(result.get("rift_action", "")) == "launch"
		starts_tool_cooldown = starts_tool_cooldown and not consumed_on_use
		if starts_tool_cooldown:
			cooldowns[tool_id] = _server_tool_cooldown(tool_id)
		state["tool_cooldowns"] = cooldowns
		state["action_sequence"] = int(state.get("action_sequence", 0)) + 1
		result["animation_action"] = _animation_action_for_tool(tool_id)
		result["action_sequence"] = state["action_sequence"]
		player_states[peer_id] = state
		_emit_handheld_projectile_visual(peer_id, tool_id, result)
	reliable_world_event_ready.emit({
		"type": "tool_used",
		"data": result,
		"tick": server_tick,
	})
	return result


func local_reload_weapon(peer_id: int, tool_id: String) -> Dictionary:
	return server_reload_weapon(peer_id, tool_id)


func server_reload_weapon(peer_id: int, tool_id: String) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "tool_id": tool_id, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0 or not _player_has_tool(state, tool_id):
		result["reason"] = "player_unavailable"
		return result
	if bool(state.get("prone", false)):
		result["reason"] = "player_prone"
		return result
	if str(state.get("current_tool_id", "")) != tool_id:
		result["reason"] = "weapon_not_selected"
		if _uses_finite_ammo(tool_id):
			_emit_weapon_ammo_state(peer_id, tool_id, _get_or_create_weapon_ammo_state(state, tool_id))
		return result
	if not _uses_finite_ammo(tool_id):
		result["reason"] = "not_reloadable"
		return result
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	var ammo_state: Dictionary = ammo_states.get(tool_id, _default_weapon_ammo_state(tool_id))
	if float(ammo_state.get("reload_remaining", 0.0)) > 0.0:
		result["reason"] = "already_reloading"
		_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
		return result
	var capacity := _weapon_magazine_size(tool_id)
	if int(ammo_state.get("ammo_in_mag", 0)) >= capacity:
		result["reason"] = "magazine_full"
		_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
		return result
	if int(ammo_state.get("reserve_ammo", 0)) <= 0:
		result["reason"] = "no_reserve_ammo"
		_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
		return result
	var reload_time := _weapon_reload_time(tool_id)
	ammo_state["reload_remaining"] = reload_time
	ammo_state["reload_duration"] = reload_time
	ammo_states[tool_id] = ammo_state
	state["weapon_ammo_states"] = ammo_states
	player_states[peer_id] = state
	result["ok"] = true
	result["ammo_state"] = ammo_state.duplicate(true)
	_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
	return result


func _locomotion_state_for(state: Dictionary, move: Vector2) -> String:
	if not bool(state.get("grounded", true)):
		return "air"
	if bool(state.get("prone", false)):
		return "prone"
	if move.length_squared() > 0.001:
		return "walk"
	return "idle_tool" if not str(state.get("current_tool_id", "")).is_empty() else "idle"


func _animation_action_for_tool(tool_id: String) -> String:
	match tool_id:
		"rubber_revolver", "flame_gun", "freeze_gun", "nail_gun", "suppressed_pistol", "shotgun", "hunting_rifle", "m4", "ar15", "medicine_pistol", "tranquilizer_pistol", "spicy_blaster", "repair_welder", "vehicle_shield_shooter":
			return "shooting"
		"eater":
			return "melee"
		_:
			return "utility"


func _emit_handheld_projectile_visual(peer_id: int, tool_id: String, result: Dictionary) -> void:
	var visual_type := ""
	var speed := 0.0
	var lifetime := 0.0
	match tool_id:
		"wand":
			# Lightning is an instantaneous hit effect, not a travelling projectile.
			# Broadcast its confirmed strike endpoints so observers can reproduce the
			# same full lightning effect as the casting client.
			if str(result.get("hit_kind", "none")) != "none":
				var hit_position := _vector3_from_value(result.get("hit_position", Vector3.ZERO))
				# Lightning falls vertically from above the confirmed hit, rather
				# than from the caster's X/Z position.
				var strike_origin := hit_position + Vector3.UP * 20.0
				reliable_world_event_ready.emit({
					"type": "lightning_struck",
					"owner_peer_id": peer_id,
					"origin": strike_origin,
					"hit_position": hit_position,
					"tick": server_tick,
				})
			return
		"rubber_revolver":
			visual_type = "rubber_bullet"
			speed = CombatBalance.get_float("rubber_revolver", "visual_speed")
			lifetime = CombatBalance.get_float("rubber_revolver", "visual_lifetime")
		"flame_gun", "freeze_gun":
			visual_type = "color_bullet"
			speed = CombatBalance.get_float(tool_id, "visual_speed")
			lifetime = CombatBalance.get_float(tool_id, "visual_lifetime")
		"nail_gun":
			visual_type = "nail_bullet"
			speed = CombatBalance.get_float("nail_gun", "visual_speed")
			lifetime = CombatBalance.get_float("nail_gun", "visual_lifetime")
		"suppressed_pistol", "shotgun", "hunting_rifle", "m4", "ar15":
			visual_type = "nail_bullet"
			speed = CombatBalance.get_float(tool_id, "visual_speed")
			lifetime = CombatBalance.get_float(tool_id, "visual_lifetime")
		"medicine_pistol":
			visual_type = "medicine_bullet"
			speed = CombatBalance.get_float("medicine_pistol", "visual_speed")
			lifetime = minf(
				CombatBalance.get_float("medicine_pistol", "visual_lifetime"),
				CombatBalance.get_float("medicine_pistol", "range") / speed
			)
		"tranquilizer_pistol":
			visual_type = "tranquilizer_bullet"
			speed = CombatBalance.get_float("tranquilizer_pistol", "visual_speed")
			lifetime = minf(
				CombatBalance.get_float("tranquilizer_pistol", "visual_lifetime"),
				CombatBalance.get_float("tranquilizer_pistol", "range") / speed
			)
		_:
			return
	var origin := _vector3_from_value(result.get("origin", Vector3.ZERO))
	if tool_id == "shotgun":
		for pellet_value: Variant in result.get("pellet_results", []):
			if not pellet_value is Dictionary:
				continue
			var pellet := pellet_value as Dictionary
			var pellet_direction := _vector3_from_value(
				pellet.get("direction", Vector3.FORWARD)
			).normalized()
			if pellet_direction.length_squared() <= 0.001:
				continue
			var pellet_lifetime := lifetime
			if str(pellet.get("hit_kind", "none")) != "none":
				var pellet_hit := _vector3_from_value(pellet.get("hit_position", origin))
				pellet_lifetime = minf(
					pellet_lifetime,
					maxf(0.01, origin.distance_to(pellet_hit) / maxf(speed, 0.01))
				)
			_emit_visual_projectile(
				peer_id, visual_type, origin, pellet_direction,
				speed, pellet_lifetime, "nail"
			)
		return
	var direction := _vector3_from_value(result.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		return
	if str(result.get("hit_kind", "none")) != "none":
		var impact_position := _vector3_from_value(result.get("hit_position", origin))
		lifetime = minf(
			lifetime,
			maxf(0.01, origin.distance_to(impact_position) / maxf(speed, 0.01))
		)
	_emit_visual_projectile(peer_id, visual_type, origin, direction, speed, lifetime, str(result.get("effect", "")))


func _emit_visual_projectile(
	owner_peer_id: int,
	visual_type: String,
	origin: Vector3,
	direction: Vector3,
	speed: float,
	lifetime: float,
	effect: String = "",
	spawn_for_owner := false
) -> void:
	var normalized_direction := direction.normalized()
	if normalized_direction.length_squared() <= 0.001:
		return
	var visual_id := next_visual_projectile_id
	next_visual_projectile_id += 1
	reliable_world_event_ready.emit({
		"type": "visual_projectile_fired",
		"visual_id": visual_id,
		"owner_peer_id": owner_peer_id,
		"team": str((player_states.get(owner_peer_id, {}) as Dictionary).get("team", "")),
		"visual_type": visual_type,
		"origin": origin,
		"direction": normalized_direction,
		"speed": speed,
		"lifetime": lifetime,
		"effect": effect,
		"spawn_for_owner": spawn_for_owner,
		"tick": server_tick,
	})


func _make_base_tool_result(peer_id: int, tool_id: String, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	return {
		"ok": true,
		"peer_id": peer_id,
		"team": state.get("team", ""),
		"tool_id": tool_id,
		"tool_index": int(tool_request.get("tool_index", state.get("current_tool_index", 0))),
		"origin": tool_request.get("origin", state.get("position", Vector3.ZERO)),
		"direction": tool_request.get("direction", Vector3.FORWARD),
		"tick": server_tick,
		"input_seq": int(tool_request.get("input_seq", latest_inputs.get(peer_id, {}).get("input_seq", 0))),
	}


func _execute_tool(peer_id: int, tool_id: String, tool_request: Dictionary) -> Dictionary:
	var result := _make_base_tool_result(peer_id, tool_id, tool_request)
	match tool_id:
		"rubber_revolver":
			result.merge(_server_hitscan(peer_id, tool_request, CombatBalance.get_float("rubber_revolver", "range"), CombatBalance.get_float("rubber_revolver", "damage"), CombatBalance.get_float("rubber_revolver", "knockback"), "rubber"), true)
		"flame_gun":
			result.merge(_server_hitscan(peer_id, tool_request, CombatBalance.get_float("flame_gun", "range"), CombatBalance.get_float("flame_gun", "damage"), CombatBalance.get_float("flame_gun", "knockback"), "flame"), true)
		"freeze_gun":
			result.merge(_server_hitscan(peer_id, tool_request, CombatBalance.get_float("freeze_gun", "range"), CombatBalance.get_float("freeze_gun", "damage"), CombatBalance.get_float("freeze_gun", "knockback"), "freeze"), true)
		"nail_gun":
			result.merge(_server_hitscan(peer_id, tool_request, CombatBalance.get_float("nail_gun", "range"), CombatBalance.get_float("nail_gun", "damage"), CombatBalance.get_float("nail_gun", "knockback"), "nail"), true)
		"suppressed_pistol", "hunting_rifle", "m4", "ar15":
			result.merge(_server_hitscan(peer_id, tool_request, CombatBalance.get_float(tool_id, "range"), CombatBalance.get_float(tool_id, "damage"), CombatBalance.get_float(tool_id, "knockback"), "nail"), true)
		"shotgun":
			result.merge(_server_shotgun(peer_id, tool_request), true)
		"medicine_pistol":
			result.merge(_server_healing_hitscan(peer_id, tool_request), true)
		"repair_welder":
			result.merge(_server_repair_welder(peer_id, tool_request), true)
		"vehicle_shield_shooter":
			result.merge(_spawn_vehicle_shield_laser(peer_id, tool_request), true)
		"tranquilizer_pistol":
			result.merge(_server_tranquilizer_hitscan(peer_id, tool_request), true)
		"wand":
			result.merge(_server_wand(peer_id, tool_request), true)
		"rift_book":
			result.merge(_server_rift_book(peer_id, tool_request), true)
		"wreck":
			result.merge(_spawn_server_projectile(peer_id, tool_request, "boom", CombatBalance.get_float("wreck", "projectile_speed"), CombatBalance.get_float("wreck", "damage"), CombatBalance.get_float("wreck", "radius"), "Explosion"), true)
		"bug_cannon":
			result.merge(_spawn_server_projectile(peer_id, tool_request, "bug_boom", CombatBalance.get_float("bug_cannon", "projectile_speed"), CombatBalance.get_float("bug_cannon", "damage"), CombatBalance.get_float("bug_cannon", "radius"), "bug"), true)
		"medicine_cannon":
			result.merge(_spawn_server_projectile(peer_id, tool_request, "medicine_boom", CombatBalance.get_float("medicine_cannon", "projectile_speed"), CombatBalance.get_float("medicine_cannon", "damage"), CombatBalance.get_float("medicine_cannon", "radius"), "medicine_storm"), true)
		"spicy_blaster":
			result.merge(_spawn_spicy_projectile(peer_id, tool_request), true)
		"grenade":
			result.merge(_spawn_grenade_projectile(peer_id, tool_request), true)
		"animal_chicken":
			result.merge(_server_spawn_livestock(peer_id, tool_request, "res://items/Chicken.tscn", "chicken"), true)
		"animal_pig":
			result.merge(_server_spawn_livestock(peer_id, tool_request, "res://items/Pig.tscn", "pig"), true)
		"animal_angus_cow":
			result.merge(_server_spawn_livestock(peer_id, tool_request, "res://items/AngusCow.tscn", "angus_cow"), true)
		"sprout_blaster":
			result.merge(_server_plant_selected_crop(peer_id, tool_request), true)
		"fertilizer":
			result.merge(_server_fertilize(peer_id, tool_request), true)
		"eater":
			result.merge(_server_eater(peer_id, tool_request), true)
		"auto_shooter":
			result.merge(_server_place_tool(peer_id, tool_request, "AutoShooter"), true)
		"shield_door":
			result.merge(_server_place_tool(peer_id, tool_request, "ShieldDoor"), true)
		"anti_air":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/AntiAir.tscn", "anti_air"), true)
		"area_protector":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/AreaProtector.tscn", "area_protector"), true)
		"wheat_sentry":
			result.merge(_server_place_tool(peer_id, tool_request, "WheatSentry"), true)
		"plant_protector":
			result.merge(_server_place_tool(peer_id, tool_request, "PlantProtector"), true)
		"brick":
			result.merge(_server_place_tool(peer_id, tool_request, "Brick"), true)
		"normal_drone":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/NormalDrone.tscn", "normal_drone"), true)
		"action_drone":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/ActionDrone.tscn", "action_drone"), true)
		"tech_drone":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/TechDrone.tscn", "tech_drone"), true)
		"boom_buggy":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/BoomBuggy.tscn", "boom_buggy"), true)
		"small_mouse":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/SmallMouse.tscn", "small_mouse"), true)
		"farm_runner":
			result.merge(_server_place_tool(peer_id, tool_request, "FarmRunner"), true)
		"signal_jam":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/SignalJam.tscn", "signal_jam"), true)
		"signal_augment":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/SignalAugment.tscn", "signal_augment"), true)
		"survey_rider":
			result.merge(_server_place_vehicle_scene(peer_id, tool_request, tool_id, "res://character/weapons/SurveyRider.tscn"), true)
		"field_kitchen":
			result.merge(_server_place_vehicle_scene(peer_id, tool_request, tool_id, "res://character/weapons/KitchenCar.tscn"), true)
		"auto_cooker":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/AutomaticCook.tscn", "auto_cooker"), true)
		"trap":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/Trap.tscn", "trap"), true)
		"big_mouth":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/BigMouth.tscn", "big_mouth"), true)
		"fake_player":
			result.merge(_server_place_free_scene(peer_id, tool_request, "res://character/weapons/FakePlayer.tscn", "fake_player"), true)
		_:
			result["ok"] = false
			result["reason"] = "unsupported_tool"
	return result


func _server_spawn_livestock(
	peer_id: int,
	tool_request: Dictionary,
	scene_path: String,
	species_id: String
) -> Dictionary:
	var state: Dictionary = player_states.get(peer_id, {})
	var team := str(state.get("team", ""))
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	if is_local_authority():
		player_position = _vector3_from_value(tool_request.get("player_position", player_position))
	var origin := _vector3_from_value(tool_request.get("origin", player_position + Vector3.UP * 1.5))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var requested_position := _vector3_from_value(tool_request.get("target_position", Vector3.ZERO))
	if requested_position == Vector3.ZERO:
		var hit := _raycast_world(origin, origin + direction * 10.0, COLLISION_LAYER_GROUND)
		requested_position = _vector3_from_value(hit.get("position", player_position + direction * 3.0))
	if requested_position.distance_to(player_position) > 10.0:
		requested_position = player_position + direction * 3.0
	var placement_yaw := _placement_yaw_for_peer(peer_id, tool_request)
	var placement := _validate_free_placement(peer_id, scene_path, requested_position, placement_yaw)
	if not bool(placement.get("ok", false)):
		return {
			"ok": false,
			"reason": str(placement.get("reason", "invalid_placement")),
			"species_id": species_id,
		}
	var packed := load(scene_path) as PackedScene
	var animal := packed.instantiate() as FarmLivestock if packed != null else null
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if animal == null or world == null:
		if animal != null:
			animal.queue_free()
		return {"ok": false, "reason": "livestock_scene_unavailable", "species_id": species_id}
	var spawn_position := _vector3_from_value(placement.get("position", requested_position))
	var assigned_id := "%s:%d" % [species_id, next_livestock_id]
	next_livestock_id += 1
	animal.name = "%s_%d" % [species_id.capitalize(), next_livestock_id]
	animal.animal_id = assigned_id
	animal.owner_team = team
	animal.home_position = spawn_position
	animal.housed_in_chop = false
	var inventory_value: Variant = tool_request.get("inventory_item", {})
	if inventory_value is Dictionary:
		var inventory_item := inventory_value as Dictionary
		if inventory_item.has("current_hp"):
			animal.initial_hp = float(inventory_item.get("current_hp", -1.0))
		animal.initial_growth_progress = clampf(
			float(inventory_item.get("growth_progress", 0.0)), 0.0, 100.0
		)
	world.add_child(animal)
	animal.global_position = spawn_position
	animal.rotation.y = placement_yaw
	return {
		"ok": true,
		"placed": species_id,
		"animal_id": assigned_id,
		"position": spawn_position,
		"yaw": placement_yaw,
	}


func server_livestock_pickup_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": "pickup", "tick": server_tick}
	if not player_states.has(peer_id):
		return _livestock_pickup_failure(peer_id, result, "unknown_player", "玩家状态不可用")
	var state: Dictionary = player_states[peer_id]
	var animal_id := str(action.get("animal_id", ""))
	var animal: FarmLivestock = null
	for node in get_tree().get_nodes_in_group("farm_livestock"):
		if node is FarmLivestock and str((node as FarmLivestock).animal_id) == animal_id:
			animal = node as FarmLivestock
			break
	if not is_instance_valid(animal) or animal.destroyed or animal.current_hp <= 0.0:
		return _livestock_pickup_failure(peer_id, result, "livestock_unavailable", "这只动物已无法抱起")
	if animal.housed_in_chop or animal.owner_team.is_empty() \
			or animal.owner_team != str(state.get("team", "")):
		return _livestock_pickup_failure(peer_id, result, "livestock_not_owned", "只能抱起本队散养的动物")
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	if player_position.distance_to(animal.global_position) > 4.0:
		return _livestock_pickup_failure(peer_id, result, "livestock_too_far", "距离动物太远")
	var tool_id := "animal_" + animal.species_id
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	if definition.is_empty():
		return _livestock_pickup_failure(peer_id, result, "livestock_item_missing", "动物背包物品未注册")
	var weight_kg := float(definition.get("weight_kg", 0.0))
	if _server_backpack_entry_count(state) >= _server_bag_capacity(state):
		return _livestock_pickup_failure(peer_id, result, "personal_bag_full", "背包格子已满")
	if _personal_ingredient_total_weight(state) + weight_kg > _server_bag_weight_capacity_kg(state) + 0.001:
		return _livestock_pickup_failure(peer_id, result, "personal_bag_overweight", "背包载重不足")
	var entry := {
		"kind": "tool",
		"tool_id": tool_id,
		"display_name": str(definition.get("name", animal.display_name)),
		"species_id": animal.species_id,
		"livestock_instance_id": animal.animal_id,
		"current_hp": animal.current_hp,
		"max_hp": animal.max_hp,
		"growth_progress": animal.get_growth_progress(),
		"maturity_seconds": animal.maturity_seconds,
		"weight_kg": weight_kg,
	}
	var tool_ids: Array = state.get("special_tool_ids", [])
	tool_ids.append(tool_id)
	state["special_tool_ids"] = tool_ids
	_server_layout_add_item(state, entry)
	player_states[peer_id] = state
	animal.remove_from_group("wild_animals")
	animal.remove_from_group("farm_livestock")
	animal.queue_free()
	_emit_personal_inventory_grant(peer_id, [entry])
	_emit_gameplay_notice(peer_id, "已抱起%s（%d / %d HP）" % [
		str(definition.get("short", animal.display_name)), roundi(float(entry["current_hp"])),
		roundi(float(entry["max_hp"])),
	])
	result["ok"] = true
	result["item"] = entry.duplicate(true)
	return result


func _livestock_pickup_failure(
	peer_id: int, result: Dictionary, reason: String, message: String
) -> Dictionary:
	result["reason"] = reason
	result["message"] = message
	if player_states.has(peer_id):
		_emit_gameplay_notice(peer_id, message)
	return result


func _server_rift_book(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var existing_id := str(rift_anchor_by_peer.get(peer_id, ""))
	if not existing_id.is_empty():
		var existing := _node_for_tool_ref({"kind": "placed", "id": existing_id}) as RiftAnchor
		if is_instance_valid(existing) and existing.landed and existing.current_hp > 0.0:
			# Player state position is the feet/root point; the collision query below
			# accounts for the player's capsule center independently.
			var teleport_position := existing.global_position + Vector3.UP * 0.05
			if _can_rift_teleport(peer_id, teleport_position, existing):
				_destroy_registered_tool_ref({"kind": "placed", "id": existing_id})
				rift_anchor_by_peer.erase(peer_id)
				var state: Dictionary = player_states[peer_id]
				state["position"] = teleport_position
				state["velocity"] = Vector3.ZERO
				state["knockback_velocity"] = Vector3.ZERO
				player_states[peer_id] = state
				if mode == MODE_SERVER:
					var proxy := _ensure_player_physics_node(peer_id, teleport_position)
					if is_instance_valid(proxy):
						proxy.global_position = teleport_position
						proxy.velocity = Vector3.ZERO
				# Local authority has no network replicator to apply the reliable
				# event, so move the owning player node immediately as well.
				if mode == MODE_LOCAL:
					for player_node in get_tree().get_nodes_in_group("human_players"):
						if player_node is GamePlayer \
								and int((player_node as GamePlayer).authority_peer_id) == peer_id \
								and not (player_node as GamePlayer).is_remote_proxy:
							(player_node as GamePlayer).global_position = teleport_position
							(player_node as GamePlayer).velocity = Vector3.ZERO
							break
				reliable_world_event_ready.emit({
					"type": "rift_teleported", "peer_id": peer_id,
					"position": teleport_position, "tick": server_tick,
				})
				return {"ok": true, "rift_action": "teleport", "position": teleport_position}
			return {"ok": false, "reason": "teleport_blocked"}
		if not is_instance_valid(existing) or existing.current_hp <= 0.0:
			rift_anchor_by_peer.erase(peer_id)
		else:
			return {"ok": false, "reason": "anchor_in_flight"}

	var state: Dictionary = player_states[peer_id]
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		return {"ok": false, "reason": "invalid_direction"}
	var anchor := RIFT_ANCHOR_SCENE.instantiate() as RiftAnchor
	if anchor == null or GlobalVar.gameworld == null:
		return {"ok": false, "reason": "anchor_scene_unavailable"}
	GlobalVar.gameworld.add_child(anchor)
	anchor.launch(origin + direction * 0.8, direction, peer_id, str(state.get("team", "")))
	var anchor_id := str(anchor.get_path())
	anchor.set_meta("network_device_id", anchor_id)
	rift_anchor_by_peer[peer_id] = anchor_id
	_register_placed_tool(peer_id, "rift_anchor", str(state.get("team", "")), anchor_id, anchor.global_position, anchor.rotation.y)
	var placed_state: Dictionary = placed_tool_states.get(anchor_id, {})
	placed_state["device_id"] = anchor_id
	placed_state["scene_path"] = "res://character/weapons/RiftAnchor.tscn"
	placed_state["free_placement"] = true
	placed_state["anchor_owner_peer_id"] = peer_id
	placed_state["anchor_landed"] = false
	placed_tool_states[anchor_id] = placed_state
	return {
		"ok": true,
		"rift_action": "launch",
		"placed": "rift_anchor",
		"device_id": anchor_id,
		"anchor_id": anchor_id,
		"team": str(state.get("team", "")),
		"position": anchor.global_position,
		"yaw": anchor.rotation.y,
		"origin": anchor.global_position,
		"direction": direction,
		"scene_path": "res://character/weapons/RiftAnchor.tscn",
	}


func activate_rift_anchor(anchor: RiftAnchor) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var id := str(anchor.get_meta("network_device_id", anchor.get_path()))
	var state: Dictionary = placed_tool_states.get(id, {})
	if state.is_empty():
		return
	state["position"] = anchor.global_position
	state["yaw"] = anchor.rotation.y
	state["hp"] = anchor.current_hp
	state["anchor_landed"] = true
	placed_tool_states[id] = state
	reliable_world_event_ready.emit({
		"type": "rift_anchor_activated", "anchor_id": id,
		"position": anchor.global_position, "tick": server_tick,
	})


func destroy_rift_anchor(anchor: RiftAnchor) -> void:
	if anchor == null or not is_instance_valid(anchor):
		return
	var id := str(anchor.get_meta("network_device_id", anchor.get_path()))
	var owner_peer := int(anchor.owner_peer_id)
	if owner_peer > 0 and str(rift_anchor_by_peer.get(owner_peer, "")) == id:
		rift_anchor_by_peer.erase(owner_peer)
	_destroy_registered_tool_ref({"kind": "placed", "id": id})


func destroy_harvest_tree(tree: HarvestTree, log_count: int) -> void:
	if tree == null or not is_instance_valid(tree) or not (is_server_authority() or is_local_authority()):
		return
	var tree_id := tree.resource_id
	var fall_direction := tree.begin_authoritative_destroy(log_count)
	reliable_world_event_ready.emit({
		"type": "harvest_tree_destroyed",
		"tree_id": tree_id,
		"resource_id": tree_id,
		"position": tree.global_position,
		"fall_direction": fall_direction,
		"tick": server_tick,
	})


func spawn_tree_log_pickups(position: Vector3, log_count: int) -> void:
	spawn_nature_resource_drops(position, [{"item_id": "log", "count": log_count, "weight_kg": 2.0, "model_path": LOG_DROP_MODEL}])


func spawn_nature_resource_drops(position: Vector3, drops: Array) -> void:
	if not (is_server_authority() or is_local_authority()):
		return
	var sequence := 0
	for drop_value: Variant in drops:
		if not drop_value is Dictionary:
			continue
		var drop := drop_value as Dictionary
		var count := maxi(0, int(drop.get("count", drop.get("quantity", 0))))
		for index in range(count):
			var angle := TAU * float(sequence) / float(maxi(1, count))
			sequence += 1
			var direction := Vector3(cos(angle), 0.35, sin(angle)).normalized()
			var kind := str(drop.get("kind", "ingredient"))
			var item_id := str(drop.get(
				"item_id",
				drop.get("ingredient_id", drop.get("tool_id", drop.get("equipment_id", "")))
			))
			var has_weight := drop.has("weight_kg")
			var weight := maxf(0.01, float(drop.get("weight_kg", 1.0))) if has_weight else 0.0
			var model_path := str(drop.get("model_path", ""))
			if model_path.is_empty():
				if kind == "ingredient":
					model_path = IngredientCatalog.get_harvest_drop_scene_path(item_id)
				elif kind == "dish":
					model_path = DishCatalog.get_model_path(str(drop.get("dish_id", item_id)))
				elif kind == "tool" or kind == "weapon":
					model_path = str((authoritative_tool_definitions.get(item_id, {}) as Dictionary).get("path", ""))
				elif kind == "equipment":
					model_path = EquipmentCatalog.get_scene_path(str(drop.get("equipment_id", item_id)))
			if item_id.is_empty() or model_path.is_empty():
				continue
			var display_name := str(drop.get("display_name", ""))
			if display_name.is_empty() and kind == "dish":
				display_name = str(DishCatalog.get_definition(str(drop.get("dish_id", item_id))).get("display_name", ""))
			if display_name.is_empty() and kind == "equipment":
				display_name = str(EquipmentCatalog.get_definition(str(drop.get("equipment_id", item_id))).get("name", ""))
			if display_name.is_empty():
				display_name = str(IngredientCatalog.get_definition(item_id).get("display_name", item_id))
			var item: Dictionary = drop.duplicate(true)
			item["kind"] = kind
			item["display_name"] = display_name
			item.erase("count")
			item.erase("model_path")
			if kind == "ingredient":
				item["ingredient_id"] = str(drop.get("ingredient_id", item_id))
				if has_weight:
					item["weight_kg"] = weight
			elif kind == "tool" or kind == "weapon":
				item["tool_id"] = str(drop.get("tool_id", item_id))
			elif kind == "equipment":
				var equipment_id := str(drop.get("equipment_id", item_id))
				var equipment_definition := EquipmentCatalog.get_definition(equipment_id)
				if equipment_definition.is_empty():
					continue
				item["equipment_id"] = equipment_id
				item["equipment_type"] = str(equipment_definition.get("equipment_type", ""))
				var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
				if max_hp > 0.0:
					item["current_hp"] = clampf(float(drop.get("current_hp", max_hp)), 0.0, max_hp)
					item["max_hp"] = max_hp
			var state := {
				"item_id": _allocate_dropped_item_id("nature_drop"),
				"item": item, "model_path": model_path,
				"position": position + Vector3.UP * 1.0 + direction * 0.55,
				"velocity": direction * 3.5 + Vector3.UP * 2.5,
				"angular_velocity": Vector3(1.5, 2.0, 0.8),
				"landed": false, "lifetime_remaining": PickupItem.LIFETIME_SECONDS,
			}
			if _spawn_authoritative_dropped_item(state):
				reliable_world_event_ready.emit({"type": "dropped_item_spawned", "item_state": state, "tick": server_tick})


func grant_crop_harvest(
	peer_id: int,
	ingredient_id: String,
	weight_kg: float,
	_fallback_team: String,
	drop_position := Vector3.ZERO
) -> bool:
	if not player_states.has(peer_id) or IngredientCatalog.get_definition(ingredient_id).is_empty() \
			or weight_kg <= 0.0:
		_spawn_crop_harvest_overflow(drop_position, ingredient_id, weight_kg)
		return false
	var state: Dictionary = player_states[peer_id]
	var personal_weight := _personal_ingredient_weight_that_fits(
		state, ingredient_id, weight_kg, false
	)
	var entries: Array[Dictionary] = []
	if personal_weight > 0.001:
		_server_add_personal_ingredient(state, ingredient_id, personal_weight, false)
		entries.append({
			"kind": "ingredient", "ingredient_id": ingredient_id,
			"weight_kg": personal_weight, "is_chopped": false,
		})
		player_states[peer_id] = state
		_emit_personal_inventory_grant(peer_id, entries)
	var overflow_weight := maxf(0.0, weight_kg - personal_weight)
	if overflow_weight <= 0.001:
		return true
	_spawn_crop_harvest_overflow(drop_position, ingredient_id, overflow_weight)
	var definition := IngredientCatalog.get_definition(ingredient_id)
	var display_name := str(definition.get("display_name", ingredient_id))
	var no_slot := not _personal_ingredient_has_available_slot(state, ingredient_id, false)
	var reason := "背包格子已满" if no_slot else "背包载重量不足"
	_emit_gameplay_notice(
		peer_id,
		"%s，%.2f kg %s已掉落在地面" % [reason, overflow_weight, display_name]
	)
	return true


func _spawn_crop_harvest_overflow(position: Vector3, ingredient_id: String, weight_kg: float) -> void:
	if weight_kg <= 0.001:
		return
	spawn_nature_resource_drops(position, [{
		"kind": "ingredient", "ingredient_id": ingredient_id,
		"item_id": ingredient_id, "count": 1, "weight_kg": weight_kg,
	}])


func grant_ore_harvest(_peer_id: int, position: Vector3, drops: Array) -> void:
	# Mining always creates world pickups. A player receives ore only after
	# explicitly collecting those pickups and passing bag slot/weight checks.
	spawn_nature_resource_drops(position, drops)


func _personal_ingredient_weight_that_fits(
	state: Dictionary,
	ingredient_id: String,
	requested_weight: float,
	is_chopped: bool
) -> float:
	if requested_weight <= 0.0 \
			or not _personal_ingredient_has_available_slot(state, ingredient_id, is_chopped):
		return 0.0
	var free_weight := maxf(
		0.0,
		_server_bag_weight_capacity_kg(state) - _personal_ingredient_total_weight(state)
	)
	return minf(requested_weight, free_weight)


func _personal_ingredient_has_available_slot(
	state: Dictionary,
	ingredient_id: String,
	is_chopped: bool
) -> bool:
	var values: Variant = state.get("personal_ingredients", {})
	var key := _personal_ingredient_key(ingredient_id, is_chopped)
	return (values is Dictionary and float((values as Dictionary).get(key, 0.0)) > 0.0001) \
		or _server_backpack_entry_count(state) < _server_bag_capacity(state)


func _emit_personal_inventory_grant(peer_id: int, entries: Array[Dictionary]) -> void:
	if entries.is_empty():
		return
	if mode == MODE_LOCAL:
		_apply_test_backpack_grant_to_local_player(peer_id, entries)
	else:
		reliable_world_event_ready.emit({
			"type": "personal_inventory_grant", "peer_id": peer_id,
			"entries": entries, "tick": server_tick,
		})


func _emit_gameplay_notice(peer_id: int, text: String) -> void:
	if peer_id <= 0 or text.is_empty():
		return
	reliable_world_event_ready.emit({
		"type": "gameplay_notice", "peer_id": peer_id,
		"text": text, "tick": server_tick,
	})


func _destroy_rift_anchor_for_peer(peer_id: int) -> void:
	var id := str(rift_anchor_by_peer.get(peer_id, ""))
	if id.is_empty():
		return
	rift_anchor_by_peer.erase(peer_id)
	if placed_tool_states.has(id):
		_destroy_registered_tool_ref({"kind": "placed", "id": id})


func _can_rift_teleport(peer_id: int, position: Vector3, anchor_to_ignore: Node3D = null) -> bool:
	if not player_states.has(peer_id):
		return false
	var state: Dictionary = player_states[peer_id]
	if not str(state.get("vehicle_id", "")).is_empty():
		return false
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return false
	var query := PhysicsShapeQueryParameters3D.new()
	var shape := CapsuleShape3D.new()
	shape.radius = 0.42
	shape.height = 1.8
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, position + Vector3.UP * 0.99)
	query.collision_mask = FREE_PLACEMENT_BLOCKING_MASK
	if is_instance_valid(anchor_to_ignore):
		var excluded: Array[RID] = [anchor_to_ignore.get_rid()]
		var hit_area := anchor_to_ignore.find_child("Hit3D", true, false) as CollisionObject3D
		if hit_area != null:
			excluded.append(hit_area.get_rid())
		query.exclude = excluded
	var world_3d := get_tree().root.get_world_3d()
	if world_3d == null:
		return false
	var hits := world_3d.direct_space_state.intersect_shape(query, 1)
	return hits.is_empty()


func local_shop_transaction(peer_id: int, transaction: Dictionary) -> Dictionary:
	_sync_local_player_interaction_state(peer_id)
	return server_shop_transaction(peer_id, transaction)


func _make_purchased_livestock_entry(tool_id: String) -> Dictionary:
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	if definition.is_empty():
		return {}
	var max_hp := 200.0 if tool_id == "animal_chicken" else 400.0
	var entry := {
		"kind": "tool",
		"tool_id": tool_id,
		"livestock_instance_id": "stored:%d" % next_livestock_id,
		"current_hp": max_hp,
		"max_hp": max_hp,
		"growth_progress": 0.0,
		"maturity_seconds": float(definition.get("maturity_seconds", 0.0)),
		"weight_kg": float(definition.get("weight_kg", 0.0)),
	}
	next_livestock_id += 1
	return entry


func _livestock_sell_price(product: Dictionary, item: Dictionary) -> int:
	var base_price := maxi(0, int(product.get("sell_price", 0)))
	var progress := clampf(float(item.get("growth_progress", 0.0)), 0.0, 100.0)
	return roundi(float(base_price) * (1.0 + 2.0 * progress / 100.0))


func _check_livestock_purchase_capacity(team: String, tool_id: String, amount: int) -> Dictionary:
	var required_kind := "chicken" if tool_id == "animal_chicken" else "livestock"
	var has_completed_chop := false
	var available_slots := 0
	for node in get_tree().get_nodes_in_group("livestock_chops"):
		if not node is LivestockChop:
			continue
		var chop := node as LivestockChop
		if chop.owner_team != team or chop.chop_kind != required_kind or not chop.completed:
			continue
		has_completed_chop = true
		var chop_state := chop.get_chop_state()
		var slots: Array = chop_state.get("slots", [])
		for slot_value: Variant in slots:
			if not slot_value is Dictionary or (slot_value as Dictionary).is_empty():
				available_slots += 1
	if not has_completed_chop:
		return {
			"ok": false,
			"reason": "chicken_chop_not_built" if required_kind == "chicken" \
				else "livestock_chop_not_built",
		}
	if amount <= 0 or available_slots < amount:
		return {
			"ok": false,
			"reason": "chicken_chop_full" if required_kind == "chicken" \
				else "livestock_chop_full",
		}
	return {"ok": true, "available_slots": available_slots}


func _emit_shop_transaction_result(result: Dictionary) -> Dictionary:
	reliable_world_event_ready.emit({"type": "shop_transaction", "data": result, "tick": server_tick})
	return result


func server_shop_transaction(peer_id: int, transaction: Dictionary) -> Dictionary:
	if not player_states.has(peer_id):
		return _emit_shop_transaction_result({
			"ok": false, "reason": "unknown_player", "peer_id": peer_id,
			"shop_category": str(transaction.get("shop_category", "general")),
		})
	var team := str(player_states[peer_id].get("team", ""))
	if team.is_empty():
		return _emit_shop_transaction_result({
			"ok": false, "reason": "missing_team", "peer_id": peer_id,
			"shop_category": str(transaction.get("shop_category", "general")),
		})
	var shop_category := str(transaction.get("shop_category", "general"))
	var action_name := str(transaction.get("action", "trade"))
	if shop_category == "livestock_market":
		var market := _livestock_market_from_transaction(transaction)
		var session_result := {
			"ok": false,
			"peer_id": peer_id,
			"team": team,
			"shop_category": shop_category,
			"session_action": action_name,
		}
		if market == null:
			session_result["reason"] = "unknown_market"
			return _emit_shop_transaction_result(session_result)
		if action_name == "close":
			session_result["ok"] = market.release_team_user(team, peer_id) \
				or market.get_team_user(team) == 0
			return _emit_shop_transaction_result(session_result)
		if not _can_server_interact_with_position(
			player_states[peer_id], market.get_interaction_position(), 6.0
		):
			session_result["reason"] = "market_out_of_range"
			return _emit_shop_transaction_result(session_result)
		if action_name == "open":
			session_result["ok"] = market.try_acquire_team_user(team, peer_id)
			if not bool(session_result["ok"]):
				session_result["reason"] = "market_in_use"
			return _emit_shop_transaction_result(session_result)
		if action_name == "refresh":
			session_result["ok"] = market.touch_team_user(team, peer_id)
			if not bool(session_result["ok"]):
				session_result["reason"] = "market_session_required"
			return _emit_shop_transaction_result(session_result)
		if action_name != "trade":
			session_result["reason"] = "unsupported_action"
			return _emit_shop_transaction_result(session_result)
		if not market.touch_team_user(team, peer_id):
			session_result["reason"] = "market_session_required"
			return _emit_shop_transaction_result(session_result)
	var item_id := str(transaction.get("item_id", ""))
	var is_buy := bool(transaction.get("is_buy", true))
	var product: Dictionary = GlobalVar.get_shop_product(item_id)
	if product.is_empty():
		return _emit_shop_transaction_result({
			"ok": false, "reason": "invalid_item", "peer_id": peer_id,
			"team": team, "shop_category": shop_category,
		})
	if str(product.get("shop_category", "general")) != shop_category:
		return _emit_shop_transaction_result({
			"ok": false, "reason": "item_not_sold_here", "peer_id": peer_id,
			"team": team, "shop_category": shop_category,
		})
	var is_weighted_item := str(product.get("unit", "item")) == "kg"
	var amount := float(transaction.get("amount", 1.0)) if is_weighted_item else float(int(transaction.get("amount", 1)))
	var trade_unit := IngredientCatalog.get_pickup_unit_kg(item_id) if is_weighted_item else 1.0
	if amount <= 0.0 or absf(fmod(amount, trade_unit)) > 0.0001:
		return _emit_shop_transaction_result({
			"ok": false, "reason": "invalid_amount", "peer_id": peer_id,
			"team": team, "shop_category": shop_category,
		})
	var ok := false
	var product_kind := str(product.get("kind", ""))
	var is_dish := product_kind == "dish"
	var is_weapon := product_kind == "weapon"
	var is_livestock := product_kind == "livestock"
	var dish_weight := float(DishCatalog.get_definition(item_id).get("serving_weight_kg", 0.0)) * amount if is_dish else 0.0
	var state: Dictionary = player_states[peer_id]
	var transaction_total_price := 0
	var player_slots_result: Array = []
	var failure_reason := ""
	if is_livestock and is_buy and bool(product.get("can_buy", false)):
		var livestock_amount := int(amount)
		var chop_check := _check_livestock_purchase_capacity(team, item_id, livestock_amount)
		if not bool(chop_check.get("ok", false)):
			return _emit_shop_transaction_result({
				"ok": false, "reason": str(chop_check.get("reason", "chop_full")),
				"peer_id": peer_id, "team": team, "item_id": item_id,
				"amount": amount, "is_buy": true, "kind": product_kind,
				"shop_category": shop_category,
			})
		var sample_entry := _make_purchased_livestock_entry(item_id)
		# The sample reserves an id; it is also used as the first purchased entry.
		var total_weight := float(sample_entry.get("weight_kg", 0.0)) * float(livestock_amount)
		transaction_total_price = roundi(float(product.get("buy_price", 0)) * float(livestock_amount))
		var has_capacity := not sample_entry.is_empty() and livestock_amount > 0 \
			and _server_backpack_entry_count(state) + livestock_amount <= _server_bag_capacity(state) \
			and _personal_ingredient_total_weight(state) + total_weight <= _server_bag_weight_capacity_kg(state) + 0.001
		if has_capacity and GlobalVar.check_team_item_amount(team, "money") >= transaction_total_price:
			ok = GlobalVar.remove_item(team, "money", transaction_total_price)
			if ok:
				var livestock_ids: Array = state.get("special_tool_ids", [])
				for index in range(livestock_amount):
					var entry := sample_entry if index == 0 else _make_purchased_livestock_entry(item_id)
					livestock_ids.append(item_id)
					_server_layout_add_item(state, entry)
				state["special_tool_ids"] = livestock_ids
				player_states[peer_id] = state
				player_slots_result = (state.get("backpack_slot_items", []) as Array).duplicate(true)
		elif not has_capacity:
			failure_reason = "personal_bag_full"
		else:
			failure_reason = "insufficient_money"
	elif is_livestock and not is_buy and bool(product.get("can_sell", false)):
		var livestock_amount := int(amount)
		var matching_slots: Array[int] = []
		var slots: Array = state.get("backpack_slot_items", [])
		for index in range(slots.size()):
			var item: Dictionary = slots[index] as Dictionary if slots[index] is Dictionary else {}
			if str(item.get("kind", "")) == "tool" and str(item.get("tool_id", "")) == item_id:
				matching_slots.append(index)
				transaction_total_price += _livestock_sell_price(product, item)
				if matching_slots.size() >= livestock_amount:
					break
		if livestock_amount > 0 and matching_slots.size() == livestock_amount:
			ok = true
			for slot_index: int in matching_slots:
				if _consume_dropped_item_from_player(state, {
					"kind": "tool", "tool_id": item_id, "slot_index": slot_index,
				}).is_empty():
					ok = false
					break
			if ok:
				GlobalVar.add_team_reward(team, transaction_total_price)
				_clear_invalid_current_selection(state, _typed_dictionary_array(state.get("backpack_slot_items", []) as Array))
				player_states[peer_id] = state
				player_slots_result = (state.get("backpack_slot_items", []) as Array).duplicate(true)
		else:
			failure_reason = "personal_item_insufficient"
	elif is_weapon and is_buy and bool(product.get("can_buy", false)):
		var weapon_amount := int(amount)
		var total_price := roundi(float(product.get("buy_price", 0)) * float(weapon_amount))
		var enough_slots := weapon_amount == 1 \
				and _server_backpack_entry_count(state) < _server_bag_capacity(state)
		var can_own_weapon := authoritative_tool_definitions.has(item_id) \
				and (not _player_has_tool(state, item_id) or _tool_allows_multiple(item_id))
		if enough_slots and can_own_weapon \
				and GlobalVar.check_team_item_amount(team, "money") >= total_price:
			ok = GlobalVar.remove_item(team, "money", total_price)
			if ok:
				var weapon_ids: Array = state.get("primary_weapon_ids", [])
				weapon_ids.append(item_id)
				state["primary_weapon_ids"] = weapon_ids
				var weapon_entry := {"kind": "tool", "tool_id": item_id}
				_server_layout_add_item(state, weapon_entry)
				if _uses_finite_ammo(item_id):
					var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
					if not ammo_states.has(item_id):
						ammo_states[item_id] = _default_weapon_ammo_state(item_id)
					state["weapon_ammo_states"] = ammo_states
					weapon_entry.merge(ammo_states[item_id] as Dictionary, true)
				player_states[peer_id] = state
				_emit_personal_inventory_grant(peer_id, [weapon_entry])
	elif is_dish and is_buy and bool(product.get("can_buy", false)):
		var total_price := roundi(float(product.get("buy_price", 0)) * amount)
		if dish_weight > 0.0 and GlobalVar.check_team_item_amount(team, "money") >= total_price \
				and _server_can_add_personal_dish(state, item_id, int(amount), dish_weight):
			ok = GlobalVar.remove_item(team, "money", total_price)
			if ok:
				_server_add_personal_dish(state, item_id, int(amount), dish_weight)
				player_states[peer_id] = state
	elif is_dish and (not is_buy) and bool(product.get("can_sell", false)):
		var total_sell := roundi(float(product.get("sell_price", 0)) * amount)
		ok = dish_weight > 0.0 and _server_remove_personal_dish(state, item_id, int(amount), dish_weight)
		if ok:
			player_states[peer_id] = state
			GlobalVar.add_team_reward(team, total_sell)
	elif is_buy and bool(product.get("can_buy", false)):
		var total_price := roundi(float(product.get("buy_price", 0)) * amount)
		if GlobalVar.check_team_item_amount(team, "money") >= total_price:
			ok = GlobalVar.remove_item(team, "money", total_price) and GlobalVar.add_item(team, item_id, amount)
	elif (not is_buy) and bool(product.get("can_sell", false)):
		var total_sell := roundi(float(product.get("sell_price", 0)) * amount)
		if GlobalVar.check_team_item_amount(team, item_id) >= amount:
			ok = GlobalVar.remove_item(team, item_id, amount)
			if ok:
				GlobalVar.add_team_reward(team, total_sell)
	var result := {
		"ok": ok,
		"peer_id": peer_id,
		"team": team,
		"item_id": item_id,
		"amount": amount,
		"is_buy": is_buy,
		"kind": str(product.get("kind", "")),
		"shop_category": shop_category,
		"total_weight_kg": dish_weight,
		"total_price": transaction_total_price,
	}
	if not ok and not failure_reason.is_empty():
		result["reason"] = failure_reason
	if not player_slots_result.is_empty():
		result["player_slots"] = player_slots_result
	_emit_shop_transaction_result(result)
	inventory_state_ready.emit(_build_inventory_state())
	return result


func local_farm_action(peer_id: int, action: Dictionary) -> Dictionary:
	_sync_local_player_interaction_state(peer_id)
	return server_farm_action(peer_id, action)


func local_ingredient_pickup_action(peer_id: int, action: Dictionary) -> Dictionary:
	_sync_local_player_interaction_state(peer_id)
	return server_ingredient_pickup_action(peer_id, action)


func _sync_local_player_interaction_state(peer_id: int) -> void:
	if mode != MODE_LOCAL or not player_states.has(peer_id):
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if not is_instance_valid(node) or not node is GamePlayer:
			continue
		var player := node as GamePlayer
		if player.is_remote_proxy or player.authority_peer_id != peer_id:
			continue
		var state: Dictionary = player_states[peer_id]
		state["position"] = player.global_position
		state["velocity"] = player.velocity
		state["yaw"] = player.rotation.y
		state["pitch"] = player.Head.rotation.x if is_instance_valid(player.Head) else float(state.get("pitch", 0.0))
		state["grounded"] = player.is_on_floor()
		# Local games use this player node as the inventory source of truth. Keep the
		# authority state aligned before a kitchen action validates ingredients.
		var personal_ingredients: Dictionary = {}
		var personal_dishes: Dictionary = {}
		var personal_dish_weights: Dictionary = {}
		var personal_cargo_crates: Array[Dictionary] = []
		for item: Dictionary in player.backpack_items:
			var kind := str(item.get("kind", ""))
			if kind == "cargo_crate":
				personal_cargo_crates.append(_normalize_cargo_crate(item))
				continue
			if kind == "dish":
				var dish_id := str(item.get("dish_id", ""))
				var servings := maxi(0, int(item.get("servings", 0)))
				var dish_weight := maxf(0.0, float(item.get("weight_kg", 0.0)))
				if not dish_id.is_empty() and servings > 0 and dish_weight > 0.0:
					personal_dishes[dish_id] = int(personal_dishes.get(dish_id, 0)) + servings
					personal_dish_weights[dish_id] = float(personal_dish_weights.get(dish_id, 0.0)) + dish_weight
				continue
			if kind != "ingredient":
				continue
			var ingredient_id := str(item.get("ingredient_id", ""))
			var weight_kg := maxf(0.0, float(item.get("weight_kg", 0.0)))
			if ingredient_id.is_empty() or weight_kg <= 0.0:
				continue
			var is_chopped := bool(item.get("is_chopped", false)) \
					or str(item.get("preparation", "")) == "chopped" \
					or str(item.get("model_state", "")) == "chopped"
			var key := _personal_ingredient_key(ingredient_id, is_chopped)
			personal_ingredients[key] = float(personal_ingredients.get(key, 0.0)) + weight_kg
		state["personal_ingredients"] = personal_ingredients
		state["personal_dishes"] = personal_dishes
		state["personal_dish_weights"] = personal_dish_weights
		state["personal_cargo_crates"] = personal_cargo_crates
		var backpack_slots: Array[Dictionary] = []
		for item: Dictionary in player.backpack_items:
			backpack_slots.append(item.duplicate(true))
		state["backpack_slot_items"] = backpack_slots
		state["backpack_layout_valid"] = backpack_slots.size() == _server_bag_capacity(state)
		player_states[peer_id] = state
		return


func _release_invalid_kitchen_users() -> void:
	for group_name in ["ingredient_pickups", "chopping_stations", "plating_stations", "ingredient_extractors", "stand_mixers", "auto_cookers", "oven_stations", "griddle_stations", "induction_counters", "smoker_stations", "freezer_stations", "livestock_chops"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if not node is KitchenAppliance:
				continue
			var station := node as KitchenAppliance
			var previous_peer_id := station.active_user_peer_id
			station._refresh_user_lock()
			var peer_id := station.active_user_peer_id
			if previous_peer_id != 0 and peer_id == 0:
				_emit_kitchen_lock_state(station)
			if peer_id == 0:
				continue
			if not player_states.has(peer_id):
				if station.force_release_user(peer_id):
					_emit_kitchen_lock_state(station)
				continue
			var state: Dictionary = player_states[peer_id]
			if float(state.get("respawn_left", 0.0)) > 0.0 or not _can_server_interact_with_position(state, station.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
				if station.force_release_user(peer_id):
					_emit_kitchen_lock_state(station)
	for node in get_tree().get_nodes_in_group("livestock_markets"):
		if not node is LivestockMarket:
			continue
		var market := node as LivestockMarket
		market.refresh_team_locks()
		for market_team: String in ["red", "blue"]:
			var market_peer_id := market.get_team_user(market_team)
			if market_peer_id == 0:
				continue
			if not player_states.has(market_peer_id):
				market.force_release_user(market_peer_id)
				continue
			var market_state: Dictionary = player_states[market_peer_id]
			if float(market_state.get("respawn_left", 0.0)) > 0.0 \
					or not _can_server_interact_with_position(
						market_state, market.get_interaction_position(), 6.0
					):
				market.force_release_user(market_peer_id)


func _force_release_kitchen_user(peer_id: int) -> void:
	if peer_id <= 0:
		return
	for group_name in ["ingredient_pickups", "chopping_stations", "plating_stations", "ingredient_extractors", "stand_mixers", "auto_cookers", "oven_stations", "griddle_stations", "induction_counters", "smoker_stations", "freezer_stations", "livestock_chops"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is KitchenAppliance:
				var station := node as KitchenAppliance
				if station.force_release_user(peer_id):
					_emit_kitchen_lock_state(station)
	for node in get_tree().get_nodes_in_group("livestock_markets"):
		if node is LivestockMarket:
			(node as LivestockMarket).force_release_user(peer_id)


func _emit_kitchen_lock_state(station: KitchenAppliance) -> void:
	if station is IngredientPickup:
		reliable_world_event_ready.emit({"type": "ingredient_pickup_state", "station_state": (station as IngredientPickup).get_staged_state(), "tick": server_tick})
	elif station is RecipeCookingStation:
		var recipe_station := station as RecipeCookingStation
		var event_type := recipe_station.get_state_event_type()
		if not event_type.is_empty():
			reliable_world_event_ready.emit({"type": event_type, "station_state": recipe_station.get_station_state(), "tick": server_tick})
	elif station is LivestockChop:
		reliable_world_event_ready.emit({
			"type": "livestock_chop_state",
			"station_state": (station as LivestockChop).get_chop_state(),
			"tick": server_tick,
		})


func reserve_ingredient_pickups_for_team(team: String) -> void:
	# IngredientPickup is now a direct team produce storage terminal. Recipe
	# orders must no longer reserve and remove inventory in the background.
	return


func _reserve_ready_ingredient_pickups() -> void:
	if is_client_proxy():
		return
	for team in EventBoard.VALID_TEAMS:
		reserve_ingredient_pickups_for_team(str(team))
func server_ingredient_pickup_action(peer_id: int, action: Dictionary) -> Dictionary:
	if str(action.get("station_kind", "")) == "livestock":
		return server_livestock_pickup_action(peer_id, action)
	if str(action.get("station_kind", "")) == "livestock_chop":
		return server_livestock_chop_action(peer_id, action)
	if str(action.get("station_kind", "")) == "cargo_car":
		return server_cargo_car_action(peer_id, action)
	if str(action.get("station_kind", "")) == "cargo_crate":
		return server_cargo_crate_action(peer_id, action)
	if str(action.get("station_kind", "")) == "cargo_delivery":
		return server_cargo_delivery_action(peer_id, action)
	if str(action.get("station_kind", "")) == "inventory_layout":
		return server_inventory_layout_action(peer_id, action)
	if str(action.get("station_kind", "")) == "equipment":
		return server_equipment_action(peer_id, action)
	if str(action.get("station_kind", "")) == "auto_cooker":
		return server_auto_cooker_action(peer_id, action)
	if str(action.get("station_kind", "")) == "chopping":
		return server_chopping_action(peer_id, action)
	if str(action.get("station_kind", "")) == "plating":
		return server_plating_station_action(peer_id, action)
	if str(action.get("station_kind", "")) == "extractor":
		return server_extractor_action(peer_id, action)
	if str(action.get("station_kind", "")) == "oven":
		return server_oven_action(peer_id, action)
	if str(action.get("station_kind", "")) == "griddle":
		return server_recipe_cooking_station_action(peer_id, action, "griddle_stations", "griddle_station_action_result")
	if str(action.get("station_kind", "")) == "induction":
		return server_recipe_cooking_station_action(peer_id, action, "induction_counters", "induction_counter_action_result")
	if str(action.get("station_kind", "")) == "smoker":
		return server_recipe_cooking_station_action(peer_id, action, "smoker_stations", "smoker_action_result")
	if str(action.get("station_kind", "")) == "freezer":
		return server_recipe_cooking_station_action(peer_id, action, "freezer_stations", "freezer_action_result")
	if str(action.get("station_kind", "")) == "mixer":
		return server_mixer_action(peer_id, action)
	if str(action.get("station_kind", "")) == "dropped_item":
		return server_dropped_item_action(peer_id, action)
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var station := _ingredient_pickup_from_action(action)
	if station == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or station.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = station.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = station.get_staged_state()
	elif not _can_server_interact_with_position(state, station.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif not station.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"withdraw":
				var item_kind := str(action.get("item_kind", ""))
				var item_id := str(action.get("item_id", ""))
				var amount := float(action.get("amount", 0.0))
				if item_kind == "dish":
					var definition := DishCatalog.get_definition(item_id)
					var servings := roundi(amount)
					var weight_kg := float(definition.get("serving_weight_kg", 0.0)) * float(servings)
					if definition.is_empty() or servings <= 0 or absf(amount - float(servings)) > 0.001:
						result["reason"] = "invalid_storage_item"
					elif GlobalVar.check_team_item_amount(team, item_id) + 0.001 < float(servings):
						result["reason"] = "team_storage_insufficient"
					elif not _server_can_add_personal_dish(state, item_id, servings, weight_kg):
						result["reason"] = "personal_bag_full"
					elif not GlobalVar.remove_item(team, item_id, float(servings)):
						result["reason"] = "team_storage_changed"
					else:
						_server_add_personal_dish(state, item_id, servings, weight_kg)
						result["ok"] = true
				elif item_kind == "ingredient":
					if IngredientCatalog.get_definition(item_id).is_empty() or amount <= 0.0001:
						result["reason"] = "invalid_storage_item"
					elif GlobalVar.check_team_item_amount(team, item_id) + 0.001 < amount:
						result["reason"] = "team_storage_insufficient"
					elif not _server_can_add_personal_ingredient(state, item_id, amount, false):
						result["reason"] = "personal_bag_full"
					elif not GlobalVar.remove_item(team, item_id, amount):
						result["reason"] = "team_storage_changed"
					else:
						_server_add_personal_ingredient(state, item_id, amount, false)
						result["ok"] = true
				else:
					result["reason"] = "invalid_storage_item"
			"deposit":
				var item_kind := str(action.get("item_kind", ""))
				var item_id := str(action.get("item_id", ""))
				var amount := float(action.get("amount", 0.0))
				if item_kind == "dish":
					var definition := DishCatalog.get_definition(item_id)
					var servings := roundi(amount)
					var weight_kg := float(definition.get("serving_weight_kg", 0.0)) * float(servings)
					if definition.is_empty() or servings <= 0 or absf(amount - float(servings)) > 0.001:
						result["reason"] = "invalid_storage_item"
					elif not _server_remove_personal_dish(state, item_id, servings, weight_kg):
						result["reason"] = "personal_item_insufficient"
					else:
						GlobalVar.add_item(team, item_id, float(servings))
						result["ok"] = true
				elif item_kind == "ingredient":
					if IngredientCatalog.get_definition(item_id).is_empty() or amount <= 0.0001:
						result["reason"] = "invalid_storage_item"
					elif not _server_remove_personal_ingredient(state, item_id, amount, false):
						result["reason"] = "personal_item_insufficient"
					else:
						GlobalVar.add_item(team, item_id, amount)
						result["ok"] = true
				else:
					result["reason"] = "invalid_storage_item"
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = station.get_staged_state()
	if bool(result.get("ok", false)):
		player_states[peer_id] = state
		result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": "ingredient_pickup_action_result", "data": result, "tick": server_tick})
	return result


func server_livestock_chop_action(peer_id: int, action: Dictionary) -> Dictionary:
	var action_name := str(action.get("action", ""))
	var result := {"ok": false, "peer_id": peer_id, "action": action_name, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return _emit_livestock_chop_result(result)
	var state: Dictionary = player_states[peer_id]
	var chop := _livestock_chop_from_action(action)
	if chop == null:
		result["reason"] = "unknown_station"
		return _emit_livestock_chop_result(result)
	if chop.owner_team != str(state.get("team", "")):
		result["reason"] = "wrong_team"
		return _fill_livestock_chop_result(result, state, chop)
	if action_name == "close":
		result["ok"] = chop.release_user(peer_id) or chop.active_user_peer_id == 0
		return _fill_livestock_chop_result(result, state, chop)
	if not _can_server_interact_with_position(
		state, chop.global_position, PLAYER_VEHICLE_INTERACTION_RANGE + 1.5
	):
		result["reason"] = "station_out_of_range"
		return _fill_livestock_chop_result(result, state, chop)
	if not chop.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
		return _fill_livestock_chop_result(result, state, chop)
	match action_name:
		"open", "refresh":
			result["ok"] = true
		"start_construction":
			if chop.completed or chop.constructing:
				result["reason"] = "construction_started"
			elif not _consume_chop_construction_materials(state, chop):
				result["reason"] = "materials_unavailable"
			elif chop.start_construction():
				player_states[peer_id] = state
				result["ok"] = true
			else:
				result["reason"] = "construction_start_failed"
		"place":
			var player_slot := int(action.get("player_slot", -1))
			var chop_slot := int(action.get("chop_slot", -1))
			var slots: Array = state.get("backpack_slot_items", [])
			var item: Dictionary = (slots[player_slot] as Dictionary).duplicate(true) \
				if player_slot >= 0 and player_slot < slots.size() and slots[player_slot] is Dictionary else {}
			var species_id := str(item.get("species_id", str(item.get("tool_id", "")).trim_prefix("animal_")))
			if item.is_empty() or not str(item.get("tool_id", "")).begins_with("animal_") \
					or not chop.accepts_species(species_id):
				result["reason"] = "invalid_livestock"
			elif chop_slot < 0 or chop_slot >= chop.get_slot_count() \
					or not (chop.slot_items[chop_slot] as Dictionary).is_empty():
				result["reason"] = "slot_occupied"
			else:
				item["slot_index"] = player_slot
				var consumed := _consume_dropped_item_from_player(state, item)
				if consumed.is_empty() or not chop.put_livestock(chop_slot, consumed):
					if not consumed.is_empty():
						_restore_dropped_item_to_player(state, consumed)
					result["reason"] = "invalid_livestock"
				else:
					player_states[peer_id] = state
					result["ok"] = true
		"take":
			var chop_slot := int(action.get("chop_slot", -1))
			var preview: Dictionary = chop.slot_items[chop_slot] \
				if chop_slot >= 0 and chop_slot < chop.slot_items.size() else {}
			if preview.is_empty():
				result["reason"] = "livestock_slot_empty"
			elif not _can_add_dropped_item_to_player(state, preview):
				result["reason"] = "personal_bag_full"
			else:
				var taken := chop.take_livestock(chop_slot)
				if taken.is_empty():
					result["reason"] = "livestock_slot_empty"
				else:
					_restore_dropped_item_to_player(state, taken)
					player_states[peer_id] = state
					result["ok"] = true
		_:
			result["reason"] = "unsupported_action"
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	return _fill_livestock_chop_result(result, state, chop)


func _consume_chop_construction_materials(state: Dictionary, chop: LivestockChop) -> bool:
	var team := str(state.get("team", ""))
	var requirements := {"log": chop.required_log_kg, "iron": chop.required_iron_kg}
	var deductions: Array[Dictionary] = []
	for item_id_value: Variant in requirements.keys():
		var item_id := str(item_id_value)
		var required := float(requirements[item_id_value])
		var personal_values: Dictionary = state.get("personal_ingredients", {})
		var personal := minf(required, float(personal_values.get(_personal_ingredient_key(item_id, false), 0.0)))
		var team_amount := maxf(0.0, required - personal)
		if GlobalVar.check_team_item_amount(team, item_id) + 0.001 < team_amount:
			return false
		deductions.append({"item_id": item_id, "personal": personal, "team": team_amount})
	for deduction: Dictionary in deductions:
		var item_id := str(deduction["item_id"])
		var personal := float(deduction["personal"])
		var team_amount := float(deduction["team"])
		if personal > 0.001:
			_server_remove_personal_ingredient(state, item_id, personal, false)
		if team_amount > 0.001:
			GlobalVar.remove_item(team, item_id, team_amount)
	return true


func _fill_livestock_chop_result(
	result: Dictionary, state: Dictionary, chop: LivestockChop
) -> Dictionary:
	result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	result["station_state"] = chop.get_chop_state()
	return _emit_livestock_chop_result(result)


func _emit_livestock_chop_result(result: Dictionary) -> Dictionary:
	reliable_world_event_ready.emit({
		"type": "livestock_chop_action_result", "data": result, "tick": server_tick,
	})
	return result


func server_chopping_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var station := _chopping_station_from_action(action)
	if station == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or station.owner_team != team:
		result["reason"] = "wrong_team"
	elif not _can_server_interact_with_position(state, station.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		if station.ingredient_id.is_empty() or station.chop_count < ChoppingStation.REQUIRED_CHOPS:
			result["reason"] = "ingredient_not_ready"
		elif not _server_can_add_personal_ingredient(state, station.ingredient_id, station.ingredient_weight_kg, true):
			result["reason"] = "personal_bag_full"
		else:
			result["ok"] = true
			result["ingredient"] = {
				"ingredient_id": station.ingredient_id,
				"weight_kg": station.ingredient_weight_kg,
				"is_chopped": true,
			}
			_server_add_personal_ingredient(state, station.ingredient_id, station.ingredient_weight_kg, true)
			player_states[peer_id] = state
			station.clear_station()
			station.release_user(peer_id)
		result["station_state"] = station.get_station_state()
	elif not station.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"place":
				var ingredient_id := str(action.get("ingredient_id", ""))
				var expected_weight_kg := IngredientCatalog.get_pickup_unit_kg(ingredient_id)
				var requested_weight_kg := float(action.get("weight_kg", 0.0))
				if IngredientCatalog.get_model_path(ingredient_id, "chopped_item").is_empty() \
						or absf(requested_weight_kg - expected_weight_kg) > 0.0001:
					result["reason"] = "invalid_chopping_unit"
				elif not _server_remove_personal_ingredient(state, ingredient_id, expected_weight_kg, false):
					result["reason"] = "ingredient_not_held"
				else:
					result["ok"] = station.place_ingredient(ingredient_id, expected_weight_kg)
					if not result["ok"]:
						_server_add_personal_ingredient(state, ingredient_id, expected_weight_kg, false)
					else:
						player_states[peer_id] = state
				result["slot_index"] = int(action.get("slot_index", -1))
				result["ingredient_id"] = ingredient_id
				result["weight_kg"] = expected_weight_kg
				if not result["ok"] and not result.has("reason"):
					result["reason"] = "invalid_ingredient_or_station_busy"
			"cut":
				result["ok"] = station.cut_once()
				if not result["ok"]:
					result["reason"] = "cut_unavailable"
			_:
				result["reason"] = "unsupported_action"
		if bool(result.get("ok", false)) and str(action.get("action", "")) == "cut" and station.chop_count >= ChoppingStation.REQUIRED_CHOPS:
			station.release_user(peer_id)
		result["station_state"] = station.get_station_state()
	reliable_world_event_ready.emit({"type": "chopping_action_result", "data": result, "tick": server_tick})
	return result


func server_plating_station_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var station := _plating_station_from_action(action)
	if station == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or station.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = station.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = station.get_station_state()
	elif not _can_server_interact_with_position(state, station.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		var preview := RecipeCatalog.get_result(station.recipe_id)
		var dish_id := str(preview.get("dish_id", ""))
		var servings := int(preview.get("quantity", 0))
		if dish_id.is_empty() or servings <= 0 or not _server_can_add_personal_dish(state, dish_id, servings):
			result["reason"] = "personal_bag_full"
		else:
			var output := station.take_output()
			result["ok"] = not output.is_empty()
			if result["ok"]:
				_server_add_personal_dish(state, dish_id, servings)
				player_states[peer_id] = state
				result["dish_id"] = dish_id
				result["servings"] = servings
				award_completed_dish_collection(peer_id, dish_id)
			else:
				result["reason"] = "output_unavailable"
		result["station_state"] = station.get_station_state()
	elif not station.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"place":
				var ingredient_id := str(action.get("ingredient_id", ""))
				var requested_is_chopped := bool(action.get("is_chopped", false))
				var requirement := station.get_stage_requirement(team, ingredient_id, requested_is_chopped)
				var is_chopped := bool(requirement.get("is_chopped", false))
				var required_weight := float(requirement.get("required_weight_kg", 0.0))
				if requirement.is_empty():
					result["reason"] = "ingredient_not_required_or_station_busy"
				elif not _server_remove_personal_ingredient(state, ingredient_id, required_weight, is_chopped):
					result["reason"] = "ingredient_not_held"
				else:
					result["ok"] = not station.stage_ingredient(team, ingredient_id, is_chopped).is_empty()
					if not result["ok"]:
						_server_add_personal_ingredient(state, ingredient_id, required_weight, is_chopped)
						result["reason"] = "station_rejected_ingredient"
					else:
						player_states[peer_id] = state
						result["ingredient_id"] = ingredient_id
						result["is_chopped"] = is_chopped
						result["weight_kg"] = required_weight
			"start":
				var start_result := _server_start_selected_recipe(state, team, station, str(action.get("recipe_id", "")))
				result.merge(start_result, true)
				if bool(result.get("ok", false)):
					player_states[peer_id] = state
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = station.get_station_state()
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": "plating_station_action_result", "data": result, "tick": server_tick})
	return result


func server_oven_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var oven := _oven_from_action(action)
	if oven == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or oven.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = oven.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = oven.get_station_state()
	elif not _can_server_interact_with_position(state, oven.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		var output := oven.get_output_result()
		var dish_id := str(output.get("dish_id", ""))
		var servings := int(output.get("quantity", 0))
		var weight_kg := float(output.get("total_weight_kg", 0.0))
		if dish_id.is_empty() or servings <= 0 or weight_kg <= 0.0 or not _server_can_add_personal_dish(state, dish_id, servings, weight_kg):
			result["reason"] = "personal_bag_full"
		else:
			if oven.take_output().is_empty():
				result["reason"] = "output_unavailable"
			else:
				_server_add_personal_dish(state, dish_id, servings, weight_kg)
				player_states[peer_id] = state
				result["ok"] = true
				result["dish_id"] = dish_id
				result["servings"] = servings
				result["weight_kg"] = weight_kg
				award_completed_dish_collection(peer_id, dish_id)
		result["station_state"] = oven.get_station_state()
	elif not oven.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"place":
				var ingredient_id := str(action.get("ingredient_id", ""))
				var is_chopped := bool(action.get("is_chopped", false))
				var requirement := oven.get_stage_requirement(team, ingredient_id, is_chopped)
				var required_weight := float(requirement.get("required_weight_kg", 0.0))
				if requirement.is_empty():
					result["reason"] = "ingredient_not_required_or_station_busy"
				elif not _server_remove_personal_ingredient(state, ingredient_id, required_weight, is_chopped):
					result["reason"] = "ingredient_not_held"
				else:
					result["ok"] = not oven.stage_ingredient(team, ingredient_id, is_chopped).is_empty()
					if result["ok"]:
						player_states[peer_id] = state
						result["ingredient_id"] = ingredient_id
						result["is_chopped"] = is_chopped
						result["weight_kg"] = required_weight
					else:
						_server_add_personal_ingredient(state, ingredient_id, required_weight, is_chopped)
						result["reason"] = "station_rejected_ingredient"
			"start":
				var start_result := _server_start_selected_recipe(state, team, oven, str(action.get("recipe_id", "")))
				result.merge(start_result, true)
				if bool(result.get("ok", false)):
					player_states[peer_id] = state
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = oven.get_station_state()
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": "oven_action_result", "data": result, "tick": server_tick})
	return result


func server_recipe_cooking_station_action(peer_id: int, action: Dictionary, group_name: String, event_type: String) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var station := _recipe_cooking_station_from_action(action, group_name)
	if station == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or station.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = station.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = station.get_station_state()
	elif not _can_server_interact_with_position(state, station.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		var output := station.get_output_result()
		var dish_id := str(output.get("dish_id", ""))
		var servings := int(output.get("quantity", 0))
		var weight_kg := float(output.get("total_weight_kg", 0.0))
		if dish_id.is_empty() or servings <= 0 or weight_kg <= 0.0 or not _server_can_add_personal_dish(state, dish_id, servings, weight_kg):
			result["reason"] = "personal_bag_full"
		else:
			if station.take_output().is_empty():
				result["reason"] = "output_unavailable"
			else:
				_server_add_personal_dish(state, dish_id, servings, weight_kg)
				player_states[peer_id] = state
				result["ok"] = true
				result["dish_id"] = dish_id
				result["servings"] = servings
				result["weight_kg"] = weight_kg
				award_completed_dish_collection(peer_id, dish_id)
		result["station_state"] = station.get_station_state()
	elif not station.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"place":
				var ingredient_id := str(action.get("ingredient_id", ""))
				var is_chopped := bool(action.get("is_chopped", false))
				var requirement := station.get_stage_requirement(team, ingredient_id, is_chopped)
				var required_weight := float(requirement.get("required_weight_kg", 0.0))
				if requirement.is_empty():
					result["reason"] = "ingredient_not_required_or_station_busy"
				elif not _server_remove_personal_ingredient(state, ingredient_id, required_weight, is_chopped):
					result["reason"] = "ingredient_not_held"
				else:
					result["ok"] = not station.stage_ingredient(team, ingredient_id, is_chopped).is_empty()
					if result["ok"]:
						player_states[peer_id] = state
						result["ingredient_id"] = ingredient_id
						result["is_chopped"] = is_chopped
						result["weight_kg"] = required_weight
					else:
						_server_add_personal_ingredient(state, ingredient_id, required_weight, is_chopped)
						result["reason"] = "station_rejected_ingredient"
			"start":
				var start_result := _server_start_selected_recipe(state, team, station, str(action.get("recipe_id", "")))
				result.merge(start_result, true)
				if bool(result.get("ok", false)):
					player_states[peer_id] = state
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = station.get_station_state()
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": event_type, "data": result, "tick": server_tick})
	return result


func server_auto_cooker_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok":false, "peer_id":peer_id, "action":str(action.get("action", "")), "tick":server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var cooker := _auto_cooker_from_action(action)
	if cooker == null:
		result["reason"] = "unknown_station"
	elif cooker.owner_team != str(state.get("team", "")):
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = cooker.release_user(peer_id)
		result["station_state"] = cooker.get_cook_state()
	elif not _can_server_interact_with_position(state, cooker.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		var output := cooker.get_completed_result()
		if output.is_empty():
			result["reason"] = "output_not_ready"
		elif not _server_can_add_personal_dish(state, str(output.get("dish_id", "")), int(output.get("quantity", 0)), float(output.get("total_weight_kg", 0.0))):
			result["reason"] = "personal_bag_full"
		else:
			output = cooker.take_completed_result()
			_server_add_personal_dish(state, str(output.get("dish_id", "")), int(output.get("quantity", 0)), float(output.get("total_weight_kg", 0.0)))
			player_states[peer_id] = state
			cooker.release_user(peer_id)
			result["ok"] = true
			result["result"] = output
			award_completed_dish_collection(peer_id, str(output.get("dish_id", "")))
	elif not cooker.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	elif str(action.get("action", "")) == "acquire":
		result["ok"] = true
	elif str(action.get("action", "")) == "start":
		var recipe_id := str(action.get("recipe_id", ""))
		var recipe := AutoCookerRecipeCatalog.get_recipe(recipe_id)
		var inputs := AutoCookerRecipeCatalog.get_ingredients(recipe_id)
		if recipe.is_empty() or inputs.is_empty() or not cooker.can_start(recipe_id):
			result["reason"] = "invalid_or_busy_recipe"
		elif not _server_can_add_personal_dish(state, str((recipe.get("result", {}) as Dictionary).get("dish_id", "")), int((recipe.get("result", {}) as Dictionary).get("quantity", 0)), float((recipe.get("result", {}) as Dictionary).get("total_weight_kg", 0.0))):
			result["reason"] = "personal_bag_full"
		elif not _can_fund_ingredient_inputs(state, str(state.get("team", "")), inputs):
			result["reason"] = "ingredients_insufficient"
		else:
			result["personal_inputs"] = _consume_ingredient_inputs(state, str(state.get("team", "")), inputs)
			result["ok"] = cooker.start(recipe_id, peer_id)
			if result["ok"]: player_states[peer_id] = state
			else: result["reason"] = "cooker_rejected_recipe"
	result["station_state"] = cooker.get_cook_state() if cooker != null else {}
	if bool(result.get("ok", false)): inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type":"auto_cooker_action_result", "data":result, "tick":server_tick})
	return result


func _can_fund_ingredient_inputs(state: Dictionary, team: String, inputs: Array[Dictionary]) -> bool:
	for entry in inputs:
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var required := float(entry.get("weight_kg", 0.0))
		var personal := float((state.get("personal_ingredients", {}) as Dictionary).get(_personal_ingredient_key(ingredient_id, false), 0.0))
		if personal + GlobalVar.check_team_item_amount(team, ingredient_id) + 0.001 < required: return false
	return true


func _consume_ingredient_inputs(state: Dictionary, team: String, inputs: Array[Dictionary]) -> Array[Dictionary]:
	var consumed_from_backpack: Array[Dictionary] = []
	for entry in inputs:
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var remaining := float(entry.get("weight_kg", 0.0))
		var personal := float((state.get("personal_ingredients", {}) as Dictionary).get(_personal_ingredient_key(ingredient_id, false), 0.0))
		var from_backpack := minf(personal, remaining)
		if from_backpack > 0.0:
			_server_remove_personal_ingredient(state, ingredient_id, from_backpack, false)
			consumed_from_backpack.append({"ingredient_id":ingredient_id, "weight_kg":from_backpack})
		remaining -= from_backpack
		if remaining > 0.0: GlobalVar.remove_item(team, ingredient_id, remaining)
	return consumed_from_backpack


func server_extractor_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var extractor := _ingredient_extractor_from_action(action)
	if extractor == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or extractor.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = extractor.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = extractor.get_extractor_state()
	elif not _can_server_interact_with_position(state, extractor.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		if not extractor.can_take_output():
			result["reason"] = "output_not_ready"
		elif not _server_can_add_personal_ingredient(state, extractor.output_ingredient_id, extractor.output_weight_kg, false):
			result["reason"] = "personal_bag_full"
		else:
			var output := extractor.take_output()
			if output.is_empty():
				result["reason"] = "output_unavailable"
			else:
				_server_add_personal_ingredient(state, str(output.get("ingredient_id", "")), float(output.get("weight_kg", 0.0)), false)
				player_states[peer_id] = state
				result["ok"] = true
				result["ingredient"] = output
		result["station_state"] = extractor.get_extractor_state()
	elif not extractor.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"start":
				var recipe_id := str(action.get("recipe_id", ""))
				var recipe := ExtractorRecipeCatalog.get_recipe(recipe_id)
				var inputs := ExtractorRecipeCatalog.get_inputs(recipe_id)
				if recipe.is_empty() or inputs.is_empty() or not extractor.can_start_extraction(recipe_id):
					result["reason"] = "invalid_or_busy_recipe"
				elif not _can_fund_ingredient_inputs(state, team, inputs):
					result["reason"] = "ingredients_insufficient"
				else:
					var personal_inputs := _consume_ingredient_inputs(state, team, inputs)
					result["ok"] = extractor.start_extraction(recipe_id)
					if result["ok"]:
						player_states[peer_id] = state
						result["personal_inputs"] = personal_inputs
					else:
						result["reason"] = "extractor_rejected_recipe"
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = extractor.get_extractor_state()
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": "extractor_action_result", "data": result, "tick": server_tick})
	return result


func server_mixer_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var mixer := _stand_mixer_from_action(action)
	if mixer == null:
		result["reason"] = "unknown_station"
	elif team.is_empty() or mixer.owner_team != team:
		result["reason"] = "wrong_team"
	elif str(action.get("action", "")) == "release":
		result["ok"] = mixer.release_user(peer_id)
		if not result["ok"]:
			result["reason"] = "not_station_user"
		result["station_state"] = mixer.get_mixer_state()
	elif not _can_server_interact_with_position(state, mixer.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
		result["reason"] = "station_out_of_range"
	elif str(action.get("action", "")) == "take":
		if not mixer.can_take_output():
			result["reason"] = "output_not_ready"
		elif not _server_can_add_personal_ingredient(state, mixer.output_ingredient_id, mixer.output_weight_kg, false):
			result["reason"] = "personal_bag_full"
		else:
			var output := mixer.take_output()
			if output.is_empty():
				result["reason"] = "output_unavailable"
			else:
				_server_add_personal_ingredient(state, str(output.get("ingredient_id", "")), float(output.get("weight_kg", 0.0)), false)
				player_states[peer_id] = state
				result["ok"] = true
				result["ingredient"] = output
		result["station_state"] = mixer.get_mixer_state()
	elif not mixer.try_acquire_user(peer_id):
		result["reason"] = "station_in_use"
	else:
		match str(action.get("action", "")):
			"acquire":
				result["ok"] = true
			"start":
				var recipe_id := str(action.get("recipe_id", ""))
				var recipe := MixerRecipeCatalog.get_recipe(recipe_id)
				var inputs := MixerRecipeCatalog.get_inputs(recipe_id)
				if recipe.is_empty() or inputs.is_empty() or not mixer.can_start_mixing(recipe_id):
					result["reason"] = "invalid_or_busy_recipe"
				elif not _can_fund_ingredient_inputs(state, team, inputs):
					result["reason"] = "ingredients_insufficient"
				else:
					var personal_inputs := _consume_ingredient_inputs(state, team, inputs)
					result["ok"] = mixer.start_mixing(recipe_id)
					if result["ok"]:
						player_states[peer_id] = state
						result["personal_inputs"] = personal_inputs
					else:
						result["reason"] = "mixer_rejected_recipe"
			_:
				result["reason"] = "unsupported_action"
		result["station_state"] = mixer.get_mixer_state()
	if bool(result.get("ok", false)):
		inventory_state_ready.emit(_build_inventory_state())
	reliable_world_event_ready.emit({"type": "stand_mixer_action_result", "data": result, "tick": server_tick})
	return result


func server_dropped_item_action(peer_id: int, action: Dictionary) -> Dictionary:
	var action_name := str(action.get("action", ""))
	var result := {"ok": false, "peer_id": peer_id, "action": action_name, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		result["reason"] = "player_unavailable"
		return result
	match action_name:
		"throw":
			var item_value: Variant = action.get("item", {})
			var item := _consume_dropped_item_from_player(state, item_value as Dictionary if item_value is Dictionary else {})
			if item.is_empty():
				result["reason"] = "item_not_held"
			else:
				var direction := _validated_throw_direction(action.get("direction", Vector3.ZERO), state)
				var item_state := _make_dropped_item_state(peer_id, item, state, direction)
				if item_state.is_empty() or not _spawn_authoritative_dropped_item(item_state):
					_restore_dropped_item_to_player(state, item)
					result["reason"] = "spawn_failed"
				else:
					state["current_tool_id"] = ""
					player_states[peer_id] = state
					result["ok"] = true
					result["slot_index"] = int(action.get("slot_index", -1))
					result["item"] = item.duplicate(true)
					result["item_state"] = item_state
					result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
		"pickup":
			var item_id := str(action.get("item_id", ""))
			var pickup := dropped_item_nodes.get(item_id, null) as PickupItem
			if not is_instance_valid(pickup) or not pickup.landed:
				result["reason"] = "item_unavailable"
			elif not _can_server_interact_with_position(state, pickup.global_position, PLAYER_VEHICLE_INTERACTION_RANGE):
				result["reason"] = "item_out_of_range"
			elif str(pickup.item_data.get("kind", "")) in ["tool", "weapon"] \
					and _player_has_tool(state, str(pickup.item_data.get("tool_id", ""))) \
					and not _tool_allows_multiple(str(pickup.item_data.get("tool_id", ""))):
				result["reason"] = "unique_tool_already_owned"
			elif not _can_add_dropped_item_to_player(state, pickup.item_data):
				result["reason"] = "personal_bag_full"
			else:
				var item := pickup.item_data.duplicate(true)
				_restore_dropped_item_to_player(state, item)
				player_states[peer_id] = state
				_remove_authoritative_dropped_item(item_id, false)
				result["ok"] = true
				result["item_id"] = item_id
				result["item"] = item
		_:
			result["reason"] = "unsupported_action"
	reliable_world_event_ready.emit({"type": "dropped_item_action_result", "data": result, "tick": server_tick})
	return result


func server_cargo_car_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {
		"ok": false,
		"peer_id": peer_id,
		"action": str(action.get("action", "")),
		"vehicle_id": str(action.get("vehicle_id", "")),
		"tick": server_tick,
	}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return _emit_cargo_car_result(result)
	var state: Dictionary = player_states[peer_id]
	var vehicle := _find_vehicle(str(action.get("vehicle_id", "")))
	if vehicle == null or not vehicle.supports_cargo():
		result["reason"] = "unknown_vehicle"
		return _emit_cargo_car_result(result)
	var action_name := str(action.get("action", ""))
	if action_name == "close":
		result["ok"] = vehicle.release_cargo_user(peer_id) or vehicle.cargo_user_peer_id == 0
		state["cargo_storage_open"] = false
		player_states[peer_id] = state
		return _fill_cargo_car_result(result, state, vehicle)
	if not vehicle.is_cargo_storage_interaction_available_to(
		_vector3_from_value(state.get("position", Vector3.ZERO))
	):
		result["reason"] = "vehicle_out_of_range"
		return _emit_cargo_car_result(result)
	if not vehicle.try_acquire_cargo_user(peer_id):
		result["reason"] = "station_in_use"
		return _emit_cargo_car_result(result)
	state["cargo_storage_open"] = true
	var previous_selection_id := str(state.get("current_tool_id", ""))
	var slots: Array = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	match action_name:
		"open":
			result["ok"] = true
		"load":
			var player_slot := int(action.get("player_slot", -1))
			var cargo_slot := int(action.get("cargo_slot", -1))
			var crate: Dictionary = slots[player_slot] as Dictionary if player_slot >= 0 and player_slot < slots.size() and slots[player_slot] is Dictionary else {}
			if not vehicle.is_valid_cargo_crate(crate):
				result["reason"] = "invalid_cargo_crate"
			elif _find_personal_cargo_crate(state, str(crate.get("crate_instance_id", ""))).is_empty():
				result["reason"] = "cargo_crate_not_owned"
			elif cargo_slot < 0 or cargo_slot >= vehicle.get_available_cargo_slot_count():
				result["reason"] = "cargo_slot_damaged"
			elif vehicle.get_cargo_weight_kg() + float(crate.get("total_weight_kg", 0.0)) > vehicle.get_cargo_capacity_kg() + 0.001:
				result["reason"] = "cargo_overweight"
			elif vehicle.try_load_cargo_crate(crate, cargo_slot) < 0:
				result["reason"] = "cargo_slot_unavailable"
			else:
				slots[player_slot] = {}
				_remove_personal_cargo_crate(state, str(crate.get("crate_instance_id", "")))
				state["backpack_slot_items"] = slots
				_clear_invalid_current_selection(state, _typed_dictionary_array(slots))
				result["ok"] = true
		"unload":
			var cargo_slot := int(action.get("cargo_slot", -1))
			var player_slot := int(action.get("player_slot", -1))
			var manifest := vehicle.get_cargo_manifest()
			var crate: Dictionary = manifest[cargo_slot] if cargo_slot >= 0 and cargo_slot < manifest.size() else {}
			if crate.is_empty():
				result["reason"] = "cargo_slot_empty"
			elif player_slot < 0 or player_slot >= slots.size() or not (slots[player_slot] as Dictionary).is_empty():
				result["reason"] = "player_slot_unavailable"
			elif _personal_ingredient_total_weight(state) + float(crate.get("total_weight_kg", 0.0)) > _server_bag_weight_capacity_kg(state) + 0.001:
				result["reason"] = "personal_bag_full"
			else:
				var taken := vehicle.take_cargo_crate(cargo_slot)
				if taken.is_empty():
					result["reason"] = "cargo_slot_empty"
				else:
					slots[player_slot] = taken
					_add_personal_cargo_crate(state, taken)
					state["backpack_slot_items"] = slots
					result["ok"] = true
		"drop":
			var cargo_slot := int(action.get("cargo_slot", -1))
			var taken := vehicle.take_cargo_crate(cargo_slot)
			if taken.is_empty():
				result["reason"] = "cargo_slot_empty"
			else:
				var direction := _validated_throw_direction(action.get("direction", Vector3.ZERO), state)
				var item_state := _make_dropped_item_state(peer_id, taken, state, direction)
				if item_state.is_empty() or not _spawn_authoritative_dropped_item(item_state):
					vehicle.try_load_cargo_crate(taken, cargo_slot)
					result["reason"] = "spawn_failed"
				else:
					result["ok"] = true
					result["item_state"] = item_state
					reliable_world_event_ready.emit({
						"type": "dropped_item_spawned", "item_state": item_state, "tick": server_tick,
					})
		_:
			result["reason"] = "unsupported_action"
	player_states[peer_id] = state
	if previous_selection_id != str(state.get("current_tool_id", "")):
		reliable_world_event_ready.emit({
			"type": "tool_selected", "peer_id": peer_id,
			"tool_index": int(state.get("current_tool_index", -1)),
			"tool_id": str(state.get("current_tool_id", "")), "tick": server_tick,
		})
	var vehicle_id := vehicle.get_vehicle_id()
	if vehicle_states.has(vehicle_id):
		var vehicle_state: Dictionary = vehicle_states[vehicle_id]
		vehicle_state.merge(vehicle.get_network_state(), true)
		vehicle_states[vehicle_id] = vehicle_state
	return _fill_cargo_car_result(result, state, vehicle)


func _quantize_requested_item_weight(item: Dictionary, requested_weight_kg: float) -> float:
	var unit_weight := UnitWeightItem.get_unit_weight_kg(item)
	if unit_weight <= 0.0001 or requested_weight_kg <= 0.0001:
		return 0.0
	var unit_count := maxi(1, floori((requested_weight_kg + 0.0001) / unit_weight))
	return minf(UnitWeightItem.get_weight_kg(item), unit_weight * float(unit_count))


func server_cargo_crate_action(peer_id: int, action: Dictionary) -> Dictionary:
	var action_name := str(action.get("action", ""))
	var result := {"ok": false, "peer_id": peer_id, "action": action_name, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return _emit_cargo_crate_result(result)
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		result["reason"] = "player_unavailable"
		return _emit_cargo_crate_result(result)
	if action_name == "place":
		return _server_place_carried_cargo_crate(peer_id, action, state, result)
	var crate_id := str(action.get("crate_id", ""))
	var tool_ref := _registered_tool_ref_by_id(crate_id)
	var crate_node = _node_for_tool_ref(tool_ref)
	if not crate_node is CargoCrateGround or not is_instance_valid(crate_node):
		result["reason"] = "unknown_crate"
		return _emit_cargo_crate_result(result)
	var crate := crate_node as CargoCrateGround
	if action_name == "close":
		result["ok"] = crate.release_user(peer_id) or crate.active_user_peer_id == 0
		return _fill_cargo_crate_result(result, state, crate)
	if not _can_server_interact_with_position(state, crate.global_position, 4.5):
		result["reason"] = "crate_out_of_range"
		return _emit_cargo_crate_result(result)
	if action_name != "pickup" and not crate.try_acquire_user(peer_id):
		result["reason"] = "crate_in_use"
		return _emit_cargo_crate_result(result)
	match action_name:
		"open":
			result["ok"] = true
		"store":
			var slots: Array = (state.get("backpack_slot_items", []) as Array).duplicate(true)
			var player_slot := int(action.get("player_slot", -1))
			var item: Dictionary = slots[player_slot] as Dictionary \
				if player_slot >= 0 and player_slot < slots.size() and slots[player_slot] is Dictionary else {}
			var crate_data := crate.get_crate_data()
			var stored: Dictionary = crate_data.get("stored_item", {}) as Dictionary \
				if crate_data.get("stored_item", {}) is Dictionary else {}
			var remaining_capacity := maxf(0.0, float(crate_data.get("capacity_kg", 0.0)) - CargoCrateData.item_weight_kg(stored))
			var is_crop_transfer := CargoCrateData.is_mergeable_crop_item(item)
			var requested_weight_kg := float(action.get("requested_weight_kg", 0.0))
			var wants_unit_transfer := requested_weight_kg > 0.0001
			var requested_unit_weight := _quantize_requested_item_weight(item, requested_weight_kg) \
				if wants_unit_transfer else 0.0
			var is_unit_transfer := requested_unit_weight > 0.0001 and CargoCrateData.is_unit_weight_item(item)
			if item.is_empty():
				result["reason"] = "player_slot_empty"
			elif str(item.get("kind", "")) == "cargo_crate":
				result["reason"] = "nested_crate"
			elif not stored.is_empty() and not CargoCrateData.can_merge_unit_weight_items(stored, item):
				result["reason"] = "crate_not_empty"
			elif remaining_capacity <= 0.001:
				result["reason"] = "crate_overweight"
			else:
				var requested_weight := CargoCrateData.item_weight_kg(item)
				var transfer_item := UnitWeightItem.make_piece(
					item,
					minf(requested_unit_weight, remaining_capacity) if is_unit_transfer \
					else (minf(requested_weight, remaining_capacity) if is_crop_transfer else requested_weight)
				) if is_unit_transfer or is_crop_transfer else item.duplicate(true)
				var transfer_weight := CargoCrateData.item_weight_kg(transfer_item)
				if (not is_crop_transfer and not is_unit_transfer and requested_weight > remaining_capacity + 0.001) \
						or transfer_item.is_empty():
					result["reason"] = "crate_overweight"
				else:
					var consumed := _consume_dropped_item_from_player(state, transfer_item)
					if consumed.is_empty() or not crate.set_stored_item(consumed):
						if not consumed.is_empty():
							_restore_dropped_item_to_player(state, consumed)
						result["reason"] = "store_failed"
					else:
						result["ok"] = true
						result["transferred_weight_kg"] = transfer_weight
						result["requested_weight_kg"] = requested_weight
						result["remaining_in_backpack_kg"] = maxf(0.0, requested_weight - transfer_weight)
		"take":
			var stored: Dictionary = crate.get_crate_data().get("stored_item", {})
			var requested_unit_weight := _quantize_requested_item_weight(
				stored, float(action.get("requested_weight_kg", 0.0))
			) if float(action.get("requested_weight_kg", 0.0)) > 0.0001 else 0.0
			var taken_preview := UnitWeightItem.make_piece(stored, requested_unit_weight) \
				if requested_unit_weight > 0.0001 else stored.duplicate(true)
			if stored.is_empty() or taken_preview.is_empty():
				result["reason"] = "crate_empty"
			elif not _can_add_dropped_item_to_player(state, taken_preview):
				result["reason"] = "personal_bag_full"
			else:
				var taken := crate.take_stored_weight(requested_unit_weight) \
					if requested_unit_weight > 0.0001 else crate.take_stored_item()
				_restore_dropped_item_to_player(state, taken)
				result["ok"] = true
		"drop":
			var stored: Dictionary = crate.get_crate_data().get("stored_item", {})
			var requested_unit_weight := _quantize_requested_item_weight(
				stored, float(action.get("requested_weight_kg", 0.0))
			) if float(action.get("requested_weight_kg", 0.0)) > 0.0001 else 0.0
			var taken := crate.take_stored_weight(requested_unit_weight) \
				if requested_unit_weight > 0.0001 else crate.take_stored_item()
			if taken.is_empty():
				result["reason"] = "crate_empty"
			else:
				var direction := _validated_throw_direction(action.get("direction", Vector3.ZERO), state)
				var item_state := _make_dropped_item_state(peer_id, taken, state, direction)
				if item_state.is_empty() or not _spawn_authoritative_dropped_item(item_state):
					crate.set_stored_item(taken)
					result["reason"] = "spawn_failed"
				else:
					result["ok"] = true
					result["item_state"] = item_state
					reliable_world_event_ready.emit({
						"type": "dropped_item_spawned", "item_state": item_state, "tick": server_tick,
					})
		"pickup":
			var carried := crate.get_crate_data()
			if crate.active_user_peer_id > 0 and crate.active_user_peer_id != peer_id:
				result["reason"] = "crate_in_use"
			elif not _can_add_dropped_item_to_player(state, carried):
				result["reason"] = "personal_bag_full"
			else:
				_restore_dropped_item_to_player(state, carried)
				player_states[peer_id] = state
				result["ok"] = true
				result["crate_removed"] = true
				result["crate_data"] = carried
				result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
				_destroy_registered_tool_ref(tool_ref)
				return _emit_cargo_crate_result(result)
		_:
			result["reason"] = "unsupported_action"
	if bool(result.get("ok", false)):
		var placed_state: Dictionary = placed_tool_states.get(crate_id, {})
		placed_state["crate_data"] = crate.get_crate_data()
		placed_tool_states[crate_id] = placed_state
		player_states[peer_id] = state
	return _fill_cargo_crate_result(result, state, crate)


func _server_place_carried_cargo_crate(
	peer_id: int, action: Dictionary, state: Dictionary, result: Dictionary
) -> Dictionary:
	var slot_index := int(action.get("slot_index", -1))
	var slots: Array = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	var item: Dictionary = slots[slot_index] as Dictionary \
		if slot_index >= 0 and slot_index < slots.size() and slots[slot_index] is Dictionary else {}
	var normalized := CargoCrateData.normalize(item)
	if normalized.is_empty() or str(item.get("kind", "")) != "cargo_crate":
		result["reason"] = "crate_not_held"
		return _emit_cargo_crate_result(result)
	var scene_path := str(normalized.get("model_path", ""))
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	var target_position := _vector3_from_value(action.get("target_position", player_position + Vector3.FORWARD * 2.5))
	var yaw := float(action.get("yaw", state.get("yaw", 0.0)))
	var placement := _validate_free_placement(peer_id, scene_path, target_position, yaw)
	if not bool(placement.get("ok", false)):
		result["reason"] = str(placement.get("reason", "invalid_placement"))
		return _emit_cargo_crate_result(result)
	var packed := load(scene_path) as PackedScene
	var node := packed.instantiate() as CargoCrateGround if packed != null else null
	if node == null or GlobalVar.gameworld == null:
		result["reason"] = "missing_crate_scene"
		return _emit_cargo_crate_result(result)
	var consumed := _consume_dropped_item_from_player(state, normalized)
	if consumed.is_empty():
		node.queue_free()
		result["reason"] = "crate_not_held"
		return _emit_cargo_crate_result(result)
	var crate_id := "ground_%s" % str(normalized.get("crate_instance_id", "crate"))
	node.name = crate_id.replace(":", "_")
	node.set_meta("network_device_id", crate_id)
	node.setup_crate(consumed)
	GlobalVar.gameworld.add_child(node)
	node.global_position = _vector3_from_value(placement.get("position", target_position))
	node.rotation.y = yaw
	placed_tool_states[crate_id] = {
		"tool_id": crate_id, "device_id": crate_id, "tool_name": "cargo_crate",
		"owner_peer_id": peer_id, "team": "", "path": str(node.get_path()),
		"position": node.global_position, "yaw": yaw,
		"hp": float(consumed.get("current_hp", 500.0)), "max_hp": 500.0,
		"cooldown_left": 0.0, "scene_path": scene_path, "free_placement": true,
		"crate_data": consumed.duplicate(true),
	}
	_clear_invalid_current_selection(state, _typed_dictionary_array(state.get("backpack_slot_items", []) as Array))
	player_states[peer_id] = state
	result["ok"] = true
	result["crate_id"] = crate_id
	result["crate_removed_from_bag"] = true
	result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	reliable_world_event_ready.emit({
		"type": "cargo_crate_placed", "crate": placed_tool_states[crate_id].duplicate(true), "tick": server_tick,
	})
	return _emit_cargo_crate_result(result)


func _fill_cargo_crate_result(result: Dictionary, state: Dictionary, crate: CargoCrateGround) -> Dictionary:
	result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	result["crate_data"] = crate.get_crate_data()
	return _emit_cargo_crate_result(result)


func _emit_cargo_crate_result(result: Dictionary) -> Dictionary:
	reliable_world_event_ready.emit({"type": "cargo_crate_action_result", "data": result, "tick": server_tick})
	return result


func _fill_cargo_car_result(result: Dictionary, state: Dictionary, vehicle: VehicleBase) -> Dictionary:
	result["player_slots"] = (state.get("backpack_slot_items", []) as Array).duplicate(true)
	result["cargo_manifest"] = vehicle.get_cargo_manifest()
	result["available_slots"] = vehicle.get_available_cargo_slot_count()
	result["cargo_weight_kg"] = vehicle.get_cargo_weight_kg()
	return _emit_cargo_car_result(result)


func _emit_cargo_car_result(result: Dictionary) -> Dictionary:
	reliable_world_event_ready.emit({"type": "cargo_car_action_result", "data": result, "tick": server_tick})
	return result


func request_cargo_delivery_preview(
	building_id: String,
	building_name: String,
	team: String,
	entrant_kind: String,
	peer_id: int,
	vehicle_id := ""
) -> Dictionary:
	if is_client_proxy() or not player_states.has(peer_id):
		return {}
	var state: Dictionary = player_states[peer_id]
	if bool(state.get("cargo_delivery_modal", false)):
		return {}
	var crates: Array[Dictionary] = []
	if entrant_kind == "cargo_car":
		var vehicle := _find_vehicle(vehicle_id)
		if vehicle == null or vehicle.driver_peer_id != peer_id:
			return {}
		crates = vehicle.get_cargo_manifest()
	else:
		var slots: Array = state.get("backpack_slot_items", [])
		var selected_slot := int(state.get("current_tool_index", -1))
		for index in range(slots.size()):
			var item: Dictionary = slots[index] as Dictionary if slots[index] is Dictionary else {}
			crates.append(item if index == selected_slot and str(item.get("kind", "")) == "cargo_crate" else {})
	var preview := FoodOrderEmitter.build_cargo_delivery_preview(
		building_id, building_name, team, entrant_kind, peer_id, vehicle_id, crates
	)
	if preview.is_empty():
		return {}
	state["cargo_delivery_modal"] = true
	state["cargo_delivery_context"] = {
		"building_id": building_id,
		"task_id": int(preview.get("task_id", 0)),
		"entrant_kind": entrant_kind,
		"vehicle_id": vehicle_id,
	}
	player_states[peer_id] = state
	if entrant_kind == "cargo_car" and vehicle_states.has(vehicle_id):
		var vehicle_state: Dictionary = vehicle_states[vehicle_id]
		vehicle_state["input"] = {"throttle": 0.0, "steering": 0.0, "brake": 1.0}
		vehicle_states[vehicle_id] = vehicle_state
	reliable_world_event_ready.emit({"type": "cargo_delivery_preview", "peer_id": peer_id, "data": preview, "tick": server_tick})
	return preview


func server_cargo_delivery_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": str(action.get("action", "")), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return _emit_cargo_delivery_result(result)
	var state: Dictionary = player_states[peer_id]
	var previous_selection_id := str(state.get("current_tool_id", ""))
	var context: Dictionary = state.get("cargo_delivery_context", {})
	if str(action.get("action", "")) == "cancel":
		state["cargo_delivery_modal"] = false
		state["cargo_delivery_context"] = {}
		player_states[peer_id] = state
		result["ok"] = true
		return _emit_cargo_delivery_result(result)
	if not bool(state.get("cargo_delivery_modal", false)) or context.is_empty():
		result["reason"] = "delivery_not_pending"
		return _emit_cargo_delivery_result(result)
	if str(context.get("building_id", "")) != str(action.get("building_id", "")) \
			or int(context.get("task_id", 0)) != int(action.get("task_id", 0)):
		result["reason"] = "delivery_context_changed"
		return _emit_cargo_delivery_result(result)
	var entrant_kind := str(context.get("entrant_kind", ""))
	var vehicle_id := str(context.get("vehicle_id", ""))
	var crates: Array[Dictionary] = []
	var vehicle: VehicleBase = null
	if entrant_kind == "cargo_car":
		vehicle = _find_vehicle(vehicle_id)
		if vehicle == null or vehicle.driver_peer_id != peer_id:
			result["reason"] = "vehicle_unavailable"
			return _emit_cargo_delivery_result(result)
		crates = vehicle.get_cargo_manifest()
	else:
		var slots: Array = state.get("backpack_slot_items", [])
		var selected_slot := int(state.get("current_tool_index", -1))
		for index in range(slots.size()):
			var item: Dictionary = slots[index] as Dictionary if slots[index] is Dictionary else {}
			crates.append(item if index == selected_slot and str(item.get("kind", "")) == "cargo_crate" else {})
	var preview := FoodOrderEmitter.build_cargo_delivery_preview(
		str(context.get("building_id", "")),
		str(action.get("building_name", "交付点")),
		str(state.get("team", "")), entrant_kind, peer_id, vehicle_id, crates,
		int(context.get("task_id", 0))
	)
	if preview.is_empty():
		result["reason"] = "cargo_or_task_changed"
		return _emit_cargo_delivery_result(result)
	_apply_cargo_consumption(crates, preview.get("consumption", []) as Array)
	if entrant_kind == "cargo_car":
		vehicle.set_cargo_manifest(crates)
		if vehicle_states.has(vehicle_id):
			var vehicle_state: Dictionary = vehicle_states[vehicle_id]
			vehicle_state.merge(vehicle.get_network_state(), true)
			vehicle_states[vehicle_id] = vehicle_state
		result["cargo_manifest"] = vehicle.get_cargo_manifest()
	else:
		state["backpack_slot_items"] = crates
		_rebuild_personal_cargo_crates_from_layout(state)
		_clear_invalid_current_selection(state, crates)
		result["player_slots"] = crates.duplicate(true)
	var progress_result := FoodOrderEmitter.apply_cargo_delivery_progress(
		str(state.get("team", "")), int(context.get("task_id", 0)), preview.get("delivered_now", {}) as Dictionary
	)
	state["cargo_delivery_modal"] = false
	state["cargo_delivery_context"] = {}
	player_states[peer_id] = state
	if previous_selection_id != str(state.get("current_tool_id", "")):
		reliable_world_event_ready.emit({
			"type": "tool_selected", "peer_id": peer_id,
			"tool_index": int(state.get("current_tool_index", -1)),
			"tool_id": str(state.get("current_tool_id", "")), "tick": server_tick,
		})
	result["ok"] = true
	result["task_id"] = int(context.get("task_id", 0))
	result["completed"] = bool(progress_result.get("completed", false))
	result["reward_money"] = int(progress_result.get("reward_money", 0))
	result["delivered_now"] = preview.get("delivered_now", {})
	return _emit_cargo_delivery_result(result)


func _apply_cargo_consumption(crates: Array[Dictionary], consumption: Array) -> void:
	for entry_value: Variant in consumption:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var slot_index := int(entry.get("slot_index", -1))
		if slot_index < 0 or slot_index >= crates.size() or crates[slot_index].is_empty():
			continue
		var crate := CargoCrateData.normalize(crates[slot_index])
		var delivery := CargoCrateData.get_delivery_content(crate)
		if str(delivery.get("content_id", "")) != str(entry.get("content_id", "")) \
				or str(delivery.get("unit", "")) != str(entry.get("unit", "")):
			continue
		crates[slot_index] = CargoCrateData.consume_delivery_quantity(
			crate, float(entry.get("quantity", 0.0))
		)


func _rebuild_personal_cargo_crates_from_layout(state: Dictionary) -> void:
	var crates: Array[Dictionary] = []
	for item_value: Variant in state.get("backpack_slot_items", []):
		if item_value is Dictionary and str((item_value as Dictionary).get("kind", "")) == "cargo_crate":
			crates.append(_normalize_cargo_crate(item_value as Dictionary))
	state["personal_cargo_crates"] = crates


func _emit_cargo_delivery_result(result: Dictionary) -> Dictionary:
	reliable_world_event_ready.emit({"type": "cargo_delivery_result", "data": result, "tick": server_tick})
	return result


func _typed_dictionary_array(values: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for value: Variant in values:
		result.append(value as Dictionary if value is Dictionary else {})
	return result


func _normalize_cargo_crate(value: Dictionary) -> Dictionary:
	return CargoCrateData.normalize(value)


func _add_personal_cargo_crate(state: Dictionary, crate: Dictionary) -> void:
	var crates: Array = (state.get("personal_cargo_crates", []) as Array).duplicate(true)
	crates.append(_normalize_cargo_crate(crate))
	state["personal_cargo_crates"] = crates


func _remove_personal_cargo_crate(state: Dictionary, crate_instance_id: String) -> Dictionary:
	var crates: Array = (state.get("personal_cargo_crates", []) as Array).duplicate(true)
	for index in range(crates.size()):
		var crate: Dictionary = crates[index] as Dictionary if crates[index] is Dictionary else {}
		if str(crate.get("crate_instance_id", "")) == crate_instance_id:
			crates.remove_at(index)
			state["personal_cargo_crates"] = crates
			return crate
	return {}


func _find_personal_cargo_crate(state: Dictionary, crate_instance_id: String) -> Dictionary:
	for crate_value: Variant in state.get("personal_cargo_crates", []):
		if crate_value is Dictionary and str((crate_value as Dictionary).get("crate_instance_id", "")) == crate_instance_id:
			return (crate_value as Dictionary).duplicate(true)
	return {}


func server_inventory_layout_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": "sync", "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	var slots_value: Variant = action.get("slots", [])
	if not slots_value is Array or (slots_value as Array).size() != _server_bag_capacity(state):
		result["reason"] = "invalid_slot_count"
		return result
	var normalized_slots: Array[Dictionary] = []
	var tool_ids := {}
	var equipment_ids := {}
	var ingredient_weights := {}
	var dish_servings := {}
	var dish_weights := {}
	var cargo_crate_ids := {}
	var authoritative_livestock_items := {}
	for existing_value: Variant in state.get("backpack_slot_items", []):
		if not existing_value is Dictionary:
			continue
		var existing := existing_value as Dictionary
		var livestock_instance_id := str(existing.get("livestock_instance_id", ""))
		if str(existing.get("tool_id", "")).begins_with("animal_") and not livestock_instance_id.is_empty():
			authoritative_livestock_items[livestock_instance_id] = existing.duplicate(true)
	for item_value: Variant in slots_value:
		if not item_value is Dictionary:
			result["reason"] = "invalid_slot_item"
			return result
		var item := item_value as Dictionary
		var normalized: Dictionary = {}
		match str(item.get("kind", "")):
			"":
				pass
			"tool", "weapon":
				var tool_id := str(item.get("tool_id", ""))
				if tool_id.is_empty() or (tool_ids.has(tool_id) and not _tool_allows_multiple(tool_id)):
					result["reason"] = "invalid_tool_layout"
					return result
				tool_ids[tool_id] = int(tool_ids.get(tool_id, 0)) + 1
				if tool_id.begins_with("animal_"):
					var livestock_instance_id := str(item.get("livestock_instance_id", ""))
					if livestock_instance_id.is_empty() or not authoritative_livestock_items.has(livestock_instance_id):
						result["reason"] = "invalid_livestock_item"
						return result
					normalized = (authoritative_livestock_items[livestock_instance_id] as Dictionary).duplicate(true)
					authoritative_livestock_items.erase(livestock_instance_id)
				else:
					normalized = {"kind": "tool", "tool_id": tool_id}
			"equipment":
				var equipment_id := str(item.get("equipment_id", ""))
				var definition := EquipmentCatalog.get_definition(equipment_id)
				if definition.is_empty() or equipment_ids.has(equipment_id):
					result["reason"] = "invalid_equipment_layout"
					return result
				equipment_ids[equipment_id] = true
				normalized = _server_equipment_item(state, equipment_id)
			"ingredient":
				var ingredient_id := str(item.get("ingredient_id", ""))
				var weight_kg := maxf(0.0, float(item.get("weight_kg", 0.0)))
				var is_chopped := bool(item.get("is_chopped", false))
				if IngredientCatalog.get_definition(ingredient_id).is_empty() or weight_kg <= 0.0:
					result["reason"] = "invalid_ingredient_layout"
					return result
				var key := _personal_ingredient_key(ingredient_id, is_chopped)
				ingredient_weights[key] = float(ingredient_weights.get(key, 0.0)) + weight_kg
				normalized = {"kind": "ingredient", "ingredient_id": ingredient_id, "weight_kg": weight_kg, "is_chopped": is_chopped}
			"dish":
				var dish_id := str(item.get("dish_id", ""))
				var servings := int(item.get("servings", 0))
				var weight_kg := maxf(0.0, float(item.get("weight_kg", 0.0)))
				if DishCatalog.get_definition(dish_id).is_empty() or servings <= 0 or weight_kg <= 0.0:
					result["reason"] = "invalid_dish_layout"
					return result
				dish_servings[dish_id] = int(dish_servings.get(dish_id, 0)) + servings
				dish_weights[dish_id] = float(dish_weights.get(dish_id, 0.0)) + weight_kg
				normalized = {"kind": "dish", "dish_id": dish_id, "servings": servings, "weight_kg": weight_kg}
			"cargo_crate":
				normalized = _normalize_cargo_crate(item)
				var crate_id := str(normalized.get("crate_instance_id", ""))
				if crate_id.is_empty() or cargo_crate_ids.has(crate_id) \
						or float(normalized.get("total_weight_kg", 0.0)) <= 0.0:
					result["reason"] = "invalid_cargo_crate_layout"
					return result
				cargo_crate_ids[crate_id] = _cargo_crate_signature(normalized)
			_:
				result["reason"] = "unsupported_slot_item"
				return result
		normalized_slots.append(normalized)
	if not _inventory_layout_matches_state(state, tool_ids, equipment_ids, ingredient_weights, dish_servings, dish_weights, cargo_crate_ids):
		result["reason"] = "layout_inventory_mismatch"
		return result
	state["backpack_slot_items"] = normalized_slots
	state["backpack_layout_valid"] = true
	var previous_tool_index := int(state.get("current_tool_index", -1))
	var previous_tool_id := str(state.get("current_tool_id", ""))
	var selected_slot := clampi(
		int(action.get("selected_slot", previous_tool_index)),
		-1,
		PLAYER_HOTBAR_SLOT_COUNT - 1
	)
	var requested_selection_id := str(action.get("selected_id", previous_tool_id))
	var expected_selection_id := _selection_id_for_layout_slot(normalized_slots, selected_slot)
	state["current_tool_index"] = selected_slot
	state["current_tool_id"] = requested_selection_id if requested_selection_id == expected_selection_id else ""
	player_states[peer_id] = state
	if previous_tool_index != int(state["current_tool_index"]) \
			or previous_tool_id != str(state["current_tool_id"]):
		reliable_world_event_ready.emit({
			"type": "tool_selected",
			"peer_id": peer_id,
			"tool_index": int(state["current_tool_index"]),
			"tool_id": str(state["current_tool_id"]),
			"tick": server_tick,
		})
	result["ok"] = true
	return result


func _selection_id_for_layout_slot(slots: Array[Dictionary], slot_index: int) -> String:
	if slot_index < 0 or slot_index >= mini(PLAYER_HOTBAR_SLOT_COUNT, slots.size()):
		return ""
	var item: Dictionary = slots[slot_index]
	match str(item.get("kind", "")):
		"tool", "weapon":
			return str(item.get("tool_id", ""))
		"ingredient":
			var ingredient_id := str(item.get("ingredient_id", ""))
			if ingredient_id.is_empty():
				return ""
			return HANDHELD_INGREDIENT_PREFIX + ingredient_id \
				+ (":chopped" if bool(item.get("is_chopped", false)) else ":whole")
		"dish":
			var dish_id := str(item.get("dish_id", ""))
			return "dish:" + dish_id if not dish_id.is_empty() else ""
		"cargo_crate":
			return "cargo_crate:" + str(item.get("crate_size", "medium"))
	return ""


func _clear_invalid_current_selection(state: Dictionary, slots: Array[Dictionary]) -> void:
	var current_id := str(state.get("current_tool_id", ""))
	if current_id.is_empty():
		return
	var current_index := int(state.get("current_tool_index", -1))
	if current_id != _selection_id_for_layout_slot(slots, current_index):
		state["current_tool_id"] = ""


func _inventory_layout_matches_state(
	state: Dictionary,
	tool_ids: Dictionary,
	equipment_ids: Dictionary,
	ingredient_weights: Dictionary,
	dish_servings: Dictionary,
	dish_weights: Dictionary,
	cargo_crate_ids: Dictionary
) -> bool:
	var expected_tools := {}
	for bucket in ["primary_weapon_ids", "special_tool_ids"]:
		var values: Variant = state.get(bucket, [])
		if values is Array:
			for value: Variant in values:
				if not str(value).is_empty():
					var tool_id := str(value)
					expected_tools[tool_id] = int(expected_tools.get(tool_id, 0)) + 1
	if tool_ids != expected_tools:
		return false
	var expected_equipment := {}
	var owned_value: Variant = state.get("owned_equipment_ids", [])
	if owned_value is Array:
		for value: Variant in owned_value:
			var equipment_id := str(value)
			if not _is_equipment_equipped(state, equipment_id):
				expected_equipment[equipment_id] = true
	if equipment_ids != expected_equipment:
		return false
	if not _float_dictionary_matches(ingredient_weights, state.get("personal_ingredients", {})):
		return false
	if dish_servings != (state.get("personal_dishes", {}) as Dictionary):
		return false
	if not _float_dictionary_matches(dish_weights, state.get("personal_dish_weights", {})):
		return false
	var expected_crate_ids := {}
	for crate_value: Variant in (state.get("personal_cargo_crates", []) as Array):
		if crate_value is Dictionary:
			var normalized_crate := _normalize_cargo_crate(crate_value as Dictionary)
			expected_crate_ids[str(normalized_crate.get("crate_instance_id", ""))] = _cargo_crate_signature(normalized_crate)
	expected_crate_ids.erase("")
	return cargo_crate_ids == expected_crate_ids


func _cargo_crate_signature(crate: Dictionary) -> String:
	return "%s|%s|%s|%.6f|%.6f|%s" % [
		str(crate.get("content_kind", "")),
		str(crate.get("content_id", "")),
		str(crate.get("content_unit", "")),
		float(crate.get("content_quantity", 0.0)),
		float(crate.get("total_weight_kg", 0.0)),
		var_to_str(crate.get("stored_item", {})),
	]


func _float_dictionary_matches(first: Dictionary, second_value: Variant) -> bool:
	if not second_value is Dictionary:
		return first.is_empty()
	var second := second_value as Dictionary
	if first.size() != second.size():
		return false
	for key: Variant in first.keys():
		if not second.has(key) or not is_equal_approx(float(first[key]), float(second[key])):
			return false
	return true


func server_equipment_action(peer_id: int, action: Dictionary) -> Dictionary:
	var action_name := str(action.get("action", ""))
	var result := {"ok": false, "peer_id": peer_id, "action": action_name, "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		result["reason"] = "player_unavailable"
		return result
	match action_name:
		"equip", "swap":
			var equipment_id := str(action.get("equipment_id", ""))
			var equipment_type := str(action.get("equipment_type", ""))
			var state_key := _equipment_state_key(equipment_type)
			var definition := EquipmentCatalog.get_definition(equipment_id)
			var owned_ids: Array = state.get("owned_equipment_ids", [])
			var old_equipment_id := str(state.get(state_key, "")) if not state_key.is_empty() else ""
			var slot_index := int(action.get("slot_index", -1))
			var extra_slots := int(definition.get("extra_slots", 0))
			if state_key.is_empty() or definition.is_empty() or str(definition.get("equipment_type", "")) != equipment_type:
				result["reason"] = "invalid_equipment"
			elif not owned_ids.has(equipment_id) or equipment_id == old_equipment_id:
				result["reason"] = "equipment_not_owned"
			elif action_name == "equip" and not old_equipment_id.is_empty():
				result["reason"] = "equipment_slot_occupied"
			elif action_name == "equip" and (slot_index < 0 or slot_index >= BASE_PLAYER_BAG_SLOTS):
				result["reason"] = "invalid_equip_source"
			elif action_name == "swap" and (old_equipment_id.is_empty() or slot_index < 0 or slot_index >= BASE_PLAYER_BAG_SLOTS):
				result["reason"] = "invalid_swap_source"
			elif equipment_type == "backpack" and (extra_slots <= 0 or extra_slots > MAX_EQUIPMENT_EXTRA_SLOTS or extra_slots % BAG_SLOTS_PER_ROW != 0):
				result["reason"] = "invalid_slot_expansion"
			else:
				var overflow_value: Variant = action.get("overflow_items", [])
				var overflow_items: Array = overflow_value as Array if overflow_value is Array else []
				var maximum_overflow := EquipmentCatalog.get_extra_slots(old_equipment_id) if equipment_type == "backpack" else 0
				var simulated := state.duplicate(true)
				var valid_overflow := overflow_items.size() <= maximum_overflow
				for item_value: Variant in overflow_items:
					if not valid_overflow or not item_value is Dictionary or _consume_dropped_item_from_player(simulated, item_value as Dictionary).is_empty():
						valid_overflow = false
						break
				if not state_key.is_empty():
					simulated[state_key] = equipment_id
				if valid_overflow and _server_backpack_entry_count(simulated) > _server_bag_capacity(simulated):
					valid_overflow = false
				if not valid_overflow:
					result["reason"] = "overflow_mismatch"
				else:
					var dropped_states := _drop_equipment_overflow_items(peer_id, state, overflow_items)
					if dropped_states.size() != overflow_items.size():
						_rollback_equipment_overflow(state, dropped_states)
						result["reason"] = "drop_spawn_failed"
					else:
						state[state_key] = equipment_id
						result["ok"] = true
						result["equipment_id"] = equipment_id
						result["old_equipment_id"] = old_equipment_id
						result["equipment_item"] = _server_equipment_item(state, equipment_id)
						result["old_equipment_item"] = _server_equipment_item(state, old_equipment_id)
						result["equipment_type"] = equipment_type
						result["slot_index"] = slot_index
						result["dropped_item_states"] = dropped_states
		"unequip":
			var equipment_type := str(action.get("equipment_type", ""))
			var state_key := _equipment_state_key(equipment_type)
			var equipment_id := str(state.get(state_key, "")) if not state_key.is_empty() else ""
			var definition := EquipmentCatalog.get_definition(equipment_id)
			var target_slot_index := int(action.get("target_slot_index", -1))
			var overflow_value: Variant = action.get("overflow_items", [])
			var overflow_items: Array = overflow_value as Array if overflow_value is Array else []
			var extra_slots := int(definition.get("extra_slots", 0)) if equipment_type == "backpack" else 0
			if equipment_id.is_empty() or definition.is_empty():
				result["reason"] = "equipment_slot_empty"
			elif target_slot_index < 0 or target_slot_index >= BASE_PLAYER_BAG_SLOTS:
				result["reason"] = "invalid_target_slot"
			elif overflow_items.size() > extra_slots:
				result["reason"] = "invalid_overflow"
			else:
				var simulated := state.duplicate(true)
				var valid_overflow := true
				for item_value: Variant in overflow_items:
					if not item_value is Dictionary or _consume_dropped_item_from_player(simulated, item_value as Dictionary).is_empty():
						valid_overflow = false
						break
				simulated[state_key] = ""
				if valid_overflow and _server_backpack_entry_count(simulated) > _server_bag_capacity(simulated):
					valid_overflow = false
				if not valid_overflow:
					result["reason"] = "overflow_mismatch"
				else:
					var dropped_states := _drop_equipment_overflow_items(peer_id, state, overflow_items)
					if dropped_states.size() != overflow_items.size():
						_rollback_equipment_overflow(state, dropped_states)
						result["reason"] = "drop_spawn_failed"
					else:
						state[state_key] = ""
						result["ok"] = true
						result["equipment_id"] = equipment_id
						result["equipment_item"] = _server_equipment_item(state, equipment_id)
						result["equipment_type"] = equipment_type
						result["target_slot_index"] = target_slot_index
						result["dropped_item_states"] = dropped_states
		_:
			result["reason"] = "unsupported_action"
	if bool(result.get("ok", false)):
		_update_backpack_layout_after_equipment_action(state, result)
		player_states[peer_id] = state
	reliable_world_event_ready.emit({"type": "equipment_action_result", "data": result, "tick": server_tick})
	return result


func _equipment_state_key(equipment_type: String) -> String:
	match equipment_type:
		"backpack": return "equipped_backpack_id"
		"chest_armor": return "equipped_chest_armor_id"
		"legwear": return "equipped_legwear_id"
	return ""


func _initialize_equipment_hp(value: Variant, owned_ids_value: Variant) -> Dictionary:
	var result: Dictionary = (value as Dictionary).duplicate(true) if value is Dictionary else {}
	if owned_ids_value is Array:
		for equipment_id_value: Variant in owned_ids_value:
			var equipment_id := str(equipment_id_value)
			var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
			if max_hp > 0.0:
				result[equipment_id] = clampf(float(result.get(equipment_id, max_hp)), 0.0, max_hp)
	return result


func _set_server_equipment_hp(state: Dictionary, equipment_id: String, current_hp: float) -> void:
	var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
	if max_hp <= 0.0:
		return
	var values: Dictionary = (state.get("equipment_hp", {}) as Dictionary).duplicate(true)
	values[equipment_id] = clampf(current_hp, 0.0, max_hp)
	state["equipment_hp"] = values


func _server_equipment_item(state: Dictionary, equipment_id: String) -> Dictionary:
	var definition := EquipmentCatalog.get_definition(equipment_id)
	if definition.is_empty():
		return {}
	var item := {
		"kind": "equipment",
		"equipment_id": equipment_id,
		"equipment_type": str(definition.get("equipment_type", "")),
	}
	var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
	if max_hp > 0.0:
		var values: Dictionary = state.get("equipment_hp", {})
		item["current_hp"] = clampf(float(values.get(equipment_id, max_hp)), 0.0, max_hp)
		item["max_hp"] = max_hp
	return item


func _update_backpack_layout_after_equipment_action(state: Dictionary, result: Dictionary) -> void:
	var slots_value: Variant = state.get("backpack_slot_items", [])
	var slots: Array = (slots_value as Array).duplicate(true) if slots_value is Array else []
	var next_capacity := _server_bag_capacity(state)
	if slots.size() < next_capacity:
		var old_size := slots.size()
		slots.resize(next_capacity)
		for index in range(old_size, next_capacity):
			slots[index] = {}
	elif slots.size() > next_capacity:
		slots.resize(next_capacity)
	var action_name := str(result.get("action", ""))
	var equipment_id := str(result.get("equipment_id", ""))
	var definition := EquipmentCatalog.get_definition(equipment_id)
	if action_name == "equip":
		var slot_index := int(result.get("slot_index", -1))
		if slot_index >= 0 and slot_index < slots.size():
			slots[slot_index] = {}
	elif action_name == "swap":
		var slot_index := int(result.get("slot_index", -1))
		var old_equipment_id := str(result.get("old_equipment_id", ""))
		if slot_index >= 0 and slot_index < slots.size():
			slots[slot_index] = _server_equipment_item(state, old_equipment_id)
	elif action_name == "unequip":
		var target_slot_index := int(result.get("target_slot_index", -1))
		if target_slot_index >= 0 and target_slot_index < slots.size():
			slots[target_slot_index] = _server_equipment_item(state, equipment_id)
	state["backpack_slot_items"] = slots
	state["backpack_layout_valid"] = true


func _is_equipment_equipped(state: Dictionary, equipment_id: String) -> bool:
	return not equipment_id.is_empty() and equipment_id in [
		str(state.get("equipped_backpack_id", "")),
		str(state.get("equipped_chest_armor_id", "")),
		str(state.get("equipped_legwear_id", "")),
	]


func _drop_equipment_overflow_items(peer_id: int, state: Dictionary, items: Array) -> Array[Dictionary]:
	var dropped_states: Array[Dictionary] = []
	for item_value: Variant in items:
		var item := _consume_dropped_item_from_player(state, item_value as Dictionary)
		var angle := randf_range(0.0, TAU)
		var direction := Vector3(cos(angle), randf_range(0.12, 0.28), sin(angle)).normalized()
		var item_state := _make_dropped_item_state(peer_id, item, state, direction)
		if item_state.is_empty() or not _spawn_authoritative_dropped_item(item_state):
			_restore_dropped_item_to_player(state, item)
			continue
		dropped_states.append(item_state)
	return dropped_states


func _rollback_equipment_overflow(state: Dictionary, dropped_states: Array[Dictionary]) -> void:
	for item_state: Dictionary in dropped_states:
		_remove_authoritative_dropped_item(str(item_state.get("item_id", "")), false)
		var item_value: Variant = item_state.get("item", {})
		if item_value is Dictionary:
			_restore_dropped_item_to_player(state, item_value as Dictionary)


func _consume_dropped_item_from_player(state: Dictionary, requested: Dictionary) -> Dictionary:
	match str(requested.get("kind", "")):
		"tool", "weapon":
			var tool_id := str(requested.get("tool_id", ""))
			if not authoritative_tool_definitions.has(tool_id):
				return {}
			var requested_slot := int(requested.get("slot_index", -1))
			var requested_slot_item: Dictionary = {}
			var slots_value: Variant = state.get("backpack_slot_items", [])
			if slots_value is Array and requested_slot >= 0 and requested_slot < (slots_value as Array).size():
				var slot_value: Variant = (slots_value as Array)[requested_slot]
				if slot_value is Dictionary and str((slot_value as Dictionary).get("tool_id", "")) == tool_id:
					requested_slot_item = (slot_value as Dictionary).duplicate(true)
			for bucket in ["primary_weapon_ids", "special_tool_ids"]:
				var ids: Array = state.get(bucket, [])
				var index := ids.find(tool_id)
				if index >= 0:
					ids.remove_at(index)
					state[bucket] = ids
					var definition: Dictionary = authoritative_tool_definitions[tool_id]
					var dropped_tool := {
						"kind": str(requested.get("kind", "tool")),
						"tool_id": tool_id,
						"tool_bucket": bucket,
						"display_name": str(definition.get("name", definition.get("short", "道具"))),
					}
					if not requested_slot_item.is_empty():
						dropped_tool.merge(requested_slot_item, true)
						dropped_tool["tool_bucket"] = bucket
					if _uses_finite_ammo(tool_id):
						var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
						var ammo_state: Dictionary = ammo_states.get(tool_id, _default_weapon_ammo_state(tool_id))
						ammo_state["reload_remaining"] = 0.0
						ammo_state["reload_duration"] = 0.0
						dropped_tool["ammo_in_mag"] = int(ammo_state.get("ammo_in_mag", 0))
						dropped_tool["reserve_ammo"] = int(ammo_state.get("reserve_ammo", 0))
						ammo_states.erase(tool_id)
						state["weapon_ammo_states"] = ammo_states
					if not requested_slot_item.is_empty():
						var slots: Array = (state.get("backpack_slot_items", []) as Array).duplicate(true)
						slots[requested_slot] = {}
						state["backpack_slot_items"] = slots
					else:
						_server_layout_remove_item(state, dropped_tool)
					return dropped_tool
		"ingredient":
			var ingredient_id := str(requested.get("ingredient_id", ""))
			var weight_kg := maxf(0.0, float(requested.get("weight_kg", 0.0)))
			var is_chopped := bool(requested.get("is_chopped", false))
			var definition := IngredientCatalog.get_definition(ingredient_id)
			if definition.is_empty() or not _server_remove_personal_ingredient(state, ingredient_id, weight_kg, is_chopped):
				return {}
			return {
				"kind": "ingredient",
				"ingredient_id": ingredient_id,
				"weight_kg": weight_kg,
				"is_chopped": is_chopped,
				"display_name": ("切碎的" if is_chopped else "") + str(definition.get("display_name", ingredient_id)),
			}
		"dish":
			var dish_id := str(requested.get("dish_id", ""))
			var servings := int(requested.get("servings", 0))
			var weight_kg := maxf(0.0, float(requested.get("weight_kg", 0.0)))
			var definition := DishCatalog.get_definition(dish_id)
			if definition.is_empty() or not _server_remove_personal_dish(state, dish_id, servings, weight_kg):
				return {}
			return {
				"kind": "dish",
				"dish_id": dish_id,
				"servings": servings,
				"weight_kg": weight_kg,
				"display_name": str(definition.get("display_name", dish_id)),
			}
		"equipment":
			var equipment_id := str(requested.get("equipment_id", ""))
			var definition := EquipmentCatalog.get_definition(equipment_id)
			var equipment_ids: Array = state.get("owned_equipment_ids", [])
			if definition.is_empty() or _is_equipment_equipped(state, equipment_id) or not equipment_ids.has(equipment_id):
				return {}
			equipment_ids.erase(equipment_id)
			state["owned_equipment_ids"] = equipment_ids
			var dropped_equipment := {
				"kind": "equipment",
				"equipment_id": equipment_id,
				"equipment_type": str(definition.get("equipment_type", "")),
				"display_name": str(definition.get("name", equipment_id)),
			}
			var max_hp := EquipmentCatalog.get_max_hp(equipment_id)
			if max_hp > 0.0:
				var equipment_hp: Dictionary = state.get("equipment_hp", {})
				dropped_equipment["current_hp"] = clampf(float(equipment_hp.get(equipment_id, max_hp)), 0.0, max_hp)
				dropped_equipment["max_hp"] = max_hp
				equipment_hp.erase(equipment_id)
				state["equipment_hp"] = equipment_hp
			_server_layout_remove_item(state, dropped_equipment)
			return dropped_equipment
		"cargo_crate":
			var crate := _remove_personal_cargo_crate(state, str(requested.get("crate_instance_id", "")))
			if crate.is_empty():
				return {}
			_server_layout_remove_item(state, crate)
			return crate
	return {}


func _restore_dropped_item_to_player(state: Dictionary, item: Dictionary) -> void:
	match str(item.get("kind", "")):
		"tool", "weapon":
			var bucket := str(item.get("tool_bucket", "special_tool_ids"))
			if bucket != "primary_weapon_ids" and bucket != "special_tool_ids":
				bucket = "special_tool_ids"
			var ids: Array = state.get(bucket, [])
			var tool_id := str(item.get("tool_id", ""))
			if not tool_id.is_empty() and (not _player_has_tool(state, tool_id) or _tool_allows_multiple(tool_id)):
				ids.append(tool_id)
				state[bucket] = ids
				_server_layout_add_item(state, item)
				if _uses_finite_ammo(tool_id):
					var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
					ammo_states[tool_id] = {
						"ammo_in_mag": clampi(int(item.get("ammo_in_mag", _weapon_magazine_size(tool_id))), 0, _weapon_magazine_size(tool_id)),
						"reserve_ammo": maxi(0, int(item.get("reserve_ammo", _weapon_initial_reserve(tool_id)))),
						"reload_remaining": 0.0,
						"reload_duration": 0.0,
					}
					state["weapon_ammo_states"] = ammo_states
		"ingredient":
			_server_add_personal_ingredient(
				state,
				str(item.get("ingredient_id", "")),
				float(item.get("weight_kg", 0.0)),
				bool(item.get("is_chopped", false))
			)
		"dish":
			_server_add_personal_dish(
				state,
				str(item.get("dish_id", "")),
				int(item.get("servings", 0)),
				float(item.get("weight_kg", 0.0))
			)
		"equipment":
			var equipment_id := str(item.get("equipment_id", ""))
			var equipment_ids: Array = state.get("owned_equipment_ids", [])
			if not equipment_id.is_empty() and not equipment_ids.has(equipment_id):
				equipment_ids.append(equipment_id)
				state["owned_equipment_ids"] = equipment_ids
				_set_server_equipment_hp(state, equipment_id, float(item.get("current_hp", EquipmentCatalog.get_max_hp(equipment_id))))
				# Equipped items do not occupy backpack slots. This flag is present when
				# a death drop failed to spawn and the equipment is being rolled back.
				if not bool(item.get("was_equipped", false)):
					_server_layout_add_item(state, item)
		"cargo_crate":
			_add_personal_cargo_crate(state, item)
			_server_layout_add_item(state, item)


func _can_add_dropped_item_to_player(state: Dictionary, item: Dictionary) -> bool:
	if str(item.get("kind", "")) == "tool" or str(item.get("kind", "")) == "weapon":
		var tool_id := str(item.get("tool_id", ""))
		return (not _player_has_tool(state, tool_id) or _tool_allows_multiple(tool_id)) \
			and _server_backpack_entry_count(state) < _server_bag_capacity(state) \
			and _personal_ingredient_total_weight(state) + float(item.get("weight_kg", 0.0)) \
				<= _server_bag_weight_capacity_kg(state) + 0.001
	if str(item.get("kind", "")) == "equipment":
		var equipment_id := str(item.get("equipment_id", ""))
		return not (state.get("owned_equipment_ids", []) as Array).has(equipment_id) \
				and not EquipmentCatalog.get_definition(equipment_id).is_empty() \
				and _server_backpack_entry_count(state) < _server_bag_capacity(state)
	if str(item.get("kind", "")) == "ingredient":
		return _server_can_add_personal_ingredient(
			state,
			str(item.get("ingredient_id", "")),
			float(item.get("weight_kg", 0.0)),
			bool(item.get("is_chopped", false))
		)
	if str(item.get("kind", "")) == "dish":
		return _server_can_add_personal_dish(
			state,
			str(item.get("dish_id", "")),
			int(item.get("servings", 0)),
			float(item.get("weight_kg", 0.0))
		)
	if str(item.get("kind", "")) == "cargo_crate":
		return _server_backpack_entry_count(state) < _server_bag_capacity(state) \
			and _personal_ingredient_total_weight(state) + float(item.get("total_weight_kg", 0.0)) <= _server_bag_weight_capacity_kg(state) + 0.001
	return false


func _validated_throw_direction(direction_value: Variant, state: Dictionary) -> Vector3:
	if direction_value is Vector3 and (direction_value as Vector3).length_squared() > 0.1:
		var requested := (direction_value as Vector3).normalized()
		requested.y = clampf(requested.y, -0.35, 0.65)
		return requested.normalized()
	var yaw := float(state.get("yaw", 0.0))
	return (Basis(Vector3.UP, yaw) * Vector3.FORWARD).normalized()


func _make_dropped_item_state(peer_id: int, item: Dictionary, player_state: Dictionary, direction: Vector3) -> Dictionary:
	var model_path := ""
	if str(item.get("kind", "")) == "tool" or str(item.get("kind", "")) == "weapon":
		model_path = str((authoritative_tool_definitions.get(str(item.get("tool_id", "")), {}) as Dictionary).get("path", ""))
	elif str(item.get("kind", "")) == "ingredient":
		var ingredient_id := str(item.get("ingredient_id", ""))
		model_path = IngredientCatalog.get_model_path(ingredient_id, "chopped_item" if bool(item.get("is_chopped", false)) else "whole_item")
		if model_path.is_empty():
			model_path = IngredientCatalog.get_harvest_drop_scene_path(ingredient_id)
	elif str(item.get("kind", "")) == "dish":
		model_path = DishCatalog.get_model_path(str(item.get("dish_id", "")))
	elif str(item.get("kind", "")) == "equipment":
		model_path = EquipmentCatalog.get_scene_path(str(item.get("equipment_id", "")))
	elif str(item.get("kind", "")) == "cargo_crate":
		model_path = str(item.get("model_path", "res://assets/saved_glbs/cargo_crates.tscn"))
	if model_path.is_empty():
		return {}
	var item_id := _allocate_dropped_item_id("drop_%d" % peer_id)
	var player_position := _vector3_from_value(player_state.get("position", Vector3.ZERO))
	return {
		"item_id": item_id,
		"item": item.duplicate(true),
		"model_path": model_path,
		"position": player_position + Vector3.UP * 1.35 + direction * 0.65,
		"velocity": direction * 7.0 + Vector3.UP * 2.6,
		"angular_velocity": Vector3(2.5, 4.0, 1.8),
		"landed": false,
		"lifetime_remaining": PickupItem.LIFETIME_SECONDS,
	}


func _spawn_authoritative_dropped_item(state: Dictionary) -> bool:
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world == null:
		return false
	var item_id := str(state.get("item_id", ""))
	if item_id.is_empty() or dropped_item_nodes.has(item_id):
		push_warning("Rejected dropped item with empty or duplicate id: %s" % item_id)
		return false
	var pickup := PICKUP_ITEM_SCENE.instantiate() as PickupItem
	if pickup == null:
		return false
	world.add_child(pickup)
	pickup.setup(state)
	pickup.despawn_requested.connect(func(expired_id: String) -> void:
		_remove_authoritative_dropped_item(expired_id, true)
	)
	dropped_item_nodes[item_id] = pickup
	return true


func _allocate_dropped_item_id(prefix: String) -> String:
	var item_id := "%s_%d" % [prefix, next_dropped_item_id]
	next_dropped_item_id += 1
	while dropped_item_nodes.has(item_id):
		item_id = "%s_%d" % [prefix, next_dropped_item_id]
		next_dropped_item_id += 1
	return item_id


func _remove_authoritative_dropped_item(item_id: String, emit_event: bool) -> void:
	var pickup = dropped_item_nodes.get(item_id, null)
	if is_instance_valid(pickup):
		(pickup as Node).queue_free()
	dropped_item_nodes.erase(item_id)
	if emit_event:
		reliable_world_event_ready.emit({"type": "dropped_item_removed", "item_id": item_id, "tick": server_tick})


func _clear_dropped_items() -> void:
	for pickup in dropped_item_nodes.values():
		if is_instance_valid(pickup):
			(pickup as Node).queue_free()
	dropped_item_nodes.clear()


func server_farm_action(peer_id: int, action: Dictionary) -> Dictionary:
	var result := {"ok": false, "peer_id": peer_id, "action": action.duplicate(true), "tick": server_tick}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
		return result
	var team := str(player_states[peer_id].get("team", ""))
	if team.is_empty():
		result["reason"] = "missing_team"
		return result
	var tile := _farm_tile_from_action(action)
	var action_type := str(action.get("type", ""))
	match action_type:
		"claim_land":
			if tile != null:
				result["ok"] = tile.claim_land(team)
		"plant":
			if tile != null:
				var seed_name := str(action.get("seed_name", ""))
				if seed_name.is_empty() and not GlobalVar.plant_item_list.is_empty():
					seed_name = str(GlobalVar.plant_item_list[randi_range(0, GlobalVar.plant_item_list.size() - 1)])
				result["ok"] = tile.plant(seed_name, team)
				result["seed_name"] = seed_name
		"harvest":
			if tile != null:
				var source := _vector3_from_value(action.get("absorb_source", tile.global_position))
				result["ok"] = tile.harvest(source, {
					"absorption_type": "player_crop",
					"owner_peer_id": peer_id,
				})
				if bool(result["ok"]):
					award_action_reward(
						peer_id,
						CombatBalance.get_int("team_rewards", "crop_harvest", 5),
						"收割作物"
					)
		"harvest_one":
			if tile != null:
				var crop_index := int(action.get("crop_index", -1))
				var crop_position_value: Variant = action.get("crop_position", null)
				if crop_position_value is Vector3:
					crop_index = tile.get_harvestable_crop_index_at_position(crop_position_value as Vector3)
				var crop := tile.get_harvestable_crop(crop_index)
				var player_state: Dictionary = player_states[peer_id]
				var player_position := _vector3_from_value(player_state.get("position", Vector3.ZERO))
				if crop != null and _can_server_interact_with_position(player_state, crop.global_position, PLAYER_CROP_INTERACTION_RANGE):
					result["ok"] = tile.harvest_one(player_position + Vector3.UP * 0.9, crop_index, {
						"absorption_type": "player_crop",
						"owner_peer_id": peer_id,
					})
					result["crop_index"] = crop_index
					result["crop_position"] = crop.global_position
					if bool(result["ok"]):
						award_action_reward(
							peer_id,
							CombatBalance.get_int("team_rewards", "crop_harvest", 5),
							"收割作物"
						)
				else:
					result["reason"] = "crop_out_of_range"
		"place_tool":
			if tile != null:
				var placement_yaw := _placement_yaw_for_peer(peer_id, action)
				result["ok"] = tile.setting_tool(str(action.get("tool_name", "")), team, null, placement_yaw)
				result["yaw"] = placement_yaw
		_:
			result["reason"] = "unsupported_farm_action"
	if tile != null:
		result["tile_path"] = str(tile.get_path())
		result["tile_position"] = tile.global_position
	result["team"] = team
	reliable_world_event_ready.emit({"type": "farm_action_requested", "data": result, "tick": server_tick})
	return result


func local_remote_control_input(peer_id: int, input_frame: Dictionary) -> void:
	server_remote_control_input(peer_id, input_frame)


func local_remote_control_session(peer_id: int, device_id: String, connected: bool) -> Dictionary:
	return server_remote_control_session(peer_id, device_id, connected)


func _is_remote_controllable_device(device_type: String) -> bool:
	return _is_remote_tool_category(device_type)


func server_remote_control_session(peer_id: int, device_id: String, connected: bool) -> Dictionary:
	var result := {
		"ok": false,
		"peer_id": peer_id,
		"device_id": device_id,
		"connected": connected,
		"tick": server_tick,
	}
	if not player_states.has(peer_id):
		result["reason"] = "unknown_player"
	elif device_id.is_empty() or not remote_device_states.has(device_id):
		result["reason"] = "unknown_device"
	else:
		var state: Dictionary = remote_device_states[device_id]
		if int(state.get("owner_peer_id", 0)) != peer_id:
			result["reason"] = "not_device_owner"
		elif not _is_remote_controllable_device(str(state.get("device_type", ""))):
			result["reason"] = "unsupported_device"
		elif _node_for_tool_ref({"kind": "remote", "id": device_id}) == null:
			result["reason"] = "device_destroyed"
		else:
			state.merge(_remote_link_quality_for(peer_id, state), true)
			var controller_peer_id := int(state.get("controller_peer_id", 0))
			if connected:
				if controller_peer_id != 0 and controller_peer_id != peer_id:
					result["reason"] = "device_in_use"
				elif float(state.get("effective_signal", 0.0)) < REMOTE_RECONNECT_MIN_EFFECTIVE_SIGNAL:
					result["reason"] = "signal_too_weak"
				else:
					state["controller_peer_id"] = peer_id
					result["ok"] = true
			else:
				if controller_peer_id == 0 or controller_peer_id == peer_id:
					state["controller_peer_id"] = 0
					state["input"] = {}
					result["ok"] = true
				else:
					result["reason"] = "not_active_controller"
			remote_device_states[device_id] = state
			result["device_type"] = state.get("device_type", "")
			result["team"] = state.get("team", "")
			result["position"] = state.get("position", Vector3.ZERO)
			result["signal_strength"] = state.get("signal_strength", 0.0)
			result["jam_ratio"] = state.get("jam_ratio", 1.0)
			result["aug_ratio"] = state.get("aug_ratio", 1.0)
			result["effective_signal"] = state.get("effective_signal", 0.0)
	reliable_world_event_ready.emit({"type": "remote_control_session", "data": result, "tick": server_tick})
	return result


func server_remote_control_input(peer_id: int, input_frame: Dictionary) -> void:
	if not player_states.has(peer_id):
		return
	var device_id := str(input_frame.get("device_id", input_frame.get("device_path", "")))
	if device_id.is_empty():
		return
	if not remote_device_states.has(device_id):
		return
	var state: Dictionary = remote_device_states[device_id]
	if int(state.get("owner_peer_id", 0)) != peer_id:
		return
	if int(state.get("controller_peer_id", 0)) != peer_id:
		return
	var device_type := str(state.get("device_type", ""))
	if device_type == "normal_drone" or device_type == "action_drone" or device_type == "tech_drone" or device_type == "small_mouse" or device_type == "boom_buggy":
		var input_seq := int(input_frame.get("input_seq", -1))
		if input_seq <= int(state.get("last_input_seq", 0)):
			return
		var move_value: Variant = input_frame.get("move", Vector2.ZERO)
		var move := move_value as Vector2 if move_value is Vector2 else Vector2.ZERO
		if move.length_squared() > 1.0:
			move = move.normalized()
		state["input"] = {
			"input_seq": input_seq,
			"move": move,
			"vertical": clampf(float(input_frame.get("vertical", 0.0)), -1.0, 1.0),
			"jump_seq": int(input_frame.get("jump_seq", 0)),
			"yaw": float(input_frame.get("yaw", state.get("yaw", 0.0))),
		}
		state["last_input_seq"] = input_seq
	else:
		# Legacy remote devices still use their existing client-side simulation.
		state["position"] = input_frame.get("position", state.get("position", Vector3.ZERO))
		state["velocity"] = input_frame.get("velocity", state.get("velocity", Vector3.ZERO))
		state["yaw"] = float(input_frame.get("yaw", state.get("yaw", 0.0)))
		state["input"] = input_frame.duplicate(true)
	state["last_tick"] = server_tick
	remote_device_states[device_id] = state
	bytes_received_this_second += len(JSON.stringify(input_frame).to_utf8_buffer())


func _simulate_remote_devices(delta: float) -> void:
	# In single-player, the real local device runs its own movement, camera,
	# jumping, and primary-action code. This loop is server-only authority work.
	if mode != MODE_SERVER:
		return
	for raw_device_id in remote_device_states.keys():
		var device_id := str(raw_device_id)
		var state: Dictionary = remote_device_states[device_id]
		var device_type := str(state.get("device_type", ""))
		if device_type != "normal_drone" and device_type != "action_drone" and device_type != "tech_drone" and device_type != "small_mouse" and device_type != "boom_buggy":
			continue
		if int(state.get("controller_peer_id", 0)) == 0:
			continue
		var node = _node_for_tool_ref({"kind": "remote", "id": device_id})
		if node == null or not node.has_method("simulate_authoritative_remote_input"):
			continue
		if node.has_method("set_server_authority_simulation"):
			node.call("set_server_authority_simulation", true)
		node.call("simulate_authoritative_remote_input", state.get("input", {}), delta)
		var body := node as CharacterBody3D
		if body == null:
			continue
		state["position"] = body.global_position
		state["velocity"] = body.velocity
		state["yaw"] = body.rotation.y
		state["hp"] = _node_float_property(body, "current_hp", float(state.get("hp", 0.0)))
		remote_device_states[device_id] = state


func _update_remote_device_link_quality() -> void:
	for raw_device_id in remote_device_states.keys():
		var device_id := str(raw_device_id)
		if not remote_device_states.has(device_id):
			continue
		var state: Dictionary = remote_device_states[device_id]
		if not _is_remote_controllable_device(str(state.get("device_type", ""))):
			continue
		# Local-mode remote devices simulate themselves, while dedicated-server
		# devices have just completed their authority simulation. Read the live
		# transform in both cases before evaluating distance-based signal.
		var device = _node_for_tool_ref({"kind": "remote", "id": device_id}) as Node3D
		if is_instance_valid(device):
			state["position"] = device.global_position
			state["yaw"] = device.rotation.y
		var owner_peer_id := int(state.get("owner_peer_id", 0))
		if not player_states.has(owner_peer_id):
			continue
		state.merge(_remote_link_quality_for(owner_peer_id, state), true)
		if device != null:
			_set_remote_device_jam_ratio(device, float(state.get("jam_ratio", 1.0)))
			_set_remote_device_augment_ratio(device, float(state.get("aug_ratio", 1.0)))
			device.set_meta("network_effective_signal", float(state.get("effective_signal", 0.0)))
			device.set_meta("network_jam_ratio", float(state.get("jam_ratio", 1.0)))
			device.set_meta("network_aug_ratio", float(state.get("aug_ratio", 1.0)))
		var controller_peer_id := int(state.get("controller_peer_id", 0))
		if controller_peer_id != 0 and float(state.get("effective_signal", 0.0)) < REMOTE_CONTROL_LOST_EFFECTIVE_SIGNAL:
			state["controller_peer_id"] = 0
			state["input"] = {}
			_emit_remote_control_session_event(state, controller_peer_id, false, true, "signal_too_weak")
		remote_device_states[device_id] = state


func _remote_link_quality_for(peer_id: int, state: Dictionary) -> Dictionary:
	if str(state.get("device_type", "")) == "action_drone":
		return {
			"signal_strength": 1.0,
			"jam_ratio": 1.0,
			"aug_ratio": 1.0,
			"effective_signal": 1.0,
		}
	var player_state: Dictionary = player_states.get(peer_id, {})
	var player_position := _vector3_from_value(player_state.get("position", Vector3.ZERO))
	var device_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	var signal_range := maxf(0.01, float(state.get("signal_range", 100.0)))
	var signal_strength := clampf(1.0 - device_position.distance_to(player_position) / signal_range, 0.0, 1.0)
	var device_type := str(state.get("device_type", ""))
	# These two devices retain their existing 10% distance-signal floor.
	if device_type == "normal_drone" or device_type == "action_drone" or device_type == "tech_drone" or device_type == "small_mouse":
		signal_strength = maxf(signal_strength, 0.1)
	var jam_ratio := _jam_ratio_for_remote_device(state)
	var aug_ratio := _augment_ratio_for_remote_device(state)
	return {
		"signal_strength": signal_strength,
		"jam_ratio": jam_ratio,
		"aug_ratio": aug_ratio,
		"effective_signal": signal_strength * jam_ratio * aug_ratio,
	}


func _jam_ratio_for_remote_device(remote_state: Dictionary) -> float:
	var device_id := str(remote_state.get("device_id", ""))
	if device_id.is_empty():
		return 1.0
	var ratio := 1.0
	for raw_jammer_id in placed_tool_states.keys():
		var jammer: Dictionary = placed_tool_states[str(raw_jammer_id)]
		if str(jammer.get("tool_name", "")) != "signal_jam":
			continue
		var jammer_node = _node_for_tool_ref({"kind": "placed", "id": str(raw_jammer_id)})
		if jammer_node != null and jammer_node.has_method("get_jam_ratio_for_device"):
			ratio = minf(
				ratio,
				clampf(float(jammer_node.call("get_jam_ratio_for_device", device_id)), 0.01, 1.0)
			)
	return ratio


func _augment_ratio_for_remote_device(remote_state: Dictionary) -> float:
	var device_id := str(remote_state.get("device_id", ""))
	if device_id.is_empty():
		return 1.0
	var ratio := 1.0
	for raw_augment_id in placed_tool_states.keys():
		var augment: Dictionary = placed_tool_states[str(raw_augment_id)]
		if str(augment.get("tool_name", "")) != "signal_augment":
			continue
		var augment_node = _node_for_tool_ref({"kind": "placed", "id": str(raw_augment_id)})
		if augment_node != null and augment_node.has_method("get_augment_ratio_for_device"):
			ratio = maxf(
				ratio,
				clampf(float(augment_node.call("get_augment_ratio_for_device", device_id)), 1.0, 100.0)
			)
	return ratio


func _set_remote_device_jam_ratio(device: Node, ratio: float) -> void:
	if device.has_method("set_jam_ratio"):
		device.call("set_jam_ratio", ratio)
	else:
		device.set("jam_ratio", clampf(ratio, 0.01, 1.0))


func _set_remote_device_augment_ratio(device: Node, ratio: float) -> void:
	if device.has_method("set_aug_ratio"):
		device.call("set_aug_ratio", ratio)
	else:
		device.set("aug_ratio", clampf(ratio, 1.0, 100.0))


func _emit_remote_control_session_event(
	state: Dictionary,
	peer_id: int,
	connected: bool,
	ok: bool,
	reason: String = ""
) -> void:
	var data := {
		"ok": ok,
		"peer_id": peer_id,
		"device_id": state.get("device_id", ""),
		"device_type": state.get("device_type", ""),
		"team": state.get("team", ""),
		"position": state.get("position", Vector3.ZERO),
		"connected": connected,
		"reason": reason,
		"signal_strength": state.get("signal_strength", 0.0),
		"jam_ratio": state.get("jam_ratio", 1.0),
		"aug_ratio": state.get("aug_ratio", 1.0),
		"effective_signal": state.get("effective_signal", 0.0),
		"tick": server_tick,
	}
	reliable_world_event_ready.emit({"type": "remote_control_session", "data": data, "tick": server_tick})


func local_remote_action(peer_id: int, action: Dictionary) -> Dictionary:
	return server_remote_action(peer_id, action)


func server_remote_action(peer_id: int, action: Dictionary) -> Dictionary:
	if not player_states.has(peer_id):
		return {"ok": false, "reason": "unknown_player"}
	var device_id := str(action.get("device_id", action.get("device_path", "")))
	if device_id.is_empty() or not remote_device_states.has(device_id):
		return {"ok": false, "reason": "unknown_device"}
	var device_state: Dictionary = remote_device_states[device_id]
	if int(device_state.get("owner_peer_id", 0)) != peer_id \
		or int(device_state.get("controller_peer_id", 0)) != peer_id:
		return {"ok": false, "reason": "remote_control_not_active"}
	device_state.merge(_remote_link_quality_for(peer_id, device_state), true)
	remote_device_states[device_id] = device_state
	var device_type := str(device_state.get("device_type", ""))
	var action_device := _gameplay_tool_node(_node_for_tool_ref({
		"kind": "remote",
		"id": device_id,
	}))
	if action_device != null and action_device.has_method("is_electronics_disabled") \
		and bool(action_device.call("is_electronics_disabled")):
		return {"ok": false, "reason": "electronics_disabled"}
	var required_signal := REMOTE_CONTROL_LOST_EFFECTIVE_SIGNAL
	if device_type == "normal_drone" or device_type == "action_drone" or device_type == "tech_drone" or device_type == "small_mouse":
		required_signal = REMOTE_PRECISION_ACTION_MIN_EFFECTIVE_SIGNAL
	if float(device_state.get("effective_signal", 0.0)) < required_signal:
		return {"ok": false, "reason": "signal_too_weak"}
	var action_name := str(action.get("action", ""))
	if action_name == "primary" and device_type in ["normal_drone", "tech_drone", "small_mouse"]:
		var device_node := _gameplay_tool_node(_node_for_tool_ref({
			"kind": "remote",
			"id": device_id,
		}))
		var cooldown_property := "bomb_cooldown" if device_type == "normal_drone" else "repair_pulse_cooldown" if device_type == "tech_drone" else "primary_action_cooldown"
		var cooldown_profile := "normal_drone" if device_type == "normal_drone" else "tech_drone" if device_type == "tech_drone" else "small_mouse"
		var cooldown_key := "bomb_cooldown" if device_type == "normal_drone" else "primary_cooldown"
		var cooldown := maxf(0.0, _configured_tool_float(device_node, cooldown_property, CombatBalance.get_float(cooldown_profile, cooldown_key)))
		var now_msec := Time.get_ticks_msec()
		var ready_at_msec := int(device_state.get("primary_action_ready_at_msec", 0))
		if now_msec < ready_at_msec:
			return {
				"ok": false,
				"reason": "cooldown",
				"cooldown_left": float(ready_at_msec - now_msec) / 1000.0,
			}
		device_state["primary_action_ready_at_msec"] = now_msec + int(roundi(cooldown * 1000.0))
		remote_device_states[device_id] = device_state
	var result := {
		"ok": true,
		"peer_id": peer_id,
		"team": player_states[peer_id].get("team", ""),
		"device_id": device_id,
		"device_type": str(device_state.get("device_type", "remote")),
		"action": action_name,
		"position": device_state.get("position", Vector3.ZERO),
		"tick": server_tick,
	}
	reliable_world_event_ready.emit({"type": "remote_action", "data": result, "tick": server_tick})
	_apply_remote_action_gameplay(peer_id, action, result)
	return result


func _tool_id_from_index(state: Dictionary, tool_index: int) -> String:
	var ids: Array = []
	for key in ["primary_weapon_ids", "special_tool_ids"]:
		var source: Variant = state.get(key, [])
		if source is Array:
			ids.append_array(source)
	if tool_index >= 0 and tool_index < ids.size():
		return str(ids[tool_index])
	return ""


func _player_has_tool(state: Dictionary, tool_id: String) -> bool:
	if tool_id.is_empty():
		return false
	for key in ["primary_weapon_ids", "special_tool_ids"]:
		var source: Variant = state.get(key, [])
		if source is Array and (source as Array).has(tool_id):
			return true
	return false


func _tool_allows_multiple(tool_id: String) -> bool:
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return bool(definition.get("allow_multiple", false))


func _server_tool_cooldown(tool_id: String) -> float:
	if tool_id == "rift_book":
		return CombatBalance.get_float("rift_book", "cooldown", 10.0)
	if tool_id == "spicy_blaster":
		return CombatBalance.get_float("spicy_blaster", "cooldown")
	if tool_id == "medicine_pistol" or tool_id == "tranquilizer_pistol":
		return CombatBalance.get_float(tool_id, "cooldown")
	if tool_id == "repair_welder":
		return CombatBalance.get_float("repair_welder", "pulse_interval", 0.1)
	if tool_id == "vehicle_shield_shooter":
		return CombatBalance.get_float("vehicle_shield_shooter", "cooldown", 60.0)
	if authoritative_tool_cooldowns.has(tool_id):
		return float(authoritative_tool_cooldowns[tool_id])
	push_warning("Missing authoritative cooldown for tool: " + tool_id)
	return 1.0


func _uses_finite_ammo(tool_id: String) -> bool:
	return FINITE_AMMO_WEAPON_IDS.has(tool_id)


func _weapon_magazine_size(tool_id: String) -> int:
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return maxi(1, int(definition.get("magazine_size", 1)))


func _weapon_initial_reserve(tool_id: String) -> int:
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return maxi(0, int(definition.get("initial_reserve_ammo", 200)))


func _weapon_reload_time(tool_id: String) -> float:
	var definition: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return maxf(0.05, float(definition.get("reload_time", 1.0)))


func _default_weapon_ammo_state(tool_id: String) -> Dictionary:
	return {
		"ammo_in_mag": _weapon_magazine_size(tool_id),
		"reserve_ammo": _weapon_initial_reserve(tool_id),
		"reload_remaining": 0.0,
		"reload_duration": 0.0,
	}


func _get_or_create_weapon_ammo_state(state: Dictionary, tool_id: String) -> Dictionary:
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	if not ammo_states.has(tool_id):
		ammo_states[tool_id] = _default_weapon_ammo_state(tool_id)
		state["weapon_ammo_states"] = ammo_states
	return ammo_states[tool_id] as Dictionary


func _initialize_weapon_ammo_states(existing_value: Variant, primary_value: Variant, special_value: Variant) -> Dictionary:
	var existing: Dictionary = existing_value.duplicate(true) if existing_value is Dictionary else {}
	var result: Dictionary = {}
	for source_value: Variant in [primary_value, special_value]:
		if not source_value is Array:
			continue
		for id_value: Variant in source_value as Array:
			var tool_id := str(id_value)
			if _uses_finite_ammo(tool_id):
				result[tool_id] = (existing.get(tool_id, _default_weapon_ammo_state(tool_id)) as Dictionary).duplicate(true)
	return result


func _tick_weapon_reloads(peer_id: int, state: Dictionary, delta: float) -> void:
	var ammo_states: Dictionary = state.get("weapon_ammo_states", {})
	for tool_id_value: Variant in ammo_states.keys():
		var tool_id := str(tool_id_value)
		var ammo_state: Dictionary = ammo_states[tool_id]
		var remaining := float(ammo_state.get("reload_remaining", 0.0))
		if remaining <= 0.0:
			continue
		remaining = maxf(0.0, remaining - delta)
		ammo_state["reload_remaining"] = remaining
		if remaining <= 0.0:
			var needed := maxi(0, _weapon_magazine_size(tool_id) - int(ammo_state.get("ammo_in_mag", 0)))
			var transferred := mini(needed, int(ammo_state.get("reserve_ammo", 0)))
			ammo_state["ammo_in_mag"] = int(ammo_state.get("ammo_in_mag", 0)) + transferred
			ammo_state["reserve_ammo"] = int(ammo_state.get("reserve_ammo", 0)) - transferred
			ammo_state["reload_duration"] = 0.0
			_emit_weapon_ammo_state(peer_id, tool_id, ammo_state)
		ammo_states[tool_id] = ammo_state
	state["weapon_ammo_states"] = ammo_states


func _emit_weapon_ammo_state(peer_id: int, tool_id: String, ammo_state: Dictionary) -> void:
	reliable_world_event_ready.emit({
		"type": "weapon_ammo_state",
		"peer_id": peer_id,
		"tool_id": tool_id,
		"ammo_state": ammo_state.duplicate(true),
		"tick": server_tick,
	})


func _server_hitscan(
	peer_id: int,
	tool_request: Dictionary,
	max_distance: float,
	damage: float,
	knockback: float,
	effect: String,
	show_owner_hit_marker := true
) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var end := origin + direction * max_distance
	# The requested origin is normally the camera or muzzle, both of which can
	# overlap the caster's authority capsule. Ignore that capsule so a hitscan
	# starts in front of its owner, as the client-side LookAtTarget does.
	var hit := _raycast_world(origin, end, DEFAULT_COMBAT_RAYCAST_MASK, _player_raycast_exclusion(peer_id))
	var trace_end := _vector3_from_value(hit.get("position", end)) if hit.has("collider") else end
	var hit_position := trace_end
	var hit_kind := "world" if hit.has("collider") else "none"
	# A direct server-physics hit is the exact player capsule intersection. The
	# segment test remains as a latency-tolerant fallback, limited by the first
	# world/body collision so it cannot shoot through cover.
	var hit_peer_id := _valid_hitscan_player_target(
		_peer_id_for_player_physics_collider(hit.get("collider", null)), peer_id, team
	)
	if hit_peer_id == 0:
		hit_peer_id = _find_player_hit_by_segment(peer_id, team, origin, trace_end, 0.75)
	var damage_position := hit_position
	if hit_peer_id != 0 and player_states.has(hit_peer_id):
		damage_position = _vector3_from_value(
			(player_states[hit_peer_id] as Dictionary).get("position", hit_position)
		)
	var applied_damage := damage * AreaProtectorTool.get_damage_multiplier_at(
		self, damage_position, team
	)
	if hit_peer_id != 0:
		# Preserve the actual body collision point for lightning and all other
		# server-confirmed hits instead of placing effects at the player's feet.
		hit_position = trace_end
		hit_kind = "player"
		if _damage_player(hit_peer_id, applied_damage, knockback, direction, team, effect, peer_id) and show_owner_hit_marker:
			_emit_hit_confirmed(peer_id, 1, applied_damage, effect)
	elif hit.has("collider"):
		var collider = hit.get("collider")
		var hit_wild_animal := _wild_animal_for_collider(collider)
		hit_position = hit.get("position", end)
		applied_damage = damage * AreaProtectorTool.get_damage_multiplier_at(
			self, hit_position, team
		)
		hit_kind = "world"
		if _apply_hit_to_collider(collider, effect, applied_damage, team, int(hit.get("shape", -1)), peer_id):
			_apply_wild_animal_knockback(collider, direction, knockback)
			hit_kind = "wild_animal" if hit_wild_animal != null else "tool"
			if show_owner_hit_marker:
				_emit_hit_confirmed(peer_id, 1, applied_damage, effect)
	return {
		"hit_kind": hit_kind,
		"hit_peer_id": hit_peer_id,
		"hit_position": hit_position,
		"effect": effect,
		"damage": applied_damage if hit_kind in ["player", "tool", "wild_animal"] else 0.0,
		"knockback": knockback,
	}


func _server_shotgun(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var center_direction := _vector3_from_value(
		tool_request.get("direction", Vector3.FORWARD)
	).normalized()
	if center_direction.length_squared() <= 0.001:
		center_direction = Vector3.FORWARD
	var bullet_count := maxi(
		1,
		CombatBalance.get_int("shotgun", "bullet_count", 2)
	)
	var spread_degrees := CombatBalance.get_float(
		"shotgun", "spread_degrees", 3.0
	)
	var screen_right := center_direction.cross(Vector3.UP).normalized()
	var spread_axis := screen_right.cross(center_direction).normalized()
	if spread_axis.length_squared() <= 0.001:
		spread_axis = Vector3.UP
	var pellet_results: Array[Dictionary] = []
	var confirmed_hits := 0
	var total_damage := 0.0
	var summary_hit_kind := "none"
	var summary_hit_position := _vector3_from_value(
		tool_request.get("origin", Vector3.ZERO)
	)

	for index in range(bullet_count):
		var angle_degrees := 0.0
		if bullet_count > 1:
			angle_degrees = lerpf(
				-spread_degrees * 0.5,
				spread_degrees * 0.5,
				float(index) / float(bullet_count - 1)
			)
		var pellet_direction := center_direction.rotated(
			spread_axis,
			deg_to_rad(angle_degrees)
		).normalized()
		var pellet_request := tool_request.duplicate(true)
		pellet_request["direction"] = pellet_direction
		var pellet := _server_hitscan(
			peer_id,
			pellet_request,
			CombatBalance.get_float("shotgun", "range"),
			CombatBalance.get_float("shotgun", "damage"),
			CombatBalance.get_float("shotgun", "knockback"),
			"nail",
			false
		)
		pellet["direction"] = pellet_direction
		pellet_results.append(pellet)
		var pellet_damage := float(pellet.get("damage", 0.0))
		if pellet_damage > 0.0:
			confirmed_hits += 1
			total_damage += pellet_damage
		if summary_hit_kind == "none" \
				and str(pellet.get("hit_kind", "none")) != "none":
			summary_hit_kind = str(pellet.get("hit_kind", "none"))
			summary_hit_position = _vector3_from_value(
				pellet.get("hit_position", summary_hit_position)
			)

	if confirmed_hits > 0:
		_emit_hit_confirmed(peer_id, confirmed_hits, total_damage, "nail")
	return {
		"hit_kind": summary_hit_kind,
		"hit_position": summary_hit_position,
		"effect": "nail",
		"damage": total_damage,
		"knockback": CombatBalance.get_float("shotgun", "knockback"),
		"pellet_results": pellet_results,
	}


func _server_healing_hitscan(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var end := origin + direction * CombatBalance.get_float("medicine_pistol", "range")
	var hit := _raycast_world(origin, end, DEFAULT_COMBAT_RAYCAST_MASK, _player_raycast_exclusion(peer_id))
	var trace_end := _vector3_from_value(hit.get("position", end)) if hit.has("collider") else end
	var hit_peer_id := _valid_hitscan_player_target(
		_peer_id_for_player_physics_collider(hit.get("collider", null)), peer_id, "", true
	)
	if hit_peer_id == 0:
		hit_peer_id = _find_player_hit_by_segment(peer_id, "", origin, trace_end, 0.75, true)
	var hit_position := trace_end
	var hit_kind := "world" if hit.has("collider") else "none"
	if hit_peer_id != 0:
		hit_kind = "player"
		_heal_player(hit_peer_id, CombatBalance.get_float("medicine_pistol", "heal_amount"), peer_id)
	return {
		"hit_kind": hit_kind,
		"hit_peer_id": hit_peer_id,
		"hit_position": hit_position,
		"effect": MedicineBullet.EFFECT_HEALING,
		"healing": CombatBalance.get_float("medicine_pistol", "heal_amount") if hit_peer_id != 0 else 0.0,
	}


func _server_repair_welder(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	var fallback_origin := player_position + Vector3.UP * 1.2
	var origin := _vector3_from_value(tool_request.get("origin", fallback_origin))
	# Permit the real hand muzzle while rejecting a forged remote origin.
	if origin.distance_to(fallback_origin) > 2.5:
		origin = fallback_origin
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = -Basis(Vector3.UP, float(state.get("yaw", 0.0))).z
	var end := origin + direction * CombatBalance.get_float("repair_welder", "range", 4.0)
	var hit := _raycast_world(
		origin, end, DEFAULT_COMBAT_RAYCAST_MASK, _player_raycast_exclusion(peer_id)
	)
	var hit_position := _vector3_from_value(hit.get("position", end))
	var vehicle := _vehicle_for_collider(hit.get("collider", null))
	var repaired := 0.0
	var vehicle_id := ""
	if vehicle != null and is_instance_valid(vehicle):
		vehicle_id = vehicle.get_vehicle_id()
		repaired = vehicle.repair(CombatBalance.get_float("repair_welder", "repair_amount", 10.0))
		if repaired > 0.0:
			var vehicle_state: Dictionary = vehicle_states.get(vehicle_id, {})
			vehicle_state.merge(vehicle.get_network_state(), true)
			vehicle_state["vehicle_id"] = vehicle_id
			vehicle_states[vehicle_id] = vehicle_state
	return {
		"hit_kind": "vehicle" if vehicle != null else ("world" if hit.has("collider") else "none"),
		"hit_position": hit_position,
		"vehicle_id": vehicle_id,
		"repaired_hp": repaired,
		"effect": "repair_welder",
	}


func _server_tranquilizer_hitscan(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var damage := CombatBalance.get_float("tranquilizer_pistol", "damage")
	var end := origin + direction * CombatBalance.get_float("tranquilizer_pistol", "range")
	var hit := _raycast_world(origin, end, DEFAULT_COMBAT_RAYCAST_MASK, _player_raycast_exclusion(peer_id))
	var trace_end := _vector3_from_value(hit.get("position", end)) if hit.has("collider") else end
	var hit_peer_id := _valid_hitscan_player_target(
		_peer_id_for_player_physics_collider(hit.get("collider", null)), peer_id, team
	)
	if hit_peer_id == 0:
		hit_peer_id = _find_player_hit_by_segment(peer_id, team, origin, trace_end, 0.75)
	var hit_kind := "world" if hit.has("collider") else "none"
	var applied_damage := damage
	if hit_peer_id != 0:
		hit_kind = "player"
		var target_position := _vector3_from_value(
			(player_states[hit_peer_id] as Dictionary).get("position", trace_end)
		)
		applied_damage *= AreaProtectorTool.get_damage_multiplier_at(
			self, target_position, team
		)
		if _damage_player(hit_peer_id, applied_damage, 0.0, direction, team, TranquilizerBullet.EFFECT_TRANQUILIZER, peer_id):
			_emit_hit_confirmed(peer_id, 1, applied_damage, TranquilizerBullet.EFFECT_TRANQUILIZER)
	elif hit.has("collider"):
		var collider: Variant = hit.get("collider")
		var wild_animal := _wild_animal_for_collider(collider)
		if wild_animal != null and _apply_hit_to_collider(
			collider,
			TranquilizerBullet.EFFECT_TRANQUILIZER,
			applied_damage,
			team,
			int(hit.get("shape", -1)),
			peer_id
		):
			hit_kind = "wild_animal"
			_emit_hit_confirmed(peer_id, 1, applied_damage, TranquilizerBullet.EFFECT_TRANQUILIZER)
	return {
		"hit_kind": hit_kind,
		"hit_peer_id": hit_peer_id,
		"hit_position": trace_end,
		"effect": TranquilizerBullet.EFFECT_TRANQUILIZER,
		"damage": applied_damage if hit_kind in ["player", "wild_animal"] else 0.0,
		"knockback": 0.0,
	}


func _server_wand(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var data := _server_hitscan(peer_id, tool_request, CombatBalance.get_float("wand", "range"), CombatBalance.get_float("wand", "damage"), 0.0, "lightening")
	data["lightning"] = true
	return data


func _server_plant_selected_crop(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var seed_id := str(tool_request.get("seed_id", ""))
	if seed_id.is_empty():
		var plantable_ids := IngredientCatalog.get_plantable_ids()
		seed_id = "potato" if plantable_ids.has("potato") else (plantable_ids[0] if not plantable_ids.is_empty() else "")
	if not IngredientCatalog.is_plantable(seed_id):
		return {"ok": false, "reason": "invalid_seed_id"}
	var collider: Variant = _raycast_requested_collider(state, tool_request)
	if collider is FarmTile:
		var ok := (collider as FarmTile).plant(seed_id, team)
		return {
			"ok": ok,
			"farm_action": "plant",
			"seed_id": seed_id,
			"tile_path": str((collider as Node).get_path()),
			"tile_position": (collider as FarmTile).global_position,
		}
	return {"ok": false, "reason": "no_farm_tile"}


func _server_fertilize(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var tile := _raycast_requested_collider(state, tool_request) as FarmTile
	if tile == null:
		return {"ok": false, "reason": "no_farm_tile"}
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	if origin.distance_to(tile.global_position) > CombatBalance.get_float("fertilizer", "range"):
		return {"ok": false, "reason": "out_of_range"}
	var multiplier := CombatBalance.get_float("fertilizer", "growth_multiplier")
	var ok := tile.apply_fertilizer(str(state.get("team", "")), multiplier)
	return {
		"ok": ok,
		"reason": "invalid_fertilizer_target" if not ok else "",
		"farm_action": "fertilize",
		"tile_path": str(tile.get_path()),
		"tile_position": tile.global_position,
		"fertilizer_multiplier": multiplier if ok else 1.0,
		"fertilizer_blocked": tile.fertilizer_blocked,
	}


func _server_eater(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var harvested := 0
	var absorbed := 0
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null:
		var plots: Array = manager.call("get_plots_in_radius", origin, CombatBalance.get_float("eater", "range"))
		for plot in plots:
			if harvested >= CombatBalance.get_int("eater", "mature_plot_limit"):
				break
			if plot is FarmTile and plot.land_owner == team and plot.can_harvest:
				if plot.harvest(origin, {
					"absorption_type": "eater_crop",
					"owner_peer_id": peer_id,
				}):
					harvested += 1
					award_action_reward(
						peer_id,
						CombatBalance.get_int("team_rewards", "crop_harvest", 5),
						"收割作物"
					)
	for projectile_id in projectile_states.keys():
		if absorbed >= CombatBalance.get_int("eater", "projectile_limit"):
			break
		var projectile: Dictionary = projectile_states[projectile_id]
		if str(projectile.get("team", "")) == team:
			continue
		var pos := _vector3_from_value(projectile.get("position", Vector3.ZERO))
		if pos.distance_to(origin) <= CombatBalance.get_float("eater", "range"):
			_emit_projectile_absorption_visual(projectile, origin, peer_id)
			projectile_states.erase(projectile_id)
			absorbed += 1
	return {"ok": true, "farm_action": "eater", "harvested": harvested, "absorbed_projectiles": absorbed}


func emit_crop_absorption_visual(seed_name: String, start_position: Vector3, end_position: Vector3, context: Dictionary = {}) -> void:
	if mode != MODE_SERVER:
		return
	var visual_scene := FarmTile.get_harvest_drop_scene_path(seed_name)
	_emit_absorption_visual({
		"absorption_type": str(context.get("absorption_type", "crop")),
		"owner_peer_id": int(context.get("owner_peer_id", 0)),
		"seed_name": seed_name,
		"visual_scene": visual_scene,
		"crop_positions": context.get("crop_positions", []),
		"start_position": start_position,
		"end_position": end_position,
		"duration": float(context.get("duration", 0.42)),
	})


func get_placed_tool_owner_peer_id(tool_node: Node) -> int:
	if mode == MODE_LOCAL:
		return LOCAL_PLAYER_ID
	if tool_node == null:
		return 0
	var device_id := str(tool_node.get_meta("network_device_id", ""))
	if not device_id.is_empty():
		var direct_state: Dictionary = placed_tool_states.get(device_id, remote_device_states.get(device_id, {}))
		var direct_owner_peer_id := int(direct_state.get("owner_peer_id", 0))
		if direct_owner_peer_id > 0:
			return direct_owner_peer_id
	var tile: Node = tool_node
	while tile != null and not tile is FarmTile:
		tile = tile.get_parent()
	if tile == null:
		return 0
	var state: Dictionary = placed_tool_states.get(str(tile.get_path()), {})
	return int(state.get("owner_peer_id", 0))


func _emit_projectile_absorption_visual(projectile: Dictionary, end_position: Vector3, owner_peer_id: int) -> void:
	_emit_absorption_visual({
		"absorption_type": "eater_projectile",
		"owner_peer_id": owner_peer_id,
		"projectile_id": int(projectile.get("projectile_id", 0)),
		"visual_type": str(projectile.get("type", "")),
		"effect": str(projectile.get("effect", "")),
		"start_position": _vector3_from_value(projectile.get("position", Vector3.ZERO)),
		"end_position": end_position,
		"duration": 0.28,
	})


func _emit_absorption_visual(data: Dictionary) -> void:
	var event := data.duplicate(true)
	event["type"] = "absorption_visual"
	event["absorption_id"] = next_absorption_visual_id
	event["tick"] = server_tick
	next_absorption_visual_id += 1
	reliable_world_event_ready.emit(event)


func _server_place_tool(peer_id: int, tool_request: Dictionary, tool_scene_name: String) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var placement_yaw := _placement_yaw_for_peer(peer_id, tool_request)
	var collider: Variant = _raycast_requested_collider(state, tool_request)
	if collider is FarmTile:
		var ok := (collider as FarmTile).setting_tool(tool_scene_name, team, null, placement_yaw)
		var tile_path := str((collider as Node).get_path())
		var tile_position := (collider as FarmTile).global_position
		if ok:
			_register_placed_tool(peer_id, tool_scene_name, team, tile_path, tile_position, placement_yaw)
		return {"ok": ok, "placed": tool_scene_name, "tile_path": tile_path, "tile_position": tile_position, "yaw": placement_yaw}
	return {"ok": false, "reason": "no_farm_tile", "placed": tool_scene_name}


func _server_place_free_scene(peer_id: int, tool_request: Dictionary, scene_path: String, device_type: String) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var team := str(state.get("team", ""))
	var placement_yaw := _placement_yaw_for_peer(peer_id, tool_request)
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	if is_local_authority():
		# Local mode has the real player transform in the input request. The initial
		# authority state is created before FarmInit assigns the team spawn position.
		player_position = _vector3_from_value(tool_request.get("player_position", player_position))
	var origin := _vector3_from_value(tool_request.get("origin", player_position))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var hit := _raycast_world(origin, origin + direction * 12.0)
	var target_position := _vector3_from_value(tool_request.get("target_position", Vector3.ZERO))
	var position := target_position if target_position != Vector3.ZERO else _vector3_from_value(hit.get("position", player_position + direction * 4.0))
	if position.distance_to(player_position) > 10.0:
		position = player_position + direction * 4.0
	if _is_free_placement_tool(device_type):
		var placement := _validate_free_placement(peer_id, scene_path, position, placement_yaw)
		if not bool(placement.get("ok", false)):
			return {
				"ok": false,
				"reason": str(placement.get("reason", "invalid_placement")),
				"device_type": device_type,
			}
		position = _vector3_from_value(placement.get("position", position))
	else:
		position = _project_position_to_ground(position + Vector3.UP * 2.0, position)
	var packed := load(scene_path) as PackedScene
	if packed == null or GlobalVar.gameworld == null:
		_free_placement_debug("creation rejected reason=missing_scene_or_world scene=%s world=%s" % [scene_path, GlobalVar.gameworld])
		return {"ok": false, "reason": "missing_scene_or_world", "device_type": device_type}
	var node := packed.instantiate() as Node3D
	if node == null:
		_free_placement_debug("creation rejected reason=bad_scene scene=%s" % scene_path)
		return {"ok": false, "reason": "bad_scene", "device_type": device_type}
	GlobalVar.gameworld.add_child(node)
	node.global_position = position
	node.rotation.y = placement_yaw
	node.set("tool_owner", team)
	if node is KitchenAppliance:
		(node as KitchenAppliance).owner_team = team
	if node.has_method("activate_tool"):
		node.call("activate_tool")
	if is_server_authority() and node.has_method("set_server_authority_simulation"):
		node.call("set_server_authority_simulation", true)
	var device_id := str(node.get_path())
	node.set_meta("network_device_id", device_id)
	var device_max_hp := _configured_tool_hp(device_type, node)
	var is_remote_device := _is_remote_tool_category(device_type)
	if is_remote_device:
		remote_device_states[device_id] = {
			"device_id": device_id,
			"device_path": device_id,
			"device_type": device_type,
			"owner_peer_id": peer_id,
			"team": team,
			"position": position,
			"velocity": Vector3.ZERO,
			"yaw": placement_yaw,
			"hp": device_max_hp,
			"max_hp": device_max_hp,
			"last_input_seq": 0,
			"last_tick": server_tick,
			"controller_peer_id": peer_id if _is_remote_controllable_device(device_type) else 0,
			"signal_range": float(node.get("use_distance")) if _is_remote_controllable_device(device_type) else 0.0,
		}
		if device_type == "normal_drone":
			var startup_bomb_lock := maxf(
				0.0,
				_configured_tool_float(
					node,
					"startup_bomb_lock",
					CombatBalance.get_float("normal_drone", "startup_bomb_lock", 3.0)
				)
			)
			remote_device_states[device_id]["primary_action_ready_at_msec"] = \
				Time.get_ticks_msec() + int(roundi(startup_bomb_lock * 1000.0))
	else:
		_register_placed_tool(peer_id, device_type, team, device_id, position, placement_yaw)
		var placed_state: Dictionary = placed_tool_states.get(device_id, {})
		placed_state["device_id"] = device_id
		placed_state["scene_path"] = scene_path
		placed_state["free_placement"] = true
		placed_tool_states[device_id] = placed_state
	var result := {
		"ok": true,
		"placed": device_type,
		"device_id": device_id,
		"position": position,
		"yaw": placement_yaw,
		"category": str(authoritative_tool_definitions.get(device_type, {}).get("category", "utility")),
		"scene_path": scene_path,
	}
	if mode == MODE_LOCAL and is_remote_device:
		# 单人本地权威需要把实例返回给 Player，便于立刻进入无人机/小车等遥控视角。
		# Dedicated Server 模式不能把 Node 放进 RPC 事件，否则网络序列化会失败。
		result["remote_node"] = node
	_free_placement_debug(
		"created type=%s path=%s position=%s active=%s"
		% [device_type, node.get_path(), node.global_position, is_instance_valid(node)]
	)
	return result


func _server_place_vehicle_scene(peer_id: int, tool_request: Dictionary, tool_id: String, scene_path: String) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var placement_yaw := _placement_yaw_for_peer(peer_id, tool_request)
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	if is_local_authority():
		player_position = _vector3_from_value(tool_request.get("player_position", player_position))
	var origin := _vector3_from_value(tool_request.get("origin", player_position))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var hit := _raycast_world(origin, origin + direction * 12.0)
	var requested_position := _vector3_from_value(tool_request.get("target_position", Vector3.ZERO))
	var position := requested_position if requested_position != Vector3.ZERO else _vector3_from_value(hit.get("position", player_position + direction * 4.0))
	if position.distance_to(player_position) > 10.0:
		position = player_position + direction * 4.0
	var placement := _validate_free_placement(peer_id, scene_path, position, placement_yaw)
	if not bool(placement.get("ok", false)):
		return {"ok": false, "reason": str(placement.get("reason", "invalid_placement")), "placed": tool_id}
	var packed := load(scene_path) as PackedScene
	var vehicle := packed.instantiate() as VehicleBase if packed != null else null
	if vehicle == null or GlobalVar.gameworld == null:
		return {"ok": false, "reason": "missing_vehicle_scene", "placed": tool_id}
	var vehicle_id := "%s_%d" % [tool_id, next_dynamic_vehicle_id]
	next_dynamic_vehicle_id += 1
	vehicle.name = "%s_%d" % [tool_id.capitalize(), next_dynamic_vehicle_id]
	vehicle.network_id = vehicle_id
	vehicle.owner_team = str(state.get("team", ""))
	if vehicle.has_method("set_kitchen_team"):
		vehicle.call("set_kitchen_team", str(state.get("team", "")))
	GlobalVar.gameworld.add_child(vehicle)
	vehicle.global_position = _vector3_from_value(placement.get("position", position))
	vehicle.rotation.y = placement_yaw
	var vehicle_state := vehicle.get_network_state()
	vehicle_state["vehicle_id"] = vehicle_id
	vehicle_state["scene_path"] = scene_path
	vehicle_state["owner_team"] = str(state.get("team", ""))
	vehicle_states[vehicle_id] = vehicle_state
	reliable_world_event_ready.emit({
		"type": "vehicle_placed",
		"vehicle_id": vehicle_id,
		"scene_path": scene_path,
		"owner_team": str(state.get("team", "")),
		"position": vehicle.global_position,
		"yaw": vehicle.rotation.y,
		"tick": server_tick,
	})
	return {"ok": true, "placed": tool_id, "vehicle_id": vehicle_id, "position": vehicle.global_position, "yaw": placement_yaw}


func _is_free_placement_tool(tool_id: String) -> bool:
	var tool: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return bool(tool.get("free_placement", false))


func _is_remote_tool_category(tool_id: String) -> bool:
	var tool: Dictionary = authoritative_tool_definitions.get(tool_id, {})
	return str(tool.get("category", "utility")) == "remote"


func get_authority_player_peer_id(body: Node) -> int:
	if body is GamePlayer:
		return int((body as GamePlayer).authority_peer_id)
	return _peer_id_for_player_physics_collider(body)


func register_map_placed_tool(
	node: Node3D,
	tool_name: String,
	tool_id: String,
	team: String
) -> bool:
	if node == null or not is_instance_valid(node) or tool_id.is_empty() \
			or (not is_server_authority() and not is_local_authority()):
		return false
	var tool_max_hp := _configured_tool_hp(tool_name, node)
	var definition: Dictionary = authoritative_tool_definitions.get(tool_name, {})
	node.set_meta("network_device_id", tool_id)
	placed_tool_states[tool_id] = {
		"tool_id": tool_id,
		"device_id": tool_id,
		"tool_name": tool_name,
		"owner_peer_id": 0,
		"team": team,
		"path": str(node.get_path()),
		"position": node.global_position,
		"yaw": node.rotation.y,
		"hp": tool_max_hp,
		"max_hp": tool_max_hp,
		"cooldown_left": 0.0,
		"scene_path": str(definition.get("path", "")),
		"free_placement": true,
	}
	return true


func register_map_cargo_crate(crate: CargoCrateGround) -> bool:
	if crate == null or not is_instance_valid(crate) \
			or (not is_server_authority() and not is_local_authority()):
		return false
	var crate_id := str(crate.get_meta("network_device_id", crate.get_path()))
	crate.set_meta("network_device_id", crate_id)
	var existing: Dictionary = placed_tool_states.get(crate_id, {})
	existing.merge({
		"tool_id": crate_id, "device_id": crate_id, "tool_name": "cargo_crate",
		"owner_peer_id": int(existing.get("owner_peer_id", 0)), "team": "",
		"path": str(crate.get_path()), "position": crate.global_position, "yaw": crate.rotation.y,
		"hp": float(existing.get("hp", crate.current_hp)), "max_hp": 500.0,
		"cooldown_left": 0.0, "scene_path": str(crate.get_crate_data().get("model_path", "")),
		"free_placement": true, "crate_data": crate.get_crate_data(),
	}, true)
	placed_tool_states[crate_id] = existing
	return true


func trigger_trap(trap: TrapTool, body: Node3D, damage: float, source_team: String) -> bool:
	if trap == null or not is_instance_valid(trap) or damage <= 0.0 \
			or (not is_server_authority() and not is_local_authority()):
		return false
	var damaged := false
	var target_kind := ""
	var peer_id := get_authority_player_peer_id(body)
	if peer_id > 0:
		var trap_owner_peer_id := get_placed_tool_owner_peer_id(trap)
		damaged = _damage_player(
			peer_id, damage, 0.0, Vector3.ZERO, source_team, "trap", trap_owner_peer_id
		)
		target_kind = "player"
		if damaged and is_local_authority():
			_apply_local_trap_player_damage(peer_id)
	elif body is VehicleBase:
		damaged = (body as VehicleBase).impact("trap", damage, "")
		target_kind = "vehicle"
	elif body is BlackBear:
		var trap_owner_peer_id := get_placed_tool_owner_peer_id(trap)
		damaged = (body as BlackBear).impact_from_peer(
			"trap", damage, source_team, trap_owner_peer_id
		)
		target_kind = "wild_animal"
	elif body is FarmLivestock:
		var livestock := body as FarmLivestock
		if livestock.housed_in_chop \
				or (not livestock.owner_team.is_empty() and livestock.owner_team == source_team):
			return false
		var trap_owner_peer_id := get_placed_tool_owner_peer_id(trap)
		damaged = livestock.impact_from_peer(
			"trap", damage, source_team, trap_owner_peer_id
		)
		target_kind = "livestock"
	if not damaged:
		return false
	var device_id := str(trap.get_meta("network_device_id", str(trap.get_path())))
	reliable_world_event_ready.emit({
		"type": "trap_triggered",
		"device_id": device_id,
		"position": trap.global_position,
		"target_kind": target_kind,
		"tick": server_tick,
	})
	return true


func capture_player_with_big_mouth(
	big_mouth: BigMouthTool,
	peer_id: int,
	anchor_position: Vector3,
	duration: float
) -> bool:
	if big_mouth == null or not is_instance_valid(big_mouth) or peer_id <= 0 \
			or duration <= 0.0 or not player_states.has(peer_id) \
			or (not is_server_authority() and not is_local_authority()):
		return false
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0 \
			or float(state.get("big_mouth_capture_remaining", 0.0)) > 0.0 \
			or not str(state.get("vehicle_id", "")).is_empty() \
			or (not big_mouth.tool_owner.is_empty() \
				and str(state.get("team", "")) == big_mouth.tool_owner):
		return false
	state["big_mouth_capture_remaining"] = duration
	state["big_mouth_pull_remaining"] = big_mouth.tongue_retract_seconds
	state["big_mouth_anchor"] = anchor_position
	state["big_mouth_device_id"] = str(big_mouth.get_meta("network_device_id", str(big_mouth.get_path())))
	state["velocity"] = Vector3.ZERO
	state["knockback_velocity"] = Vector3.ZERO
	player_states[peer_id] = state
	latest_inputs.erase(peer_id)
	var device_id := str(big_mouth.get_meta("network_device_id", str(big_mouth.get_path())))
	var event := {
		"type": "big_mouth_triggered",
		"device_id": device_id,
		"position": big_mouth.global_position,
		"victim_peer_id": peer_id,
		"anchor_position": anchor_position,
		"capture_seconds": duration,
		"pull_seconds": big_mouth.tongue_retract_seconds,
		"tick": server_tick,
	}
	if is_local_authority():
		_apply_local_big_mouth_capture(peer_id, anchor_position, duration, big_mouth.tongue_retract_seconds)
	reliable_world_event_ready.emit(event)
	return true


func release_big_mouth_capture(peer_id: int, reason := "released") -> bool:
	if not player_states.has(peer_id):
		return false
	var state: Dictionary = player_states[peer_id]
	if float(state.get("big_mouth_capture_remaining", 0.0)) <= 0.0 \
			and str(state.get("big_mouth_device_id", "")).is_empty():
		return false
	var device_id := str(state.get("big_mouth_device_id", ""))
	state["big_mouth_capture_remaining"] = 0.0
	state["big_mouth_pull_remaining"] = 0.0
	state["big_mouth_device_id"] = ""
	state["velocity"] = Vector3.ZERO
	player_states[peer_id] = state
	_notify_big_mouth_capture_released(device_id, reason == "timeout")
	if is_local_authority():
		_apply_local_big_mouth_release(peer_id)
	reliable_world_event_ready.emit({
		"type": "big_mouth_released",
		"device_id": device_id,
		"victim_peer_id": peer_id,
		"reason": reason,
		"tick": server_tick,
	})
	return true


func _notify_big_mouth_capture_released(device_id: String, preserve_cooldown := false) -> void:
	if device_id.is_empty():
		return
	var tool_ref := _registered_tool_ref_by_id(device_id)
	var big_mouth := _node_for_tool_ref(tool_ref) as BigMouthTool
	if is_instance_valid(big_mouth):
		if preserve_cooldown:
			big_mouth.finish_capture_hold()
		else:
			big_mouth.release_capture_early()


func release_big_mouth_captures_for_device(device_id: String, reason := "destroyed") -> void:
	if device_id.is_empty():
		return
	for peer_id_value in player_states.keys():
		var peer_id := int(peer_id_value)
		var state: Dictionary = player_states[peer_id]
		if str(state.get("big_mouth_device_id", "")) == device_id:
			release_big_mouth_capture(peer_id, reason)


func _apply_local_big_mouth_release(peer_id: int) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).release_big_mouth_capture()
			return


func _apply_local_big_mouth_capture(
	peer_id: int,
	anchor_position: Vector3,
	duration: float,
	pull_seconds: float
) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_big_mouth_capture(anchor_position, duration, pull_seconds)
			return


func expire_trap(trap: TrapTool) -> void:
	if trap == null or not is_instance_valid(trap):
		return
	var device_id := str(trap.get_meta("network_device_id", str(trap.get_path())))
	remote_device_states.erase(device_id)
	placed_tool_states.erase(device_id)
	reliable_world_event_ready.emit({
		"type": "trap_expired",
		"device_id": device_id,
		"position": trap.global_position,
		"tick": server_tick,
	})


func _apply_local_trap_player_damage(peer_id: int) -> void:
	var state: Dictionary = player_states.get(peer_id, {})
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).server_hp = float(state.get("hp", 0.0))
			(node as GamePlayer)._update_health_ui()
			return


func _placement_yaw_for_peer(peer_id: int, tool_request: Dictionary) -> float:
	var state: Dictionary = player_states.get(peer_id, {})
	var yaw := float(state.get("yaw", 0.0))
	if is_local_authority():
		yaw = float(tool_request.get("yaw", yaw))
	return wrapf(yaw, -PI, PI)


func _validate_free_placement(peer_id: int, scene_path: String, requested_position: Vector3, placement_yaw: float) -> Dictionary:
	_free_placement_debug("request peer=%d scene=%s requested=%s" % [peer_id, scene_path, requested_position])
	var player_state: Dictionary = player_states.get(peer_id, {})
	var player_position := _vector3_from_value(player_state.get("position", requested_position))
	var ray_center_y := maxf(requested_position.y, player_position.y)
	var ray_start := Vector3(requested_position.x, ray_center_y + FREE_PLACEMENT_GROUND_RAY_ABOVE, requested_position.z)
	var ray_end := Vector3(requested_position.x, ray_center_y - FREE_PLACEMENT_GROUND_RAY_BELOW, requested_position.z)
	var ground_hit := _raycast_world(
		ray_start,
		ray_end,
		COLLISION_LAYER_GROUND
	)
	if not ground_hit.has("position"):
		_free_placement_debug(
			"rejected reason=placement_no_ground mask=%d ray_start=%s ray_end=%s"
			% [COLLISION_LAYER_GROUND, ray_start, ray_end]
		)
		return {"ok": false, "reason": "placement_no_ground"}
	var ground_normal := _vector3_from_value(ground_hit.get("normal", Vector3.UP)).normalized()
	var slope_degrees := rad_to_deg(acos(clampf(ground_normal.dot(Vector3.UP), -1.0, 1.0)))
	_free_placement_debug(
		"ground collider=%s position=%s normal=%s slope=%.2f max=%.2f"
		% [
			_free_placement_collider_label(ground_hit.get("collider", null)),
			ground_hit.get("position", Vector3.ZERO),
			ground_normal,
			slope_degrees,
			FREE_PLACEMENT_MAX_SLOPE_DEGREES,
		]
	)
	if slope_degrees > FREE_PLACEMENT_MAX_SLOPE_DEGREES:
		_free_placement_debug("rejected reason=placement_too_steep")
		return {"ok": false, "reason": "placement_too_steep"}
	var ground_position := _vector3_from_value(ground_hit.get("position", requested_position))
	var packed := load(scene_path) as PackedScene
	if packed == null:
		_free_placement_debug("rejected reason=placement_missing_scene")
		return {"ok": false, "reason": "placement_missing_scene"}
	var placement_preview := packed.instantiate() as Node3D
	if placement_preview == null:
		_free_placement_debug("rejected reason=placement_bad_scene")
		return {"ok": false, "reason": "placement_bad_scene"}
	var collision_shape := placement_preview.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision_shape == null:
		collision_shape = placement_preview.get_node_or_null("VehicleShape") as CollisionShape3D
	if collision_shape == null or collision_shape.shape == null:
		placement_preview.free()
		_free_placement_debug("rejected reason=placement_missing_collision_shape")
		return {"ok": false, "reason": "placement_missing_collision_shape"}
	var support_offset := _free_placement_support_offset(collision_shape)
	var placement_position := ground_position + Vector3.UP * support_offset
	var clearance_shape := _make_free_placement_clearance_shape(collision_shape.shape)
	if clearance_shape == null:
		placement_preview.free()
		_free_placement_debug(
			"rejected reason=placement_unsupported_collision_shape shape=%s"
			% collision_shape.shape.get_class()
		)
		return {"ok": false, "reason": "placement_unsupported_collision_shape"}
	var placement_cast := ShapeCast3D.new()
	placement_cast.shape = clearance_shape
	placement_cast.target_position = Vector3.ZERO
	placement_cast.collision_mask = FREE_PLACEMENT_BLOCKING_MASK
	placement_cast.collide_with_bodies = true
	placement_cast.collide_with_areas = false
	placement_cast.enabled = true
	var world := GlobalVar.gameworld
	if world == null:
		world = get_tree().current_scene as Node3D
	if world == null:
		placement_preview.free()
		_free_placement_debug("rejected reason=placement_missing_world")
		return {"ok": false, "reason": "placement_missing_world"}
	world.add_child(placement_cast)
	placement_cast.global_transform = Transform3D(Basis(Vector3.UP, placement_yaw), placement_position) * collision_shape.transform
	_add_free_placement_exception(placement_cast, player_physics_nodes.get(peer_id, null))
	for player in get_tree().get_nodes_in_group("human_players"):
		if player is GamePlayer and int(player.authority_peer_id) == peer_id:
			_add_free_placement_exception(placement_cast, player)
	placement_cast.force_shapecast_update()
	var blocked := placement_cast.is_colliding()
	var blocking_colliders: Array[String] = []
	for index in range(placement_cast.get_collision_count()):
		blocking_colliders.append(_free_placement_collider_label(placement_cast.get_collider(index)))
	_free_placement_debug(
		"shape=%s clearance=%s position=%s mask=%d collisions=%s"
		% [
			collision_shape.shape.get_class(),
			clearance_shape.get_class(),
			placement_position,
			FREE_PLACEMENT_BLOCKING_MASK,
			blocking_colliders,
		]
	)
	placement_cast.queue_free()
	placement_preview.free()
	if blocked:
		_free_placement_debug("rejected reason=placement_blocked")
		return {"ok": false, "reason": "placement_blocked"}
	_free_placement_debug(
		"accepted position=%s support_offset=%.3f" % [placement_position, support_offset]
	)
	return {"ok": true, "position": placement_position}


func _free_placement_support_offset(collision_shape: CollisionShape3D) -> float:
	# Root placement is chosen so the lowest point of the collision shape rests on
	# the sampled ground, irrespective of the scene's mesh/model origin.
	var transform := collision_shape.transform
	var shape := collision_shape.shape
	var y_extent := 0.0
	if shape is BoxShape3D:
		var half_size := (shape as BoxShape3D).size * 0.5
		y_extent = (
			absf(transform.basis.x.y) * half_size.x
			+ absf(transform.basis.y.y) * half_size.y
			+ absf(transform.basis.z.y) * half_size.z
		)
	elif shape is SphereShape3D:
		var radius := (shape as SphereShape3D).radius
		y_extent = radius * Vector3(
			transform.basis.x.y,
			transform.basis.y.y,
			transform.basis.z.y
		).length()
	elif shape is CapsuleShape3D:
		var capsule := shape as CapsuleShape3D
		var radius := capsule.radius
		var segment_half_height := maxf(0.0, capsule.height * 0.5 - radius)
		var sphere_y_extent := radius * Vector3(
			transform.basis.x.y,
			transform.basis.y.y,
			transform.basis.z.y
		).length()
		y_extent = absf(transform.basis.y.y) * segment_half_height + sphere_y_extent
	elif shape is CylinderShape3D:
		var cylinder := shape as CylinderShape3D
		var radial_y_extent := cylinder.radius * sqrt(
			pow(transform.basis.x.y, 2.0) + pow(transform.basis.z.y, 2.0)
		)
		y_extent = absf(transform.basis.y.y) * cylinder.height * 0.5 + radial_y_extent
	else:
		# Unsupported shapes were already rejected by the clearance validator.
		return -transform.origin.y
	return -(transform.origin.y - y_extent)


func _make_free_placement_clearance_shape(source_shape: Shape3D) -> Shape3D:
	var expanded := source_shape.duplicate(true) as Shape3D
	if expanded is BoxShape3D:
		(expanded as BoxShape3D).size += Vector3.ONE * FREE_PLACEMENT_CLEARANCE * 2.0
	elif expanded is SphereShape3D:
		(expanded as SphereShape3D).radius += FREE_PLACEMENT_CLEARANCE
	elif expanded is CapsuleShape3D:
		var capsule := expanded as CapsuleShape3D
		capsule.radius += FREE_PLACEMENT_CLEARANCE
		capsule.height += FREE_PLACEMENT_CLEARANCE * 2.0
	elif expanded is CylinderShape3D:
		var cylinder := expanded as CylinderShape3D
		cylinder.radius += FREE_PLACEMENT_CLEARANCE
		cylinder.height += FREE_PLACEMENT_CLEARANCE * 2.0
	else:
		return null
	return expanded


func _add_free_placement_exception(shape_cast: ShapeCast3D, node: Variant) -> void:
	if node is CollisionObject3D:
		shape_cast.add_exception(node as CollisionObject3D)


func _free_placement_collider_label(collider: Variant) -> String:
	if collider is CollisionObject3D:
		var body := collider as CollisionObject3D
		return "%s<%s> layer=%d" % [body.get_path(), body.get_class(), body.collision_layer]
	return str(collider)


func _free_placement_debug(message: String) -> void:
	if free_placement_debug_enabled:
		print("[FreePlacement] ", message)


func _spawn_server_projectile(
	peer_id: int,
	tool_request: Dictionary,
	projectile_type: String,
	speed: float,
	damage: float,
	radius: float,
	effect: String,
	collision_mask := -1,
	show_owner_hit_marker := true
) -> Dictionary:
	var state: Dictionary = player_states[peer_id]
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var resolved_collision_mask := collision_mask
	if resolved_collision_mask < 0:
		resolved_collision_mask = _projectile_collision_mask_for_type(projectile_type)
	var projectile_id := next_projectile_id
	next_projectile_id += 1
	projectile_states[projectile_id] = {
		"projectile_id": projectile_id,
		"type": projectile_type,
		"team": state.get("team", ""),
		"owner_peer_id": peer_id,
		"position": origin,
		"velocity": direction * speed,
		"damage": damage,
		"radius": radius,
		"effect": effect,
		"show_owner_hit_marker": show_owner_hit_marker,
		"collision_mask": resolved_collision_mask,
		"life": 0.0,
		"max_life": 8.0,
	}
	if mode == MODE_LOCAL and projectile_type in ["boom", "drone_bomb", "auto_shooter_boom"]:
		_spawn_local_projectile_visual(projectile_id, BOOM_BULLET_SCENE, projectile_states[projectile_id])
	return {"ok": true, "projectile_id": projectile_id, "projectile_type": projectile_type, "position": origin}


func _spawn_grenade_projectile(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	# Throw along the crosshair ray with a slight lift for a readable ballistic arc.
	direction = (direction + Vector3.UP * 0.15).normalized()
	var result := _spawn_server_projectile(
		peer_id,
		{
			"origin": tool_request.get("origin", (player_states[peer_id] as Dictionary).get("position", Vector3.ZERO)),
			"direction": direction,
		},
		"grenade",
		CombatBalance.get_float("grenade", "throw_speed"),
		CombatBalance.get_float("grenade", "damage"),
		CombatBalance.get_float("grenade", "damage_radius"),
		"grenade",
		_projectile_collision_mask_for_type("grenade"),
		true
	)
	var projectile_id := int(result.get("projectile_id", 0))
	if projectile_states.has(projectile_id):
		var projectile: Dictionary = projectile_states[projectile_id]
		projectile["gravity"] = CombatBalance.get_float("grenade", "gravity")
		projectile["max_life"] = CombatBalance.get_float("grenade", "lifetime")
		projectile["fuse_only"] = true
		projectile["friendly_fire"] = true
		projectile["linear_falloff"] = true
		projectile["knockback"] = CombatBalance.get_float("grenade", "knockback")
		projectile_states[projectile_id] = projectile
		_spawn_local_projectile_visual(projectile_id, GRENADE_VISUAL_SCENE, projectile)
	return result


func _spawn_vehicle_shield_laser(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var result := _spawn_server_projectile(
		peer_id,
		tool_request,
		"vehicle_shield_laser",
		CombatBalance.get_float("vehicle_shield_shooter", "projectile_speed", 60.0),
		0.0,
		0.0,
		"vehicle_shield",
		_projectile_collision_mask_for_type("vehicle_shield_laser"),
		false
	)
	var projectile_id := int(result.get("projectile_id", 0))
	if projectile_states.has(projectile_id):
		var projectile: Dictionary = projectile_states[projectile_id]
		projectile["gravity"] = 0.0
		projectile["max_life"] = CombatBalance.get_float(
			"vehicle_shield_shooter", "projectile_lifetime", 3.0
		)
		projectile["ignore_player_collisions"] = true
		projectile_states[projectile_id] = projectile
		_spawn_local_projectile_visual(projectile_id, SHIELD_LASER_VISUAL_SCENE, projectile)
	return result


func _spawn_local_projectile_visual(projectile_id: int, scene: PackedScene, projectile: Dictionary) -> void:
	if mode != MODE_LOCAL or projectile_id <= 0 or scene == null:
		return
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world == null:
		return
	var visual := scene.instantiate() as Node3D
	if visual == null:
		return
	world.add_child(visual)
	visual.global_position = _vector3_from_value(projectile.get("position", Vector3.ZERO))
	local_projectile_visual_nodes[projectile_id] = visual


func _remove_local_projectile_visual(projectile_id: int) -> void:
	var visual: Variant = local_projectile_visual_nodes.get(projectile_id, null)
	if is_instance_valid(visual):
		(visual as Node).queue_free()
	local_projectile_visual_nodes.erase(projectile_id)


func _spawn_local_grenade_explosion(position: Vector3) -> void:
	if mode != MODE_LOCAL:
		return
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world == null:
		return
	var effect := GRENADE_EXPLOSION_SCENE.instantiate() as Node3D
	if effect == null:
		return
	world.add_child(effect)
	effect.global_position = position


func _spawn_local_boom_explosion(position: Vector3) -> void:
	if mode != MODE_LOCAL:
		return
	var world: Node = GlobalVar.gameworld if is_instance_valid(GlobalVar.gameworld) else get_tree().current_scene
	if world == null:
		return
	var effect := BOOM_EFFECT_SCENE.instantiate() as Node3D
	if effect == null:
		return
	world.add_child(effect)
	effect.global_position = position


func _spawn_spicy_projectile(peer_id: int, tool_request: Dictionary) -> Dictionary:
	var result := _spawn_server_projectile(
		peer_id,
		tool_request,
		"spicy_bullet",
		CombatBalance.get_float("spicy_blaster", "projectile_speed"),
		CombatBalance.get_float("spicy_blaster", "projectile_strength"),
		0.0,
		"spicy",
		COLLISION_LAYER_GROUND
	)
	if not bool(result.get("ok", false)):
		return result
	var projectile_id := int(result.get("projectile_id", 0))
	var projectile: Dictionary = projectile_states.get(projectile_id, {})
	if projectile.is_empty():
		return result
	projectile["gravity"] = CombatBalance.get_float("spicy_blaster", "projectile_gravity")
	projectile["max_life"] = CombatBalance.get_float("spicy_blaster", "projectile_lifetime")
	projectile["max_distance"] = CombatBalance.get_float("spicy_blaster", "projectile_range")
	projectile["start_position"] = projectile.get("position", Vector3.ZERO)
	projectile["ignore_player_collisions"] = true
	projectile_states[projectile_id] = projectile
	return result


func _simulate_projectiles(delta: float) -> void:
	var to_remove: Array[int] = []
	for raw_id in projectile_states.keys():
		var projectile_id := int(raw_id)
		var projectile: Dictionary = projectile_states[projectile_id]
		var position := _vector3_from_value(projectile.get("position", Vector3.ZERO))
		var velocity := _vector3_from_value(projectile.get("velocity", Vector3.ZERO))
		var old_position := position
		var projectile_delta := delta
		if _is_area_protector_cannonball_type(str(projectile.get("type", ""))):
			projectile_delta *= AreaProtectorTool.get_cannonball_speed_multiplier_at(
				self, old_position, str(projectile.get("team", ""))
			)
		velocity += Vector3.DOWN * float(projectile.get("gravity", 18.0)) * projectile_delta
		position += velocity * projectile_delta
		projectile["life"] = float(projectile.get("life", 0.0)) + delta
		projectile["position"] = position
		projectile["velocity"] = velocity
		projectile_states[projectile_id] = projectile
		var hit := _raycast_world(
			old_position,
			position,
			int(projectile.get("collision_mask", DEFAULT_COMBAT_RAYCAST_MASK))
		)
		# This sweep models the player capsule, not the projectile's impact radius.
		var hit_peer := 0
		var fuse_only := bool(projectile.get("fuse_only", false))
		if not fuse_only and not bool(projectile.get("ignore_player_collisions", false)):
			hit_peer = _find_player_hit_by_segment(
				int(projectile.get("owner_peer_id", 0)),
				str(projectile.get("team", "")),
				old_position,
				position,
				maxf(0.01, float(projectile.get("direct_hit_radius", 0.6)))
			)
		var timed_out := float(projectile.get("life", 0.0)) >= float(projectile.get("max_life", 8.0))
		var max_distance := float(projectile.get("max_distance", 0.0))
		if max_distance > 0.0:
			var start := _vector3_from_value(projectile.get("start_position", old_position))
			timed_out = timed_out or start.distance_to(position) >= max_distance
		if fuse_only and hit.has("collider") and not timed_out:
			var hit_position := _vector3_from_value(hit.get("position", position))
			var hit_normal := _vector3_from_value(hit.get("normal", Vector3.UP)).normalized()
			if hit_normal.length_squared() <= 0.001:
				hit_normal = Vector3.UP
			position = hit_position + hit_normal * 0.06
			velocity = velocity.bounce(hit_normal) * 0.32
			velocity.x *= 0.72
			velocity.z *= 0.72
			if velocity.length() < 1.15 or hit_normal.dot(Vector3.UP) > 0.75:
				velocity = Vector3.ZERO
				projectile["resting"] = true
			projectile["position"] = position
			projectile["velocity"] = velocity
			projectile_states[projectile_id] = projectile
		elif hit_peer != 0 or (hit.has("collider") and not fuse_only) or timed_out:
			var hit_position := _vector3_from_value(hit.get("position", position))
			var hit_world := hit.has("collider")
			if str(projectile.get("type", "")) == "vehicle_shield_laser":
				if hit_world:
					_apply_vehicle_shield_laser_hit(projectile, hit)
				to_remove.append(projectile_id)
				continue
			# The current maps are flat. A spicy shot that reaches its travel cap
			# therefore deposits directly below its final X/Z instead of vanishing.
			if str(projectile.get("type", "")) == "spicy_bullet" and timed_out and not hit_world:
				hit_position = Vector3(position.x, 0.0, position.z)
				hit_world = true
			_explode_projectile(projectile_id, hit_position, hit_peer, hit_world)
			to_remove.append(projectile_id)
		var local_visual: Variant = local_projectile_visual_nodes.get(projectile_id, null)
		if is_instance_valid(local_visual) and not to_remove.has(projectile_id):
			(local_visual as Node3D).global_position = _vector3_from_value(projectile.get("position", position))
			var visual_velocity := _vector3_from_value(projectile.get("velocity", velocity))
			if visual_velocity.length_squared() > 0.01:
				(local_visual as Node3D).look_at((local_visual as Node3D).global_position + visual_velocity, Vector3.UP)
	for projectile_id in to_remove:
		projectile_states.erase(projectile_id)
		_remove_local_projectile_visual(projectile_id)


func _register_placed_tool(peer_id: int, tool_name: String, team: String, tool_path: String, position: Vector3, yaw := 0.0) -> void:
	var placed_node := _gameplay_tool_node(get_node_or_null(NodePath(tool_path)))
	var placed_max_hp := _configured_tool_hp(tool_name, placed_node)
	placed_tool_states[tool_path] = {
		"tool_id": tool_path,
		"tool_name": tool_name,
		"owner_peer_id": peer_id,
		"team": team,
		"path": tool_path,
		"position": position,
		"yaw": yaw,
		"hp": placed_max_hp,
		"max_hp": placed_max_hp,
		"cooldown_left": 0.2,
		"free_placement": false,
	}


func _simulate_placed_tools(delta: float) -> void:
	for raw_id in placed_tool_states.keys():
		var tool_id := str(raw_id)
		var tool: Dictionary = placed_tool_states[tool_id]
		var cooldown_left := maxf(0.0, float(tool.get("cooldown_left", 0.0)) - delta)
		tool["cooldown_left"] = cooldown_left
		if cooldown_left > 0.0:
			placed_tool_states[tool_id] = tool
			continue
		var tool_name := str(tool.get("tool_name", ""))
		match tool_name:
			"AutoShooter":
				var shooter := _gameplay_tool_node(_node_for_tool_ref({"kind": "placed", "id": tool_id}))
				if shooter == null or not shooter.has_method("is_deployed_on_farm_tile") \
						or not bool(shooter.call("is_deployed_on_farm_tile")):
					tool["cooldown_left"] = 0.5
					placed_tool_states[tool_id] = tool
					continue
				if shooter != null and float(shooter.get("disable_remaining")) > 0.0:
					tool["cooldown_left"] = 0.1
					placed_tool_states[tool_id] = tool
					continue
				if _server_fire_tool_projectile(
					tool,
					_configured_tool_float(shooter, "target_range", CombatBalance.get_float("auto_shooter", "target_range")),
					_configured_tool_float(shooter, "projectile_speed", CombatBalance.get_float("auto_shooter", "projectile_speed")),
					_configured_tool_float(shooter, "projectile_damage", CombatBalance.get_float("auto_shooter", "damage")),
					_configured_tool_float(shooter, "projectile_radius", CombatBalance.get_float("auto_shooter", "radius")),
					"Explosion",
					"auto_shooter_boom"
				):
					tool["cooldown_left"] = _configured_tool_float(shooter, "shoot_cd_time", CombatBalance.get_float("auto_shooter", "fire_interval"))
				else:
					tool["cooldown_left"] = 0.5
			"WheatSentry":
				var sentry := _gameplay_tool_node(_node_for_tool_ref({"kind": "placed", "id": tool_id}))
				if sentry != null and sentry.has_method("is_electronics_disabled") and bool(sentry.call("is_electronics_disabled")):
					tool["cooldown_left"] = 0.1
					placed_tool_states[tool_id] = tool
					continue
				var target: Variant = _find_nearest_enemy_player_position(
					str(tool.get("team", "")),
					_vector3_from_value(tool.get("position", Vector3.ZERO)) + Vector3.UP * 1.2,
					_configured_tool_float(sentry, "target_range", CombatBalance.get_float("wheat_sentry", "target_range"))
				)
				var fired := false
				if target is Vector3:
					_update_wheat_sentry_authoritative_visual(tool, target as Vector3, delta)
					var aim_ready := sentry == null or not sentry.has_method("is_authoritative_fire_ready") or bool(sentry.call("is_authoritative_fire_ready", target))
					if aim_ready:
						var muzzle_origin: Variant = sentry.call("get_authoritative_fire_origin") if sentry != null and sentry.has_method("get_authoritative_fire_origin") else null
						var muzzle_direction: Variant = sentry.call("get_authoritative_fire_direction") if sentry != null and sentry.has_method("get_authoritative_fire_direction") else null
						fired = _server_fire_tool_projectile(
							tool,
							_configured_tool_float(sentry, "target_range", CombatBalance.get_float("wheat_sentry", "target_range")),
							_configured_tool_float(sentry, "bullet_speed", CombatBalance.get_float("wheat_sentry", "projectile_speed")),
							_configured_tool_float(sentry, "projectile_damage", CombatBalance.get_float("wheat_sentry", "damage")),
							_configured_tool_float(sentry, "impact_radius", CombatBalance.get_float("wheat_sentry", "impact_radius")),
							"nail",
							"wheat_sentry_bullet",
							false,
							target,
							muzzle_origin,
							muzzle_direction,
							0.0,
							_configured_tool_float(sentry, "direct_hit_radius", CombatBalance.get_float("wheat_sentry", "direct_hit_radius"))
						)
				elif sentry != null and sentry.has_method("apply_authoritative_idle_rotation"):
					sentry.call("apply_authoritative_idle_rotation", delta)
				if fired:
					tool["cooldown_left"] = _configured_tool_float(sentry, "fire_interval", CombatBalance.get_float("wheat_sentry", "fire_interval"))
				else:
					tool["cooldown_left"] = 0.05
			"AntiAir", "anti_air":
				var anti_air := _gameplay_tool_node(_node_for_tool_ref({"kind": "placed", "id": tool_id}))
				if anti_air != null and float(anti_air.get("disable_remaining")) > 0.0:
					tool["cooldown_left"] = 0.1
					placed_tool_states[tool_id] = tool
					continue
				if _server_intercept_enemy_projectile(tool, _configured_tool_float(anti_air, "intercept_range", CombatBalance.get_float("anti_air", "intercept_range"))):
					var shots_left := int(tool.get("intercepts_remaining", _configured_tool_int(anti_air, "magazine_size", CombatBalance.get_int("anti_air", "magazine_size")))) - 1
					if shots_left <= 0:
						tool["intercepts_remaining"] = _configured_tool_int(anti_air, "magazine_size", CombatBalance.get_int("anti_air", "magazine_size"))
						tool["cooldown_left"] = _configured_tool_float(anti_air, "cooldown_time", CombatBalance.get_float("anti_air", "reload_time"))
					else:
						tool["intercepts_remaining"] = shots_left
						tool["cooldown_left"] = 0.0
				else:
					tool["cooldown_left"] = 0.25
			_:
				tool["cooldown_left"] = 1.0
		placed_tool_states[tool_id] = tool


func _server_fire_tool_projectile(
	tool: Dictionary,
	range: float,
	speed: float,
	damage: float,
	radius: float,
	effect: String,
	projectile_type: String,
	horizontal_only := false,
	target_override: Variant = null,
	origin_override: Variant = null,
	direction_override: Variant = null,
	gravity := 18.0,
	direct_hit_radius := 0.6
) -> bool:
	var team := str(tool.get("team", ""))
	var origin := _vector3_from_value(origin_override) if origin_override is Vector3 else _vector3_from_value(tool.get("position", Vector3.ZERO)) + Vector3.UP * 1.2
	var target: Variant = target_override
	if not target is Vector3:
		target = _find_nearest_enemy_player_position(team, origin, range)
	if target == null:
		return false
	var direction: Vector3 = _vector3_from_value(direction_override) if direction_override is Vector3 else (target as Vector3) - origin
	if horizontal_only and not direction_override is Vector3:
		direction.y = 0.0
	direction = direction.normalized()
	if direction.length_squared() <= 0.001:
		return false
	var projectile_id := next_projectile_id
	next_projectile_id += 1
	projectile_states[projectile_id] = {
		"projectile_id": projectile_id,
		"type": projectile_type,
		"team": team,
		"owner_peer_id": int(tool.get("owner_peer_id", 0)),
		"position": origin,
		"velocity": direction * speed,
		"damage": damage,
		"radius": radius,
		"effect": effect,
		"show_owner_hit_marker": false,
		"gravity": gravity,
		"direct_hit_radius": direct_hit_radius,
		"collision_mask": _projectile_collision_mask_for_type(projectile_type),
		"life": 0.0,
		"max_life": 5.0,
	}
	reliable_world_event_ready.emit({
		"type": "tool_projectile_fired",
		"projectile_id": projectile_id,
		"tool_name": tool.get("tool_name", ""),
		"position": origin,
		"tick": server_tick,
	})
	return true


func _update_wheat_sentry_authoritative_visual(tool: Dictionary, target_position: Vector3, delta: float) -> void:
	var node = get_node_or_null(NodePath(str(tool.get("path", tool.get("tool_id", "")))))
	if node is FarmTile:
		node = (node as FarmTile).tool_child
	if node != null and node.has_method("apply_authoritative_target_position"):
		node.call("apply_authoritative_target_position", target_position, delta)


func _projectile_collision_mask_for_type(projectile_type: String) -> int:
	return int(PROJECTILE_COLLISION_MASK_BY_TYPE.get(projectile_type, DEFAULT_COMBAT_RAYCAST_MASK))


func _is_area_protector_cannonball_type(projectile_type: String) -> bool:
	var normalized := projectile_type.to_lower()
	return normalized.contains("boom") or normalized.contains("bomb")


func _is_area_protector_damage_projectile_type(projectile_type: String) -> bool:
	var normalized := projectile_type.to_lower()
	return normalized.contains("bullet") or normalized.contains("boom") \
		or normalized.contains("bomb")


func _find_nearest_enemy_player_position(team: String, origin: Vector3, range: float):
	var best_position = null
	var best_distance := range
	for raw_peer_id in player_states.keys():
		var state: Dictionary = player_states[raw_peer_id]
		if str(state.get("team", "")) == team:
			continue
		if float(state.get("hp", PLAYER_MAX_HP)) <= 0.0:
			continue
		var pos := _vector3_from_value(state.get("position", Vector3.ZERO)) + Vector3.UP
		var dist := origin.distance_to(pos)
		if dist <= best_distance:
			best_distance = dist
			best_position = pos
	return best_position


func _server_intercept_enemy_projectile(tool: Dictionary, range: float) -> bool:
	var team := str(tool.get("team", ""))
	var origin := _vector3_from_value(tool.get("position", Vector3.ZERO))
	var best_projectile_id := 0
	var best_distance := range
	for raw_projectile_id in projectile_states.keys():
		var projectile_id := int(raw_projectile_id)
		var projectile: Dictionary = projectile_states[projectile_id]
		if str(projectile.get("team", "")) == team:
			continue
		var pos := _vector3_from_value(projectile.get("position", Vector3.ZERO))
		var dist := origin.distance_to(pos)
		if dist <= best_distance:
			best_distance = dist
			best_projectile_id = projectile_id
	if best_projectile_id == 0:
		return false
	var intercepted: Dictionary = projectile_states.get(best_projectile_id, {})
	projectile_states.erase(best_projectile_id)
	var intercept_position := _vector3_from_value(intercepted.get("position", origin))
	var intercept_direction := (intercept_position - origin).normalized()
	if intercept_direction.length_squared() > 0.001:
		_emit_visual_projectile(
			int(tool.get("owner_peer_id", 0)),
			"defend_bullet",
			origin + Vector3.UP * 1.2,
			intercept_direction,
			200.0,
			maxf(0.05, origin.distance_to(intercept_position) / 200.0),
			"",
			true
		)
	reliable_world_event_ready.emit({
		"type": "projectile_intercepted",
		"projectile_id": best_projectile_id,
		"position": intercepted.get("position", origin),
		"tick": server_tick,
	})
	return true


## Local BoomBullet entities (Wreck, NormalDrone, and AutoShooter) use this
## instead of their old AI-only overlap check.  Multiplayer projectiles are
## still resolved by _explode_projectile on the server.
func apply_local_boom_explosion(
	position: Vector3,
	team: String,
	damage: float,
	radius: float,
	effect := "Explosion",
	knockback := 20.0
) -> void:
	if not is_local_authority() or radius <= 0.0 or damage <= 0.0:
		return
	# Match server projectile resolution: the shield zone weakens an enemy Boom
	# at the actual detonation point, before its radius damage is distributed.
	damage *= AreaProtectorTool.get_damage_multiplier_at(self, position, team)
	var attacker_peer_id := resolve_attacker_peer_id(team)
	for peer_id_value in player_states.keys():
		var peer_id := int(peer_id_value)
		var target: Dictionary = player_states[peer_id]
		if str(target.get("team", "")) == team:
			continue
		var position_value: Variant = get_authoritative_player_position(peer_id)
		var target_position: Vector3 = position_value as Vector3 if position_value is Vector3 else _vector3_from_value(target.get("position", Vector3.ZERO))
		var distance := target_position.distance_to(position)
		if distance > radius:
			continue
		var ratio := 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(position, target_position + Vector3.UP * 0.9)
		var direction := (target_position - position).normalized()
		_damage_player(
			peer_id,
			damage * ratio * occlusion,
			knockback * ratio * occlusion,
			direction,
			team,
			effect,
			attacker_peer_id
		)
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null:
		var plots: Array = manager.call("get_plots_in_radius", position, radius)
		for plot in plots:
			if not plot is FarmTile:
				continue
			var tile := plot as FarmTile
			var occlusion := _explosion_damage_multiplier(position, tile.global_position + Vector3.UP * 0.15, tile)
			tile.impact(effect, damage * occlusion, team)
	_damage_future_warriors_in_radius(position, radius, damage, team, effect, false, false)
	_damage_farmer_ais_in_radius(position, radius, damage, team, effect, false, false)
	_damage_assistant_ai_in_radius(position, radius, damage, team, effect, false, false)
	_damage_ai_normal_drones_in_radius(position, radius, damage, team, effect, false, false)
	_damage_vehicles_in_radius(position, radius, damage, team, effect)
	_damage_tools_in_radius(position, radius, damage, team, effect)
	_damage_harvest_trees_in_radius(position, radius, damage, team, effect, false, attacker_peer_id)
	_damage_nature_resources_in_radius(position, radius, damage, team, effect, false, attacker_peer_id)
	_damage_wild_animals_in_radius(position, radius, damage, knockback, team, effect, false, attacker_peer_id)


func _explode_projectile(projectile_id: int, hit_position: Vector3, direct_hit_peer_id := 0, hit_world := true) -> void:
	if not projectile_states.has(projectile_id):
		return
	var projectile: Dictionary = projectile_states[projectile_id]
	var team := str(projectile.get("team", ""))
	var radius := float(projectile.get("radius", 4.0))
	var damage := float(projectile.get("damage", 100.0))
	if _is_area_protector_damage_projectile_type(str(projectile.get("type", ""))):
		damage *= AreaProtectorTool.get_damage_multiplier_at(
			self, hit_position, str(projectile.get("team", ""))
		)
	var effect := str(projectile.get("effect", "Explosion"))
	var projectile_type := str(projectile.get("type", ""))
	var friendly_fire := bool(projectile.get("friendly_fire", false))
	var damage_team := "" if friendly_fire else team
	var linear_falloff := bool(projectile.get("linear_falloff", false))
	var knockback_strength := float(projectile.get("knockback", 20.0))
	var confirmed_target_count := 0
	var confirmed_total_damage := 0.0
	if projectile_type != "spicy_bullet":
		for peer_id in player_states.keys():
			var target: Dictionary = player_states[peer_id]
			if not friendly_fire and str(target.get("team", "")) == team:
				continue
			var is_direct_hit := int(peer_id) == direct_hit_peer_id
			var position_value: Variant = get_authoritative_player_position(int(peer_id))
			var pos: Vector3 = position_value as Vector3 if position_value is Vector3 else _vector3_from_value(target.get("position", Vector3.ZERO))
			var dist := pos.distance_to(hit_position)
			if is_direct_hit or dist <= radius:
				var ratio := 1.0 if is_direct_hit else maxf(0.0, 1.0 - dist / radius) \
					if linear_falloff else 1.0 - (dist / radius) * 0.5
				var dir := (pos - hit_position).normalized()
				var occlusion := _explosion_damage_multiplier(hit_position, pos + Vector3.UP * 0.9)
				var applied_damage := damage * ratio * occlusion
				if _damage_player(
					int(peer_id), applied_damage, knockback_strength * ratio * occlusion,
					dir, damage_team, effect, int(projectile.get("owner_peer_id", 0))
				):
					confirmed_target_count += 1
					confirmed_total_damage += applied_damage
		var future_warrior_damage := _damage_future_warriors_in_radius(
			hit_position, radius, damage, damage_team, effect, linear_falloff, friendly_fire
		)
		confirmed_target_count += int(future_warrior_damage.get("count", 0))
		confirmed_total_damage += float(future_warrior_damage.get("total_damage", 0.0))
		var farmer_ai_damage := _damage_farmer_ais_in_radius(
			hit_position, radius, damage, damage_team, effect, linear_falloff, friendly_fire
		)
		confirmed_target_count += int(farmer_ai_damage.get("count", 0))
		confirmed_total_damage += float(farmer_ai_damage.get("total_damage", 0.0))
		var assistant_damage := _damage_assistant_ai_in_radius(hit_position, radius, damage, damage_team, effect, linear_falloff, friendly_fire)
		confirmed_target_count += int(assistant_damage.get("count", 0))
		confirmed_total_damage += float(assistant_damage.get("total_damage", 0.0))
		var ai_drone_damage := _damage_ai_normal_drones_in_radius(hit_position, radius, damage, damage_team, effect, linear_falloff, friendly_fire)
		confirmed_target_count += int(ai_drone_damage.get("count", 0))
		confirmed_total_damage += float(ai_drone_damage.get("total_damage", 0.0))
		var manager := get_node_or_null("/root/Farmlandmanager")
		if manager != null:
			var plots: Array = manager.call("get_plots_in_radius", hit_position, radius)
			for plot in plots:
				if plot is FarmTile:
					var tile := plot as FarmTile
					var occlusion := _explosion_damage_multiplier(hit_position, tile.global_position + Vector3.UP * 0.15, tile)
					var tile_distance := tile.global_position.distance_to(hit_position)
					var tile_ratio := maxf(0.0, 1.0 - tile_distance / radius) if linear_falloff else 1.0
					tile.impact(effect, damage * tile_ratio * occlusion, damage_team)
	if projectile_type == "bug_boom":
		_spawn_authoritative_bug_storm(hit_position, team)
	elif projectile_type == "medicine_boom":
		_spawn_authoritative_medicine_storm(
			hit_position,
			team,
			int(projectile.get("owner_peer_id", 0))
		)
	elif projectile_type == "spicy_bullet" and hit_world:
		_spawn_authoritative_spicy_area(
			hit_position,
			team,
			int(projectile.get("owner_peer_id", 0)),
			_vector3_from_value(projectile.get("velocity", Vector3.FORWARD))
		)
	if projectile_type != "spicy_bullet":
		var damaged_vehicles := _damage_vehicles_in_radius(hit_position, radius, damage, damage_team, effect, linear_falloff)
		confirmed_target_count += damaged_vehicles
		if damaged_vehicles > 0:
			confirmed_total_damage += damage
		var damaged_tools := _damage_tools_in_radius(hit_position, radius, damage, damage_team, effect, linear_falloff)
		confirmed_target_count += damaged_tools
		if damaged_tools > 0:
			confirmed_total_damage += damage
		var damaged_trees := _damage_harvest_trees_in_radius(
			hit_position, radius, damage, damage_team, effect, linear_falloff,
			int(projectile.get("owner_peer_id", 0))
		)
		confirmed_target_count += damaged_trees
		if damaged_trees > 0:
			confirmed_total_damage += damage * float(damaged_trees)
		var damaged_nature := _damage_nature_resources_in_radius(
			hit_position, radius, damage, damage_team, effect, linear_falloff,
			int(projectile.get("owner_peer_id", 0))
		)
		confirmed_target_count += damaged_nature
		if damaged_nature > 0:
			confirmed_total_damage += damage * float(damaged_nature)
		var damaged_animals := _damage_wild_animals_in_radius(
			hit_position, radius, damage, knockback_strength,
			damage_team, effect, linear_falloff,
			int(projectile.get("owner_peer_id", 0))
		)
		confirmed_target_count += damaged_animals
		if damaged_animals > 0:
			confirmed_total_damage += damage * float(damaged_animals)
	if confirmed_target_count > 0 and bool(projectile.get("show_owner_hit_marker", false)):
		_emit_hit_confirmed(
			int(projectile.get("owner_peer_id", 0)),
			confirmed_target_count,
			confirmed_total_damage,
			projectile_type
		)
	if projectile_type == "grenade":
		_spawn_local_grenade_explosion(hit_position)
	elif mode == MODE_LOCAL and projectile_type in ["boom", "drone_bomb", "auto_shooter_boom"]:
		_spawn_local_boom_explosion(hit_position)
	reliable_world_event_ready.emit({
		"type": "projectile_exploded",
		"projectile_id": projectile_id,
		"projectile_type": projectile.get("type", ""),
		"team": team,
		"position": hit_position,
		"effect": effect,
		"direction": _vector3_from_value(projectile.get("velocity", Vector3.FORWARD)),
		"hit_world": hit_world,
		"shake_radius": CombatBalance.get_float("grenade", "shake_radius") if projectile_type == "grenade" else 0.0,
		"tick": server_tick,
	})


func _spawn_authoritative_bug_storm(position: Vector3, source_team: String) -> void:
	var world_root: Node = GlobalVar.gameworld
	if world_root == null or not is_instance_valid(world_root):
		world_root = get_tree().current_scene
	if world_root == null:
		return
	var storm := BUG_STORM_SCENE.instantiate() as Node3D
	if storm == null:
		return
	storm.set("source_team", source_team)
	storm.set("visual_only", false)
	storm.set("effect_distance", CombatBalance.get_float("bug_storm", "radius"))
	storm.set("lifetime", CombatBalance.get_float("bug_storm", "lifetime"))
	storm.set("tick_interval", CombatBalance.get_float("bug_storm", "tick_interval"))
	storm.set("bug_strength", CombatBalance.get_float("bug_storm", "strength"))
	storm.set("fade_time", CombatBalance.get_float("bug_storm", "fade_time"))
	world_root.add_child(storm)
	storm.global_position = position


func _spawn_authoritative_medicine_storm(
	position: Vector3,
	source_team: String,
	source_peer_id := 0
) -> void:
	var world_root: Node = GlobalVar.gameworld
	if world_root == null or not is_instance_valid(world_root):
		world_root = get_tree().current_scene
	if world_root == null:
		return
	var storm := MEDICINE_STORM_SCENE.instantiate() as Node3D
	if storm == null:
		return
	storm.set("source_team", source_team)
	storm.set("effect_distance", CombatBalance.get_float("medicine_storm", "radius"))
	storm.set("lifetime", CombatBalance.get_float("medicine_storm", "lifetime"))
	storm.set("tick_interval", CombatBalance.get_float("medicine_storm", "tick_interval"))
	storm.set("effect_strength", CombatBalance.get_float("medicine_storm", "strength"))
	# Local matches BugStorm's scene-driven impact path. Dedicated servers use
	# player_states below because their lightweight physics bodies have no impact().
	storm.set("visual_only", mode == MODE_SERVER)
	world_root.add_child(storm)
	storm.global_position = position
	if mode != MODE_SERVER:
		return
	var storm_id := next_medicine_storm_id
	next_medicine_storm_id += 1
	medicine_storm_states[storm_id] = {
		"position": position,
		"team": source_team,
		"source_peer_id": source_peer_id,
			"life_left": CombatBalance.get_float("medicine_storm", "lifetime"),
			"tick_left": 0.0,
			"radius": CombatBalance.get_float("medicine_storm", "radius"),
	}


func _simulate_medicine_storms(delta: float) -> void:
	if mode != MODE_SERVER:
		return
	var expired: Array[int] = []
	for raw_id in medicine_storm_states.keys():
		var storm_id := int(raw_id)
		var storm: Dictionary = medicine_storm_states[storm_id]
		storm["life_left"] = float(storm.get("life_left", 0.0)) - delta
		storm["tick_left"] = float(storm.get("tick_left", 0.0)) - delta
		if float(storm["tick_left"]) <= 0.0:
			storm["tick_left"] = CombatBalance.get_float("medicine_storm", "tick_interval")
			_apply_authoritative_medicine_storm_tick(storm)
		if float(storm["life_left"]) <= 0.0:
			expired.append(storm_id)
		else:
			medicine_storm_states[storm_id] = storm
	for storm_id in expired:
		medicine_storm_states.erase(storm_id)


func _apply_authoritative_medicine_storm_tick(storm: Dictionary) -> void:
	var center := _vector3_from_value(storm.get("position", Vector3.ZERO))
	var source_team := str(storm.get("team", ""))
	var source_peer_id := int(storm.get("source_peer_id", 0))
	var radius := float(storm.get("radius", CombatBalance.get_float("medicine_storm", "radius")))
	for raw_peer_id in player_states.keys():
		var peer_id := int(raw_peer_id)
		var target: Dictionary = player_states[peer_id]
		if float(target.get("respawn_left", 0.0)) > 0.0:
			continue
		var target_position := _vector3_from_value(target.get("position", Vector3.ZERO))
		if center.distance_to(target_position) > radius:
			continue
		if str(target.get("team", "")) == source_team:
			_heal_player(peer_id, CombatBalance.get_float("medicine_storm", "strength"), source_peer_id)
		else:
			_damage_player(peer_id, CombatBalance.get_float("medicine_storm", "strength"), 0.0, Vector3.ZERO, source_team, "medicine_storm")


func _spawn_authoritative_spicy_area(position: Vector3, source_team: String, source_peer_id: int, direction: Vector3) -> void:
	var world_root: Node = GlobalVar.gameworld
	if world_root == null or not is_instance_valid(world_root):
		world_root = get_tree().current_scene
	if world_root == null:
		return
	var forward := Vector3(direction.x, 0.0, direction.z).normalized()
	if forward.length_squared() <= 0.001:
		forward = Vector3.FORWARD
	var area := SPICY_AREA_SCENE.instantiate() as Node3D
	if area != null:
		area.set("source_team", source_team)
		area.set("visual_only", false)
		area.set("lifetime", CombatBalance.get_float("spicy_blaster", "area_lifetime"))
		area.set("fade_time", CombatBalance.get_float("spicy_blaster", "area_fade_time"))
		area.set("area_length", CombatBalance.get_float("spicy_blaster", "area_length"))
		area.set("area_width", CombatBalance.get_float("spicy_blaster", "area_width"))
		area.set("area_height", CombatBalance.get_float("spicy_blaster", "area_height"))
		area.set("tick_interval", CombatBalance.get_float("spicy_blaster", "area_tick_interval"))
		world_root.add_child(area)
		area.global_position = position
		area.look_at(area.global_position + forward, Vector3.UP)


func _raycast_requested_collider(state: Dictionary, tool_request: Dictionary):
	var target_tile_path := str(tool_request.get("target_tile_path", ""))
	if not target_tile_path.is_empty():
		var tile_node := get_node_or_null(NodePath(target_tile_path))
		if tile_node is FarmTile:
			return tile_node
	var target_position := _vector3_from_value(tool_request.get("target_position", Vector3.ZERO))
	if target_position != Vector3.ZERO:
		var manager := get_node_or_null("/root/Farmlandmanager")
		if manager != null:
			var plots: Array = manager.call("get_plots_in_radius", target_position, 1.75)
			for plot in plots:
				if plot is FarmTile:
					return plot
	var origin := _vector3_from_value(tool_request.get("origin", state.get("position", Vector3.ZERO)))
	var direction := _vector3_from_value(tool_request.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		direction = Vector3.FORWARD
	var hit := _raycast_world(origin, origin + direction * 80.0)
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null:
		var resolved_tile: FarmTile = manager.call("resolve_hit_tile", hit) as FarmTile
		if resolved_tile != null:
			return resolved_tile
	var hit_position := _vector3_from_value(hit.get("position", Vector3.ZERO))
	if hit_position != Vector3.ZERO:
		var nearest := _nearest_farm_tile(hit_position, 2.0)
		if nearest != null:
			return nearest
	return _nearest_farm_tile_along_segment(origin, origin + direction * 12.0, 1.8)


func _project_position_to_ground(from_position: Vector3, fallback: Vector3) -> Vector3:
	var hit := _raycast_world(from_position, from_position + Vector3.DOWN * 8.0)
	if hit.has("position"):
		return _vector3_from_value(hit.get("position", fallback))
	return fallback


func _nearest_farm_tile(world_position: Vector3, radius: float) -> FarmTile:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null or not manager.has_method("get_plots_in_radius"):
		return null
	var plots: Array = manager.call("get_plots_in_radius", world_position, radius)
	var best: FarmTile = null
	var best_distance := INF
	for plot in plots:
		if not plot is FarmTile:
			continue
		var distance := (plot as FarmTile).global_position.distance_squared_to(world_position)
		if distance < best_distance:
			best_distance = distance
			best = plot
	return best


func _nearest_farm_tile_along_segment(start: Vector3, end: Vector3, radius: float) -> FarmTile:
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager == null or not manager.has_method("get_all_plots"):
		return null
	var plots: Array = manager.call("get_all_plots")
	var segment := end - start
	var len_sq := segment.length_squared()
	if len_sq <= 0.0001:
		return null
	var best: FarmTile = null
	var best_t := INF
	for plot in plots:
		if not plot is FarmTile:
			continue
		var tile := plot as FarmTile
		var pos := tile.global_position
		var t := clampf((pos - start).dot(segment) / len_sq, 0.0, 1.0)
		var closest := start + segment * t
		if closest.distance_to(pos) <= radius and t < best_t:
			best_t = t
			best = tile
	return best


func _raycast_world(
	origin: Vector3,
	end: Vector3,
	collision_mask := DEFAULT_COMBAT_RAYCAST_MASK,
	exclude: Array[RID] = []
) -> Dictionary:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return {}
	var world := tree.root.get_world_3d()
	if world == null:
		return {}
	var query := PhysicsRayQueryParameters3D.create(origin, end)
	query.collision_mask = collision_mask
	query.exclude = exclude
	query.collide_with_areas = true
	query.collide_with_bodies = true
	return world.direct_space_state.intersect_ray(query)


func _can_server_interact_with_position(state: Dictionary, target_position: Vector3, max_distance: float) -> bool:
	var player_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	var horizontal_offset := target_position - player_position
	horizontal_offset.y = 0.0
	var distance := horizontal_offset.length()
	if distance > max_distance:
		return false
	if distance > 0.001:
		var forward := -Basis(Vector3.UP, float(state.get("yaw", 0.0))).z
		forward.y = 0.0
		if forward.normalized().dot(horizontal_offset / distance) < PLAYER_INTERACTION_MIN_FORWARD_DOT:
			return false
	var hit := _raycast_world(
		player_position + Vector3.UP * 1.2,
		target_position + Vector3.UP * 0.5,
		COLLISION_LAYER_WALL,
		_player_raycast_exclusion(int(state.get("peer_id", 0)))
	)
	return hit.is_empty()


func _player_raycast_exclusion(peer_id: int) -> Array[RID]:
	var exclude: Array[RID] = []
	var proxy: Node = player_physics_nodes.get(peer_id, null)
	if is_instance_valid(proxy) and proxy is CollisionObject3D:
		exclude.append((proxy as CollisionObject3D).get_rid())
	return exclude


func _valid_hitscan_player_target(
	candidate_peer_id: int,
	shooter_peer_id: int,
	shooter_team: String,
	include_same_team := false
) -> int:
	if candidate_peer_id == 0 or candidate_peer_id == shooter_peer_id:
		return 0
	if not player_states.has(candidate_peer_id):
		return 0
	var candidate_state: Dictionary = player_states[candidate_peer_id]
	if float(candidate_state.get("respawn_left", 0.0)) > 0.0:
		return 0
	if not include_same_team and not shooter_team.is_empty() and str(candidate_state.get("team", "")) == shooter_team:
		return 0
	return candidate_peer_id


func _find_player_hit_by_segment(
	shooter_peer_id: int,
	shooter_team: String,
	start: Vector3,
	end: Vector3,
	radius: float,
	include_same_team := false
) -> int:
	var best_peer_id := 0
	var best_t := INF
	var segment := end - start
	var len_sq := segment.length_squared()
	if len_sq <= 0.0001:
		return 0
	for raw_peer_id in player_states.keys():
		var peer_id := int(raw_peer_id)
		if peer_id == shooter_peer_id:
			continue
		var state: Dictionary = player_states[peer_id]
		if float(state.get("respawn_left", 0.0)) > 0.0:
			continue
		if not include_same_team and not shooter_team.is_empty() and str(state.get("team", "")) == shooter_team:
			continue
		var pos := _vector3_from_value(state.get("position", Vector3.ZERO)) + Vector3.UP
		var t := clampf((pos - start).dot(segment) / len_sq, 0.0, 1.0)
		var closest := start + segment * t
		if closest.distance_to(pos) <= radius and t < best_t:
			best_t = t
			best_peer_id = peer_id
	return best_peer_id


func _damage_player(
	peer_id: int,
	damage: float,
	knockback: float,
	direction: Vector3,
	attacker_team: String,
	effect: String,
	attacker_peer_id := 0
) -> bool:
	if not player_states.has(peer_id):
		return false
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return false
	if not attacker_team.is_empty() and str(state.get("team", "")) == attacker_team:
		return false
	var incoming_damage := maxf(0.0, damage)
	var armor_result := _absorb_player_damage_with_equipment(state, incoming_damage)
	var absorbed_damage := float(armor_result.get("absorbed_damage", 0.0))
	var health_damage := float(armor_result.get("remaining_damage", incoming_damage))
	var previous_hp := float(state.get("hp", PLAYER_MAX_HP))
	var hp := maxf(0.0, previous_hp - health_damage)
	var knockback_velocity := _vector3_from_value(state.get("knockback_velocity", Vector3.ZERO))
	if knockback > 0.0 and direction.length_squared() > 0.001:
		var horizontal_direction := Vector3(direction.x, 0.0, direction.z).normalized()
		knockback_velocity += horizontal_direction * knockback
	state["hp"] = hp
	state["knockback_velocity"] = knockback_velocity
	if effect.strip_edges().to_lower() in ["labeled", "labelled"]:
		state["labeled_remaining"] = maxf(
			float(state.get("labeled_remaining", 0.0)),
			CombatBalance.get_float("small_mouse", "labeled_duration")
		)
	player_states[peer_id] = state
	if hp <= 0.0:
		var resolved_attacker_peer_id := resolve_attacker_peer_id(attacker_team, attacker_peer_id)
		if previous_hp > 0.0 and resolved_attacker_peer_id != peer_id \
				and player_states.has(resolved_attacker_peer_id):
			var killer_team := str((player_states[resolved_attacker_peer_id] as Dictionary).get("team", ""))
			var victim_team := str(state.get("team", ""))
			if not killer_team.is_empty() and killer_team != victim_team:
				award_action_reward(
					resolved_attacker_peer_id,
					CombatBalance.get_int("team_rewards", "enemy_player_kill", 200),
					"击杀对方玩家"
				)
		elif previous_hp > 0.0 and not attacker_team.is_empty() \
				and attacker_team != str(state.get("team", "")):
			_award_team_combat_reward_without_player(
				attacker_team,
				CombatBalance.get_int("team_rewards", "enemy_player_kill", 200),
				"击杀对方玩家"
			)
		_begin_player_respawn(peer_id)
	reliable_world_event_ready.emit({
		"type": "player_damaged",
		"peer_id": peer_id,
		"damage": health_damage,
		"incoming_damage": incoming_damage,
		"absorbed_damage": absorbed_damage,
		"chest_armor": armor_result.get("chest_armor", {}),
		"legwear": armor_result.get("legwear", {}),
		"hp": hp,
		"knockback": knockback,
		"direction": direction,
		"effect": effect,
		"tick": server_tick,
	})
	return incoming_damage > 0.0 and (absorbed_damage > 0.0 or hp < previous_hp)


func _absorb_player_damage_with_equipment(state: Dictionary, damage: float) -> Dictionary:
	var result := {
		"remaining_damage": maxf(0.0, damage),
		"absorbed_damage": 0.0,
		"chest_armor": {},
		"legwear": {},
	}
	if damage <= 0.0:
		return result
	var chest_id := str(state.get("equipped_chest_armor_id", ""))
	var legwear_id := str(state.get("equipped_legwear_id", ""))
	var chest_definition := EquipmentCatalog.get_definition(chest_id)
	var legwear_definition := EquipmentCatalog.get_definition(legwear_id)
	var chest_max_hp := EquipmentCatalog.get_max_hp(chest_id)
	var legwear_max_hp := EquipmentCatalog.get_max_hp(legwear_id)
	var equipment_hp: Dictionary = (state.get("equipment_hp", {}) as Dictionary).duplicate(true)
	var chest_hp := clampf(float(equipment_hp.get(chest_id, chest_max_hp)), 0.0, chest_max_hp)
	var legwear_hp := clampf(float(equipment_hp.get(legwear_id, legwear_max_hp)), 0.0, legwear_max_hp)
	var chest_active := not chest_id.is_empty() \
		and str(chest_definition.get("equipment_type", "")) == "chest_armor" \
		and chest_max_hp > 0.0 and chest_hp > 0.0
	var legwear_active := not legwear_id.is_empty() \
		and str(legwear_definition.get("equipment_type", "")) == "legwear" \
		and legwear_max_hp > 0.0 and legwear_hp > 0.0
	if not chest_active and not legwear_active:
		if not chest_id.is_empty():
			result["chest_armor"] = _server_equipment_item(state, chest_id)
		if not legwear_id.is_empty():
			result["legwear"] = _server_equipment_item(state, legwear_id)
		return result
	var chest_allocation := 0.0
	var legwear_allocation := 0.0
	if chest_active and legwear_active:
		chest_allocation = float(roundi(damage * 2.0 / 3.0))
		legwear_allocation = maxf(0.0, damage - chest_allocation)
	elif chest_active:
		chest_allocation = damage
	else:
		legwear_allocation = damage
	var chest_absorbed := minf(chest_hp, chest_allocation)
	var legwear_absorbed := minf(legwear_hp, legwear_allocation)
	if chest_active:
		equipment_hp[chest_id] = maxf(0.0, chest_hp - chest_absorbed)
	if legwear_active:
		equipment_hp[legwear_id] = maxf(0.0, legwear_hp - legwear_absorbed)
	state["equipment_hp"] = equipment_hp
	var absorbed := chest_absorbed + legwear_absorbed
	result["remaining_damage"] = maxf(0.0, damage - absorbed)
	result["absorbed_damage"] = absorbed
	if not chest_id.is_empty():
		result["chest_armor"] = _server_equipment_item(state, chest_id)
	if not legwear_id.is_empty():
		result["legwear"] = _server_equipment_item(state, legwear_id)
	return result


func _emit_hit_confirmed(attacker_peer_id: int, target_count: int, total_damage: float, source: String) -> void:
	if attacker_peer_id <= 0 or target_count <= 0 or total_damage <= 0.0:
		return
	var confirmation_id := next_hit_confirmation_id
	next_hit_confirmation_id += 1
	reliable_world_event_ready.emit({
		"type": "hit_confirmed",
		"confirmation_id": confirmation_id,
		"attacker_peer_id": attacker_peer_id,
		"target_count": target_count,
		"total_damage": total_damage,
		"source": source,
		"tick": server_tick,
	})


func award_action_reward(peer_id: int, amount: int, description: String) -> bool:
	if peer_id <= 0 or amount <= 0 or not player_states.has(peer_id) \
			or (not is_server_authority() and not is_local_authority()):
		return false
	var team := str((player_states[peer_id] as Dictionary).get("team", ""))
	if team.is_empty() or not GlobalVar.add_team_reward(team, float(amount)):
		return false
	GlobalVar.add_match_stat(team, _match_stat_category_for_action(description), amount)
	reliable_world_event_ready.emit({
		"type": "action_reward",
		"peer_id": peer_id,
		"team": team,
		"amount": amount,
		"description": description,
		"tick": server_tick,
	})
	return true


func award_future_warrior_defeat(attacker_team: String, defender_team: String) -> void:
	award_team_ai_defeat(attacker_team, defender_team, "Future Warrior")


func award_team_ai_defeat(attacker_team: String, defender_team: String, display_name: String) -> void:
	if attacker_team.is_empty() or attacker_team == defender_team \
			or (not is_server_authority() and not is_local_authority()):
		return
	var amount := CombatBalance.get_int("team_rewards", "enemy_player_kill", 200)
	var attacker_peer_id := resolve_attacker_peer_id(attacker_team)
	if attacker_peer_id > 0:
		award_action_reward(attacker_peer_id, amount, "击杀敌方 %s" % display_name)
	else:
		_award_team_combat_reward_without_player(attacker_team, amount, "击杀敌方 %s" % display_name)


func _award_team_combat_reward_without_player(team: String, amount: int, description: String) -> bool:
	if team.is_empty() or amount <= 0 or not GlobalVar.add_team_reward(team, float(amount)):
		return false
	GlobalVar.add_match_stat(team, "combat", amount)
	return true


func _match_stat_category_for_action(description: String) -> String:
	if description.contains("黑熊") or description.contains("击杀") or description.contains("摧毁"):
		return "combat"
	if description.contains("收割") or description.contains("砍伐"):
		return "agriculture_livestock"
	if description.contains("矿"):
		return "mining"
	if description.contains("成品菜") or description.contains("料理"):
		return "cooking"
	return "combat"


func get_authoritative_player_position(peer_id: int) -> Variant:
	if not player_states.has(peer_id):
		return null
	if is_local_authority():
		for node in get_tree().get_nodes_in_group("human_players"):
			if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
					and int((node as GamePlayer).authority_peer_id) == peer_id:
				return (node as GamePlayer).global_position
	var proxy: Node = player_physics_nodes.get(peer_id, null)
	if is_instance_valid(proxy) and proxy is Node3D:
		return (proxy as Node3D).global_position
	var position_value: Variant = (player_states[peer_id] as Dictionary).get("position", null)
	return position_value if position_value is Vector3 else null


func damage_player_from_wild_animal(
	peer_id: int,
	animal_position: Vector3,
	damage: float,
	max_range: float,
	direction: Vector3
) -> bool:
	if not (is_server_authority() or is_local_authority()):
		return false
	if not player_states.has(peer_id):
		return false
	var state: Dictionary = player_states[peer_id]
	if float(state.get("hp", 0.0)) <= 0.0 or float(state.get("respawn_left", 0.0)) > 0.0:
		return false
	var target_position_value: Variant = get_authoritative_player_position(peer_id)
	if not target_position_value is Vector3:
		return false
	var target_position := target_position_value as Vector3
	var horizontal_distance := Vector2(animal_position.x, animal_position.z).distance_to(
		Vector2(target_position.x, target_position.z)
	)
	var melee_tolerance := 0.2
	if horizontal_distance > maxf(0.0, max_range) + melee_tolerance:
		return false
	return _damage_player(peer_id, damage, 0.0, direction, "", "wild_animal")


func award_completed_dish_collection(peer_id: int, dish_id: String) -> bool:
	if dish_id in ["burnt_plate", "ruined_soup"] \
			or DishCatalog.get_definition(dish_id).is_empty():
		return false
	return award_action_reward(
		peer_id,
		CombatBalance.get_int("team_rewards", "completed_dish_collected", 100),
		"领取成品菜"
	)


func resolve_attacker_peer_id(attacker_team: String, preferred_peer_id := 0) -> int:
	if preferred_peer_id > 0 and player_states.has(preferred_peer_id):
		var preferred_team := str((player_states[preferred_peer_id] as Dictionary).get("team", ""))
		if attacker_team.is_empty() or preferred_team == attacker_team:
			return preferred_peer_id
	if is_local_authority() and not attacker_team.is_empty():
		for value: Variant in player_states.keys():
			var candidate_peer_id := int(value)
			if str((player_states[candidate_peer_id] as Dictionary).get("team", "")) == attacker_team:
				return candidate_peer_id
	return 0


func show_local_hit_marker_for_team(attacker_team: String) -> void:
	if not is_local_authority() or attacker_team.is_empty():
		return
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and str((node as GamePlayer).team) == attacker_team:
			(node as GamePlayer).show_hit_marker()
			return


func _begin_player_respawn(peer_id: int) -> void:
	if not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	_force_release_kitchen_user(peer_id)
	_destroy_rift_anchor_for_peer(peer_id)
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return
		release_big_mouth_capture(peer_id, "player_died")
	state = player_states.get(peer_id, state)
	_remove_player_from_vehicle(peer_id, true)
	state = player_states.get(peer_id, {})
	_destroy_owned_remote_devices_for_player(peer_id)
	# Do not carry a pre-death movement frame into the first live authority tick.
	latest_inputs.erase(peer_id)
	var death_drop_mode := _get_death_drop_mode()
	var dropped_inventory_items := _drop_player_inventory_on_death(peer_id, state, death_drop_mode)
	state["hp"] = 0.0
	state["velocity"] = Vector3.ZERO
	state["knockback_velocity"] = Vector3.ZERO
	state["spicy_remaining"] = 0.0
	state["spicy_dps"] = 0.0
	state["labeled_remaining"] = 0.0
	state["respawn_left"] = PLAYER_RESPAWN_SECONDS
	player_states[peer_id] = state
	var proxy: Node = player_physics_nodes.get(peer_id, null)
	if is_instance_valid(proxy) and proxy is CollisionObject3D:
		(proxy as CollisionObject3D).collision_layer = 0
		(proxy as CollisionObject3D).collision_mask = 0
	if mode == MODE_LOCAL:
		_apply_local_player_death_inventory(peer_id, dropped_inventory_items)
		_apply_local_player_respawn_state(peer_id, PLAYER_RESPAWN_SECONDS)
	reliable_world_event_ready.emit({
		"type": "player_died",
		"peer_id": peer_id,
		"respawn_seconds": PLAYER_RESPAWN_SECONDS,
		"death_drop_mode": death_drop_mode,
		"dropped_inventory_items": dropped_inventory_items,
		"tick": server_tick,
	})


func _get_death_drop_mode() -> String:
	if server_manager != null and server_manager.has_method("get_death_drop_mode"):
		var configured_mode := str(server_manager.call("get_death_drop_mode")).to_lower()
		if configured_mode == "all" or configured_mode == "random" or configured_mode == "save":
			return configured_mode
	return "save"


func _drop_player_inventory_on_death(peer_id: int, state: Dictionary, drop_mode: String) -> Array[Dictionary]:
	if drop_mode == "save":
		return []
	var candidates := _select_death_drop_candidates(state, drop_mode)
	if candidates.is_empty():
		return []
	var dropped: Array[Dictionary] = []
	var layout_value: Variant = state.get("backpack_slot_items", [])
	var layout: Array = (layout_value as Array).duplicate(true) if layout_value is Array else []
	for candidate: Dictionary in candidates:
		var equipped_type := str(candidate.get("equipped_type", ""))
		var equipment_state_key := _equipment_state_key(equipped_type)
		var equipped_id := str(state.get(equipment_state_key, "")) if not equipment_state_key.is_empty() else ""
		if not equipment_state_key.is_empty():
			state[equipment_state_key] = ""
		var item := _consume_dropped_item_from_player(state, candidate)
		if item.is_empty():
			if not equipment_state_key.is_empty():
				state[equipment_state_key] = equipped_id
			continue
		if not equipment_state_key.is_empty():
			item["was_equipped"] = true
			item["equipment_type"] = equipped_type
		var angle := randf_range(0.0, TAU)
		var direction := Vector3(cos(angle), randf_range(0.08, 0.28), sin(angle)).normalized()
		var item_state := _make_dropped_item_state(peer_id, item, state, direction)
		if item_state.is_empty() or not _spawn_authoritative_dropped_item(item_state):
			_restore_dropped_item_to_player(state, item)
			if not equipment_state_key.is_empty():
				state[equipment_state_key] = equipped_id
			continue
		var slot_index := int(candidate.get("slot_index", -1))
		if slot_index >= 0 and slot_index < layout.size():
			layout[slot_index] = {}
		dropped.append(item.duplicate(true))
		reliable_world_event_ready.emit({
			"type": "dropped_item_spawned",
			"item_state": item_state,
			"tick": server_tick,
		})
	var next_capacity := _server_bag_capacity(state)
	if layout.size() > next_capacity:
		layout.resize(next_capacity)
	state["backpack_slot_items"] = layout
	state["backpack_layout_valid"] = true
	_clear_invalid_current_selection(state, layout)
	return dropped


func _select_death_drop_candidates(state: Dictionary, drop_mode: String) -> Array[Dictionary]:
	var candidate_groups := _get_slotted_death_drop_candidates(state)
	var base_candidates: Array[Dictionary] = candidate_groups.get("base", [])
	var extension_candidates: Array[Dictionary] = candidate_groups.get("extension", [])
	var equipped_candidates := _get_equipped_death_drop_candidates(state)
	var candidates: Array[Dictionary] = []
	if not bool(candidate_groups.get("valid", false)):
		base_candidates = _get_player_drop_candidates(state)
		if drop_mode == "random" and str(state.get("equipped_backpack_id", "")).is_empty() and not base_candidates.is_empty():
			base_candidates.shuffle()
			base_candidates.resize(randi_range(1, base_candidates.size()))
		candidates.append_array(base_candidates)
	elif drop_mode == "random":
		if not base_candidates.is_empty():
			base_candidates.shuffle()
			base_candidates.resize(randi_range(1, base_candidates.size()))
		candidates.append_array(base_candidates)
		# Equipped items always drop in random mode. If that includes a backpack,
		# every slot provided by that backpack is also mandatory.
		if not str(state.get("equipped_backpack_id", "")).is_empty():
			candidates.append_array(extension_candidates)
	else:
		candidates.append_array(base_candidates)
		candidates.append_array(extension_candidates)
	candidates.append_array(equipped_candidates)
	return candidates


func _get_slotted_death_drop_candidates(state: Dictionary) -> Dictionary:
	var base: Array[Dictionary] = []
	var extension: Array[Dictionary] = []
	var slots_value: Variant = state.get("backpack_slot_items", [])
	if not bool(state.get("backpack_layout_valid", false)) \
			or not slots_value is Array or (slots_value as Array).size() != _server_bag_capacity(state):
		return {"valid": false, "base": base, "extension": extension}
	var slots := slots_value as Array
	for index in range(slots.size()):
		var item_value: Variant = slots[index]
		if not item_value is Dictionary or (item_value as Dictionary).is_empty():
			continue
		var candidate := (item_value as Dictionary).duplicate(true)
		candidate["slot_index"] = index
		if index < BASE_PLAYER_BAG_SLOTS:
			base.append(candidate)
		else:
			extension.append(candidate)
	return {"valid": true, "base": base, "extension": extension}


func _get_equipped_death_drop_candidates(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for equipment_type in ["backpack", "chest_armor", "legwear"]:
		var state_key := _equipment_state_key(equipment_type)
		var equipment_id := str(state.get(state_key, ""))
		if not equipment_id.is_empty():
			result.append({
				"kind": "equipment",
				"equipment_id": equipment_id,
				"equipped_type": equipment_type,
			})
	return result


func _get_player_drop_candidates(state: Dictionary) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for bucket in ["primary_weapon_ids", "special_tool_ids"]:
		var ids_value: Variant = state.get(bucket, [])
		if ids_value is Array:
			for tool_id_value: Variant in ids_value:
				var tool_id := str(tool_id_value)
				if not tool_id.is_empty():
					candidates.append({"kind": "tool", "tool_id": tool_id})
	var equipment_ids: Variant = state.get("owned_equipment_ids", [])
	if equipment_ids is Array:
		for equipment_id_value: Variant in equipment_ids:
			var equipment_id := str(equipment_id_value)
			if not equipment_id.is_empty() and not _is_equipment_equipped(state, equipment_id):
				candidates.append({"kind": "equipment", "equipment_id": equipment_id})
	var ingredient_values: Variant = state.get("personal_ingredients", {})
	if ingredient_values is Dictionary:
		for key_value: Variant in (ingredient_values as Dictionary).keys():
			var key := str(key_value)
			var weight_kg := float((ingredient_values as Dictionary).get(key_value, 0.0))
			var ingredient_id := key.trim_suffix("|chopped").trim_suffix("|whole")
			if not ingredient_id.is_empty() and weight_kg > 0.0:
				candidates.append({
					"kind": "ingredient",
					"ingredient_id": ingredient_id,
					"weight_kg": weight_kg,
					"is_chopped": key.ends_with("|chopped"),
				})
	var dish_values: Variant = state.get("personal_dishes", {})
	var dish_weights: Variant = state.get("personal_dish_weights", {})
	if dish_values is Dictionary and dish_weights is Dictionary:
		for dish_id_value: Variant in (dish_values as Dictionary).keys():
			var dish_id := str(dish_id_value)
			var servings := int((dish_values as Dictionary).get(dish_id_value, 0))
			var weight_kg := float((dish_weights as Dictionary).get(dish_id_value, 0.0))
			if not dish_id.is_empty() and servings > 0 and weight_kg > 0.0:
				candidates.append({"kind": "dish", "dish_id": dish_id, "servings": servings, "weight_kg": weight_kg})
	return candidates


func _apply_local_player_death_inventory(peer_id: int, dropped_items: Array[Dictionary]) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and not (node as GamePlayer).is_remote_proxy \
				and int((node as GamePlayer).authority_peer_id) == peer_id:
			(node as GamePlayer).apply_death_inventory_drop(dropped_items)
			return


func _remove_player_from_vehicle(peer_id: int, notify_player: bool) -> void:
	if not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	var vehicle_id := str(state.get("vehicle_id", ""))
	if vehicle_id.is_empty():
		return
	var vehicle := _find_vehicle(vehicle_id)
	var seat_index := int(state.get("vehicle_seat_index", -1))
	var exit_position := _vector3_from_value(state.get("position", Vector3.ZERO))
	if vehicle != null:
		seat_index = vehicle.exit_seat(peer_id)
		exit_position = vehicle.get_exit_position(seat_index)
		if vehicle.driver_peer_id == 0:
			vehicle.set_drive_input(0.0, 0.0, 1.0)
	state["vehicle_id"] = ""
	state["vehicle_seat_index"] = -1
	state["position"] = exit_position
	state["velocity"] = Vector3.ZERO
	player_states[peer_id] = state
	_set_server_player_vehicle_collision(peer_id, false, exit_position)
	if notify_player:
		var session_result := {
			"ok": true,
			"peer_id": peer_id,
			"vehicle_id": vehicle_id,
			"connected": false,
			"seat_index": seat_index,
			"exit_position": exit_position,
		}
		_apply_local_player_vehicle_session(session_result)
		reliable_world_event_ready.emit({
			"type": "vehicle_session",
			"data": session_result,
			"tick": server_tick,
		})


func _destroy_owned_remote_devices_for_player(peer_id: int) -> void:
	var device_ids: Array[String] = []
	for raw_device_id in remote_device_states.keys():
		var device_id := str(raw_device_id)
		var device: Dictionary = remote_device_states[device_id]
		if int(device.get("owner_peer_id", 0)) == peer_id:
			device_ids.append(device_id)
	for device_id in device_ids:
		if not remote_device_states.has(device_id):
			continue
		var device: Dictionary = remote_device_states[device_id]
		var controller_peer_id := int(device.get("controller_peer_id", 0))
		if controller_peer_id != 0:
			device["controller_peer_id"] = 0
			device["input"] = {}
			remote_device_states[device_id] = device
			_emit_remote_control_session_event(device, controller_peer_id, false, true, "owner_respawning")
		_destroy_registered_tool_ref({"kind": "remote", "id": device_id})


func _respawn_player(peer_id: int) -> void:
	if not player_states.has(peer_id):
		return
	var state: Dictionary = player_states[peer_id]
	var spawn_position := _vector3_from_value(
		state.get("spawn_position", state.get("position", Vector3.ZERO))
	)
	state["position"] = spawn_position
	state["velocity"] = Vector3.ZERO
	state["knockback_velocity"] = Vector3.ZERO
	state["hp"] = PLAYER_MAX_HP
	state["respawn_left"] = 0.0
	state["grounded"] = true
	state["locomotion_state"] = "idle"
	player_states[peer_id] = state
	var proxy: Node = player_physics_nodes.get(peer_id, null)
	if is_instance_valid(proxy) and proxy is CharacterBody3D:
		var body := proxy as CharacterBody3D
		_set_server_player_prone_collision(body, false)
		body.global_position = spawn_position
		body.velocity = Vector3.ZERO
		body.collision_layer = COLLISION_LAYER_CHARACTER
		body.collision_mask = DEFAULT_COMBAT_RAYCAST_MASK
	if mode == MODE_LOCAL:
		_apply_local_player_respawn_state(peer_id, 0.0, spawn_position)
	reliable_world_event_ready.emit({
		"type": "player_respawned",
		"peer_id": peer_id,
		"position": spawn_position,
		"tick": server_tick,
	})


func _apply_local_player_respawn_state(peer_id: int, respawn_left: float, spawn_position: Variant = null) -> void:
	for node in get_tree().get_nodes_in_group("human_players"):
		if node is GamePlayer and int(node.authority_peer_id) == peer_id:
			node.call("apply_respawn_state", respawn_left, spawn_position)
			break


func _heal_player(peer_id: int, amount: float, healer_peer_id: int) -> void:
	if not player_states.has(peer_id) or amount <= 0.0:
		return
	var state: Dictionary = player_states[peer_id]
	if float(state.get("respawn_left", 0.0)) > 0.0:
		return
	var old_hp := float(state.get("hp", PLAYER_MAX_HP))
	var hp := minf(PLAYER_MAX_HP, old_hp + amount)
	state["hp"] = hp
	player_states[peer_id] = state
	if mode == MODE_LOCAL:
		for node in get_tree().get_nodes_in_group("human_players"):
			if node is GamePlayer and int(node.authority_peer_id) == peer_id:
				node.set("server_hp", hp)
				node.call("_update_health_ui")
				break
	reliable_world_event_ready.emit({
		"type": "player_healed",
		"peer_id": peer_id,
		"healer_peer_id": healer_peer_id,
		"healing": hp - old_hp,
		"hp": hp,
		"tick": server_tick,
	})


func _apply_hit_to_collider(
	collider,
	effect: String,
	damage: float,
	attacker_team: String,
	shape_index: int = -1,
	attacker_peer_id := 0
) -> bool:
	if collider == null or not is_instance_valid(collider):
		return false
	var manager := get_node_or_null("/root/Farmlandmanager")
	if manager != null:
		var farm_tile: FarmTile = manager.call("resolve_farm_tile", collider, shape_index) as FarmTile
		if farm_tile != null:
			farm_tile.impact(effect, damage, attacker_team)
			return false
	var node = collider
	while node != null:
		if node is FutureWarriorAI:
			return bool((node as FutureWarriorAI).impact(effect, damage, attacker_team))
		if node is FarmerAI:
			return bool((node as FarmerAI).impact(effect, damage, attacker_team))
		if node is AssistantAI:
			return bool((node as AssistantAI).impact(effect, damage, attacker_team))
		if node is AINormalDrone:
			return bool((node as AINormalDrone).impact(effect, damage, attacker_team))
		if node is VehicleBase:
			return _damage_vehicle(node as VehicleBase, damage, effect, attacker_team)
		var tool_ref := _registered_tool_ref_for_node(node)
		if not tool_ref.is_empty():
			return _damage_registered_tool_ref(tool_ref, damage, effect, attacker_team)
		if attacker_peer_id > 0 and node.has_method("impact_from_peer"):
			return bool(node.call("impact_from_peer", effect, damage, attacker_team, attacker_peer_id))
		if node.has_method("impact"):
			return bool(node.call("impact", effect, damage, attacker_team))
		node = node.get_parent() if node is Node else null
	return false


func _damage_future_warriors_in_radius(
	center: Vector3,
	radius: float,
	damage: float,
	attacker_team: String,
	effect: String,
	linear_falloff := false,
	friendly_fire := false
) -> Dictionary:
	var result := {"count": 0, "total_damage": 0.0}
	for node in get_tree().get_nodes_in_group("future_warrior_ai"):
		if not node is FutureWarriorAI or not is_instance_valid(node):
			continue
		var warrior := node as FutureWarriorAI
		if int(warrior.state) == FutureWarriorAI.AIState.DEAD:
			continue
		if not friendly_fire and not attacker_team.is_empty() and warrior.team_id == attacker_team:
			continue
		var distance := warrior.global_position.distance_to(center)
		if distance > radius:
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, warrior.global_position + Vector3.UP * 0.85, warrior)
		var applied_damage := maxf(0.0, damage * ratio * occlusion)
		if applied_damage <= 0.0:
			continue
		var direction := warrior.global_position - center
		if warrior.impact(effect, applied_damage, attacker_team, direction):
			result["count"] = int(result["count"]) + 1
			result["total_damage"] = float(result["total_damage"]) + applied_damage
	return result


func _damage_farmer_ais_in_radius(
	center: Vector3,
	radius: float,
	damage: float,
	attacker_team: String,
	effect: String,
	linear_falloff := false,
	friendly_fire := false
) -> Dictionary:
	var result := {"count": 0, "total_damage": 0.0}
	for node in get_tree().get_nodes_in_group("farmer_ai"):
		if not node is FarmerAI or not is_instance_valid(node):
			continue
		var farmer := node as FarmerAI
		if int(farmer.state) == FarmerAI.AIState.DEAD:
			continue
		if not friendly_fire and not attacker_team.is_empty() and farmer.team_id == attacker_team:
			continue
		var distance := farmer.global_position.distance_to(center)
		if distance > radius:
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, farmer.global_position + Vector3.UP * 0.85, farmer)
		var applied_damage := maxf(0.0, damage * ratio * occlusion)
		if applied_damage <= 0.0:
			continue
		var direction := farmer.global_position - center
		if farmer.impact(effect, applied_damage, attacker_team, direction):
			result["count"] = int(result["count"]) + 1
			result["total_damage"] = float(result["total_damage"]) + applied_damage
	return result


func _damage_assistant_ai_in_radius(center: Vector3, radius: float, damage: float, attacker_team: String, effect: String, linear_falloff := false, friendly_fire := false) -> Dictionary:
	return _damage_group_nodes_in_radius("assistant_ai", center, radius, damage, attacker_team, effect, linear_falloff, friendly_fire)


func _damage_ai_normal_drones_in_radius(center: Vector3, radius: float, damage: float, attacker_team: String, effect: String, linear_falloff := false, friendly_fire := false) -> Dictionary:
	return _damage_group_nodes_in_radius("ai_normal_drones", center, radius, damage, attacker_team, effect, linear_falloff, friendly_fire)


func _damage_group_nodes_in_radius(group_name: String, center: Vector3, radius: float, damage: float, attacker_team: String, effect: String, linear_falloff: bool, friendly_fire: bool) -> Dictionary:
	var result := {"count": 0, "total_damage": 0.0}
	for node in get_tree().get_nodes_in_group(group_name):
		if not node is Node3D or not is_instance_valid(node):
			continue
		var target := node as Node3D
		var target_team := str(target.call("get_combat_team")) if target.has_method("get_combat_team") else ""
		if not friendly_fire and not attacker_team.is_empty() and target_team == attacker_team:
			continue
		var distance := target.global_position.distance_to(center)
		if distance > radius:
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var applied := maxf(0.0, damage * ratio * _explosion_damage_multiplier(center, target.global_position + Vector3.UP, target))
		if applied > 0.0 and target.has_method("impact") and bool(target.call("impact", effect, applied, attacker_team)):
			result["count"] = int(result["count"]) + 1
			result["total_damage"] = float(result["total_damage"]) + applied
	return result


func _tool_max_hp(tool_name: String) -> float:
	match tool_name:
		"HarvestTree", "harvest_tree", "Oak", "Redcedar", "CottonWood":
			return 500.0
		"ShieldDoor", "shield_door":
			return CombatBalance.get_tool_max_hp("shield_door")
		"Brick", "brick":
			return CombatBalance.get_tool_max_hp("brick")
		"AutoShooter", "auto_shooter":
			return CombatBalance.get_tool_max_hp("auto_shooter")
		"WheatSentry", "wheat_sentry":
			return CombatBalance.get_tool_max_hp("wheat_sentry")
		"AntiAir", "anti_air":
			return CombatBalance.get_tool_max_hp("anti_air")
		"AreaProtector", "area_protector":
			return CombatBalance.get_tool_max_hp("area_protector")
		"FarmRunner", "farm_runner":
			return CombatBalance.get_tool_max_hp("farm_runner")
		"PlantProtector", "plant_protector":
			return CombatBalance.get_tool_max_hp("plant_protector")
		"SignalJam", "signal_jam", "SignalAugment", "signal_augment":
			return CombatBalance.get_tool_max_hp("signal_jam" if tool_name.to_lower().contains("jam") else "signal_augment")
		"normal_drone", "NormalDrone", "action_drone", "ActionDrone":
			return CombatBalance.get_tool_max_hp("normal_drone")
		"tech_drone", "TechDrone":
			return CombatBalance.get_tool_max_hp("tech_drone")
		"boom_buggy", "BoomBuggy":
			return CombatBalance.get_tool_max_hp("boom_buggy")
		"small_mouse", "SmallMouse":
			return CombatBalance.get_tool_max_hp("small_mouse")
		"auto_cooker", "AutoCooker":
			return CombatBalance.get_tool_max_hp("auto_cooker")
		"big_mouth", "BigMouth":
			return CombatBalance.get_tool_max_hp("big_mouth")
		"fake_player", "FakePlayer":
			return CombatBalance.get_tool_max_hp("fake_player")
		"rift_anchor", "RiftAnchor":
			return CombatBalance.get_tool_max_hp("rift_anchor")
		_:
			return CombatBalance.get_tool_max_hp("default")


func _registered_tool_ref_for_node(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	var node_path := str(node.get_path())
	for raw_id in placed_tool_states.keys():
		var id := str(raw_id)
		var state: Dictionary = placed_tool_states[id]
		var path := str(state.get("path", id))
		if node_path == path or node_path.begins_with(path + "/"):
			return {"kind": "placed", "id": id}
	for raw_id in remote_device_states.keys():
		var id := str(raw_id)
		var state: Dictionary = remote_device_states[id]
		var path := str(state.get("device_path", id))
		if node_path == path or node_path.begins_with(path + "/"):
			return {"kind": "remote", "id": id}
	return {}


func _node_has_property(node: Variant, property_name: String) -> bool:
	if not node is Object or not is_instance_valid(node):
		return false
	for info in (node as Object).get_property_list():
		if str((info as Dictionary).get("name", "")) == property_name:
			return true
	return false


func _node_float_property(node: Variant, property_name: String, fallback: float) -> float:
	if not _node_has_property(node, property_name):
		return fallback
	var value = (node as Object).get(property_name)
	if value == null:
		return fallback
	return float(value)


func _configured_tool_int(node: Variant, property_name: String, fallback: int) -> int:
	return int(roundi(_configured_tool_float(node, property_name, float(fallback))))


func _configured_tool_float(node: Variant, property_name: String, fallback: float) -> float:
	return _node_float_property(node, property_name, fallback)


func _gameplay_tool_node(node: Variant) -> Node:
	if not node is Node or not is_instance_valid(node):
		return null
	if node is FarmTile:
		var tool_child := (node as FarmTile).tool_child
		return tool_child if is_instance_valid(tool_child) else null
	return node as Node


func _configured_tool_hp(tool_name: String, node: Node) -> float:
	var fallback := _tool_max_hp(tool_name)
	var gameplay_node := _gameplay_tool_node(node)
	for property_name in ["max_hp", "current_hp", "set_hp", "SET_HP"]:
		if _node_has_property(gameplay_node, property_name):
			return maxf(0.0, _node_float_property(gameplay_node, property_name, fallback))
	return fallback


func _state_dictionary_for_tool_ref(tool_ref: Dictionary) -> Dictionary:
	var kind := str(tool_ref.get("kind", ""))
	var id := str(tool_ref.get("id", ""))
	if kind == "placed":
		return placed_tool_states.get(id, {})
	if kind == "remote":
		return remote_device_states.get(id, {})
	return {}


func _registered_tool_ref_by_id(id: String) -> Dictionary:
	if placed_tool_states.has(id):
		return {"kind": "placed", "id": id}
	if remote_device_states.has(id):
		return {"kind": "remote", "id": id}
	return {}


func _node_for_tool_ref(tool_ref: Dictionary):
	var state := _state_dictionary_for_tool_ref(tool_ref)
	var path := str(state.get("path", state.get("device_path", state.get("tool_id", state.get("device_id", "")))))
	if path.is_empty():
		return null
	return get_node_or_null(NodePath(path))


func _damage_registered_tool_ref(tool_ref: Dictionary, damage: float, effect: String, attacker_team: String) -> bool:
	if damage <= 0.0:
		return false
	var kind := str(tool_ref.get("kind", ""))
	var id := str(tool_ref.get("id", ""))
	if id.is_empty():
		return false
	var state := _state_dictionary_for_tool_ref(tool_ref)
	if state.is_empty():
		return false
	var team := str(state.get("team", ""))
	var is_enemy_tool := not attacker_team.is_empty() and not team.is_empty() and team != attacker_team
	if not attacker_team.is_empty() and team == attacker_team:
		return false
	var node = _node_for_tool_ref(tool_ref)
	var before_hp := float(state.get("hp", _tool_max_hp(str(state.get("tool_name", state.get("device_type", ""))))))
	if node != null and is_instance_valid(node) and node.has_method("impact"):
		node.call("impact", effect, damage, attacker_team)
	var after_hp := before_hp - damage
	if node != null and is_instance_valid(node):
		if node is FarmTile:
			var tile := node as FarmTile
			if is_instance_valid(tile.tool_child):
				after_hp = _node_float_property(tile.tool_child, "current_hp", after_hp)
			else:
				after_hp = 0.0
		else:
			after_hp = _node_float_property(node, "current_hp", after_hp)
	else:
		after_hp = 0.0
	state["hp"] = maxf(0.0, after_hp)
	if kind == "remote" and float(state["hp"]) < before_hp:
		reliable_world_event_ready.emit({
			"type": "remote_device_damaged",
			"device_id": id,
			"controller_peer_id": int(state.get("controller_peer_id", 0)),
			"damage": before_hp - float(state["hp"]),
			"hp": float(state["hp"]),
			"tick": server_tick,
		})
	if state["hp"] <= 0.0:
		_destroy_registered_tool_ref(tool_ref)
		return is_enemy_tool and before_hp > 0.0
	if kind == "placed":
		placed_tool_states[id] = state
	elif kind == "remote":
		remote_device_states[id] = state
	return is_enemy_tool and float(state.get("hp", before_hp)) < before_hp


func _destroy_registered_tool_ref(tool_ref: Dictionary) -> void:
	var kind := str(tool_ref.get("kind", ""))
	var id := str(tool_ref.get("id", ""))
	var state := _state_dictionary_for_tool_ref(tool_ref)
	if str(state.get("device_type", state.get("tool_name", ""))).to_lower() == "big_mouth":
		release_big_mouth_captures_for_device(id, "destroyed")
	var node = _node_for_tool_ref(tool_ref)
	if node != null and is_instance_valid(node):
		if node is FarmTile:
			(node as FarmTile).apply_authoritative_tool_destroyed()
		else:
			node.queue_free()
	if kind == "placed":
		placed_tool_states.erase(id)
		remote_device_states.erase(id)
	elif kind == "remote":
		remote_device_states.erase(id)
		placed_tool_states.erase(id)
	var event_device_id := str(state.get("device_id", ""))
	if event_device_id.is_empty():
		event_device_id = id
	reliable_world_event_ready.emit({
		"type": "tool_destroyed",
		"kind": kind,
		"id": id,
		"tile_path": str(state.get("path", "")) if kind == "placed" and not bool(state.get("free_placement", false)) else "",
		"device_id": event_device_id,
		"position": state.get("position", Vector3.ZERO),
		"tick": server_tick,
	})


func _damage_tools_in_radius(center: Vector3, radius: float, damage: float, attacker_team: String, effect: String, linear_falloff := false) -> int:
	if radius <= 0.0 or damage <= 0.0:
		return 0
	var touched_paths := {}
	var damaged_count := 0
	for raw_id in placed_tool_states.keys():
		var id := str(raw_id)
		if not placed_tool_states.has(id):
			continue
		var state: Dictionary = placed_tool_states[id]
		var pos := _vector3_from_value(state.get("position", Vector3.ZERO))
		var dist := pos.distance_to(center)
		if dist > radius:
			continue
		var ratio := maxf(0.0, 1.0 - dist / radius) if linear_falloff else 1.0 - (dist / radius) * 0.5
		var ref := {"kind": "placed", "id": id}
		var node = _node_for_tool_ref(ref)
		var occlusion := _explosion_damage_multiplier(
			center,
			pos + Vector3.UP * 0.5,
			node
		)
		if _damage_registered_tool_ref(ref, damage * ratio * occlusion, effect, attacker_team):
			damaged_count += 1
		touched_paths[str(state.get("path", id))] = true
	for raw_id in remote_device_states.keys():
		var id := str(raw_id)
		if not remote_device_states.has(id):
			continue
		var state: Dictionary = remote_device_states[id]
		var path := str(state.get("device_path", id))
		if touched_paths.has(path):
			continue
		var pos := _vector3_from_value(state.get("position", Vector3.ZERO))
		var dist := pos.distance_to(center)
		if dist > radius:
			continue
		var ratio := maxf(0.0, 1.0 - dist / radius) if linear_falloff else 1.0 - (dist / radius) * 0.5
		var ref := {"kind": "remote", "id": id}
		var node = _node_for_tool_ref(ref)
		var occlusion := _explosion_damage_multiplier(
			center,
			pos + Vector3.UP * 0.5,
			node
		)
		if _damage_registered_tool_ref(ref, damage * ratio * occlusion, effect, attacker_team):
			damaged_count += 1
	return damaged_count


func _damage_harvest_trees_in_radius(
	center: Vector3, radius: float, damage: float, attacker_team: String,
	effect: String, linear_falloff := false, attacker_peer_id := 0
) -> int:
	var damaged_count := 0
	for node in get_tree().get_nodes_in_group("harvest_trees"):
		if not node is HarvestTree or not is_instance_valid(node):
			continue
		var tree := node as HarvestTree
		if tree.destroyed or tree.global_position.distance_to(center) > radius:
			continue
		var distance := tree.global_position.distance_to(center)
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, tree.global_position + Vector3.UP, tree) if linear_falloff else 1.0
		var applied := tree.impact_from_peer(
			effect, damage * ratio * occlusion, attacker_team, attacker_peer_id
		) if attacker_peer_id > 0 else tree.impact(
			effect, damage * ratio * occlusion, attacker_team
		)
		if applied:
			damaged_count += 1
	return damaged_count


func _damage_nature_resources_in_radius(
	center: Vector3, radius: float, damage: float, attacker_team: String,
	effect: String, linear_falloff := false, attacker_peer_id := 0
) -> int:
	var damaged_count := 0
	for node in get_tree().get_nodes_in_group("nature_resources"):
		if not node is Node3D or not is_instance_valid(node) or node is HarvestTree:
			continue
		var resource := node as Node3D
		var distance := resource.global_position.distance_to(center)
		if distance > radius or not resource.has_method("impact"):
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, resource.global_position + Vector3.UP * 0.5, resource) if linear_falloff else 1.0
		var applied := bool(resource.call(
			"impact_from_peer", effect, damage * ratio * occlusion, attacker_team, attacker_peer_id
		)) if attacker_peer_id > 0 and resource.has_method("impact_from_peer") else bool(
			resource.call("impact", effect, damage * ratio * occlusion, attacker_team)
		)
		if applied:
			damaged_count += 1
	return damaged_count


func _damage_wild_animals_in_radius(
	center: Vector3,
	radius: float,
	damage: float,
	knockback: float,
	attacker_team: String,
	effect: String,
	linear_falloff := false,
	attacker_peer_id := 0
) -> int:
	var damaged_count := 0
	for node in get_tree().get_nodes_in_group("wild_animals"):
		if not node is Node3D or not is_instance_valid(node) or not node.has_method("impact"):
			continue
		var animal := node as Node3D
		var distance := animal.global_position.distance_to(center)
		if distance > radius:
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, animal.global_position + Vector3.UP * 0.8, animal)
		var applied := bool(animal.call(
			"impact_from_peer", effect, damage * ratio * occlusion, attacker_team, attacker_peer_id
		)) if attacker_peer_id > 0 and animal.has_method("impact_from_peer") else bool(
			animal.call("impact", effect, damage * ratio * occlusion, attacker_team)
		)
		if applied:
			var direction := animal.global_position - center
			_apply_wild_animal_knockback(animal, direction, knockback * ratio * occlusion)
			damaged_count += 1
	return damaged_count


func _apply_wild_animal_knockback(collider: Variant, direction: Vector3, strength: float) -> void:
	if strength <= 0.0:
		return
	var animal := _wild_animal_for_collider(collider)
	if animal != null and animal.has_method("apply_knockback"):
		animal.call("apply_knockback", direction, strength)


func _wild_animal_for_collider(collider: Variant) -> Node:
	if not collider is Node:
		return null
	var cursor := collider as Node
	while cursor != null:
		if cursor.is_in_group("wild_animals"):
			return cursor
		cursor = cursor.get_parent()
	return null


func _vehicle_team(vehicle: VehicleBase) -> String:
	if vehicle == null or not is_instance_valid(vehicle):
		return ""
	var state: Dictionary = vehicle_states.get(vehicle.get_vehicle_id(), {})
	var vehicle_team := str(state.get("owner_team", vehicle.owner_team))
	if not vehicle_team.is_empty():
		return vehicle_team
	var driver_peer_id := int(state.get("driver_peer_id", vehicle.driver_peer_id))
	if driver_peer_id > 0 and player_states.has(driver_peer_id):
		return str((player_states[driver_peer_id] as Dictionary).get("team", ""))
	return ""


func _vehicle_for_collider(collider: Variant) -> VehicleBase:
	var node := collider as Node
	while node != null:
		if node is VehicleBase:
			return node as VehicleBase
		node = node.get_parent()
	return null


func _apply_vehicle_shield_laser_hit(projectile: Dictionary, hit: Dictionary) -> bool:
	var vehicle := _vehicle_for_collider(hit.get("collider", null))
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	var source_team := str(projectile.get("team", ""))
	if source_team.is_empty() or _vehicle_team(vehicle) != source_team:
		return false
	var duration := CombatBalance.get_float("vehicle_shield_shooter", "shield_duration", 30.0)
	var max_hp := CombatBalance.get_float("vehicle_shield_shooter", "shield_hp", 2000.0)
	if not vehicle.apply_vehicle_shield(duration, max_hp):
		return false
	var vehicle_id := vehicle.get_vehicle_id()
	var vehicle_state: Dictionary = vehicle_states.get(vehicle_id, {})
	vehicle_state.merge(vehicle.get_network_state(), true)
	vehicle_state["vehicle_id"] = vehicle_id
	vehicle_states[vehicle_id] = vehicle_state
	reliable_world_event_ready.emit({
		"type": "vehicle_shield_applied",
		"vehicle_id": vehicle_id,
		"shield_remaining": vehicle.shield_remaining,
		"shield_hp": vehicle.shield_hp,
		"shield_max_hp": vehicle.shield_max_hp,
		"tick": server_tick,
	})
	return true


func notify_vehicle_damaged(vehicle: VehicleBase, damage: float) -> void:
	if vehicle == null or not is_instance_valid(vehicle) or damage <= 0.0 \
			or (not is_server_authority() and not is_local_authority()):
		return
	var occupant_peer_ids: Array[int] = []
	for peer_id_value: Variant in vehicle.seat_occupants.values():
		var peer_id := int(peer_id_value)
		if peer_id > 0 and not occupant_peer_ids.has(peer_id):
			occupant_peer_ids.append(peer_id)
	reliable_world_event_ready.emit({
		"type": "vehicle_damaged",
		"vehicle_id": vehicle.get_vehicle_id(),
		"occupant_peer_ids": occupant_peer_ids,
		"damage": damage,
		"hp": vehicle.current_hp,
		"tick": server_tick,
	})


func _damage_vehicle(vehicle: VehicleBase, damage: float, effect: String, attacker_team: String) -> bool:
	if vehicle == null or not is_instance_valid(vehicle) or damage <= 0.0:
		return false
	var target_team := _vehicle_team(vehicle)
	var is_enemy_vehicle := not attacker_team.is_empty() and not target_team.is_empty() \
		and target_team != attacker_team
	var damage_applied := vehicle.impact(effect, damage, attacker_team)
	return damage_applied and is_enemy_vehicle


func _damage_vehicles_in_radius(center: Vector3, radius: float, damage: float, attacker_team: String, effect: String, linear_falloff := false) -> int:
	if radius <= 0.0 or damage <= 0.0:
		return 0
	var damaged_count := 0
	for node in get_tree().get_nodes_in_group("vehicle_bases"):
		if not node is VehicleBase:
			continue
		var vehicle := node as VehicleBase
		var distance := vehicle.global_position.distance_to(center)
		if distance > radius:
			continue
		var ratio := maxf(0.0, 1.0 - distance / radius) if linear_falloff else 1.0 - (distance / radius) * 0.5
		var occlusion := _explosion_damage_multiplier(center, vehicle.global_position + Vector3.UP, vehicle)
		if _damage_vehicle(vehicle, damage * ratio * occlusion, effect, attacker_team):
			damaged_count += 1
	return damaged_count


func _explosion_damage_multiplier(
	explosion_position: Vector3,
	target_position: Vector3,
	target_node: Node = null
) -> float:
	var origin := explosion_position + Vector3.UP * 0.35
	var hit := _raycast_world(origin, target_position, EXPLOSION_OCCLUSION_MASK)
	if hit.is_empty():
		return 1.0
	var collider: Variant = hit.get("collider", null)
	if _collider_belongs_to_target(collider, target_node):
		return 1.0
	if _collider_collision_layer(collider) & COLLISION_LAYER_TOOL:
		return EXPLOSION_TOOL_DAMAGE_MULTIPLIER
	return EXPLOSION_WALL_DAMAGE_MULTIPLIER


func _collider_belongs_to_target(collider: Variant, target_node: Node) -> bool:
	if target_node == null or not collider is Node:
		return false
	var cursor := collider as Node
	while cursor != null:
		if cursor == target_node:
			return true
		cursor = cursor.get_parent()
	return false


func _collider_collision_layer(collider: Variant) -> int:
	if not collider is Node:
		return 0
	var cursor := collider as Node
	while cursor != null:
		if cursor is CollisionObject3D:
			return (cursor as CollisionObject3D).collision_layer
		cursor = cursor.get_parent()
	return 0


func _apply_remote_action_gameplay(peer_id: int, action: Dictionary, result: Dictionary) -> void:
	if not bool(result.get("ok", false)):
		return
	var device_type := str(result.get("device_type", ""))
	var action_name := str(action.get("action", ""))
	var position := _vector3_from_value(result.get("position", Vector3.ZERO))
	var device_node := _gameplay_tool_node(_node_for_tool_ref({
		"kind": "remote",
		"id": str(result.get("device_id", "")),
	}))
	if device_type == "normal_drone" and action_name == "primary":
		_spawn_server_projectile(peer_id, {
			"origin": position,
			"direction": Vector3.DOWN,
		}, "drone_bomb",
			_configured_tool_float(device_node, "bomb_initial_down_speed", CombatBalance.get_float("normal_drone", "bomb_speed")),
			_configured_tool_float(device_node, "bomb_damage", CombatBalance.get_float("normal_drone", "bomb_damage")),
			_configured_tool_float(device_node, "bomb_explosion_radius", CombatBalance.get_float("normal_drone", "bomb_radius")),
			"Explosion")
	elif device_type == "boom_buggy" and action_name == "primary":
		var projectile_id := next_projectile_id
		next_projectile_id += 1
		projectile_states[projectile_id] = {
			"projectile_id": projectile_id,
			"type": "boom_buggy_explosion",
			"team": result.get("team", ""),
			"owner_peer_id": peer_id,
			"position": position,
			"velocity": Vector3.ZERO,
			"damage": _configured_tool_float(device_node, "explosion_strength", CombatBalance.get_float("boom_buggy", "damage")),
			"radius": _configured_tool_float(device_node, "explosion_radius", CombatBalance.get_float("boom_buggy", "radius")),
			"effect": "Explosion",
			"show_owner_hit_marker": true,
			"life": 0.0,
			"max_life": 0.0,
		}
		_explode_projectile(projectile_id, position)
		projectile_states.erase(projectile_id)
	elif device_type == "small_mouse" and action_name == "primary":
		# The client aims from ActionMount toward the center-screen ray target.
		# Use the same authoritative mount here so the damage ray and visible
		# laser share the exact origin instead of gaining a vertical offset.
		var action_mount := device_node.get_node_or_null("ActionMount") as Node3D if device_node != null else null
		var laser_origin := action_mount.global_position if is_instance_valid(action_mount) else position + Vector3.UP * 0.3
		var laser_direction := _vector3_from_value(action.get("direction", Vector3.FORWARD)).normalized()
		# Remote player proxies are visual-only on clients, so their colliders do
		# not participate in the client camera ray. Resolve that center-screen ray
		# on the authoritative physics world, then converge from ActionMount.
		var aim_origin := _vector3_from_value(action.get("aim_origin", laser_origin))
		var aim_direction := _vector3_from_value(action.get("aim_direction", Vector3.ZERO)).normalized()
		if aim_direction.length_squared() > 0.001 and aim_origin.distance_to(laser_origin) <= 3.0:
			var aim_hit := _raycast_world(aim_origin, aim_origin + aim_direction * _configured_tool_float(device_node, "primary_action_range", CombatBalance.get_float("small_mouse", "range")))
			var aim_point := _vector3_from_value(aim_hit.get("position", aim_origin + aim_direction * _configured_tool_float(device_node, "primary_action_range", CombatBalance.get_float("small_mouse", "range"))))
			var mount_direction := (aim_point - laser_origin).normalized()
			if mount_direction.length_squared() > 0.001:
				laser_direction = mount_direction
		var data := _server_hitscan(peer_id, {
			"origin": laser_origin,
			"direction": laser_direction,
		},
			_configured_tool_float(device_node, "primary_action_range", CombatBalance.get_float("small_mouse", "range")),
			_configured_tool_float(device_node, "primary_action_damage", CombatBalance.get_float("small_mouse", "damage")),
			0.0,
			"labeled")
		var laser_lifetime := 1.0
		if str(data.get("hit_kind", "none")) != "none":
			var impact_position := _vector3_from_value(data.get("hit_position", laser_origin))
			laser_lifetime = minf(
				laser_lifetime,
					maxf(0.01, laser_origin.distance_to(impact_position) / _configured_tool_float(device_node, "primary_action_visual_speed", CombatBalance.get_float("small_mouse", "visual_speed")))
			)
		_emit_visual_projectile(
			peer_id,
			"detect_laser_bullet",
			laser_origin,
			laser_direction,
			_configured_tool_float(device_node, "primary_action_visual_speed", CombatBalance.get_float("small_mouse", "visual_speed")),
			laser_lifetime,
			"labeled",
			true
		)
	elif device_type == "tech_drone" and action_name == "primary":
		_apply_tech_drone_repair_pulse(peer_id, result, device_node, action)


func _tech_drone_electronic_type_key(value: String) -> String:
	match value.to_lower().replace("_", ""):
		"antiair":
			return "anti_air"
		"autoshooter":
			return "auto_shooter"
		"wheatsentry":
			return "wheat_sentry"
		"signaljam":
			return "signal_jam"
		"signalaugment":
			return "signal_augment"
		"normaldrone":
			return "normal_drone"
		"techdrone":
			return "tech_drone"
		"smallmouse":
			return "small_mouse"
		"boombuggy":
			return "boom_buggy"
	return value.to_lower()


func _is_tech_drone_electronic_device(device_type: String) -> bool:
	return _tech_drone_electronic_type_key(device_type) in [
		"anti_air", "auto_shooter", "wheat_sentry", "signal_jam",
		"signal_augment", "normal_drone", "tech_drone", "small_mouse",
		"boom_buggy", "farm_runner", "plant_protector",
	]


func _is_tech_drone_emp_target(device_type: String) -> bool:
	# Restrict EMP to equipment which already has a Lightning shutdown path.
	return _tech_drone_electronic_type_key(device_type) in [
		"anti_air", "auto_shooter", "signal_jam", "signal_augment",
		"normal_drone", "tech_drone", "small_mouse", "boom_buggy",
		"wheat_sentry", "farm_runner", "plant_protector",
	]


func _tool_ref_for_collider(collider: Variant) -> Dictionary:
	var node := collider as Node
	while node != null:
		var tool_ref := _registered_tool_ref_for_node(node)
		if not tool_ref.is_empty():
			return tool_ref
		node = node.get_parent()
	return {}


func _repair_registered_tool_ref(tool_ref: Dictionary, amount: float) -> void:
	var kind := str(tool_ref.get("kind", ""))
	var id := str(tool_ref.get("id", ""))
	var state := _state_dictionary_for_tool_ref(tool_ref)
	if id.is_empty() or state.is_empty():
		return
	var type_name := _tech_drone_electronic_type_key(
		str(state.get("tool_name", state.get("device_type", "")))
	)
	if not _is_tech_drone_electronic_device(type_name):
		return
	var max_hp := float(state.get("max_hp", _tool_max_hp(type_name)))
	var repaired_hp := minf(max_hp, float(state.get("hp", max_hp)) + maxf(0.0, amount))
	state["hp"] = repaired_hp
	var node := _gameplay_tool_node(_node_for_tool_ref(tool_ref))
	if node != null:
		if _node_has_property(node, "current_hp"):
			node.set("current_hp", repaired_hp)
		if node.has_method("apply_network_health"):
			node.call("apply_network_health", repaired_hp)
	if kind == "placed":
		placed_tool_states[id] = state
	elif kind == "remote":
		remote_device_states[id] = state


func _apply_tech_drone_repair_pulse(
	peer_id: int,
	result: Dictionary,
	device_node: Node,
	action: Dictionary
) -> void:
	var action_point := device_node.get_node_or_null("ActionPoint") as Node3D if device_node != null else null
	var origin := action_point.global_position if is_instance_valid(action_point) else _vector3_from_value(result.get("position", Vector3.ZERO))
	var direction := _vector3_from_value(action.get("direction", Vector3.FORWARD)).normalized()
	if direction.length_squared() <= 0.001:
		return
	var range := _configured_tool_float(device_node, "repair_pulse_range", CombatBalance.get_float("tech_drone", "repair_range"))
	var visual_speed := _configured_tool_float(device_node, "repair_pulse_visual_speed", CombatBalance.get_float("tech_drone", "visual_speed"))
	var hit := _raycast_world(origin, origin + direction * range)
	var hit_position := _vector3_from_value(hit.get("position", origin + direction * range))
	var actor_team := str(result.get("team", ""))
	if hit.has("collider"):
		var tool_ref := _tool_ref_for_collider(hit.get("collider"))
		if not tool_ref.is_empty():
			var state := _state_dictionary_for_tool_ref(tool_ref)
			var target_type := _tech_drone_electronic_type_key(
				str(state.get("tool_name", state.get("device_type", "")))
			)
			if str(state.get("team", "")) == actor_team:
				_repair_registered_tool_ref(
					tool_ref,
					CombatBalance.get_float("tech_drone", "repair_amount")
				)
			elif _is_tech_drone_emp_target(target_type):
				var target := _gameplay_tool_node(_node_for_tool_ref(tool_ref))
				if target != null and target.has_method("impact"):
					target.call("impact", "repair_laser", 0.0, actor_team)
		elif hit.get("collider") is Node:
			var cursor := hit.get("collider") as Node
			while cursor != null:
				if cursor is AINormalDrone:
					var ai_drone := cursor as AINormalDrone
					if ai_drone.team_id != actor_team:
						ai_drone.impact("repair_laser", 0.0, actor_team)
					break
				cursor = cursor.get_parent()
	var lifetime := maxf(0.01, origin.distance_to(hit_position) / maxf(visual_speed, 0.01))
	_emit_visual_projectile(peer_id, "repair_laser", origin, direction, visual_speed, lifetime, "repair_laser", true)


func _farm_tile_from_action(action: Dictionary) -> FarmTile:
	var tile_path := str(action.get("tile_path", ""))
	if not tile_path.is_empty():
		var node := get_node_or_null(NodePath(tile_path))
		if node is FarmTile:
			return node
	var position_value: Variant = action.get("tile_position", action.get("position", null))
	if position_value is Vector3:
		var position := position_value as Vector3
		var manager := get_node_or_null("/root/Farmlandmanager")
		if manager != null:
			var plots: Array = manager.call("get_plots_in_radius", position, 1.5)
			for plot in plots:
				if plot is FarmTile:
					return plot
	return null


func _ingredient_pickup_from_action(action: Dictionary) -> IngredientPickup:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is IngredientPickup:
			return node as IngredientPickup
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: IngredientPickup = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("ingredient_pickups"):
			if node is IngredientPickup:
				var distance := (node as IngredientPickup).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best_distance = distance
					best = node as IngredientPickup
		return best
	return null


func _livestock_chop_from_action(action: Dictionary) -> LivestockChop:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is LivestockChop:
			return node as LivestockChop
	var position_value: Variant = action.get("station_position", null)
	if position_value is Vector3:
		var best: LivestockChop = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("livestock_chops"):
			if node is LivestockChop:
				var distance := (node as LivestockChop).global_position.distance_squared_to(position_value as Vector3)
				if distance < best_distance:
					best = node as LivestockChop
					best_distance = distance
		return best
	return null


func _livestock_market_from_transaction(transaction: Dictionary) -> LivestockMarket:
	var market_path := str(transaction.get("shop_path", ""))
	if not market_path.is_empty():
		var path_node := get_node_or_null(NodePath(market_path))
		if path_node is LivestockMarket:
			return path_node as LivestockMarket
	var position_value: Variant = transaction.get("shop_position", null)
	if position_value is Vector3:
		var best: LivestockMarket = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("livestock_markets"):
			if node is LivestockMarket:
				var distance := (node as LivestockMarket).global_position.distance_squared_to(
					position_value as Vector3
				)
				if distance < best_distance:
					best = node as LivestockMarket
					best_distance = distance
		return best
	return null


func _chopping_station_from_action(action: Dictionary) -> ChoppingStation:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is ChoppingStation:
			return node as ChoppingStation
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: ChoppingStation = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("chopping_stations"):
			if node is ChoppingStation:
				var distance := (node as ChoppingStation).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as ChoppingStation
					best_distance = distance
		return best
	return null


func _plating_station_from_action(action: Dictionary) -> PlatingStation:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is PlatingStation:
			return node as PlatingStation
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: PlatingStation = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("plating_stations"):
			if node is PlatingStation:
				var distance := (node as PlatingStation).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as PlatingStation
					best_distance = distance
		return best
	return null


func _oven_from_action(action: Dictionary) -> Oven:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is Oven:
			return node as Oven
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: Oven = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("oven_stations"):
			if node is Oven:
				var distance := (node as Oven).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as Oven
					best_distance = distance
		return best
	return null


func _recipe_cooking_station_from_action(action: Dictionary, group_name: String) -> RecipeCookingStation:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is RecipeCookingStation and node.is_in_group(group_name):
			return node as RecipeCookingStation
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: RecipeCookingStation = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group(group_name):
			if node is RecipeCookingStation:
				var distance := (node as RecipeCookingStation).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as RecipeCookingStation
					best_distance = distance
		return best
	return null


func _ingredient_extractor_from_action(action: Dictionary) -> IngredientExtractor:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is IngredientExtractor:
			return node as IngredientExtractor
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: IngredientExtractor = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("ingredient_extractors"):
			if node is IngredientExtractor:
				var distance := (node as IngredientExtractor).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as IngredientExtractor
					best_distance = distance
		return best
	return null


func _stand_mixer_from_action(action: Dictionary) -> StandMixer:
	var station_path := str(action.get("station_path", ""))
	if not station_path.is_empty():
		var node := get_node_or_null(NodePath(station_path))
		if node is StandMixer:
			return node as StandMixer
	var station_position: Variant = action.get("station_position", null)
	if station_position is Vector3:
		var best: StandMixer = null
		var best_distance := INF
		for node in get_tree().get_nodes_in_group("stand_mixers"):
			if node is StandMixer:
				var distance := (node as StandMixer).global_position.distance_squared_to(station_position as Vector3)
				if distance < best_distance:
					best = node as StandMixer
					best_distance = distance
		return best
	return null


func _auto_cooker_from_action(action: Dictionary) -> AutoCooker:
	var station_path := str(action.get("station_path", ""))
	var node := get_node_or_null(NodePath(station_path)) if not station_path.is_empty() else null
	if node is AutoCooker: return node as AutoCooker
	var position: Variant = action.get("station_position", null)
	if position is Vector3:
		for candidate in get_tree().get_nodes_in_group("auto_cookers"):
			if candidate is AutoCooker and (candidate as AutoCooker).global_position.distance_squared_to(position as Vector3) < 0.25:
				return candidate as AutoCooker
	return null


func _ingredient_from_selection_id(selection_id: String) -> Dictionary:
	if not selection_id.begins_with(HANDHELD_INGREDIENT_PREFIX):
		return {}
	var parts := selection_id.split(":", false)
	if parts.size() != 3 or parts[1].is_empty() or IngredientCatalog.get_definition(parts[1]).is_empty():
		return {}
	return {"ingredient_id": parts[1], "is_chopped": parts[2] == "chopped"}


func _dish_from_selection_id(selection_id: String) -> String:
	if not selection_id.begins_with("dish:"):
		return ""
	var dish_id := selection_id.trim_prefix("dish:")
	return dish_id if not DishCatalog.get_definition(dish_id).is_empty() else ""


func _personal_ingredient_key(ingredient_id: String, is_chopped: bool) -> String:
	return ingredient_id + ("|chopped" if is_chopped else "|whole")


func _personal_ingredient_total_weight(state: Dictionary) -> float:
	var values: Variant = state.get("personal_ingredients", {})
	if not values is Dictionary:
		return 0.0
	var total := 0.0
	for weight in (values as Dictionary).values():
		total += maxf(0.0, float(weight))
	var dishes: Variant = state.get("personal_dishes", {})
	var dish_weights: Variant = state.get("personal_dish_weights", {})
	if dishes is Dictionary:
		for dish_id_value in (dishes as Dictionary).keys():
			var dish_id := str(dish_id_value)
			var servings := int((dishes as Dictionary).get(dish_id, 0))
			var stored_weight := float((dish_weights as Dictionary).get(dish_id, -1.0)) if dish_weights is Dictionary else -1.0
			total += maxf(0.0, stored_weight if stored_weight >= 0.0 else DishCatalog.get_definition(dish_id).get("serving_weight_kg", 0.0) * float(servings))
	var cargo_crates: Variant = state.get("personal_cargo_crates", [])
	if cargo_crates is Array:
		for crate_value: Variant in cargo_crates:
			if crate_value is Dictionary:
				total += maxf(0.0, float((crate_value as Dictionary).get("total_weight_kg", 0.0)))
	var slots_value: Variant = state.get("backpack_slot_items", [])
	if slots_value is Array:
		for item_value: Variant in slots_value:
			if item_value is Dictionary and str((item_value as Dictionary).get("kind", "")) in ["tool", "weapon"]:
				total += maxf(0.0, float((item_value as Dictionary).get("weight_kg", 0.0)))
	return total


func _server_has_personal_ingredient(state: Dictionary, ingredient_id: String, weight_kg: float, is_chopped: bool) -> bool:
	var values: Variant = state.get("personal_ingredients", {})
	return values is Dictionary and float((values as Dictionary).get(_personal_ingredient_key(ingredient_id, is_chopped), 0.0)) + 0.001 >= weight_kg


func _server_start_selected_recipe(state: Dictionary, team: String, station: RecipeCookingStation, recipe_id: String) -> Dictionary:
	if not station.can_start_selected_recipe(recipe_id):
		return {"ok": false, "reason": "invalid_recipe_for_station"}
	var deductions: Array[Dictionary] = []
	var personal_values: Variant = state.get("personal_ingredients", {})
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(recipe_id):
		var ingredient_id := str(ingredient.get("ingredient_id", ""))
		var is_chopped := bool(ingredient.get("is_chopped", false))
		var required_weight := float(ingredient.get("weight_kg", 0.0))
		var personal_available := 0.0
		if personal_values is Dictionary:
			personal_available = float((personal_values as Dictionary).get(_personal_ingredient_key(ingredient_id, is_chopped), 0.0))
		var personal_weight := minf(required_weight, personal_available)
		var team_weight := maxf(0.0, required_weight - personal_weight)
		if GlobalVar.check_team_item_amount(team, ingredient_id) + 0.001 < team_weight:
			return {"ok": false, "reason": "ingredients_unavailable"}
		deductions.append({
			"ingredient_id": ingredient_id,
			"is_chopped": is_chopped,
			"personal_weight_kg": personal_weight,
			"team_weight_kg": team_weight,
		})
	var consumed_personal: Array[Dictionary] = []
	for deduction: Dictionary in deductions:
		var ingredient_id := str(deduction.get("ingredient_id", ""))
		var is_chopped := bool(deduction.get("is_chopped", false))
		var personal_weight := float(deduction.get("personal_weight_kg", 0.0))
		var team_weight := float(deduction.get("team_weight_kg", 0.0))
		if personal_weight > 0.0001:
			_server_remove_personal_ingredient(state, ingredient_id, personal_weight, is_chopped)
			consumed_personal.append({"ingredient_id": ingredient_id, "is_chopped": is_chopped, "weight_kg": personal_weight})
		if team_weight > 0.0001:
			GlobalVar.remove_item(team, ingredient_id, team_weight)
	if not station.start_selected_recipe(recipe_id):
		for deduction: Dictionary in deductions:
			var ingredient_id := str(deduction.get("ingredient_id", ""))
			var is_chopped := bool(deduction.get("is_chopped", false))
			var personal_weight := float(deduction.get("personal_weight_kg", 0.0))
			var team_weight := float(deduction.get("team_weight_kg", 0.0))
			if personal_weight > 0.0001:
				_server_add_personal_ingredient(state, ingredient_id, personal_weight, is_chopped)
			if team_weight > 0.0001:
				GlobalVar.add_item(team, ingredient_id, team_weight)
		return {"ok": false, "reason": "station_rejected_recipe"}
	return {"ok": true, "recipe_id": recipe_id, "consumed_personal_ingredients": consumed_personal}


func _server_can_add_personal_ingredient(state: Dictionary, ingredient_id: String, weight_kg: float, is_chopped: bool) -> bool:
	if ingredient_id.is_empty() or weight_kg <= 0.0 \
			or _personal_ingredient_total_weight(state) + weight_kg > _server_bag_weight_capacity_kg(state) + 0.001:
		return false
	var values: Variant = state.get("personal_ingredients", {})
	var key := _personal_ingredient_key(ingredient_id, is_chopped)
	return (values is Dictionary and float((values as Dictionary).get(key, 0.0)) > 0.0001) \
		or _server_backpack_entry_count(state) < _server_bag_capacity(state)


func _server_add_personal_ingredient(state: Dictionary, ingredient_id: String, weight_kg: float, is_chopped: bool) -> void:
	var values: Dictionary = (state.get("personal_ingredients", {}) as Dictionary).duplicate(true)
	var key := _personal_ingredient_key(ingredient_id, is_chopped)
	values[key] = float(values.get(key, 0.0)) + weight_kg
	state["personal_ingredients"] = values
	_server_layout_add_item(state, {"kind": "ingredient", "ingredient_id": ingredient_id, "weight_kg": weight_kg, "is_chopped": is_chopped})


func _server_remove_personal_ingredient(state: Dictionary, ingredient_id: String, weight_kg: float, is_chopped: bool) -> bool:
	if not _server_has_personal_ingredient(state, ingredient_id, weight_kg, is_chopped):
		return false
	var values: Dictionary = (state.get("personal_ingredients", {}) as Dictionary).duplicate(true)
	var key := _personal_ingredient_key(ingredient_id, is_chopped)
	var remaining := float(values.get(key, 0.0)) - weight_kg
	if remaining <= 0.001:
		values.erase(key)
	else:
		values[key] = remaining
	state["personal_ingredients"] = values
	_server_layout_remove_item(state, {"kind": "ingredient", "ingredient_id": ingredient_id, "weight_kg": weight_kg, "is_chopped": is_chopped})
	return true


func _server_has_personal_dish(state: Dictionary, dish_id: String) -> bool:
	var values: Variant = state.get("personal_dishes", {})
	return values is Dictionary and int((values as Dictionary).get(dish_id, 0)) > 0


func _server_remove_personal_dish(state: Dictionary, dish_id: String, servings: int, weight_kg: float) -> bool:
	if dish_id.is_empty() or servings <= 0 or weight_kg <= 0.0:
		return false
	var values: Dictionary = (state.get("personal_dishes", {}) as Dictionary).duplicate(true)
	var weights: Dictionary = (state.get("personal_dish_weights", {}) as Dictionary).duplicate(true)
	var held_servings := int(values.get(dish_id, 0))
	var held_weight := float(weights.get(dish_id, 0.0))
	if held_servings < servings or held_weight + 0.001 < weight_kg:
		return false
	var remaining_servings := held_servings - servings
	var remaining_weight := maxf(0.0, held_weight - weight_kg)
	if remaining_servings <= 0 or remaining_weight <= 0.001:
		values.erase(dish_id)
		weights.erase(dish_id)
	else:
		values[dish_id] = remaining_servings
		weights[dish_id] = remaining_weight
	state["personal_dishes"] = values
	state["personal_dish_weights"] = weights
	_server_layout_remove_item(state, {"kind": "dish", "dish_id": dish_id, "servings": servings, "weight_kg": weight_kg})
	return true


func _server_add_personal_dish(state: Dictionary, dish_id: String, servings: int, weight_kg := -1.0) -> void:
	var definition := DishCatalog.get_definition(dish_id)
	var added_weight := weight_kg if weight_kg > 0.0 else float(definition.get("serving_weight_kg", 0.0)) * float(servings)
	if definition.is_empty() or servings <= 0 or added_weight <= 0.0:
		return
	var values: Dictionary = (state.get("personal_dishes", {}) as Dictionary).duplicate(true)
	var weights: Dictionary = (state.get("personal_dish_weights", {}) as Dictionary).duplicate(true)
	values[dish_id] = int(values.get(dish_id, 0)) + servings
	weights[dish_id] = float(weights.get(dish_id, 0.0)) + added_weight
	state["personal_dishes"] = values
	state["personal_dish_weights"] = weights
	_server_layout_add_item(state, {"kind": "dish", "dish_id": dish_id, "servings": servings, "weight_kg": added_weight})


func _server_can_add_personal_dish(state: Dictionary, dish_id: String, servings: int, weight_kg := -1.0) -> bool:
	var definition := DishCatalog.get_definition(dish_id)
	var weight := weight_kg if weight_kg > 0.0 else float(definition.get("serving_weight_kg", 0.0)) * float(servings)
	if definition.is_empty() or servings <= 0 or weight <= 0.0 \
			or _personal_ingredient_total_weight(state) + weight > _server_bag_weight_capacity_kg(state) + 0.001:
		return false
	var values: Variant = state.get("personal_dishes", {})
	return (values is Dictionary and int((values as Dictionary).get(dish_id, 0)) > 0) \
		or _server_backpack_entry_count(state) < _server_bag_capacity(state)


func apply_world_snapshot(snapshot: Dictionary) -> void:
	last_snapshot = snapshot.duplicate(true)
	var event_board_state: Variant = snapshot.get("event_board", {})
	if event_board_state is Dictionary:
		EventBoard.apply_state(event_board_state as Dictionary)


func apply_reliable_world_event(event: Dictionary) -> void:
	var event_type := str(event.get("type", ""))
	if event_type == "event_board_state":
		var event_board_state: Variant = event.get("data", {})
		if event_board_state is Dictionary:
			EventBoard.apply_state(event_board_state as Dictionary)
	elif event_type == "team_money_changed":
		var team := str(event.get("team", ""))
		if GlobalVar.team_storage.has(team):
			var team_data: Dictionary = GlobalVar.team_storage[team]
			team_data["money"] = float(event.get("new_amount", team_data.get("money", 0.0)))
			GlobalVar.storage_changed.emit(team, "money", float(team_data["money"]))
	elif event_type == "team_score_changed":
		var score_team := str(event.get("team", ""))
		if GlobalVar.team_scores.has(score_team):
			GlobalVar.apply_team_scores({
				score_team: float(event.get(
					"new_score",
					GlobalVar.get_team_score(score_team)
				))
			})
	reliable_world_event_ready.emit(event)


func report_farm_tile_delta(tile: FarmTile, delta: Dictionary) -> void:
	if mode != MODE_SERVER or tile == null or not is_instance_valid(tile):
		return
	var key := str(delta.get("field_id", ""))
	if not key.is_empty():
		key += ":%s" % str(delta.get("grid_coordinate", Vector2i.ZERO))
	else:
		key = str(delta.get("tile_path", tile.get_path()))
	pending_farm_tile_deltas[key] = delta
	farm_reconcile_states[key] = delta.duplicate(true)


func _flush_farm_tile_deltas() -> void:
	if mode != MODE_SERVER or pending_farm_tile_deltas.is_empty():
		return
	var tiles: Array[Dictionary] = []
	for delta_value in pending_farm_tile_deltas.values():
		if delta_value is Dictionary:
			tiles.append(delta_value as Dictionary)
	pending_farm_tile_deltas.clear()
	if tiles.is_empty():
		return
	reliable_world_event_ready.emit({
		"type": "farm_tile_deltas",
		"tiles": tiles,
		"tick": server_tick,
	})


func _queue_farm_reconcile_chunks() -> void:
	# Reliable deltas maintain a persistent cache of the tiles that have ever
	# changed. Reconciliation therefore scales with modified tiles instead of
	# scanning all 1536 map tiles on a periodic authority frame.
	if not pending_farm_reconcile_chunks.is_empty():
		return
	var states: Array[Dictionary] = []
	for state_value: Variant in farm_reconcile_states.values():
		if state_value is Dictionary:
			states.append((state_value as Dictionary).duplicate(true))
	if states.is_empty():
		return
	farm_reconcile_cycle += 1
	var chunk_count := ceili(float(states.size()) / float(FARM_RECONCILE_CHUNK_SIZE))
	for offset in range(0, states.size(), FARM_RECONCILE_CHUNK_SIZE):
		pending_farm_reconcile_chunks.append({
			"type": "farm_reconcile_chunk",
			"cycle": farm_reconcile_cycle,
			"chunk_index": offset / FARM_RECONCILE_CHUNK_SIZE,
			"chunk_count": chunk_count,
			"tiles": states.slice(offset, mini(offset + FARM_RECONCILE_CHUNK_SIZE, states.size())),
		})


func _flush_next_farm_reconcile_chunk() -> void:
	if mode != MODE_SERVER or pending_farm_reconcile_chunks.is_empty():
		return
	var event := pending_farm_reconcile_chunks.pop_front() as Dictionary
	event["tick"] = server_tick
	reliable_world_event_ready.emit(event)


func apply_inventory_state(state: Dictionary) -> void:
	var teams: Variant = state.get("teams", {})
	if teams is Dictionary:
		GlobalVar.team_storage = (teams as Dictionary).duplicate(true)
		for team in GlobalVar.team_storage.keys():
			var team_data: Variant = GlobalVar.team_storage[team]
			if team_data is Dictionary:
				for item_name in (team_data as Dictionary).keys():
					GlobalVar.storage_changed.emit(str(team), str(item_name), float((team_data as Dictionary).get(item_name, 0.0)))
	var scores: Variant = state.get("scores", {})
	if scores is Dictionary:
		GlobalVar.apply_team_scores(scores as Dictionary)
	inventory_state_ready.emit(state)


func apply_player_correction(correction: Dictionary) -> void:
	player_correction_ready.emit(int(correction.get("peer_id", 0)), correction)


func _build_world_snapshot() -> Dictionary:
	# 高频快照：目标 30Hz / unreliable。
	# 这里只放需要频繁校正或插值的数据：玩家、移动投射物、遥控设备。
	var remaining_time_seconds := -1
	var match_duration_seconds := 0
	if server_manager != null:
		if server_manager.has_method("get_match_remaining_seconds"):
			remaining_time_seconds = int(server_manager.call("get_match_remaining_seconds"))
		if server_manager.has_method("get_match_duration_seconds"):
			match_duration_seconds = int(server_manager.call("get_match_duration_seconds"))
	var public_players: Array[Dictionary] = []
	for raw_peer_id in player_states.keys():
		var peer_id := int(raw_peer_id)
		var state: Dictionary = player_states[peer_id]
		public_players.append({
			"peer_id": peer_id,
			"display_name": state.get("display_name", "Player_%d" % peer_id),
			"team": state.get("team", ""),
			"big_mouth_capture_remaining": float(state.get("big_mouth_capture_remaining", 0.0)),
			"big_mouth_anchor": state.get("big_mouth_anchor", Vector3.ZERO),
			"hero_id": state.get("hero_id", "farmer"),
			"primary_weapon_ids": state.get("primary_weapon_ids", []),
			"special_tool_ids": state.get("special_tool_ids", []),
			"equipped_backpack_id": str(state.get("equipped_backpack_id", "")),
			"equipped_items": {
				"backpack": _server_equipment_item(state, str(state.get("equipped_backpack_id", ""))),
				"chest_armor": _server_equipment_item(state, str(state.get("equipped_chest_armor_id", ""))),
				"legwear": _server_equipment_item(state, str(state.get("equipped_legwear_id", ""))),
			},
			"position": state.get("position", Vector3.ZERO),
			"velocity": state.get("velocity", Vector3.ZERO),
			"yaw": float(state.get("yaw", 0.0)),
			"pitch": float(state.get("pitch", 0.0)),
			"grounded": bool(state.get("grounded", true)),
			"prone": bool(state.get("prone", false)),
			"locomotion_state": state.get("locomotion_state", "idle_tool"),
			"hp": float(state.get("hp", PLAYER_MAX_HP)),
			"respawn_left": float(state.get("respawn_left", 0.0)),
			"labeled_remaining": float(state.get("labeled_remaining", 0.0)),
			"current_tool_index": int(state.get("current_tool_index", 0)),
			"current_tool_id": str(state.get("current_tool_id", "")),
			"last_input_seq": int(state.get("last_input_seq", 0)),
			"vehicle_id": state.get("vehicle_id", ""),
			"vehicle_seat_index": int(state.get("vehicle_seat_index", -1)),
		})
	var public_vehicles: Array[Dictionary] = []
	for raw_vehicle_id in vehicle_states.keys():
		var vehicle_id := str(raw_vehicle_id)
		var vehicle: Dictionary = vehicle_states[vehicle_id]
		public_vehicles.append({
			"vehicle_id": vehicle_id,
			"scene_path": vehicle.get("scene_path", ""),
			"owner_team": vehicle.get("owner_team", ""),
			"position": vehicle.get("position", Vector3.ZERO),
			"yaw": float(vehicle.get("yaw", 0.0)),
			"speed": float(vehicle.get("speed", 0.0)),
			"steering": float(vehicle.get("steering", 0.0)),
			"hp": float(vehicle.get("hp", 0.0)),
			"shield_hp": float(vehicle.get("shield_hp", 0.0)),
			"shield_max_hp": float(vehicle.get("shield_max_hp", 0.0)),
			"shield_remaining": float(vehicle.get("shield_remaining", 0.0)),
			"cargo_weight_kg": float(vehicle.get("cargo_weight_kg", 0.0)),
			"cargo_occupied_slots": vehicle.get("cargo_occupied_slots", []),
			"cargo_available_slots": int(vehicle.get("cargo_available_slots", 12)),
			"driver_peer_id": int(vehicle.get("driver_peer_id", 0)),
			"seat_occupants": vehicle.get("seat_occupants", []),
		})
	var public_projectiles: Array[Dictionary] = []
	for raw_projectile_id in projectile_states.keys():
		var projectile_id := int(raw_projectile_id)
		var projectile: Dictionary = projectile_states[projectile_id]
		public_projectiles.append({
			"projectile_id": projectile_id,
			"type": projectile.get("type", ""),
			"position": projectile.get("position", Vector3.ZERO),
			"velocity": projectile.get("velocity", Vector3.ZERO),
		})
	var public_remote_devices: Array[Dictionary] = []
	for raw_device_id in remote_device_states.keys():
		var device_id := str(raw_device_id)
		var device: Dictionary = remote_device_states[device_id]
		var device_type := str(device.get("device_type", ""))
		var device_node := _gameplay_tool_node(_node_for_tool_ref({
			"kind": "remote",
			"id": device_id,
		}))
		var primary_cooldown := 0.0
		if device_type == "normal_drone" or device_type == "tech_drone" or device_type == "small_mouse":
			var cooldown_property := "bomb_cooldown" if device_type == "normal_drone" else "repair_pulse_cooldown" if device_type == "tech_drone" else "primary_action_cooldown"
			var cooldown_profile := "normal_drone" if device_type == "normal_drone" else "tech_drone" if device_type == "tech_drone" else "small_mouse"
			var cooldown_key := "bomb_cooldown" if device_type == "normal_drone" else "primary_cooldown"
			primary_cooldown = maxf(0.0, _configured_tool_float(device_node, cooldown_property, CombatBalance.get_float(cooldown_profile, cooldown_key)))
		public_remote_devices.append({
			"device_id": device_id,
			"device_type": device.get("device_type", ""),
			"team": device.get("team", ""),
			"position": device.get("position", Vector3.ZERO),
			"velocity": device.get("velocity", Vector3.ZERO),
			"yaw": float(device.get("yaw", 0.0)),
			"hp": float(device.get("hp", 0.0)),
			"last_input_seq": int(device.get("last_input_seq", 0)),
			"signal_strength": float(device.get("signal_strength", 0.0)),
			"jam_ratio": float(device.get("jam_ratio", 1.0)),
			"aug_ratio": float(device.get("aug_ratio", 1.0)),
			"effective_signal": float(device.get("effective_signal", 0.0)),
			"primary_action_cooldown": primary_cooldown,
			"primary_action_cooldown_left": maxf(0.0, float(int(device.get("primary_action_ready_at_msec", 0)) - Time.get_ticks_msec()) / 1000.0),
			"electronics_disabled_remaining": float(device_node.call("get_electronics_disabled_remaining")) if device_node != null and device_node.has_method("get_electronics_disabled_remaining") else 0.0,
		})
	var public_placed_tools: Array[Dictionary] = []
	for raw_tool_id in placed_tool_states.keys():
		var tool_id := str(raw_tool_id)
		var tool: Dictionary = placed_tool_states[tool_id]
		var public_tool := {
			"tool_id": tool_id,
			"device_id": tool.get("device_id", tool_id),
			"tool_name": tool.get("tool_name", ""),
			"path": tool.get("path", tool_id),
			"scene_path": tool.get("scene_path", ""),
			"team": tool.get("team", ""),
			"free_placement": bool(tool.get("free_placement", false)),
			"anchor_landed": bool(tool.get("anchor_landed", false)),
			"position": tool.get("position", Vector3.ZERO),
			"yaw": float(tool.get("yaw", 0.0)),
			"hp": float(tool.get("hp", 0.0)),
		}
		var node = get_node_or_null(NodePath(str(tool.get("path", tool_id))))
		if node is FarmTile:
			node = (node as FarmTile).tool_child
		if node != null and node.has_method("get_network_visual_state"):
			public_tool["visual_state"] = node.call("get_network_visual_state")
		public_placed_tools.append(public_tool)
	var public_wild_animals: Array[Dictionary] = []
	for animal in get_tree().get_nodes_in_group("wild_animals"):
		if is_instance_valid(animal) and animal.has_method("get_network_state"):
			public_wild_animals.append(animal.call("get_network_state") as Dictionary)
	return {
		"tick": server_tick,
		"server_time_msec": Time.get_ticks_msec(),
		"remaining_time_seconds": remaining_time_seconds,
		"match_duration_seconds": match_duration_seconds,
		"players": public_players,
		"vehicles": public_vehicles,
		"projectiles": public_projectiles,
		"remote_devices": public_remote_devices,
		"placed_tools": public_placed_tools,
		"wild_animals": public_wild_animals,
	}


func _estimate_world_snapshot_bytes(snapshot: Dictionary) -> int:
	# Metrics only need a stable approximation. Avoid JSON.stringify here: it
	# allocates and serializes the full 30 Hz snapshot on the authority thread.
	var estimate := 96
	var players_value: Variant = snapshot.get("players", [])
	var vehicles_value: Variant = snapshot.get("vehicles", [])
	var projectiles_value: Variant = snapshot.get("projectiles", [])
	var remotes_value: Variant = snapshot.get("remote_devices", [])
	var tools_value: Variant = snapshot.get("placed_tools", [])
	var animals_value: Variant = snapshot.get("wild_animals", [])
	if players_value is Array:
		estimate += (players_value as Array).size() * 320
	if vehicles_value is Array:
		estimate += (vehicles_value as Array).size() * 280
	if projectiles_value is Array:
		estimate += (projectiles_value as Array).size() * 96
	if remotes_value is Array:
		estimate += (remotes_value as Array).size() * 280
	if tools_value is Array:
		estimate += (tools_value as Array).size() * 300
	if animals_value is Array:
		estimate += (animals_value as Array).size() * 160
	return estimate


func _build_low_frequency_snapshot(include_nature_resources := false) -> Dictionary:
	# 低频快照：1Hz。自然资源已有可靠增量事件，仅每 10 秒全量纠偏，
	# 避免所有资源状态集中在每秒同一帧生成和应用。
	# 比分/库存/数量类信息不用 30Hz 更新，但客户端 UI 需要稳定拿到最新权威值。
	var scores := {}
	if GlobalVar.has_method("get_team_scores"):
		scores = GlobalVar.get_team_scores()
	var inventory := {}
	if GlobalVar.has_method("get_public_inventory_state"):
		inventory = GlobalVar.get_public_inventory_state()
	var extractors: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("ingredient_extractors"):
		if node is IngredientExtractor:
			extractors.append((node as IngredientExtractor).get_extractor_state())
	var auto_cookers: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("auto_cookers"):
		if node is AutoCooker: auto_cookers.append((node as AutoCooker).get_cook_state())
	var induction_counters: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("induction_counters"):
		if node is RecipeCookingStation:
			induction_counters.append((node as RecipeCookingStation).get_station_state())
	var freezers: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("freezer_stations"):
		if node is RecipeCookingStation:
			freezers.append((node as RecipeCookingStation).get_station_state())
	var stand_mixers: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("stand_mixers"):
		if node is StandMixer:
			stand_mixers.append((node as StandMixer).get_mixer_state())
	var livestock_chops: Array[Dictionary] = []
	for node in get_tree().get_nodes_in_group("livestock_chops"):
		if node is LivestockChop:
			livestock_chops.append((node as LivestockChop).get_chop_state())
	var dropped_items: Array[Dictionary] = []
	for pickup in dropped_item_nodes.values():
		if pickup is PickupItem and is_instance_valid(pickup):
			dropped_items.append((pickup as PickupItem).get_pickup_state())
	var cargo_car_respawns: Array[Dictionary] = []
	for team_value in cargo_car_respawn_states.keys():
		var team := str(team_value)
		var respawn_state: Dictionary = cargo_car_respawn_states[team]
		cargo_car_respawns.append({
			"team": team,
			"active": true,
			"remaining": float(respawn_state.get("remaining", 0.0)),
			"duration": 60.0,
		})
	var rare_resource_state: Dictionary = {}
	var rare_manager := get_tree().get_first_node_in_group("rare_resource_manager")
	if rare_manager != null:
		rare_resource_state = (rare_manager.get("active_resource") as Dictionary).duplicate(true)
	var nature_resources: Array[Dictionary] = []
	if include_nature_resources:
		var nature_nodes: Array[Node] = []
		for group_name in ["nature_resources", "harvest_trees", "harvest_ores", "harvest_mushrooms"]:
			for node in get_tree().get_nodes_in_group(group_name):
				if is_instance_valid(node) and not nature_nodes.has(node):
					nature_nodes.append(node)
		for node in nature_nodes:
			if not is_instance_valid(node) or not node is Node3D:
				continue
			var resource_id := str(node.get("resource_id")) if _node_has_property(node, "resource_id") else str(node.get("tree_id")) if _node_has_property(node, "tree_id") else str(node.get_path())
			var hp := float(node.get("current_hp")) if _node_has_property(node, "current_hp") else 0.0
			nature_resources.append({
				"resource_id": resource_id,
				"resource_kind": "tree" if node is HarvestTree else "nature",
				"position": node.global_position,
				"hp": hp,
				"destroyed": bool(node.get("destroyed")) if _node_has_property(node, "destroyed") else false,
			})
	var livestock_growth: Array[Dictionary] = []
	for animal in get_tree().get_nodes_in_group("farm_livestock"):
		if is_instance_valid(animal) and animal.has_method("get_low_frequency_growth_state"):
			livestock_growth.append(animal.call("get_low_frequency_growth_state") as Dictionary)
	var snapshot := {
		"tick": server_tick,
		"scores": scores,
		"inventory": inventory,
		"extractors": extractors,
		"auto_cookers": auto_cookers,
		"induction_counters": induction_counters,
		"freezers": freezers,
		"stand_mixers": stand_mixers,
		"livestock_chops": livestock_chops,
		"livestock_growth": livestock_growth,
		"dropped_items": dropped_items,
		"cargo_car_respawns": cargo_car_respawns,
		"rare_resource": rare_resource_state,
		"projectile_count": projectile_states.size(),
		"remote_device_count": remote_device_states.size(),
		"placed_tool_count": placed_tool_states.size(),
	}
	if include_nature_resources:
		snapshot["nature_resources"] = nature_resources
	return snapshot


func _make_player_correction(peer_id: int) -> Dictionary:
	var state: Dictionary = player_states.get(peer_id, {})
	return {
		"peer_id": peer_id,
		"tick": server_tick,
		"input_seq": int(state.get("last_input_seq", 0)),
		"position": state.get("position", Vector3.ZERO),
		"velocity": state.get("velocity", Vector3.ZERO),
		"grounded": bool(state.get("grounded", true)),
		"last_jump_seq": int(state.get("last_jump_seq", 0)),
		"yaw": float(state.get("yaw", 0.0)),
		"pitch": float(state.get("pitch", 0.0)),
	}


func _build_inventory_state() -> Dictionary:
	return {
		"tick": server_tick,
		"teams": GlobalVar.team_storage.duplicate(true),
		"scores": GlobalVar.get_team_scores(),
	}


func _roll_metrics_second() -> void:
	var seconds := maxf(metrics_second_accumulator, 0.001)
	measured_tick_rate = float(ticks_this_second) / seconds
	measured_snapshot_rate = float(snapshots_this_second) / seconds
	measured_bytes_sent_per_second = int(float(bytes_sent_this_second) / seconds)
	measured_bytes_received_per_second = int(float(bytes_received_this_second) / seconds)
	ticks_this_second = 0
	snapshots_this_second = 0
	bytes_sent_this_second = 0
	bytes_received_this_second = 0
	metrics_second_accumulator = 0.0


func get_server_tick_rate() -> float:
	return measured_tick_rate


func get_average_tick_ms() -> float:
	if tick_samples_ms.is_empty():
		return 0.0
	var total := 0.0
	for sample: float in tick_samples_ms:
		total += sample
	return total / float(tick_samples_ms.size())


func get_max_tick_ms() -> float:
	var max_value := 0.0
	for sample: float in tick_samples_ms:
		max_value = maxf(max_value, sample)
	return max_value


func get_snapshot_send_rate() -> float:
	return measured_snapshot_rate


func get_connected_peer_count() -> int:
	if server_manager != null and server_manager.has_method("get_connected_peer_count"):
		return int(server_manager.call("get_connected_peer_count"))
	return player_states.size()


func get_bytes_sent_per_second() -> int:
	return measured_bytes_sent_per_second


func get_bytes_received_per_second() -> int:
	return measured_bytes_received_per_second


func get_peer_rtt_ms(peer_id: int) -> float:
	if MultiplayerNetwork.is_connected_to_game_server() and peer_id == MultiplayerNetwork.get_unique_peer_id():
		return MultiplayerNetwork.get_last_rtt_ms()
	return 0.0


func get_peer_packet_loss(_peer_id: int) -> float:
	# Godot ENet 的公开 GDScript API 不稳定暴露 packet loss；先保留统一接口。
	return 0.0


func get_server_metrics_public_info() -> Dictionary:
	var load_state := "OK"
	var avg_ms := get_average_tick_ms()
	if measured_tick_rate > 0.0 and measured_tick_rate < TARGET_TICK_RATE * 0.9:
		load_state = "LOW_TICK_RATE"
	elif avg_ms > TARGET_TICK_INTERVAL * 1000.0:
		load_state = "SLOW_TICK"
	return {
		"target_tick_rate": TARGET_TICK_RATE,
		"tick_rate": measured_tick_rate,
		"avg_tick_ms": avg_ms,
		"max_tick_ms": get_max_tick_ms(),
		"snapshot_rate": measured_snapshot_rate,
		"peer_count": get_connected_peer_count(),
		"bytes_sent_per_second": measured_bytes_sent_per_second,
		"bytes_received_per_second": measured_bytes_received_per_second,
		"server_load_state": load_state,
	}


func print_server_metrics() -> void:
	var m := get_server_metrics_public_info()
	print(
		"[ServerMetrics] tick=%.1fHz avg=%.2fms max=%.2fms snapshot=%.1fHz peers=%d sent=%dB/s recv=%dB/s state=%s"
		% [
			float(m.get("tick_rate", 0.0)),
			float(m.get("avg_tick_ms", 0.0)),
			float(m.get("max_tick_ms", 0.0)),
			float(m.get("snapshot_rate", 0.0)),
			int(m.get("peer_count", 0)),
			int(m.get("bytes_sent_per_second", 0)),
			int(m.get("bytes_received_per_second", 0)),
			str(m.get("server_load_state", "UNKNOWN")),
		]
	)


func _vector2_from_value(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", 0.0)), float(value.get("y", 0.0)))
	return Vector2.ZERO


func _vector3_from_value(value: Variant) -> Vector3:
	if value is Vector3:
		return value
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	if value is Dictionary:
		return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))
	return Vector3.ZERO
