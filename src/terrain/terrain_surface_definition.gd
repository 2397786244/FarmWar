@tool
class_name TerrainSurfaceDefinition
extends Resource

@export_range(0, 255, 1) var surface_id: int = 0
@export var display_name: String = "Surface"
@export_color_no_alpha var color: Color = Color.WHITE
@export_range(0.0, 1.0, 0.01) var roughness: float = 0.9

# Reserved for later gameplay systems. The terrain renderer does not read these yet.
@export var footstep_type: StringName = &""
@export_range(0.1, 2.0, 0.05) var movement_speed_multiplier: float = 1.0
