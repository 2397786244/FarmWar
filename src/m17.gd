extends NailFirearmTool
class_name M17Tool

const FLASHLIGHT_RANGE := 15.0
const FLASHLIGHT_ANGLE := 35.0
const FLASHLIGHT_ENERGY := 5.0
const FLASHLIGHT_COLOR := Color(1.0, 0.97, 0.88, 1.0)

@onready var flashlight_glow: Node3D = _find_flashlight_glow()
@onready var flashlight_light: SpotLight3D = get_node_or_null("Light/FlashlightLight") as SpotLight3D

var flashlight_on := false


func _ready() -> void:
	super._ready()
	if is_instance_valid(flashlight_light):
		flashlight_light.light_color = FLASHLIGHT_COLOR
		flashlight_light.light_energy = FLASHLIGHT_ENERGY
		flashlight_light.spot_range = FLASHLIGHT_RANGE
		flashlight_light.spot_angle = FLASHLIGHT_ANGLE
		flashlight_light.shadow_enabled = false
	set_flashlight_enabled(false)


func toggle_flashlight() -> bool:
	set_flashlight_enabled(not flashlight_on)
	return flashlight_on


func set_flashlight_enabled(enabled: bool) -> void:
	flashlight_on = enabled
	if is_instance_valid(flashlight_glow):
		flashlight_glow.visible = enabled
	if is_instance_valid(flashlight_light):
		flashlight_light.visible = enabled


func is_flashlight_on() -> bool:
	return flashlight_on


func _find_flashlight_glow() -> Node3D:
	var mesh_root := get_node_or_null("Mesh")
	return _find_named_descendant(mesh_root, "FlashlightGlow")


func _find_named_descendant(root: Node, wanted_name: String) -> Node3D:
	if root == null:
		return null
	if root.name == wanted_name and root is Node3D:
		return root as Node3D
	for child: Node in root.get_children():
		var match := _find_named_descendant(child, wanted_name)
		if match != null:
			return match
	return null
