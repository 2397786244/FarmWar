extends Node3D
class_name EmotionController

enum EmotionType {
	NEUTRAL,
	HAPPY,
	ANGRY,
	SURPRISED,
	FUNNY
}

var parts: Dictionary = {}
var defaults: Dictionary = {}

var part_names := [
	"LeftEye",
	"RightEye",
	"LeftBrow",
	"RightBrow",
	"MouthLeft",
	"MouthCenter",
	"MouthRight",
	"FunnyTongue"
]

func _ready() -> void:
	pass
	#for part_name in part_names:
		#var node := $"../CharacterSkeleton".find_child(part_name, true, false) as Node3D
		#if node:
			#parts[part_name] = node
			#defaults[part_name] = {
				#"transform": node.transform,
				#"visible": node.visible
			#}
#
	#set_expression(EmotionType.NEUTRAL)


func reset_face() -> void:
	for part_name in parts:
		var node: Node3D = parts[part_name]
		node.transform = defaults[part_name]["transform"]
		node.visible = defaults[part_name]["visible"]

	# 舌头只在滑稽表情中显示
	if parts.has("FunnyTongue"):
		parts["FunnyTongue"].visible = false


func set_expression(expression: EmotionType) -> void:
	reset_face()

	match expression:
		EmotionType.NEUTRAL:
			pass

		EmotionType.HAPPY:
			parts["LeftBrow"].position.y += 0.015
			parts["RightBrow"].position.y += 0.015

			parts["MouthLeft"].rotation.z += deg_to_rad(18)
			parts["MouthRight"].rotation.z -= deg_to_rad(18)

		EmotionType.ANGRY:
			parts["LeftEye"].scale.y *= 0.65
			parts["RightEye"].scale.y *= 0.65

			parts["LeftBrow"].rotation.z -= deg_to_rad(22)
			parts["RightBrow"].rotation.z += deg_to_rad(22)

			parts["LeftBrow"].position.y -= 0.015
			parts["RightBrow"].position.y -= 0.015

			parts["MouthLeft"].rotation.z -= deg_to_rad(15)
			parts["MouthRight"].rotation.z += deg_to_rad(15)

		EmotionType.SURPRISED:
			parts["LeftEye"].scale *= Vector3(1.25, 1.35, 1.0)
			parts["RightEye"].scale *= Vector3(1.25, 1.35, 1.0)

			parts["LeftBrow"].position.y += 0.025
			parts["RightBrow"].position.y += 0.025

			parts["MouthCenter"].scale *= Vector3(1.15, 1.8, 1.0)
		
		EmotionType.FUNNY:
			parts["LeftEye"].scale.y *= 0.45
			parts["RightEye"].scale *= Vector3(1.25, 1.25, 1.0)

			parts["LeftBrow"].rotation.z += deg_to_rad(15)
			parts["RightBrow"].rotation.z += deg_to_rad(25)

			parts["FunnyTongue"].visible = true

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
