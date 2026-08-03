## FarmWar Runtime Map Editor V9 - single script prototype
## Target: Godot 4.6.x
## Usage:
##   1. Copy this file to the FarmWar project, for example:
##      res://src/editor/farmwar_runtime_map_editor.gd
##   2. Create an empty Node3D scene and attach this script to its root.
##   3. Run the scene. All editor nodes and UI are created at runtime.
##
## Implemented tools:
##   - Create a new map with a configurable size.
##   - Free-fly editor camera.
##   - Terrain raise/lower, smooth and flatten brushes.
##   - Surface-mask paint compatible with terrain_surface.gdshader.
##   - Explicit Ground StaticBody3D with chunked height collisions.

##   - Renderer-compatible terrain triangle winding with upward vertex normals,
##     palette-derived default ground, safety floor and terrain edge skirt.
##   - Runtime-editable surface palette: add, rename, recolor and remove surfaces.
##   - Manual grass brush using chunked MultiMesh (independent of surface color).
##   - Place existing FarmWar tree scenes.
##   - Place existing FarmWar ore scenes.
##   - Place giant-crop and wild-animal spawn points.
##   - Visual building asset browser for all res://buildings scenes except nature/.
##   - Building placement with slope validation and live scene preview.
##   - Unified object selection with runtime XYZ move gizmo, three-axis rotation,
##     non-uniform XYZ scale, uniform scale, duplicate and delete for buildings,
##     trees, ores and spawn points.
##   - FarmWar map skeleton: fixed editor daylight, environment, clouds,
##     navigation, roads root, surface-area root, terrain baker, boundaries,
##     size-aware far scenery, TreeForestManager and manual grass.
##   - DayNightSystem is present in the packed gameplay map but disabled while
##     editing, so the editor lighting remains stable.
##   - Import a PNG map icon from the host filesystem, letterbox it to 128x128,
##     preview it, and save it as map_icon.png in the map package.
##   - CharacterBody3D editor camera rig colliding with terrain and boundaries.
##   - Red boundary walls/strips and a MAP BOUNDARY warning.
##   - Ctrl+Z / Cmd+Z undo and Ctrl+Y / Shift+Cmd+Z redo for terrain,
##     surface paint, grass chunks, placed resources/spawns and palette edits.
##   - New/Open/Save/Save As map-package workflow.
##   - Place configurable FarmFieldGenerator regions with editor-only previews.
##   - Visual continuous-road curve editor with draggable control points.
##   - Save generated map scene and authoritative editor data under user://maps/.
##
extends Node3D
class_name FarmWarRuntimeMapEditor


enum ToolMode {
	TERRAIN,
	SURFACE,
	GRASS,
	TREE,
	ORE,
	SPAWN,
	BUILDING,
	AUXILIARY,
	AI,
	OBJECT_EDIT,
	ROAD,
	WATER,
	FARMLAND,
}

enum ObjectTransformMode {
	MOVE,
	ROTATE,
	SCALE,
}

enum GizmoAxis {
	NONE,
	X,
	Y,
	Z,
	UNIFORM,
}

enum HeightMode {
	RAISE_LOWER,
	SMOOTH,
	FLATTEN,
}

enum TemplateMode {
	CRESTON_TOWN,
	REDPINE_COUNTY,
}


const TERRAIN_SHADER_PATH = "res://src/terrain/terrain_surface.gdshader"
const TERRAIN_BAKER_PATH = "res://src/terrain/terrain_surface_baker.gd"
const SURFACE_PALETTE_SCRIPT_PATH = "res://src/terrain/terrain_surface_palette.gd"
const SURFACE_DEFINITION_SCRIPT_PATH = "res://src/terrain/terrain_surface_definition.gd"
const ROAD_SCRIPT_PATH = "res://src/terrain/road_path_3d.gd"
const ROAD_TYPE_RAIL = 4
const TREE_FOREST_MANAGER_PATH = "res://src/tree_forest_manager.gd"
const FARM_INITIALIZER_PATH = "res://src/farm_init.gd"
# The shared scenery implementation was moved out of src/environment.  Keep
# the editor on the same script as the shipped maps; the old path silently
# produced a plain Node3D and therefore no distant ring at all.
const FAR_SCENERY_PATH = "res://src/far_scenery_ring_3d.gd"
const CLOUD_SYSTEM_PATH = "res://worlds/shared/cloud_system.tscn"
const DAY_NIGHT_SYSTEM_PATH = "res://worlds/shared/day_night_system.tscn"
const WEATHER_SYSTEM_PATH = "res://worlds/shared/weather_system.tscn"
const WATER_BODY_PATH = "res://worlds/shared/WaterBody3D.tscn"
const TEAM_SPAWN_POINT_PATH = "res://buildings/TeamSpawnPoint.tscn"
const MESSAGE_AREA_PATH = "res://buildings/auxiliary/MessageArea.tscn"
const NEUTRAL_CROP_GENERATOR_PATH = "res://buildings/auxiliary/NeutralCropGenerator.tscn"
const FARM_FIELD_GENERATOR_SCRIPT_PATH = "res://src/farm_field_generator.gd"
const FARM_FIELD_TILE_SPACING := 2.2
const POWER_POLE_PATH = "res://buildings/auxiliary/PowerPole.tscn"
const POWER_WIRE_SCRIPT_PATH = "res://src/power_wire_3d.gd"
const POWER_WIRE_ROOT_NAME = "PowerWires"
const MAP_ICON_FILE_NAME = "map_icon.png"
const EDITOR_OBJECTS_FILE_NAME = "editor_objects.dat"
const ROADS_FILE_NAME = "roads.dat"
const WATER_BODIES_FILE_NAME = "water_bodies.dat"
const SURFACE_PALETTE_FILE_NAME = "surface_palette.png"
const MAP_ICON_SIZE = 128
const FAR_SCENERY_GROUND_MARGIN = 768.0
const EDITOR_FAR_GROUND_ROOT_NAME = "_EditorGuaranteedFarGround"
const WILD_ANIMAL_GENERATOR_PATH = "res://src/wild_animal_generator.gd"
const RARE_RESOURCE_SPAWN_PATH = "res://buildings/nature/RareResourceSpawnPoint.tscn"
const SMALL_GRASS_PATH = "res://assets/environment/Grass_small.glb"
const TALL_GRASS_PATH = "res://assets/environment/Grass_tall.glb"
const BLACK_EYED_SUSAN_PATH = "res://assets/nature/Wildflower_BlackEyedSusan.glb"
const CONEFLOWER_PATH = "res://assets/nature/Wildflower_Coneflower.glb"
const FERN_CLUMP_PATH = "res://assets/nature/Fern_Clump.glb"
const MANUAL_GRASS_SPECIES := {
	"small": {"label": "Small Grass", "path": SMALL_GRASS_PATH, "scale": Vector2(0.85, 1.15), "visibility": 100.0},
	"tall": {"label": "Tall Grass", "path": TALL_GRASS_PATH, "scale": Vector2(0.85, 1.20), "visibility": 120.0},
	"black_eyed_susan": {"label": "Black-Eyed Susan", "path": BLACK_EYED_SUSAN_PATH, "scale": Vector2(0.85, 1.15), "visibility": 90.0},
	"coneflower": {"label": "Coneflower", "path": CONEFLOWER_PATH, "scale": Vector2(0.85, 1.15), "visibility": 90.0},
	"fern": {"label": "Fern Clump", "path": FERN_CLUMP_PATH, "scale": Vector2(0.80, 1.20), "visibility": 100.0},
}
const BUILDINGS_RESOURCE_ROOT = "res://buildings"
const BUILDINGS_EXCLUDED_ROOT = "res://buildings/nature"
const BUILDING_THUMBNAIL_SIZE = Vector2i(192, 128)
const BUILDING_BROWSER_CARD_SIZE = Vector2(172.0, 178.0)

const CRESTON_PALETTE_PATH = "res://worlds/creston_town/creston_town_surface_palette.tres"
const REDPINE_PALETTE_PATH = "res://worlds/redpine_county/redpine_county_surface_palette.tres"

const TERRAIN_COLLISION_LAYER = 1
const BOUNDARY_COLLISION_LAYER = 2
const WATER_COLLISION_LAYER = 65536
const WATER_COLLISION_MASK = 8 | 8192
const GRASS_CHUNK_SIZE = 32.0
const MAX_RAY_DISTANCE = 6000.0
const EDITOR_MARKER_META = &"farmwar_editor_visual_only"

const TREE_ASSETS = [
	{"label": "CottonWood", "path": "res://buildings/nature/CottonWood.tscn", "id": "cottonwood"},
	{"label": "Oak", "path": "res://buildings/nature/Oak.tscn", "id": "oak"},
	{"label": "Redcedar", "path": "res://buildings/nature/Redcedar.tscn", "id": "redcedar"},
	{"label": "RedMaple", "path": "res://buildings/nature/RedMaple.tscn", "id": "redmaple"},
]

const ORE_ASSETS = [
	{"label": "Iron Ore", "path": "res://items/IronOre.tscn", "id": "iron_ore"},
	{"label": "Coal Ore", "path": "res://items/CoalOre.tscn", "id": "coal_ore"},
	{"label": "Limestone Ore", "path": "res://items/LimestoneOre.tscn", "id": "limestone_ore"},
	{"label": "Copper Ore", "path": "res://items/CopperOre.tscn", "id": "copper_ore"},
	{"label": "Moss Rock", "path": "res://items/MossRock.tscn", "id": "moss_rock"},
	{"label": "Granite Rock", "path": "res://items/GraniteRock.tscn", "id": "granite_rock"},
	{"label": "Normal Mushroom", "path": "res://items/NormalMushroom.tscn", "id": "normal_mushroom"},
	{"label": "Bolete Mushroom", "path": "res://items/BoleteMushroom.tscn", "id": "bolete_mushroom"},
	{"label": "Red-White Mushroom", "path": "res://items/RedWhiteMushroom.tscn", "id": "redwhite_mushroom"},
	{"label": "Truffle", "path": "res://items/Truffle.tscn", "id": "truffle"},
]

const AI_TYPES := [
	{"id": "farmer", "label": "FarmerAI", "scene": "res://character/FarmerAI.tscn"},
	{"id": "futurewarrior", "label": "FutureWarriorAI", "scene": "res://character/FutureWarriorAI.tscn"},
	{"id": "assistant", "label": "AssistantAI", "scene": "res://character/AssistantAI.tscn"},
]

const FALLBACK_SURFACES = [
	{"label": "Grass", "id": 0, "color": Color("75a94b")},
	{"label": "Soil", "id": 1, "color": Color("875f3d")},
	{"label": "Asphalt", "id": 2, "color": Color("55585c")},
	{"label": "Gravel", "id": 3, "color": Color("9b927d")},
]


@export_category("Startup")
@export var create_default_map_on_ready = true
@export var default_map_name = "NewFarmMap"
@export var default_map_size = Vector2i(256, 256)
@export var default_template = TemplateMode.CRESTON_TOWN

@export_category("Terrain")
@export_range(0.25, 4.0, 0.25) var vertex_spacing = 1.0
@export_range(8, 64, 1) var terrain_chunk_cells = 32
@export_range(128, 2048, 128) var surface_mask_resolution = 1024
@export var initial_ground_height = 0.5
@export var minimum_terrain_height = -40.0
@export var maximum_terrain_height = 120.0
@export_range(0.1, 8.0, 0.1) var camera_ground_clearance = 1.5
@export_range(0.0, 16.0, 0.25) var camera_boundary_margin = 1.0
@export_range(1.0, 32.0, 1.0) var foundation_depth_below_minimum = 8.0
@export_range(0.05, 2.0, 0.05) var boundary_warning_strip_height = 0.25

@export_category("Object Placement")
@export var align_placed_objects_to_surface_normal = true
@export_range(0.0, 2.0, 0.01) var placed_object_ground_offset = 0.02

@export_category("Building Placement")
@export_range(0.0, 45.0, 0.5) var building_max_slope_degrees = 12.0
@export_range(1.0, 90.0, 1.0) var building_rotation_step_degrees = 15.0
@export_range(0.0, 2.0, 0.01) var building_ground_offset = 0.02
@export_range(0.0, 4.0, 0.05) var building_overlap_margin = 0.15
@export var building_overlap_checks_resources = true
@export_range(0.05, 0.95, 0.05) var building_preview_transparency = 0.55

@export_category("Object Editing")
@export_range(0.01, 5.0, 0.01) var object_move_snap = 0.25
@export_range(1.0, 90.0, 1.0) var object_rotation_snap_degrees = 15.0
@export_range(8.0, 96.0, 1.0) var object_pick_radius_px = 36.0
@export_range(4.0, 32.0, 1.0) var gizmo_pick_radius_px = 12.0
@export_range(0.01, 1.0, 0.01) var object_scale_snap = 0.05
@export_range(0.01, 1.0, 0.01) var object_minimum_scale = 0.05
@export_range(1.0, 100.0, 0.5) var object_maximum_scale = 30.0

@export_category("Far Scenery")
@export var force_guaranteed_far_ground = true
@export_range(500.0, 20000.0, 100.0) var editor_far_visibility_distance = 6000.0

@export_category("Road Editor")
@export_range(0.25, 4.0, 0.05) var road_mesh_sample_spacing = 1.0
@export_range(64, 4096, 1) var road_max_mesh_samples = 768
@export_range(-0.1, 1.0, 0.01) var road_default_vertical_offset = 0.06
@export_range(0.5, 4.0, 0.1) var road_control_point_pick_radius_px = 18.0
@export_range(1.0, 30.0, 0.5) var road_selection_world_distance = 8.0

@export_category("Map Package")
@export var default_map_version = "1.0.0"

@export_category("Storage")
@export var map_save_root = "user://maps"


# Current map data. Height and surface-mask data are authoritative; generated
# meshes and collision shapes are derived from them.
var _map_root: Node3D
# _map_name is kept as the internal folder/scene identifier for compatibility.
var _map_name = ""
var _map_id = ""
var _display_name = ""
var _map_version = "1.0.0"
var _current_map_folder = ""
var _map_size = Vector2.ZERO
var _terrain_origin = Vector2.ZERO
var _sample_width = 0
var _sample_depth = 0
var _height_samples = PackedFloat32Array()
var _surface_mask_image: Image
var _surface_mask_texture: ImageTexture
var _surface_palette_resource: Resource
var _surface_palette_lookup: Texture2D
# Editable runtime copy. Array order matters: entry 0 is the default map surface.
var _surface_entries: Array = []
var _terrain_material: ShaderMaterial
var _template_mode = TemplateMode.CRESTON_TOWN

# Generated map roots.
var _ground_body: StaticBody3D
var _terrain_root: Node3D
var _boundary_root: Node3D
var _surface_areas_root: Node3D
var _roads_root: Node3D
var _water_root: Node3D
var _manual_grass_root: Node3D
var _trees_root: Node3D
var _ores_root: Node3D
var _spawns_root: Node3D
var _buildings_root: Node3D
var _farmlands_root: Node3D
var _power_wires_root: Node3D
var _tree_forest_manager: Node3D
var _far_scenery_ring: Node3D
var _terrain_baker: Node3D
var _terrain_foundation_root: Node3D
var _terrain_skirt_mesh: MeshInstance3D
var _ground_safety_mesh: MeshInstance3D
var _day_night_system: Node
var _weather_system: Node

# Terrain chunks and collision shapes keyed by Vector2i.
var _terrain_chunks: Dictionary = {}
var _terrain_collision_shapes: Dictionary = {}
var _collision_dirty_chunks: Dictionary = {}

# Manual grass data:
# {
#   "small": {"x:z": Array[Transform3D]},
#   "tall":  {"x:z": Array[Transform3D]}, plus other species keys.
# }
var _manual_grass = {
	"small": {},
	"tall": {},
	"black_eyed_susan": {},
	"coneflower": {},
	"fern": {},
}
var _grass_generated_nodes: Dictionary = {}
var _grass_mesh_cache: Dictionary = {}

# Editor state.
var _tool_mode = ToolMode.TERRAIN
var _height_mode = HeightMode.RAISE_LOWER
var _selected_surface_id = 0
var _selected_grass_species = "small"
var _selected_asset: Dictionary = TREE_ASSETS[0]
var _selected_spawn_kind = "giant_crop"
var _selected_team_spawn_team := "red"
var _selected_auxiliary_kind := "message_area"
var _selected_neutral_crop_id := "wheat"
var _neutral_crop_area_size := Vector2(16.0, 16.0)
var _neutral_crop_respawn_interval := 120.0
var _neutral_crop_initial_delay := 0.0
var _neutral_crop_show_boundary := true
var _neutral_crop_boundary_color := Color(0.95, 0.85, 0.25, 1.0)
var _farmland_length_tiles := 16
var _farmland_width_tiles := 16
var _selected_farmland_owner := ""
var _ai_configurations: Array = []
var _selected_ai_index := -1
var _brush_radius = 8.0
var _brush_strength = 2.5
var _grass_density = 0.15
var _placement_interval = 0.18
var _placement_timer = 0.0
var _stroke_active = false
var _stroke_placed_once = false
var _flatten_target_height = 0.0
var _latest_hit = {}
var _rng = RandomNumberGenerator.new()
var _next_object_id = 1
var _next_spawn_id = 1

# Building browser and placement state. Assets are discovered at runtime, so
# newly added building scenes automatically appear without editing this file.
var _building_assets: Array[Dictionary] = []
var _filtered_building_assets: Array[Dictionary] = []
var _building_categories: PackedStringArray = PackedStringArray(["All"])
var _selected_building_asset: Dictionary = {}
var _building_search_text = ""
var _building_category_filter = "All"
var _building_preview: Node3D
var _building_preview_yaw = 0.0
var _building_preview_valid = false
var _building_preview_block_reason = ""
var _building_footprint_fill: MeshInstance3D
var _building_footprint_fill_mesh: ImmediateMesh
var _building_footprint_fill_material: StandardMaterial3D
var _building_footprint_outline: MeshInstance3D
var _building_footprint_outline_mesh: ImmediateMesh
var _building_footprint_outline_material: StandardMaterial3D
var _building_search_edit: LineEdit
var _building_category_option: OptionButton
var _building_count_label: Label
var _building_grid: GridContainer
var _building_thumbnail_cards: Dictionary = {}
var _building_thumbnail_cache: Dictionary = {}
var _building_thumbnail_queue: Array[String] = []
var _building_thumbnail_rendering = false
var _thumbnail_viewport: SubViewport
var _thumbnail_viewport_texture: ViewportTexture
var _thumbnail_scene_root: Node3D
var _thumbnail_camera: Camera3D

# Unified object transform state.
var _object_transform_mode = ObjectTransformMode.MOVE
var _selected_map_object: Node3D
var _object_dragging = false
var _object_drag_before_transform = Transform3D.IDENTITY
var _object_drag_start_global_transform = Transform3D.IDENTITY
var _object_drag_start_mouse = Vector2.ZERO
var _object_drag_start_parameter = 0.0
var _object_drag_start_vector = Vector3.ZERO
var _object_drag_plane_normal = Vector3.UP
var _object_drag_axis_world = Vector3.ZERO
var _object_drag_axis = GizmoAxis.NONE
var _object_transform_valid = true
var _gizmo_local_space = true
var _selection_visual: MeshInstance3D
var _selection_visual_mesh: ImmediateMesh
var _object_gizmo: MeshInstance3D
var _object_gizmo_mesh: ImmediateMesh
var _object_gizmo_material: StandardMaterial3D
var _selection_status_label: Label
var _object_move_button: Button
var _object_rotate_button: Button
var _object_scale_button: Button
var _object_delete_button: Button
var _object_duplicate_button: Button
var _object_local_axes_check: CheckBox
var _object_x_spin: SpinBox
var _object_y_spin: SpinBox
var _object_z_spin: SpinBox
var _object_rot_x_spin: SpinBox
var _object_rot_y_spin: SpinBox
var _object_rot_z_spin: SpinBox
var _object_scale_x_spin: SpinBox
var _object_scale_y_spin: SpinBox
var _object_scale_z_spin: SpinBox
var _object_uniform_scale_spin: SpinBox

# Continuous road editor state.
var _selected_road: Path3D
var _road_drawing_active = false
var _road_selected_point = -1
var _road_dragging = false
var _road_drag_before: Dictionary = {}
var _road_type = 1
var _road_width_override = 0.0
var _road_vertical_offset = 0.06
var _road_edit_visual_root: Node3D
var _road_marker_root: Node3D
var _road_centerline: MeshInstance3D
var _road_centerline_mesh: ImmediateMesh
var _road_preview_line: MeshInstance3D
var _road_preview_mesh: ImmediateMesh
var _road_list_option: OptionButton
var _road_type_option: OptionButton
var _road_width_spin: SpinBox
var _road_offset_spin: SpinBox
var _road_finish_button: Button
var _road_delete_point_button: Button
var _road_conform_button: Button
var _road_delete_button: Button

# Water body editor state. Lake outlines are drawn as closed polygons; river
# centerlines are converted into a strip by WaterBody3D using river_width.
var _selected_water: WaterBody3D
var _water_body_type := WaterBody3D.BodyType.LAKE
var _water_drawing_active := false
var _water_points := PackedVector2Array()
var _water_preview_root: Node3D
var _water_preview_mesh: ImmediateMesh
var _water_preview_line: MeshInstance3D
var _water_marker_root: Node3D
var _water_level := 0.5
var _water_depth := 2.0
var _water_width := 6.0
var _water_type_option: OptionButton
var _water_level_spin: SpinBox
var _water_depth_spin: SpinBox
var _water_width_spin: SpinBox
var _water_finish_button: Button
var _water_cancel_button: Button
var _water_delete_button: Button
var _water_list_option: OptionButton
var _water_history_guard := false

# Runtime undo/redo. A drag from mouse-down to mouse-up is one action.
var _undo_redo = UndoRedo.new()
var _saved_undo_version = 0
var _stroke_tool_mode = ToolMode.TERRAIN
var _stroke_height_before: Dictionary = {}
var _stroke_surface_before: Dictionary = {}
var _stroke_grass_before: Dictionary = {}
var _stroke_added_objects: Array[Dictionary] = []
var _stroke_removed_objects: Array[Dictionary] = []
var _palette_history_guard = false

# Editor camera.
var _camera_rig: CharacterBody3D
var _editor_camera: Camera3D
var _camera_yaw = 0.0
var _camera_pitch = deg_to_rad(-35.0)
var _camera_speed = 28.0
var _camera_look_active = false

# Brush visual.
var _brush_preview: MeshInstance3D
var _brush_preview_mesh: ImmediateMesh
var _brush_preview_material: StandardMaterial3D
var _farmland_cursor_preview: Node3D
var _height_boundary_preview: MeshInstance3D
var _height_boundary_mesh: ImmediateMesh
var _height_boundary_material: StandardMaterial3D
var _height_contour_points := PackedVector2Array()
var _height_contour_delta := 0.0
var _persistent_height_contour_preview: MeshInstance3D
var _persistent_height_contour_mesh: ImmediateMesh
var _persistent_height_contour_material: StandardMaterial3D
var _persistent_height_contour_visible := false

# UI references.
var _ui_layer: CanvasLayer
var _ui_root: Control
var _bottom_content: Container
var _building_browser_content: VBoxContainer
var _right_content: VBoxContainer
var _brush_settings_grid: GridContainer
var _building_selected_info_label: Label
var _bottom_dock_panel: PanelContainer
var _right_dock_panel: PanelContainer
var _left_toolbar_panel: PanelContainer
var _status_label: Label
var _tool_title_label: Label
var _radius_label: Label
var _strength_label: Label
var _map_name_edit: LineEdit
var _map_width_spin: SpinBox
var _map_depth_spin: SpinBox
var _template_option: OptionButton
var _map_id_edit: LineEdit
var _map_version_edit: LineEdit
var _icon_preview: TextureRect
var _icon_status_label: Label
var _icon_file_dialog: FileDialog
var _open_map_file_dialog: FileDialog
var _save_as_directory_dialog: FileDialog
var _export_directory_dialog: FileDialog
var _discard_changes_dialog: ConfirmationDialog
var _pending_destructive_action: Callable
var _boundary_warning_label: Label
var _boundary_warning_until_msec = 0
var _map_icon_image: Image
var _map_icon_texture: ImageTexture
var _map_icon_source_path = ""
var _tool_buttons: Dictionary = {}
var _last_save_succeeded := false


func _ready() -> void:
	_rng.randomize()
	_undo_redo.max_steps = 100
	_build_editor_camera()
	_build_brush_preview()
	_build_farmland_cursor_preview()
	_build_selection_visual()
	_build_transform_gizmo()
	_build_building_footprint_preview()
	_build_thumbnail_renderer()
	_scan_building_assets()
	_build_editor_ui()
	set_process(true)
	set_physics_process(true)

	if create_default_map_on_ready:
		call_deferred("_create_map_from_ui")


func _exit_tree() -> void:
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# -----------------------------------------------------------------------------
# Editor UI
# -----------------------------------------------------------------------------

func _build_editor_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.name = "MapEditorUI"
	_ui_layer.layer = 100
	add_child(_ui_layer)

	_ui_root = Control.new()
	_ui_root.name = "Root"
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_ui_root)

	_build_top_bar()
	_build_left_toolbar()
	_build_right_dock()
	_build_bottom_dock()
	_build_boundary_warning_ui()
	_refresh_bottom_dock()

func _build_boundary_warning_ui() -> void:
	_boundary_warning_label = Label.new()
	_boundary_warning_label.name = "BoundaryWarning"
	_boundary_warning_label.text = "MAP BOUNDARY"
	_boundary_warning_label.visible = false
	_boundary_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boundary_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boundary_warning_label.add_theme_color_override(
		"font_color",
		Color(1.0, 0.08, 0.03, 1.0)
	)
	_boundary_warning_label.add_theme_color_override(
		"font_shadow_color",
		Color(0.0, 0.0, 0.0, 0.95)
	)
	_boundary_warning_label.add_theme_constant_override("shadow_offset_x", 2)
	_boundary_warning_label.add_theme_constant_override("shadow_offset_y", 2)
	_boundary_warning_label.add_theme_font_size_override("font_size", 30)
	_boundary_warning_label.anchor_left = 0.5
	_boundary_warning_label.anchor_right = 0.5
	_boundary_warning_label.offset_left = -180.0
	_boundary_warning_label.offset_right = 180.0
	_boundary_warning_label.offset_top = 112.0
	_boundary_warning_label.offset_bottom = 154.0
	_ui_root.add_child(_boundary_warning_label)


func _show_boundary_warning() -> void:
	_boundary_warning_until_msec = Time.get_ticks_msec() + 700
	if _boundary_warning_label != null:
		_boundary_warning_label.visible = true


func _build_top_bar() -> void:
	var panel = PanelContainer.new()
	panel.name = "TopBar"
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 100.0
	_ui_root.add_child(panel)

	var rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	panel.add_child(rows)

	var primary_row = HBoxContainer.new()
	primary_row.add_theme_constant_override("separation", 8)
	rows.add_child(primary_row)

	var title = Label.new()
	title.text = "FarmWar Runtime Map Editor"
	title.custom_minimum_size.x = 220.0
	primary_row.add_child(title)

	primary_row.add_child(_make_label("Display Name"))
	_map_name_edit = LineEdit.new()
	_map_name_edit.text = default_map_name
	_map_name_edit.custom_minimum_size.x = 150.0
	primary_row.add_child(_map_name_edit)

	primary_row.add_child(_make_label("Map ID"))
	_map_id_edit = LineEdit.new()
	_map_id_edit.placeholder_text = "auto_from_display_name"
	_map_id_edit.custom_minimum_size.x = 150.0
	primary_row.add_child(_map_id_edit)

	primary_row.add_child(_make_label("Width"))
	_map_width_spin = SpinBox.new()
	_map_width_spin.min_value = 32
	_map_width_spin.max_value = 2048
	_map_width_spin.step = 16
	_map_width_spin.value = default_map_size.x
	_map_width_spin.custom_minimum_size.x = 82.0
	primary_row.add_child(_map_width_spin)

	primary_row.add_child(_make_label("Depth"))
	_map_depth_spin = SpinBox.new()
	_map_depth_spin.min_value = 32
	_map_depth_spin.max_value = 2048
	_map_depth_spin.step = 16
	_map_depth_spin.value = default_map_size.y
	_map_depth_spin.custom_minimum_size.x = 82.0
	primary_row.add_child(_map_depth_spin)

	_template_option = OptionButton.new()
	_template_option.add_item("Creston Town", TemplateMode.CRESTON_TOWN)
	_template_option.add_item("Redpine County", TemplateMode.REDPINE_COUNTY)
	_template_option.select(default_template)
	_template_option.item_selected.connect(_on_template_selected)
	primary_row.add_child(_template_option)

	var new_button = Button.new()
	new_button.text = "New Map"
	new_button.tooltip_text = "Create a new map from the fields in this row."
	new_button.pressed.connect(_request_new_map)
	primary_row.add_child(new_button)

	var open_button = Button.new()
	open_button.text = "Open Map"
	open_button.tooltip_text = "Open a saved FarmWar map package by selecting map.json."
	open_button.pressed.connect(_request_open_map)
	primary_row.add_child(open_button)

	var return_button = Button.new()
	return_button.name = "ReturnToMainMenuButton"
	return_button.text = "返回主界面"
	return_button.tooltip_text = "返回 FarmWar 主界面。"
	return_button.custom_minimum_size = Vector2(148.0, 42.0)
	return_button.add_theme_font_size_override("font_size", 18)
	return_button.add_theme_color_override("font_color", Color.WHITE)
	return_button.add_theme_color_override("font_hover_color", Color.WHITE)
	return_button.add_theme_color_override("font_pressed_color", Color.WHITE)
	var return_normal := StyleBoxFlat.new()
	return_normal.bg_color = Color("8f3d3d")
	return_normal.corner_radius_top_left = 6
	return_normal.corner_radius_top_right = 6
	return_normal.corner_radius_bottom_left = 6
	return_normal.corner_radius_bottom_right = 6
	var return_hover := return_normal.duplicate() as StyleBoxFlat
	return_hover.bg_color = Color("bd5050")
	var return_pressed := return_normal.duplicate() as StyleBoxFlat
	return_pressed.bg_color = Color("d66a52")
	return_button.add_theme_stylebox_override("normal", return_normal)
	return_button.add_theme_stylebox_override("hover", return_hover)
	return_button.add_theme_stylebox_override("pressed", return_pressed)
	return_button.pressed.connect(_request_return_to_main_menu)
	primary_row.add_child(return_button)

	var package_row = HBoxContainer.new()
	package_row.add_theme_constant_override("separation", 8)
	rows.add_child(package_row)

	package_row.add_child(_make_label("Version"))
	_map_version_edit = LineEdit.new()
	_map_version_edit.text = default_map_version
	_map_version_edit.custom_minimum_size.x = 100.0
	package_row.add_child(_map_version_edit)

	var import_icon_button = Button.new()
	import_icon_button.text = "Import PNG Icon"
	import_icon_button.tooltip_text = "Choose any PNG image. It will be letterboxed onto black and saved as 128x128 map_icon.png."
	import_icon_button.pressed.connect(_open_icon_file_dialog)
	package_row.add_child(import_icon_button)

	_icon_preview = TextureRect.new()
	_icon_preview.custom_minimum_size = Vector2(44.0, 44.0)
	_icon_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	package_row.add_child(_icon_preview)

	_icon_status_label = Label.new()
	_icon_status_label.text = "No icon selected"
	_icon_status_label.custom_minimum_size.x = 210.0
	package_row.add_child(_icon_status_label)

	var save_button = Button.new()
	save_button.text = "Save"
	save_button.pressed.connect(save_current_map)
	package_row.add_child(save_button)

	var save_as_button = Button.new()
	save_as_button.text = "Save As"
	save_as_button.tooltip_text = "Choose a parent folder under user data; a map-id package folder is created inside it."
	save_as_button.pressed.connect(_open_save_as_dialog)
	package_row.add_child(save_as_button)

	var export_button = Button.new()
	export_button.text = "导出地图"
	export_button.tooltip_text = "将完整地图包复制到指定目录，例如游戏可执行文件旁的 maps 文件夹。"
	export_button.pressed.connect(_request_export_map)
	package_row.add_child(export_button)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	package_row.add_child(_status_label)

	_build_icon_file_dialog()
	_build_map_file_dialogs()


func _build_left_toolbar() -> void:
	var panel = PanelContainer.new()
	_left_toolbar_panel = panel
	panel.name = "LeftToolbar"
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 104.0
	panel.offset_left = 8.0
	panel.offset_right = 198.0
	panel.offset_bottom = -8.0
	_ui_root.add_child(panel)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var heading = Label.new()
	heading.text = "TOOLS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var group = ButtonGroup.new()
	_add_tool_button(column, group, ToolMode.TERRAIN, "Terrain", "Raise, lower, smooth or flatten terrain")
	_add_tool_button(column, group, ToolMode.SURFACE, "Surface Colors", "Paint and configure terrain surface colors")
	_add_tool_button(column, group, ToolMode.ROAD, "Roads", "Draw and edit continuous curve roads")
	_add_tool_button(column, group, ToolMode.WATER, "Water", "Draw irregular lakes and river centerlines")
	_add_tool_button(column, group, ToolMode.GRASS, "Grass", "Manual MultiMesh grass brush")
	_add_tool_button(column, group, ToolMode.TREE, "Trees", "Place complete harvestable tree scenes")
	_add_tool_button(column, group, ToolMode.ORE, "Ores & Mushrooms", "Place complete harvestable ore or mushroom scenes")
	_add_tool_button(column, group, ToolMode.SPAWN, "Spawn Points", "Team player spawns, giant crop or wild animal generators")
	_add_tool_button(column, group, ToolMode.BUILDING, "Buildings", "Browse and place scenes from res://buildings, excluding nature/")
	_add_tool_button(column, group, ToolMode.FARMLAND, "Farmland", "Place configurable FarmFieldGenerator regions")
	_add_tool_button(column, group, ToolMode.AUXILIARY, "Auxiliary", "Place tutorial message areas and helper volumes")
	_add_tool_button(column, group, ToolMode.AI, "AI Players", "Configure map AI players, teams, spawn points and respawn times")
	_add_tool_button(column, group, ToolMode.OBJECT_EDIT, "Transform Objects", "XYZ move, three-axis rotation and scale")

	(_tool_buttons[ToolMode.TERRAIN] as Button).button_pressed = true

	var help = Label.new()
	help.text = "LMB: use/select gizmo
RMB: camera look
WASD + Q/E: camera
G: move gizmo
R: rotate gizmo
S: scale gizmo
Delete: delete selected
Ctrl/Cmd+D: duplicate
Ctrl/Cmd+Z: undo
Ctrl/Cmd+S: save"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	column.add_child(help)

func _add_tool_button(
	parent: Control,
	group: ButtonGroup,
	mode: ToolMode,
	text: String,
	tooltip: String
) -> void:
	var button = Button.new()
	button.text = text
	button.toggle_mode = true
	button.button_group = group
	button.tooltip_text = tooltip
	button.pressed.connect(_select_tool.bind(mode))
	parent.add_child(button)
	_tool_buttons[mode] = button


func _build_right_dock() -> void:
	var panel = PanelContainer.new()
	_right_dock_panel = panel
	panel.name = "ToolInspectorDock"
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	# Keep the dock attached to the viewport's right edge.  Some inspector
	# controls have a larger minimum width; growing toward BEGIN prevents that
	# minimum size from pushing half of the dock beyond the right screen edge.
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.custom_minimum_size = Vector2(340.0, 0.0)
	panel.offset_left = -348.0
	panel.offset_right = -8.0
	panel.offset_top = 104.0
	panel.offset_bottom = -8.0
	_ui_root.add_child(panel)

	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	_tool_title_label = Label.new()
	_tool_title_label.text = "Terrain"
	_tool_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(_tool_title_label)

	_brush_settings_grid = GridContainer.new()
	_brush_settings_grid.columns = 2
	layout.add_child(_brush_settings_grid)

	_radius_label = Label.new()
	_radius_label.text = "Radius: %.1f m" % _brush_radius
	_radius_label.custom_minimum_size.x = 88.0
	_brush_settings_grid.add_child(_radius_label)
	var radius_slider = HSlider.new()
	radius_slider.min_value = 1.0
	radius_slider.max_value = 64.0
	radius_slider.step = 0.5
	radius_slider.value = _brush_radius
	radius_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	radius_slider.custom_minimum_size = Vector2(158.0, 26.0)
	radius_slider.value_changed.connect(_on_radius_changed)
	_brush_settings_grid.add_child(radius_slider)

	_strength_label = Label.new()
	_strength_label.text = "Strength: %.2f" % _brush_strength
	_strength_label.custom_minimum_size.x = 88.0
	_brush_settings_grid.add_child(_strength_label)
	var strength_slider = HSlider.new()
	strength_slider.min_value = 0.05
	strength_slider.max_value = 12.0
	strength_slider.step = 0.05
	strength_slider.value = _brush_strength
	strength_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	strength_slider.custom_minimum_size = Vector2(158.0, 26.0)
	strength_slider.value_changed.connect(_on_strength_changed)
	_brush_settings_grid.add_child(strength_slider)

	var separator = HSeparator.new()
	layout.add_child(separator)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)

	_right_content = VBoxContainer.new()
	_right_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_right_content.custom_minimum_size.x = 0.0
	_right_content.add_theme_constant_override("separation", 7)
	scroll.add_child(_right_content)

func _build_bottom_dock() -> void:
	var panel = PanelContainer.new()
	_bottom_dock_panel = panel
	panel.name = "BuildingAssetBrowserDock"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 206.0
	panel.offset_right = -338.0
	panel.offset_top = -338.0
	panel.offset_bottom = -8.0
	panel.visible = false
	_ui_root.add_child(panel)

	var layout = VBoxContainer.new()
	layout.add_theme_constant_override("separation", 6)
	panel.add_child(layout)

	var title = Label.new()
	title.text = "BUILDING ASSET BROWSER"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layout.add_child(title)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_building_browser_content = VBoxContainer.new()
	_building_browser_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_browser_content.add_theme_constant_override("separation", 6)
	scroll.add_child(_building_browser_content)

func _refresh_bottom_dock() -> void:
	if _right_content == null or _building_browser_content == null:
		return
	_configure_bottom_dock_for_tool()
	for child in _right_content.get_children():
		_right_content.remove_child(child)
		child.queue_free()
	for child in _building_browser_content.get_children():
		_building_browser_content.remove_child(child)
		child.queue_free()

	_bottom_content = _right_content
	match _tool_mode:
		ToolMode.TERRAIN:
			_tool_title_label.text = "Terrain Height"
			_add_height_mode_buttons()
		ToolMode.SURFACE:
			_tool_title_label.text = "Surface Colors"
			_add_surface_buttons()
		ToolMode.GRASS:
			_tool_title_label.text = "Manual Grass"
			_add_grass_buttons()
		ToolMode.TREE:
			_tool_title_label.text = "Trees"
			_add_asset_buttons(TREE_ASSETS)
		ToolMode.ORE:
			_tool_title_label.text = "Ores"
			_add_asset_buttons(ORE_ASSETS)
		ToolMode.SPAWN:
			_tool_title_label.text = "Spawn Points"
			_add_spawn_buttons()
		ToolMode.BUILDING:
			_tool_title_label.text = "Building Placement"
			_add_building_placement_controls()
			_bottom_content = _building_browser_content
			_add_building_browser()
		ToolMode.FARMLAND:
			_tool_title_label.text = "Farmland Placement"
			_add_farmland_controls()
		ToolMode.AUXILIARY:
			_tool_title_label.text = "Auxiliary Areas"
			_add_auxiliary_buttons()
		ToolMode.AI:
			_tool_title_label.text = "Map AI Players"
			_add_ai_configuration_controls()
		ToolMode.OBJECT_EDIT:
			_tool_title_label.text = "Object Transform"
			_add_object_edit_controls()
		ToolMode.ROAD:
			_tool_title_label.text = "Continuous Roads"
			_add_road_buttons()
		ToolMode.WATER:
			_tool_title_label.text = "Water Bodies"
			_add_water_buttons()
		_:
			_tool_title_label.text = "Unavailable"

func _configure_bottom_dock_for_tool() -> void:
	var building_mode = _tool_mode == ToolMode.BUILDING
	if _brush_settings_grid != null:
		_brush_settings_grid.visible = _tool_mode in [ToolMode.TERRAIN, ToolMode.SURFACE, ToolMode.GRASS, ToolMode.TREE, ToolMode.ORE, ToolMode.SPAWN, ToolMode.AUXILIARY]
	if _bottom_dock_panel != null:
		_bottom_dock_panel.visible = building_mode
	if _left_toolbar_panel != null:
		_left_toolbar_panel.offset_bottom = -346.0 if building_mode else -8.0
	if _right_dock_panel != null:
		_right_dock_panel.offset_bottom = -346.0 if building_mode else -8.0

func _add_height_mode_buttons() -> void:
	var group = ButtonGroup.new()
	for entry in [
		{"label": "Raise / Lower", "mode": HeightMode.RAISE_LOWER},
		{"label": "Smooth", "mode": HeightMode.SMOOTH},
		{"label": "Flatten", "mode": HeightMode.FLATTEN},
	]:
		var button = Button.new()
		button.text = entry["label"]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = int(entry["mode"]) == _height_mode
		button.pressed.connect(_select_height_mode.bind(int(entry["mode"])))
		_bottom_content.add_child(button)

	var hint = Label.new()
	hint.text = "Raise/Lower: hold Shift to lower. Flatten samples the height where each stroke begins."
	_bottom_content.add_child(hint)


func _add_surface_buttons() -> void:
	var surfaces = _read_surface_entries()
	var group = ButtonGroup.new()

	for entry_index in range(surfaces.size()):
		var entry = surfaces[entry_index] as Dictionary
		var surface_id = int(entry.get("id", 0))

		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(178.0, 92.0)
		_bottom_content.add_child(card)

		var column = VBoxContainer.new()
		column.add_theme_constant_override("separation", 3)
		card.add_child(column)

		var select_button = Button.new()
		select_button.text = "%s [ID %d]" % [
			str(entry.get("label", "Surface")),
			surface_id,
		]
		select_button.toggle_mode = true
		select_button.button_group = group
		select_button.button_pressed = surface_id == _selected_surface_id
		select_button.pressed.connect(_select_surface.bind(surface_id))
		column.add_child(select_button)

		var edit_row = HBoxContainer.new()
		edit_row.add_theme_constant_override("separation", 4)
		column.add_child(edit_row)

		var color_button = ColorPickerButton.new()
		color_button.color = entry.get("color", Color.WHITE) as Color
		color_button.edit_alpha = false
		color_button.custom_minimum_size = Vector2(48.0, 28.0)
		color_button.tooltip_text = "Change this terrain surface color"
		color_button.color_changed.connect(
			_on_surface_color_changed.bind(surface_id)
		)
		edit_row.add_child(color_button)

		var name_edit = LineEdit.new()
		name_edit.text = str(entry.get("label", "Surface"))
		name_edit.custom_minimum_size.x = 86.0
		name_edit.tooltip_text = "Rename this terrain surface"
		name_edit.text_submitted.connect(
			_on_surface_name_submitted.bind(surface_id)
		)
		name_edit.focus_exited.connect(
			_on_surface_name_focus_exited.bind(surface_id, name_edit)
		)
		edit_row.add_child(name_edit)

		var remove_button = Button.new()
		remove_button.text = "×"
		remove_button.tooltip_text = (
			"The first palette color is the base terrain and cannot be removed."
			if entry_index == 0
			else "Remove this surface and remap painted pixels to the base surface."
		)
		remove_button.disabled = entry_index == 0
		remove_button.pressed.connect(_remove_surface_entry.bind(surface_id))
		edit_row.add_child(remove_button)

	var add_button = Button.new()
	add_button.text = "+ Add Surface Color"
	add_button.tooltip_text = "Add another paintable terrain color (maximum 256 IDs)."
	add_button.pressed.connect(_add_surface_entry)
	_bottom_content.add_child(add_button)

	var hint = Label.new()
	hint.text = (
		"The first palette entry is the default color for the entire new map. "
		+ "LMB paints the selected color; Shift+LMB restores the first color."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 0.0
	_bottom_content.add_child(hint)


func _add_grass_buttons() -> void:
	var group = ButtonGroup.new()
	for species_value in MANUAL_GRASS_SPECIES.keys():
		var species := str(species_value)
		var definition := MANUAL_GRASS_SPECIES[species] as Dictionary
		var entry := {"label": str(definition.get("label", species)), "species": species}
		var button = Button.new()
		button.text = entry["label"]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = str(entry["species"]) == _selected_grass_species
		button.pressed.connect(_select_grass_species.bind(str(entry["species"])))
		_bottom_content.add_child(button)

	var density_label = Label.new()
	density_label.text = "Density"
	_bottom_content.add_child(density_label)

	var density = HSlider.new()
	density.min_value = 0.01
	density.max_value = 1.0
	density.step = 0.01
	density.value = _grass_density
	density.custom_minimum_size.x = 180.0
	density.value_changed.connect(func(value: float) -> void: _grass_density = value)
	_bottom_content.add_child(density)

	var hint = Label.new()
	hint.text = "Vegetation is stored as manually painted points and rebuilt into 32 m MultiMesh chunks. Shift+LMB erases the selected species."
	_bottom_content.add_child(hint)


func _add_asset_buttons(assets: Array) -> void:
	var group = ButtonGroup.new()
	for asset_value in assets:
		var asset = asset_value as Dictionary
		var button = Button.new()
		button.text = str(asset.get("label", "Asset"))
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = str(asset.get("path", "")) == str(_selected_asset.get("path", ""))
		button.tooltip_text = str(asset.get("path", ""))
		button.pressed.connect(_select_asset.bind(asset))
		_bottom_content.add_child(button)

	var hint = Label.new()
	hint.text = "LMB places complete FarmWar interaction scenes. Shift+LMB erases items inside the brush."
	_bottom_content.add_child(hint)


func _add_spawn_buttons() -> void:
	var group = ButtonGroup.new()
	for entry in [
		{"label": "Player Spawn Point", "kind": "player"},
		{"label": "Giant Crop Spawn", "kind": "giant_crop"},
		{"label": "Wild Animal Spawn", "kind": "wild_animal"},
	]:
		var button = Button.new()
		button.text = entry["label"]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = str(entry["kind"]) == _selected_spawn_kind
		button.pressed.connect(_select_spawn_kind.bind(str(entry["kind"])))
		_bottom_content.add_child(button)

	var team_row = HBoxContainer.new()
	team_row.add_child(_make_label("Inspector · Player Spawn Team"))
	var team_option = OptionButton.new()
	team_option.add_item("Red Team")
	team_option.add_item("Blue Team")
	team_option.select(0 if _selected_team_spawn_team == "red" else 1)
	team_option.item_selected.connect(func(index: int) -> void:
		_selected_team_spawn_team = "red" if index == 0 else "blue"
	)
	team_row.add_child(team_option)
	_bottom_content.add_child(team_row)

	var hint = Label.new()
	hint.text = "Select Player Spawn Point, set its team in Inspector, then place it. Every playable map needs at least one red and one blue point; these points are independent from buses."
	_bottom_content.add_child(hint)


func _add_auxiliary_buttons() -> void:
	var title := Label.new()
	title.text = "Tutorial Auxiliary"
	_bottom_content.add_child(title)
	var group := ButtonGroup.new()
	for entry in [
		{"label": "Message Area", "kind": "message_area"},
		{"label": "Power Pole", "kind": "power_pole"},
		{"label": "Neutral Crop Generator", "kind": "neutral_crop_generator"},
	]:
		var button := Button.new()
		button.text = str(entry["label"])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = _selected_auxiliary_kind == str(entry["kind"])
		button.pressed.connect(func() -> void:
			_selected_auxiliary_kind = str(entry["kind"])
			_refresh_bottom_dock()
		)
		_bottom_content.add_child(button)
	if _selected_auxiliary_kind == "neutral_crop_generator":
		_add_neutral_crop_generator_controls()
	var hint := Label.new()
	hint.text = "左键放置辅助物体。Message Area 可在 Inspector 设置提示；Power Pole 会按放置顺序与相邻电线杆生成两条下垂黑色电线；Neutral Crop Generator 会在无归属空 FarmTile 上按单一周期生成作物。Shift+左键删除。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)


func _add_neutral_crop_generator_controls() -> void:
	var heading := Label.new()
	heading.text = "Neutral Crop Generator Settings"
	_bottom_content.add_child(heading)

	var crop_row := HBoxContainer.new()
	crop_row.add_child(_make_label("Crop"))
	var crop_option := OptionButton.new()
	var plantable_ids := IngredientCatalog.get_plantable_ids()
	for crop_id_value: String in plantable_ids:
		crop_option.add_item(crop_id_value)
		crop_option.set_item_metadata(crop_option.item_count - 1, crop_id_value)
	var selected_crop_index := plantable_ids.find(_selected_neutral_crop_id)
	if selected_crop_index < 0 and not plantable_ids.is_empty():
		selected_crop_index = 0
		_selected_neutral_crop_id = plantable_ids[0]
	if selected_crop_index >= 0:
		crop_option.select(selected_crop_index)
	crop_option.item_selected.connect(func(index: int) -> void:
		_selected_neutral_crop_id = str(crop_option.get_item_metadata(index))
	)
	crop_row.add_child(crop_option)
	_bottom_content.add_child(crop_row)

	var size_row := HBoxContainer.new()
	size_row.add_child(_make_label("Area W / D"))
	var width_spin := SpinBox.new()
	width_spin.min_value = 1.0
	width_spin.max_value = 512.0
	width_spin.step = 1.0
	width_spin.value = _neutral_crop_area_size.x
	width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_spin.value_changed.connect(func(value: float) -> void:
		_neutral_crop_area_size.x = maxf(1.0, value)
	)
	size_row.add_child(width_spin)
	var depth_spin := SpinBox.new()
	depth_spin.min_value = 1.0
	depth_spin.max_value = 512.0
	depth_spin.step = 1.0
	depth_spin.value = _neutral_crop_area_size.y
	depth_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_spin.value_changed.connect(func(value: float) -> void:
		_neutral_crop_area_size.y = maxf(1.0, value)
	)
	size_row.add_child(depth_spin)
	_bottom_content.add_child(size_row)

	var interval_row := HBoxContainer.new()
	interval_row.add_child(_make_label("周期 (秒)"))
	var interval_spin := SpinBox.new()
	interval_spin.min_value = 1.0
	interval_spin.max_value = 3600.0
	interval_spin.step = 1.0
	interval_spin.value = _neutral_crop_respawn_interval
	interval_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interval_spin.value_changed.connect(func(value: float) -> void:
		_neutral_crop_respawn_interval = maxf(1.0, value)
	)
	interval_row.add_child(interval_spin)
	_bottom_content.add_child(interval_row)

	var delay_row := HBoxContainer.new()
	delay_row.add_child(_make_label("初次延迟 (秒)"))
	var delay_spin := SpinBox.new()
	delay_spin.min_value = 0.0
	delay_spin.max_value = 3600.0
	delay_spin.step = 1.0
	delay_spin.value = _neutral_crop_initial_delay
	delay_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delay_spin.value_changed.connect(func(value: float) -> void:
		_neutral_crop_initial_delay = maxf(0.0, value)
	)
	delay_row.add_child(delay_spin)
	_bottom_content.add_child(delay_row)

	var boundary_row := HBoxContainer.new()
	boundary_row.add_child(_make_label("边界颜色"))
	var color_picker := ColorPickerButton.new()
	color_picker.color = _neutral_crop_boundary_color
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(72.0, 30.0)
	color_picker.color_changed.connect(func(value: Color) -> void:
		_neutral_crop_boundary_color = Color(value.r, value.g, value.b, 1.0)
	)
	boundary_row.add_child(color_picker)
	_bottom_content.add_child(boundary_row)

	var boundary_check := CheckBox.new()
	boundary_check.text = "显示编辑器边界"
	boundary_check.button_pressed = _neutral_crop_show_boundary
	boundary_check.toggled.connect(func(value: bool) -> void:
		_neutral_crop_show_boundary = value
	)
	_bottom_content.add_child(boundary_check)


func _add_farmland_controls() -> void:
	var heading := Label.new()
	heading.text = "FarmFieldGenerator Settings"
	_bottom_content.add_child(heading)

	var length_row := HBoxContainer.new()
	length_row.add_child(_make_label("Length (tiles)"))
	var length_spin := SpinBox.new()
	length_spin.min_value = 1
	length_spin.max_value = 128
	length_spin.step = 1
	length_spin.value = _farmland_length_tiles
	length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	length_spin.value_changed.connect(func(value: float) -> void:
		_farmland_length_tiles = clampi(roundi(value), 1, 128)
		_update_farmland_cursor_preview_from_latest_hit()
	)
	length_row.add_child(length_spin)
	_bottom_content.add_child(length_row)

	var width_row := HBoxContainer.new()
	width_row.add_child(_make_label("Width (tiles)"))
	var width_spin := SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 128
	width_spin.step = 1
	width_spin.value = _farmland_width_tiles
	width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_spin.value_changed.connect(func(value: float) -> void:
		_farmland_width_tiles = clampi(roundi(value), 1, 128)
		_update_farmland_cursor_preview_from_latest_hit()
	)
	width_row.add_child(width_spin)
	_bottom_content.add_child(width_row)

	var owner_row := HBoxContainer.new()
	owner_row.add_child(_make_label("Ownership"))
	var owner_option := OptionButton.new()
	owner_option.add_item("No Owner")
	owner_option.add_item("Red Team")
	owner_option.add_item("Blue Team")
	owner_option.select(0 if _selected_farmland_owner.is_empty() else (1 if _selected_farmland_owner == "red" else 2))
	owner_option.item_selected.connect(func(index: int) -> void:
		_selected_farmland_owner = "" if index == 0 else ("red" if index == 1 else "blue")
		_update_farmland_cursor_preview_from_latest_hit()
	)
	owner_row.add_child(owner_option)
	_bottom_content.add_child(owner_row)

	var hint := Label.new()
	hint.text = "左键放置农田区域。编辑器只显示半透明覆盖范围；进入游戏加载地图时才生成 FarmTile。Shift+左键删除。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)


func _add_ai_configuration_controls() -> void:
	var explanation := Label.new()
	explanation.text = "地图 AI 是可选规则：没有配置时不会生成任何 AI。AI 由房主/本地权威生成；合作客户端只接收同步结果。"
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(explanation)

	var list_row := HBoxContainer.new()
	list_row.add_child(_make_label("AI 列表"))
	var list_option := OptionButton.new()
	list_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for index in range(_ai_configurations.size()):
		var entry := _ai_configurations[index] as Dictionary
		list_option.add_item("%02d  %s · %s · %s" % [
			index + 1,
			_ai_type_label(str(entry.get("ai_type", ""))),
			"红队" if str(entry.get("team", "red")) == "red" else "蓝队",
			("随机出生点" if str(entry.get("spawn_point_id", "")).is_empty() else str(entry.get("spawn_point_id", ""))),
		])
	list_option.disabled = _ai_configurations.is_empty()
	if _selected_ai_index >= 0 and _selected_ai_index < list_option.item_count:
		list_option.select(_selected_ai_index)
	list_option.item_selected.connect(func(index: int) -> void:
		_selected_ai_index = index
		_refresh_bottom_dock()
	)
	list_row.add_child(list_option)
	var add_button := Button.new()
	add_button.text = "+ 添加 AI"
	add_button.pressed.connect(_add_ai_configuration)
	list_row.add_child(add_button)
	_bottom_content.add_child(list_row)

	if _ai_configurations.is_empty():
		var empty_label := Label.new()
		empty_label.text = "当前地图没有 AI 配置。点击“添加 AI”后再选择类型、队伍和出生点。"
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bottom_content.add_child(empty_label)
		return
	if _selected_ai_index < 0 or _selected_ai_index >= _ai_configurations.size():
		_selected_ai_index = 0

	var entry := _ai_configurations[_selected_ai_index] as Dictionary
	var type_row := HBoxContainer.new()
	type_row.add_child(_make_label("AI 类型"))
	var type_option := OptionButton.new()
	for ai_type_value in AI_TYPES:
		var ai_type := ai_type_value as Dictionary
		type_option.add_item(str(ai_type.get("label", "AI")))
		type_option.set_item_metadata(type_option.item_count - 1, str(ai_type.get("id", "")))
		if str(ai_type.get("id", "")) == str(entry.get("ai_type", "")):
			type_option.select(type_option.item_count - 1)
	type_option.item_selected.connect(func(index: int) -> void:
		_update_selected_ai_configuration("ai_type", str(type_option.get_item_metadata(index)))
	)
	type_row.add_child(type_option)
	_bottom_content.add_child(type_row)

	var team_row := HBoxContainer.new()
	team_row.add_child(_make_label("队伍"))
	var team_option := OptionButton.new()
	team_option.add_item("红队")
	team_option.add_item("蓝队")
	team_option.select(0 if str(entry.get("team", "red")) == "red" else 1)
	team_option.item_selected.connect(func(index: int) -> void:
		_update_selected_ai_configuration("team", "red" if index == 0 else "blue")
	)
	team_row.add_child(team_option)
	_bottom_content.add_child(team_row)

	var spawn_row := HBoxContainer.new()
	spawn_row.add_child(_make_label("出生点"))
	var spawn_option := OptionButton.new()
	spawn_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_option.add_item("随机选择本队出生点")
	spawn_option.set_item_metadata(0, "")
	var spawn_id := str(entry.get("spawn_point_id", ""))
	var spawn_index := 0
	for point_value in _get_editor_team_spawn_points(str(entry.get("team", "red"))):
		var point := point_value as TeamSpawnPoint
		var label := _spawn_point_display_label(point)
		spawn_option.add_item(label)
		spawn_option.set_item_metadata(spawn_option.item_count - 1, point.spawn_point_id)
		if point.spawn_point_id == spawn_id:
			spawn_index = spawn_option.item_count - 1
	spawn_option.select(spawn_index)
	spawn_option.item_selected.connect(func(index: int) -> void:
		_update_selected_ai_configuration("spawn_point_id", str(spawn_option.get_item_metadata(index)))
	)
	spawn_row.add_child(spawn_option)
	_bottom_content.add_child(spawn_row)

	var respawn_row := HBoxContainer.new()
	respawn_row.add_child(_make_label("复活时间 (秒)"))
	var respawn_spin := SpinBox.new()
	respawn_spin.min_value = 1.0
	respawn_spin.max_value = 600.0
	respawn_spin.step = 1.0
	respawn_spin.value = clampf(float(entry.get("respawn_seconds", 10.0)), 1.0, 600.0)
	respawn_spin.value_changed.connect(func(value: float) -> void:
		_update_selected_ai_configuration("respawn_seconds", value)
	)
	respawn_row.add_child(respawn_spin)
	_bottom_content.add_child(respawn_row)

	var delete_button := Button.new()
	delete_button.text = "删除当前 AI 配置"
	delete_button.add_theme_color_override("font_color", Color("ff8b82"))
	delete_button.pressed.connect(_remove_selected_ai_configuration)
	_bottom_content.add_child(delete_button)

	var hint := Label.new()
	hint.text = "出生点编号只在编辑器预览中显示（R#01 / B#01），实际游戏不会显示。空出生点表示从所选队伍的出生点中随机选择。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)


func _ai_type_label(ai_type: String) -> String:
	for value in AI_TYPES:
		var entry := value as Dictionary
		if str(entry.get("id", "")) == ai_type.to_lower():
			return str(entry.get("label", ai_type))
	return ai_type if not ai_type.is_empty() else "未设置"


func _default_ai_configuration() -> Dictionary:
	return {
		"ai_type": "farmer",
		"team": "blue",
		"spawn_point_id": "",
		"respawn_seconds": 10.0,
		"name": "",
	}


func _add_ai_configuration() -> void:
	var before := _ai_configurations.duplicate(true)
	var after := _ai_configurations.duplicate(true)
	after.append(_default_ai_configuration())
	_selected_ai_index = after.size() - 1
	_record_ai_configuration_change(before, after, "Add Map AI")


func _remove_selected_ai_configuration() -> void:
	if _selected_ai_index < 0 or _selected_ai_index >= _ai_configurations.size():
		return
	var before := _ai_configurations.duplicate(true)
	var after := _ai_configurations.duplicate(true)
	after.remove_at(_selected_ai_index)
	_selected_ai_index = mini(_selected_ai_index, after.size() - 1)
	_record_ai_configuration_change(before, after, "Remove Map AI")


func _update_selected_ai_configuration(property_name: String, value: Variant) -> void:
	if _selected_ai_index < 0 or _selected_ai_index >= _ai_configurations.size():
		return
	var before := _ai_configurations.duplicate(true)
	var after := _ai_configurations.duplicate(true)
	var entry := after[_selected_ai_index] as Dictionary
	entry[property_name] = value
	after[_selected_ai_index] = entry
	_record_ai_configuration_change(before, after, "Edit Map AI")


func _record_ai_configuration_change(before: Array, after: Array, action_name: String) -> void:
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(_apply_ai_configuration.bind(after))
	_undo_redo.add_undo_method(_apply_ai_configuration.bind(before))
	_undo_redo.commit_action(false)
	_apply_ai_configuration(after)


func _apply_ai_configuration(value: Array) -> void:
	_ai_configurations = value.duplicate(true)
	if _map_root != null:
		_map_root.set_meta("farmwar_ai_configuration", _ai_configurations.duplicate(true))
	_refresh_bottom_dock()


func _get_editor_team_spawn_points(team_filter: String = "") -> Array[TeamSpawnPoint]:
	var result: Array[TeamSpawnPoint] = []
	if _spawns_root == null:
		return result
	for child in _spawns_root.get_children():
		if child is TeamSpawnPoint:
			var point := child as TeamSpawnPoint
			if team_filter.is_empty() or str(point.team) == team_filter:
				result.append(point)
	result.sort_custom(func(left: TeamSpawnPoint, right: TeamSpawnPoint) -> bool:
		return left.spawn_point_id < right.spawn_point_id
	)
	return result


func _spawn_point_display_label(point: TeamSpawnPoint) -> String:
	if point == null:
		return "未知出生点"
	var prefix := "R" if str(point.team) == "red" else "B"
	var id_parts := str(point.spawn_point_id).split("_")
	var suffix := str(id_parts[id_parts.size() - 1]) if not id_parts.is_empty() else ""
	var number := int(suffix) if suffix.is_valid_int() else 0
	return "%s#%02d (%s)" % [prefix, number, point.spawn_point_id]



func _add_building_placement_controls() -> void:
	_building_selected_info_label = Label.new()
	_building_selected_info_label.text = "Selected: %s" % str(_selected_building_asset.get("label", "None"))
	_building_selected_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(_building_selected_info_label)

	var rotate_button = Button.new()
	rotate_button.text = "Rotate Preview +%d° (R)" % int(building_rotation_step_degrees)
	rotate_button.pressed.connect(_rotate_building_preview_once)
	_bottom_content.add_child(rotate_button)

	var rules = Label.new()
	rules.text = "The full building model follows the mouse. The translucent footprint is green when valid and red when outside the map, too steep, or overlapping another placed object."
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(rules)

	var slope = Label.new()
	slope.text = "Maximum slope: %.1f°
Overlap margin: %.2f m" % [building_max_slope_degrees, building_overlap_margin]
	_bottom_content.add_child(slope)

func _add_building_browser() -> void:
	var browser = VBoxContainer.new()
	browser.name = "BuildingBrowser"
	browser.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	browser.add_theme_constant_override("separation", 6)
	_bottom_content.add_child(browser)

	var toolbar = HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	browser.add_child(toolbar)

	var search_label = Label.new()
	search_label.text = "Search"
	toolbar.add_child(search_label)

	_building_search_edit = LineEdit.new()
	_building_search_edit.placeholder_text = "Building name or path"
	_building_search_edit.text = _building_search_text
	_building_search_edit.custom_minimum_size.x = 260.0
	_building_search_edit.text_changed.connect(_on_building_search_changed)
	toolbar.add_child(_building_search_edit)

	var category_label = Label.new()
	category_label.text = "Folder"
	toolbar.add_child(category_label)

	_building_category_option = OptionButton.new()
	_building_category_option.custom_minimum_size.x = 180.0
	for category in _building_categories:
		_building_category_option.add_item(category)
		if category == _building_category_filter:
			_building_category_option.select(_building_category_option.item_count - 1)
	_building_category_option.item_selected.connect(_on_building_category_selected)
	toolbar.add_child(_building_category_option)

	var refresh_button = Button.new()
	refresh_button.text = "Rescan"
	refresh_button.tooltip_text = "Scan res://buildings again. The nature/ folder is always excluded."
	refresh_button.pressed.connect(_rescan_building_assets)
	toolbar.add_child(refresh_button)

	var rotate_button = Button.new()
	rotate_button.text = "Rotate Preview +%d°" % int(building_rotation_step_degrees)
	rotate_button.pressed.connect(_rotate_building_preview_once)
	toolbar.add_child(rotate_button)

	_building_count_label = Label.new()
	_building_count_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_building_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	toolbar.add_child(_building_count_label)

	_building_grid = GridContainer.new()
	_building_grid.columns = maxi(2, int((get_viewport().get_visible_rect().size.x - 570.0) / BUILDING_BROWSER_CARD_SIZE.x))
	_building_grid.add_theme_constant_override("h_separation", 8)
	_building_grid.add_theme_constant_override("v_separation", 8)
	browser.add_child(_building_grid)
	_refresh_building_browser_grid()


func _add_object_edit_controls() -> void:
	var mode_label = Label.new()
	mode_label.text = "Transform Mode"
	_bottom_content.add_child(mode_label)

	var mode_row = HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 4)
	_bottom_content.add_child(mode_row)
	var group = ButtonGroup.new()

	_object_move_button = Button.new()
	_object_move_button.text = "Move (G)"
	_object_move_button.toggle_mode = true
	_object_move_button.button_group = group
	_object_move_button.button_pressed = _object_transform_mode == ObjectTransformMode.MOVE
	_object_move_button.pressed.connect(_set_object_transform_mode.bind(ObjectTransformMode.MOVE))
	mode_row.add_child(_object_move_button)

	_object_rotate_button = Button.new()
	_object_rotate_button.text = "Rotate (R)"
	_object_rotate_button.toggle_mode = true
	_object_rotate_button.button_group = group
	_object_rotate_button.button_pressed = _object_transform_mode == ObjectTransformMode.ROTATE
	_object_rotate_button.pressed.connect(_set_object_transform_mode.bind(ObjectTransformMode.ROTATE))
	mode_row.add_child(_object_rotate_button)

	_object_scale_button = Button.new()
	_object_scale_button.text = "Scale (S)"
	_object_scale_button.toggle_mode = true
	_object_scale_button.button_group = group
	_object_scale_button.button_pressed = _object_transform_mode == ObjectTransformMode.SCALE
	_object_scale_button.pressed.connect(_set_object_transform_mode.bind(ObjectTransformMode.SCALE))
	mode_row.add_child(_object_scale_button)

	_object_local_axes_check = CheckBox.new()
	_object_local_axes_check.text = "Local axes"
	_object_local_axes_check.button_pressed = _gizmo_local_space
	_object_local_axes_check.toggled.connect(func(value: bool) -> void:
		_gizmo_local_space = value
		_refresh_transform_gizmo()
	)
	_bottom_content.add_child(_object_local_axes_check)

	_selection_status_label = Label.new()
	_selection_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(_selection_status_label)

	_add_transform_spin_group("Position", "m")
	_add_transform_spin_group("Rotation", "°")
	_add_transform_spin_group("Scale", "")

	var uniform_row = HBoxContainer.new()
	uniform_row.add_child(_make_label("Uniform"))
	_object_uniform_scale_spin = SpinBox.new()
	_object_uniform_scale_spin.min_value = object_minimum_scale
	_object_uniform_scale_spin.max_value = object_maximum_scale
	_object_uniform_scale_spin.step = object_scale_snap
	_object_uniform_scale_spin.value = 1.0
	_object_uniform_scale_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uniform_row.add_child(_object_uniform_scale_spin)
	var uniform_button = Button.new()
	uniform_button.text = "Set XYZ"
	uniform_button.pressed.connect(_apply_uniform_scale_from_inspector)
	uniform_row.add_child(uniform_button)
	_bottom_content.add_child(uniform_row)

	var apply_numeric = Button.new()
	apply_numeric.text = "Apply Exact Transform"
	apply_numeric.pressed.connect(_apply_numeric_object_transform)
	_bottom_content.add_child(apply_numeric)

	if _selected_map_object is TeamSpawnPoint:
		var spawn_team_row = HBoxContainer.new()
		spawn_team_row.add_child(_make_label("Inspector · Spawn Team"))
		var spawn_team_option = OptionButton.new()
		spawn_team_option.add_item("Red Team")
		spawn_team_option.add_item("Blue Team")
		spawn_team_option.select(0 if str((_selected_map_object as TeamSpawnPoint).team) == "red" else 1)
		spawn_team_option.item_selected.connect(func(index: int) -> void:
			_set_selected_team_spawn_team("red" if index == 0 else "blue")
		)
		spawn_team_row.add_child(spawn_team_option)
		_bottom_content.add_child(spawn_team_row)

	if is_instance_valid(_selected_map_object) and str(_selected_map_object.get_meta("map_editor_category", "")) == "auxiliary" and _is_message_area(_selected_map_object):
		_add_message_area_inspector_controls()
	if is_instance_valid(_selected_map_object) and str(_selected_map_object.get_meta("map_editor_category", "")) == "auxiliary" and _is_neutral_crop_generator(_selected_map_object):
		_add_neutral_crop_generator_inspector_controls()

	if is_instance_valid(_selected_map_object) and _is_farmland(_selected_map_object):
		_add_farmland_inspector_controls()

	var action_row = HBoxContainer.new()
	_bottom_content.add_child(action_row)
	_object_duplicate_button = Button.new()
	_object_duplicate_button.text = "Duplicate"
	_object_duplicate_button.pressed.connect(_duplicate_selected_object)
	action_row.add_child(_object_duplicate_button)
	_object_delete_button = Button.new()
	_object_delete_button.text = "Delete"
	_object_delete_button.pressed.connect(_delete_selected_object)
	action_row.add_child(_object_delete_button)
	var align_button = Button.new()
	align_button.text = "Drop To Ground"
	align_button.pressed.connect(_align_selected_object_to_ground)
	action_row.add_child(align_button)

	var hint = Label.new()
	hint.text = "Click an object, then drag the colored gizmo. Move supports X/Y/Z, Rotate supports all three axes, and Scale supports X/Y/Z plus the center uniform handle."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)

	_update_object_edit_status()
	_sync_object_numeric_controls()


func _add_message_area_inspector_controls() -> void:
	var message_area := _selected_map_object
	var heading := Label.new()
	heading.text = "Message Area Inspector"
	_bottom_content.add_child(heading)

	var prompt_label := Label.new()
	prompt_label.text = "Prompt Text"
	_bottom_content.add_child(prompt_label)
	var prompt_edit := TextEdit.new()
	prompt_edit.custom_minimum_size = Vector2(0.0, 86.0)
	prompt_edit.text = str(message_area.get("prompt_text"))
	prompt_edit.placeholder_text = "Enter tutorial message..."
	prompt_edit.text_changed.connect(func() -> void:
		_set_message_area_property("prompt_text", prompt_edit.text)
	)
	_bottom_content.add_child(prompt_edit)

	var color_row := HBoxContainer.new()
	color_row.add_child(_make_label("Boundary Color"))
	var color_picker := ColorPickerButton.new()
	color_picker.color = message_area.get("boundary_color") as Color
	color_picker.custom_minimum_size = Vector2(72.0, 30.0)
	color_picker.color_changed.connect(func(value: Color) -> void:
		_set_message_area_property("boundary_color", value)
	)
	color_row.add_child(color_picker)
	_bottom_content.add_child(color_row)

	var boundary_check := CheckBox.new()
	boundary_check.text = "Show Boundary"
	boundary_check.button_pressed = bool(message_area.get("show_boundary"))
	boundary_check.toggled.connect(func(value: bool) -> void:
		_set_message_area_property("show_boundary", value)
	)
	_bottom_content.add_child(boundary_check)


func _set_message_area_property(property_name: String, value: Variant) -> void:
	if not is_instance_valid(_selected_map_object) or str(_selected_map_object.get_meta("map_editor_category", "")) != "auxiliary":
		return
	if not _has_property(_selected_map_object, property_name):
		return
	var before: Variant = _selected_map_object.get(property_name)
	if before == value:
		return
	var uuid := str(_selected_map_object.get_meta("map_editor_uuid", ""))
	_undo_redo.create_action("Edit Message Area")
	_undo_redo.add_do_method(_apply_object_property_by_uuid.bind(uuid, property_name, value))
	_undo_redo.add_undo_method(_apply_object_property_by_uuid.bind(uuid, property_name, before))
	_undo_redo.commit_action(false)
	_apply_object_property_by_uuid(uuid, property_name, value)


func _add_neutral_crop_generator_inspector_controls() -> void:
	var generator := _selected_map_object
	var heading := Label.new()
	heading.text = "Neutral Crop Generator Inspector"
	_bottom_content.add_child(heading)

	var crop_row := HBoxContainer.new()
	crop_row.add_child(_make_label("Crop"))
	var crop_option := OptionButton.new()
	var crop_ids := IngredientCatalog.get_plantable_ids()
	var current_crop := str(_get_property_or(generator, "crop_id", "wheat"))
	for crop_id_value: String in crop_ids:
		crop_option.add_item(crop_id_value)
		crop_option.set_item_metadata(crop_option.item_count - 1, crop_id_value)
		if crop_id_value == current_crop:
			crop_option.select(crop_option.item_count - 1)
	crop_option.item_selected.connect(func(index: int) -> void:
		_set_neutral_crop_generator_property("crop_id", str(crop_option.get_item_metadata(index)))
	)
	crop_row.add_child(crop_option)
	_bottom_content.add_child(crop_row)

	var area_size := _get_property_or(generator, "area_size", Vector2(16.0, 16.0)) as Vector2
	var size_row := HBoxContainer.new()
	size_row.add_child(_make_label("Area W / D"))
	var width_spin := SpinBox.new()
	width_spin.min_value = 1.0
	width_spin.max_value = 512.0
	width_spin.step = 1.0
	width_spin.value = area_size.x
	width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_spin.value_changed.connect(func(value: float) -> void:
		var current := _get_property_or(generator, "area_size", Vector2(16.0, 16.0)) as Vector2
		_set_neutral_crop_generator_property("area_size", Vector2(maxf(1.0, value), current.y))
	)
	size_row.add_child(width_spin)
	var depth_spin := SpinBox.new()
	depth_spin.min_value = 1.0
	depth_spin.max_value = 512.0
	depth_spin.step = 1.0
	depth_spin.value = area_size.y
	depth_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	depth_spin.value_changed.connect(func(value: float) -> void:
		var current := _get_property_or(generator, "area_size", Vector2(16.0, 16.0)) as Vector2
		_set_neutral_crop_generator_property("area_size", Vector2(current.x, maxf(1.0, value)))
	)
	size_row.add_child(depth_spin)
	_bottom_content.add_child(size_row)

	_add_neutral_crop_generator_spin("周期 (秒)", "respawn_interval_seconds", 1.0, 3600.0)
	_add_neutral_crop_generator_spin("初次延迟 (秒)", "initial_spawn_delay", 0.0, 3600.0)

	var color_row := HBoxContainer.new()
	color_row.add_child(_make_label("边界颜色"))
	var color_picker := ColorPickerButton.new()
	color_picker.color = _get_property_or(generator, "boundary_color", Color(0.95, 0.85, 0.25, 1.0)) as Color
	color_picker.edit_alpha = false
	color_picker.custom_minimum_size = Vector2(72.0, 30.0)
	color_picker.color_changed.connect(func(value: Color) -> void:
		_set_neutral_crop_generator_property("boundary_color", Color(value.r, value.g, value.b, 1.0))
	)
	color_row.add_child(color_picker)
	_bottom_content.add_child(color_row)

	var boundary_check := CheckBox.new()
	boundary_check.text = "显示编辑器边界"
	boundary_check.button_pressed = bool(_get_property_or(generator, "show_boundary", true))
	boundary_check.toggled.connect(func(value: bool) -> void:
		_set_neutral_crop_generator_property("show_boundary", value)
	)
	_bottom_content.add_child(boundary_check)


func _add_neutral_crop_generator_spin(label_text: String, property_name: String, minimum: float, maximum: float) -> void:
	var row := HBoxContainer.new()
	row.add_child(_make_label(label_text))
	var spin := SpinBox.new()
	spin.min_value = minimum
	spin.max_value = maximum
	spin.step = 1.0
	spin.value = float(_get_property_or(_selected_map_object, property_name, minimum))
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(func(value: float) -> void:
		_set_neutral_crop_generator_property(property_name, maxf(minimum, value))
	)
	row.add_child(spin)
	_bottom_content.add_child(row)


func _set_neutral_crop_generator_property(property_name: String, value: Variant) -> void:
	if not is_instance_valid(_selected_map_object) or not _is_neutral_crop_generator(_selected_map_object):
		return
	if not _has_property(_selected_map_object, property_name):
		return
	var before: Variant = _selected_map_object.get(property_name)
	if before == value:
		return
	var uuid := str(_selected_map_object.get_meta("map_editor_uuid", ""))
	if uuid.is_empty():
		return
	_undo_redo.create_action("Edit Neutral Crop Generator")
	_undo_redo.add_do_method(_apply_object_property_by_uuid.bind(uuid, property_name, value))
	_undo_redo.add_undo_method(_apply_object_property_by_uuid.bind(uuid, property_name, before))
	_undo_redo.commit_action(false)
	_apply_object_property_by_uuid(uuid, property_name, value)


func _add_farmland_inspector_controls() -> void:
	var field := _selected_map_object
	var heading := Label.new()
	heading.text = "Farmland Inspector"
	_bottom_content.add_child(heading)

	var length_row := HBoxContainer.new()
	length_row.add_child(_make_label("Length (tiles)"))
	var length_spin := SpinBox.new()
	length_spin.min_value = 1
	length_spin.max_value = 128
	length_spin.step = 1
	length_spin.value = int(_get_property_or(field, "length_tiles", 1))
	length_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	length_spin.value_changed.connect(func(value: float) -> void:
		_set_farmland_property("length_tiles", clampi(roundi(value), 1, 128))
	)
	length_row.add_child(length_spin)
	_bottom_content.add_child(length_row)

	var width_row := HBoxContainer.new()
	width_row.add_child(_make_label("Width (tiles)"))
	var width_spin := SpinBox.new()
	width_spin.min_value = 1
	width_spin.max_value = 128
	width_spin.step = 1
	width_spin.value = int(_get_property_or(field, "width_tiles", 1))
	width_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	width_spin.value_changed.connect(func(value: float) -> void:
		_set_farmland_property("width_tiles", clampi(roundi(value), 1, 128))
	)
	width_row.add_child(width_spin)
	_bottom_content.add_child(width_row)

	var owner_row := HBoxContainer.new()
	owner_row.add_child(_make_label("Ownership"))
	var owner_option := OptionButton.new()
	owner_option.add_item("No Owner")
	owner_option.add_item("Red Team")
	owner_option.add_item("Blue Team")
	var owner := str(_get_property_or(field, "field_owner", ""))
	owner_option.select(0 if owner.is_empty() else (1 if owner == "red" else 2))
	owner_option.item_selected.connect(func(index: int) -> void:
		_set_farmland_property("field_owner", "" if index == 0 else ("red" if index == 1 else "blue"))
	)
	owner_row.add_child(owner_option)
	_bottom_content.add_child(owner_row)

	var hint := Label.new()
	hint.text = "修改会实时更新半透明预览；游戏加载地图时才生成 FarmTile。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)


func _set_farmland_property(property_name: String, value: Variant) -> void:
	if not is_instance_valid(_selected_map_object) or not _is_farmland(_selected_map_object):
		return
	if not _has_property(_selected_map_object, property_name):
		return
	var before: Variant = _selected_map_object.get(property_name)
	if before == value:
		return
	var uuid := str(_selected_map_object.get_meta("map_editor_uuid", ""))
	if uuid.is_empty():
		return
	_undo_redo.create_action("Edit Farmland")
	_undo_redo.add_do_method(_apply_object_property_by_uuid.bind(uuid, property_name, value))
	_undo_redo.add_undo_method(_apply_object_property_by_uuid.bind(uuid, property_name, before))
	_undo_redo.commit_action(false)
	_apply_object_property_by_uuid(uuid, property_name, value)


func _apply_object_property_by_uuid(uuid: String, property_name: String, value: Variant) -> void:
	var node := _find_editor_object_by_uuid(uuid)
	if node == null or not _has_property(node, property_name):
		return
	node.set(property_name, value)
	if node.has_method("refresh_visuals"):
		node.call("refresh_visuals")
	if _is_farmland(node):
		_refresh_farmland_preview(node)


func _add_transform_spin_group(title: String, suffix_text: String) -> void:
	var heading = Label.new()
	heading.text = title
	_bottom_content.add_child(heading)
	var grid = GridContainer.new()
	grid.columns = 2
	_bottom_content.add_child(grid)
	for axis_name in ["X", "Y", "Z"]:
		grid.add_child(_make_label(axis_name))
		var spin = SpinBox.new()
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if title == "Position":
			spin.min_value = -100000.0
			spin.max_value = 100000.0
			spin.step = object_move_snap
		elif title == "Rotation":
			spin.min_value = -360.0
			spin.max_value = 360.0
			spin.step = object_rotation_snap_degrees
		else:
			spin.min_value = object_minimum_scale
			spin.max_value = object_maximum_scale
			spin.step = object_scale_snap
		spin.suffix = suffix_text
		grid.add_child(spin)
		if title == "Position":
			if axis_name == "X":
				_object_x_spin = spin
			elif axis_name == "Y":
				_object_y_spin = spin
			else:
				_object_z_spin = spin
		elif title == "Rotation":
			if axis_name == "X":
				_object_rot_x_spin = spin
			elif axis_name == "Y":
				_object_rot_y_spin = spin
			else:
				_object_rot_z_spin = spin
		else:
			if axis_name == "X":
				_object_scale_x_spin = spin
			elif axis_name == "Y":
				_object_scale_y_spin = spin
			else:
				_object_scale_z_spin = spin

func _scan_building_assets() -> void:
	_building_assets.clear()
	var category_set: Dictionary = {"All": true}
	_scan_building_directory(BUILDINGS_RESOURCE_ROOT, "", _building_assets, category_set)
	_building_assets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("label", "")).naturalnocasecmp_to(str(b.get("label", ""))) < 0
	)
	_building_categories = PackedStringArray(category_set.keys())
	_building_categories.sort()
	if _building_categories.has("All"):
		_building_categories.remove_at(_building_categories.find("All"))
	_building_categories.insert(0, "All")
	if _selected_building_asset.is_empty() and not _building_assets.is_empty():
		_selected_building_asset = _building_assets[0].duplicate(true)


func _scan_building_directory(
	directory_path: String,
	relative_category: String,
	result: Array[Dictionary],
	category_set: Dictionary
) -> void:
	if directory_path == BUILDINGS_EXCLUDED_ROOT or directory_path.begins_with(BUILDINGS_EXCLUDED_ROOT + "/"):
		return
	var entries = ResourceLoader.list_directory(directory_path)
	for entry_value in entries:
		var entry = str(entry_value)
		if entry.ends_with("/"):
			var directory_name = entry.trim_suffix("/")
			if directory_name.to_lower() == "nature":
				continue
			var next_category = directory_name if relative_category.is_empty() else relative_category.path_join(directory_name)
			_scan_building_directory(directory_path.path_join(directory_name), next_category, result, category_set)
			continue
		if entry.get_extension().to_lower() != "tscn":
			continue
		var resource_path = directory_path.path_join(entry)
		if resource_path.begins_with(BUILDINGS_EXCLUDED_ROOT):
			continue
		var category = "Root" if relative_category.is_empty() else relative_category
		category_set[category] = true
		result.append({
			"label": _humanize_asset_name(entry.get_basename()),
			"path": resource_path,
			"id": entry.get_basename().to_snake_case(),
			"category": category,
		})


func _humanize_asset_name(value: String) -> String:
	var result = value.replace("_", " ").replace("-", " ")
	var output = ""
	for index in range(result.length()):
		var character = result[index]
		if index > 0 and character == character.to_upper() and character != character.to_lower():
			var previous = result[index - 1]
			if previous != " " and previous == previous.to_lower():
				output += " "
		output += character
	return output.strip_edges()


func _rescan_building_assets() -> void:
	_building_thumbnail_queue.clear()
	_scan_building_assets()
	_refresh_bottom_dock()
	_set_status("Found %d building scenes outside nature/." % _building_assets.size())


func _on_building_search_changed(value: String) -> void:
	_building_search_text = value.strip_edges().to_lower()
	_refresh_building_browser_grid()


func _on_building_category_selected(index: int) -> void:
	if _building_category_option == null or index < 0 or index >= _building_category_option.item_count:
		return
	_building_category_filter = _building_category_option.get_item_text(index)
	_refresh_building_browser_grid()


func _refresh_building_browser_grid() -> void:
	if _building_grid == null:
		return
	for child in _building_grid.get_children():
		_building_grid.remove_child(child)
		child.queue_free()
	_building_thumbnail_cards.clear()
	_filtered_building_assets.clear()

	for asset_value in _building_assets:
		var asset = asset_value as Dictionary
		var category = str(asset.get("category", "Root"))
		if _building_category_filter != "All" and category != _building_category_filter:
			continue
		var searchable = (str(asset.get("label", "")) + " " + str(asset.get("path", ""))).to_lower()
		if not _building_search_text.is_empty() and not searchable.contains(_building_search_text):
			continue
		_filtered_building_assets.append(asset)

	for asset_value in _filtered_building_assets:
		_add_building_asset_card(asset_value as Dictionary)
	if _building_count_label != null:
		_building_count_label.text = "%d / %d assets" % [_filtered_building_assets.size(), _building_assets.size()]


func _add_building_asset_card(asset: Dictionary) -> void:
	var path = str(asset.get("path", ""))
	var card = PanelContainer.new()
	card.custom_minimum_size = BUILDING_BROWSER_CARD_SIZE
	_building_grid.add_child(card)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	card.add_child(column)

	var preview = TextureRect.new()
	preview.custom_minimum_size = Vector2(BUILDING_THUMBNAIL_SIZE)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.texture = _building_thumbnail_cache.get(path, _make_thumbnail_placeholder()) as Texture2D
	column.add_child(preview)
	_building_thumbnail_cards[path] = preview

	var select_button = Button.new()
	select_button.text = str(asset.get("label", "Building"))
	select_button.toggle_mode = true
	select_button.button_pressed = path == str(_selected_building_asset.get("path", ""))
	select_button.tooltip_text = path
	select_button.pressed.connect(_select_building_asset.bind(asset))
	column.add_child(select_button)

	var category_label = Label.new()
	category_label.text = str(asset.get("category", "Root"))
	category_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	category_label.modulate = Color(0.78, 0.78, 0.78, 1.0)
	column.add_child(category_label)
	_queue_building_thumbnail(path)


func _select_building_asset(asset: Dictionary) -> void:
	_selected_building_asset = asset.duplicate(true)
	_building_preview_yaw = 0.0
	_rebuild_building_preview()
	_refresh_building_browser_grid()
	if is_instance_valid(_building_selected_info_label):
		_building_selected_info_label.text = "Selected: %s" % str(asset.get("label", "Building"))
	_set_status("Building selected: %s" % str(asset.get("label", "Building")))


func _rotate_building_preview_once() -> void:
	_building_preview_yaw += deg_to_rad(building_rotation_step_degrees)
	_update_building_preview_from_latest_hit()


func _queue_building_thumbnail(path: String) -> void:
	if path.is_empty() or _building_thumbnail_cache.has(path) or _building_thumbnail_queue.has(path):
		return
	_building_thumbnail_queue.append(path)
	if not _building_thumbnail_rendering:
		call_deferred("_render_building_thumbnail_queue")


func _build_thumbnail_renderer() -> void:
	_thumbnail_viewport = SubViewport.new()
	_thumbnail_viewport.name = "BuildingThumbnailViewport"
	_thumbnail_viewport.size = Vector2i(256, 192)
	_thumbnail_viewport.own_world_3d = true
	_thumbnail_viewport.transparent_bg = false
	_thumbnail_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_thumbnail_viewport)
	_thumbnail_viewport_texture = _thumbnail_viewport.get_texture()

	var environment_node = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.075, 0.085, 0.10, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82, 1.0)
	environment.ambient_light_energy = 0.9
	environment_node.environment = environment
	_thumbnail_viewport.add_child(environment_node)

	var key_light = DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	_thumbnail_viewport.add_child(key_light)

	var fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill_light.light_energy = 0.55
	fill_light.shadow_enabled = false
	_thumbnail_viewport.add_child(fill_light)

	_thumbnail_camera = Camera3D.new()
	_thumbnail_camera.current = true
	_thumbnail_camera.fov = 42.0
	_thumbnail_camera.near = 0.01
	_thumbnail_camera.far = 1000.0
	_thumbnail_viewport.add_child(_thumbnail_camera)

	_thumbnail_scene_root = Node3D.new()
	_thumbnail_scene_root.name = "PreviewScene"
	_thumbnail_viewport.add_child(_thumbnail_scene_root)


func _render_building_thumbnail_queue() -> void:
	if _building_thumbnail_rendering:
		return
	_building_thumbnail_rendering = true
	while not _building_thumbnail_queue.is_empty():
		var path = _building_thumbnail_queue.pop_front()
		if _building_thumbnail_cache.has(path):
			continue
		var texture = await _render_one_building_thumbnail(path)
		if texture != null:
			_building_thumbnail_cache[path] = texture
			# Browser refreshes can free old cards while this coroutine awaits a
			# viewport frame. Validate the raw Variant before casting it.
			var card_value: Variant = _building_thumbnail_cards.get(path, null)
			if is_instance_valid(card_value) and card_value is TextureRect:
				var card := card_value as TextureRect
				card.texture = texture
			elif card_value != null:
				_building_thumbnail_cards.erase(path)
		await get_tree().process_frame
	_building_thumbnail_rendering = false


func _render_one_building_thumbnail(path: String) -> Texture2D:
	var packed = _load_resource_or_null(path) as PackedScene
	if packed == null:
		return _make_thumbnail_placeholder()
	var instance = packed.instantiate() as Node3D
	if instance == null:
		return _make_thumbnail_placeholder()
	_prepare_thumbnail_scene(instance)
	_thumbnail_scene_root.add_child(instance)
	await get_tree().process_frame

	var bounds = _calculate_node_aabb_relative_to(instance, instance)
	if bounds.size.length_squared() <= 0.000001:
		_thumbnail_scene_root.remove_child(instance)
		instance.free()
		return _make_thumbnail_placeholder()
	instance.position = -bounds.get_center()
	var diameter = maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	var radius = maxf(0.5, diameter * 0.5)
	var target = Vector3(0.0, maxf(0.0, bounds.size.y * 0.06), 0.0)
	_thumbnail_camera.position = Vector3(radius * 1.65, radius * 1.15, radius * 1.65)
	_thumbnail_camera.look_at(target, Vector3.UP)
	_thumbnail_camera.near = maxf(0.01, radius * 0.01)
	_thumbnail_camera.far = maxf(100.0, radius * 12.0)
	_thumbnail_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var image = _thumbnail_viewport_texture.get_image()
	if image == null or image.is_empty():
		_thumbnail_scene_root.remove_child(instance)
		instance.free()
		return _make_thumbnail_placeholder()
	image.resize(BUILDING_THUMBNAIL_SIZE.x, BUILDING_THUMBNAIL_SIZE.y, Image.INTERPOLATE_LANCZOS)
	var texture = ImageTexture.create_from_image(image)
	_thumbnail_scene_root.remove_child(instance)
	instance.free()
	return texture


func _prepare_thumbnail_scene(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null:
		node.set_script(null)
	if node is CollisionObject3D:
		var collision_object = node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is Light3D:
		(node as Light3D).visible = false
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	for child in node.get_children():
		_prepare_thumbnail_scene(child)


func _calculate_node_aabb_relative_to(node: Node, root: Node3D) -> AABB:
	var found = false
	var result = AABB()
	if node is VisualInstance3D and node.has_method("get_aabb"):
		var visual = node as Node3D
		var local_aabb: AABB = node.call("get_aabb")
		if local_aabb.size.length_squared() > 0.000001:
			var relative_transform = root.global_transform.affine_inverse() * visual.global_transform
			result = relative_transform * local_aabb
			found = true
	for child in node.get_children():
		var child_aabb = _calculate_node_aabb_relative_to(child, root)
		if child_aabb.size.length_squared() <= 0.000001:
			continue
		if not found:
			result = child_aabb
			found = true
		else:
			result = result.merge(child_aabb)
	return result if found else AABB()


func _make_thumbnail_placeholder() -> Texture2D:
	var image = Image.create(BUILDING_THUMBNAIL_SIZE.x, BUILDING_THUMBNAIL_SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.12, 0.13, 0.15, 1.0))
	return ImageTexture.create_from_image(image)

func _add_road_buttons() -> void:
	var new_road_button = Button.new()
	new_road_button.text = "New Road"
	new_road_button.pressed.connect(_begin_new_road)
	_bottom_content.add_child(new_road_button)

	var new_rail_button = Button.new()
	new_rail_button.text = "New Rail"
	new_rail_button.tooltip_text = "Draw a 12m RailTrack path with overlapping pieces at bends."
	new_rail_button.pressed.connect(_begin_new_rail)
	_bottom_content.add_child(new_rail_button)

	_road_finish_button = Button.new()
	_road_finish_button.text = "Finish Road"
	_road_finish_button.pressed.connect(_finish_active_road)
	_bottom_content.add_child(_road_finish_button)

	_road_delete_point_button = Button.new()
	_road_delete_point_button.text = "Delete Point"
	_road_delete_point_button.pressed.connect(_delete_selected_road_point)
	_bottom_content.add_child(_road_delete_point_button)

	_road_conform_button = Button.new()
	_road_conform_button.text = "Conform To Terrain"
	_road_conform_button.pressed.connect(_conform_selected_road_to_terrain)
	_bottom_content.add_child(_road_conform_button)

	_road_delete_button = Button.new()
	_road_delete_button.text = "Delete Road"
	_road_delete_button.pressed.connect(_delete_selected_road)
	_bottom_content.add_child(_road_delete_button)

	_bottom_content.add_child(_make_label("Road"))
	_road_list_option = OptionButton.new()
	_road_list_option.custom_minimum_size.x = 170.0
	_road_list_option.item_selected.connect(_on_road_list_selected)
	_bottom_content.add_child(_road_list_option)
	_refresh_road_list_option()

	_bottom_content.add_child(_make_label("Type"))
	_road_type_option = OptionButton.new()
	for entry in [
		{"label": "Asphalt Narrow", "id": 0},
		{"label": "Asphalt Wide", "id": 1},
		{"label": "Country Gravel Narrow", "id": 2},
		{"label": "Country Gravel Wide", "id": 3},
		{"label": "Rail Track", "id": ROAD_TYPE_RAIL},
	]:
		_road_type_option.add_item(str(entry["label"]), int(entry["id"]))
	_road_type_option.select(clampi(_road_type, 0, ROAD_TYPE_RAIL))
	_road_type_option.item_selected.connect(_on_road_type_selected)
	_bottom_content.add_child(_road_type_option)

	_bottom_content.add_child(_make_label("Width Override"))
	_road_width_spin = SpinBox.new()
	_road_width_spin.min_value = 0.0
	_road_width_spin.max_value = 20.0
	_road_width_spin.step = 0.1
	_road_width_spin.value = _road_width_override
	_road_width_spin.tooltip_text = "0 uses the width defined by the selected road type."
	_road_width_spin.value_changed.connect(_on_road_width_changed)
	_bottom_content.add_child(_road_width_spin)

	_bottom_content.add_child(_make_label("Height Offset"))
	_road_offset_spin = SpinBox.new()
	_road_offset_spin.min_value = -0.1
	_road_offset_spin.max_value = 1.0
	_road_offset_spin.step = 0.01
	_road_offset_spin.value = _road_vertical_offset
	_road_offset_spin.value_changed.connect(_on_road_offset_changed)
	_bottom_content.add_child(_road_offset_spin)

	var hint = Label.new()
	hint.text = "New Road or New Rail, then click the terrain to add points. Enter/Finish completes it. Select a yellow point and drag it along the terrain. RailTrack uses the 12m model with overlapping pieces to keep bends closed."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 0.0
	_bottom_content.add_child(hint)
	_update_road_control_states()


func _update_road_control_states() -> void:
	if _road_finish_button != null:
		_road_finish_button.disabled = not _road_drawing_active
	if _road_delete_point_button != null:
		_road_delete_point_button.disabled = (
			_selected_road == null or _road_selected_point < 0
		)
	if _road_conform_button != null:
		_road_conform_button.disabled = _selected_road == null
	if _road_delete_button != null:
		_road_delete_button.disabled = _selected_road == null


func _add_water_buttons() -> void:
	var new_lake_button := Button.new()
	new_lake_button.text = "New Lake"
	new_lake_button.pressed.connect(_begin_new_lake)
	_bottom_content.add_child(new_lake_button)

	var new_river_button := Button.new()
	new_river_button.text = "New River"
	new_river_button.pressed.connect(_begin_new_river)
	_bottom_content.add_child(new_river_button)

	_water_finish_button = Button.new()
	_water_finish_button.text = "Finish Water"
	_water_finish_button.pressed.connect(_finish_active_water)
	_bottom_content.add_child(_water_finish_button)

	_water_cancel_button = Button.new()
	_water_cancel_button.text = "Cancel Drawing"
	_water_cancel_button.pressed.connect(_cancel_active_water)
	_bottom_content.add_child(_water_cancel_button)

	_water_delete_button = Button.new()
	_water_delete_button.text = "Delete Water"
	_water_delete_button.pressed.connect(_delete_selected_water)
	_bottom_content.add_child(_water_delete_button)

	_bottom_content.add_child(_make_label("Water Body"))
	_water_list_option = OptionButton.new()
	_water_list_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_water_list_option.item_selected.connect(_on_water_list_selected)
	_bottom_content.add_child(_water_list_option)

	_bottom_content.add_child(_make_label("Type"))
	_water_type_option = OptionButton.new()
	_water_type_option.add_item("Lake", WaterBody3D.BodyType.LAKE)
	_water_type_option.add_item("River Centerline", WaterBody3D.BodyType.RIVER)
	_water_type_option.item_selected.connect(_on_water_type_selected)
	_bottom_content.add_child(_water_type_option)

	_bottom_content.add_child(_make_label("Water Level (world Y)"))
	_water_level_spin = SpinBox.new()
	_water_level_spin.min_value = -40.0
	_water_level_spin.max_value = 120.0
	_water_level_spin.step = 0.05
	_water_level_spin.value = _water_level
	_water_level_spin.value_changed.connect(_on_water_level_changed)
	_bottom_content.add_child(_water_level_spin)

	_bottom_content.add_child(_make_label("Depth"))
	_water_depth_spin = SpinBox.new()
	_water_depth_spin.min_value = 0.1
	_water_depth_spin.max_value = 100.0
	_water_depth_spin.step = 0.1
	_water_depth_spin.value = _water_depth
	_water_depth_spin.value_changed.connect(_on_water_depth_changed)
	_bottom_content.add_child(_water_depth_spin)

	_bottom_content.add_child(_make_label("River Width (River only)"))
	_water_width_spin = SpinBox.new()
	_water_width_spin.min_value = 0.5
	_water_width_spin.max_value = 100.0
	_water_width_spin.step = 0.1
	_water_width_spin.value = _water_width
	_water_width_spin.value_changed.connect(_on_water_width_changed)
	_bottom_content.add_child(_water_width_spin)

	var hint := Label.new()
	hint.text = "Lake: click at least 3 points around an irregular boundary. River: click a centerline, then set width. Enter completes. Water has a slow low-poly flow animation; direction is fixed. Depth changes transparency and darkness. WaterBody3D stays at Y=0; players can enter the water, while AI, wildlife and livestock avoid it."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bottom_content.add_child(hint)
	_refresh_water_list_option()
	_update_water_control_states()


func _update_water_control_states() -> void:
	if _water_finish_button != null:
		_water_finish_button.disabled = not _water_drawing_active
	if _water_cancel_button != null:
		_water_cancel_button.disabled = not _water_drawing_active
	if _water_delete_button != null:
		_water_delete_button.disabled = _selected_water == null
	if _water_width_spin != null:
		# Width only affects a river generated from a centerline; lakes use the
		# polygon drawn by the user and therefore have no width parameter.
		_water_width_spin.editable = _water_body_type == WaterBody3D.BodyType.RIVER


func _on_water_type_selected(index: int) -> void:
	_water_body_type = _water_type_option.get_item_id(index)
	if _selected_water != null and not _water_drawing_active:
		var before := _serialize_water(_selected_water)
		_selected_water.body_type = _water_body_type
		_selected_water.rebuild_water_body()
		_commit_water_state_change("Change Water Type", before, _serialize_water(_selected_water))
	_update_water_control_states()


func _on_water_level_changed(value: float) -> void:
	_water_level = value
	if _selected_water != null:
		_apply_water_numeric_property(_selected_water, "water_level", value, "Change Water Level")


func _on_water_depth_changed(value: float) -> void:
	_water_depth = value
	if _selected_water != null:
		_apply_water_numeric_property(_selected_water, "water_depth", value, "Change Water Depth")


func _on_water_width_changed(value: float) -> void:
	_water_width = value
	if _selected_water != null:
		_apply_water_numeric_property(_selected_water, "river_width", value, "Change River Width")


func _apply_water_numeric_property(water: WaterBody3D, property_name: String, value: float, action_name: String) -> void:
	if water == null or _water_history_guard:
		return
	var before := _serialize_water(water)
	_set_property_if_present(water, property_name, value)
	water.rebuild_water_body()
	if not _water_drawing_active:
		_commit_water_state_change(action_name, before, _serialize_water(water))


func _make_label(text_value: String) -> Label:
	var label = Label.new()
	label.text = text_value
	return label


func _on_template_selected(index: int) -> void:
	_template_mode = _template_option.get_item_id(index)
	if _template_mode == TemplateMode.REDPINE_COUNTY:
		_map_width_spin.value = 1024
		_map_depth_spin.value = 1024
	else:
		_map_width_spin.value = 256
		_map_depth_spin.value = 256


func _on_radius_changed(value: float) -> void:
	_brush_radius = value
	_radius_label.text = "Radius: %.1f m" % value


func _on_strength_changed(value: float) -> void:
	_brush_strength = value
	_strength_label.text = "Strength: %.2f" % value


func _select_tool(mode: ToolMode) -> void:
	if _tool_mode == ToolMode.ROAD and mode != ToolMode.ROAD:
		_finish_active_road()
	if _tool_mode == ToolMode.WATER and mode != ToolMode.WATER:
		_finish_active_water()
	if _tool_mode == ToolMode.OBJECT_EDIT and mode != ToolMode.OBJECT_EDIT:
		_end_object_transform_drag()
	_tool_mode = mode
	_set_road_edit_visuals_visible(mode == ToolMode.ROAD)
	_set_water_edit_visuals_visible(mode == ToolMode.WATER)
	if mode != ToolMode.BUILDING:
		_set_building_preview_visible(false)
		if _brush_preview_material != null:
			_brush_preview_material.albedo_color = Color(1.0, 0.8, 0.1, 0.95)
	elif not _selected_building_asset.is_empty():
		_rebuild_building_preview()
	_set_farmland_cursor_preview_visible(mode == ToolMode.FARMLAND)
	_set_selection_visual_visible(mode == ToolMode.OBJECT_EDIT)
	_refresh_bottom_dock()
	_set_status("Tool: %s" % _tool_name(mode))

func _select_height_mode(mode: int) -> void:
	_height_mode = mode


func _select_surface(surface_id: int) -> void:
	_selected_surface_id = clampi(surface_id, 0, 255)


func _add_surface_entry() -> void:
	var before_entries = _surface_entries.duplicate(true)
	var before_mask: Image = null
	var used_ids: Dictionary = {}
	for entry_value in _surface_entries:
		var entry = entry_value as Dictionary
		used_ids[int(entry.get("id", 0))] = true

	var new_id = -1
	for candidate in range(256):
		if not used_ids.has(candidate):
			new_id = candidate
			break
	if new_id < 0:
		_set_status("Surface palette is full (256 IDs).")
		return

	var hue = fmod(0.17 * float(new_id + 1), 1.0)
	var new_color = Color.from_hsv(hue, 0.48, 0.72)
	_surface_entries.append({
		"label": "Surface %d" % new_id,
		"id": new_id,
		"color": new_color,
		"roughness": 0.9,
	})
	_selected_surface_id = new_id
	_rebuild_surface_palette_lookup()
	_refresh_bottom_dock()
	_commit_palette_change(
		"Add Surface Color",
		before_entries,
		before_mask,
		_surface_entries.duplicate(true),
		null
	)
	_set_status("Added terrain surface ID %d." % new_id)


func _remove_surface_entry(surface_id: int) -> void:
	var before_entries = _surface_entries.duplicate(true)
	var before_mask = _duplicate_surface_mask_image()
	var remove_index = _find_surface_entry_index(surface_id)
	if remove_index < 0:
		return
	if remove_index == 0:
		_set_status("The first palette color is the map base and cannot be removed.")
		return

	var default_id = _get_default_surface_id()
	_surface_entries.remove_at(remove_index)
	_remap_surface_mask_id(surface_id, default_id)
	if _selected_surface_id == surface_id:
		_selected_surface_id = default_id
	_rebuild_surface_palette_lookup()
	if _surface_mask_texture != null and _surface_mask_image != null:
		_surface_mask_texture.update(_surface_mask_image)
	_refresh_bottom_dock()
	_commit_palette_change(
		"Remove Surface Color",
		before_entries,
		before_mask,
		_surface_entries.duplicate(true),
		_duplicate_surface_mask_image()
	)
	_set_status(
		"Removed surface ID %d; painted pixels were restored to base ID %d."
		% [surface_id, default_id]
	)


func _on_surface_color_changed(color: Color, surface_id: int) -> void:
	if _palette_history_guard:
		return
	var entry_index = _find_surface_entry_index(surface_id)
	if entry_index < 0:
		return
	var entry = _surface_entries[entry_index] as Dictionary
	var old_color = entry.get("color", Color.WHITE) as Color
	var new_color = Color(color.r, color.g, color.b, 1.0)
	if old_color.is_equal_approx(new_color):
		return
	var before_entries = _surface_entries.duplicate(true)
	var before_mask: Image = null
	entry["color"] = new_color
	_surface_entries[entry_index] = entry
	_rebuild_surface_palette_lookup()
	_commit_palette_change(
		"Change Surface Color %d" % surface_id,
		before_entries,
		before_mask,
		_surface_entries.duplicate(true),
		null,
		true
	)
	_set_status("Updated surface ID %d color." % surface_id)


func _on_surface_name_submitted(new_text: String, surface_id: int) -> void:
	_set_surface_name(surface_id, new_text)


func _on_surface_name_focus_exited(surface_id: int, name_edit: LineEdit) -> void:
	if name_edit != null:
		_set_surface_name(surface_id, name_edit.text)


func _set_surface_name(surface_id: int, requested_name: String) -> void:
	var before_entries = _surface_entries.duplicate(true)
	var before_mask: Image = null
	var entry_index = _find_surface_entry_index(surface_id)
	if entry_index < 0:
		return
	var clean_name = requested_name.strip_edges()
	if clean_name.is_empty():
		clean_name = "Surface %d" % surface_id
	var entry = _surface_entries[entry_index] as Dictionary
	if str(entry.get("label", "")) == clean_name:
		return
	entry["label"] = clean_name
	_surface_entries[entry_index] = entry
	_refresh_bottom_dock()
	_commit_palette_change(
		"Rename Surface %d" % surface_id,
		before_entries,
		before_mask,
		_surface_entries.duplicate(true),
		null
	)
	_set_status("Renamed surface ID %d." % surface_id)


func _duplicate_surface_mask_image() -> Image:
	if _surface_mask_image == null:
		return null
	return _surface_mask_image.duplicate()


func _commit_palette_change(
	action_name: String,
	before_entries: Array,
	before_mask: Image,
	after_entries: Array,
	after_mask: Image,
	merge_continuous: bool = false
) -> void:
	if _palette_history_guard:
		return
	var merge_mode = (
		UndoRedo.MERGE_ENDS
		if merge_continuous
		else UndoRedo.MERGE_DISABLE
	)
	_undo_redo.create_action(action_name, merge_mode)
	_undo_redo.add_do_method(
		_apply_palette_state.bind(
			after_entries.duplicate(true),
			after_mask.duplicate() if after_mask != null else null
		)
	)
	_undo_redo.add_undo_method(
		_apply_palette_state.bind(
			before_entries.duplicate(true),
			before_mask.duplicate() if before_mask != null else null
		)
	)
	_undo_redo.commit_action(false)


func _apply_palette_state(entries: Array, mask_image: Image) -> void:
	_palette_history_guard = true
	_surface_entries = entries.duplicate(true)
	if mask_image != null:
		_surface_mask_image = mask_image.duplicate()
		if _surface_mask_texture == null:
			_surface_mask_texture = ImageTexture.create_from_image(
				_surface_mask_image
			)
			if _terrain_material != null:
				_terrain_material.set_shader_parameter(
					"surface_mask",
					_surface_mask_texture
				)
		else:
			_surface_mask_texture.update(_surface_mask_image)
	if _find_surface_entry_index(_selected_surface_id) < 0:
		_selected_surface_id = _get_default_surface_id()
	_rebuild_surface_palette_lookup()
	_refresh_bottom_dock()
	_palette_history_guard = false


func _find_surface_entry_index(surface_id: int) -> int:
	for index in range(_surface_entries.size()):
		var entry = _surface_entries[index] as Dictionary
		if int(entry.get("id", -1)) == surface_id:
			return index
	return -1


func _remap_surface_mask_id(old_id: int, replacement_id: int) -> void:
	if _surface_mask_image == null:
		return
	for y in range(_surface_mask_image.get_height()):
		for x in range(_surface_mask_image.get_width()):
			var pixel = _surface_mask_image.get_pixel(x, y)
			var base_id = clampi(roundi(pixel.r * 255.0), 0, 255)
			var overlay_id = clampi(roundi(pixel.g * 255.0), 0, 255)
			var blend = clampf(pixel.b, 0.0, 1.0)
			if base_id == old_id:
				base_id = replacement_id
			if overlay_id == old_id:
				overlay_id = replacement_id
			if base_id == overlay_id:
				blend = 0.0
			_surface_mask_image.set_pixel(
				x,
				y,
				Color(
					float(base_id) / 255.0,
					float(overlay_id) / 255.0,
					blend,
					1.0
				)
			)


func _select_grass_species(species: String) -> void:
	_selected_grass_species = species


func _select_asset(asset: Dictionary) -> void:
	_selected_asset = asset


func _select_spawn_kind(kind: String) -> void:
	_selected_spawn_kind = kind


func _tool_name(mode: ToolMode) -> String:
	match mode:
		ToolMode.TERRAIN: return "Terrain Height"
		ToolMode.SURFACE: return "Surface Paint"
		ToolMode.GRASS: return "Manual Grass"
		ToolMode.TREE: return "Trees"
		ToolMode.ORE: return "Ores"
		ToolMode.SPAWN: return "Spawn Points"
		ToolMode.BUILDING: return "Buildings"
		ToolMode.FARMLAND: return "Farmland"
		ToolMode.AUXILIARY: return "Auxiliary Areas"
		ToolMode.AI: return "Map AI Players"
		ToolMode.OBJECT_EDIT: return "Object Edit"
		ToolMode.ROAD: return "Roads"
		ToolMode.WATER: return "Water Bodies"
		_: return "Unavailable"


func _set_status(text_value: String) -> void:
	if _status_label != null:
		_status_label.text = text_value


# -----------------------------------------------------------------------------
# Editor camera, input and brush dispatch
# -----------------------------------------------------------------------------

func _build_editor_camera() -> void:
	_camera_rig = CharacterBody3D.new()
	_camera_rig.name = "EditorCameraRig"
	_camera_rig.collision_layer = 0
	_camera_rig.collision_mask = (
		TERRAIN_COLLISION_LAYER
		| BOUNDARY_COLLISION_LAYER
	)
	_camera_rig.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	add_child(_camera_rig)

	var collision = CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var sphere = SphereShape3D.new()
	sphere.radius = maxf(0.3, camera_ground_clearance * 0.45)
	collision.shape = sphere
	_camera_rig.add_child(collision)

	_editor_camera = Camera3D.new()
	_editor_camera.name = "EditorCamera"
	_editor_camera.current = true
	_editor_camera.near = 0.1
	_editor_camera.far = 5000.0
	_editor_camera.fov = 65.0
	_camera_rig.add_child(_editor_camera)
	_camera_rig.position = Vector3(0.0, 90.0, 110.0)
	_camera_yaw = 0.0
	_camera_pitch = deg_to_rad(-35.0)
	_apply_camera_rotation()


func _build_brush_preview() -> void:
	_brush_preview_mesh = ImmediateMesh.new()
	_brush_preview_material = StandardMaterial3D.new()
	_brush_preview_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_brush_preview_material.albedo_color = Color(1.0, 0.8, 0.1, 0.95)
	_brush_preview_material.no_depth_test = true

	_brush_preview = MeshInstance3D.new()
	_brush_preview.name = "TerrainContactBrush"
	_brush_preview.mesh = _brush_preview_mesh
	_brush_preview.material_override = _brush_preview_material
	_brush_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_brush_preview.visible = false
	add_child(_brush_preview)

	_height_boundary_mesh = ImmediateMesh.new()
	_height_boundary_material = StandardMaterial3D.new()
	_height_boundary_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_height_boundary_material.no_depth_test = true
	_height_boundary_material.albedo_color = Color(0.25, 0.85, 1.0, 0.95)
	_height_boundary_preview = MeshInstance3D.new()
	_height_boundary_preview.name = "TerrainHeightBoundary"
	_height_boundary_preview.mesh = _height_boundary_mesh
	_height_boundary_preview.material_override = _height_boundary_material
	_height_boundary_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_height_boundary_preview.visible = false
	_height_boundary_preview.set_meta(EDITOR_MARKER_META, true)
	add_child(_height_boundary_preview)

	# Persistent topographic contours remain visible after a terrain stroke ends.
	# They are separate from the one-stroke boundary above, so starting a new
	# brush stroke no longer erases the previously sculpted terrain information.
	_persistent_height_contour_mesh = ImmediateMesh.new()
	_persistent_height_contour_material = StandardMaterial3D.new()
	_persistent_height_contour_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_persistent_height_contour_material.no_depth_test = true
	_persistent_height_contour_material.vertex_color_use_as_albedo = true
	_persistent_height_contour_preview = MeshInstance3D.new()
	_persistent_height_contour_preview.name = "PersistentTerrainHeightContours"
	_persistent_height_contour_preview.mesh = _persistent_height_contour_mesh
	_persistent_height_contour_preview.material_override = _persistent_height_contour_material
	_persistent_height_contour_preview.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_persistent_height_contour_preview.visible = false
	_persistent_height_contour_preview.set_meta(EDITOR_MARKER_META, true)
	add_child(_persistent_height_contour_preview)


func _build_farmland_cursor_preview() -> void:
	_farmland_cursor_preview = Node3D.new()
	_farmland_cursor_preview.name = "FarmlandPlacementPreview"
	_farmland_cursor_preview.set_meta(EDITOR_MARKER_META, true)
	add_child(_farmland_cursor_preview)
	_create_farmland_preview_visuals(_farmland_cursor_preview)
	_farmland_cursor_preview.visible = false


func _create_farmland_preview_visuals(preview_root: Node3D) -> void:
	var fill := MeshInstance3D.new()
	fill.name = "Fill"
	fill.set_meta(EDITOR_MARKER_META, true)
	fill.mesh = BoxMesh.new()
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview_root.add_child(fill)
	var fill_material := StandardMaterial3D.new()
	fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	fill_material.no_depth_test = true
	fill.material_override = fill_material

	var outline := MeshInstance3D.new()
	outline.name = "Outline"
	outline.set_meta(EDITOR_MARKER_META, true)
	outline.mesh = ImmediateMesh.new()
	outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	preview_root.add_child(outline)
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.no_depth_test = true
	outline.material_override = outline_material


func _farmland_preview_color(owner: String, outline := false) -> Color:
	var color := Color(0.96, 0.96, 0.96, 0.22)
	if owner == "red":
		color = Color(0.95, 0.16, 0.16, 0.25)
	elif owner == "blue":
		color = Color(0.16, 0.36, 1.0, 0.25)
	if outline:
		color.a = 0.9
	return color


func _configure_farmland_preview(preview_root: Node3D, length_tiles: int, width_tiles: int, owner: String) -> void:
	if preview_root == null:
		return
	var length := maxi(1, length_tiles)
	var width := maxi(1, width_tiles)
	var size_x := float(length) * FARM_FIELD_TILE_SPACING
	var size_z := float(width) * FARM_FIELD_TILE_SPACING
	var center := Vector3(
		float(length - 1) * FARM_FIELD_TILE_SPACING * 0.5,
		0.05,
		float(width - 1) * FARM_FIELD_TILE_SPACING * 0.5
	)
	var fill := preview_root.get_node_or_null("Fill") as MeshInstance3D
	if fill != null:
		var box := fill.mesh as BoxMesh
		if box == null:
			box = BoxMesh.new()
			fill.mesh = box
		box.size = Vector3(size_x, 0.04, size_z)
		fill.position = center
		var fill_material := fill.material_override as StandardMaterial3D
		if fill_material != null:
			fill_material.albedo_color = _farmland_preview_color(owner)
	var outline := preview_root.get_node_or_null("Outline") as MeshInstance3D
	if outline != null:
		var line_mesh := outline.mesh as ImmediateMesh
		if line_mesh == null:
			line_mesh = ImmediateMesh.new()
			outline.mesh = line_mesh
		line_mesh.clear_surfaces()
		var outline_material := outline.material_override as StandardMaterial3D
		if outline_material != null:
			outline_material.albedo_color = _farmland_preview_color(owner, true)
		outline.position = center
		line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, outline_material)
		var half_x := size_x * 0.5
		var half_z := size_z * 0.5
		for point in [
			Vector3(-half_x, 0.085, -half_z),
			Vector3(half_x, 0.085, -half_z),
			Vector3(half_x, 0.085, half_z),
			Vector3(-half_x, 0.085, half_z),
			Vector3(-half_x, 0.085, -half_z),
		]:
			line_mesh.surface_add_vertex(point)
		line_mesh.surface_end()


func _refresh_farmland_preview(field: Node3D) -> void:
	if field == null or not _is_farmland(field):
		return
	var preview := field.get_node_or_null("_EditorFarmlandPreview") as Node3D
	if preview == null:
		preview = Node3D.new()
		preview.name = "_EditorFarmlandPreview"
		preview.set_meta(EDITOR_MARKER_META, true)
		field.add_child(preview)
		_create_farmland_preview_visuals(preview)
	_configure_farmland_preview(
		preview,
		int(_get_property_or(field, "length_tiles", _farmland_length_tiles)),
		int(_get_property_or(field, "width_tiles", _farmland_width_tiles)),
		str(_get_property_or(field, "field_owner", ""))
	)


func _refresh_all_farmland_previews() -> void:
	if _farmlands_root == null:
		return
	for child in _farmlands_root.get_children():
		if child is Node3D:
			_refresh_farmland_preview(child as Node3D)


func _update_farmland_cursor_preview(center: Vector3) -> void:
	if _farmland_cursor_preview == null:
		return
	_farmland_cursor_preview.global_position = center
	_configure_farmland_preview(_farmland_cursor_preview, _farmland_length_tiles, _farmland_width_tiles, _selected_farmland_owner)
	_farmland_cursor_preview.visible = true


func _update_farmland_cursor_preview_from_latest_hit() -> void:
	if _tool_mode != ToolMode.FARMLAND or _latest_hit.is_empty():
		if _farmland_cursor_preview != null:
			_farmland_cursor_preview.visible = false
		return
	_update_farmland_cursor_preview(_latest_hit.get("position", Vector3.ZERO) as Vector3)


func _set_farmland_cursor_preview_visible(value: bool) -> void:
	if _farmland_cursor_preview != null:
		_farmland_cursor_preview.visible = value and _tool_mode == ToolMode.FARMLAND



func _build_selection_visual() -> void:
	_selection_visual_mesh = ImmediateMesh.new()
	_selection_visual = MeshInstance3D.new()
	_selection_visual.name = "ObjectSelectionBounds"
	_selection_visual.mesh = _selection_visual_mesh
	_selection_visual.material_override = _make_unshaded_material(Color(0.1, 0.9, 1.0, 1.0))
	_selection_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_selection_visual.visible = false
	_selection_visual.set_meta(EDITOR_MARKER_META, true)
	add_child(_selection_visual)

func _build_transform_gizmo() -> void:
	_object_gizmo_mesh = ImmediateMesh.new()
	_object_gizmo_material = StandardMaterial3D.new()
	_object_gizmo_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_object_gizmo_material.vertex_color_use_as_albedo = true
	_object_gizmo_material.no_depth_test = true
	_object_gizmo_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_object_gizmo = MeshInstance3D.new()
	_object_gizmo.name = "RuntimeTransformGizmo"
	_object_gizmo.mesh = _object_gizmo_mesh
	_object_gizmo.material_override = _object_gizmo_material
	_object_gizmo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_object_gizmo.visible = false
	_object_gizmo.set_meta(EDITOR_MARKER_META, true)
	add_child(_object_gizmo)


func _build_building_footprint_preview() -> void:
	_building_footprint_fill_mesh = ImmediateMesh.new()
	_building_footprint_fill_material = StandardMaterial3D.new()
	_building_footprint_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_building_footprint_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_building_footprint_fill_material.no_depth_test = false
	_building_footprint_fill_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_building_footprint_fill = MeshInstance3D.new()
	_building_footprint_fill.name = "BuildingFootprintFill"
	_building_footprint_fill.mesh = _building_footprint_fill_mesh
	_building_footprint_fill.material_override = _building_footprint_fill_material
	_building_footprint_fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_building_footprint_fill.visible = false
	_building_footprint_fill.set_meta(EDITOR_MARKER_META, true)
	add_child(_building_footprint_fill)

	_building_footprint_outline_mesh = ImmediateMesh.new()
	_building_footprint_outline_material = StandardMaterial3D.new()
	_building_footprint_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_building_footprint_outline_material.no_depth_test = true
	_building_footprint_outline = MeshInstance3D.new()
	_building_footprint_outline.name = "BuildingFootprintOutline"
	_building_footprint_outline.mesh = _building_footprint_outline_mesh
	_building_footprint_outline.material_override = _building_footprint_outline_material
	_building_footprint_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_building_footprint_outline.visible = false
	_building_footprint_outline.set_meta(EDITOR_MARKER_META, true)
	add_child(_building_footprint_outline)

func _set_selection_visual_visible(value: bool) -> void:
	if _selection_visual != null:
		_selection_visual.visible = value and is_instance_valid(_selected_map_object)
	if _object_gizmo != null:
		_object_gizmo.visible = value and is_instance_valid(_selected_map_object)
	if value:
		_refresh_selection_visual()
		_refresh_transform_gizmo()
	else:
		_hide_building_footprint_preview()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_button = event as InputEventMouseButton

		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			_camera_look_active = mouse_button.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mouse_button.pressed else Input.MOUSE_MODE_VISIBLE
			get_viewport().set_input_as_handled()
			return

		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			if mouse_button.pressed:
				if _pointer_is_over_ui() or _map_root == null:
					return
				if _tool_mode == ToolMode.ROAD:
					_handle_road_left_press()
				elif _tool_mode == ToolMode.WATER:
					_handle_water_left_press()
				elif _tool_mode == ToolMode.OBJECT_EDIT:
					_handle_object_edit_left_press()
				else:
					_begin_stroke()
			else:
				if _tool_mode == ToolMode.ROAD:
					_end_road_point_drag()
				elif _tool_mode == ToolMode.WATER:
					_update_water_preview_from_latest_hit()
				elif _tool_mode == ToolMode.OBJECT_EDIT:
					_end_object_transform_drag()
				else:
					_end_stroke()
			get_viewport().set_input_as_handled()
			return

		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_UP:
			_camera_speed = minf(_camera_speed * 1.15, 500.0)
			_set_status("Camera speed: %.1f" % _camera_speed)
			return
		if mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_camera_speed = maxf(_camera_speed / 1.15, 2.0)
			_set_status("Camera speed: %.1f" % _camera_speed)
			return

	if event is InputEventMouseMotion and _object_dragging and _tool_mode == ToolMode.OBJECT_EDIT:
		_update_object_gizmo_drag(get_viewport().get_mouse_position())
		get_viewport().set_input_as_handled()
		return

	if event is InputEventMouseMotion and _camera_look_active:
		var motion = event as InputEventMouseMotion
		_camera_yaw -= motion.relative.x * 0.003
		_camera_pitch = clampf(_camera_pitch - motion.relative.y * 0.003, deg_to_rad(-89.0), deg_to_rad(89.0))
		_apply_camera_rotation()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey:
		var key_event = event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		var command_pressed = key_event.ctrl_pressed or key_event.meta_pressed
		if command_pressed and key_event.keycode == KEY_Z:
			_end_stroke()
			_end_object_transform_drag()
			if key_event.shift_pressed:
				_redo_last_action()
			else:
				_undo_last_action()
			get_viewport().set_input_as_handled()
			return
		if command_pressed and key_event.keycode == KEY_Y:
			_end_stroke()
			_end_object_transform_drag()
			_redo_last_action()
			get_viewport().set_input_as_handled()
			return
		if command_pressed and key_event.keycode == KEY_S:
			save_current_map()
			get_viewport().set_input_as_handled()
			return
		if command_pressed and key_event.keycode == KEY_D and _tool_mode == ToolMode.OBJECT_EDIT:
			_duplicate_selected_object()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.BUILDING and key_event.keycode == KEY_R:
			_building_preview_yaw += deg_to_rad(building_rotation_step_degrees)
			_update_building_preview_from_latest_hit()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.OBJECT_EDIT and key_event.keycode == KEY_G:
			_set_object_transform_mode(ObjectTransformMode.MOVE)
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.OBJECT_EDIT and key_event.keycode == KEY_R:
			_set_object_transform_mode(ObjectTransformMode.ROTATE)
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.OBJECT_EDIT and key_event.keycode == KEY_S:
			_set_object_transform_mode(ObjectTransformMode.SCALE)
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.OBJECT_EDIT and key_event.keycode == KEY_DELETE:
			_delete_selected_object()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.ROAD and key_event.keycode == KEY_ENTER:
			_finish_active_road()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.WATER and key_event.keycode == KEY_ENTER:
			_finish_active_water()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.ROAD and key_event.keycode == KEY_ESCAPE:
			_cancel_active_road()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.WATER and key_event.keycode == KEY_ESCAPE:
			_cancel_active_water()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.ROAD and key_event.keycode == KEY_DELETE:
			if _road_selected_point >= 0:
				_delete_selected_road_point()
			else:
				_delete_selected_road()
			get_viewport().set_input_as_handled()
			return
		if _tool_mode == ToolMode.WATER and key_event.keycode == KEY_DELETE:
			_delete_selected_water()
			get_viewport().set_input_as_handled()
			return
		if key_event.keycode == KEY_BRACKETLEFT:
			_brush_radius = maxf(1.0, _brush_radius - 1.0)
			_radius_label.text = "Radius: %.1f m" % _brush_radius
			return
		if key_event.keycode == KEY_BRACKETRIGHT:
			_brush_radius = minf(64.0, _brush_radius + 1.0)
			_radius_label.text = "Radius: %.1f m" % _brush_radius
			return
		match key_event.keycode:
			KEY_1: _press_tool_shortcut(ToolMode.TERRAIN)
			KEY_2: _press_tool_shortcut(ToolMode.SURFACE)
			KEY_3: _press_tool_shortcut(ToolMode.ROAD)
			KEY_4: _press_tool_shortcut(ToolMode.GRASS)
			KEY_5: _press_tool_shortcut(ToolMode.TREE)
			KEY_6: _press_tool_shortcut(ToolMode.ORE)
			KEY_7: _press_tool_shortcut(ToolMode.SPAWN)
			KEY_8: _press_tool_shortcut(ToolMode.BUILDING)
			KEY_9: _press_tool_shortcut(ToolMode.OBJECT_EDIT)

func _press_tool_shortcut(mode: ToolMode) -> void:
	var button = _tool_buttons.get(mode, null) as Button
	if button != null:
		button.button_pressed = true
	_select_tool(mode)


func _process(delta: float) -> void:
	_update_free_camera(delta)
	if (
		_boundary_warning_label != null
		and _boundary_warning_label.visible
		and Time.get_ticks_msec() >= _boundary_warning_until_msec
	):
		_boundary_warning_label.visible = false
	_placement_timer = maxf(0.0, _placement_timer - delta)
	# A UI control can consume the mouse-release event after a drag crosses
	# onto a panel, so also finish the stroke by polling the physical button.
	if _stroke_active and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_stroke()
	if _object_dragging and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_end_object_transform_drag()


func _physics_process(delta: float) -> void:
	if _map_root == null or _editor_camera == null:
		_brush_preview.visible = false
		_set_height_boundary_visible(false)
		_set_persistent_height_contour_visible(false)
		return
	_set_persistent_height_contour_visible(
		_tool_mode == ToolMode.TERRAIN
		and not (_stroke_active and _stroke_tool_mode == ToolMode.TERRAIN)
	)

	_latest_hit = _raycast_terrain()
	if _tool_mode == ToolMode.OBJECT_EDIT:
		_brush_preview.visible = false
		_set_farmland_cursor_preview_visible(false)
		_set_height_boundary_visible(false)
		_set_building_preview_visible(false)
		_refresh_selection_visual()
		_refresh_transform_gizmo()
		return

	if _latest_hit.is_empty():
		_brush_preview.visible = false
		_set_farmland_cursor_preview_visible(false)
		_set_height_boundary_visible(false)
		if _tool_mode == ToolMode.BUILDING:
			_set_building_preview_visible(false)
		return

	var hit_position = _latest_hit.get("position", Vector3.ZERO) as Vector3
	if _tool_mode == ToolMode.ROAD:
		_brush_preview.visible = false
		_set_height_boundary_visible(false)
		_update_road_preview(hit_position)
		if _road_dragging and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _pointer_is_over_ui():
			_drag_selected_road_point(hit_position)
		return
	if _tool_mode == ToolMode.WATER:
		_brush_preview.visible = false
		_set_height_boundary_visible(false)
		_update_water_preview(hit_position)
		return
	if _tool_mode == ToolMode.FARMLAND:
		_brush_preview.visible = false
		_set_height_boundary_visible(false)
		_update_farmland_cursor_preview(hit_position)
	else:
		_set_farmland_cursor_preview_visible(false)
	if _tool_mode == ToolMode.BUILDING:
		_set_height_boundary_visible(false)
		_update_building_preview(hit_position)
	else:
		_set_building_preview_visible(false)
	if _tool_mode != ToolMode.FARMLAND:
		_update_contact_brush(hit_position)
	if _tool_mode == ToolMode.TERRAIN:
		_update_height_boundary()
	else:
		_set_height_boundary_visible(false)

	if not _stroke_active or _camera_look_active or _pointer_is_over_ui():
		return

	match _tool_mode:
		ToolMode.TERRAIN:
			_apply_height_brush(hit_position, delta)
		ToolMode.SURFACE:
			_apply_surface_brush(hit_position, delta)
		ToolMode.GRASS:
			_apply_grass_brush(hit_position, delta)
		ToolMode.TREE:
			_apply_scene_placement_brush(hit_position, delta, _trees_root, "tree")
		ToolMode.ORE:
			_apply_scene_placement_brush(hit_position, delta, _ores_root, "ore")
		ToolMode.SPAWN:
			_apply_spawn_brush(hit_position)
		ToolMode.AUXILIARY:
			_apply_auxiliary_brush(hit_position)
		ToolMode.FARMLAND:
			_apply_farmland_brush(hit_position)
		ToolMode.BUILDING:
			_apply_building_placement(hit_position)

func _update_free_camera(delta: float) -> void:
	if _editor_camera == null or _camera_rig == null:
		return

	var move = Vector3.ZERO
	var forward = -_editor_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var right = _editor_camera.global_basis.x
	right.y = 0.0
	right = right.normalized()

	if Input.is_key_pressed(KEY_W): move += forward
	if Input.is_key_pressed(KEY_S): move -= forward
	if Input.is_key_pressed(KEY_D): move += right
	if Input.is_key_pressed(KEY_A): move -= right
	if Input.is_key_pressed(KEY_E): move += Vector3.UP
	if Input.is_key_pressed(KEY_Q): move -= Vector3.UP

	if move.length_squared() > 0.0001:
		var speed_multiplier = 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
		var motion = (
			move.normalized()
			* _camera_speed
			* speed_multiplier
			* delta
		)
		_camera_rig.move_and_collide(motion)

	_camera_rig.global_position = _clamp_editor_camera_above_ground(
		_camera_rig.global_position
	)


func _apply_camera_rotation() -> void:
	if _editor_camera != null:
		_editor_camera.rotation = Vector3(_camera_pitch, _camera_yaw, 0.0)


func _pointer_is_over_ui() -> bool:
	return get_viewport().gui_get_hovered_control() != null


func _begin_stroke() -> void:
	if _stroke_active:
		return
	_stroke_active = true
	_stroke_tool_mode = _tool_mode
	_stroke_placed_once = false
	_placement_timer = 0.0
	_stroke_height_before.clear()
	if _stroke_tool_mode == ToolMode.TERRAIN:
		_height_contour_points.clear()
		_height_contour_delta = 0.0
		_set_height_boundary_visible(false)
		# The current stroke is shown by the temporary boundary. Hide the saved
		# contour layer underneath it so the same region never renders duplicate
		# outlines while it is being sculpted.
		_set_persistent_height_contour_visible(false)
	_stroke_surface_before.clear()
	_stroke_grass_before.clear()
	_stroke_added_objects.clear()
	_stroke_removed_objects.clear()
	if _height_mode == HeightMode.FLATTEN and not _latest_hit.is_empty():
		_flatten_target_height = (_latest_hit.get("position", Vector3.ZERO) as Vector3).y


func _end_stroke() -> void:
	if not _stroke_active:
		return
	_stroke_active = false
	_stroke_placed_once = false
	_flush_terrain_collision_updates()

	match _stroke_tool_mode:
		ToolMode.TERRAIN:
			_commit_height_stroke()
			_rebuild_persistent_height_contours()
			_height_contour_points.clear()
			_height_contour_delta = 0.0
			_set_height_boundary_visible(false)
			_set_persistent_height_contour_visible(_tool_mode == ToolMode.TERRAIN)
			call_deferred("_rebuild_all_roads_to_terrain")
		ToolMode.SURFACE:
			_commit_surface_stroke()
		ToolMode.GRASS:
			_commit_grass_stroke()
		ToolMode.TREE, ToolMode.ORE, ToolMode.SPAWN, ToolMode.BUILDING, ToolMode.AUXILIARY, ToolMode.FARMLAND:
			_commit_object_stroke()

	_stroke_height_before.clear()
	_stroke_surface_before.clear()
	_stroke_grass_before.clear()
	_stroke_added_objects.clear()
	_stroke_removed_objects.clear()


func _undo_last_action() -> void:
	if not _undo_redo.has_undo():
		_set_status("Nothing to undo")
		return
	var action_name = _undo_redo.get_current_action_name()
	_undo_redo.undo()
	_set_status("Undo: %s" % action_name)


func _redo_last_action() -> void:
	if not _undo_redo.has_redo():
		_set_status("Nothing to redo")
		return
	_undo_redo.redo()
	_set_status("Redo completed")


func _reset_undo_history() -> void:
	_undo_redo.clear_history(false)
	_saved_undo_version = _undo_redo.get_version()


func has_unsaved_changes() -> bool:
	return _undo_redo.get_version() != _saved_undo_version


func _raycast_terrain() -> Dictionary:
	var mouse_position = get_viewport().get_mouse_position()
	var ray_from = _editor_camera.project_ray_origin(mouse_position)
	var ray_direction = _editor_camera.project_ray_normal(mouse_position)
	var ray_to = ray_from + ray_direction * MAX_RAY_DISTANCE
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to, TERRAIN_COLLISION_LAYER)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return get_world_3d().direct_space_state.intersect_ray(query)


func _update_contact_brush(center: Vector3) -> void:
	if _brush_preview_mesh == null:
		return
	_brush_preview_mesh.clear_surfaces()
	_brush_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _brush_preview_material)
	var segments = 64
	for index in range(segments + 1):
		var angle = TAU * float(index) / float(segments)
		var x = center.x + cos(angle) * _brush_radius
		var z = center.z + sin(angle) * _brush_radius
		var y = get_terrain_height_world(Vector2(x, z)) + 0.08
		_brush_preview_mesh.surface_add_vertex(Vector3(x, y, z))
	_brush_preview_mesh.surface_end()
	# The original brush ring remains a terrain-following cursor preview. The
	# height-change contour is rendered separately from actual changed samples.
	_brush_preview.visible = true


func _set_height_boundary_visible(value: bool) -> void:
	if _height_boundary_preview != null:
		_height_boundary_preview.visible = value


func _set_persistent_height_contour_visible(value: bool) -> void:
	_persistent_height_contour_visible = value
	if _persistent_height_contour_preview != null:
		_persistent_height_contour_preview.visible = value \
			and _persistent_height_contour_mesh != null \
			and _persistent_height_contour_mesh.get_surface_count() > 0


func _rebuild_persistent_height_contours() -> void:
	if _persistent_height_contour_mesh == null or _persistent_height_contour_material == null:
		return
	_persistent_height_contour_mesh.clear_surfaces()
	if _height_samples.is_empty() or _sample_width < 2 or _sample_depth < 2:
		_set_persistent_height_contour_visible(false)
		return

	# Keep the editor responsive on 1024 m maps by sampling at most a 192 x 192
	# contour grid. Small maps retain their full height-sample resolution.
	var contour_grid_limit := 192
	var largest_dimension := maxi(_sample_width, _sample_depth) - 1
	var sample_step := maxi(1, ceili(float(largest_dimension) / float(contour_grid_limit)))
	var contour_offsets: Array[float] = [-4.0, -2.0, -1.0, -0.5, 0.0, 0.5, 1.0, 2.0, 4.0]
	var baseline := float(initial_ground_height)
	var contour_vertices: Array[Vector3] = []
	var contour_colors: Array[Color] = []
	for offset in contour_offsets:
		var threshold := baseline + offset
		var contour_color := Color(0.78, 0.35, 1.0, 0.78)
		if offset > 0.0:
			contour_color = Color(1.0, 0.22, 0.08, 0.82)
		elif offset < 0.0:
			contour_color = Color(0.12, 0.48, 1.0, 0.82)
		for sample_z in range(0, _sample_depth - sample_step, sample_step):
			for sample_x in range(0, _sample_width - sample_step, sample_step):
				var p00 := Vector2(
					_terrain_origin.x + float(sample_x) * vertex_spacing,
					_terrain_origin.y + float(sample_z) * vertex_spacing
				)
				var p10 := Vector2(
					_terrain_origin.x + float(sample_x + sample_step) * vertex_spacing,
					_terrain_origin.y + float(sample_z) * vertex_spacing
				)
				var p11 := Vector2(
					_terrain_origin.x + float(sample_x + sample_step) * vertex_spacing,
					_terrain_origin.y + float(sample_z + sample_step) * vertex_spacing
				)
				var p01 := Vector2(
					_terrain_origin.x + float(sample_x) * vertex_spacing,
					_terrain_origin.y + float(sample_z + sample_step) * vertex_spacing
				)
				var h00 := _get_height_sample(sample_x, sample_z)
				var h10 := _get_height_sample(sample_x + sample_step, sample_z)
				var h11 := _get_height_sample(sample_x + sample_step, sample_z + sample_step)
				var h01 := _get_height_sample(sample_x, sample_z + sample_step)
				var intersections: Array[Vector2] = []
				_append_height_contour_intersection(intersections, p00, h00, p10, h10, threshold)
				_append_height_contour_intersection(intersections, p10, h10, p11, h11, threshold)
				_append_height_contour_intersection(intersections, p11, h11, p01, h01, threshold)
				_append_height_contour_intersection(intersections, p01, h01, p00, h00, threshold)
				if intersections.size() == 2:
					_append_height_contour_segment(contour_vertices, contour_colors, intersections[0], intersections[1], threshold, contour_color)
				elif intersections.size() == 4:
					_append_height_contour_segment(contour_vertices, contour_colors, intersections[0], intersections[1], threshold, contour_color)
					_append_height_contour_segment(contour_vertices, contour_colors, intersections[2], intersections[3], threshold, contour_color)

	if contour_vertices.size() < 2:
		_set_persistent_height_contour_visible(false)
		return
	_persistent_height_contour_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _persistent_height_contour_material)
	for index in contour_vertices.size():
		_persistent_height_contour_mesh.surface_set_color(contour_colors[index])
		_persistent_height_contour_mesh.surface_add_vertex(contour_vertices[index])
	_persistent_height_contour_mesh.surface_end()
	_set_persistent_height_contour_visible(_persistent_height_contour_visible)


func _append_height_contour_intersection(
	intersections: Array[Vector2],
	from_point: Vector2,
	from_height: float,
	to_point: Vector2,
	to_height: float,
	threshold: float
) -> void:
	if is_equal_approx(from_height, to_height):
		return
	var low := minf(from_height, to_height)
	var high := maxf(from_height, to_height)
	if threshold < low or threshold > high:
		return
	var ratio := clampf((threshold - from_height) / (to_height - from_height), 0.0, 1.0)
	var point := from_point.lerp(to_point, ratio)
	for existing in intersections:
		if existing.distance_squared_to(point) < 0.0001:
			return
	intersections.append(point)


func _append_height_contour_segment(
	vertices: Array[Vector3],
	colors: Array[Color],
	from_point: Vector2,
	to_point: Vector2,
	threshold: float,
	color: Color
) -> void:
	var contour_y := threshold + 0.10
	vertices.append(Vector3(from_point.x, contour_y, from_point.y))
	vertices.append(Vector3(to_point.x, contour_y, to_point.y))
	colors.append(color)
	colors.append(color)


func _update_height_boundary() -> void:
	if _height_boundary_mesh == null or _height_boundary_material == null:
		return
	_height_boundary_mesh.clear_surfaces()
	if _height_contour_points.size() < 2:
		_set_height_boundary_visible(false)
		return
	var boundary_color := Color(0.25, 0.85, 1.0, 0.95)
	if _height_contour_delta > 0.001:
		boundary_color = Color(1.0, 0.38, 0.12, 0.98)
	elif _height_contour_delta < -0.001:
		boundary_color = Color(0.20, 0.52, 1.0, 0.98)
	else:
		boundary_color = Color(0.78, 0.35, 1.0, 0.98)
	_height_boundary_material.albedo_color = boundary_color
	_height_boundary_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, _height_boundary_material)
	for point in _height_contour_points:
		var y := get_terrain_height_world(point) + 0.12
		_height_boundary_mesh.surface_add_vertex(Vector3(point.x, y, point.y))
	var first_point := _height_contour_points[0]
	_height_boundary_mesh.surface_add_vertex(
		Vector3(first_point.x, get_terrain_height_world(first_point) + 0.12, first_point.y)
	)
	_height_boundary_mesh.surface_end()
	_set_height_boundary_visible(true)


# -----------------------------------------------------------------------------
# New map and FarmWar map skeleton
# -----------------------------------------------------------------------------

func _create_map_from_ui() -> void:
	var requested_display_name = _map_name_edit.text.strip_edges()
	if requested_display_name.is_empty():
		requested_display_name = "New Farm Map"
	var requested_map_id = _map_id_edit.text.strip_edges()
	var requested_version = _map_version_edit.text.strip_edges()
	if requested_version.is_empty():
		requested_version = default_map_version
	var requested_size = Vector2i(
		maxi(32, int(_map_width_spin.value)),
		maxi(32, int(_map_depth_spin.value))
	)
	create_new_map(
		requested_display_name,
		requested_size,
		_template_mode,
		requested_map_id,
		requested_version
	)


func create_new_map(
	name_value: String,
	size_value: Vector2i,
	template: TemplateMode,
	map_id_value: String = "",
	version_value: String = "1.0.0"
) -> void:
	_set_status("Creating map...")
	_end_stroke()
	_current_map_folder = ""
	_reset_road_editor_state()
	_reset_water_editor_state()
	_clear_selected_map_object()
	_clear_building_preview()

	if is_instance_valid(_map_root):
		var previous_map = _map_root
		if previous_map.get_parent() != null:
			previous_map.get_parent().remove_child(previous_map)
		previous_map.queue_free()
		_map_root = null

	_display_name = name_value.strip_edges()
	if _display_name.is_empty():
		_display_name = "New Farm Map"
	_map_id = _make_map_id(
		map_id_value
		if not map_id_value.strip_edges().is_empty()
		else _display_name
	)
	_map_name = _map_id
	_map_version = version_value.strip_edges()
	if _map_version.is_empty():
		_map_version = default_map_version
	if _map_id_edit != null:
		_map_id_edit.text = _map_id
	if _map_version_edit != null:
		_map_version_edit.text = _map_version
	_map_size = Vector2(
		maxf(32.0, float(size_value.x)),
		maxf(32.0, float(size_value.y))
	)
	_template_mode = template
	_terrain_origin = -_map_size * 0.5
	_sample_width = int(round(_map_size.x / vertex_spacing)) + 1
	_sample_depth = int(round(_map_size.y / vertex_spacing)) + 1

	_height_samples = PackedFloat32Array()
	_height_samples.resize(_sample_width * _sample_depth)
	_height_samples.fill(initial_ground_height)

	# Load the selected template palette before initializing the mask. The whole
	# map starts with the palette's configured default surface rather than an
	# assumed hard-coded color/ID.
	_load_template_surface_resources()
	var default_surface_id = _get_default_surface_id()
	var default_encoded = float(default_surface_id) / 255.0
	_selected_surface_id = default_surface_id

	_surface_mask_image = Image.create(
		surface_mask_resolution,
		surface_mask_resolution,
		false,
		Image.FORMAT_RGBA8
	)
	# FarmWar mask encoding: R=base ID, G=overlay ID, B=blend. A is unused
	# by the terrain shader, but keep it opaque for exported PNG inspection.
	_surface_mask_image.fill(Color(default_encoded, default_encoded, 0.0, 1.0))
	_surface_mask_texture = ImageTexture.create_from_image(_surface_mask_image)

	_manual_grass = _new_manual_grass_data()
	_grass_generated_nodes.clear()
	_terrain_chunks.clear()
	_terrain_collision_shapes.clear()
	_collision_dirty_chunks.clear()
	_next_object_id = 1
	_next_spawn_id = 1
	_ai_configurations = []
	_selected_ai_index = -1
	_clear_map_icon()

	_create_terrain_material()

	_map_root = Node3D.new()
	_map_root.name = _map_id.validate_node_name()
	_map_root.set_meta("farmwar_map_format_version", 5)
	_map_root.set_meta("farmwar_map_id", _map_id)
	_map_root.set_meta("farmwar_display_name", _display_name)
	_map_root.set_meta("farmwar_map_version", _map_version)
	_map_root.set_meta("farmwar_map_name", _map_id)
	_map_root.set_meta("farmwar_map_size", _map_size)
	_map_root.set_meta("farmwar_terrain_winding_version", 2)
	_map_root.set_meta("farmwar_editor_generated", true)
	_map_root.set_meta("farmwar_ai_configuration", _ai_configurations.duplicate(true))
	add_child(_map_root)

	_create_environment_skeleton()
	_create_map_content_roots()
	_create_boundary_walls()
	_create_terrain_chunks()
	_rebuild_persistent_height_contours()
	_create_terrain_foundation()
	_configure_integrated_systems()
	_configure_camera_for_map_and_far_scenery()
	_focus_camera_on_map()
	_refresh_bottom_dock()
	_reset_undo_history()

	_set_status("Created %s [%s] (%d x %d m, %d x %d height samples)" % [
		_display_name,
		_map_id,
		int(_map_size.x),
		int(_map_size.y),
		_sample_width,
		_sample_depth,
	])


func _load_template_surface_resources() -> void:
	var palette_path = CRESTON_PALETTE_PATH
	if _template_mode == TemplateMode.REDPINE_COUNTY:
		palette_path = REDPINE_PALETTE_PATH

	_surface_palette_resource = _load_resource_or_null(palette_path)
	_surface_entries = _extract_surface_entries(_surface_palette_resource)
	if _surface_entries.is_empty():
		_surface_entries = FALLBACK_SURFACES.duplicate(true)

	# The first visible palette entry is deliberately the default surface. This
	# matches the map editor UI and avoids a hidden default ID disagreeing with
	# the color users see first.
	_rebuild_surface_palette_lookup()


func _extract_surface_entries(palette: Resource) -> Array:
	var result: Array = []
	if palette == null or not _has_property(palette, "surfaces"):
		return result

	var surfaces_value = palette.get("surfaces")
	if not (surfaces_value is Array):
		return result

	for surface_value in surfaces_value:
		if surface_value == null:
			continue
		var surface_object = surface_value as Object
		var surface_id = clampi(
			int(_get_property_or(surface_object, "surface_id", result.size())),
			0,
			255
		)
		var display_name = str(
			_get_property_or(
				surface_object,
				"display_name",
				"Surface %d" % surface_id
			)
		)
		var display_color = _get_property_or(
			surface_object,
			"color",
			Color.WHITE
		) as Color
		var roughness = clampf(
			float(_get_property_or(surface_object, "roughness", 0.9)),
			0.0,
			1.0
		)
		result.append({
			"label": display_name,
			"id": surface_id,
			"color": display_color,
			"roughness": roughness,
		})
	return result


func _sync_surface_palette_resource_from_entries() -> void:
	var palette_script = _load_resource_or_null(
		SURFACE_PALETTE_SCRIPT_PATH
	) as Script
	var definition_script = _load_resource_or_null(
		SURFACE_DEFINITION_SCRIPT_PATH
	) as Script
	if palette_script == null or definition_script == null:
		return

	var runtime_palette = Resource.new()
	runtime_palette.set_script(palette_script)
	if not _has_property(runtime_palette, "surfaces"):
		return

	# Read the typed Array created by TerrainSurfacePalette, then append
	# TerrainSurfaceDefinition resources so the existing TerrainSurfaceBaker can
	# use colors added from this runtime editor as well.
	var typed_surfaces = runtime_palette.get("surfaces")
	for entry_value in _surface_entries:
		var entry = entry_value as Dictionary
		var definition = Resource.new()
		definition.set_script(definition_script)
		_set_property_if_present(
			definition,
			"surface_id",
			clampi(int(entry.get("id", 0)), 0, 255)
		)
		_set_property_if_present(
			definition,
			"display_name",
			str(entry.get("label", "Surface"))
		)
		_set_property_if_present(
			definition,
			"color",
			entry.get("color", Color.WHITE) as Color
		)
		_set_property_if_present(
			definition,
			"roughness",
			clampf(float(entry.get("roughness", 0.9)), 0.0, 1.0)
		)
		typed_surfaces.append(definition)

	runtime_palette.set("surfaces", typed_surfaces)
	_set_property_if_present(
		runtime_palette,
		"default_surface_id",
		_get_default_surface_id()
	)
	_surface_palette_resource = runtime_palette

	if _terrain_baker != null:
		_set_property_if_present(
			_terrain_baker,
			"palette",
			_surface_palette_resource
		)


func _get_default_surface_id() -> int:
	if not _surface_entries.is_empty():
		return clampi(
			int((_surface_entries[0] as Dictionary).get("id", 0)),
			0,
			255
		)
	return 0


func _create_terrain_material() -> void:
	_terrain_material = ShaderMaterial.new()
	var source_shader = _load_resource_or_null(TERRAIN_SHADER_PATH) as Shader
	if source_shader == null:
		push_error("FarmWar map editor: missing terrain shader: %s" % TERRAIN_SHADER_PATH)
		return

	# Use the same single-sided receiver as Creston. The generated index order
	# follows Godot's renderer front-face convention; vertex normals remain +Y.
	_terrain_material.shader = source_shader
	_terrain_material.set_shader_parameter("surface_mask", _surface_mask_texture)
	_terrain_material.set_shader_parameter("surface_palette", _surface_palette_lookup)
	_terrain_material.set_shader_parameter("terrain_origin", _terrain_origin)
	_terrain_material.set_shader_parameter("terrain_size", _map_size)


func _create_environment_skeleton() -> void:
	var sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.945, 0.816)
	sun.shadow_enabled = true
	# Match Creston Town's stable default directional-shadow setup. Enlarging a
	# cascaded shadow map to 512m produced a visible camera-following square on
	# generated terrain instead of a natural local object shadow.
	sun.directional_shadow_max_distance = 100.0
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	_map_root.add_child(sun)

	var world_environment = WorldEnvironment.new()
	world_environment.name = "WorldEnvironment"
	var environment = Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.8
	var sky_material = ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.459, 0.741, 0.922)
	sky_material.sky_horizon_color = Color(0.867, 0.937, 0.788)
	sky_material.ground_bottom_color = Color(0.306, 0.435, 0.271)
	sky_material.ground_horizon_color = Color(0.788, 0.835, 0.659)
	var sky = Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	world_environment.environment = environment
	_map_root.add_child(world_environment)

	var navigation = NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var navigation_mesh = NavigationMesh.new()
	navigation_mesh.agent_height = 1.8
	navigation_mesh.agent_radius = 0.4
	navigation.navigation_mesh = navigation_mesh
	_map_root.add_child(navigation)

	var cloud_scene = _load_resource_or_null(CLOUD_SYSTEM_PATH) as PackedScene
	if cloud_scene != null:
		var cloud_system = cloud_scene.instantiate()
		cloud_system.name = "CloudSystem"
		_set_property_if_present(cloud_system, "coverage_size", Vector2(maxf(_map_size.x, 1024.0), maxf(_map_size.y, 1024.0)))
		_set_property_if_present(cloud_system, "cloud_visibility_distance", maxf(_map_size.length(), 500.0))
		_map_root.add_child(cloud_system)

	# Keep gameplay day/night in the generated map package, but disable it in
	# the runtime editor so lighting never changes while the user is editing.
	var day_night_scene = _load_resource_or_null(DAY_NIGHT_SYSTEM_PATH) as PackedScene
	if day_night_scene != null:
		_day_night_system = day_night_scene.instantiate()
		_day_night_system.name = "DayNightSystem"
		# Match Creston Town's morning lighting.  Noon pushes directional shadows
		# almost directly underneath props, which makes newly generated maps look
		# as if they have no shadows at all even when shadow rendering is active.
		_set_property_if_present(_day_night_system, "initial_hour", 10.0)
		_day_night_system.process_mode = Node.PROCESS_MODE_DISABLED
		_map_root.add_child(_day_night_system)

	var weather_scene = _load_resource_or_null(WEATHER_SYSTEM_PATH) as PackedScene
	if weather_scene != null:
		_weather_system = weather_scene.instantiate()
		_weather_system.name = "WeatherSystem"
		_weather_system.process_mode = Node.PROCESS_MODE_DISABLED
		_map_root.add_child(_weather_system)


func _create_map_content_roots() -> void:
	# Match the existing FarmWar map skeleton: one explicit Ground StaticBody3D
	# owns all terrain collision shapes, while chunk meshes are grouped below it.
	_ground_body = StaticBody3D.new()
	_ground_body.name = "Ground"
	_ground_body.collision_layer = TERRAIN_COLLISION_LAYER
	_ground_body.collision_mask = 14334
	_ground_body.set_meta("farmwar_editor_terrain", true)
	_map_root.add_child(_ground_body)

	_terrain_root = _new_child_node3d(_ground_body, "Grass")
	_terrain_foundation_root = _new_child_node3d(_map_root, "TerrainFoundation")
	_boundary_root = _new_child_node3d(_map_root, "MapBoundaryWalls")
	_surface_areas_root = _new_child_node3d(_map_root, "SurfaceAreas")
	_roads_root = _new_child_node3d(_map_root, "Roads")
	_water_root = _new_child_node3d(_map_root, "WaterBodies")
	_manual_grass_root = _new_child_node3d(_map_root, "ManualGrass")
	_trees_root = _new_child_node3d(_map_root, "Trees")
	_ores_root = _new_child_node3d(_map_root, "Ores")
	_spawns_root = _new_child_node3d(_map_root, "SpawnPoints")
	_buildings_root = _new_child_node3d(_map_root, "Buildings")
	_farmlands_root = _new_child_node3d(_map_root, "FarmFields")
	_power_wires_root = _new_child_node3d(_map_root, POWER_WIRE_ROOT_NAME)

	var tree_script = _load_resource_or_null(TREE_FOREST_MANAGER_PATH) as Script
	_tree_forest_manager = Node3D.new()
	_tree_forest_manager.name = "TreeForestManager"
	if tree_script != null:
		_tree_forest_manager.set_script(tree_script)
	_map_root.add_child(_tree_forest_manager)

	var far_script = _load_resource_or_null(FAR_SCENERY_PATH) as Script
	_far_scenery_ring = Node3D.new()
	_far_scenery_ring.name = "FarSceneryRing"
	if far_script != null:
		_far_scenery_ring.set_script(far_script)
	# FarSceneryRing3D builds immediately in _ready(), so configure all size-
	# dependent properties before adding it to the active SceneTree.
	var far_extent = maxf(_map_size.x, _map_size.y) * 0.5
	_set_property_if_present(_far_scenery_ring, "core_map_size", _map_size)
	_set_property_if_present(_far_scenery_ring, "far_ground_size", _far_ground_size_for_map())
	_set_property_if_present(_far_scenery_ring, "inner_tree_half_extent", far_extent + 72.0)
	_set_property_if_present(_far_scenery_ring, "outer_tree_half_extent", far_extent + 168.0)
	_set_property_if_present(_far_scenery_ring, "fourth_rock_half_extent", far_extent + 388.0)
	_set_property_if_present(_far_scenery_ring, "fifth_rock_half_extent", far_extent + 608.0)
	_set_property_if_present(_far_scenery_ring, "visibility_distance", maxf(800.0, far_extent * 3.2))
	_set_property_if_present(_far_scenery_ring, "surface_palette_lookup", _surface_palette_lookup)
	_set_property_if_present(_far_scenery_ring, "far_farm_inner_margin", 260.0)
	_set_property_if_present(_far_scenery_ring, "far_grass_inner_half_extent", far_extent + 8.0)
	_set_property_if_present(_far_scenery_ring, "far_grass_outer_half_extent", far_extent + 208.0)
	_map_root.add_child(_far_scenery_ring)
	call_deferred("_ensure_far_scenery_visible")

	var baker_script = _load_resource_or_null(TERRAIN_BAKER_PATH) as Script
	_terrain_baker = Node3D.new()
	_terrain_baker.name = "TerrainSurfaceBaker"
	if baker_script != null:
		_terrain_baker.set_script(baker_script)
	_map_root.add_child(_terrain_baker)


func _configure_integrated_systems() -> void:
	if _far_scenery_ring != null:
		var max_extent = maxf(_map_size.x, _map_size.y) * 0.5
		_set_property_if_present(_far_scenery_ring, "core_map_size", _map_size)
		_set_property_if_present(_far_scenery_ring, "far_ground_size", _far_ground_size_for_map())
		_set_property_if_present(_far_scenery_ring, "inner_tree_half_extent", max_extent + 72.0)
		_set_property_if_present(_far_scenery_ring, "outer_tree_half_extent", max_extent + 168.0)
		_set_property_if_present(_far_scenery_ring, "fourth_rock_half_extent", max_extent + 388.0)
		_set_property_if_present(_far_scenery_ring, "fifth_rock_half_extent", max_extent + 608.0)
		_set_property_if_present(_far_scenery_ring, "visibility_distance", maxf(800.0, max_extent * 3.2))
		_set_property_if_present(_far_scenery_ring, "surface_palette_lookup", _surface_palette_lookup)
		_set_property_if_present(_far_scenery_ring, "far_farm_inner_margin", 260.0)
		_set_property_if_present(_far_scenery_ring, "far_grass_inner_half_extent", max_extent + 8.0)
		_set_property_if_present(_far_scenery_ring, "far_grass_outer_half_extent", max_extent + 208.0)

	if _terrain_baker != null:
		_set_property_if_present(_terrain_baker, "palette", _surface_palette_resource)
		_set_property_if_present(_terrain_baker, "area_root", NodePath("../SurfaceAreas"))
		_set_property_if_present(_terrain_baker, "terrain_size", _map_size)
		_set_property_if_present(_terrain_baker, "mask_resolution", surface_mask_resolution)
		_set_property_if_present(_terrain_baker, "mask_output_path", "user://maps/%s/%s_surface_mask.res" % [_map_name, _map_name])
		_set_property_if_present(_terrain_baker, "palette_output_path", "user://maps/%s/%s_surface_palette_lookup.res" % [_map_name, _map_name])


func _create_boundary_walls() -> void:
	var wall_height = 50.0
	var thickness = 2.0
	_create_boundary_wall(
		"NorthWall",
		Vector3(0.0, wall_height * 0.5, _terrain_origin.y - thickness * 0.5),
		Vector3(_map_size.x + 4.0, wall_height, thickness)
	)
	_create_boundary_wall(
		"SouthWall",
		Vector3(0.0, wall_height * 0.5, _terrain_origin.y + _map_size.y + thickness * 0.5),
		Vector3(_map_size.x + 4.0, wall_height, thickness)
	)
	_create_boundary_wall(
		"WestWall",
		Vector3(_terrain_origin.x - thickness * 0.5, wall_height * 0.5, 0.0),
		Vector3(thickness, wall_height, _map_size.y)
	)
	_create_boundary_wall(
		"EastWall",
		Vector3(_terrain_origin.x + _map_size.x + thickness * 0.5, wall_height * 0.5, 0.0),
		Vector3(thickness, wall_height, _map_size.y)
	)


func _create_boundary_wall(name_value: String, world_position: Vector3, size_value: Vector3) -> void:
	var body = StaticBody3D.new()
	body.name = name_value
	body.collision_layer = BOUNDARY_COLLISION_LAYER
	body.collision_mask = 0
	body.position = world_position
	_boundary_root.add_child(body)

	var shape_node = CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var box = BoxShape3D.new()
	box.size = size_value
	shape_node.shape = box
	body.add_child(shape_node)

	# Editor-only red warning wall. The collision remains in the saved map, but
	# this translucent visualization is not packed.
	var warning = MeshInstance3D.new()
	warning.name = "_BoundaryWarning"
	warning.set_meta(EDITOR_MARKER_META, true)
	var warning_mesh = BoxMesh.new()
	warning_mesh.size = size_value
	var warning_material = StandardMaterial3D.new()
	warning_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	warning_material.albedo_color = Color(1.0, 0.06, 0.03, 0.16)
	warning_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	warning_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	warning_mesh.material = warning_material
	warning.mesh = warning_mesh
	warning.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(warning)

	# Strong red strip at ground level makes the playable border easy to read
	# even when the tall transparent wall is viewed at a shallow angle.
	var strip = MeshInstance3D.new()
	strip.name = "_BoundaryStrip"
	strip.set_meta(EDITOR_MARKER_META, true)
	var strip_mesh = BoxMesh.new()
	var strip_size = size_value
	strip_size.y = boundary_warning_strip_height
	strip_mesh.size = strip_size
	var strip_material = StandardMaterial3D.new()
	strip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_material.albedo_color = Color(1.0, 0.02, 0.01, 0.92)
	strip_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	strip_mesh.material = strip_material
	strip.mesh = strip_mesh
	strip.position.y = -world_position.y + initial_ground_height + boundary_warning_strip_height * 0.5
	strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(strip)


func _focus_camera_on_map() -> void:
	var extent = maxf(_map_size.x, _map_size.y)
	if _camera_rig != null:
		_camera_rig.position = Vector3(
			0.0,
			maxf(45.0, extent * 0.35),
			maxf(55.0, extent * 0.42)
		)
		_camera_rig.position = _clamp_editor_camera_above_ground(
			_camera_rig.position
		)
	_camera_yaw = 0.0
	_camera_pitch = deg_to_rad(-38.0)
	_camera_speed = clampf(extent * 0.11, 18.0, 130.0)
	_apply_camera_rotation()


func _new_child_node3d(parent: Node, name_value: String) -> Node3D:
	var node = Node3D.new()
	node.name = name_value
	parent.add_child(node)
	return node


# -----------------------------------------------------------------------------
# Dynamic chunked terrain
# -----------------------------------------------------------------------------

func _create_terrain_chunks() -> void:
	if _ground_body == null or _terrain_root == null:
		push_error("FarmWar map editor: Ground StaticBody3D was not created.")
		return

	var cell_count_x = _sample_width - 1
	var cell_count_z = _sample_depth - 1
	var chunk_count_x = int(ceil(float(cell_count_x) / float(terrain_chunk_cells)))
	var chunk_count_z = int(ceil(float(cell_count_z) / float(terrain_chunk_cells)))

	for chunk_z in range(chunk_count_z):
		for chunk_x in range(chunk_count_x):
			var coordinate = Vector2i(chunk_x, chunk_z)
			var start_x = chunk_x * terrain_chunk_cells
			var start_z = chunk_z * terrain_chunk_cells
			var cells_x = mini(terrain_chunk_cells, cell_count_x - start_x)
			var cells_z = mini(terrain_chunk_cells, cell_count_z - start_z)

			var center_sample = Vector2(
				float(start_x) + float(cells_x) * 0.5,
				float(start_z) + float(cells_z) * 0.5
			)
			var chunk_position = Vector3(
				_terrain_origin.x + center_sample.x * vertex_spacing,
				0.0,
				_terrain_origin.y + center_sample.y * vertex_spacing
			)

			var chunk_root = Node3D.new()
			chunk_root.name = "TerrainChunk_%d_%d" % [chunk_x, chunk_z]
			chunk_root.position = chunk_position
			chunk_root.set_meta("chunk_coordinate", coordinate)
			chunk_root.set_meta("start_sample", Vector2i(start_x, start_z))
			chunk_root.set_meta("cell_size", Vector2i(cells_x, cells_z))
			_terrain_root.add_child(chunk_root)

			var mesh_instance = MeshInstance3D.new()
			mesh_instance.name = "Mesh"
			mesh_instance.material_override = _terrain_material
			# Terrain is a receiver, not a caster. A full-map terrain mesh in the
			# directional shadow pass creates a camera-following square/self-shadow.
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk_root.add_child(mesh_instance)

			# CollisionShape3D is a direct child of the one explicit Ground
			# StaticBody3D, matching the existing FarmWar map structure.
			var collision = CollisionShape3D.new()
			collision.name = "TerrainCollision_%d_%d" % [chunk_x, chunk_z]
			collision.position = chunk_position
			collision.debug_color = Color(0.91, 0.19, 0.58, 0.35)
			_ground_body.add_child(collision)

			_terrain_chunks[coordinate] = chunk_root
			_terrain_collision_shapes[coordinate] = collision
			_rebuild_terrain_chunk(coordinate, true)

	_verify_terrain_mesh_visibility()

	# Let the existing baker know which mesh carries the shared material.
	if _terrain_baker != null and not _terrain_chunks.is_empty():
		var first_chunk = _terrain_chunks.values()[0] as Node3D
		var first_mesh = first_chunk.get_node_or_null("Mesh") as MeshInstance3D
		if first_mesh != null:
			_set_property_if_present(
				_terrain_baker,
				"target_mesh",
				_terrain_baker.get_path_to(first_mesh)
			)


func _verify_terrain_mesh_visibility() -> void:
	if _ground_body == null:
		push_error("FarmWar map editor: Ground StaticBody3D is missing.")
		return
	if _terrain_chunks.is_empty():
		push_error("FarmWar map editor: no terrain chunks were generated.")
		return
	if _terrain_material == null or _terrain_material.shader == null:
		push_error("FarmWar map editor: terrain material/shader is unavailable.")
		return
	var first_coordinate = _terrain_chunks.keys()[0] as Vector2i
	var first_chunk = _terrain_chunks[first_coordinate] as Node3D
	var first_mesh_instance = first_chunk.get_node_or_null("Mesh") as MeshInstance3D
	var first_collision = _terrain_collision_shapes.get(
		first_coordinate,
		null
	) as CollisionShape3D
	if first_mesh_instance == null or first_mesh_instance.mesh == null:
		push_error("FarmWar map editor: first terrain chunk has no visible mesh.")
	elif first_mesh_instance.mesh.get_surface_count() > 0:
		var arrays = first_mesh_instance.mesh.surface_get_arrays(0)
		var vertices = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var indices = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		var normals = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array
		if indices.size() >= 3:
			var normal_index: int = indices[0]
			if normals.size() <= normal_index or normals[normal_index].dot(Vector3.UP) <= 0.0:
				push_error(
					"FarmWar map editor: terrain vertex normal faces downward."
				)
	if first_collision == null or first_collision.shape == null:
		push_error("FarmWar map editor: first terrain chunk has no collision shape.")


func _rebuild_terrain_chunk(coordinate: Vector2i, update_collision: bool) -> void:
	var chunk_root = _terrain_chunks.get(coordinate, null) as Node3D
	if chunk_root == null:
		return

	var start_sample = chunk_root.get_meta("start_sample", Vector2i.ZERO) as Vector2i
	var cell_size = chunk_root.get_meta("cell_size", Vector2i.ZERO) as Vector2i
	var cells_x = cell_size.x
	var cells_z = cell_size.y
	var row_width = cells_x + 1

	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()
	vertices.resize((cells_x + 1) * (cells_z + 1))
	normals.resize(vertices.size())
	uvs.resize(vertices.size())

	var center_local_x = float(cells_x) * vertex_spacing * 0.5
	var center_local_z = float(cells_z) * vertex_spacing * 0.5

	for local_z in range(cells_z + 1):
		for local_x in range(cells_x + 1):
			var global_x = start_sample.x + local_x
			var global_z = start_sample.y + local_z
			var array_index = local_z * row_width + local_x
			vertices[array_index] = Vector3(
				float(local_x) * vertex_spacing - center_local_x,
				_get_height_sample(global_x, global_z),
				float(local_z) * vertex_spacing - center_local_z
			)
			normals[array_index] = _calculate_height_normal(global_x, global_z)
			uvs[array_index] = Vector2(
				float(global_x) / float(maxi(1, _sample_width - 1)),
				float(global_z) / float(maxi(1, _sample_depth - 1))
			)

	indices.resize(cells_x * cells_z * 6)
	var write_index = 0
	for local_z in range(cells_z):
		for local_x in range(cells_x):
			var i0 = local_z * row_width + local_x
			var i1 = i0 + 1
			var i2 = i0 + row_width
			var i3 = i2 + 1

			# Godot's front-face order is intentionally paired with +Y vertex
			# normals. Do not swap these indices without changing the material cull
			# mode as well.
			indices[write_index] = i0
			indices[write_index + 1] = i1
			indices[write_index + 2] = i2
			indices[write_index + 3] = i1
			indices[write_index + 4] = i3
			indices[write_index + 5] = i2
			write_index += 6

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if mesh.get_surface_count() > 0 and _terrain_material != null:
		mesh.surface_set_material(0, _terrain_material)

	var mesh_instance = chunk_root.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance != null:
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _terrain_material
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if update_collision:
		_rebuild_terrain_chunk_collision(chunk_root, start_sample, cell_size)


func _rebuild_terrain_chunk_collision(
	chunk_root: Node3D,
	start_sample: Vector2i,
	cell_size: Vector2i
) -> void:
	var width = cell_size.x + 1
	var depth = cell_size.y + 1
	var data = PackedFloat32Array()
	data.resize(width * depth)

	for local_z in range(depth):
		for local_x in range(width):
			data[local_z * width + local_x] = _get_height_sample(
				start_sample.x + local_x,
				start_sample.y + local_z
			)

	var shape = HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = data

	var coordinate = chunk_root.get_meta("chunk_coordinate", Vector2i.ZERO) as Vector2i
	var collision = _terrain_collision_shapes.get(coordinate, null) as CollisionShape3D
	if collision != null:
		collision.scale = Vector3(vertex_spacing, 1.0, vertex_spacing)
		collision.shape = shape


func _apply_height_brush(center: Vector3, delta: float) -> void:
	var bounds = _sample_bounds_for_brush(center, _brush_radius, 1)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return

	var direction = -1.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	var source_values: Dictionary = {}
	if _height_mode == HeightMode.SMOOTH:
		for z in range(bounds.position.y - 1, bounds.end.y + 1):
			for x in range(bounds.position.x - 1, bounds.end.x + 1):
				var clamped_x = clampi(x, 0, _sample_width - 1)
				var clamped_z = clampi(z, 0, _sample_depth - 1)
				source_values[_sample_index(clamped_x, clamped_z)] = _get_height_sample(clamped_x, clamped_z)

	var changed = false
	for z in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var sample_world = Vector2(
				_terrain_origin.x + float(x) * vertex_spacing,
				_terrain_origin.y + float(z) * vertex_spacing
			)
			var distance = sample_world.distance_to(Vector2(center.x, center.z))
			if distance > _brush_radius:
				continue

			var falloff = _smooth_falloff(distance, _brush_radius)
			var current = _get_height_sample(x, z)
			var next_value = current

			match _height_mode:
				HeightMode.RAISE_LOWER:
					next_value = current + direction * _brush_strength * delta * falloff
				HeightMode.FLATTEN:
					var blend = clampf(_brush_strength * 0.35 * delta * falloff, 0.0, 1.0)
					next_value = lerpf(current, _flatten_target_height, blend)
				HeightMode.SMOOTH:
					var average = 0.0
					var count = 0
					for neighbor_z in range(z - 1, z + 2):
						for neighbor_x in range(x - 1, x + 2):
							var nx = clampi(neighbor_x, 0, _sample_width - 1)
							var nz = clampi(neighbor_z, 0, _sample_depth - 1)
							average += float(source_values.get(_sample_index(nx, nz), current))
							count += 1
					average /= float(maxi(1, count))
					var smooth_blend = clampf(_brush_strength * 0.25 * delta * falloff, 0.0, 1.0)
					next_value = lerpf(current, average, smooth_blend)

			next_value = clampf(next_value, minimum_terrain_height, maximum_terrain_height)
			if not is_equal_approx(next_value, current):
				var sample_id = _sample_index(x, z)
				if not _stroke_height_before.has(sample_id):
					_stroke_height_before[sample_id] = current
				_set_height_sample(x, z, next_value)
				changed = true

	if changed:
		_refresh_height_change_contour()
		_rebuild_chunks_for_sample_rect(bounds)
		if _rect_touches_terrain_edge(bounds):
			_rebuild_terrain_skirt()


func _refresh_height_change_contour() -> void:
	var changed_points := PackedVector2Array()
	var total_delta := 0.0
	var changed_count := 0
	for index_value in _stroke_height_before.keys():
		var index := int(index_value)
		if index < 0 or index >= _height_samples.size():
			continue
		var old_height := float(_stroke_height_before[index])
		var new_height := float(_height_samples[index])
		var difference := new_height - old_height
		if is_zero_approx(difference):
			continue
		var sample_x: int = index % _sample_width
		var sample_z: int = index / _sample_width
		changed_points.append(Vector2(
			_terrain_origin.x + float(sample_x) * vertex_spacing,
			_terrain_origin.y + float(sample_z) * vertex_spacing
		))
		total_delta += difference
		changed_count += 1
	if changed_points.size() < 2:
		_height_contour_points.clear()
		_height_contour_delta = 0.0
		return
	var hull := Geometry2D.convex_hull(changed_points)
	if hull.size() < 2:
		_height_contour_points.clear()
		_height_contour_delta = 0.0
		return
	_height_contour_points = hull
	_height_contour_delta = total_delta / float(maxi(1, changed_count))


func _commit_height_stroke() -> void:
	if _stroke_height_before.is_empty():
		return

	var before_patch: Dictionary = {}
	var after_patch: Dictionary = {}
	for index_value in _stroke_height_before.keys():
		var index = int(index_value)
		var old_height = float(_stroke_height_before[index])
		var new_height = float(_height_samples[index])
		if is_equal_approx(old_height, new_height):
			continue
		before_patch[index] = old_height
		after_patch[index] = new_height

	if before_patch.is_empty():
		return

	_undo_redo.create_action("Edit Terrain Height")
	_undo_redo.add_do_method(
		_apply_height_patch.bind(after_patch.duplicate(true))
	)
	_undo_redo.add_undo_method(
		_apply_height_patch.bind(before_patch.duplicate(true))
	)
	_undo_redo.commit_action(false)


func _apply_height_patch(patch: Dictionary) -> void:
	if patch.is_empty() or _height_samples.is_empty():
		return
	_height_contour_points.clear()
	_height_contour_delta = 0.0
	_set_height_boundary_visible(false)

	var min_x = _sample_width - 1
	var min_z = _sample_depth - 1
	var max_x = 0
	var max_z = 0

	for index_value in patch.keys():
		var index = int(index_value)
		if index < 0 or index >= _height_samples.size():
			continue
		var x = index % _sample_width
		var z = int(index / _sample_width)
		_height_samples[index] = float(patch[index])
		min_x = mini(min_x, x)
		min_z = mini(min_z, z)
		max_x = maxi(max_x, x)
		max_z = maxi(max_z, z)

	if max_x < min_x or max_z < min_z:
		return

	var dirty_rect = Rect2i(
		min_x,
		min_z,
		max_x - min_x + 1,
		max_z - min_z + 1
	)
	_rebuild_chunks_for_sample_rect(dirty_rect)
	_flush_terrain_collision_updates()
	if _rect_touches_terrain_edge(dirty_rect):
		_rebuild_terrain_skirt()
	if _camera_rig != null:
		_camera_rig.global_position = _clamp_editor_camera_above_ground(
			_camera_rig.global_position
		)
	_rebuild_persistent_height_contours()
	call_deferred("_rebuild_all_roads_to_terrain")


func _rebuild_chunks_for_sample_rect(rect: Rect2i) -> void:
	var expanded = rect.grow(1)
	var min_cell_x = clampi(expanded.position.x, 0, _sample_width - 1)
	var min_cell_z = clampi(expanded.position.y, 0, _sample_depth - 1)
	var max_cell_x = clampi(expanded.end.x, 0, _sample_width - 1)
	var max_cell_z = clampi(expanded.end.y, 0, _sample_depth - 1)

	var min_chunk = Vector2i(
		floori(float(min_cell_x) / float(terrain_chunk_cells)),
		floori(float(min_cell_z) / float(terrain_chunk_cells))
	)
	var max_chunk = Vector2i(
		floori(float(max_cell_x) / float(terrain_chunk_cells)),
		floori(float(max_cell_z) / float(terrain_chunk_cells))
	)

	for chunk_z in range(min_chunk.y, max_chunk.y + 1):
		for chunk_x in range(min_chunk.x, max_chunk.x + 1):
			var coordinate = Vector2i(chunk_x, chunk_z)
			if not _terrain_chunks.has(coordinate):
				continue
			_rebuild_terrain_chunk(coordinate, false)
			_collision_dirty_chunks[coordinate] = true


func _flush_terrain_collision_updates() -> void:
	for coordinate_value in _collision_dirty_chunks.keys():
		var coordinate = coordinate_value as Vector2i
		_rebuild_terrain_chunk(coordinate, true)
	_collision_dirty_chunks.clear()


func _sample_bounds_for_brush(center: Vector3, radius: float, padding: int = 0) -> Rect2i:
	var minimum = _world_to_sample_float(Vector2(center.x - radius, center.z - radius))
	var maximum = _world_to_sample_float(Vector2(center.x + radius, center.z + radius))
	var min_x = clampi(floori(minimum.x) - padding, 0, _sample_width - 1)
	var min_z = clampi(floori(minimum.y) - padding, 0, _sample_depth - 1)
	var max_x = clampi(ceili(maximum.x) + padding, 0, _sample_width - 1)
	var max_z = clampi(ceili(maximum.y) + padding, 0, _sample_depth - 1)
	return Rect2i(min_x, min_z, max_x - min_x + 1, max_z - min_z + 1)


func _calculate_height_normal(x: int, z: int) -> Vector3:
	var left = _get_height_sample(x - 1, z)
	var right = _get_height_sample(x + 1, z)
	var back = _get_height_sample(x, z - 1)
	var front = _get_height_sample(x, z + 1)
	return Vector3(
		left - right,
		2.0 * vertex_spacing,
		back - front
	).normalized()


func _sample_index(x: int, z: int) -> int:
	return z * _sample_width + x


func _get_height_sample(x: int, z: int) -> float:
	if _height_samples.is_empty():
		return initial_ground_height
	x = clampi(x, 0, _sample_width - 1)
	z = clampi(z, 0, _sample_depth - 1)
	return _height_samples[_sample_index(x, z)]


func _set_height_sample(x: int, z: int, value: float) -> void:
	if x < 0 or x >= _sample_width or z < 0 or z >= _sample_depth:
		return
	_height_samples[_sample_index(x, z)] = value


func _world_to_sample_float(world_xz: Vector2) -> Vector2:
	return (world_xz - _terrain_origin) / vertex_spacing


func get_terrain_height_world(world_xz: Vector2) -> float:
	if _height_samples.is_empty():
		return initial_ground_height
	var sample = _world_to_sample_float(world_xz)
	var x0 = clampi(floori(sample.x), 0, _sample_width - 1)
	var z0 = clampi(floori(sample.y), 0, _sample_depth - 1)
	var x1 = mini(x0 + 1, _sample_width - 1)
	var z1 = mini(z0 + 1, _sample_depth - 1)
	var tx = clampf(sample.x - float(x0), 0.0, 1.0)
	var tz = clampf(sample.y - float(z0), 0.0, 1.0)
	var top = lerpf(_get_height_sample(x0, z0), _get_height_sample(x1, z0), tx)
	var bottom = lerpf(_get_height_sample(x0, z1), _get_height_sample(x1, z1), tx)
	return lerpf(top, bottom, tz)


func get_terrain_normal_world(world_xz: Vector2) -> Vector3:
	# Central differences provide a smooth normal at arbitrary world positions,
	# including random points selected inside a placement brush.
	var step = maxf(vertex_spacing, 0.25)
	var left = get_terrain_height_world(world_xz + Vector2(-step, 0.0))
	var right = get_terrain_height_world(world_xz + Vector2(step, 0.0))
	var back = get_terrain_height_world(world_xz + Vector2(0.0, -step))
	var front = get_terrain_height_world(world_xz + Vector2(0.0, step))
	var normal = Vector3(
		left - right,
		2.0 * step,
		back - front
	)
	if normal.length_squared() <= 0.000001:
		return Vector3.UP
	return normal.normalized()


func _basis_from_surface_normal(
	surface_normal: Vector3,
	yaw_radians: float,
	uniform_scale: float
) -> Basis:
	var up_axis = surface_normal.normalized()
	if up_axis.length_squared() <= 0.000001:
		up_axis = Vector3.UP

	if not align_placed_objects_to_surface_normal:
		return Basis(Vector3.UP, yaw_radians).scaled(
			Vector3.ONE * uniform_scale
		)

	# Start from the requested world-space yaw direction, project it onto the
	# tangent plane, and build an orthonormal basis whose Y column is exactly
	# the terrain normal.
	var yaw_basis = Basis(Vector3.UP, yaw_radians)
	var z_axis = yaw_basis.z - up_axis * yaw_basis.z.dot(up_axis)
	if z_axis.length_squared() <= 0.000001:
		z_axis = Vector3.FORWARD - up_axis * Vector3.FORWARD.dot(up_axis)
	if z_axis.length_squared() <= 0.000001:
		z_axis = Vector3.RIGHT - up_axis * Vector3.RIGHT.dot(up_axis)
	z_axis = z_axis.normalized()
	var x_axis = up_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(up_axis).normalized()

	return Basis(x_axis, up_axis, z_axis).orthonormalized().scaled(
		Vector3.ONE * uniform_scale
	)


func _place_node_on_terrain(
	node: Node3D,
	world_xz: Vector2,
	yaw_radians: float,
	uniform_scale: float,
	ground_offset: float
) -> void:
	if node == null:
		return
	var surface_normal = get_terrain_normal_world(world_xz)
	var basis = _basis_from_surface_normal(
		surface_normal,
		yaw_radians,
		uniform_scale
	)
	var position_value = Vector3(
		world_xz.x,
		get_terrain_height_world(world_xz) + ground_offset,
		world_xz.y
	)
	node.global_transform = Transform3D(basis, position_value)


func _point_inside_map(world_xz: Vector2, margin: float = 0.0) -> bool:
	return (
		world_xz.x >= _terrain_origin.x + margin
		and world_xz.y >= _terrain_origin.y + margin
		and world_xz.x <= _terrain_origin.x + _map_size.x - margin
		and world_xz.y <= _terrain_origin.y + _map_size.y - margin
	)


func _smooth_falloff(distance: float, radius: float) -> float:
	if radius <= 0.0001:
		return 1.0
	var t = clampf(1.0 - distance / radius, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


# -----------------------------------------------------------------------------
# FarmWar surface-mask paint
# -----------------------------------------------------------------------------

func _apply_surface_brush(center: Vector3, delta: float) -> void:
	if _surface_mask_image == null or _surface_mask_texture == null:
		return

	var target_id = _get_default_surface_id() if Input.is_key_pressed(KEY_SHIFT) else _selected_surface_id
	var image_width = _surface_mask_image.get_width()
	var image_height = _surface_mask_image.get_height()
	var center_uv = (Vector2(center.x, center.z) - _terrain_origin) / _map_size
	var center_pixel = Vector2(center_uv.x * float(image_width - 1), center_uv.y * float(image_height - 1))
	var radius_px_x = _brush_radius / _map_size.x * float(image_width)
	var radius_px_y = _brush_radius / _map_size.y * float(image_height)
	var min_x = clampi(floori(center_pixel.x - radius_px_x), 0, image_width - 1)
	var max_x = clampi(ceili(center_pixel.x + radius_px_x), 0, image_width - 1)
	var min_y = clampi(floori(center_pixel.y - radius_px_y), 0, image_height - 1)
	var max_y = clampi(ceili(center_pixel.y + radius_px_y), 0, image_height - 1)
	var changed = false

	for pixel_y in range(min_y, max_y + 1):
		for pixel_x in range(min_x, max_x + 1):
			var uv = Vector2(
				float(pixel_x) / float(maxi(1, image_width - 1)),
				float(pixel_y) / float(maxi(1, image_height - 1))
			)
			var world_xz = _terrain_origin + uv * _map_size
			var distance = world_xz.distance_to(Vector2(center.x, center.z))
			if distance > _brush_radius:
				continue
			var falloff = _smooth_falloff(distance, _brush_radius)
			var amount = clampf(_brush_strength * 0.45 * delta * falloff, 0.0, 1.0)
			var pixel = Vector2i(pixel_x, pixel_y)
			var pixel_index = pixel_y * image_width + pixel_x
			if not _stroke_surface_before.has(pixel_index):
				_stroke_surface_before[pixel_index] = _surface_mask_image.get_pixelv(pixel)
			_paint_surface_pixel(pixel, target_id, amount)
			changed = true

	if changed:
		_surface_mask_texture.update(_surface_mask_image)


func _commit_surface_stroke() -> void:
	if _stroke_surface_before.is_empty() or _surface_mask_image == null:
		return

	var before_patch: Dictionary = {}
	var after_patch: Dictionary = {}
	var image_width = _surface_mask_image.get_width()

	for index_value in _stroke_surface_before.keys():
		var index = int(index_value)
		var pixel = Vector2i(index % image_width, int(index / image_width))
		var old_color = _stroke_surface_before[index] as Color
		var new_color = _surface_mask_image.get_pixelv(pixel)
		if old_color.is_equal_approx(new_color):
			continue
		before_patch[index] = old_color
		after_patch[index] = new_color

	if before_patch.is_empty():
		return

	_undo_redo.create_action("Paint Terrain Surface")
	_undo_redo.add_do_method(
		_apply_surface_patch.bind(after_patch.duplicate(true))
	)
	_undo_redo.add_undo_method(
		_apply_surface_patch.bind(before_patch.duplicate(true))
	)
	_undo_redo.commit_action(false)


func _apply_surface_patch(patch: Dictionary) -> void:
	if patch.is_empty() or _surface_mask_image == null:
		return
	var image_width = _surface_mask_image.get_width()
	for index_value in patch.keys():
		var index = int(index_value)
		var pixel = Vector2i(index % image_width, int(index / image_width))
		_surface_mask_image.set_pixelv(pixel, patch[index] as Color)
	if _surface_mask_texture != null:
		_surface_mask_texture.update(_surface_mask_image)


func _paint_surface_pixel(pixel: Vector2i, target_id: int, amount: float) -> void:
	var mask = _surface_mask_image.get_pixelv(pixel)
	var base_id = clampi(roundi(mask.r * 255.0), 0, 255)
	var overlay_id = clampi(roundi(mask.g * 255.0), 0, 255)
	var blend = clampf(mask.b, 0.0, 1.0)

	if target_id == base_id:
		blend = lerpf(blend, 0.0, amount)
	elif target_id == overlay_id:
		blend = lerpf(blend, 1.0, amount)
	else:
		# Preserve whichever surface is currently dominant, then blend toward
		# the newly selected overlay. This matches the existing shader's
		# base/overlay/blend model instead of treating the mask as RGBA weights.
		if blend >= 0.5:
			base_id = overlay_id
		overlay_id = target_id
		blend = lerpf(0.0, 1.0, amount)

	if blend >= 0.995:
		base_id = overlay_id
		blend = 0.0

	_surface_mask_image.set_pixelv(pixel, Color(
		float(base_id) / 255.0,
		float(overlay_id) / 255.0,
		blend,
		1.0
	))


func _read_surface_entries() -> Array:
	if _surface_entries.is_empty():
		_surface_entries = FALLBACK_SURFACES.duplicate(true)
	return _surface_entries.duplicate(true)


func _build_surface_palette_image() -> Image:
	var image = Image.create(256, 1, false, Image.FORMAT_RGBA8)
	var fallback_color = Color(0.2, 0.6, 0.2, 0.9)
	if not _surface_entries.is_empty():
		var default_entry = _surface_entries[0] as Dictionary
		var default_color = default_entry.get("color", Color("75a94b")) as Color
		var default_roughness = clampf(
			float(default_entry.get("roughness", 0.9)),
			0.0,
			1.0
		)
		fallback_color = Color(
			default_color.r,
			default_color.g,
			default_color.b,
			default_roughness
		)
	image.fill(fallback_color)

	for entry_value in _surface_entries:
		var entry = entry_value as Dictionary
		var surface_id = clampi(int(entry.get("id", 0)), 0, 255)
		var color = entry.get("color", Color.WHITE) as Color
		var roughness = clampf(float(entry.get("roughness", 0.9)), 0.0, 1.0)
		image.set_pixel(
			surface_id,
			0,
			Color(color.r, color.g, color.b, roughness)
		)
	return image


func _rebuild_surface_palette_lookup() -> void:
	_sync_surface_palette_resource_from_entries()
	var palette_image = _build_surface_palette_image()
	if _surface_palette_lookup is ImageTexture:
		(_surface_palette_lookup as ImageTexture).update(palette_image)
	else:
		_surface_palette_lookup = ImageTexture.create_from_image(palette_image)

	if _terrain_material != null:
		_terrain_material.set_shader_parameter(
			"surface_palette",
			_surface_palette_lookup
		)
	if _far_scenery_ring != null:
		_set_property_if_present(
			_far_scenery_ring,
			"surface_palette_lookup",
			_surface_palette_lookup
		)
	_update_ground_safety_color()


func _make_fallback_palette_lookup() -> ImageTexture:
	if _surface_entries.is_empty():
		_surface_entries = FALLBACK_SURFACES.duplicate(true)
	return ImageTexture.create_from_image(_build_surface_palette_image())


# -----------------------------------------------------------------------------
# Manual grass brush and chunked MultiMesh rendering
# -----------------------------------------------------------------------------

func _new_manual_grass_data() -> Dictionary:
	var result: Dictionary = {}
	for species_value in MANUAL_GRASS_SPECIES.keys():
		result[str(species_value)] = {}
	return result


func _ensure_manual_grass_species() -> void:
	for species_value in MANUAL_GRASS_SPECIES.keys():
		var species := str(species_value)
		if not _manual_grass.has(species) or not _manual_grass[species] is Dictionary:
			_manual_grass[species] = {}


func _apply_grass_brush(center: Vector3, delta: float) -> void:
	_ensure_manual_grass_species()
	if Input.is_key_pressed(KEY_SHIFT):
		_erase_grass(center, _brush_radius)
		return

	var expected_count = PI * _brush_radius * _brush_radius * _grass_density * delta
	var count = int(floor(expected_count))
	if _rng.randf() < expected_count - float(count):
		count += 1
	count = mini(count, 80)
	if count <= 0:
		return

	var dirty_chunks: Dictionary = {}
	for _index in range(count):
		var random_point = _random_point_in_disc(Vector2(center.x, center.z), _brush_radius)
		if not _point_inside_map(random_point, 0.2):
			continue
		var coordinate = _grass_chunk_coordinate(random_point)
		var key = _chunk_key(coordinate)
		_capture_grass_chunk_before(_selected_grass_species, key)
		var species_chunks = _manual_grass[_selected_grass_species] as Dictionary
		if not species_chunks.has(key):
			species_chunks[key] = []
		var transforms = species_chunks[key] as Array
		var species_definition := MANUAL_GRASS_SPECIES.get(_selected_grass_species, MANUAL_GRASS_SPECIES["small"]) as Dictionary
		var scale_range := species_definition.get("scale", Vector2(0.85, 1.15)) as Vector2
		var scale_value = _rng.randf_range(scale_range.x, scale_range.y)
		var transform = Transform3D(
			Basis(Vector3.UP, _rng.randf_range(-PI, PI)).scaled(Vector3.ONE * scale_value),
			Vector3(random_point.x, get_terrain_height_world(random_point) + 0.015, random_point.y)
		)
		transforms.append(transform)
		dirty_chunks[key] = true

	for key_value in dirty_chunks.keys():
		_rebuild_manual_grass_chunk(_selected_grass_species, str(key_value))


func _erase_grass(center: Vector3, radius: float) -> void:
	var center_xz = Vector2(center.x, center.z)
	var species_chunks = _manual_grass[_selected_grass_species] as Dictionary
	var dirty_chunks: Array[String] = []

	for key_value in species_chunks.keys():
		var key = str(key_value)
		var transforms = species_chunks[key] as Array
		var kept: Array = []
		for transform_value in transforms:
			var transform = transform_value as Transform3D
			var position_xz = Vector2(transform.origin.x, transform.origin.z)
			if position_xz.distance_to(center_xz) > radius:
				kept.append(transform)
		if kept.size() != transforms.size():
			_capture_grass_chunk_before(_selected_grass_species, key)
			if kept.is_empty():
				species_chunks.erase(key)
			else:
				species_chunks[key] = kept
			dirty_chunks.append(key)

	for key in dirty_chunks:
		_rebuild_manual_grass_chunk(_selected_grass_species, key)


func _capture_grass_chunk_before(species: String, key: String) -> void:
	var history_key = "%s@%s" % [species, key]
	if _stroke_grass_before.has(history_key):
		return
	var species_chunks = _manual_grass.get(species, {}) as Dictionary
	if species_chunks.has(key):
		_stroke_grass_before[history_key] = (
			species_chunks[key] as Array
		).duplicate(true)
	else:
		_stroke_grass_before[history_key] = null


func _commit_grass_stroke() -> void:
	if _stroke_grass_before.is_empty():
		return

	var before_patch: Dictionary = {}
	var after_patch: Dictionary = {}
	for history_key_value in _stroke_grass_before.keys():
		var history_key = str(history_key_value)
		before_patch[history_key] = _duplicate_grass_patch_value(
			_stroke_grass_before[history_key]
		)
		var separator = history_key.find("@")
		if separator < 0:
			continue
		var species = history_key.substr(0, separator)
		var key = history_key.substr(separator + 1)
		var species_chunks = _manual_grass.get(species, {}) as Dictionary
		if species_chunks.has(key):
			after_patch[history_key] = (
				species_chunks[key] as Array
			).duplicate(true)
		else:
			after_patch[history_key] = null

	_undo_redo.create_action("Paint Manual Grass")
	_undo_redo.add_do_method(
		_apply_grass_patch.bind(after_patch.duplicate(true))
	)
	_undo_redo.add_undo_method(
		_apply_grass_patch.bind(before_patch.duplicate(true))
	)
	_undo_redo.commit_action(false)


func _duplicate_grass_patch_value(value: Variant) -> Variant:
	if value == null:
		return null
	return (value as Array).duplicate(true)


func _apply_grass_patch(patch: Dictionary) -> void:
	var dirty_keys: Array[String] = []
	for history_key_value in patch.keys():
		var history_key = str(history_key_value)
		var separator = history_key.find("@")
		if separator < 0:
			continue
		var species = history_key.substr(0, separator)
		var key = history_key.substr(separator + 1)
		if not _manual_grass.has(species):
			_manual_grass[species] = {}
		var species_chunks = _manual_grass[species] as Dictionary
		var value = patch[history_key]
		if value == null:
			species_chunks.erase(key)
		else:
			species_chunks[key] = (value as Array).duplicate(true)
		dirty_keys.append(history_key)

	for history_key in dirty_keys:
		var separator = history_key.find("@")
		var species = history_key.substr(0, separator)
		var key = history_key.substr(separator + 1)
		_rebuild_manual_grass_chunk(species, key)


func _rebuild_manual_grass_chunk(species: String, key: String) -> void:
	var generated_key = "%s@%s" % [species, key]
	var existing = _grass_generated_nodes.get(generated_key, null) as Node
	if is_instance_valid(existing):
		var existing_parent = existing.get_parent()
		if existing_parent != null:
			existing_parent.remove_child(existing)
		existing.free()
	_grass_generated_nodes.erase(generated_key)

	var species_chunks = _manual_grass[species] as Dictionary
	if not species_chunks.has(key):
		return
	var transforms = species_chunks[key] as Array
	if transforms.is_empty():
		return

	var coordinate = _parse_chunk_key(key)
	var center_xz = _grass_chunk_center(coordinate)
	var chunk_root = Node3D.new()
	chunk_root.name = "%s_%s" % [species.capitalize(), key.replace(":", "_")]
	chunk_root.position = Vector3(center_xz.x, 0.0, center_xz.y)
	_manual_grass_root.add_child(chunk_root)
	_grass_generated_nodes[generated_key] = chunk_root

	var species_definition := MANUAL_GRASS_SPECIES.get(species, MANUAL_GRASS_SPECIES["small"]) as Dictionary
	var source_path := str(species_definition.get("path", SMALL_GRASS_PATH))
	var components = _get_grass_mesh_components(source_path)
	for component_index in range(components.size()):
		var component = components[component_index] as Dictionary
		var mesh = component.get("mesh", null) as Mesh
		if mesh == null:
			continue
		var source_transform = component.get("transform", Transform3D.IDENTITY) as Transform3D
		var multi = MultiMesh.new()
		multi.transform_format = MultiMesh.TRANSFORM_3D
		multi.mesh = mesh
		multi.instance_count = transforms.size()
		for instance_index in range(transforms.size()):
			var world_transform = transforms[instance_index] as Transform3D
			var local_transform = world_transform
			local_transform.origin -= Vector3(center_xz.x, 0.0, center_xz.y)
			multi.set_instance_transform(instance_index, local_transform * source_transform)

		var instance = MultiMeshInstance3D.new()
		instance.name = "Mesh_%d" % component_index
		instance.multimesh = multi
		instance.material_override = component.get("material", null) as Material
		# Painted grass is local/chunked, so unlike far-distance grass it should
		# participate in the normal shadow pass with trees, buildings and players.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		instance.visibility_range_end = float(species_definition.get("visibility", 100.0))
		instance.extra_cull_margin = 2.0
		chunk_root.add_child(instance)


func _get_grass_mesh_components(scene_path: String) -> Array:
	if _grass_mesh_cache.has(scene_path):
		return (_grass_mesh_cache[scene_path] as Array).duplicate()
	var result: Array = []
	var packed = _load_resource_or_null(scene_path) as PackedScene
	if packed == null:
		push_warning("FarmWar map editor: grass scene not found: %s" % scene_path)
		return result
	var source_root = packed.instantiate() as Node3D
	if source_root == null:
		return result
	_collect_grass_mesh_components(source_root, source_root, result)
	source_root.free()
	_grass_mesh_cache[scene_path] = result
	return result.duplicate()


func _collect_grass_mesh_components(node: Node, root: Node3D, result: Array) -> void:
	if node is MeshInstance3D:
		var source = node as MeshInstance3D
		if source.mesh != null:
			result.append({
				"mesh": source.mesh,
				"material": source.material_override,
				"transform": _relative_transform_to_root(source, root),
			})
	for child in node.get_children():
		_collect_grass_mesh_components(child, root, result)


func _relative_transform_to_root(node: Node3D, root: Node3D) -> Transform3D:
	var result = node.transform
	var cursor = node.get_parent() as Node3D
	while cursor != null and cursor != root:
		result = cursor.transform * result
		cursor = cursor.get_parent() as Node3D
	return result


func _grass_chunk_coordinate(world_xz: Vector2) -> Vector2i:
	var relative = world_xz - _terrain_origin
	return Vector2i(
		floori(relative.x / GRASS_CHUNK_SIZE),
		floori(relative.y / GRASS_CHUNK_SIZE)
	)


func _grass_chunk_center(coordinate: Vector2i) -> Vector2:
	var minimum = _terrain_origin + Vector2(coordinate) * GRASS_CHUNK_SIZE
	var maximum = Vector2(
		minf(minimum.x + GRASS_CHUNK_SIZE, _terrain_origin.x + _map_size.x),
		minf(minimum.y + GRASS_CHUNK_SIZE, _terrain_origin.y + _map_size.y)
	)
	return (minimum + maximum) * 0.5


func _random_point_in_disc(center: Vector2, radius: float) -> Vector2:
	var angle = _rng.randf_range(0.0, TAU)
	var distance = sqrt(_rng.randf()) * radius
	return center + Vector2(cos(angle), sin(angle)) * distance


func _chunk_key(coordinate: Vector2i) -> String:
	return "%d:%d" % [coordinate.x, coordinate.y]


func _parse_chunk_key(key: String) -> Vector2i:
	var parts = key.split(":")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


# -----------------------------------------------------------------------------
# Tree, ore and spawn placement
# -----------------------------------------------------------------------------

func _apply_scene_placement_brush(
	center: Vector3,
	delta: float,
	category_root: Node3D,
	category_name: String
) -> void:
	if category_root == null:
		return
	if Input.is_key_pressed(KEY_SHIFT):
		_erase_nodes_in_radius(category_root, center, _brush_radius)
		return
	if _placement_timer > 0.0:
		return

	var point_xz = Vector2(center.x, center.z)
	if _brush_radius > 1.5:
		point_xz = _random_point_in_disc(point_xz, _brush_radius * 0.65)
	if not _point_inside_map(point_xz, 0.5):
		return
	# Only trees are excluded from water. Rocks and mushroom resources remain
	# placeable for now, as requested.
	if category_name == "tree" and _is_point_in_water(point_xz, get_terrain_height_world(point_xz)):
		_set_status("Resource placement blocked: point is inside water")
		return

	var scene_path = str(_selected_asset.get("path", ""))
	var packed = _load_resource_or_null(scene_path) as PackedScene
	if packed == null:
		_set_status("Missing asset: %s" % scene_path)
		_placement_timer = 0.5
		return

	var instance = packed.instantiate() as Node3D
	if instance == null:
		_set_status("Asset root is not Node3D: %s" % scene_path)
		_placement_timer = 0.5
		return

	instance.name = "%s_%04d" % [str(_selected_asset.get("id", category_name)).capitalize(), _next_object_id]
	instance.set_meta("map_editor_category", category_name)
	instance.set_meta("map_editor_asset_path", scene_path)
	instance.set_meta("map_editor_uuid", _new_editor_uuid(category_name))
	instance.set_meta("map_editor_align_mode", "surface_normal")
	instance.set_meta("map_editor_ground_offset", placed_object_ground_offset)
	category_root.add_child(instance)

	# Place the complete interactive scene on the authoritative terrain. Its
	# global Y axis follows the terrain normal, while random yaw is applied
	# around that normal rather than around world Y.
	var placement_yaw = _rng.randf_range(-PI, PI)
	var scale_value = _rng.randf_range(0.92, 1.08)
	_place_node_on_terrain(
		instance,
		point_xz,
		placement_yaw,
		scale_value,
		placed_object_ground_offset
	)

	var identifier = "%s_%04d" % [str(_selected_asset.get("id", category_name)), _next_object_id]
	_set_property_if_present(instance, "tree_id", identifier)
	_set_property_if_present(instance, "resource_id", identifier)
	_stroke_added_objects.append(_serialize_editor_object(instance))
	_next_object_id += 1
	_placement_timer = maxf(_placement_interval, 0.05)
	_stroke_placed_once = true
	_rebuild_resource_multimeshes_deferred()


func _erase_nodes_in_radius(category_root: Node3D, center: Vector3, radius: float, category_filter: String = "") -> void:
	var center_xz = Vector2(center.x, center.z)
	var erased = 0
	for child in category_root.get_children():
		if not child is Node3D:
			continue
		var node = child as Node3D
		if not category_filter.is_empty() and str(node.get_meta("map_editor_category", "")) != category_filter:
			continue
		var node_xz = Vector2(node.position.x, node.position.z)
		if node_xz.distance_to(center_xz) <= radius:
			_stroke_removed_objects.append(_serialize_editor_object(node))
			category_root.remove_child(node)
			node.free()
			erased += 1
	if erased > 0:
		_rebuild_resource_multimeshes_deferred()
		if category_root == _buildings_root:
			_rebuild_power_wires()
		_set_status("Removed %d resource nodes" % erased)


func _rebuild_resource_multimeshes_deferred() -> void:
	if _tree_forest_manager != null and _tree_forest_manager.has_method("_build_from_scene_trees"):
		_tree_forest_manager.call_deferred("_build_from_scene_trees")


func _apply_spawn_brush(center: Vector3) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		_erase_nodes_in_radius(_spawns_root, center, _brush_radius)
		return
	if _stroke_placed_once:
		return
	if _is_point_in_water(Vector2(center.x, center.z), center.y):
		_set_status("Spawn placement blocked: point is inside water")
		return

	if _selected_spawn_kind == "player":
		_place_team_spawn(center, _selected_team_spawn_team)
	elif _selected_spawn_kind == "wild_animal":
		_place_wild_animal_spawn(center)
	else:
		_place_giant_crop_spawn(center)
	_stroke_placed_once = true


func _place_team_spawn(center: Vector3, team: String, record_undo := true) -> void:
	var packed = _load_resource_or_null(TEAM_SPAWN_POINT_PATH) as PackedScene
	if packed == null:
		_set_status("Missing TeamSpawnPoint scene")
		return
	var spawn := packed.instantiate() as Node3D
	if spawn == null:
		return
	spawn.name = "%sTeamSpawn" % ("Red" if team == "red" else "Blue")
	spawn.set_meta("map_editor_spawn_kind", "team_%s" % team)
	spawn.set_meta("map_editor_category", "spawn")
	spawn.set_meta("map_editor_asset_path", TEAM_SPAWN_POINT_PATH)
	spawn.set_meta("map_editor_uuid", _new_editor_uuid("spawn"))
	spawn.set_meta("map_editor_align_mode", "upright")
	spawn.set_meta("map_editor_ground_offset", 0.05)
	_spawns_root.add_child(spawn)
	_place_node_on_terrain(spawn, Vector2(center.x, center.z), 0.0, 1.0, 0.05)
	_set_property_if_present(spawn, "team", team)
	_set_property_if_present(spawn, "spawn_point_id", _next_team_spawn_id(team))
	_add_spawn_editor_marker(spawn, Color(0.95, 0.2, 0.2, 1.0) if team == "red" else Color(0.2, 0.45, 1.0, 1.0))
	if record_undo:
		_stroke_added_objects.append(_serialize_editor_object(spawn))
	_next_spawn_id += 1
	_set_status("Placed %s team player spawn" % team)


func _next_team_spawn_id(team: String) -> String:
	var highest := 0
	if _spawns_root != null:
		for child in _spawns_root.get_children():
			if not child is TeamSpawnPoint:
				continue
			var point := child as TeamSpawnPoint
			if str(point.team) != team:
				continue
			var id_parts := str(point.spawn_point_id).split("_")
			var suffix := str(id_parts[id_parts.size() - 1]) if not id_parts.is_empty() else ""
			if suffix.is_valid_int():
				highest = maxi(highest, int(suffix))
	return "%s_spawn_%02d" % [team, highest + 1]


func _place_giant_crop_spawn(center: Vector3) -> void:
	var packed = _load_resource_or_null(RARE_RESOURCE_SPAWN_PATH) as PackedScene
	if packed == null:
		_set_status("Missing giant crop spawn scene")
		return
	var spawn = packed.instantiate() as Node3D
	if spawn == null:
		return
	var id_value = "giant_crop_%03d" % _next_spawn_id
	spawn.name = "GiantCropSpawn_%03d" % _next_spawn_id
	spawn.process_mode = Node.PROCESS_MODE_DISABLED
	spawn.set_meta("map_editor_spawn_kind", "giant_crop")
	spawn.set_meta("map_editor_category", "spawn")
	spawn.set_meta("map_editor_asset_path", RARE_RESOURCE_SPAWN_PATH)
	spawn.set_meta("map_editor_uuid", _new_editor_uuid("spawn"))
	spawn.set_meta("map_editor_align_mode", "upright")
	spawn.set_meta("map_editor_ground_offset", 0.05)
	_spawns_root.add_child(spawn)
	_place_node_on_terrain(
		spawn,
		Vector2(center.x, center.z),
		0.0,
		1.0,
		0.05
	)
	_set_property_if_present(spawn, "spawn_point_id", id_value)
	if _has_property(spawn, "allowed_resource_ids"):
		var allowed: Array[String] = ["giant_pepper", "giant_pumpkin"]
		spawn.set("allowed_resource_ids", allowed)
	_add_spawn_editor_marker(spawn, Color(1.0, 0.45, 0.1, 1.0))
	_stroke_added_objects.append(_serialize_editor_object(spawn))
	_next_spawn_id += 1
	_set_status("Placed giant crop spawn: %s" % id_value)


func _place_wild_animal_spawn(center: Vector3) -> void:
	var script = _load_resource_or_null(WILD_ANIMAL_GENERATOR_PATH) as Script
	if script == null:
		_set_status("Missing wild animal generator script")
		return
	var spawn = Marker3D.new()
	spawn.name = "WildAnimalSpawn_%03d" % _next_spawn_id
	spawn.set_script(script)
	# Prevent animals spawning while this editor scene is running. The saved
	# scene restores PROCESS_MODE_INHERIT for generator nodes.
	spawn.process_mode = Node.PROCESS_MODE_DISABLED
	spawn.set_meta("map_editor_spawn_kind", "wild_animal")
	spawn.set_meta("map_editor_category", "spawn")
	spawn.set_meta("map_editor_asset_path", WILD_ANIMAL_GENERATOR_PATH)
	spawn.set_meta("map_editor_uuid", _new_editor_uuid("spawn"))
	spawn.set_meta("map_editor_align_mode", "upright")
	spawn.set_meta("map_editor_ground_offset", 0.05)
	_spawns_root.add_child(spawn)
	_place_node_on_terrain(
		spawn,
		Vector2(center.x, center.z),
		0.0,
		1.0,
		0.05
	)
	_set_property_if_present(spawn, "generator_id", "wild_animal_%03d" % _next_spawn_id)
	_add_spawn_editor_marker(spawn, Color(0.2, 0.75, 1.0, 1.0))
	_stroke_added_objects.append(_serialize_editor_object(spawn))
	_next_spawn_id += 1
	_set_status("Placed wild animal spawn")


func _apply_farmland_brush(center: Vector3) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		_erase_nodes_in_radius(_farmlands_root, center, _brush_radius, "farmland")
		return
	if _stroke_placed_once or _farmlands_root == null:
		return
	var corners := [
		Vector2(center.x, center.z),
		Vector2(center.x + float(_farmland_length_tiles) * FARM_FIELD_TILE_SPACING, center.z),
		Vector2(center.x, center.z + float(_farmland_width_tiles) * FARM_FIELD_TILE_SPACING),
		Vector2(
			center.x + float(_farmland_length_tiles) * FARM_FIELD_TILE_SPACING,
			center.z + float(_farmland_width_tiles) * FARM_FIELD_TILE_SPACING
		),
	]
	for corner in corners:
		if not _point_inside_map(corner, 0.5):
			_set_status("Farmland placement blocked: area crosses the map boundary")
			return
		if _is_point_in_water(corner, get_terrain_height_world(corner)):
			_set_status("Farmland placement blocked: area overlaps water")
			return

	var field_script := _load_resource_or_null(FARM_FIELD_GENERATOR_SCRIPT_PATH) as Script
	if field_script == null:
		_set_status("Missing FarmFieldGenerator script")
		return
	var field := Node3D.new()
	field.name = "FarmField_%04d" % _next_object_id
	field.set_script(field_script)
	_set_property_if_present(field, "generate_on_ready", false)
	_set_property_if_present(field, "length_tiles", _farmland_length_tiles)
	_set_property_if_present(field, "width_tiles", _farmland_width_tiles)
	_set_property_if_present(field, "tile_spacing", FARM_FIELD_TILE_SPACING)
	_set_property_if_present(field, "field_owner", _selected_farmland_owner)
	_set_property_if_present(field, "field_label", "editor_field_%04d" % _next_object_id)
	field.set_meta("map_editor_category", "farmland")
	field.set_meta("map_editor_asset_path", FARM_FIELD_GENERATOR_SCRIPT_PATH)
	field.set_meta("map_editor_uuid", _new_editor_uuid("farmland"))
	field.set_meta("map_editor_align_mode", "upright")
	field.set_meta("map_editor_ground_offset", 0.02)
	_farmlands_root.add_child(field)
	_place_map_object_at_terrain(field, Vector2(center.x, center.z), 0.0, false, 0.02)
	_refresh_farmland_preview(field)
	_stroke_added_objects.append(_serialize_editor_object(field))
	_next_object_id += 1
	_stroke_placed_once = true
	_set_status("Placed farmland preview; runtime will generate %d x %d FarmTiles" % [_farmland_length_tiles, _farmland_width_tiles])


func _apply_auxiliary_brush(center: Vector3) -> void:
	if Input.is_key_pressed(KEY_SHIFT):
		_erase_nodes_in_radius(_buildings_root, center, _brush_radius, "auxiliary")
		return
	if _stroke_placed_once:
		return
	if not _point_inside_map(Vector2(center.x, center.z), 0.5):
		return
	if _is_point_in_water(Vector2(center.x, center.z), center.y):
		_set_status("Auxiliary placement blocked: point is inside water")
		return
	var asset_path := MESSAGE_AREA_PATH
	if _selected_auxiliary_kind == "power_pole":
		asset_path = POWER_POLE_PATH
	elif _selected_auxiliary_kind == "neutral_crop_generator":
		asset_path = NEUTRAL_CROP_GENERATOR_PATH
	var packed := _load_resource_or_null(asset_path) as PackedScene
	if packed == null:
		_set_status("Missing auxiliary scene: %s" % asset_path)
		return
	var instance := packed.instantiate() as Node3D
	if instance == null:
		_set_status("Auxiliary root is not Node3D: %s" % asset_path)
		return
	var is_power_pole := _selected_auxiliary_kind == "power_pole"
	var is_neutral_crop_generator := _selected_auxiliary_kind == "neutral_crop_generator"
	instance.name = ("PowerPole" if is_power_pole else "MessageArea") + "_%04d" % _next_object_id
	if is_neutral_crop_generator:
		instance.name = "NeutralCropGenerator_%04d" % _next_object_id
	instance.set_meta("map_editor_category", "auxiliary")
	instance.set_meta("map_editor_asset_path", asset_path)
	instance.set_meta("map_editor_uuid", _new_editor_uuid("auxiliary"))
	instance.set_meta("map_editor_align_mode", "upright")
	instance.set_meta("map_editor_ground_offset", 0.0 if is_power_pole else 0.02)
	if is_neutral_crop_generator:
		_set_property_if_present(instance, "generator_id", "neutral_crop_%03d" % _next_object_id)
		_set_property_if_present(instance, "crop_id", _selected_neutral_crop_id)
		_set_property_if_present(instance, "area_size", _neutral_crop_area_size)
		_set_property_if_present(instance, "respawn_interval_seconds", _neutral_crop_respawn_interval)
		_set_property_if_present(instance, "initial_spawn_delay", _neutral_crop_initial_delay)
		_set_property_if_present(instance, "show_boundary", _neutral_crop_show_boundary)
		_set_property_if_present(instance, "boundary_color", _neutral_crop_boundary_color)
	_buildings_root.add_child(instance)
	var placement_yaw := _rng.randf_range(-PI, PI) if is_power_pole else 0.0
	if is_power_pole:
		_place_map_object_at_terrain(instance, Vector2(center.x, center.z), placement_yaw, false, 0.0)
	else:
		_place_node_on_terrain(instance, Vector2(center.x, center.z), placement_yaw, 1.0, 0.02)
	if is_neutral_crop_generator and instance.has_method("refresh_visuals"):
		instance.call("refresh_visuals")
	_stroke_added_objects.append(_serialize_editor_object(instance))
	_next_object_id += 1
	_stroke_placed_once = true
	_rebuild_power_wires()
	if is_power_pole:
		_set_status("Placed Power Pole; adjacent poles now show two live wires")
	elif is_neutral_crop_generator:
		_set_status("Placed Neutral Crop Generator; crops will be generated when the map loads")
	else:
		_set_status("Placed MessageArea; use Transform Objects to edit its Inspector")


func _is_message_area(node: Node3D) -> bool:
	if node == null:
		return false
	var asset_path := str(node.get_meta("map_editor_asset_path", node.scene_file_path))
	return asset_path == MESSAGE_AREA_PATH or node.scene_file_path == MESSAGE_AREA_PATH


func _is_neutral_crop_generator(node: Node3D) -> bool:
	if node == null:
		return false
	var asset_path := str(node.get_meta("map_editor_asset_path", node.scene_file_path))
	return asset_path == NEUTRAL_CROP_GENERATOR_PATH or node.scene_file_path == NEUTRAL_CROP_GENERATOR_PATH


func _is_farmland(node: Node3D) -> bool:
	if node == null:
		return false
	var asset_path := str(node.get_meta("map_editor_asset_path", node.scene_file_path))
	return asset_path == FARM_FIELD_GENERATOR_SCRIPT_PATH or node.get_meta("map_editor_category", "") == "farmland"


func _is_power_pole(node: Node3D) -> bool:
	if node == null:
		return false
	var asset_path := str(node.get_meta("map_editor_asset_path", node.scene_file_path))
	if asset_path == POWER_POLE_PATH or node.scene_file_path == POWER_POLE_PATH:
		return node.get_node_or_null("WirePoint1") != null and node.get_node_or_null("WirePoint2") != null
	return false


func _clear_power_wires() -> void:
	if _power_wires_root == null:
		return
	for child in _power_wires_root.get_children():
		_power_wires_root.remove_child(child)
		child.free()


func _get_power_poles() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if _buildings_root == null:
		return result
	for child in _buildings_root.get_children():
		if child is Node3D and _is_power_pole(child as Node3D):
			result.append(child as Node3D)
	result.sort_custom(func(first: Node3D, second: Node3D) -> bool:
		var first_uuid := str(first.get_meta("map_editor_uuid", first.name))
		var second_uuid := str(second.get_meta("map_editor_uuid", second.name))
		return first_uuid.naturalnocasecmp_to(second_uuid) < 0
	)
	return result


func _rebuild_power_wires() -> void:
	if _power_wires_root == null:
		return
	_clear_power_wires()
	var poles := _get_power_poles()
	if poles.size() < 2:
		return
	var wire_script := _load_resource_or_null(POWER_WIRE_SCRIPT_PATH) as Script
	if wire_script == null:
		push_warning("FarmWar map editor: missing power wire script: %s" % POWER_WIRE_SCRIPT_PATH)
		return
	var wire_count := 0
	for pole_index in range(poles.size() - 1):
		var first := poles[pole_index]
		var second := poles[pole_index + 1]
		for wire_index in range(2):
			var first_point := first.get_node_or_null("WirePoint%d" % (wire_index + 1)) as Node3D
			var second_point := second.get_node_or_null("WirePoint%d" % (wire_index + 1)) as Node3D
			if first_point == null or second_point == null:
				continue
			var wire := Node3D.new()
			wire.name = "PowerWire_%03d" % wire_count
			wire.set_script(wire_script)
			wire.set_meta("power_wire_generated", true)
			wire.set_meta("power_wire_start_uuid", str(first.get_meta("map_editor_uuid", "")))
			wire.set_meta("power_wire_end_uuid", str(second.get_meta("map_editor_uuid", "")))
			wire.set_meta("power_wire_index", wire_index)
			_power_wires_root.add_child(wire)
			var local_start := wire.to_local(first_point.global_position)
			var local_end := wire.to_local(second_point.global_position)
			wire.call("rebuild_from_endpoints", local_start, local_end)
			wire_count += 1
	_power_wires_root.set_meta("power_wire_count", wire_count)


func _new_editor_uuid(category: String) -> String:
	return "%s_%d_%d" % [
		category,
		Time.get_ticks_usec(),
		_rng.randi(),
	]


func _serialize_editor_object(node: Node3D) -> Dictionary:
	var category = str(node.get_meta("map_editor_category", "spawn"))
	var spawn_kind = str(node.get_meta("map_editor_spawn_kind", ""))
	var record: Dictionary = {
		"uuid": str(node.get_meta("map_editor_uuid", _new_editor_uuid(category))),
		"category": category,
		"spawn_kind": spawn_kind,
		"asset_path": str(node.get_meta("map_editor_asset_path", node.scene_file_path)),
		"name": node.name,
		"transform": node.transform,
		"process_mode": int(node.process_mode),
		"align_mode": str(node.get_meta("map_editor_align_mode", "surface_normal")),
		"ground_offset": float(node.get_meta("map_editor_ground_offset", placed_object_ground_offset)),
		"properties": {},
	}
	node.set_meta("map_editor_uuid", record["uuid"])

	var properties = record["properties"] as Dictionary
	for property_name in [
		"tree_id",
		"resource_id",
		"team",
		"spawn_point_id",
		"generator_id",
		"crop_id",
		"respawn_interval_seconds",
		"initial_spawn_delay",
		"boundary_color",
		"show_boundary",
		"allowed_resource_ids",
		"prompt_text",
		"area_size",
		"field_label",
		"length_tiles",
		"width_tiles",
		"tile_spacing",
		"field_owner",
		"generate_on_ready",
	]:
		if _has_property(node, property_name):
			properties[property_name] = node.get(property_name)
	return record


func _commit_object_stroke() -> void:
	if _stroke_added_objects.is_empty() and _stroke_removed_objects.is_empty():
		return
	var added = _stroke_added_objects.duplicate(true)
	var removed = _stroke_removed_objects.duplicate(true)
	var action_name = "Edit Map Objects"
	if not added.is_empty() and removed.is_empty():
		action_name = "Place Map Objects"
	elif added.is_empty() and not removed.is_empty():
		action_name = "Remove Map Objects"

	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(
		_apply_object_change.bind(added, removed)
	)
	_undo_redo.add_undo_method(
		_apply_object_change.bind(removed, added)
	)
	_undo_redo.commit_action(false)


func _apply_object_change(
	records_to_restore: Array,
	records_to_remove: Array
) -> void:
	_remove_object_records(records_to_remove)
	_restore_object_records(records_to_restore)
	_rebuild_resource_multimeshes_deferred()
	_rebuild_power_wires()


func _remove_object_records(records: Array) -> void:
	for record_value in records:
		var record = record_value as Dictionary
		var uuid = str(record.get("uuid", ""))
		var node = _find_editor_object_by_uuid(uuid)
		if node == null:
			continue
		var parent = node.get_parent()
		if parent != null:
			parent.remove_child(node)
		node.free()


func _restore_object_records(records: Array) -> void:
	for record_value in records:
		var record = record_value as Dictionary
		var uuid = str(record.get("uuid", ""))
		if not uuid.is_empty() and _find_editor_object_by_uuid(uuid) != null:
			continue
		var category = str(record.get("category", "spawn"))
		var spawn_kind = str(record.get("spawn_kind", ""))
		var asset_path = str(record.get("asset_path", ""))
		var node: Node3D

		if category == "farmland":
			var field_script := _load_resource_or_null(FARM_FIELD_GENERATOR_SCRIPT_PATH) as Script
			if field_script == null:
				continue
			var field := Node3D.new()
			field.set_script(field_script)
			# FarmWorldInitializer explicitly generates fields after the map has
			# finished loading. Never generate editor preview tiles on add/load.
			_set_property_if_present(field, "generate_on_ready", false)
			node = field
		elif category == "spawn" and spawn_kind == "wild_animal":
			var script = _load_resource_or_null(WILD_ANIMAL_GENERATOR_PATH) as Script
			if script == null:
				continue
			var marker = Marker3D.new()
			marker.set_script(script)
			marker.process_mode = Node.PROCESS_MODE_DISABLED
			node = marker
		else:
			var packed = _load_resource_or_null(asset_path) as PackedScene
			if packed == null:
				continue
			node = packed.instantiate() as Node3D
			if node == null:
				continue

		node.name = str(record.get("name", "MapObject"))
		node.transform = record.get("transform", Transform3D.IDENTITY) as Transform3D
		node.set_meta("map_editor_uuid", uuid)
		node.set_meta("map_editor_category", category)
		node.set_meta("map_editor_asset_path", asset_path)
		node.set_meta("map_editor_align_mode", str(record.get("align_mode", "surface_normal")))
		node.set_meta("map_editor_ground_offset", float(record.get("ground_offset", placed_object_ground_offset)))
		if not spawn_kind.is_empty():
			node.set_meta("map_editor_spawn_kind", spawn_kind)

		var target_root = _category_root_for_record(category)
		if target_root == null:
			node.free()
			continue
		target_root.add_child(node)

		var properties = record.get("properties", {}) as Dictionary
		for property_name_value in properties.keys():
			var property_name = str(property_name_value)
			_set_property_if_present(node, property_name, properties[property_name])
		if node.has_method("refresh_visuals"):
			node.call("refresh_visuals")

		if category == "spawn":
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if spawn_kind == "wild_animal":
				_add_spawn_editor_marker(node, Color(0.2, 0.75, 1.0, 1.0))
			elif spawn_kind == "team_red":
				_add_spawn_editor_marker(node, Color(0.95, 0.2, 0.2, 1.0))
			elif spawn_kind == "team_blue":
				_add_spawn_editor_marker(node, Color(0.2, 0.45, 1.0, 1.0))
			else:
				_add_spawn_editor_marker(node, Color(1.0, 0.45, 0.1, 1.0))
		elif category == "farmland":
			_set_property_if_present(node, "generate_on_ready", false)
			_refresh_farmland_preview(node)
	_rebuild_power_wires()


func _category_root_for_record(category: String) -> Node3D:
	match category:
		"tree":
			return _trees_root
		"ore":
			return _ores_root
		"building":
			return _buildings_root
		"auxiliary":
			return _buildings_root
		"farmland":
			return _farmlands_root
		_:
			return _spawns_root


func _find_editor_object_by_uuid(uuid: String) -> Node3D:
	if uuid.is_empty():
		return null
	for root in [_trees_root, _ores_root, _spawns_root, _buildings_root, _farmlands_root]:
		if root == null:
			continue
		for child in root.get_children():
			if child is Node3D and str(child.get_meta("map_editor_uuid", "")) == uuid:
				return child as Node3D
	return null


func _add_spawn_editor_marker(spawn: Node3D, color: Color) -> void:
	var marker = MeshInstance3D.new()
	marker.name = "_EditorMarker"
	marker.set_meta(EDITOR_MARKER_META, true)
	var cylinder = CylinderMesh.new()
	cylinder.top_radius = 0.35
	cylinder.bottom_radius = 0.35
	cylinder.height = 4.0
	marker.mesh = cylinder
	marker.position.y = 2.0
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(color.r, color.g, color.b, 0.65)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	spawn.add_child(marker)
	if spawn is TeamSpawnPoint:
		var label := Label3D.new()
		label.name = "_EditorSpawnLabel"
		label.set_meta(EDITOR_MARKER_META, true)
		label.position = Vector3(0.0, 4.6, 0.0)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.outline_size = 8
		label.modulate = color
		label.no_depth_test = true
		spawn.add_child(label)
		_refresh_spawn_editor_label(spawn as TeamSpawnPoint)


func _refresh_spawn_editor_label(point: TeamSpawnPoint) -> void:
	if point == null:
		return
	var label := point.get_node_or_null("_EditorSpawnLabel") as Label3D
	if label == null:
		return
	label.text = _spawn_point_display_label(point).get_slice(" (", 0)
	label.modulate = Color(0.95, 0.2, 0.2, 1.0) if str(point.team) == "red" else Color(0.2, 0.45, 1.0, 1.0)


# -----------------------------------------------------------------------------
# Building placement and unified object transform tool
# -----------------------------------------------------------------------------

func _apply_building_placement(center: Vector3) -> void:
	if _stroke_placed_once or _selected_building_asset.is_empty():
		return
	if not _building_preview_valid:
		_set_status("Building placement blocked: %s" % _building_preview_block_reason)
		return
	var scene_path = str(_selected_building_asset.get("path", ""))
	if not scene_path.begins_with(BUILDINGS_RESOURCE_ROOT + "/") or scene_path.begins_with(BUILDINGS_EXCLUDED_ROOT + "/"):
		_set_status("Rejected building path: %s" % scene_path)
		return
	var packed = _load_resource_or_null(scene_path) as PackedScene
	if packed == null:
		_set_status("Missing building scene: %s" % scene_path)
		return
	var instance = packed.instantiate() as Node3D
	if instance == null:
		_set_status("Building scene root is not Node3D: %s" % scene_path)
		return
	instance.name = "%s_%04d" % [str(_selected_building_asset.get("id", "building")).capitalize(), _next_object_id]
	instance.set_meta("map_editor_category", "building")
	instance.set_meta("map_editor_asset_path", scene_path)
	instance.set_meta("map_editor_uuid", _new_editor_uuid("building"))
	instance.set_meta("map_editor_align_mode", "upright")
	instance.set_meta("map_editor_ground_offset", building_ground_offset)
	_buildings_root.add_child(instance)
	_place_map_object_at_terrain(instance, Vector2(center.x, center.z), _building_preview_yaw, false, building_ground_offset)
	var validation = _validate_building_node(instance, instance)
	if not bool(validation.get("valid", false)):
		_buildings_root.remove_child(instance)
		instance.queue_free()
		_set_status("Building placement blocked: %s" % str(validation.get("reason", "overlap")))
		return
	_stroke_added_objects.append(_serialize_editor_object(instance))
	_next_object_id += 1
	_stroke_placed_once = true
	_set_status("Placed building: %s" % str(_selected_building_asset.get("label", instance.name)))

func _rebuild_building_preview() -> void:
	_clear_building_preview()
	if _selected_building_asset.is_empty():
		return
	var path = str(_selected_building_asset.get("path", ""))
	var packed = _load_resource_or_null(path) as PackedScene
	if packed == null:
		return
	var preview = packed.instantiate() as Node3D
	if preview == null:
		return
	_prepare_editor_preview_scene(preview)
	preview.name = "BuildingPlacementPreview"
	preview.set_meta(EDITOR_MARKER_META, true)
	add_child(preview)
	_building_preview = preview
	_update_building_preview_from_latest_hit()


func _prepare_editor_preview_scene(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.get_script() != null:
		node.set_script(null)
	if node is CollisionObject3D:
		var collision_object = node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	if node is GeometryInstance3D:
		var geometry = node as GeometryInstance3D
		geometry.transparency = clampf(building_preview_transparency, 0.05, 0.95)
		geometry.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if node is Light3D:
		(node as Light3D).visible = false
	if node is Camera3D:
		(node as Camera3D).current = false
	if node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	if node is WorldEnvironment:
		(node as WorldEnvironment).environment = null
	for child in node.get_children():
		_prepare_editor_preview_scene(child)

func _clear_building_preview() -> void:
	if is_instance_valid(_building_preview):
		if _building_preview.get_parent() != null:
			_building_preview.get_parent().remove_child(_building_preview)
		_building_preview.queue_free()
	_building_preview = null
	_building_preview_valid = false
	_building_preview_block_reason = ""
	_hide_building_footprint_preview()

func _set_building_preview_visible(value: bool) -> void:
	if is_instance_valid(_building_preview):
		_building_preview.visible = value
	if not value:
		_hide_building_footprint_preview()

func _update_building_preview_from_latest_hit() -> void:
	if _latest_hit.is_empty():
		_set_building_preview_visible(false)
		return
	_update_building_preview(_latest_hit.get("position", Vector3.ZERO) as Vector3)


func _update_building_preview(center: Vector3) -> void:
	if not is_instance_valid(_building_preview):
		if not _selected_building_asset.is_empty():
			_rebuild_building_preview()
		if not is_instance_valid(_building_preview):
			return
	var world_xz = Vector2(center.x, center.z)
	_place_map_object_at_terrain(_building_preview, world_xz, _building_preview_yaw, false, building_ground_offset)
	var validation = _validate_building_node(_building_preview, null)
	_building_preview_valid = bool(validation.get("valid", false))
	_building_preview_block_reason = str(validation.get("reason", ""))
	_building_preview.visible = true
	_draw_building_footprint(_get_node_footprint_polygon(_building_preview), _building_preview_valid)
	_brush_preview_material.albedo_color = Color(0.2, 1.0, 0.25, 0.95) if _building_preview_valid else Color(1.0, 0.1, 0.05, 0.95)

func _validate_building_node(node: Node3D, ignore_node: Node3D) -> Dictionary:
	var polygon = _get_node_footprint_polygon(node)
	if polygon.size() < 3:
		return {"valid": false, "reason": "building has no usable visual bounds"}
	for corner in polygon:
		if not _point_inside_map(corner, 0.05):
			return {"valid": false, "reason": "footprint crosses the map boundary"}
	var center_xz = Vector2(node.global_position.x, node.global_position.z)
	if _is_point_in_water(center_xz, node.global_position.y):
		return {"valid": false, "reason": "footprint is inside water"}
	for corner in polygon:
		if _is_point_in_water(corner, get_terrain_height_world(corner)):
			return {"valid": false, "reason": "footprint overlaps water"}
	var normal = get_terrain_normal_world(center_xz)
	var slope_degrees = rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
	if slope_degrees > building_max_slope_degrees:
		return {"valid": false, "reason": "slope %.1f° exceeds %.1f°" % [slope_degrees, building_max_slope_degrees]}
	for candidate in _get_building_overlap_candidates():
		if candidate == ignore_node or not is_instance_valid(candidate):
			continue
		var candidate_polygon = _get_node_footprint_polygon(candidate)
		if candidate_polygon.size() < 3:
			continue
		if _footprint_polygons_overlap(polygon, candidate_polygon, building_overlap_margin):
			return {"valid": false, "reason": "overlaps %s" % candidate.name}
	return {"valid": true, "reason": ""}


func _get_building_overlap_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for root in [_buildings_root, _trees_root, _ores_root]:
		if root == null:
			continue
		if root != _buildings_root and not building_overlap_checks_resources:
			continue
		for child in root.get_children():
			if child is Node3D and not bool(child.get_meta(EDITOR_MARKER_META, false)):
				result.append(child as Node3D)
	return result


func _get_node_footprint_polygon(node: Node3D) -> PackedVector2Array:
	var local_aabb = _calculate_node_aabb_relative_to(node, node)
	if local_aabb.size.length_squared() <= 0.000001:
		local_aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3(1.0, 1.0, 1.0))
	var projected_points = PackedVector2Array()
	for x_index in [0, 1]:
		for y_index in [0, 1]:
			for z_index in [0, 1]:
				var local_corner = local_aabb.position + Vector3(
					local_aabb.size.x * x_index,
					local_aabb.size.y * y_index,
					local_aabb.size.z * z_index
				)
				var world_corner = node.to_global(local_corner)
				projected_points.append(Vector2(world_corner.x, world_corner.z))
	var hull = Geometry2D.convex_hull(projected_points)
	if hull.size() > 1 and hull[0].is_equal_approx(hull[hull.size() - 1]):
		hull.resize(hull.size() - 1)
	return hull

func _footprint_polygons_overlap(first: PackedVector2Array, second: PackedVector2Array, margin: float) -> bool:
	for polygon in [first, second]:
		for index in range(polygon.size()):
			var edge = polygon[(index + 1) % polygon.size()] - polygon[index]
			if edge.length_squared() <= 0.000001:
				continue
			var axis = Vector2(-edge.y, edge.x).normalized()
			var first_range = _project_footprint_polygon(first, axis)
			var second_range = _project_footprint_polygon(second, axis)
			if first_range.y + margin < second_range.x or second_range.y + margin < first_range.x:
				return false
	return true


func _project_footprint_polygon(polygon: PackedVector2Array, axis: Vector2) -> Vector2:
	var minimum = polygon[0].dot(axis)
	var maximum = minimum
	for point in polygon:
		var value = point.dot(axis)
		minimum = minf(minimum, value)
		maximum = maxf(maximum, value)
	return Vector2(minimum, maximum)


func _draw_building_footprint(polygon: PackedVector2Array, valid: bool) -> void:
	if polygon.size() < 3 or _building_footprint_fill_mesh == null:
		_hide_building_footprint_preview()
		return
	var fill_color = Color(0.15, 1.0, 0.25, 0.26) if valid else Color(1.0, 0.08, 0.04, 0.34)
	var outline_color = Color(0.15, 1.0, 0.25, 0.98) if valid else Color(1.0, 0.08, 0.04, 1.0)
	_building_footprint_fill_material.albedo_color = fill_color
	_building_footprint_outline_material.albedo_color = outline_color
	var vertices: Array[Vector3] = []
	for corner in polygon:
		vertices.append(Vector3(corner.x, get_terrain_height_world(corner) + 0.045, corner.y))
	var triangles = Geometry2D.triangulate_polygon(polygon)
	_building_footprint_fill_mesh.clear_surfaces()
	if triangles.size() >= 3:
		_building_footprint_fill_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in triangles:
			_building_footprint_fill_mesh.surface_add_vertex(vertices[int(index)])
		_building_footprint_fill_mesh.surface_end()
	_building_footprint_outline_mesh.clear_surfaces()
	_building_footprint_outline_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(vertices.size()):
		_building_footprint_outline_mesh.surface_add_vertex(vertices[index])
		_building_footprint_outline_mesh.surface_add_vertex(vertices[(index + 1) % vertices.size()])
	_building_footprint_outline_mesh.surface_end()
	_building_footprint_fill.global_transform = Transform3D.IDENTITY
	_building_footprint_outline.global_transform = Transform3D.IDENTITY
	_building_footprint_fill.visible = triangles.size() >= 3
	_building_footprint_outline.visible = true

func _hide_building_footprint_preview() -> void:
	if _building_footprint_fill != null:
		_building_footprint_fill.visible = false
	if _building_footprint_outline != null:
		_building_footprint_outline.visible = false

func _place_map_object_at_terrain(
	node: Node3D,
	world_xz: Vector2,
	yaw_radians: float,
	align_to_normal: bool,
	ground_offset: float
) -> void:
	var surface_normal = get_terrain_normal_world(world_xz) if align_to_normal else Vector3.UP
	var scale_value = node.global_basis.get_scale()
	var basis = _basis_from_surface_normal_explicit(surface_normal, yaw_radians, scale_value, align_to_normal)
	node.global_transform = Transform3D(
		basis,
		Vector3(world_xz.x, get_terrain_height_world(world_xz) + ground_offset, world_xz.y)
	)


func _basis_from_surface_normal_explicit(
	surface_normal: Vector3,
	yaw_radians: float,
	scale_value: Vector3,
	align_to_normal: bool
) -> Basis:
	if not align_to_normal:
		return Basis(Vector3.UP, yaw_radians).scaled(scale_value)
	var up_axis = surface_normal.normalized()
	if up_axis.length_squared() <= 0.000001:
		up_axis = Vector3.UP
	var yaw_basis = Basis(Vector3.UP, yaw_radians)
	var z_axis = yaw_basis.z - up_axis * yaw_basis.z.dot(up_axis)
	if z_axis.length_squared() <= 0.000001:
		z_axis = Vector3.FORWARD - up_axis * Vector3.FORWARD.dot(up_axis)
	if z_axis.length_squared() <= 0.000001:
		z_axis = Vector3.RIGHT - up_axis * Vector3.RIGHT.dot(up_axis)
	z_axis = z_axis.normalized()
	var x_axis = up_axis.cross(z_axis).normalized()
	z_axis = x_axis.cross(up_axis).normalized()
	return Basis(x_axis, up_axis, z_axis).orthonormalized().scaled(scale_value)


func _refresh_transform_gizmo() -> void:
	if _object_gizmo_mesh == null or not is_instance_valid(_selected_map_object) or _tool_mode != ToolMode.OBJECT_EDIT:
		if _object_gizmo != null:
			_object_gizmo.visible = false
		return
	var pivot = _selected_map_object.global_position
	var length = _get_transform_gizmo_length()
	_object_gizmo_mesh.clear_surfaces()
	_object_gizmo_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if _object_transform_mode == ObjectTransformMode.ROTATE:
		_draw_gizmo_rotation_ring(pivot, _get_gizmo_axis_world(GizmoAxis.X), length * 0.78, _gizmo_axis_color(GizmoAxis.X))
		_draw_gizmo_rotation_ring(pivot, _get_gizmo_axis_world(GizmoAxis.Y), length * 0.78, _gizmo_axis_color(GizmoAxis.Y))
		_draw_gizmo_rotation_ring(pivot, _get_gizmo_axis_world(GizmoAxis.Z), length * 0.78, _gizmo_axis_color(GizmoAxis.Z))
	else:
		for axis in [GizmoAxis.X, GizmoAxis.Y, GizmoAxis.Z]:
			var direction = _get_gizmo_axis_world(axis)
			var color = _gizmo_axis_color(axis)
			_draw_gizmo_line(pivot, pivot + direction * length, color)
			_draw_gizmo_tip(pivot + direction * length, length * 0.07, color)
		if _object_transform_mode == ObjectTransformMode.SCALE:
			_draw_gizmo_tip(pivot, length * 0.09, Color(1.0, 0.92, 0.2, 1.0))
	_object_gizmo_mesh.surface_end()
	_object_gizmo.global_transform = Transform3D.IDENTITY
	_object_gizmo.visible = true


func _get_transform_gizmo_length() -> float:
	if _editor_camera == null or not is_instance_valid(_selected_map_object):
		return 2.0
	var distance = _editor_camera.global_position.distance_to(_selected_map_object.global_position)
	return clampf(distance * 0.09, 1.25, 18.0)


func _get_gizmo_axis_world(axis: int) -> Vector3:
	var local_axis = Vector3.RIGHT
	if axis == GizmoAxis.Y:
		local_axis = Vector3.UP
	elif axis == GizmoAxis.Z:
		local_axis = Vector3.BACK
	if not _gizmo_local_space or not is_instance_valid(_selected_map_object):
		return local_axis
	var rotation_basis = _selected_map_object.global_basis.orthonormalized()
	return (rotation_basis * local_axis).normalized()


func _gizmo_axis_color(axis: int) -> Color:
	var color = Color.WHITE
	if axis == GizmoAxis.X:
		color = Color(1.0, 0.18, 0.16, 1.0)
	elif axis == GizmoAxis.Y:
		color = Color(0.2, 1.0, 0.28, 1.0)
	elif axis == GizmoAxis.Z:
		color = Color(0.2, 0.48, 1.0, 1.0)
	if _object_dragging and _object_drag_axis == axis:
		color = Color(1.0, 0.95, 0.25, 1.0)
	return color


func _draw_gizmo_line(from: Vector3, to: Vector3, color: Color) -> void:
	_object_gizmo_mesh.surface_set_color(color)
	_object_gizmo_mesh.surface_add_vertex(from)
	_object_gizmo_mesh.surface_add_vertex(to)


func _draw_gizmo_tip(center: Vector3, half_size: float, color: Color) -> void:
	var right = _editor_camera.global_basis.x.normalized() * half_size
	var up = _editor_camera.global_basis.y.normalized() * half_size
	_draw_gizmo_line(center - right, center + right, color)
	_draw_gizmo_line(center - up, center + up, color)
	_draw_gizmo_line(center - right - up, center + right + up, color)
	_draw_gizmo_line(center - right + up, center + right - up, color)


func _draw_gizmo_rotation_ring(center: Vector3, normal: Vector3, radius: float, color: Color) -> void:
	var reference = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent = normal.cross(reference).normalized()
	var bitangent = normal.cross(tangent).normalized()
	var segments = 64
	for index in range(segments):
		var angle_a = TAU * float(index) / float(segments)
		var angle_b = TAU * float(index + 1) / float(segments)
		var point_a = center + (tangent * cos(angle_a) + bitangent * sin(angle_a)) * radius
		var point_b = center + (tangent * cos(angle_b) + bitangent * sin(angle_b)) * radius
		_draw_gizmo_line(point_a, point_b, color)


func _pick_transform_gizmo_handle(mouse_position: Vector2) -> int:
	if not is_instance_valid(_selected_map_object) or _editor_camera == null:
		return GizmoAxis.NONE
	var pivot = _selected_map_object.global_position
	var length = _get_transform_gizmo_length()
	var best_axis = GizmoAxis.NONE
	var best_distance = gizmo_pick_radius_px + 1.0
	var pivot_screen = _editor_camera.unproject_position(pivot)
	if _object_transform_mode == ObjectTransformMode.SCALE and mouse_position.distance_to(pivot_screen) <= gizmo_pick_radius_px:
		return GizmoAxis.UNIFORM
	if _object_transform_mode == ObjectTransformMode.ROTATE:
		for axis in [GizmoAxis.X, GizmoAxis.Y, GizmoAxis.Z]:
			var distance = _screen_distance_to_rotation_ring(mouse_position, pivot, _get_gizmo_axis_world(axis), length * 0.78)
			if distance < best_distance:
				best_distance = distance
				best_axis = axis
	else:
		for axis in [GizmoAxis.X, GizmoAxis.Y, GizmoAxis.Z]:
			var end_screen = _editor_camera.unproject_position(pivot + _get_gizmo_axis_world(axis) * length)
			var distance = _point_segment_distance_2d(mouse_position, pivot_screen, end_screen)
			if distance < best_distance:
				best_distance = distance
				best_axis = axis
	return best_axis if best_distance <= gizmo_pick_radius_px else GizmoAxis.NONE


func _screen_distance_to_rotation_ring(mouse_position: Vector2, center: Vector3, normal: Vector3, radius: float) -> float:
	var reference = Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	var tangent = normal.cross(reference).normalized()
	var bitangent = normal.cross(tangent).normalized()
	var best = 1000000.0
	var segments = 64
	for index in range(segments):
		var angle_a = TAU * float(index) / float(segments)
		var angle_b = TAU * float(index + 1) / float(segments)
		var world_a = center + (tangent * cos(angle_a) + bitangent * sin(angle_a)) * radius
		var world_b = center + (tangent * cos(angle_b) + bitangent * sin(angle_b)) * radius
		var screen_a = _editor_camera.unproject_position(world_a)
		var screen_b = _editor_camera.unproject_position(world_b)
		best = minf(best, _point_segment_distance_2d(mouse_position, screen_a, screen_b))
	return best


func _point_segment_distance_2d(point: Vector2, start: Vector2, end: Vector2) -> float:
	var segment = end - start
	var length_squared = segment.length_squared()
	if length_squared <= 0.000001:
		return point.distance_to(start)
	var amount = clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(start + segment * amount)


func _begin_object_gizmo_drag(axis: int, mouse_position: Vector2) -> void:
	if not is_instance_valid(_selected_map_object):
		return
	_object_dragging = true
	_object_drag_axis = axis
	_object_drag_before_transform = _selected_map_object.transform
	_object_drag_start_global_transform = _selected_map_object.global_transform
	_object_drag_start_mouse = mouse_position
	_object_transform_valid = true
	var pivot = _selected_map_object.global_position
	if axis == GizmoAxis.UNIFORM:
		_refresh_transform_gizmo()
		return
	_object_drag_axis_world = _get_gizmo_axis_world(axis)
	var ray = _get_editor_mouse_ray(mouse_position)
	var ray_origin = ray["origin"] as Vector3
	var ray_direction = ray["direction"] as Vector3
	if _object_transform_mode == ObjectTransformMode.ROTATE:
		_object_drag_plane_normal = _object_drag_axis_world
		var rotation_hit = _intersect_ray_plane(ray_origin, ray_direction, pivot, _object_drag_plane_normal)
		if rotation_hit != null:
			_object_drag_start_vector = ((rotation_hit as Vector3) - pivot).normalized()
	else:
		var camera_forward = -_editor_camera.global_basis.z.normalized()
		var side = _object_drag_axis_world.cross(camera_forward)
		if side.length_squared() <= 0.000001:
			side = _object_drag_axis_world.cross(_editor_camera.global_basis.y.normalized())
		_object_drag_plane_normal = side.cross(_object_drag_axis_world).normalized()
		var axis_hit = _intersect_ray_plane(ray_origin, ray_direction, pivot, _object_drag_plane_normal)
		if axis_hit != null:
			_object_drag_start_parameter = ((axis_hit as Vector3) - pivot).dot(_object_drag_axis_world)
	_refresh_transform_gizmo()


func _get_editor_mouse_ray(mouse_position: Vector2) -> Dictionary:
	return {
		"origin": _editor_camera.project_ray_origin(mouse_position),
		"direction": _editor_camera.project_ray_normal(mouse_position).normalized(),
	}


func _intersect_ray_plane(ray_origin: Vector3, ray_direction: Vector3, plane_point: Vector3, plane_normal: Vector3):
	var denominator = plane_normal.dot(ray_direction)
	if absf(denominator) <= 0.000001:
		return null
	var distance = plane_normal.dot(plane_point - ray_origin) / denominator
	if distance < 0.0:
		return null
	return ray_origin + ray_direction * distance


func _update_object_gizmo_drag(mouse_position: Vector2) -> void:
	if not _object_dragging or not is_instance_valid(_selected_map_object):
		return
	if _object_transform_mode == ObjectTransformMode.MOVE:
		_update_move_gizmo_drag(mouse_position)
	elif _object_transform_mode == ObjectTransformMode.ROTATE:
		_update_rotate_gizmo_drag(mouse_position)
	else:
		_update_scale_gizmo_drag(mouse_position)
	_update_selected_object_transform_validity()
	_refresh_selection_visual()
	_refresh_transform_gizmo()
	_sync_object_numeric_controls()
	if _is_power_pole(_selected_map_object):
		_rebuild_power_wires()


func _update_move_gizmo_drag(mouse_position: Vector2) -> void:
	var ray = _get_editor_mouse_ray(mouse_position)
	var hit = _intersect_ray_plane(ray["origin"] as Vector3, ray["direction"] as Vector3, _object_drag_start_global_transform.origin, _object_drag_plane_normal)
	if hit == null:
		return
	var parameter = ((hit as Vector3) - _object_drag_start_global_transform.origin).dot(_object_drag_axis_world)
	var delta = snappedf(parameter - _object_drag_start_parameter, object_move_snap)
	var transform_value = _object_drag_start_global_transform
	transform_value.origin += _object_drag_axis_world * delta
	if not _point_inside_map(Vector2(transform_value.origin.x, transform_value.origin.z), 0.0):
		_show_boundary_warning()
		return
	_selected_map_object.global_transform = transform_value


func _update_rotate_gizmo_drag(mouse_position: Vector2) -> void:
	var pivot = _object_drag_start_global_transform.origin
	var ray = _get_editor_mouse_ray(mouse_position)
	var hit = _intersect_ray_plane(ray["origin"] as Vector3, ray["direction"] as Vector3, pivot, _object_drag_axis_world)
	if hit == null:
		return
	var current_vector = ((hit as Vector3) - pivot).normalized()
	if current_vector.length_squared() <= 0.000001 or _object_drag_start_vector.length_squared() <= 0.000001:
		return
	var angle = atan2(
		_object_drag_axis_world.dot(_object_drag_start_vector.cross(current_vector)),
		_object_drag_start_vector.dot(current_vector)
	)
	angle = snappedf(angle, deg_to_rad(object_rotation_snap_degrees))
	var start_scale = _object_drag_start_global_transform.basis.get_scale()
	var start_rotation = _object_drag_start_global_transform.basis.orthonormalized()
	var new_rotation: Basis
	if _gizmo_local_space:
		var local_axis = Vector3.RIGHT
		if _object_drag_axis == GizmoAxis.Y:
			local_axis = Vector3.UP
		elif _object_drag_axis == GizmoAxis.Z:
			local_axis = Vector3.BACK
		new_rotation = start_rotation * Basis(local_axis, angle)
	else:
		new_rotation = Basis(_object_drag_axis_world, angle) * start_rotation
	_selected_map_object.global_transform = Transform3D(new_rotation * Basis.from_scale(start_scale), pivot)


func _update_scale_gizmo_drag(mouse_position: Vector2) -> void:
	var start_scale = _object_drag_start_global_transform.basis.get_scale()
	var new_scale = start_scale
	if _object_drag_axis == GizmoAxis.UNIFORM:
		var factor = 1.0 + (_object_drag_start_mouse.y - mouse_position.y) * 0.01
		factor = maxf(0.01, factor)
		new_scale = start_scale * factor
	else:
		var ray = _get_editor_mouse_ray(mouse_position)
		var hit = _intersect_ray_plane(ray["origin"] as Vector3, ray["direction"] as Vector3, _object_drag_start_global_transform.origin, _object_drag_plane_normal)
		if hit == null:
			return
		var parameter = ((hit as Vector3) - _object_drag_start_global_transform.origin).dot(_object_drag_axis_world)
		var delta = parameter - _object_drag_start_parameter
		var factor = maxf(0.01, 1.0 + delta / maxf(_get_transform_gizmo_length(), 0.1))
		if _object_drag_axis == GizmoAxis.X:
			new_scale.x = start_scale.x * factor
		elif _object_drag_axis == GizmoAxis.Y:
			new_scale.y = start_scale.y * factor
		else:
			new_scale.z = start_scale.z * factor
	new_scale.x = clampf(snappedf(new_scale.x, object_scale_snap), object_minimum_scale, object_maximum_scale)
	new_scale.y = clampf(snappedf(new_scale.y, object_scale_snap), object_minimum_scale, object_maximum_scale)
	new_scale.z = clampf(snappedf(new_scale.z, object_scale_snap), object_minimum_scale, object_maximum_scale)
	var rotation = _object_drag_start_global_transform.basis.orthonormalized()
	_selected_map_object.global_transform = Transform3D(rotation * Basis.from_scale(new_scale), _object_drag_start_global_transform.origin)


func _update_selected_object_transform_validity() -> void:
	_object_transform_valid = true
	if not is_instance_valid(_selected_map_object):
		return
	if str(_selected_map_object.get_meta("map_editor_category", "")) == "building":
		var validation = _validate_building_node(_selected_map_object, _selected_map_object)
		_object_transform_valid = bool(validation.get("valid", false))
		_draw_building_footprint(_get_node_footprint_polygon(_selected_map_object), _object_transform_valid)
	else:
		_hide_building_footprint_preview()

func _handle_object_edit_left_press() -> void:
	if is_instance_valid(_selected_map_object):
		var axis = _pick_transform_gizmo_handle(get_viewport().get_mouse_position())
		if axis != GizmoAxis.NONE:
			_begin_object_gizmo_drag(axis, get_viewport().get_mouse_position())
			return
	var picked = _pick_editor_object_at_mouse()
	if picked == null:
		_clear_selected_map_object()
		return
	_select_map_object(picked)

func _pick_editor_object_at_mouse() -> Node3D:
	if _editor_camera == null:
		return null
	var mouse_position = get_viewport().get_mouse_position()
	var ray_from = _editor_camera.project_ray_origin(mouse_position)
	var ray_to = ray_from + _editor_camera.project_ray_normal(mouse_position) * MAX_RAY_DISTANCE
	var query = PhysicsRayQueryParameters3D.create(ray_from, ray_to, 0x7FFFFFFF)
	query.collide_with_areas = true
	query.collide_with_bodies = true
	if _camera_rig != null:
		query.exclude = [_camera_rig.get_rid()]
	var hit = get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var collider = hit.get("collider", null) as Node
		var root = _find_editable_object_root(collider)
		if root != null:
			return root

	var best: Node3D = null
	var best_score = INF
	for candidate in _get_all_editable_objects():
		var center = _get_object_selection_center(candidate)
		if _editor_camera.is_position_behind(center):
			continue
		var screen = _editor_camera.unproject_position(center)
		var pixel_distance = screen.distance_to(mouse_position)
		if pixel_distance > object_pick_radius_px:
			continue
		var score = pixel_distance + _editor_camera.global_position.distance_to(center) * 0.002
		if score < best_score:
			best_score = score
			best = candidate
	return best


func _find_editable_object_root(node: Node) -> Node3D:
	var cursor = node
	while cursor != null:
		if cursor is Node3D and _is_direct_editable_object(cursor as Node3D):
			return cursor as Node3D
		cursor = cursor.get_parent()
	return null


func _is_direct_editable_object(node: Node3D) -> bool:
	if node == null:
		return false
	return node.get_parent() in [_trees_root, _ores_root, _spawns_root, _buildings_root, _farmlands_root]


func _get_all_editable_objects() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for root in [_trees_root, _ores_root, _spawns_root, _buildings_root, _farmlands_root]:
		if root == null:
			continue
		for child in root.get_children():
			if child is Node3D:
				result.append(child as Node3D)
	return result


func _get_object_selection_center(node: Node3D) -> Vector3:
	var aabb = _calculate_node_aabb_relative_to(node, node)
	if aabb.size.length_squared() <= 0.000001:
		return node.global_position
	return node.to_global(aabb.get_center())


func _select_map_object(node: Node3D) -> void:
	_selected_map_object = node
	_object_transform_valid = true
	_refresh_selection_visual()
	_refresh_transform_gizmo()
	_update_object_edit_status()
	_sync_object_numeric_controls()
	if _tool_mode == ToolMode.OBJECT_EDIT:
		_refresh_bottom_dock()
	_set_status("Selected: %s" % node.name)


func _set_selected_team_spawn_team(team: String) -> void:
	if not _selected_map_object is TeamSpawnPoint:
		return
	var point := _selected_map_object as TeamSpawnPoint
	var previous_team := str(point.team)
	if previous_team == team:
		return
	var uuid := str(point.get_meta("map_editor_uuid", ""))
	if uuid.is_empty():
		return
	var previous_spawn_id := point.spawn_point_id
	var next_spawn_id := _next_team_spawn_id(team)
	_apply_team_spawn_team(uuid, team, next_spawn_id)
	_undo_redo.create_action("Set Spawn Team")
	_undo_redo.add_do_method(_apply_team_spawn_team.bind(uuid, team, next_spawn_id))
	_undo_redo.add_undo_method(_apply_team_spawn_team.bind(uuid, previous_team, previous_spawn_id))
	_undo_redo.commit_action(false)
	_refresh_bottom_dock()


func _apply_team_spawn_team(uuid: String, team: String, spawn_id_override: String = "") -> void:
	var node := _find_editor_object_by_uuid(uuid)
	if not node is TeamSpawnPoint:
		return
	var point := node as TeamSpawnPoint
	point.team = team
	point.spawn_point_id = spawn_id_override if not spawn_id_override.is_empty() else _next_team_spawn_id(team)
	point.name = "%sTeamSpawn" % ("Red" if team == "red" else "Blue")
	var marker := point.get_node_or_null("_EditorMarker") as MeshInstance3D
	if marker != null:
		var material := marker.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = Color(0.95, 0.2, 0.2, 0.65) if team == "red" else Color(0.2, 0.45, 1.0, 0.65)
	_refresh_spawn_editor_label(point)

func _clear_selected_map_object() -> void:
	_end_object_transform_drag()
	_selected_map_object = null
	_object_transform_valid = true
	if _selection_visual != null:
		_selection_visual.visible = false
	if _object_gizmo != null:
		_object_gizmo.visible = false
	_hide_building_footprint_preview()
	_update_object_edit_status()
	_sync_object_numeric_controls()

func _set_object_transform_mode(mode: int) -> void:
	_end_object_transform_drag()
	_object_transform_mode = mode
	if _object_move_button != null:
		_object_move_button.button_pressed = mode == ObjectTransformMode.MOVE
	if _object_rotate_button != null:
		_object_rotate_button.button_pressed = mode == ObjectTransformMode.ROTATE
	if _object_scale_button != null:
		_object_scale_button.button_pressed = mode == ObjectTransformMode.SCALE
	_update_object_edit_status()
	_refresh_transform_gizmo()

func _move_selected_object_to_terrain(hit_position: Vector3) -> void:
	# Retained for compatibility with older callers. The V9 editor uses the XYZ gizmo.
	if not is_instance_valid(_selected_map_object):
		return
	var transform_value = _selected_map_object.global_transform
	transform_value.origin = hit_position
	_selected_map_object.global_transform = transform_value
	_refresh_selection_visual()
	_refresh_transform_gizmo()

func _rotate_selected_object_from_mouse(relative_x: float) -> void:
	# Retained for compatibility. Rotation is handled by the three-axis gizmo.
	return

func _end_object_transform_drag() -> void:
	if not _object_dragging:
		return
	_object_dragging = false
	_object_drag_axis = GizmoAxis.NONE
	if not is_instance_valid(_selected_map_object):
		return
	if not _object_transform_valid:
		_selected_map_object.transform = _object_drag_before_transform
		_set_status("Transform cancelled: building footprint overlaps another object or leaves the map.")
		_object_transform_valid = true
		_hide_building_footprint_preview()
		_refresh_selection_visual()
		_refresh_transform_gizmo()
		_sync_object_numeric_controls()
		return
	var after = _selected_map_object.transform
	if _object_drag_before_transform.is_equal_approx(after):
		_hide_building_footprint_preview()
		_refresh_transform_gizmo()
		return
	var uuid = str(_selected_map_object.get_meta("map_editor_uuid", ""))
	var action_name = "Move Map Object"
	if _object_transform_mode == ObjectTransformMode.ROTATE:
		action_name = "Rotate Map Object"
	elif _object_transform_mode == ObjectTransformMode.SCALE:
		action_name = "Scale Map Object"
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(_apply_object_transform_by_uuid.bind(uuid, after))
	_undo_redo.add_undo_method(_apply_object_transform_by_uuid.bind(uuid, _object_drag_before_transform))
	_undo_redo.commit_action(false)
	_hide_building_footprint_preview()
	var category = str(_selected_map_object.get_meta("map_editor_category", ""))
	if category in ["tree", "ore"]:
		_rebuild_resource_multimeshes_deferred()
	if _is_power_pole(_selected_map_object):
		_rebuild_power_wires()
	_refresh_transform_gizmo()

func _apply_object_transform_by_uuid(uuid: String, transform_value: Transform3D) -> void:
	var node = _find_editor_object_by_uuid(uuid)
	if node == null:
		return
	node.transform = transform_value
	if node == _selected_map_object:
		_refresh_selection_visual()
		_refresh_transform_gizmo()
		_sync_object_numeric_controls()
	var category = str(node.get_meta("map_editor_category", ""))
	if category in ["tree", "ore"]:
		_rebuild_resource_multimeshes_deferred()
	if _is_power_pole(node):
		_rebuild_power_wires()

func _delete_selected_object() -> void:
	if not is_instance_valid(_selected_map_object):
		return
	var record = _serialize_editor_object(_selected_map_object)
	var records: Array = [record]
	_remove_object_records(records)
	_clear_selected_map_object()
	_undo_redo.create_action("Delete Map Object")
	_undo_redo.add_do_method(_remove_object_records.bind(records))
	_undo_redo.add_undo_method(_restore_object_records.bind(records))
	_undo_redo.commit_action(false)
	_rebuild_resource_multimeshes_deferred()
	_rebuild_power_wires()


func _duplicate_selected_object() -> void:
	if not is_instance_valid(_selected_map_object):
		return
	var record = _serialize_editor_object(_selected_map_object)
	record["uuid"] = _new_editor_uuid(str(record.get("category", "object")))
	record["name"] = "%s_Copy" % str(record.get("name", "MapObject"))
	var transform_value = record.get("transform", Transform3D.IDENTITY) as Transform3D
	var local_aabb = _calculate_node_aabb_relative_to(_selected_map_object, _selected_map_object)
	var offset_distance = maxf(1.0, local_aabb.size.x + building_overlap_margin + 0.5)
	transform_value.origin += Vector3(offset_distance, 0.0, 0.0)
	record["transform"] = transform_value
	var records: Array = [record]
	_restore_object_records(records)
	var duplicated = _find_editor_object_by_uuid(str(record["uuid"]))
	if duplicated == null:
		return
	if str(record.get("category", "")) == "building":
		var validation = _validate_building_node(duplicated, duplicated)
		if not bool(validation.get("valid", false)):
			_remove_object_records(records)
			_set_status("Duplicate blocked: %s" % str(validation.get("reason", "overlap")))
			return
	_undo_redo.create_action("Duplicate Map Object")
	_undo_redo.add_do_method(_restore_object_records.bind(records))
	_undo_redo.add_undo_method(_remove_object_records.bind(records))
	_undo_redo.commit_action(false)
	_select_map_object(duplicated)
	_rebuild_resource_multimeshes_deferred()
	_rebuild_power_wires()

func _align_selected_object_to_ground() -> void:
	if not is_instance_valid(_selected_map_object):
		return
	var before = _selected_map_object.transform
	var category = str(_selected_map_object.get_meta("map_editor_category", "spawn"))
	var align_to_normal = category in ["tree", "ore"]
	var xz = Vector2(_selected_map_object.global_position.x, _selected_map_object.global_position.z)
	var yaw = _extract_world_yaw(_selected_map_object.global_basis)
	var ground_offset = float(_selected_map_object.get_meta("map_editor_ground_offset", placed_object_ground_offset))
	_place_map_object_at_terrain(_selected_map_object, xz, yaw, align_to_normal, ground_offset)
	var after = _selected_map_object.transform
	if before.is_equal_approx(after):
		return
	var uuid = str(_selected_map_object.get_meta("map_editor_uuid", ""))
	_undo_redo.create_action("Align Map Object To Ground")
	_undo_redo.add_do_method(_apply_object_transform_by_uuid.bind(uuid, after))
	_undo_redo.add_undo_method(_apply_object_transform_by_uuid.bind(uuid, before))
	_undo_redo.commit_action(false)
	_refresh_selection_visual()
	if _is_power_pole(_selected_map_object):
		_rebuild_power_wires()


func _extract_world_yaw(basis: Basis) -> float:
	var z_axis = basis.z
	z_axis.y = 0.0
	if z_axis.length_squared() <= 0.000001:
		return 0.0
	z_axis = z_axis.normalized()
	return atan2(z_axis.x, z_axis.z)


func _refresh_selection_visual() -> void:
	if _selection_visual_mesh == null or not is_instance_valid(_selected_map_object) or _tool_mode != ToolMode.OBJECT_EDIT:
		if _selection_visual != null:
			_selection_visual.visible = false
		return
	var local_aabb = _calculate_node_aabb_relative_to(_selected_map_object, _selected_map_object)
	if local_aabb.size.length_squared() <= 0.000001:
		local_aabb = AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)
	var corners: Array[Vector3] = []
	for x in [0, 1]:
		for y in [0, 1]:
			for z in [0, 1]:
				corners.append(local_aabb.position + Vector3(local_aabb.size.x * x, local_aabb.size.y * y, local_aabb.size.z * z))
	var edge_pairs = [
		[0, 1], [0, 2], [0, 4], [1, 3], [1, 5], [2, 3],
		[2, 6], [3, 7], [4, 5], [4, 6], [5, 7], [6, 7],
	]
	_selection_visual_mesh.clear_surfaces()
	_selection_visual_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for pair in edge_pairs:
		_selection_visual_mesh.surface_add_vertex(_selected_map_object.to_global(corners[int(pair[0])]))
		_selection_visual_mesh.surface_add_vertex(_selected_map_object.to_global(corners[int(pair[1])]))
	_selection_visual_mesh.surface_end()
	_selection_visual.global_transform = Transform3D.IDENTITY
	var material = _selection_visual.material_override as StandardMaterial3D
	if material != null:
		material.albedo_color = Color(0.1, 0.9, 1.0, 1.0) if _object_transform_valid else Color(1.0, 0.08, 0.04, 1.0)
	_selection_visual.visible = true

func _apply_numeric_object_transform() -> void:
	if not is_instance_valid(_selected_map_object):
		return
	for control in [
		_object_x_spin, _object_y_spin, _object_z_spin,
		_object_rot_x_spin, _object_rot_y_spin, _object_rot_z_spin,
		_object_scale_x_spin, _object_scale_y_spin, _object_scale_z_spin,
	]:
		if control == null:
			return
	var position = Vector3(_object_x_spin.value, _object_y_spin.value, _object_z_spin.value)
	if not _point_inside_map(Vector2(position.x, position.z), 0.0):
		_show_boundary_warning()
		return
	var rotation = Vector3(
		deg_to_rad(_object_rot_x_spin.value),
		deg_to_rad(_object_rot_y_spin.value),
		deg_to_rad(_object_rot_z_spin.value)
	)
	var scale_value = Vector3(
		clampf(_object_scale_x_spin.value, object_minimum_scale, object_maximum_scale),
		clampf(_object_scale_y_spin.value, object_minimum_scale, object_maximum_scale),
		clampf(_object_scale_z_spin.value, object_minimum_scale, object_maximum_scale)
	)
	var before = _selected_map_object.transform
	var global_before = _selected_map_object.global_transform
	_selected_map_object.global_transform = Transform3D(
		Basis.from_euler(rotation) * Basis.from_scale(scale_value),
		position
	)
	if str(_selected_map_object.get_meta("map_editor_category", "")) == "building":
		var validation = _validate_building_node(_selected_map_object, _selected_map_object)
		if not bool(validation.get("valid", false)):
			_selected_map_object.global_transform = global_before
			_set_status("Exact transform rejected: %s" % str(validation.get("reason", "overlap")))
			_sync_object_numeric_controls()
			return
	var after = _selected_map_object.transform
	if before.is_equal_approx(after):
		return
	var uuid = str(_selected_map_object.get_meta("map_editor_uuid", ""))
	_undo_redo.create_action("Set Exact Object Transform")
	_undo_redo.add_do_method(_apply_object_transform_by_uuid.bind(uuid, after))
	_undo_redo.add_undo_method(_apply_object_transform_by_uuid.bind(uuid, before))
	_undo_redo.commit_action(false)
	_refresh_selection_visual()
	_refresh_transform_gizmo()
	_sync_object_numeric_controls()
	var category = str(_selected_map_object.get_meta("map_editor_category", ""))
	if category in ["tree", "ore"]:
		_rebuild_resource_multimeshes_deferred()
	if _is_power_pole(_selected_map_object):
		_rebuild_power_wires()

func _apply_uniform_scale_from_inspector() -> void:
	if not is_instance_valid(_selected_map_object) or _object_uniform_scale_spin == null:
		return
	var value = clampf(_object_uniform_scale_spin.value, object_minimum_scale, object_maximum_scale)
	if _object_scale_x_spin != null:
		_object_scale_x_spin.value = value
	if _object_scale_y_spin != null:
		_object_scale_y_spin.value = value
	if _object_scale_z_spin != null:
		_object_scale_z_spin.value = value
	_apply_numeric_object_transform()

func _sync_object_numeric_controls() -> void:
	var has_selection = is_instance_valid(_selected_map_object)
	for spin in [
		_object_x_spin, _object_y_spin, _object_z_spin,
		_object_rot_x_spin, _object_rot_y_spin, _object_rot_z_spin,
		_object_scale_x_spin, _object_scale_y_spin, _object_scale_z_spin,
		_object_uniform_scale_spin,
	]:
		if spin != null:
			spin.editable = has_selection
	if not has_selection:
		return
	var position = _selected_map_object.global_position
	var rotation = _selected_map_object.global_basis.orthonormalized().get_euler()
	var scale_value = _selected_map_object.global_basis.get_scale()
	if _object_x_spin != null:
		_object_x_spin.value = position.x
	if _object_y_spin != null:
		_object_y_spin.value = position.y
	if _object_z_spin != null:
		_object_z_spin.value = position.z
	if _object_rot_x_spin != null:
		_object_rot_x_spin.value = rad_to_deg(rotation.x)
	if _object_rot_y_spin != null:
		_object_rot_y_spin.value = rad_to_deg(rotation.y)
	if _object_rot_z_spin != null:
		_object_rot_z_spin.value = rad_to_deg(rotation.z)
	if _object_scale_x_spin != null:
		_object_scale_x_spin.value = scale_value.x
	if _object_scale_y_spin != null:
		_object_scale_y_spin.value = scale_value.y
	if _object_scale_z_spin != null:
		_object_scale_z_spin.value = scale_value.z
	if _object_uniform_scale_spin != null:
		_object_uniform_scale_spin.value = (scale_value.x + scale_value.y + scale_value.z) / 3.0

func _update_object_edit_status() -> void:
	if _selection_status_label != null:
		var selected_name = _selected_map_object.name if is_instance_valid(_selected_map_object) else "None"
		var mode_name = "Move"
		if _object_transform_mode == ObjectTransformMode.ROTATE:
			mode_name = "Rotate"
		elif _object_transform_mode == ObjectTransformMode.SCALE:
			mode_name = "Scale"
		var space_name = "Local" if _gizmo_local_space else "World"
		_selection_status_label.text = "Selected: %s
Mode: %s | Axes: %s" % [selected_name, mode_name, space_name]
	if _object_delete_button != null:
		_object_delete_button.disabled = not is_instance_valid(_selected_map_object)
	if _object_duplicate_button != null:
		_object_duplicate_button.disabled = not is_instance_valid(_selected_map_object)

func create_road_from_points(points: PackedVector3Array, road_type: int = 1) -> Path3D:
	if _roads_root == null or points.size() < 2:
		return null
	var road = _create_road_node()
	if road == null:
		return null
	_set_property_if_present(road, "road_type", road_type)
	for point in points:
		var terrain_point = Vector3(point.x, get_terrain_height_world(Vector2(point.x, point.z)), point.z)
		road.curve.add_point(terrain_point)
	_smooth_road_curve_handles(road.curve)
	_rebuild_road_now(road)
	return road


# -----------------------------------------------------------------------------
# Save the generated map and authoritative editor data
# -----------------------------------------------------------------------------

func save_current_map() -> void:
	_last_save_succeeded = false
	if _map_root == null:
		_set_status("No map to save")
		return

	_end_stroke()
	_sync_package_fields_from_ui()
	var folder = _resolve_current_save_folder()
	var absolute_folder = ProjectSettings.globalize_path(folder)
	var directory_error = DirAccess.make_dir_recursive_absolute(absolute_folder)
	if directory_error != OK:
		_set_status("Could not create save directory (error %d)" % directory_error)
		return

	_update_map_metadata_before_save()
	_rebuild_power_wires()
	var map_validation_error := _get_playable_map_validation_error()
	if not map_validation_error.is_empty():
		_set_status(map_validation_error)
		return
	# An imported icon always wins.  Otherwise render a small local preview of
	# the map before writing the sidecar manifest; _save_map_icon() will then
	# persist the generated 128x128 image exactly like an imported one.
	if _map_icon_image == null or _map_icon_image.is_empty():
		await _capture_generated_map_icon()
	_save_editor_sidecar_data(folder)

	# The runtime map needs FarmWorldInitializer, but attaching it while editing
	# would trigger game-specific initialization. Attach only while packing.
	var previous_script = _map_root.get_script()
	var initializer_script = _load_resource_or_null(FARM_INITIALIZER_PATH) as Script
	if initializer_script != null:
		_map_root.set_script(initializer_script)
		_set_property_if_present(_map_root, "loading_map_name", _map_id)

	var previous_day_night_process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_day_night_system):
		previous_day_night_process_mode = _day_night_system.process_mode
		_day_night_system.process_mode = Node.PROCESS_MODE_INHERIT
	var previous_weather_process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_weather_system):
		previous_weather_process_mode = _weather_system.process_mode
		_weather_system.process_mode = Node.PROCESS_MODE_INHERIT

	var disabled_spawn_nodes: Array[Node] = []
	for child in _spawns_root.get_children():
		if child.process_mode == Node.PROCESS_MODE_DISABLED:
			disabled_spawn_nodes.append(child)
			child.process_mode = Node.PROCESS_MODE_INHERIT

	_assign_pack_owners(_map_root)
	var packed = PackedScene.new()
	var pack_error = packed.pack(_map_root)
	var scene_path = "%s/%s.tscn" % [folder, _map_id]
	var save_error = ERR_CANT_CREATE
	if pack_error == OK:
		save_error = ResourceSaver.save(packed, scene_path)

	for spawn_node in disabled_spawn_nodes:
		if is_instance_valid(spawn_node):
			spawn_node.process_mode = Node.PROCESS_MODE_DISABLED
	if is_instance_valid(_day_night_system):
		_day_night_system.process_mode = previous_day_night_process_mode
	if is_instance_valid(_weather_system):
		_weather_system.process_mode = previous_weather_process_mode
	_map_root.set_script(previous_script)

	if pack_error != OK:
		_set_status("Could not pack map scene (error %d)" % pack_error)
		return
	if save_error != OK:
		_set_status("Could not save map scene (error %d)" % save_error)
		return
	_current_map_folder = folder
	_saved_undo_version = _undo_redo.get_version()
	_last_save_succeeded = true
	_set_status("Saved: %s" % scene_path)


func _capture_generated_map_icon() -> void:
	if _map_root == null or (_map_icon_image != null and not _map_icon_image.is_empty()):
		return

	# Render the actual map root in an isolated viewport.  The preview camera is
	# never made current in the editor viewport, so the user's editing camera
	# and its position remain untouched.
	var preview_viewport := SubViewport.new()
	preview_viewport.name = "GeneratedMapIconViewport"
	preview_viewport.size = Vector2i(MAP_ICON_SIZE * 2, MAP_ICON_SIZE * 2)
	preview_viewport.own_world_3d = true
	preview_viewport.transparent_bg = false
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(preview_viewport)

	var map_parent := _map_root.get_parent()
	if map_parent == null:
		preview_viewport.queue_free()
		return
	var map_index := _map_root.get_index()
	var map_transform := _map_root.transform
	var map_process_mode := _map_root.process_mode
	map_parent.remove_child(_map_root)
	preview_viewport.add_child(_map_root)
	_map_root.process_mode = Node.PROCESS_MODE_DISABLED

	var preview_camera := Camera3D.new()
	preview_camera.name = "GeneratedMapIconCamera"
	preview_camera.position = Vector3(0.0, 0.0, 10.0)
	preview_camera.rotation = Vector3(
		deg_to_rad(-45.0),
		_rng.randf_range(-PI, PI),
		0.0
	)
	preview_camera.fov = 70.0
	preview_camera.near = 0.05
	preview_camera.far = maxf(500.0, _map_size.length() * 2.0)
	preview_viewport.add_child(preview_camera)
	preview_camera.current = false
	# The requested map camera remains non-current.  A short-lived copy is used
	# only by the isolated viewport because Godot renders a viewport through its
	# current camera; both cameras have exactly the same transform and lens.
	var capture_camera := preview_camera.duplicate() as Camera3D
	capture_camera.name = "GeneratedMapIconCaptureCamera"
	capture_camera.current = true
	preview_viewport.add_child(capture_camera)
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var captured := preview_viewport.get_texture().get_image()

	capture_camera.current = false
	preview_viewport.remove_child(capture_camera)
	capture_camera.free()
	preview_viewport.remove_child(preview_camera)
	preview_camera.free()
	preview_viewport.remove_child(_map_root)
	map_parent.add_child(_map_root)
	map_parent.move_child(_map_root, mini(map_index, map_parent.get_child_count() - 1))
	_map_root.transform = map_transform
	_map_root.process_mode = map_process_mode
	preview_viewport.queue_free()

	if captured == null or captured.is_empty():
		_set_status("Map saved without an icon: preview capture failed")
		return
	_map_icon_image = _make_letterboxed_icon(captured)
	_map_icon_texture = ImageTexture.create_from_image(_map_icon_image)
	_map_icon_source_path = "generated://map_icon.png"
	if _icon_preview != null:
		_icon_preview.texture = _map_icon_texture
	if _icon_status_label != null:
		_icon_status_label.text = "Generated preview -> 128x128"


func _update_map_metadata_before_save() -> void:
	_map_root.set_meta("farmwar_map_format_version", 5)
	_map_root.set_meta("farmwar_map_id", _map_id)
	_map_root.set_meta("farmwar_display_name", _display_name)
	_map_root.set_meta("farmwar_map_version", _map_version)
	_map_root.set_meta("farmwar_map_name", _map_id)
	_map_root.set_meta("farmwar_map_size", _map_size)
	_map_root.set_meta("farmwar_terrain_winding_version", 2)
	_map_root.set_meta("terrain_origin", _terrain_origin)
	_map_root.set_meta("terrain_vertex_spacing", vertex_spacing)
	_map_root.set_meta("terrain_sample_width", _sample_width)
	_map_root.set_meta("terrain_sample_depth", _sample_depth)
	_map_root.set_meta("terrain_height_samples", _height_samples)
	_map_root.set_meta("surface_mask_image", _surface_mask_image)
	_map_root.set_meta("surface_palette_entries", _surface_entries.duplicate(true))
	_map_root.set_meta("surface_default_id", _get_default_surface_id())
	_map_root.set_meta("manual_grass", _manual_grass)
	_map_root.set_meta("farmwar_ai_configuration", _ai_configurations.duplicate(true))
	_map_root.set_meta("integrated_systems", [
		"explicit_ground_static_body",
		"dynamic_height_terrain",
		"terrain_foundation_and_skirt",
		"surface_mask",
		"manual_grass_multimesh",
		"continuous_curve_roads",
		"water_bodies",
		"day_night_gameplay_only",
		"weather_system",
		"cloud_system",
		"size_aware_far_scenery",
		"tree_resource_multimesh",
		"giant_crop_spawns",
		"wild_animal_spawns",
		"independent_red_blue_team_spawns",
		"building_content_browser",
		"building_placement",
		"object_transform_editor",
		"farmland_field_generator",
		"neutral_crop_generator",
	])


func _get_playable_map_validation_error() -> String:
	if _spawns_root == null:
		return "Cannot save playable map: missing SpawnPoints root."
	var has_red := false
	var has_blue := false
	for child in _spawns_root.get_children():
		if not child is TeamSpawnPoint:
			continue
		var point := child as TeamSpawnPoint
		has_red = has_red or point.team == "red"
		has_blue = has_blue or point.team == "blue"
	if not has_red or not has_blue:
		return "Cannot save playable map: place at least one red and one blue Player Spawn Point."
	return ""


func _save_editor_sidecar_data(folder: String) -> void:
	var height_file = FileAccess.open("%s/heightmap.bin" % folder, FileAccess.WRITE)
	if height_file != null:
		height_file.store_32(_sample_width)
		height_file.store_32(_sample_depth)
		height_file.store_float(vertex_spacing)
		height_file.store_buffer(_height_samples.to_byte_array())
		height_file.close()

	if _surface_mask_image != null:
		_surface_mask_image.save_png("%s/surface_mask.png" % folder)

	var palette_image = _build_surface_palette_image()
	palette_image.save_png("%s/%s" % [folder, SURFACE_PALETTE_FILE_NAME])
	if _surface_palette_resource != null:
		ResourceSaver.save(
			_surface_palette_resource,
			"%s/surface_palette.tres" % folder
		)

	var grass_file = FileAccess.open("%s/manual_grass.dat" % folder, FileAccess.WRITE)
	if grass_file != null:
		grass_file.store_var(_manual_grass, true)
		grass_file.close()

	_save_editor_objects_sidecar(folder)
	_save_roads_sidecar(folder)
	_save_water_bodies_sidecar(folder)

	var icon_saved = _save_map_icon(folder)
	var template_name = (
		"redpine_county"
		if _template_mode == TemplateMode.REDPINE_COUNTY
		else "creston_town"
	)
	var manifest = {
		"format_version": 5,
		"map_id": _map_id,
		"display_name": _display_name,
		"icon": MAP_ICON_FILE_NAME if icon_saved else "",
		"version": _map_version,
		"size": {
			"width": int(_map_size.x),
			"depth": int(_map_size.y),
		},
		"template": template_name,
		"scene": "%s.tscn" % _map_id,
		"terrain": {
			"vertex_spacing": vertex_spacing,
			"samples": [_sample_width, _sample_depth],
			"heightmap": "heightmap.bin",
			"surface_mask": "surface_mask.png",
			"surface_palette": SURFACE_PALETTE_FILE_NAME,
			"surface_palette_resource": "surface_palette.tres",
			"default_surface_id": _get_default_surface_id(),
			"surface_mask_resolution": [
				_surface_mask_image.get_width(),
				_surface_mask_image.get_height(),
			],
		},
		"surface_colors": _surface_entries_for_json(),
		"content": {
			"manual_grass": "manual_grass.dat",
			"editor_objects": EDITOR_OBJECTS_FILE_NAME,
			"roads": ROADS_FILE_NAME,
			"water_bodies": WATER_BODIES_FILE_NAME,
			"road_count": _roads_root.get_child_count(),
			"water_count": _water_root.get_child_count(),
			"tree_count": _trees_root.get_child_count(),
			"ore_count": _ores_root.get_child_count(),
			"spawn_count": _spawns_root.get_child_count(),
			"building_count": _buildings_root.get_child_count(),
			"farmland_count": _farmlands_root.get_child_count(),
			"neutral_crop_generator_count": _count_neutral_crop_generators(),
			"ai_configuration": _ai_configurations.duplicate(true),
			"ai_count": _ai_configurations.size(),
		},
		"features": {
			"building_placement_enabled": true,
			"object_transform_enabled": true,
			"xyz_gizmo_enabled": true,
			"building_overlap_validation_enabled": true,
			"farmland_editor_enabled": true,
			"neutral_crop_generators_enabled": true,
			"day_night_enabled_in_gameplay": is_instance_valid(_day_night_system),
			"size_aware_far_scenery": true,
			"water_bodies_enabled": true,
		},
	}

	var manifest_file = FileAccess.open("%s/map.json" % folder, FileAccess.WRITE)
	if manifest_file != null:
		manifest_file.store_string(JSON.stringify(manifest, "  "))
		manifest_file.close()


func _surface_entries_for_json() -> Array:
	var result: Array = []
	for entry_value in _surface_entries:
		var entry = entry_value as Dictionary
		var color = entry.get("color", Color.WHITE) as Color
		result.append({
			"id": int(entry.get("id", 0)),
			"name": str(entry.get("label", "Surface")),
			"color": color.to_html(false),
			"roughness": clampf(float(entry.get("roughness", 0.9)), 0.0, 1.0),
		})
	return result


func _assign_pack_owners(root: Node) -> void:
	for child in root.get_children():
		if child.has_meta(EDITOR_MARKER_META):
			child.owner = null
			continue
		child.owner = _map_root

		# External scene instances retain their own internal ownership. Far
		# scenery and resource MultiMeshes are regenerated by their scripts and
		# should not be embedded as duplicated generated geometry.
		if not child.scene_file_path.is_empty():
			continue
		if child == _far_scenery_ring or child == _tree_forest_manager:
			continue
		_assign_pack_owners(child)



# -----------------------------------------------------------------------------
# Map package workflow: New / Open / Save / Save As
# -----------------------------------------------------------------------------

func _build_map_file_dialogs() -> void:
	_open_map_file_dialog = FileDialog.new()
	_open_map_file_dialog.name = "OpenMapPackageDialog"
	_open_map_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_open_map_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_open_map_file_dialog.use_native_dialog = true
	_open_map_file_dialog.title = "Open FarmWar Map Package"
	_open_map_file_dialog.filters = PackedStringArray(["map.json ; FarmWar Map Manifest"])
	_open_map_file_dialog.file_selected.connect(_on_open_map_manifest_selected)
	_ui_layer.add_child(_open_map_file_dialog)

	_save_as_directory_dialog = FileDialog.new()
	_save_as_directory_dialog.name = "SaveMapAsDialog"
	_save_as_directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_save_as_directory_dialog.access = FileDialog.ACCESS_USERDATA
	_save_as_directory_dialog.use_native_dialog = true
	_save_as_directory_dialog.title = "Choose Parent Folder for Map Package"
	_save_as_directory_dialog.dir_selected.connect(_on_save_as_parent_selected)
	_ui_layer.add_child(_save_as_directory_dialog)

	_export_directory_dialog = FileDialog.new()
	_export_directory_dialog.name = "ExportMapDialog"
	_export_directory_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_export_directory_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_export_directory_dialog.use_native_dialog = true
	_export_directory_dialog.title = "Choose Export Parent Folder"
	_export_directory_dialog.dir_selected.connect(_on_export_parent_selected)
	_ui_layer.add_child(_export_directory_dialog)

	_discard_changes_dialog = ConfirmationDialog.new()
	_discard_changes_dialog.name = "DiscardChangesDialog"
	_discard_changes_dialog.title = "Unsaved Map Changes"
	_discard_changes_dialog.dialog_text = "The current map has unsaved changes. Discard them and continue?"
	_discard_changes_dialog.ok_button_text = "Discard"
	_discard_changes_dialog.confirmed.connect(_on_discard_changes_confirmed)
	_ui_layer.add_child(_discard_changes_dialog)


func _request_new_map() -> void:
	_confirm_discard_or_run(Callable(self, "_create_map_from_ui"))


func _request_open_map() -> void:
	_confirm_discard_or_run(Callable(self, "_show_open_map_dialog"))


func _request_export_map() -> void:
	if _map_root == null:
		_set_status("No map to export")
		return
	if _export_directory_dialog == null:
		return
	var portable_root := GameMapRegistry.get_portable_maps_root()
	if not portable_root.is_empty():
		var portable_absolute := _globalize_map_path(portable_root)
		if not DirAccess.dir_exists_absolute(portable_absolute):
			DirAccess.make_dir_recursive_absolute(portable_absolute)
		if not DirAccess.dir_exists_absolute(portable_absolute):
			portable_root = portable_root.get_base_dir()
	_export_directory_dialog.current_dir = portable_root if not portable_root.is_empty() else _globalize_map_path(map_save_root)
	_export_directory_dialog.popup_centered_ratio(0.8)


func _request_return_to_main_menu() -> void:
	_confirm_discard_or_run(Callable(self, "_return_to_main_menu"))


func _return_to_main_menu() -> void:
	var cooperative_session := get_node_or_null("/root/CooperativeSession")
	if cooperative_session != null and cooperative_session.has_method("is_active") and cooperative_session.call("is_active"):
		cooperative_session.call("stop_session")
	var authority := get_node_or_null("/root/GameAuthority")
	if authority != null and authority.has_method("stop_authority"):
		authority.call("stop_authority")
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().change_scene_to_file("res://ui/MainMenuRoot.tscn")


func _confirm_discard_or_run(action: Callable) -> void:
	if _map_root != null and has_unsaved_changes():
		_pending_destructive_action = action
		_discard_changes_dialog.popup_centered()
		return
	action.call()


func _on_discard_changes_confirmed() -> void:
	if _pending_destructive_action.is_valid():
		var action = _pending_destructive_action
		_pending_destructive_action = Callable()
		action.call()


func _show_open_map_dialog() -> void:
	if _open_map_file_dialog == null:
		return
	_open_map_file_dialog.current_dir = _globalize_map_path(map_save_root)
	_open_map_file_dialog.popup_centered_ratio(0.8)


func _open_save_as_dialog() -> void:
	if _map_root == null:
		_set_status("No map to save")
		return
	if _save_as_directory_dialog == null:
		return
	_save_as_directory_dialog.current_dir = map_save_root
	_save_as_directory_dialog.popup_centered_ratio(0.8)


func _on_save_as_parent_selected(parent_folder: String) -> void:
	_sync_package_fields_from_ui()
	var normalized_parent = _normalize_user_path(parent_folder)
	_current_map_folder = normalized_parent.trim_suffix("/").path_join(_map_id)
	save_current_map()


func _on_export_parent_selected(parent_folder: String) -> void:
	if _map_root == null:
		_set_status("No map to export")
		return
	_sync_package_fields_from_ui()
	await save_current_map()
	if not _last_save_succeeded:
		_set_status("Export cancelled: save the map successfully first")
		return
	var source_folder := _resolve_current_save_folder().trim_suffix("/")
	var target_folder := parent_folder.trim_suffix("/").path_join(_map_id)
	var source_absolute := _globalize_map_path(source_folder)
	var target_absolute := _globalize_map_path(target_folder)
	if source_absolute == target_absolute:
		_set_status("Export skipped: destination is the current map package")
		return
	if not _copy_map_package(source_absolute, target_absolute):
		_set_status("Map export failed")
		return
	_set_status("Exported map package: %s" % target_folder)


func _globalize_map_path(path: String) -> String:
	if path.begins_with("file://"):
		return path.trim_prefix("file://")
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


func _copy_map_package(source_folder: String, target_folder: String) -> bool:
	if not DirAccess.dir_exists_absolute(source_folder):
		return false
	if DirAccess.make_dir_recursive_absolute(target_folder) != OK:
		return false
	var source_directory := DirAccess.open(source_folder)
	if source_directory == null:
		return false
	source_directory.list_dir_begin()
	var entry := source_directory.get_next()
	while not entry.is_empty():
		if not entry.begins_with("."):
			var source_path := source_folder.path_join(entry)
			var target_path := target_folder.path_join(entry)
			if source_directory.current_is_dir():
				if not _copy_map_package(source_path, target_path):
					source_directory.list_dir_end()
					return false
			else:
				if DirAccess.copy_absolute(source_path, target_path) != OK:
					source_directory.list_dir_end()
					return false
		entry = source_directory.get_next()
	source_directory.list_dir_end()
	return true


func _on_open_map_manifest_selected(manifest_path: String) -> void:
	open_map_package(_normalize_user_path(manifest_path))


func _normalize_user_path(path: String) -> String:
	var localized = ProjectSettings.localize_path(path)
	if localized.begins_with("user://"):
		return localized
	return path


func _resolve_current_save_folder() -> String:
	if not _current_map_folder.is_empty():
		return _current_map_folder.trim_suffix("/")
	return "%s/%s" % [map_save_root.trim_suffix("/"), _map_id]


func open_map_package(manifest_path: String) -> void:
	if not FileAccess.file_exists(manifest_path):
		_set_status("Map manifest does not exist: %s" % manifest_path)
		return
	var manifest_text = FileAccess.get_file_as_string(manifest_path)
	var parsed = JSON.parse_string(manifest_text)
	if not parsed is Dictionary:
		_set_status("Invalid map.json")
		return
	var manifest = parsed as Dictionary
	var configured_ai_value: Variant = manifest.get(
		"ai_configuration",
		(manifest.get("content", {}) as Dictionary).get("ai_configuration", [])
	)
	var size_data = manifest.get("size", {}) as Dictionary
	var map_size_value = Vector2i(
		maxi(32, int(size_data.get("width", 256))),
		maxi(32, int(size_data.get("depth", 256)))
	)
	var template_value = TemplateMode.REDPINE_COUNTY if str(manifest.get("template", "creston_town")) == "redpine_county" else TemplateMode.CRESTON_TOWN
	var display_name_value = str(manifest.get("display_name", "Opened Farm Map"))
	var map_id_value = str(manifest.get("map_id", display_name_value))
	var version_value = str(manifest.get("version", default_map_version))
	var terrain_data = manifest.get("terrain", {}) as Dictionary
	vertex_spacing = maxf(0.25, float(terrain_data.get("vertex_spacing", vertex_spacing)))

	create_new_map(display_name_value, map_size_value, template_value, map_id_value, version_value)
	_ai_configurations = configured_ai_value.duplicate(true) if configured_ai_value is Array else []
	_selected_ai_index = 0 if not _ai_configurations.is_empty() else -1
	if _map_root != null:
		_map_root.set_meta("farmwar_ai_configuration", _ai_configurations.duplicate(true))
	_current_map_folder = manifest_path.get_base_dir()
	_load_surface_entries_from_manifest(manifest)
	_load_heightmap_sidecar(_current_map_folder.path_join(str(terrain_data.get("heightmap", "heightmap.bin"))))
	_load_surface_mask_sidecar(_current_map_folder.path_join(str(terrain_data.get("surface_mask", "surface_mask.png"))))
	_load_manual_grass_sidecar(_current_map_folder.path_join(str((manifest.get("content", {}) as Dictionary).get("manual_grass", "manual_grass.dat"))))
	_load_editor_objects_sidecar(_current_map_folder.path_join(str((manifest.get("content", {}) as Dictionary).get("editor_objects", EDITOR_OBJECTS_FILE_NAME))))
	_recalculate_loaded_object_counters()
	_load_roads_sidecar(_current_map_folder.path_join(str((manifest.get("content", {}) as Dictionary).get("roads", ROADS_FILE_NAME))))
	_load_water_bodies_sidecar(_current_map_folder.path_join(str((manifest.get("content", {}) as Dictionary).get("water_bodies", WATER_BODIES_FILE_NAME))))
	_load_map_icon_from_package(_current_map_folder, str(manifest.get("icon", "")))
	_rebuild_loaded_map_visuals()
	_update_map_ui_from_loaded_manifest()
	_reset_undo_history()
	_saved_undo_version = _undo_redo.get_version()
	_set_status("Opened: %s" % manifest_path)


func _load_surface_entries_from_manifest(manifest: Dictionary) -> void:
	var colors = manifest.get("surface_colors", []) as Array
	if colors.is_empty():
		return
	var entries: Array = []
	for value in colors:
		var item = value as Dictionary
		entries.append({
			"id": clampi(int(item.get("id", entries.size())), 0, 255),
			"label": str(item.get("name", "Surface")),
			"color": Color.from_string(str(item.get("color", "ffffff")), Color.WHITE),
			"roughness": clampf(float(item.get("roughness", 0.9)), 0.0, 1.0),
		})
	_surface_entries = entries
	_selected_surface_id = _get_default_surface_id()
	_sync_surface_palette_resource_from_entries()
	_rebuild_surface_palette_lookup()


func _load_heightmap_sidecar(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var width = int(file.get_32())
	var depth = int(file.get_32())
	var spacing = file.get_float()
	var remaining = file.get_length() - file.get_position()
	var values = file.get_buffer(remaining).to_float32_array()
	file.close()
	if width != _sample_width or depth != _sample_depth or values.size() != width * depth:
		push_warning("FarmWar map editor: heightmap dimensions do not match map.json; keeping generated terrain.")
		return
	vertex_spacing = spacing
	_height_samples = values


func _load_surface_mask_sidecar(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var image = Image.load_from_file(path)
	if image == null or image.is_empty():
		return
	image.convert(Image.FORMAT_RGBA8)
	_surface_mask_image = image
	_surface_mask_texture = ImageTexture.create_from_image(_surface_mask_image)
	if _terrain_material != null:
		_terrain_material.set_shader_parameter("surface_mask", _surface_mask_texture)


func _load_manual_grass_sidecar(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var loaded = file.get_var(true)
	file.close()
	if loaded is Dictionary:
		_manual_grass = loaded as Dictionary
	_ensure_manual_grass_species()


func _load_map_icon_from_package(folder: String, icon_name: String) -> void:
	_clear_map_icon()
	if icon_name.is_empty():
		if _icon_preview != null:
			_icon_preview.texture = null
		if _icon_status_label != null:
			_icon_status_label.text = "No icon in package"
		return
	var icon_path = folder.path_join(icon_name)
	if not FileAccess.file_exists(icon_path):
		return
	var image = Image.load_from_file(icon_path)
	if image == null or image.is_empty():
		return
	_map_icon_image = _make_letterboxed_icon(image)
	_map_icon_texture = ImageTexture.create_from_image(_map_icon_image)
	_map_icon_source_path = icon_path
	if _icon_preview != null:
		_icon_preview.texture = _map_icon_texture
	if _icon_status_label != null:
		_icon_status_label.text = icon_name


func _clear_map_icon() -> void:
	_map_icon_image = null
	_map_icon_texture = null
	_map_icon_source_path = ""
	if _icon_preview != null:
		_icon_preview.texture = null
	if _icon_status_label != null:
		_icon_status_label.text = "No icon selected"


func _recalculate_loaded_object_counters() -> void:
	_next_object_id = 1
	_next_spawn_id = 1
	for root in [_trees_root, _ores_root, _buildings_root, _farmlands_root]:
		if root != null:
			_next_object_id += root.get_child_count()
	if _spawns_root != null:
		_next_spawn_id += _spawns_root.get_child_count()


func _update_map_ui_from_loaded_manifest() -> void:
	_map_name_edit.text = _display_name
	_map_id_edit.text = _map_id
	_map_version_edit.text = _map_version
	_map_width_spin.value = _map_size.x
	_map_depth_spin.value = _map_size.y
	for index in range(_template_option.item_count):
		if _template_option.get_item_id(index) == _template_mode:
			_template_option.select(index)
			break
	_refresh_bottom_dock()


func _rebuild_loaded_map_visuals() -> void:
	_rebuild_persistent_height_contours()
	for coordinate_value in _terrain_chunks.keys():
		_rebuild_terrain_chunk(coordinate_value as Vector2i, true)
	_rebuild_terrain_skirt()
	if _ground_safety_mesh != null:
		_apply_foundation_color()
	for generated in _grass_generated_nodes.values():
		if is_instance_valid(generated):
			generated.queue_free()
	_grass_generated_nodes.clear()
	for species_value in _manual_grass.keys():
		var species = str(species_value)
		var chunks = _manual_grass.get(species, {}) as Dictionary
		for key_value in chunks.keys():
			_rebuild_manual_grass_chunk(species, str(key_value))
	_rebuild_resource_multimeshes_deferred()
	_refresh_all_farmland_previews()
	_rebuild_all_water_bodies()
	_rebuild_power_wires()
	_configure_integrated_systems()
	_configure_camera_for_map_and_far_scenery()
	_clear_selected_map_object()
	_clear_building_preview()
	_rebuild_road_edit_visuals()


func _apply_foundation_color() -> void:
	var base_color = Color("50733b")
	if not _surface_entries.is_empty():
		base_color = (_surface_entries[0] as Dictionary).get("color", base_color) as Color
	for mesh_instance in [_ground_safety_mesh, _terrain_skirt_mesh]:
		if mesh_instance == null:
			continue
		var material = mesh_instance.material_override as StandardMaterial3D
		if material != null:
			material.albedo_color = base_color.darkened(0.2)


func _save_editor_objects_sidecar(folder: String) -> void:
	var records: Array = []
	for root in [_trees_root, _ores_root, _spawns_root, _buildings_root, _farmlands_root]:
		if root == null:
			continue
		for child in root.get_children():
			if child is Node3D:
				records.append(_serialize_editor_object(child as Node3D))
	var file = FileAccess.open(folder.path_join(EDITOR_OBJECTS_FILE_NAME), FileAccess.WRITE)
	if file != null:
		file.store_var(records, true)
		file.close()


func _load_editor_objects_sidecar(path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	for root in [_trees_root, _ores_root, _spawns_root, _buildings_root, _farmlands_root]:
		for child in root.get_children():
			child.queue_free()
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var loaded = file.get_var(true)
	file.close()
	if loaded is Array:
		_restore_object_records(loaded as Array)


func _save_water_bodies_sidecar(folder: String) -> void:
	var records: Array = []
	if _water_root != null:
		for child in _water_root.get_children():
			var water := child as WaterBody3D
			if water != null:
				records.append(_serialize_water(water))
	var file := FileAccess.open(folder.path_join(WATER_BODIES_FILE_NAME), FileAccess.WRITE)
	if file != null:
		file.store_var(records, true)
		file.close()


func _load_water_bodies_sidecar(path: String) -> void:
	if _water_root == null:
		return
	for child in _water_root.get_children():
		child.queue_free()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var loaded = file.get_var(true)
	file.close()
	if loaded is Array:
		_restore_water_records(loaded as Array)


# -----------------------------------------------------------------------------
# Continuous road visual editor
# -----------------------------------------------------------------------------

func _ensure_road_edit_visuals() -> void:
	if is_instance_valid(_road_edit_visual_root):
		return
	_road_edit_visual_root = Node3D.new()
	_road_edit_visual_root.name = "RoadEditVisuals"
	add_child(_road_edit_visual_root)

	_road_marker_root = Node3D.new()
	_road_marker_root.name = "ControlPoints"
	_road_edit_visual_root.add_child(_road_marker_root)

	_road_centerline_mesh = ImmediateMesh.new()
	_road_centerline = MeshInstance3D.new()
	_road_centerline.name = "Centerline"
	_road_centerline.mesh = _road_centerline_mesh
	_road_centerline.material_override = _make_unshaded_material(Color(1.0, 0.82, 0.1, 1.0))
	_road_edit_visual_root.add_child(_road_centerline)

	_road_preview_mesh = ImmediateMesh.new()
	_road_preview_line = MeshInstance3D.new()
	_road_preview_line.name = "PreviewLine"
	_road_preview_line.mesh = _road_preview_mesh
	_road_preview_line.material_override = _make_unshaded_material(Color(0.1, 0.9, 1.0, 1.0))
	_road_edit_visual_root.add_child(_road_preview_line)


func _make_unshaded_material(color: Color) -> StandardMaterial3D:
	var material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.no_depth_test = true
	return material


func _set_road_edit_visuals_visible(value: bool) -> void:
	_ensure_road_edit_visuals()
	_road_edit_visual_root.visible = value
	if value:
		_rebuild_road_edit_visuals()


func _ensure_water_edit_visuals() -> void:
	if is_instance_valid(_water_preview_root):
		return
	_water_preview_root = Node3D.new()
	_water_preview_root.name = "WaterEditVisuals"
	_water_preview_root.set_meta(EDITOR_MARKER_META, true)
	add_child(_water_preview_root)
	_water_marker_root = Node3D.new()
	_water_marker_root.name = "ControlPoints"
	_water_preview_root.add_child(_water_marker_root)
	_water_preview_mesh = ImmediateMesh.new()
	_water_preview_line = MeshInstance3D.new()
	_water_preview_line.name = "PreviewLine"
	_water_preview_line.mesh = _water_preview_mesh
	_water_preview_line.material_override = _make_unshaded_material(Color(0.1, 0.85, 1.0, 1.0))
	_water_preview_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_water_preview_root.add_child(_water_preview_line)


func _set_water_edit_visuals_visible(value: bool) -> void:
	_ensure_water_edit_visuals()
	_water_preview_root.visible = value
	if value:
		_rebuild_water_edit_visuals()


func _rebuild_water_edit_visuals() -> void:
	_ensure_water_edit_visuals()
	for child in _water_marker_root.get_children():
		_water_marker_root.remove_child(child)
		child.queue_free()
	_water_preview_mesh.clear_surfaces()
	if not _water_preview_root.visible:
		return
	if _water_points.size() < 1:
		return
	for index in range(_water_points.size()):
		var marker := MeshInstance3D.new()
		marker.name = "WaterPoint_%02d" % index
		var sphere := SphereMesh.new()
		sphere.radius = 0.45
		sphere.height = 0.9
		marker.mesh = sphere
		marker.material_override = _make_unshaded_material(Color(0.1, 0.85, 1.0, 1.0))
		_water_marker_root.add_child(marker)
		var point := _water_points[index]
		marker.position = Vector3(point.x, _water_level + 0.18, point.y)

	# A line strip needs at least two vertices. During the first click there is
	# only one control point, so leave the ImmediateMesh empty until the next.
	if _water_points.size() >= 2:
		_water_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for point in _water_points:
			_water_preview_mesh.surface_add_vertex(Vector3(point.x, _water_level + 0.2, point.y))
		if _water_body_type == WaterBody3D.BodyType.LAKE and _water_points.size() >= 3:
			_water_preview_mesh.surface_add_vertex(Vector3(_water_points[0].x, _water_level + 0.2, _water_points[0].y))
		_water_preview_mesh.surface_end()


func _update_water_preview(cursor: Vector3) -> void:
	_ensure_water_edit_visuals()
	if not _water_preview_root.visible:
		return
	_rebuild_water_edit_visuals()
	if not _water_drawing_active or _water_points.is_empty():
		return
	_water_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var last := _water_points[_water_points.size() - 1]
	_water_preview_mesh.surface_add_vertex(Vector3(last.x, _water_level + 0.2, last.y))
	_water_preview_mesh.surface_add_vertex(Vector3(cursor.x, _water_level + 0.2, cursor.z))
	_water_preview_mesh.surface_end()


func _update_water_preview_from_latest_hit() -> void:
	if not _latest_hit.is_empty():
		_update_water_preview(_latest_hit.get("position", Vector3.ZERO) as Vector3)


func _begin_new_lake() -> void:
	_begin_new_water(WaterBody3D.BodyType.LAKE)


func _begin_new_river() -> void:
	_begin_new_water(WaterBody3D.BodyType.RIVER)


func _begin_new_water(type: int) -> void:
	if _water_root == null:
		return
	_finish_active_water()
	var packed := _load_resource_or_null(WATER_BODY_PATH) as PackedScene
	if packed == null:
		_set_status("Missing WaterBody3D scene: %s" % WATER_BODY_PATH)
		return
	var instance := packed.instantiate() as WaterBody3D
	if instance == null:
		_set_status("WaterBody3D root is invalid")
		return
	_water_body_type = type
	instance.name = ("Lake" if type == WaterBody3D.BodyType.LAKE else "River") + "_%03d" % (_water_root.get_child_count() + 1)
	instance.set_meta("map_editor_water_uuid", _new_editor_uuid("water"))
	instance.set_meta("map_editor_water_body", true)
	instance.position.y = 0.0
	instance.body_type = type
	instance.water_level = _water_level
	instance.water_depth = _water_depth
	instance.river_width = _water_width
	instance.water_collision_layer = WATER_COLLISION_LAYER
	instance.water_collision_mask = WATER_COLLISION_MASK
	_water_root.add_child(instance)
	_selected_water = instance
	_water_points = PackedVector2Array()
	_water_drawing_active = true
	_set_water_edit_visuals_visible(true)
	_refresh_water_list_option()
	_update_water_control_states()
	_set_status("Water drawing: click %s points, then press Enter" % ("3+ lake boundary" if type == WaterBody3D.BodyType.LAKE else "2+ river centerline"))


func _handle_water_left_press() -> void:
	if _latest_hit.is_empty():
		return
	var hit := _latest_hit.get("position", Vector3.ZERO) as Vector3
	if not _water_drawing_active:
		_begin_new_water(_water_body_type)
	if not _water_drawing_active:
		return
	if _water_points.is_empty():
		_water_level = hit.y
		if _water_level_spin != null:
			_water_level_spin.value = _water_level
	_water_points.append(Vector2(hit.x, hit.z))
	if _selected_water != null:
		if _water_body_type == WaterBody3D.BodyType.LAKE:
			_selected_water.polygon_points = _water_points
		else:
			_selected_water.centerline_points = _water_points
		_selected_water.water_level = _water_level
		_selected_water.rebuild_water_body()
	_rebuild_water_edit_visuals()
	_set_status("Water points: %d" % _water_points.size())


func _finish_active_water() -> void:
	if not _water_drawing_active:
		return
	var minimum_points := 3 if _water_body_type == WaterBody3D.BodyType.LAKE else 2
	if _selected_water == null or _water_points.size() < minimum_points:
		_cancel_active_water()
		_set_status("Water cancelled: at least %d points are required" % minimum_points)
		return
	_selected_water.body_type = _water_body_type
	if _water_body_type == WaterBody3D.BodyType.LAKE:
		_selected_water.polygon_points = _water_points
		_selected_water.centerline_points = PackedVector2Array()
	else:
		_selected_water.centerline_points = _water_points
		_selected_water.polygon_points = PackedVector2Array()
	_selected_water.water_level = _water_level
	_selected_water.water_depth = _water_depth
	_selected_water.river_width = _water_width
	_selected_water.water_collision_layer = WATER_COLLISION_LAYER
	_selected_water.water_collision_mask = WATER_COLLISION_MASK
	_selected_water.rebuild_water_body()
	_water_drawing_active = false
	var record := _serialize_water(_selected_water)
	_undo_redo.create_action("Create Water Body")
	_undo_redo.add_do_method(_restore_water_records.bind([record]))
	_undo_redo.add_undo_method(_remove_water_records.bind([record]))
	_undo_redo.commit_action(false)
	_water_points = PackedVector2Array()
	_rebuild_water_edit_visuals()
	_refresh_water_list_option()
	_update_water_control_states()
	_set_status("Water body completed")


func _cancel_active_water() -> void:
	if _selected_water != null and _water_drawing_active:
		var temporary := _selected_water
		_selected_water = null
		_water_root.remove_child(temporary)
		temporary.free()
	_water_drawing_active = false
	_water_points = PackedVector2Array()
	_rebuild_water_edit_visuals()
	_refresh_water_list_option()
	_update_water_control_states()


func _delete_selected_water() -> void:
	if _selected_water == null and _water_list_option != null and _water_root != null:
		var selected_index := _water_list_option.selected
		if selected_index >= 0:
			_on_water_list_selected(selected_index)
	if _selected_water == null:
		return
	if _water_drawing_active:
		# Do not delete an unfinished temporary outline.
		return
	var record := _serialize_water(_selected_water)
	_undo_redo.create_action("Delete Water Body")
	_undo_redo.add_do_method(_remove_water_records.bind([record]))
	_undo_redo.add_undo_method(_restore_water_records.bind([record]))
	_undo_redo.commit_action()
	_refresh_water_list_option()
	_update_water_control_states()


func _on_water_list_selected(index: int) -> void:
	if _water_list_option == null or _water_root == null:
		return
	var child_index := _water_list_option.get_item_id(index)
	if child_index < 0 or child_index >= _water_root.get_child_count():
		return
	var water := _water_root.get_child(child_index) as WaterBody3D
	if water == null:
		return
	_selected_water = water
	_water_body_type = water.body_type
	_water_level = water.water_level
	_water_depth = water.water_depth
	_water_width = water.river_width
	_water_points = water.centerline_points if water.body_type == WaterBody3D.BodyType.RIVER else water.polygon_points
	if _water_type_option != null:
		_water_type_option.select(int(_water_body_type))
	if _water_level_spin != null:
		_water_level_spin.value = _water_level
	if _water_depth_spin != null:
		_water_depth_spin.value = _water_depth
	if _water_width_spin != null:
		_water_width_spin.value = _water_width
	_rebuild_water_edit_visuals()
	_update_water_control_states()


func _refresh_water_list_option() -> void:
	if _water_list_option == null:
		return
	_water_list_option.clear()
	if _water_root == null:
		return
	for index in range(_water_root.get_child_count()):
		var water := _water_root.get_child(index) as WaterBody3D
		if water == null:
			continue
		_water_list_option.add_item(water.name, index)
		if water == _selected_water:
			_water_list_option.select(_water_list_option.item_count - 1)
	if _selected_water == null and _water_list_option.item_count > 0:
		# Keep the first saved water selectable after loading a package. Godot's
		# OptionButton.select() does not emit item_selected, so update the editor
		# state explicitly as well.
		_water_list_option.select(0)
		_on_water_list_selected(0)


func _serialize_water(water: WaterBody3D) -> Dictionary:
	var uuid := str(water.get_meta("map_editor_water_uuid", ""))
	if uuid.is_empty():
		uuid = _new_editor_uuid("water")
		water.set_meta("map_editor_water_uuid", uuid)
	var polygon: Array = []
	for point in water.polygon_points:
		polygon.append(point)
	var centerline: Array = []
	for point in water.centerline_points:
		centerline.append(point)
	return {
		"uuid": uuid,
		"name": water.name,
		"transform": Transform3D(Basis.IDENTITY, Vector3.ZERO),
		"body_type": int(water.body_type),
		"polygon_points": polygon,
		"centerline_points": centerline,
		"water_level": water.water_level,
		"water_depth": water.water_depth,
		"river_width": water.river_width,
		"water_collision_layer": WATER_COLLISION_LAYER,
		"water_collision_mask": WATER_COLLISION_MASK,
}


func _count_neutral_crop_generators() -> int:
	if _buildings_root == null:
		return 0
	var count := 0
	for child in _buildings_root.get_children():
		if child is Node3D and _is_neutral_crop_generator(child as Node3D):
			count += 1
	return count


func _apply_serialized_water_to_node(water: WaterBody3D, record: Dictionary) -> void:
	water.name = str(record.get("name", "WaterBody3D"))
	water.position.y = 0.0
	water.set_meta("map_editor_water_uuid", str(record.get("uuid", _new_editor_uuid("water"))))
	water.body_type = int(record.get("body_type", WaterBody3D.BodyType.LAKE))
	water.polygon_points = _packed_vector2_array_from_variant(record.get("polygon_points", []))
	water.centerline_points = _packed_vector2_array_from_variant(record.get("centerline_points", []))
	water.water_level = float(record.get("water_level", _water_level))
	water.water_depth = float(record.get("water_depth", _water_depth))
	water.river_width = float(record.get("river_width", _water_width))
	water.water_collision_layer = WATER_COLLISION_LAYER
	water.water_collision_mask = WATER_COLLISION_MASK
	water.rebuild_water_body()


func _packed_vector2_array_from_variant(value: Variant) -> PackedVector2Array:
	var result := PackedVector2Array()
	if value is PackedVector2Array:
		return value
	if not value is Array:
		return result
	for item in value as Array:
		if item is Vector2:
			result.append(item as Vector2)
	return result


func _find_water_by_uuid(uuid: String) -> WaterBody3D:
	if uuid.is_empty() or _water_root == null:
		return null
	for child in _water_root.get_children():
		var water := child as WaterBody3D
		if water != null and str(water.get_meta("map_editor_water_uuid", "")) == uuid:
			return water
	return null


func _restore_water_records(records: Array) -> void:
	for value in records:
		var record := value as Dictionary
		var uuid := str(record.get("uuid", ""))
		if not uuid.is_empty() and _find_water_by_uuid(uuid) != null:
			continue
		var packed := _load_resource_or_null(WATER_BODY_PATH) as PackedScene
		if packed == null:
			continue
		var water := packed.instantiate() as WaterBody3D
		if water == null:
			continue
		_water_root.add_child(water)
		_apply_serialized_water_to_node(water, record)
	_refresh_water_list_option()


func _remove_water_records(records: Array) -> void:
	for value in records:
		var record := value as Dictionary
		var water := _find_water_by_uuid(str(record.get("uuid", "")))
		if water == null:
			continue
		if water == _selected_water:
			_selected_water = null
		water.get_parent().remove_child(water)
		water.free()
	_refresh_water_list_option()
	_rebuild_water_edit_visuals()


func _commit_water_state_change(action_name: String, before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() or after.is_empty() or _water_history_guard:
		return
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(_apply_water_record_state.bind(after))
	_undo_redo.add_undo_method(_apply_water_record_state.bind(before))
	_undo_redo.commit_action(false)


func _apply_water_record_state(record: Dictionary) -> void:
	var water := _find_water_by_uuid(str(record.get("uuid", "")))
	if water == null:
		_restore_water_records([record])
		water = _find_water_by_uuid(str(record.get("uuid", "")))
	if water == null:
		return
	_apply_serialized_water_to_node(water, record)
	if _selected_water == water:
		_water_body_type = water.body_type
		_water_level = water.water_level
		_water_depth = water.water_depth
		_water_width = water.river_width
		_water_points = water.centerline_points if water.body_type == WaterBody3D.BodyType.RIVER else water.polygon_points
	_rebuild_water_edit_visuals()
	_refresh_water_list_option()


func _rebuild_all_water_bodies() -> void:
	if _water_root == null:
		return
	for child in _water_root.get_children():
		var water := child as WaterBody3D
		if water != null:
			water.rebuild_water_body()


func _is_point_in_water(world_xz: Vector2, y_value: float = 0.0) -> bool:
	if _water_root == null:
		return false
	var position := Vector3(world_xz.x, y_value, world_xz.y)
	for child in _water_root.get_children():
		var water := child as WaterBody3D
		if water != null and water.contains_surface_point(position):
			return true
	return false


func _reset_road_editor_state() -> void:
	_selected_road = null
	_road_drawing_active = false
	_road_selected_point = -1
	_road_dragging = false
	_road_drag_before.clear()
	if is_instance_valid(_road_edit_visual_root):
		_road_edit_visual_root.queue_free()
	_road_edit_visual_root = null
	_road_marker_root = null
	_road_centerline = null
	_road_centerline_mesh = null
	_road_preview_line = null
	_road_preview_mesh = null


func _reset_water_editor_state() -> void:
	_selected_water = null
	_water_drawing_active = false
	_water_points = PackedVector2Array()
	if is_instance_valid(_water_preview_root):
		_water_preview_root.queue_free()
	_water_preview_root = null
	_water_preview_line = null
	_water_preview_mesh = null
	_water_marker_root = null


func _begin_new_road() -> void:
	if _roads_root == null:
		return
	_finish_active_road()
	var road = _create_road_node()
	if road == null:
		_set_status("Could not create road: missing %s" % ROAD_SCRIPT_PATH)
		return
	_selected_road = road
	_road_drawing_active = true
	_road_selected_point = -1
	_refresh_road_list_option()
	_rebuild_road_edit_visuals()
	_update_road_control_states()
	_set_status("Road drawing: click terrain points, then press Enter or Finish Road")


func _begin_new_rail() -> void:
	_road_type = ROAD_TYPE_RAIL
	if _road_type_option != null:
		for index in range(_road_type_option.item_count):
			if _road_type_option.get_item_id(index) == ROAD_TYPE_RAIL:
				_road_type_option.select(index)
				break
	_begin_new_road()


func _create_road_node() -> Path3D:
	var road_script = _load_resource_or_null(ROAD_SCRIPT_PATH) as Script
	if road_script == null:
		return null
	var road = Path3D.new()
	road.name = "RoadPath3D_%03d" % (_roads_root.get_child_count() + 1)
	road.set_script(road_script)
	if not _has_property(road, "mesh_sample_spacing") or not road.has_method("rebuild_road"):
		road.free()
		_set_status(
			"Road script is still the legacy GLB-block version. Replace "
			+ ROAD_SCRIPT_PATH
			+ " with the continuous road script."
		)
		return null
	road.curve = Curve3D.new()
	road.curve.bake_interval = maxf(0.1, road_mesh_sample_spacing * 0.5)
	road.set_meta("map_editor_road_uuid", _new_editor_uuid("road"))
	_roads_root.add_child(road)
	_set_property_if_present(road, "road_type", _road_type)
	_set_property_if_present(road, "width_override", _road_width_override)
	_set_property_if_present(road, "mesh_sample_spacing", road_mesh_sample_spacing)
	_set_property_if_present(road, "max_mesh_samples", road_max_mesh_samples)
	_set_property_if_present(road, "vertical_offset", _road_vertical_offset)
	_set_property_if_present(road, "editor_preview_mode", true)
	_set_property_if_present(road, "follow_terrain", true)
	_set_property_if_present(road, "terrain_collision_mask", TERRAIN_COLLISION_LAYER)
	return road


func _handle_road_left_press() -> void:
	if _latest_hit.is_empty():
		return
	var point_index = _find_road_control_point_under_mouse()
	if point_index >= 0 and _selected_road != null:
		_road_selected_point = point_index
		_road_dragging = true
		_road_drag_before = _serialize_road(_selected_road)
		if _selected_road.has_method("set_rebuild_suspended"):
			_selected_road.call("set_rebuild_suspended", true)
		_rebuild_road_edit_visuals()
		_update_road_control_states()
		return
	var hit_position = _latest_hit.get("position", Vector3.ZERO) as Vector3
	if _road_drawing_active and _selected_road != null:
		_add_point_to_active_road(hit_position)
		return
	var nearest = _find_nearest_road(hit_position)
	if nearest != null:
		_select_road(nearest)
	else:
		_road_selected_point = -1
		_rebuild_road_edit_visuals()


func _add_point_to_active_road(hit_position: Vector3) -> void:
	if _selected_road == null or _selected_road.curve == null:
		return
	if not _selected_road.is_inside_tree():
		return
	var world_point = Vector3(
		hit_position.x,
		get_terrain_height_world(Vector2(hit_position.x, hit_position.z)),
		hit_position.z
	)
	var point = _selected_road.to_local(world_point)
	_selected_road.curve.add_point(point)
	_road_selected_point = _selected_road.curve.point_count - 1
	_smooth_road_curve_handles(_selected_road.curve)
	# Curve3D.changed schedules one coalesced rebuild. Calling rebuild_road()
	# again here used to create duplicate work on the second point.
	_rebuild_road_edit_visuals()
	_update_road_control_states()
	_set_status("Road points: %d" % _selected_road.curve.point_count)


func _finish_active_road() -> void:
	if not _road_drawing_active:
		return
	_road_drawing_active = false
	if _selected_road == null:
		return
	if _selected_road.curve == null or _selected_road.curve.point_count < 2:
		var invalid = _selected_road
		_selected_road = null
		invalid.queue_free()
		_rebuild_road_edit_visuals()
		_refresh_bottom_dock()
		_set_status("Road cancelled: at least two points are required")
		return
	_set_property_if_present(_selected_road, "editor_preview_mode", false)
	_rebuild_road_now(_selected_road)
	var record = _serialize_road(_selected_road)
	_undo_redo.create_action("Create Road")
	_undo_redo.add_do_method(_restore_road_records.bind([record]))
	_undo_redo.add_undo_method(_remove_road_records.bind([record]))
	_undo_redo.commit_action(false)
	_refresh_bottom_dock()
	_update_road_control_states()
	_set_status("Road completed")


func _cancel_active_road() -> void:
	if not _road_drawing_active:
		return
	_road_drawing_active = false
	if _selected_road != null:
		var road = _selected_road
		_selected_road = null
		road.queue_free()
	_road_selected_point = -1
	_rebuild_road_edit_visuals()
	_refresh_bottom_dock()
	_update_road_control_states()
	_set_status("Road drawing cancelled")


func _drag_selected_road_point(hit_position: Vector3) -> void:
	if _selected_road == null or _selected_road.curve == null:
		return
	if _road_selected_point < 0 or _road_selected_point >= _selected_road.curve.point_count:
		return
	if not _selected_road.is_inside_tree():
		return
	var world_point = Vector3(
		hit_position.x,
		get_terrain_height_world(Vector2(hit_position.x, hit_position.z)),
		hit_position.z
	)
	var point = _selected_road.to_local(world_point)
	_selected_road.curve.set_point_position(_road_selected_point, point)
	_smooth_road_curve_handles(_selected_road.curve)
	_rebuild_road_edit_visuals()


func _end_road_point_drag() -> void:
	if not _road_dragging:
		return
	_road_dragging = false
	if _selected_road != null and _selected_road.has_method("set_rebuild_suspended"):
		_selected_road.call("set_rebuild_suspended", false)
	if _selected_road == null or _road_drag_before.is_empty():
		_road_drag_before.clear()
		return
	var after = _serialize_road(_selected_road)
	_commit_road_state_change("Move Road Point", _road_drag_before, after)
	_road_drag_before.clear()


func _delete_selected_road_point() -> void:
	if _selected_road == null or _selected_road.curve == null or _road_selected_point < 0:
		return
	var before = _serialize_road(_selected_road)
	_selected_road.curve.remove_point(_road_selected_point)
	_road_selected_point = mini(_road_selected_point, _selected_road.curve.point_count - 1)
	_smooth_road_curve_handles(_selected_road.curve)
	_rebuild_road_now(_selected_road)
	var after = _serialize_road(_selected_road)
	_commit_road_state_change("Delete Road Point", before, after)
	_rebuild_road_edit_visuals()
	_refresh_bottom_dock()
	_update_road_control_states()


func _conform_selected_road_to_terrain() -> void:
	if _selected_road == null or _selected_road.curve == null:
		return
	var before = _serialize_road(_selected_road)
	if not _selected_road.is_inside_tree():
		return
	for index in range(_selected_road.curve.point_count):
		var local_point = _selected_road.curve.get_point_position(index)
		var world_point = _selected_road.to_global(local_point)
		world_point.y = get_terrain_height_world(Vector2(world_point.x, world_point.z))
		_selected_road.curve.set_point_position(
			index,
			_selected_road.to_local(world_point)
		)
	_smooth_road_curve_handles(_selected_road.curve)
	_rebuild_road_now(_selected_road)
	var after = _serialize_road(_selected_road)
	_commit_road_state_change("Conform Road To Terrain", before, after)
	_rebuild_road_edit_visuals()


func _delete_selected_road() -> void:
	if _selected_road == null:
		return
	var record = _serialize_road(_selected_road)
	_remove_road_records([record])
	_undo_redo.create_action("Delete Road")
	_undo_redo.add_do_method(_remove_road_records.bind([record]))
	_undo_redo.add_undo_method(_restore_road_records.bind([record]))
	_undo_redo.commit_action(false)
	_selected_road = null
	_road_selected_point = -1
	_refresh_bottom_dock()
	_rebuild_road_edit_visuals()
	_update_road_control_states()


func _commit_road_state_change(action_name: String, before: Dictionary, after: Dictionary) -> void:
	if before.is_empty() or after.is_empty():
		return
	_undo_redo.create_action(action_name)
	_undo_redo.add_do_method(_apply_road_record_state.bind(after))
	_undo_redo.add_undo_method(_apply_road_record_state.bind(before))
	_undo_redo.commit_action(false)


func _apply_road_record_state(record: Dictionary) -> void:
	var uuid = str(record.get("uuid", ""))
	var road = _find_road_by_uuid(uuid)
	if road == null:
		_restore_road_records([record])
		road = _find_road_by_uuid(uuid)
	if road == null:
		return
	_apply_serialized_road_to_node(road, record)
	if _selected_road != null and str(_selected_road.get_meta("map_editor_road_uuid", "")) == uuid:
		_selected_road = road
	_rebuild_road_edit_visuals()
	_refresh_bottom_dock()


func _smooth_road_curve_handles(target_curve: Curve3D) -> void:
	if target_curve == null:
		return
	var count = target_curve.point_count
	for index in range(count):
		var current = target_curve.get_point_position(index)
		var previous = target_curve.get_point_position(maxi(0, index - 1))
		var next = target_curve.get_point_position(mini(count - 1, index + 1))
		var tangent = (next - previous) * 0.22
		if index == 0:
			tangent = (next - current) * 0.32
		elif index == count - 1:
			tangent = (current - previous) * 0.32
		target_curve.set_point_in(index, -tangent)
		target_curve.set_point_out(index, tangent)


func _find_road_control_point_under_mouse() -> int:
	if (
		_selected_road == null
		or _selected_road.curve == null
		or _editor_camera == null
		or not _selected_road.is_inside_tree()
	):
		return -1
	var mouse = get_viewport().get_mouse_position()
	var best_index = -1
	var best_distance = road_control_point_pick_radius_px
	for index in range(_selected_road.curve.point_count):
		var world = _selected_road.to_global(_selected_road.curve.get_point_position(index))
		if _editor_camera.is_position_behind(world):
			continue
		var screen = _editor_camera.unproject_position(world)
		var distance = screen.distance_to(mouse)
		if distance <= best_distance:
			best_distance = distance
			best_index = index
	return best_index


func _find_nearest_road(world_position: Vector3) -> Path3D:
	if _roads_root == null:
		return null
	var best: Path3D
	var best_distance = road_selection_world_distance
	for child in _roads_root.get_children():
		if not child is Path3D:
			continue
		var road = child as Path3D
		if not road.is_inside_tree():
			continue
		if road.curve == null or road.curve.point_count < 2:
			continue
		var total = road.curve.get_baked_length()
		var sample_count = maxi(2, int(ceil(total / 2.0)) + 1)
		for index in range(sample_count):
			var distance_along = float(index) * total / float(sample_count - 1)
			var point = road.to_global(road.curve.sample_baked(distance_along, true))
			var distance = Vector2(point.x, point.z).distance_to(Vector2(world_position.x, world_position.z))
			if distance < best_distance:
				best_distance = distance
				best = road
	return best


func _select_road(road: Path3D) -> void:
	_selected_road = road
	_road_selected_point = -1
	_road_drawing_active = false
	_road_type = int(_get_property_or(road, "road_type", 1))
	_road_width_override = float(_get_property_or(road, "width_override", 0.0))
	_road_vertical_offset = float(_get_property_or(road, "vertical_offset", road_default_vertical_offset))
	_refresh_bottom_dock()
	_rebuild_road_edit_visuals()
	_update_road_control_states()


func _on_road_list_selected(index: int) -> void:
	if _road_list_option == null or index < 0:
		return
	var child_index = _road_list_option.get_item_id(index)
	if _roads_root != null and child_index >= 0 and child_index < _roads_root.get_child_count():
		var road = _roads_root.get_child(child_index) as Path3D
		if road != null:
			_select_road(road)


func _refresh_road_list_option() -> void:
	if _road_list_option == null:
		return
	_road_list_option.clear()
	if _roads_root == null:
		return
	for child_index in range(_roads_root.get_child_count()):
		var child = _roads_root.get_child(child_index)
		if not child is Path3D:
			continue
		_road_list_option.add_item(child.name, child_index)
		if child == _selected_road:
			_road_list_option.select(_road_list_option.item_count - 1)


func _on_road_type_selected(index: int) -> void:
	_road_type = _road_type_option.get_item_id(index)
	if _selected_road != null:
		var before = _serialize_road(_selected_road)
		_set_property_if_present(_selected_road, "road_type", _road_type)
		_rebuild_road_now(_selected_road)
		if not _road_drawing_active:
			_commit_road_state_change(
				"Change Road Type",
				before,
				_serialize_road(_selected_road)
			)


func _on_road_width_changed(value: float) -> void:
	_road_width_override = value
	if _selected_road != null:
		var before = _serialize_road(_selected_road)
		_set_property_if_present(_selected_road, "width_override", value)
		_rebuild_road_now(_selected_road)
		if not _road_drawing_active:
			_commit_road_state_change(
				"Change Road Width",
				before,
				_serialize_road(_selected_road)
			)


func _on_road_offset_changed(value: float) -> void:
	_road_vertical_offset = value
	if _selected_road != null:
		var before = _serialize_road(_selected_road)
		_set_property_if_present(_selected_road, "vertical_offset", value)
		_rebuild_road_now(_selected_road)
		if not _road_drawing_active:
			_commit_road_state_change(
				"Change Road Height Offset",
				before,
				_serialize_road(_selected_road)
			)


func _update_road_preview(cursor: Vector3) -> void:
	_ensure_road_edit_visuals()
	if _road_preview_mesh == null:
		return
	_road_preview_mesh.clear_surfaces()
	if (
		not _road_drawing_active
		or _selected_road == null
		or _selected_road.curve == null
		or _selected_road.curve.point_count == 0
		or not _selected_road.is_inside_tree()
		or _road_preview_line == null
		or not _road_preview_line.is_inside_tree()
	):
		return
	var last_world = _selected_road.to_global(
		_selected_road.curve.get_point_position(
			_selected_road.curve.point_count - 1
		)
	) + Vector3.UP * 0.12
	var target_world = Vector3(
		cursor.x,
		get_terrain_height_world(Vector2(cursor.x, cursor.z)) + 0.12,
		cursor.z
	)
	_road_preview_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_road_preview_mesh.surface_add_vertex(
		_road_preview_line.to_local(last_world)
	)
	_road_preview_mesh.surface_add_vertex(
		_road_preview_line.to_local(target_world)
	)
	_road_preview_mesh.surface_end()


func _rebuild_road_edit_visuals() -> void:
	_ensure_road_edit_visuals()
	if (
		_road_marker_root == null
		or _road_centerline_mesh == null
		or _road_centerline == null
	):
		return

	# Detach old markers immediately. queue_free() alone leaves them in the
	# scene tree until the end of the frame and can cause duplicate/stale
	# control-point visuals during rapid edits.
	for child in _road_marker_root.get_children():
		_road_marker_root.remove_child(child)
		child.queue_free()

	_road_centerline_mesh.clear_surfaces()
	if (
		_selected_road == null
		or _selected_road.curve == null
		or not _selected_road.is_inside_tree()
		or not _road_marker_root.is_inside_tree()
		or not _road_centerline.is_inside_tree()
	):
		return

	for index in range(_selected_road.curve.point_count):
		var marker = MeshInstance3D.new()
		marker.name = "RoadPoint_%02d" % index
		var sphere = SphereMesh.new()
		sphere.radius = 0.45 if index == _road_selected_point else 0.32
		sphere.height = sphere.radius * 2.0
		marker.mesh = sphere
		marker.material_override = _make_unshaded_material(
			Color(1.0, 0.2, 0.08, 1.0)
			if index == _road_selected_point
			else Color(1.0, 0.82, 0.1, 1.0)
		)

		# A Node3D cannot use global_position before it enters SceneTree.
		# Add it first, then convert the road point from world space into the
		# marker root's local space.
		_road_marker_root.add_child(marker)
		var marker_world = _selected_road.to_global(
			_selected_road.curve.get_point_position(index)
		) + Vector3.UP * 0.18
		marker.position = _road_marker_root.to_local(marker_world)

	if _selected_road.curve.point_count >= 2:
		var total = _selected_road.curve.get_baked_length()
		if total <= 0.001:
			return
		var sample_count = maxi(2, int(ceil(total / 1.0)) + 1)
		# Centerline is only an editor helper, so cap its vertices as well.
		sample_count = mini(sample_count, 2048)
		_road_centerline_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for index in range(sample_count):
			var distance = float(index) * total / float(sample_count - 1)
			var point_world = _selected_road.to_global(
				_selected_road.curve.sample_baked(distance, true)
			) + Vector3.UP * 0.18
			_road_centerline_mesh.surface_add_vertex(
				_road_centerline.to_local(point_world)
			)
		_road_centerline_mesh.surface_end()


func _rebuild_road_now(road: Path3D) -> void:
	if road == null:
		return
	if road.has_method("request_rebuild"):
		road.call("request_rebuild")
	elif road.has_method("rebuild_road"):
		road.call_deferred("rebuild_road")


func _rebuild_all_roads_to_terrain() -> void:
	if _roads_root == null:
		return
	for child in _roads_root.get_children():
		if child is Path3D:
			_rebuild_road_now(child as Path3D)


func _serialize_road(road: Path3D) -> Dictionary:
	var uuid = str(road.get_meta("map_editor_road_uuid", ""))
	if uuid.is_empty():
		uuid = _new_editor_uuid("road")
		road.set_meta("map_editor_road_uuid", uuid)
	var points: Array = []
	var in_handles: Array = []
	var out_handles: Array = []
	var tilts: Array = []
	if road.curve != null:
		for index in range(road.curve.point_count):
			points.append(road.curve.get_point_position(index))
			in_handles.append(road.curve.get_point_in(index))
			out_handles.append(road.curve.get_point_out(index))
			tilts.append(road.curve.get_point_tilt(index))
	return {
		"uuid": uuid,
		"name": road.name,
		"transform": road.transform,
		"road_type": int(_get_property_or(road, "road_type", 1)),
		"width_override": float(_get_property_or(road, "width_override", 0.0)),
		"mesh_sample_spacing": float(_get_property_or(road, "mesh_sample_spacing", road_mesh_sample_spacing)),
		"max_mesh_samples": int(_get_property_or(road, "max_mesh_samples", road_max_mesh_samples)),
		"vertical_offset": float(_get_property_or(road, "vertical_offset", road_default_vertical_offset)),
		"texture_repeat_length": float(_get_property_or(road, "texture_repeat_length", 6.0)),
		"follow_terrain": bool(_get_property_or(road, "follow_terrain", true)),
		"terrain_collision_mask": int(_get_property_or(road, "terrain_collision_mask", TERRAIN_COLLISION_LAYER)),
		"crown_height": float(_get_property_or(road, "crown_height", 0.015)),
		"edge_drop": float(_get_property_or(road, "edge_drop", 0.0)),
		"generate_collision": bool(_get_property_or(road, "generate_collision", false)),
		"points": points,
		"in_handles": in_handles,
		"out_handles": out_handles,
		"tilts": tilts,
		"closed": road.curve.closed if road.curve != null else false,
	}


func _apply_serialized_road_to_node(road: Path3D, record: Dictionary) -> void:
	road.name = str(record.get("name", "RoadPath3D"))
	road.transform = record.get("transform", Transform3D.IDENTITY) as Transform3D
	road.set_meta("map_editor_road_uuid", str(record.get("uuid", _new_editor_uuid("road"))))
	_set_property_if_present(road, "road_type", int(record.get("road_type", 1)))
	_set_property_if_present(road, "width_override", float(record.get("width_override", 0.0)))
	_set_property_if_present(road, "mesh_sample_spacing", float(record.get("mesh_sample_spacing", road_mesh_sample_spacing)))
	_set_property_if_present(road, "max_mesh_samples", int(record.get("max_mesh_samples", road_max_mesh_samples)))
	_set_property_if_present(road, "vertical_offset", float(record.get("vertical_offset", road_default_vertical_offset)))
	_set_property_if_present(road, "editor_preview_mode", false)
	_set_property_if_present(road, "texture_repeat_length", float(record.get("texture_repeat_length", 6.0)))
	_set_property_if_present(road, "follow_terrain", bool(record.get("follow_terrain", true)))
	_set_property_if_present(road, "terrain_collision_mask", int(record.get("terrain_collision_mask", TERRAIN_COLLISION_LAYER)))
	_set_property_if_present(road, "crown_height", float(record.get("crown_height", 0.015)))
	_set_property_if_present(road, "edge_drop", float(record.get("edge_drop", 0.0)))
	_set_property_if_present(road, "generate_collision", bool(record.get("generate_collision", false)))
	var curve_value = Curve3D.new()
	var points = record.get("points", []) as Array
	var in_handles = record.get("in_handles", []) as Array
	var out_handles = record.get("out_handles", []) as Array
	var tilts = record.get("tilts", []) as Array
	for index in range(points.size()):
		curve_value.add_point(
			points[index] as Vector3,
			in_handles[index] as Vector3 if index < in_handles.size() else Vector3.ZERO,
			out_handles[index] as Vector3 if index < out_handles.size() else Vector3.ZERO
		)
		if index < tilts.size():
			curve_value.set_point_tilt(index, float(tilts[index]))
	curve_value.closed = bool(record.get("closed", false))
	road.curve = curve_value
	if road.has_method("refresh_curve_connection"):
		road.call("refresh_curve_connection")
	else:
		_rebuild_road_now(road)


func _save_roads_sidecar(folder: String) -> void:
	var records: Array = []
	if _roads_root != null:
		for child in _roads_root.get_children():
			if child is Path3D:
				records.append(_serialize_road(child as Path3D))
	var file = FileAccess.open(folder.path_join(ROADS_FILE_NAME), FileAccess.WRITE)
	if file != null:
		file.store_var(records, true)
		file.close()


func _load_roads_sidecar(path: String) -> void:
	if _roads_root == null:
		return
	for child in _roads_root.get_children():
		child.queue_free()
	if not FileAccess.file_exists(path):
		return
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var loaded = file.get_var(true)
	file.close()
	if loaded is Array:
		_restore_road_records(loaded as Array)


func _restore_road_records(records: Array) -> void:
	for value in records:
		var record = value as Dictionary
		var uuid = str(record.get("uuid", ""))
		if not uuid.is_empty() and _find_road_by_uuid(uuid) != null:
			continue
		var road = _create_road_node()
		if road == null:
			continue
		_apply_serialized_road_to_node(road, record)
	_refresh_road_list_option()
	_rebuild_road_edit_visuals()


func _remove_road_records(records: Array) -> void:
	for value in records:
		var record = value as Dictionary
		var road = _find_road_by_uuid(str(record.get("uuid", "")))
		if road == null:
			continue
		if road == _selected_road:
			_selected_road = null
			_road_selected_point = -1
		road.queue_free()
	_refresh_road_list_option()
	_rebuild_road_edit_visuals()


func _find_road_by_uuid(uuid: String) -> Path3D:
	if uuid.is_empty() or _roads_root == null:
		return null
	for child in _roads_root.get_children():
		if child is Path3D and str(child.get_meta("map_editor_road_uuid", "")) == uuid:
			return child as Path3D
	return null


# -----------------------------------------------------------------------------
# Shared helpers
# -----------------------------------------------------------------------------

func _sync_package_fields_from_ui() -> void:
	if _map_name_edit != null:
		var requested_display_name = _map_name_edit.text.strip_edges()
		if not requested_display_name.is_empty():
			_display_name = requested_display_name
	if _map_version_edit != null:
		var requested_version = _map_version_edit.text.strip_edges()
		_map_version = requested_version if not requested_version.is_empty() else default_map_version
	if _map_id_edit != null:
		var raw_requested_id = _map_id_edit.text.strip_edges()
		if not raw_requested_id.is_empty():
			var requested_id = _make_map_id(raw_requested_id)
			if requested_id != _map_id:
				_map_id = requested_id
				_map_name = requested_id
				if _map_root != null:
					_map_root.name = _map_id.validate_node_name()
	_configure_integrated_systems()


func _build_icon_file_dialog() -> void:
	_icon_file_dialog = FileDialog.new()
	_icon_file_dialog.name = "MapIconFileDialog"
	_icon_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_icon_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_icon_file_dialog.use_native_dialog = true
	_icon_file_dialog.title = "Choose PNG Map Icon"
	_icon_file_dialog.filters = PackedStringArray(["*.png, *.PNG ; PNG Images"])
	_icon_file_dialog.file_selected.connect(_on_icon_file_selected)
	_ui_layer.add_child(_icon_file_dialog)


func _open_icon_file_dialog() -> void:
	if _icon_file_dialog == null:
		return
	_icon_file_dialog.popup_centered_ratio(0.75)


func _on_icon_file_selected(path: String) -> void:
	if path.get_extension().to_lower() != "png":
		_set_status("Map icon must be a PNG file")
		return

	var source = Image.load_from_file(path)
	if source == null or source.is_empty():
		_set_status("Could not load PNG icon: %s" % path)
		return
	if source.is_compressed() and source.decompress() != OK:
		_set_status("Could not decompress PNG icon")
		return

	_map_icon_image = _make_letterboxed_icon(source)
	_map_icon_texture = ImageTexture.create_from_image(_map_icon_image)
	_map_icon_source_path = path
	if _icon_preview != null:
		_icon_preview.texture = _map_icon_texture
	if _icon_status_label != null:
		_icon_status_label.text = "%s -> 128x128" % path.get_file()
	_set_status("Imported map icon: %s" % path.get_file())


func _make_letterboxed_icon(source: Image) -> Image:
	var working = source.duplicate()
	working.convert(Image.FORMAT_RGBA8)
	var source_width = maxi(1, working.get_width())
	var source_height = maxi(1, working.get_height())
	var scale_factor = minf(
		float(MAP_ICON_SIZE) / float(source_width),
		float(MAP_ICON_SIZE) / float(source_height)
	)
	var resized_width = clampi(roundi(float(source_width) * scale_factor), 1, MAP_ICON_SIZE)
	var resized_height = clampi(roundi(float(source_height) * scale_factor), 1, MAP_ICON_SIZE)
	working.resize(resized_width, resized_height, Image.INTERPOLATE_LANCZOS)

	var result = Image.create_empty(
		MAP_ICON_SIZE,
		MAP_ICON_SIZE,
		false,
		Image.FORMAT_RGBA8
	)
	result.fill(Color(0.0, 0.0, 0.0, 1.0))
	var destination = Vector2i(
		(MAP_ICON_SIZE - resized_width) / 2,
		(MAP_ICON_SIZE - resized_height) / 2
	)
	result.blit_rect(
		working,
		Rect2i(Vector2i.ZERO, Vector2i(resized_width, resized_height)),
		destination
	)
	return result


func _save_map_icon(folder: String) -> bool:
	var icon_path = "%s/%s" % [folder, MAP_ICON_FILE_NAME]
	if _map_icon_image == null or _map_icon_image.is_empty():
		var absolute_icon_path = ProjectSettings.globalize_path(icon_path)
		if FileAccess.file_exists(icon_path):
			DirAccess.remove_absolute(absolute_icon_path)
		return false
	var error = _map_icon_image.save_png(icon_path)
	if error != OK:
		push_error("FarmWar map editor: failed to save map icon (%d)" % error)
		return false
	return true


func _far_ground_size_for_map() -> Vector2:
	return _map_size + Vector2.ONE * (FAR_SCENERY_GROUND_MARGIN * 2.0)


func _configure_camera_for_map_and_far_scenery() -> void:
	if _editor_camera == null:
		return
	var far_size = _far_ground_size_for_map()
	var required_far = maxf(
		editor_far_visibility_distance,
		far_size.length() * 1.35
	)
	_editor_camera.far = maxf(_editor_camera.far, required_far)


func _ensure_far_scenery_visible() -> void:
	if _far_scenery_ring == null:
		return

	_far_scenery_ring.visible = true
	_force_far_geometry_visibility_recursive(_far_scenery_ring)

	# Do not use child_count as a success test. The external far-scenery script
	# can create only helper/boundary nodes, or create ground meshes whose shader
	# failed, while child_count is still non-zero. A guaranteed opaque ground
	# ring is therefore generated independently for the editor and saved map.
	if force_guaranteed_far_ground:
		_rebuild_guaranteed_far_ground()
	elif not _has_renderable_far_geometry(_far_scenery_ring):
		_rebuild_guaranteed_far_ground()


func _has_renderable_far_geometry(root: Node) -> bool:
	for child in root.get_children():
		if child is MeshInstance3D:
			var mesh_instance = child as MeshInstance3D
			if mesh_instance.mesh != null and mesh_instance.visible:
				return true
		elif child is MultiMeshInstance3D:
			var multi_instance = child as MultiMeshInstance3D
			if (
				multi_instance.multimesh != null
				and multi_instance.multimesh.mesh != null
				and multi_instance.multimesh.instance_count > 0
				and multi_instance.visible
			):
				return true
		if _has_renderable_far_geometry(child):
			return true
	return false


func _force_far_geometry_visibility_recursive(root: Node) -> void:
	for child in root.get_children():
		if child is GeometryInstance3D:
			var geometry = child as GeometryInstance3D
			geometry.visible = true
			# Zero disables distance-range culling. The editor camera itself receives
			# a far plane large enough for the generated ring.
			geometry.visibility_range_begin = 0.0
			geometry.visibility_range_end = 0.0
			geometry.extra_cull_margin = maxf(
				geometry.extra_cull_margin,
				FAR_SCENERY_GROUND_MARGIN * 2.0
			)
		_force_far_geometry_visibility_recursive(child)


func _rebuild_guaranteed_far_ground() -> void:
	if _far_scenery_ring == null:
		return

	var previous = _far_scenery_ring.get_node_or_null(
		NodePath(EDITOR_FAR_GROUND_ROOT_NAME)
	)
	if previous != null:
		_far_scenery_ring.remove_child(previous)
		previous.free()

	# Hide only the external script's four ground strips to prevent coplanar
	# z-fighting. Its tree, rock, farm and grass MultiMeshes remain active.
	for external_ground_name in [
		"FarGroundNorth",
		"FarGroundSouth",
		"FarGroundWest",
		"FarGroundEast",
	]:
		var external_ground = _far_scenery_ring.get_node_or_null(
			NodePath(external_ground_name)
		)
		if external_ground is GeometryInstance3D:
			(external_ground as GeometryInstance3D).visible = false

	var guaranteed_root = Node3D.new()
	guaranteed_root.name = EDITOR_FAR_GROUND_ROOT_NAME
	_far_scenery_ring.add_child(guaranteed_root)

	var far_size = _far_ground_size_for_map()
	var outer_half = far_size * 0.5
	# Begin strictly outside the formal playable rectangle. The 2 cm separation
	# avoids coplanar overlap with the editable terrain while remaining visually
	# continuous at normal camera distances.
	var outside_gap = 0.02
	var inner_half = _map_size * 0.5 + Vector2.ONE * outside_gap
	var color = Color("75a94b")
	if not _surface_entries.is_empty():
		color = (
			_surface_entries[0] as Dictionary
		).get("color", color) as Color

	var material = StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.10)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var north_south_depth = maxf(1.0, outer_half.y - inner_half.y)
	var east_west_width = maxf(1.0, outer_half.x - inner_half.x)
	var center_y = initial_ground_height - 0.51

	_create_far_ground_strip_under(
		guaranteed_root,
		"EditorFarNorth",
		Vector3(0.0, center_y, -(inner_half.y + north_south_depth * 0.5)),
		Vector3(far_size.x, 1.0, north_south_depth),
		material
	)
	_create_far_ground_strip_under(
		guaranteed_root,
		"EditorFarSouth",
		Vector3(0.0, center_y, inner_half.y + north_south_depth * 0.5),
		Vector3(far_size.x, 1.0, north_south_depth),
		material
	)
	_create_far_ground_strip_under(
		guaranteed_root,
		"EditorFarWest",
		Vector3(-(inner_half.x + east_west_width * 0.5), center_y, 0.0),
		Vector3(east_west_width, 1.0, _map_size.y),
		material
	)
	_create_far_ground_strip_under(
		guaranteed_root,
		"EditorFarEast",
		Vector3(inner_half.x + east_west_width * 0.5, center_y, 0.0),
		Vector3(east_west_width, 1.0, _map_size.y),
		material
	)

	_configure_camera_for_map_and_far_scenery()


func _create_far_ground_strip_under(
	parent: Node3D,
	name_value: String,
	position_value: Vector3,
	size_value: Vector3,
	material: Material
) -> void:
	var mesh_instance = MeshInstance3D.new()
	mesh_instance.name = name_value
	mesh_instance.position = position_value
	var mesh = BoxMesh.new()
	mesh.size = size_value
	mesh.material = material
	mesh_instance.mesh = mesh
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.visibility_range_begin = 0.0
	mesh_instance.visibility_range_end = 0.0
	mesh_instance.extra_cull_margin = maxf(
		FAR_SCENERY_GROUND_MARGIN * 2.0,
		size_value.length()
	)
	parent.add_child(mesh_instance)


func _create_terrain_foundation() -> void:
	if _terrain_foundation_root == null or _ground_body == null:
		return

	var foundation_top = minimum_terrain_height - 2.0
	var foundation_thickness = maxf(1.0, foundation_depth_below_minimum)
	var foundation_center_y = foundation_top - foundation_thickness * 0.5
	var foundation_size = Vector3(
		_map_size.x + 4.0,
		foundation_thickness,
		_map_size.y + 4.0
	)

	# A direct child collision shape on Ground acts as a final safety floor.
	var shape_node = CollisionShape3D.new()
	shape_node.name = "SafetyFloorCollision"
	shape_node.position = Vector3(0.0, foundation_center_y, 0.0)
	var shape = BoxShape3D.new()
	shape.size = foundation_size
	shape_node.shape = shape
	shape_node.debug_color = Color(0.91, 0.19, 0.58, 0.25)
	_ground_body.add_child(shape_node)

	_ground_safety_mesh = MeshInstance3D.new()
	_ground_safety_mesh.name = "GroundBase"
	_ground_safety_mesh.position = Vector3(0.0, foundation_center_y, 0.0)
	var box_mesh = BoxMesh.new()
	box_mesh.size = foundation_size
	_ground_safety_mesh.mesh = box_mesh
	# The underground safety slab must never cast onto the terrain surface.
	_ground_safety_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# It exists solely as a physics safety floor; showing it creates a false
	# deep-map layer whenever the dynamic terrain is temporarily unavailable.
	_ground_safety_mesh.visible = false
	_ground_body.add_child(_ground_safety_mesh)
	_update_ground_safety_color()

	_terrain_skirt_mesh = MeshInstance3D.new()
	_terrain_skirt_mesh.name = "TerrainEdgeSkirt"
	_terrain_skirt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_terrain_foundation_root.add_child(_terrain_skirt_mesh)
	_update_ground_safety_color()
	_rebuild_terrain_skirt()


func _update_ground_safety_color() -> void:
	var color = Color("75a94b")
	if not _surface_entries.is_empty():
		color = (
			_surface_entries[0] as Dictionary
		).get("color", color) as Color
	var material = StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.35)
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if _ground_safety_mesh != null:
		_ground_safety_mesh.material_override = material
	if _terrain_skirt_mesh != null:
		_terrain_skirt_mesh.material_override = material
	_update_fallback_far_ground_color(color)


func _update_fallback_far_ground_color(base_color: Color) -> void:
	if _far_scenery_ring == null:
		return
	var guaranteed_root = _far_scenery_ring.get_node_or_null(
		NodePath(EDITOR_FAR_GROUND_ROOT_NAME)
	)
	if guaranteed_root == null:
		return
	for child in guaranteed_root.get_children():
		if not child is MeshInstance3D:
			continue
		var mesh_instance = child as MeshInstance3D
		var material = StandardMaterial3D.new()
		material.albedo_color = base_color.darkened(0.10)
		material.roughness = 1.0
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh_instance.material_override = material


func _rebuild_terrain_skirt() -> void:
	if _terrain_skirt_mesh == null or _height_samples.is_empty():
		return

	var bottom_y = minimum_terrain_height - 2.0
	var vertices = PackedVector3Array()
	var normals = PackedVector3Array()
	var uvs = PackedVector2Array()
	var indices = PackedInt32Array()

	_append_skirt_edge(vertices, normals, uvs, indices, 0, true, bottom_y)
	_append_skirt_edge(vertices, normals, uvs, indices, _sample_depth - 1, true, bottom_y)
	_append_skirt_edge(vertices, normals, uvs, indices, 0, false, bottom_y)
	_append_skirt_edge(vertices, normals, uvs, indices, _sample_width - 1, false, bottom_y)

	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	_terrain_skirt_mesh.mesh = mesh


func _append_skirt_edge(
	vertices: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	indices: PackedInt32Array,
	fixed_sample: int,
	horizontal: bool,
	bottom_y: float
) -> void:
	var segment_count = (_sample_width - 1) if horizontal else (_sample_depth - 1)
	var base_index = vertices.size()
	var edge_normal = Vector3.ZERO
	if horizontal:
		edge_normal = Vector3(0.0, 0.0, -1.0 if fixed_sample == 0 else 1.0)
	else:
		edge_normal = Vector3(-1.0 if fixed_sample == 0 else 1.0, 0.0, 0.0)

	for index in range(segment_count + 1):
		var sample_x = index if horizontal else fixed_sample
		var sample_z = fixed_sample if horizontal else index
		var world_x = _terrain_origin.x + float(sample_x) * vertex_spacing
		var world_z = _terrain_origin.y + float(sample_z) * vertex_spacing
		var top_y = _get_height_sample(sample_x, sample_z)
		vertices.append(Vector3(world_x, top_y, world_z))
		vertices.append(Vector3(world_x, bottom_y, world_z))
		normals.append(edge_normal)
		normals.append(edge_normal)
		var edge_u = float(index) / float(maxi(1, segment_count))
		uvs.append(Vector2(edge_u, 0.0))
		uvs.append(Vector2(edge_u, 1.0))

	for index in range(segment_count):
		var i0 = base_index + index * 2
		var i1 = i0 + 1
		var i2 = i0 + 2
		var i3 = i0 + 3
		if fixed_sample == 0:
			indices.append(i0)
			indices.append(i1)
			indices.append(i2)
			indices.append(i2)
			indices.append(i1)
			indices.append(i3)
		else:
			indices.append(i0)
			indices.append(i2)
			indices.append(i1)
			indices.append(i2)
			indices.append(i3)
			indices.append(i1)


func _rect_touches_terrain_edge(rect: Rect2i) -> bool:
	return (
		rect.position.x <= 0
		or rect.position.y <= 0
		or rect.end.x >= _sample_width
		or rect.end.y >= _sample_depth
	)


func _clamp_editor_camera_above_ground(position_value: Vector3) -> Vector3:
	if _map_root == null:
		return position_value

	# The editor camera is not a CharacterBody3D, so constrain its center
	# explicitly against the playable rectangle and authoritative height data.
	var margin = clampf(
		camera_boundary_margin,
		0.0,
		minf(_map_size.x, _map_size.y) * 0.45
	)
	var map_min = _terrain_origin + Vector2.ONE * margin
	var map_max = _terrain_origin + _map_size - Vector2.ONE * margin
	var requested_x = position_value.x
	var requested_z = position_value.z
	position_value.x = clampf(position_value.x, map_min.x, map_max.x)
	position_value.z = clampf(position_value.z, map_min.y, map_max.y)
	if (
		not is_equal_approx(requested_x, position_value.x)
		or not is_equal_approx(requested_z, position_value.z)
	):
		_show_boundary_warning()

	var terrain_height = get_terrain_height_world(
		Vector2(position_value.x, position_value.z)
	)
	position_value.y = maxf(
		position_value.y,
		terrain_height + camera_ground_clearance
	)
	return position_value


func _make_map_id(value: String) -> String:
	var result = value.strip_edges().to_lower()
	result = result.replace(" ", "_").replace("-", "_")
	var output = ""
	for index in range(result.length()):
		var code = result.unicode_at(index)
		var character = result.substr(index, 1)
		var is_ascii_letter = code >= 97 and code <= 122
		var is_digit = code >= 48 and code <= 57
		if is_ascii_letter or is_digit or character == "_":
			output += character
		elif not output.ends_with("_"):
			output += "_"
	while output.contains("__"):
		output = output.replace("__", "_")
	output = output.trim_prefix("_").trim_suffix("_")
	return output if not output.is_empty() else "new_farm_map"


func _load_resource_or_null(path: String) -> Resource:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path)


func _safe_file_name(value: String) -> String:
	var result = value.strip_edges()
	for invalid_character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|"]:
		result = result.replace(invalid_character, "_")
	return result if not result.is_empty() else "NewFarmMap"


func _has_property(object: Object, property_name: String) -> bool:
	if object == null:
		return false
	for property_value in object.get_property_list():
		var property = property_value as Dictionary
		if str(property.get("name", "")) == property_name:
			return true
	return false


func _set_property_if_present(object: Object, property_name: String, value: Variant) -> void:
	if _has_property(object, property_name):
		object.set(property_name, value)


func _get_property_or(object: Object, property_name: String, fallback: Variant) -> Variant:
	if _has_property(object, property_name):
		return object.get(property_name)
	return fallback
