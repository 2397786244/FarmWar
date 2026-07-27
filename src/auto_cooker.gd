extends KitchenAppliance
class_name AutoCooker

const ROTATION_SPEED := 0.65
const PROGRESS_SYNC_INTERVAL := 0.25
const INTERACT_OBJECT_COLLISION_LAYER := 512

@export var set_hp := 500.0
@export var hp_debug_label := true
@export var tool_owner := ""

var recipe_id := ""
var cooking := false
var complete := false
var started_msec := 0
var duration_seconds := 0.0
var maker_peer_id := 0
var _last_progress_sync_msec := 0
@onready var rotating_drum: Node3D = find_child("RotatingDrum", true, false) as Node3D
@onready var health_label: Label3D = $HealthLabel

var current_hp := 500.0
var is_placed := false

func _ready() -> void:
	add_to_group("auto_cookers")
	current_hp = set_hp
	_update_health_label()

func _process(delta: float) -> void:
	if cooking and is_instance_valid(rotating_drum): rotating_drum.rotate_x(ROTATION_SPEED * delta)
	if GameAuthority.is_client_proxy() or not cooking: return
	if get_progress() < 1.0:
		if Time.get_ticks_msec() - _last_progress_sync_msec >= int(PROGRESS_SYNC_INTERVAL * 1000.0):
			_last_progress_sync_msec = Time.get_ticks_msec(); _emit_state()
		return
	cooking = false
	complete = true
	release_user(active_user_peer_id)
	_emit_state()

func get_interaction_hint(player: GamePlayer) -> String:
	if not can_player_interact(player): return "敌方自动做菜机"
	if complete: return "[E] 领取自动料理"
	if cooking: return "自动做菜中 %d%%" % roundi(get_progress() * 100.0)
	if is_in_use_by_other(player.authority_peer_id): return "队友正在使用自动做菜机"
	return "[E] 使用自动做菜机"

func interact(player: GamePlayer) -> bool:
	if not can_player_interact(player) or cooking: return false
	var page := player.get_node_or_null("SubViewport/AutoCookerPage")
	if page == null: return false
	page.call("open_for", self, player)
	if complete: page.call("take_completed_output")
	return true

func can_start(recipe: String) -> bool:
	return not cooking and not complete and recipe_id.is_empty() and not AutoCookerRecipeCatalog.get_recipe(recipe).is_empty()

func start(recipe: String, peer_id: int) -> bool:
	if not can_start(recipe): return false
	var definition := AutoCookerRecipeCatalog.get_recipe(recipe)
	recipe_id = recipe
	duration_seconds = maxf(10.0, float(definition.get("duration_seconds", 10.0)))
	started_msec = Time.get_ticks_msec()
	maker_peer_id = peer_id
	cooking = true
	complete = false
	_last_progress_sync_msec = 0
	return true

func take_completed_result() -> Dictionary:
	if not complete or recipe_id.is_empty(): return {}
	var result: Dictionary = get_completed_result()
	clear()
	return result

func get_completed_result() -> Dictionary:
	if not complete or recipe_id.is_empty(): return {}
	var result: Variant = AutoCookerRecipeCatalog.get_recipe(recipe_id).get("result", {})
	return (result as Dictionary).duplicate(true) if result is Dictionary else {}

func clear() -> void:
	recipe_id = ""; cooking = false; complete = false; started_msec = 0; duration_seconds = 0.0; maker_peer_id = 0

func get_progress() -> float:
	if complete: return 1.0
	if not cooking: return 0.0
	return clampf(float(Time.get_ticks_msec() - started_msec) / (duration_seconds * 1000.0), 0.0, 1.0)

func get_cook_state() -> Dictionary:
	return {"station_path":str(get_path()), "station_position":global_position, "recipe_id":recipe_id, "cooking":cooking, "complete":complete, "duration_seconds":duration_seconds, "progress":get_progress(), "maker_peer_id":maker_peer_id, "active_user_peer_id":active_user_peer_id}

func apply_authoritative_cook_state(state: Dictionary) -> void:
	recipe_id = str(state.get("recipe_id", "")); cooking = bool(state.get("cooking", false)); complete = bool(state.get("complete", false)); duration_seconds = float(state.get("duration_seconds", 0.0)); maker_peer_id = int(state.get("maker_peer_id", 0)); active_user_peer_id = int(state.get("active_user_peer_id", 0))
	started_msec = Time.get_ticks_msec() - int(float(state.get("progress", 0.0)) * duration_seconds * 1000.0)

func _emit_state() -> void:
	GameAuthority.reliable_world_event_ready.emit({"type":"auto_cooker_state", "station_state":get_cook_state(), "tick":GameAuthority.server_tick})

func _should_keep_user_lock() -> bool: return cooking


func activate_tool() -> void:
	collision_layer = INTERACT_OBJECT_COLLISION_LAYER
	is_placed = true
	current_hp = set_hp
	_update_health_label()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	is_placed = true
	_update_health_label()


func impact(effect: String, strength: float, attacker_team := "") -> bool:
	if not attacker_team.is_empty() and attacker_team == owner_team:
		return false
	if effect.to_lower() == "repair_laser" or strength <= 0.0:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	return true


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or not is_placed:
		return
	if not (body is BoomBullet or body is RubberBullet or body is ColorBullet or body is NailBullet or body is DetectLaserBullet):
		return
	var attacker_team := str(body.get_bullet_owner())
	if attacker_team == owner_team:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = str(body.bullet_effect)
	GameAuthority.call("_apply_hit_to_collider", self, effect, float(body.bullet_strength), attacker_team)
	body.queue_free()


func _update_health_label() -> void:
	if is_instance_valid(health_label):
		health_label.visible = hp_debug_label and is_placed
		health_label.text = "%d" % int(ceil(current_hp))
