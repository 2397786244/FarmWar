extends Node3D
class_name MedievalShieldTool

## The shield is a passive handheld tool.  Its authoritative HP lives in the
## owner's backpack slot inside GameAuthority; this node only mirrors that
## state for the visible/local scene and provides a collider entry point for
## legacy local projectile queries.
const TOOL_ID := "medieval_shield"
const DEFAULT_MAX_HP := 1000.0
const SHIELD_COLLISION_LAYER := 128

@export var tool_owner: String = ""

var current_hp := DEFAULT_MAX_HP
var max_hp := DEFAULT_MAX_HP


func _ready() -> void:
	var absorb_area := find_child("AbsorbArea", true, false) as Area3D
	if absorb_area != null:
		absorb_area.collision_layer = SHIELD_COLLISION_LAYER
		absorb_area.collision_mask = 0
		absorb_area.monitoring = false
		absorb_area.monitorable = false
	set_shield_state(current_hp, max_hp)


func set_shield_state(hp: float, maximum: float = DEFAULT_MAX_HP) -> void:
	max_hp = maxf(1.0, maximum)
	current_hp = clampf(hp, 0.0, max_hp)


func set_shield_hp(hp: float, maximum: float = DEFAULT_MAX_HP) -> void:
	set_shield_state(hp, maximum)


func get_shield_hp() -> float:
	return current_hp


func get_shield_max_hp() -> float:
	return max_hp


func is_held_shield() -> bool:
	return true


func get_shield_owner_peer_id() -> int:
	var cursor: Node = get_parent()
	for _depth in range(16):
		if cursor == null:
			break
		if cursor is GamePlayer:
			return int((cursor as GamePlayer).authority_peer_id)
		cursor = cursor.get_parent()
	return 0


func get_held_item_info_text(_item: Dictionary = {}, _definition: Dictionary = {}) -> String:
	return "盾牌 %d / %d HP" % [roundi(current_hp), roundi(max_hp)]


func impact_from_peer(
	effect: String,
	damage: float,
	attacker_team: String,
	attacker_peer_id: int
) -> bool:
	var owner_peer_id := get_shield_owner_peer_id()
	if owner_peer_id <= 0 or not is_instance_valid(GameAuthority):
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	var result: Variant = GameAuthority.apply_held_shield_damage(
		owner_peer_id,
		damage,
		attacker_peer_id,
		effect,
		1.0,
		attacker_team
	)
	if result is Dictionary:
		var state := result as Dictionary
		set_shield_state(
			float(state.get("hp", current_hp)),
			float(state.get("max_hp", max_hp))
		)
		return bool(state.get("blocked", false))
	return false
