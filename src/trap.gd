extends StaticBody3D
class_name TrapTool

signal authority_trigger_requested(trap: TrapTool, body: Node3D)

@export var tool_owner := ""
@export var damage := 200.0
@export var closed_hold_seconds := 2.0
@export var close_duration := 0.12

var triggered := false
var activated := false
var server_authority_simulation := false
var jaw_left: Node3D
var jaw_right: Node3D
var trigger_area: Area3D


func _ready() -> void:
	jaw_left = find_child("Jaw_Left", true, false) as Node3D
	jaw_right = find_child("Jaw_Right", true, false) as Node3D
	trigger_area = get_node_or_null("TriggerArea") as Area3D
	if trigger_area != null and not trigger_area.body_entered.is_connected(_on_body_entered):
		trigger_area.body_entered.connect(_on_body_entered)
	_set_detection_enabled(false)
	

func activate_tool() -> void:
	activated = true
	_set_detection_enabled(not GameAuthority.is_client_proxy() and not triggered)


func set_server_authority_simulation(enabled: bool) -> void:
	server_authority_simulation = enabled
	_set_detection_enabled(activated and enabled and not triggered)


func apply_network_triggered() -> void:
	_trigger_visual(false)


func _on_body_entered(body: Node3D) -> void:
	if not activated or triggered or GameAuthority.is_client_proxy():
		return
	if not body is GamePlayer and not body is VehicleBase \
			and not body is BlackBear and not body is FarmLivestock \
			and GameAuthority.get_authority_player_peer_id(body) <= 0:
		return
	if GameAuthority.trigger_trap(self, body, damage, tool_owner):
		_trigger_visual(true)


func _trigger_visual(expire_authority: bool) -> void:
	if triggered:
		return
	triggered = true
	_set_detection_enabled(false)
	var tween := create_tween().set_parallel(true)
	if is_instance_valid(jaw_left):
		tween.tween_property(jaw_left, "rotation_degrees:z", -80.0, close_duration) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if is_instance_valid(jaw_right):
		tween.tween_property(jaw_right, "rotation_degrees:z", 80.0, close_duration) \
			.set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	if expire_authority:
		get_tree().create_timer(closed_hold_seconds).timeout.connect(_expire_authority)


func _expire_authority() -> void:
	if GameAuthority.is_server_authority() or GameAuthority.is_local_authority():
		GameAuthority.expire_trap(self)
	if is_instance_valid(self):
		queue_free()


func _set_detection_enabled(enabled: bool) -> void:
	if trigger_area == null:
		return
	trigger_area.set_deferred("monitoring", enabled)
	trigger_area.set_deferred("monitorable", false)
