extends StaticBody3D
class_name CargoCrateGround

const LAYER_GROUND := 1
const LAYER_WALL := 2
const LAYER_CHARACTER := 8
const LAYER_BULLET := 32
const LAYER_TOOL := 128
const LAYER_VEHICLE := 8192
const LAYER_WILD_ANIMAL := 32768
const GROUND_SCALE := 5.0

@export_enum("small", "medium", "large") var crate_size := "medium"
@export var crate_instance_id := ""

var max_hp := 500.0
var current_hp := 500.0
var crate_data: Dictionary = {}
var active_user_peer_id := 0

@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var hit_area: Area3D = $Hit3D
@onready var hit_shape: CollisionShape3D = $Hit3D/CollisionShape3D
@onready var health_label: Label3D = $HealthLabel


func _ready() -> void:
	add_to_group("cargo_crates")
	add_to_group("network_map_devices")
	if not has_meta("network_device_id"):
		set_meta("network_device_id", str(get_path()))
	if crate_data.is_empty():
		crate_data = CargoCrateData.create_empty(crate_size, crate_instance_id)
	crate_instance_id = str(crate_data.get("crate_instance_id", ""))
	set_meta("crate_instance_id", crate_instance_id)
	var held_preview := bool(get_meta("held_preview", false))
	if not held_preview:
		_apply_ground_scale()
	var authority := _authority()
	var is_client_proxy := authority != null and bool(authority.call("is_client_proxy"))
	_set_gameplay_collision_enabled(not held_preview, not is_client_proxy)
	_update_health_label()
	if not hit_area.body_entered.is_connected(_on_hit_body_entered):
		hit_area.body_entered.connect(_on_hit_body_entered)
	if held_preview:
		health_label.visible = false
	else:
		call_deferred("_register_with_authority")


func _apply_ground_scale() -> void:
	if bool(get_meta("ground_scale_applied", false)):
		return
	set_meta("ground_scale_applied", true)
	scale *= GROUND_SCALE
	# Keep the world-space HP text readable while its anchor follows the larger box.
	if is_instance_valid(health_label):
		health_label.scale /= GROUND_SCALE


func setup_crate(value: Dictionary) -> void:
	crate_data = CargoCrateData.normalize(value)
	crate_size = str(crate_data.get("crate_size", crate_size))
	crate_instance_id = str(crate_data.get("crate_instance_id", crate_instance_id))
	current_hp = clampf(float(crate_data.get("current_hp", max_hp)), 0.0, max_hp)
	set_meta("crate_instance_id", crate_instance_id)
	_update_health_label()


func get_crate_data() -> Dictionary:
	crate_data["current_hp"] = current_hp
	crate_data["max_hp"] = max_hp
	return CargoCrateData.normalize(crate_data)


func set_stored_item(item: Dictionary) -> bool:
	if not CargoCrateData.can_store(crate_data, item):
		return false
	var stored: Dictionary = crate_data.get("stored_item", {}) as Dictionary \
		if crate_data.get("stored_item", {}) is Dictionary else {}
	var remaining_capacity := maxf(0.0, float(crate_data.get("capacity_kg", 0.0)) - CargoCrateData.item_weight_kg(stored))
	if CargoCrateData.item_weight_kg(item) > remaining_capacity + 0.001:
		return false
	if stored.is_empty():
		crate_data["stored_item"] = item.duplicate(true)
	else:
		var merged := UnitWeightItem.merge(stored, item)
		if merged.is_empty():
			return false
		crate_data["stored_item"] = merged
	crate_data = CargoCrateData.refresh_totals(crate_data)
	return true


func take_stored_item() -> Dictionary:
	var stored: Dictionary = crate_data.get("stored_item", {}) as Dictionary \
		if crate_data.get("stored_item", {}) is Dictionary else {}
	if stored.is_empty():
		return {}
	crate_data["stored_item"] = {}
	crate_data = CargoCrateData.refresh_totals(crate_data)
	return stored.duplicate(true)


func take_stored_weight(maximum_weight_kg: float) -> Dictionary:
	var stored: Dictionary = crate_data.get("stored_item", {}) as Dictionary \
		if crate_data.get("stored_item", {}) is Dictionary else {}
	var piece := UnitWeightItem.make_piece(stored, maximum_weight_kg)
	if piece.is_empty():
		return {}
	crate_data["stored_item"] = UnitWeightItem.subtract(stored, piece)
	crate_data = CargoCrateData.refresh_totals(crate_data)
	return piece


func get_interaction_hint(_player: Node) -> String:
	return "按E打开货运箱子    长按E捡起"


func try_acquire_user(peer_id: int) -> bool:
	if peer_id <= 0 or (active_user_peer_id > 0 and active_user_peer_id != peer_id):
		return false
	active_user_peer_id = peer_id
	return true


func release_user(peer_id: int) -> bool:
	if active_user_peer_id != peer_id:
		return false
	active_user_peer_id = 0
	return true


func impact(_effect: String, strength: float, _attacker_team := "") -> bool:
	var authority := _authority()
	if (authority != null and bool(authority.call("should_send_network_requests"))) \
			or strength <= 0.0 or current_hp <= 0.0:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	crate_data["current_hp"] = current_hp
	_update_health_label()
	if current_hp <= 0.0:
		_set_gameplay_collision_enabled(false)
		call_deferred("queue_free")
	return true


func apply_network_health(hp: float) -> void:
	current_hp = clampf(hp, 0.0, max_hp)
	crate_data["current_hp"] = current_hp
	_update_health_label()


func get_network_visual_state() -> Dictionary:
	return {"crate_data": get_crate_data()}


func apply_network_visual_state(state: Dictionary) -> void:
	var value: Variant = state.get("crate_data", {})
	if value is Dictionary:
		setup_crate(value as Dictionary)


func enable_network_visuals() -> void:
	_set_gameplay_collision_enabled(true, false)


func _register_with_authority() -> void:
	var authority := _authority()
	if authority != null and (bool(authority.call("is_server_authority")) \
			or bool(authority.call("is_local_authority"))):
		authority.call("register_map_cargo_crate", self)


func _on_hit_body_entered(body: Node3D) -> void:
	var authority := _authority()
	if authority == null or bool(authority.call("should_send_network_requests")) or current_hp <= 0.0 \
			or not body.has_method("get_bullet_owner"):
		return
	var strength := float(body.get("bullet_strength"))
	if strength <= 0.0:
		return
	var effect := "Explosion" if "boom" in body.name.to_lower() else "None"
	authority.call("_apply_hit_to_collider", self, effect, strength, str(body.call("get_bullet_owner")), -1)
	if is_instance_valid(body):
		body.queue_free()


func _set_gameplay_collision_enabled(enabled: bool, enable_hit := true) -> void:
	collision_layer = LAYER_TOOL if enabled else 0
	collision_mask = (LAYER_GROUND | LAYER_WALL | LAYER_CHARACTER | LAYER_TOOL \
		| LAYER_VEHICLE | LAYER_WILD_ANIMAL) if enabled else 0
	body_shape.set_deferred("disabled", not enabled)
	hit_area.collision_layer = LAYER_TOOL if enabled and enable_hit else 0
	hit_area.collision_mask = LAYER_BULLET if enabled and enable_hit else 0
	hit_area.set_deferred("monitoring", enabled and enable_hit)
	hit_area.set_deferred("monitorable", enabled and enable_hit)
	hit_shape.set_deferred("disabled", not enabled or not enable_hit)


func _authority() -> Node:
	return get_node_or_null("/root/GameAuthority")


func _update_health_label() -> void:
	if is_instance_valid(health_label):
		health_label.visible = current_hp > 0.0
		health_label.text = "HP: %d / %d" % [ceili(current_hp), ceili(max_hp)]
