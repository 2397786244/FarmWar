extends Node3D
class_name RepairWelderTool

@onready var welding_flame: GPUParticles3D = $Muzzle/WeldingFlame


func emit() -> void:
	play_muzzle_visual()


func play_muzzle_visual() -> void:
	if not is_instance_valid(welding_flame):
		return
	welding_flame.restart()
