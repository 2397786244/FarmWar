extends StaticBody3D
class_name SignalJam

@export var jam_dist:float = 25.0
@export var tool_owner:String = ""
@export var set_hp:float = 500.0
@export var hp_debug_label:bool = true

@export var jam_detect_tick:float = 0.5
@export var flame_duration:float = 3.0
@export var lightening_disable_duration:float = 5.0
var current_hp:float = 500.0
var jam_counter:float = 0.0
var is_placed:bool = false
var is_active:bool = false
var burn_remaining:float = 0.0
var burn_dps:float = 0.0
var lightening_disabled_remaining:float = 0.0
## device_id -> remote device body currently inside Jam3D.
## Area3D owns membership; the ratio itself is derived from the current
## positions when GameAuthority asks for it, so moving devices do not retain a
## stale value between detector updates.
var jammed_devices: Dictionary = {}

@onready var jam_3d: Area3D = $Jam3D
@onready var jam_collision_shape: CollisionShape3D = $Jam3D/CollisionShape3D
@onready var hit_3d: Area3D = $Hit3D
@onready var health_label: Label3D = get_node_or_null("Label3D") as Label3D


func _ready() -> void:
	current_hp = set_hp
	_update_health_label()
	if not is_instance_valid(jam_3d):
		return
	if not jam_3d.body_entered.is_connected(_on_jam_3d_body_entered):
		jam_3d.body_entered.connect(_on_jam_3d_body_entered)
	if not jam_3d.body_exited.is_connected(_on_jam_3d_body_exited):
		jam_3d.body_exited.connect(_on_jam_3d_body_exited)

func emit() -> Dictionary:
	var user_node = get_node_or_null("../../../")  # 这里是根据玩家来的，因为这个工具放到了ToolPivot下面，如果是AIPlayer，注意这里要修改类型
	if not user_node:
		queue_free()
		return {}
	var raycast = user_node.find_child("LookAtTarget",true)  # 这是玩家注视的Raycast。将手持的可放置工具放置玩家正视的位置				
	if tool_owner.is_empty() or not user_node:
		return {}
	if not raycast or  not raycast.is_colliding():
		return {}
	var gvec3 = raycast.get_collision_point()
	var jam = load("res://character/weapons/SignalJam.tscn").instantiate()
	GlobalVar.gameworld.add_child(jam)
	jam.global_position = gvec3
	
	jam.tool_owner = self.tool_owner
	#print(user_node.rotation)
	jam.rotation.y = user_node.rotation.y
	#if is_instance_valid(visual_obj):
		#visual_obj.queue_free()
	jam.activate_tool()
	return {}
	
func activate_tool() -> void:
	collision_layer = 128
	if not is_placed:
		current_hp = set_hp
	is_placed = true
	is_active = true
	_update_health_label()
	jam_counter = maxf(jam_detect_tick, 0.0)
	if is_instance_valid(jam_3d):
		var jam_shape := jam_collision_shape.shape as SphereShape3D
		if jam_shape != null:
			jam_shape.radius = maxf(jam_dist, 0.01)
		jam_3d.monitoring = true
		jam_3d.monitorable = false
		call_deferred("_refresh_jammed_devices")


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
			CombatBalance.get_electronic_disable_duration("signal_jam", "repair_laser")
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
				CombatBalance.get_electronic_disable_duration("signal_jam", "lightning")
			)
	return true


func _apply_damage(amount: float) -> void:
	current_hp = maxf(0.0, current_hp - maxf(amount, 0.0))
	_update_health_label()
	if current_hp <= 0.0:
		_destroy_jammer()


func apply_network_health(hp: float) -> void:
	current_hp = maxf(0.0, hp)
	is_placed = true
	_update_health_label()


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = hp_debug_label and is_placed
	health_label.text = "%d" % int(ceil(current_hp))


func _destroy_jammer() -> void:
	if not is_active:
		return
	is_active = false
	jammed_devices.clear()
	burn_remaining = 0.0
	burn_dps = 0.0
	collision_layer = 0
	collision_mask = 0
	if is_instance_valid(hit_3d):
		hit_3d.set_deferred("monitoring", false)
	if is_instance_valid(jam_3d):
		jam_3d.set_deferred("monitoring", false)
	call_deferred("queue_free")
	
	
func _physics_process(delta: float) -> void:
	if not is_active or GameAuthority.is_client_proxy():
		return
	_update_status_effects(delta)
	if not _is_operational():
		return
	jam_counter += delta
	if jam_counter < maxf(jam_detect_tick, 0.01):
		return
	jam_counter = 0.0
	_refresh_jammed_devices()


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


## Returns 0.01 at the jammer center and 1.0 at/after its edge.
## GameAuthority combines overlapping jammers by taking the lowest ratio.
func get_jam_ratio_for_device(device_id: String) -> float:
	if not _is_operational():
		return 1.0
	var target: Node3D = jammed_devices.get(device_id, null)
	if not is_instance_valid(target):
		jammed_devices.erase(device_id)
		return 1.0
	if not _can_jam_device(target):
		jammed_devices.erase(device_id)
		return 1.0
	return clampf(
		global_position.distance_to(target.global_position) / maxf(jam_dist, 0.01),
		0.01,
		1.0
	)


func _refresh_jammed_devices() -> void:
	if not is_instance_valid(jam_3d):
		return
	var current_devices: Dictionary = {}
	for body in jam_3d.get_overlapping_bodies():
		var target := _remote_device_from_collider(body)
		if not _can_jam_device(target):
			continue
		var device_id := _device_id_for(target)
		current_devices[device_id] = target
	jammed_devices = current_devices


func _on_jam_3d_body_entered(body: Node3D) -> void:
	var target := _remote_device_from_collider(body)
	if _can_jam_device(target):
		jammed_devices[_device_id_for(target)] = target


func _on_jam_3d_body_exited(body: Node3D) -> void:
	var target := _remote_device_from_collider(body)
	if target == null:
		return
	var device_id := _device_id_for(target)
	if jammed_devices.get(device_id, null) == target:
		jammed_devices.erase(device_id)


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


func _can_jam_device(target: Node3D) -> bool:
	return target != null and target != self and str(target.get("tool_owner")) != tool_owner


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
	
	
	
