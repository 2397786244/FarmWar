extends Node3D
class_name LongSpearTool

## LongSpear damage is resolved exclusively by GameAuthority.  This method is
## intentionally presentation-only so the scene remains compatible with the
## shared handheld-tool interface without creating a client-side damage path.
@export var tool_owner := ""


func emit() -> void:
	pass
