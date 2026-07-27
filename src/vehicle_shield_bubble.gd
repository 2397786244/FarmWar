extends Node3D
class_name VehicleShieldBubble

const TOOL_COLLISION_LAYER := 128

@onready var shield_mesh: MeshInstance3D = $ShieldMesh
@onready var golden_edge_glow: MeshInstance3D = $GoldenEdgeGlow
@onready var hit_area: Area3D = $Hit3D
@onready var hit_shape: CollisionShape3D = $Hit3D/CollisionShape3D
@onready var remaining_label: Label3D = $RemainingLabel


func configure(coverage_size: Vector3, center_offset: Vector3) -> void:
	position = center_offset
	var radius := maxf(1.0, coverage_size.length() * 0.5 + 0.35)
	shield_mesh.scale = Vector3.ONE * radius
	golden_edge_glow.scale = Vector3.ONE * (radius * 1.018)
	hit_area.scale = Vector3.ONE * radius
	remaining_label.position = Vector3.UP * (radius + 0.55)


func set_state(seconds: float, current_hp: float, max_hp: float) -> void:
	visible = seconds > 0.0 and current_hp > 0.0
	var collision_active := visible and not GameAuthority.should_send_network_requests()
	hit_area.collision_layer = TOOL_COLLISION_LAYER if collision_active else 0
	hit_area.monitorable = collision_active
	hit_shape.set_deferred("disabled", not collision_active)
	if visible:
		remaining_label.text = "护盾 %d / %d HP\n剩余 %ds" % [
			ceili(current_hp), ceili(max_hp), ceili(seconds),
		]


func pulse_impact() -> void:
	if not visible:
		return
	var tween := create_tween()
	shield_mesh.modulate = Color(1.0, 1.0, 1.0, 0.9)
	tween.tween_property(shield_mesh, "modulate", Color.WHITE, 0.18)
