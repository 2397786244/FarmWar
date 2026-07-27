extends Node3D
class_name WreckTool

@export var  tool_owner :String = ""
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func emit():
	if tool_owner == "":
		return
	$Emitter.restart()
	## 发射一颗炮弹
	var boom = load("res://character/weapons/boom.tscn").instantiate()
	if not GlobalVar.gameworld:
		return
	GlobalVar.gameworld.add_child(boom)
	var vec = ($RayCast3D.to_global($RayCast3D.target_position) - $RayCast3D.global_position).normalized() * 30
	boom.run($RayCast3D.global_position,vec,tool_owner)
