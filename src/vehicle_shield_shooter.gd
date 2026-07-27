extends Node3D
class_name VehicleShieldShooterTool

@onready var muzzle_flash: GPUParticles3D = $Muzzle/MuzzleFlash


func emit() -> void:
	play_muzzle_visual()


func play_muzzle_visual() -> void:
	if is_instance_valid(muzzle_flash):
		muzzle_flash.restart()
