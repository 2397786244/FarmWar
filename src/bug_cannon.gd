extends Node3D
class_name BugCannon

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
	#$Emitter.restart()
	## 发射一颗炮弹
	var boom = load("res://character/weapons/BugBoom.tscn").instantiate() as BugBoom
	if not GlobalVar.gameworld:
		return
	if boom == null:
		return
	GlobalVar.gameworld.add_child(boom)
	# GameAuthority owns the local-authority storm; this instance only supplies
	# the missing projectile flight visual.
	boom.visual_only = GameAuthority.is_local_authority()
	var vec = ($RayCast3D.to_global($RayCast3D.target_position) - $RayCast3D.global_position).normalized() * 30
	boom.run($RayCast3D.global_position,vec,"blue")
