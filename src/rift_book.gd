extends Node3D
class_name RiftBookTool

var owner_node: Node3D
var anchor_id := ""


func _ready() -> void:
	owner_node = get_parent().get_parent().get_parent() if get_parent() != null else null


func emit() -> void:
	# RiftBook is executed through GameAuthority like every other handheld tool.
	# This method only keeps legacy local test scenes compatible.
	return


func set_anchor_state(id: String) -> void:
	anchor_id = id
