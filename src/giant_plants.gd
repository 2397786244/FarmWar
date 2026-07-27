extends StaticBody3D
class_name GiantPlants

const NATURE_RESOURCE_LAYER := 16384
const CombatBalance = preload("res://src/combat_balance.gd")
@export var max_hp := 1000.0
@export var lifetime_seconds := 300.0
@export var resource_id := "giant_plant"
@export var display_name := "巨大作物"
@export var drop_item_id := "pepper"
@export var drop_count := 5
@export var drops: Array[Dictionary] = []

var current_hp := 0.0
var destroyed := false
var _last_attacker_peer_id := 0
var _pending_attacker_peer_id := 0
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D

func _ready() -> void:
	add_to_group("nature_resources")
	add_to_group("rare_resources")
	current_hp = max_hp
	collision_layer = NATURE_RESOURCE_LAYER
	var hit_area := get_node_or_null("Hit3D") as Area3D
	if hit_area != null and not hit_area.body_entered.is_connected(_on_hit_body_entered):
		hit_area.body_entered.connect(_on_hit_body_entered)
	_update_label()

func _on_hit_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or destroyed:
		return
	if not body.has_method("get_bullet_owner"):
		return
	var strength := float(body.get("bullet_strength"))
	if strength <= 0.0:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet:
		effect = str(body.get("bullet_effect"))
	var owner_team := str(body.call("get_bullet_owner"))
	var owner_peer_id := GameAuthority.resolve_attacker_peer_id(owner_team)
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, owner_team, -1, owner_peer_id
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(owner_team)

func impact(_effect: String, strength: float, _attacker_team := "") -> bool:
	if destroyed or strength <= 0.0:
		_pending_attacker_peer_id = 0
		return false
	_last_attacker_peer_id = GameAuthority.resolve_attacker_peer_id(
		_attacker_team, _pending_attacker_peer_id
	)
	_pending_attacker_peer_id = 0
	current_hp = maxf(0.0, current_hp - strength)
	_update_label()
	if GameAuthority.is_server_authority():
		var manager := get_tree().get_first_node_in_group("rare_resource_manager")
		if manager != null and manager.get("active_resource") is Dictionary:
			var active := (manager.get("active_resource") as Dictionary).duplicate(true)
			active["hp"] = current_hp
			manager.set("active_resource", active)
		GameAuthority.reliable_world_event_ready.emit({
			"type": "rare_resource_health",
			"resource_id": resource_id,
			"position": global_position,
			"hp": current_hp,
			"tick": GameAuthority.server_tick,
		})
	if current_hp <= 0.0:
		destroyed = true
		var crop_name := display_name.trim_prefix("巨大")
		GameAuthority.award_action_reward(
			_last_attacker_peer_id,
			CombatBalance.get_int("team_rewards", "giant_crop_destroyed", 500),
			"摧毁巨大「%s」" % crop_name
		)
		if drops.is_empty():
			drops = [{"kind": "ingredient", "item_id": drop_item_id, "count": drop_count, "weight_kg": 1.0}]
		GameAuthority.spawn_nature_resource_drops(global_position, drops)
		if is_instance_valid(RareResourceManager):
			RareResourceManager.destroy_active_resource("destroyed")
		queue_free()
	return true


func impact_from_peer(effect: String, strength: float, attacker_team: String, attacker_peer_id: int) -> bool:
	_pending_attacker_peer_id = attacker_peer_id
	return impact(effect, strength, attacker_team)

func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	_update_label()

func _update_label() -> void:
	if health_label != null:
		health_label.text = "%d" % int(ceil(current_hp))
