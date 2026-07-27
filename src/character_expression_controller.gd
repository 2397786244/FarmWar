extends Node3D
class_name CharacterExpressionController

const EXPRESSIONS: PackedStringArray = [
	"Calm",
	"Fierce",
	"Funny",
	"Happy",
	"Worried",
]

@export_enum("Calm", "Fierce", "Funny", "Happy", "Worried")
var initial_expression: String = "Calm"

var current_expression: String = "Calm"


func _ready() -> void:
	set_expression(initial_expression)


## Sets one coordinated facial expression on every facial MeshInstance3D.
## Returns false when the requested expression is unsupported or no matching
## blend shape exists below this node.
func set_expression(expression_name: String) -> bool:
	if not EXPRESSIONS.has(expression_name):
		push_warning("Unsupported character expression: %s" % expression_name)
		return false

	var changed := false
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := child as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		var mesh := mesh_instance.mesh
		for blend_index in range(mesh.get_blend_shape_count()):
			var blend_name := String(mesh.get_blend_shape_name(blend_index))
			if not EXPRESSIONS.has(blend_name):
				continue
			mesh_instance.set_blend_shape_value(
				blend_index,
				1.0 if blend_name == expression_name else 0.0
			)
			changed = true

	if changed:
		current_expression = expression_name
	return changed


func reset_expression() -> bool:
	return set_expression("Calm")
