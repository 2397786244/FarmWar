extends Node3D
class_name SpicyBlaster

const CombatBalance = preload("res://src/combat_balance.gd")
const BULLET_SCENE := preload("res://character/weapons/SpicyBullet.tscn")

@export var tool_owner := ""


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
