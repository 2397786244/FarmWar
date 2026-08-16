extends Node3D
class_name SpicyBlaster

const CombatBalance = preload("res://src/combat_balance.gd")
const BULLET_SCENE := preload("res://character/weapons/SpicyBullet.tscn")

@export var tool_owner := ""

@onready var model: Node3D = $Mesh

var model_rest_position := Vector3.ZERO


func _ready() -> void:
	model_rest_position = model.position


func emit() -> void:
	if tool_owner.is_empty() or not is_instance_valid(GlobalVar.gameworld):
		return
	var bullet := BULLET_SCENE.instantiate() as SpicyBullet
	if bullet == null:
		return
	GlobalVar.gameworld.add_child(bullet)
	bullet.speed = CombatBalance.get_float("spicy_blaster", "projectile_speed")
	bullet.gravity_strength = CombatBalance.get_float("spicy_blaster", "projectile_gravity")
	bullet.max_lifetime = CombatBalance.get_float("spicy_blaster", "projectile_lifetime")
	bullet.max_distance = CombatBalance.get_float("spicy_blaster", "projectile_range")
	bullet.bullet_strength = CombatBalance.get_float("spicy_blaster", "projectile_strength")
	bullet.run($Muzzle.global_position, -$Muzzle.global_transform.basis.z, tool_owner)
	play_muzzle_visual()


func play_muzzle_visual() -> void:
	$Muzzle/MuzzleFlash.restart()
	_play_recoil()


func _play_recoil() -> void:
	if not is_instance_valid(model):
		return
	var tween := create_tween()
	var recoil_offset := CombatBalance.get_model_recoil_offset("spicy_blaster")
	model.position = model_rest_position + recoil_offset
	tween.tween_property(
		model, "position", model_rest_position, CombatBalance.MODEL_RECOIL_DURATION
	) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
