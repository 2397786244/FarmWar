extends StaticBody3D
class_name SignalAugment

@export var augment_dist: float = 25.0
@export var tool_owner: String = ""
@export var set_hp: float = 500.0
@export var hp_debug_label: bool = true
@export_range(1.0, 100.0, 1.0) var max_augment_ratio: float = 100.0
@export var augment_detect_tick: float = 0.5
@export var flame_duration: float = 3.0
@export var lightening_disable_duration: float = 5.0

var current_hp: float = 500.0
var augment_counter := 0.0
var is_placed := false
var is_active := false
var burn_remaining := 0.0
var burn_dps := 0.0
var lightening_disabled_remaining := 0.0
## device_id -> allied remote device body currently inside Aug3D.
var augmented_devices: Dictionary = {}

@onready var augment_3d: Area3D = $Aug3D
@onready var augment_collision_shape: CollisionShape3D = $Aug3D/CollisionShape3D
@onready var hit_3d: Area3D = $Hit3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	current_hp = set_hp
	_update_health_label()
	if not is_instance_valid(augment_3d):
		return
	if not augment_3d.body_entered.is_connected(_on_augment_3d_body_entered):
		augment_3d.body_entered.connect(_on_augment_3d_body_entered)
	if not augment_3d.body_exited.is_connected(_on_augment_3d_body_exited):
		augment_3d.body_exited.connect(_on_augment_3d_body_exited)


func emit() -> Dictionary:
	var user_node := get_node_or_null("../../../") as Node3D
	if user_node == null or tool_owner.is_empty():
		return {}
	var raycast := user_node.find_child("LookAtTarget", true, false) as RayCast3D
	if raycast == null or not raycast.is_colliding():
		return {}
	var augment := load("res://character/weapons/SignalAugment.tscn").instantiate() as SignalAugment
	if augment == null or GlobalVar.gameworld == null:
		return {}
	GlobalVar.gameworld.add_child(augment)
	augment.global_position = raycast.get_collision_point()
	augment.rotation.y = user_node.rotation.y
	augment.tool_owner = tool_owner
	augment.activate_tool()
	return {}


func activate_tool() -> void:
	collision_layer = 128
	if not is_placed:
		current_hp = set_hp
	is_placed = true
	is_active = true
	_update_health_label()
	augment_counter = maxf(augment_detect_tick, 0.0)
	if not is_instance_valid(augment_3d):
		return
	var augment_shape := augment_collision_shape.shape as SphereShape3D
	if augment_shape != null:
		augment_shape.radius = maxf(augment_dist, 0.01)
	augment_3d.monitoring = true
	augment_3d.monitorable = false
	call_deferred("_refresh_augmented_devices")


func impact(
	_effect: String,
	strength: float,
	attacker_team: String = ""
) -> bool:
	if not is_active:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	if _effect.to_lower() == "repair_laser":
		lightening_disabled_remaining = maxf(
			lightening_disabled_remaining,
			CombatBalance.get_electronic_disable_duration("signal_augment", "repair_laser")
		)
		return true
	if strength <= 0.0:
		return false
	_apply_damage(strength)
	if current_hp <= 0.0:
		return true
	match _effect.to_lower():
		"flame":
			burn_remaining = maxf(burn_remaining, flame_duration)
			burn_dps = maxf(burn_dps, strength)
		"lightening":
			lightening_disabled_remaining = maxf(
				lightening_disabled_remaining,
				CombatBalance.get_electronic_disable_duration("signal_augment", "lightning")
			)
	return true


func _apply_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - maxf(amount, 0.0))
	_update_health_label()
	if current_hp <= 0.0:
		_destroy_augment()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	is_placed = true
	_update_health_label()


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and is_placed
	health_label.text = "%d" % int(ceil(current_hp))


func _destroy_augment() -> void:
	if not is_active:
		return
	is_active = false
	augmented_devices.clear()
	burn_remaining = 0.0
	burn_dps = 0.0
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(hit_3d):
		hit_3d.set_deferred("monitoring", false)
	if is_instance_valid(augment_3d):
		augment_3d.set_deferred("monitoring", false)
	call_deferred("queue_free")


func _physics_process(delta: float) -> void:
	if not is_active or GameAuthority.is_client_proxy():
		return
	_update_status_effects(delta)
	if not _is_operational():
		return
	augment_counter += delta
	if augment_counter < maxf(augment_detect_tick, 0.01):
		return
	augment_counter = 0.0
	_refresh_augmented_devices()


func _update_status_effects(delta: float) -> void:
	lightening_disabled_remaining = maxf(
		0.0,
		lightening_disabled_remaining - delta
	)
	if burn_remaining <= 0.0:
		return
	var burn_tick := minf(delta, burn_remaining)
	burn_remaining = maxf(0.0, burn_remaining - delta)
	_apply_damage(burn_dps * burn_tick)
	if burn_remaining <= 0.0:
		burn_dps = 0.0


func _is_operational() -> bool:
	return is_active and lightening_disabled_remaining <= 0.0


## Returns 100.0 at the augment center and 1.0 at/after its edge.
## Its reciprocal exactly cancels SignalJam at the same position and radius.
func get_augment_ratio_for_device(device_id: String) -> float:
	if not _is_operational():
		return 1.0
	var target: Node3D = augmented_devices.get(device_id, null)
	if not is_instance_valid(target):
		augmented_devices.erase(device_id)
		return 1.0
	if not _can_augment_device(target):
		augmented_devices.erase(device_id)
		return 1.0
	var normalized_distance := clampf(
		global_position.distance_to(target.global_position) / maxf(augment_dist, 0.01),
		0.01,
		1.0
	)
	return clampf(1.0 / normalized_distance, 1.0, max_augment_ratio)


func _refresh_augmented_devices() -> void:
	if not is_instance_valid(augment_3d):
		return
	var current_devices: Dictionary = {}
	for body in augment_3d.get_overlapping_bodies():
		var target := _remote_device_from_collider(body)
		if not _can_augment_device(target):
			continue
		current_devices[_device_id_for(target)] = target
	augmented_devices = current_devices


func _on_augment_3d_body_entered(body: Node3D) -> void:
	var target := _remote_device_from_collider(body)
	if _can_augment_device(target):
		augmented_devices[_device_id_for(target)] = target


func _on_augment_3d_body_exited(body: Node3D) -> void:
	var target := _remote_device_from_collider(body)
	if target == null:
		return
	var device_id := _device_id_for(target)
	if augmented_devices.get(device_id, null) == target:
		augmented_devices.erase(device_id)


func _on_hit_3d_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests():
		return
	if not (
		body is BoomBullet
		or body is RubberBullet
		or body is ColorBullet
		or body is NailBullet
		or body is DetectLaserBullet
	):
		return
	var attacker_team := str(body.get_bullet_owner())
	if attacker_team == tool_owner:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = str(body.bullet_effect)
	if impact(effect, float(body.bullet_strength), attacker_team):
		body.queue_free()


func _can_augment_device(target: Node3D) -> bool:
	return target != null and target != self and str(target.get("tool_owner")) == tool_owner


func _device_id_for(target: Node3D) -> String:
	if not is_instance_valid(target):
		return ""
	if target.has_meta("network_device_id"):
		return str(target.get_meta("network_device_id"))
	if target.is_inside_tree():
		return str(target.get_path())
	return ""


func _remote_device_from_collider(collider: Variant) -> Node3D:
	var node := collider as Node
	while node != null and node != self:
		if node is NormalDrone or node is SmallMouse or node is BoomBuggy:
			return node as Node3D
		node = node.get_parent()
	return null
