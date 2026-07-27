extends StaticBody3D
class_name FakePlayerTool

const CombatBalance = preload("res://src/combat_balance.gd")

@export var tool_owner := ""
@export var activate_on_ready := false
@export var network_device_id := ""

var max_hp := 300.0
var current_hp := 300.0
var activated := false

@onready var body_shape: CollisionShape3D = $CollisionShape3D
@onready var hit_area: Area3D = $Hit3D
@onready var hit_shape: CollisionShape3D = $Hit3D/CollisionShape3D
@onready var health_label: Label3D = $Label3D


func _ready() -> void:
	max_hp = CombatBalance.get_tool_max_hp("fake_player")
	current_hp = max_hp
	if not network_device_id.is_empty():
		set_meta("network_device_id", network_device_id)
	if not hit_area.body_entered.is_connected(_on_hit_body_entered):
		hit_area.body_entered.connect(_on_hit_body_entered)
	_set_gameplay_collision_enabled(false)
	_update_health_label()
	if activate_on_ready:
		activate_tool()


func emit() -> Dictionary:
	var user_node := get_node_or_null("../../../") as Node3D
	if user_node == null or tool_owner.is_empty() or GlobalVar.gameworld == null:
		return {}
	var raycast := user_node.find_child("LookAtTarget", true, false) as RayCast3D
	if raycast == null or not raycast.is_colliding():
		return {}
	var packed := load("res://character/weapons/FakePlayer.tscn") as PackedScene
	var decoy := packed.instantiate() as FakePlayerTool if packed != null else null
	if decoy == null:
		return {}
	GlobalVar.gameworld.add_child(decoy)
	decoy.global_position = raycast.get_collision_point()
	decoy.rotation.y = user_node.rotation.y
	decoy.tool_owner = tool_owner
	decoy.activate_tool()
	return {}


func activate_tool() -> void:
	if current_hp <= 0.0:
		return
	activated = true
	_set_gameplay_collision_enabled(not GameAuthority.is_client_proxy())
	_update_health_label()


func enable_network_visuals() -> void:
	activated = true
	_update_health_label()


func impact(_effect: String, strength: float, attacker_team: String = "") -> bool:
	if GameAuthority.should_send_network_requests() or not activated \
			or strength <= 0.0 or current_hp <= 0.0:
		return false
	if not attacker_team.is_empty() and attacker_team == tool_owner:
		return false
	current_hp = maxf(0.0, current_hp - strength)
	_update_health_label()
	if current_hp <= 0.0:
		activated = false
		_set_gameplay_collision_enabled(false)
	return true


func apply_network_health(hp: float) -> void:
	current_hp = clampf(hp, 0.0, max_hp)
	activated = current_hp > 0.0
	_update_health_label()


func _on_hit_body_entered(body: Node3D) -> void:
	if GameAuthority.should_send_network_requests() or not activated \
			or not body.has_method("get_bullet_owner"):
		return
	var attacker_team := str(body.call("get_bullet_owner"))
	var strength := float(body.get("bullet_strength"))
	if strength <= 0.0:
		return
	var effect := "Explosion" if body is BoomBullet else "None"
	if body is ColorBullet or body is DetectLaserBullet:
		effect = str(body.get("bullet_effect"))
	var applied := bool(GameAuthority.call(
		"_apply_hit_to_collider", self, effect, strength, attacker_team, -1
	))
	if applied:
		GameAuthority.show_local_hit_marker_for_team(attacker_team)
		if is_instance_valid(body):
			body.queue_free()


func _set_gameplay_collision_enabled(enabled: bool) -> void:
	collision_layer = GameAuthority.COLLISION_LAYER_TOOL if enabled else 0
	collision_mask = GameAuthority.FREE_PLACEMENT_BLOCKING_MASK if enabled else 0
	body_shape.set_deferred("disabled", not enabled)
	hit_area.collision_layer = GameAuthority.COLLISION_LAYER_TOOL if enabled else 0
	hit_area.collision_mask = GameAuthority.COLLISION_LAYER_BULLET if enabled else 0
	hit_area.set_deferred("monitoring", enabled)
	hit_area.set_deferred("monitorable", enabled)
	hit_shape.set_deferred("disabled", not enabled)


func _update_health_label() -> void:
	if not is_instance_valid(health_label):
		return
	health_label.visible = activated and current_hp > 0.0
	health_label.text = "HP: %d / %d" % [ceili(current_hp), ceili(max_hp)]
