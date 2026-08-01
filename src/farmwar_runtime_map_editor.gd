## FarmWar Runtime Map Editor V5 - single script prototype
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
##   - Upward terrain triangle winding, opaque double-sided editor rendering,
##     palette-derived default ground, safety floor and terrain edge skirt.
##   - Runtime-editable surface palette: add, rename, recolor and remove surfaces.
##   - Manual grass brush using chunked MultiMesh (independent of surface color).
##   - Place existing FarmWar tree scenes.
##   - Place existing FarmWar ore scenes.
##   - Place giant-crop and wild-animal spawn points.
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
##   - Save generated map scene and editor data under user://maps/.
##
## Deliberately not implemented in this version:
##   - Building placement.
##   - Farmland editing (the left toolbar entry is disabled).
##   - Road curve editing UI (the Roads root and create_road_from_points API exist).
##   - Runtime loading of a previously saved editor session.

extends Node3D
class_name FarmWarRuntimeMapEditor


enum ToolMode {
	TERRAIN,
	SURFACE,
	GRASS,
	TREE,
	ORE,
	SPAWN,
	FARMLAND,
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
const TREE_FOREST_MANAGER_PATH = "res://src/tree_forest_manager.gd"
const FARM_INITIALIZER_PATH = "res://src/farm_init.gd"
const FAR_SCENERY_PATH = "res://src/environment/far_scenery_ring_3d.gd"
const CLOUD_SYSTEM_PATH = "res://worlds/shared/cloud_system.tscn"
const DAY_NIGHT_SYSTEM_PATH = "res://worlds/shared/day_night_system.tscn"
const MAP_ICON_FILE_NAME = "map_icon.png"
const SURFACE_PALETTE_FILE_NAME = "surface_palette.png"
const MAP_ICON_SIZE = 128
const FAR_SCENERY_GROUND_MARGIN = 768.0
const EDITOR_FAR_GROUND_ROOT_NAME = "_EditorGuaranteedFarGround"
const WILD_ANIMAL_GENERATOR_PATH = "res://src/wild_animal_generator.gd"
const RARE_RESOURCE_SPAWN_PATH = "res://buildings/nature/RareResourceSpawnPoint.tscn"
const SMALL_GRASS_PATH = "res://assets/environment/Grass_small.glb"
const TALL_GRASS_PATH = "res://assets/environment/Grass_tall.glb"

const CRESTON_PALETTE_PATH = "res://worlds/creston_town/creston_town_surface_palette.tres"
const REDPINE_PALETTE_PATH = "res://worlds/redpine_county/redpine_county_surface_palette.tres"

const TERRAIN_COLLISION_LAYER = 1
const BOUNDARY_COLLISION_LAYER = 2
const GRASS_CHUNK_SIZE = 32.0
const MAX_RAY_DISTANCE = 6000.0
const EDITOR_MARKER_META = &"farmwar_editor_visual_only"

const TREE_ASSETS = [
	{"label": "CottonWood", "path": "res://buildings/nature/CottonWood.tscn", "id": "cottonwood"},
	{"label": "Oak", "path": "res://buildings/nature/Oak.tscn", "id": "oak"},
	{"label": "Redcedar", "path": "res://buildings/nature/Redcedar.tscn", "id": "redcedar"},
]

const ORE_ASSETS = [
	{"label": "Iron Ore", "path": "res://items/IronOre.tscn", "id": "iron_ore"},
	{"label": "Coal Ore", "path": "res://items/CoalOre.tscn", "id": "coal_ore"},
	{"label": "Limestone Ore", "path": "res://items/LimestoneOre.tscn", "id": "limestone_ore"},
	{"label": "Copper Ore", "path": "res://items/CopperOre.tscn", "id": "copper_ore"},
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

@export_category("Far Scenery")
@export var force_guaranteed_far_ground = true
@export_range(500.0, 20000.0, 100.0) var editor_far_visibility_distance = 6000.0

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
var _manual_grass_root: Node3D
var _trees_root: Node3D
var _ores_root: Node3D
var _spawns_root: Node3D
var _tree_forest_manager: Node3D
var _far_scenery_ring: Node3D
var _terrain_baker: Node3D
var _terrain_foundation_root: Node3D
var _terrain_skirt_mesh: MeshInstance3D
var _ground_safety_mesh: MeshInstance3D
var _day_night_system: Node

# Terrain chunks and collision shapes keyed by Vector2i.
var _terrain_chunks: Dictionary = {}
var _terrain_collision_shapes: Dictionary = {}
var _collision_dirty_chunks: Dictionary = {}

# Manual grass data:
# {
#   "small": {"x:z": Array[Transform3D]},
#   "tall":  {"x:z": Array[Transform3D]}
# }
var _manual_grass = {
	"small": {},
	"tall": {},
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

# UI references.
var _ui_layer: CanvasLayer
var _ui_root: Control
var _bottom_content: HFlowContainer
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
var _boundary_warning_label: Label
var _boundary_warning_until_msec = 0
var _map_icon_image: Image
var _map_icon_texture: ImageTexture
var _map_icon_source_path = ""
var _tool_buttons: Dictionary = {}


func _ready() -> void:
	_rng.randomize()
	_undo_redo.max_steps = 100
	_build_editor_camera()
	_build_brush_preview()
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
	# The full-screen UI root must not consume viewport input. Individual
	# panels and buttons retain their normal mouse filters.
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ui_layer.add_child(_ui_root)

	_build_top_bar()
	_build_left_toolbar()
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

	var create_button = Button.new()
	create_button.text = "Create New Map"
	create_button.pressed.connect(_create_map_from_ui)
	primary_row.add_child(create_button)

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
	save_button.text = "Save Map"
	save_button.pressed.connect(save_current_map)
	package_row.add_child(save_button)

	_status_label = Label.new()
	_status_label.text = "Ready"
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	package_row.add_child(_status_label)

	_build_icon_file_dialog()


func _build_left_toolbar() -> void:
	var panel = PanelContainer.new()
	panel.name = "LeftToolbar"
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_top = 104.0
	panel.offset_left = 8.0
	panel.offset_right = 190.0
	panel.offset_bottom = -154.0
	_ui_root.add_child(panel)

	var column = VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)

	var heading = Label.new()
	heading.text = "TOOLS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(heading)

	var group = ButtonGroup.new()
	_add_tool_button(column, group, ToolMode.TERRAIN, "Terrain Height", "Raise, lower, smooth or flatten terrain")
	_add_tool_button(column, group, ToolMode.SURFACE, "Surface Paint", "Paint FarmWar surface IDs")
	_add_tool_button(column, group, ToolMode.GRASS, "Place Grass", "Manual MultiMesh grass brush")
	_add_tool_button(column, group, ToolMode.TREE, "Place Trees", "Place complete harvestable tree scenes")
	_add_tool_button(column, group, ToolMode.ORE, "Place Ores", "Place complete harvestable ore scenes")
	_add_tool_button(column, group, ToolMode.SPAWN, "Place Spawn Points", "Giant crop or wild animal generators")

	var farmland_button = Button.new()
	farmland_button.text = "Farmland (later)"
	farmland_button.disabled = true
	farmland_button.tooltip_text = "Farmland editing is reserved but intentionally not implemented yet."
	column.add_child(farmland_button)
	_tool_buttons[ToolMode.FARMLAND] = farmland_button

	(_tool_buttons[ToolMode.TERRAIN] as Button).button_pressed = true

	var help = Label.new()
	help.text = "LMB: use brush\nShift+LMB: lower / erase\nRMB: look around\nWASD + Q/E: move\nMouse wheel: camera speed\n[ / ]: brush radius\nCtrl+Z / Cmd+Z: undo\nCtrl+Y / Shift+Cmd+Z: redo\nCtrl/Cmd+S: save"
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


func _build_bottom_dock() -> void:
	var panel = PanelContainer.new()
	panel.name = "BottomDock"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_left = 8.0
	panel.offset_right = -8.0
	panel.offset_top = -146.0
	panel.offset_bottom = -8.0
	_ui_root.add_child(panel)

	var layout = VBoxContainer.new()
	panel.add_child(layout)

	var header = HBoxContainer.new()
	layout.add_child(header)

	_tool_title_label = Label.new()
	_tool_title_label.text = "Terrain Height"
	_tool_title_label.custom_minimum_size.x = 180.0
	header.add_child(_tool_title_label)

	_radius_label = Label.new()
	_radius_label.text = "Radius: %.1f m" % _brush_radius
	header.add_child(_radius_label)

	var radius_slider = HSlider.new()
	radius_slider.min_value = 1.0
	radius_slider.max_value = 64.0
	radius_slider.step = 0.5
	radius_slider.value = _brush_radius
	radius_slider.custom_minimum_size.x = 180.0
	radius_slider.value_changed.connect(_on_radius_changed)
	header.add_child(radius_slider)

	_strength_label = Label.new()
	_strength_label.text = "Strength: %.2f" % _brush_strength
	header.add_child(_strength_label)

	var strength_slider = HSlider.new()
	strength_slider.min_value = 0.05
	strength_slider.max_value = 12.0
	strength_slider.step = 0.05
	strength_slider.value = _brush_strength
	strength_slider.custom_minimum_size.x = 180.0
	strength_slider.value_changed.connect(_on_strength_changed)
	header.add_child(strength_slider)

	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	_bottom_content = HFlowContainer.new()
	_bottom_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bottom_content.add_theme_constant_override("h_separation", 8)
	_bottom_content.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_bottom_content)


func _refresh_bottom_dock() -> void:
	if _bottom_content == null:
		return
	for child in _bottom_content.get_children():
		child.queue_free()

	match _tool_mode:
		ToolMode.TERRAIN:
			_tool_title_label.text = "Terrain Height"
			_add_height_mode_buttons()
		ToolMode.SURFACE:
			_tool_title_label.text = "Surface Paint"
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
		_:
			_tool_title_label.text = "Unavailable"


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
	hint.custom_minimum_size.x = 360.0
	_bottom_content.add_child(hint)


func _add_grass_buttons() -> void:
	var group = ButtonGroup.new()
	for entry in [
		{"label": "Small Grass", "species": "small"},
		{"label": "Tall Grass", "species": "tall"},
	]:
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
	hint.text = "Grass is stored as manually painted points and rebuilt into 32 m MultiMesh chunks. Shift+LMB erases."
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

	var hint = Label.new()
	hint.text = "One generator is placed per click. Shift+LMB removes generators inside the brush."
	_bottom_content.add_child(hint)


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
	_tool_mode = mode
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
				_begin_stroke()
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
			if key_event.shift_pressed:
				_redo_last_action()
			else:
				_undo_last_action()
			get_viewport().set_input_as_handled()
			return
		if command_pressed and key_event.keycode == KEY_Y:
			_end_stroke()
			_redo_last_action()
			get_viewport().set_input_as_handled()
			return
		if command_pressed and key_event.keycode == KEY_S:
			save_current_map()
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
			KEY_3: _press_tool_shortcut(ToolMode.GRASS)
			KEY_4: _press_tool_shortcut(ToolMode.TREE)
			KEY_5: _press_tool_shortcut(ToolMode.ORE)
			KEY_6: _press_tool_shortcut(ToolMode.SPAWN)


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


func _physics_process(delta: float) -> void:
	if _map_root == null or _editor_camera == null:
		_brush_preview.visible = false
		return

	_latest_hit = _raycast_terrain()
	if _latest_hit.is_empty():
		_brush_preview.visible = false
		return

	var hit_position = _latest_hit.get("position", Vector3.ZERO) as Vector3
	_update_contact_brush(hit_position)

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
		ToolMode.SURFACE:
			_commit_surface_stroke()
		ToolMode.GRASS:
			_commit_grass_stroke()
		ToolMode.TREE, ToolMode.ORE, ToolMode.SPAWN:
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
	_brush_preview.visible = true


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

	_manual_grass = {"small": {}, "tall": {}}
	_grass_generated_nodes.clear()
	_terrain_chunks.clear()
	_terrain_collision_shapes.clear()
	_collision_dirty_chunks.clear()
	_next_object_id = 1
	_next_spawn_id = 1

	_create_terrain_material()

	_map_root = Node3D.new()
	_map_root.name = _map_id.validate_node_name()
	_map_root.set_meta("farmwar_map_format_version", 2)
	_map_root.set_meta("farmwar_map_id", _map_id)
	_map_root.set_meta("farmwar_display_name", _display_name)
	_map_root.set_meta("farmwar_map_version", _map_version)
	_map_root.set_meta("farmwar_map_name", _map_id)
	_map_root.set_meta("farmwar_map_size", _map_size)
	_map_root.set_meta("farmwar_editor_generated", true)
	add_child(_map_root)

	_create_environment_skeleton()
	_create_map_content_roots()
	_create_boundary_walls()
	_create_terrain_chunks()
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

	# Use an editor/runtime copy with culling disabled. Correct winding is still
	# generated below, but this prevents a terrain surface from appearing
	# transparent if a future mesh edit accidentally flips one triangle.
	var runtime_shader = Shader.new()
	var shader_code = source_shader.code
	if shader_code.contains("cull_back"):
		shader_code = shader_code.replace("cull_back", "cull_disabled")
	runtime_shader.code = shader_code
	_terrain_material.shader = runtime_shader
	_terrain_material.set_shader_parameter("surface_mask", _surface_mask_texture)
	_terrain_material.set_shader_parameter("surface_palette", _surface_palette_lookup)
	_terrain_material.set_shader_parameter("terrain_origin", _terrain_origin)
	_terrain_material.set_shader_parameter("terrain_size", _map_size)


func _create_environment_skeleton() -> void:
	var sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.945, 0.816)
	sun.shadow_enabled = true
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
		_set_property_if_present(_day_night_system, "initial_hour", 12.0)
		_day_night_system.process_mode = Node.PROCESS_MODE_DISABLED
		_map_root.add_child(_day_night_system)


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
	_manual_grass_root = _new_child_node3d(_map_root, "ManualGrass")
	_trees_root = _new_child_node3d(_map_root, "Trees")
	_ores_root = _new_child_node3d(_map_root, "Ores")
	_spawns_root = _new_child_node3d(_map_root, "SpawnPoints")

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
			mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
		if indices.size() >= 3:
			var a = vertices[indices[0]]
			var b = vertices[indices[1]]
			var c = vertices[indices[2]]
			var geometric_normal = (b - a).cross(c - a).normalized()
			if geometric_normal.dot(Vector3.UP) <= 0.0:
				push_error(
					"FarmWar map editor: terrain triangle winding faces downward."
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

			# With +X to the right and +Z toward the bottom of the map,
			# i0 -> i2 -> i1 produces an upward-facing geometric normal.
			indices[write_index] = i0
			indices[write_index + 1] = i2
			indices[write_index + 2] = i1
			indices[write_index + 3] = i1
			indices[write_index + 4] = i2
			indices[write_index + 5] = i3
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
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

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
		_rebuild_chunks_for_sample_rect(bounds)
		if _rect_touches_terrain_edge(bounds):
			_rebuild_terrain_skirt()


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

func _apply_grass_brush(center: Vector3, delta: float) -> void:
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
		var scale_range = Vector2(0.85, 1.15) if _selected_grass_species == "small" else Vector2(0.85, 1.20)
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

	var source_path = SMALL_GRASS_PATH if species == "small" else TALL_GRASS_PATH
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
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.visibility_range_end = 100.0 if species == "small" else 120.0
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


func _erase_nodes_in_radius(category_root: Node3D, center: Vector3, radius: float) -> void:
	var center_xz = Vector2(center.x, center.z)
	var erased = 0
	for child in category_root.get_children():
		if not child is Node3D:
			continue
		var node = child as Node3D
		var node_xz = Vector2(node.position.x, node.position.z)
		if node_xz.distance_to(center_xz) <= radius:
			_stroke_removed_objects.append(_serialize_editor_object(node))
			category_root.remove_child(node)
			node.free()
			erased += 1
	if erased > 0:
		_rebuild_resource_multimeshes_deferred()
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

	if _selected_spawn_kind == "wild_animal":
		_place_wild_animal_spawn(center)
	else:
		_place_giant_crop_spawn(center)
	_stroke_placed_once = true


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
		"properties": {},
	}
	node.set_meta("map_editor_uuid", record["uuid"])

	var properties = record["properties"] as Dictionary
	for property_name in [
		"tree_id",
		"resource_id",
		"spawn_point_id",
		"generator_id",
		"allowed_resource_ids",
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

		if category == "spawn" and spawn_kind == "wild_animal":
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

		if category == "spawn":
			node.process_mode = Node.PROCESS_MODE_DISABLED
			if spawn_kind == "wild_animal":
				_add_spawn_editor_marker(node, Color(0.2, 0.75, 1.0, 1.0))
			else:
				_add_spawn_editor_marker(node, Color(1.0, 0.45, 0.1, 1.0))


func _category_root_for_record(category: String) -> Node3D:
	match category:
		"tree":
			return _trees_root
		"ore":
			return _ores_root
		_:
			return _spawns_root


func _find_editor_object_by_uuid(uuid: String) -> Node3D:
	if uuid.is_empty():
		return null
	for root in [_trees_root, _ores_root, _spawns_root]:
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


# The current toolbar intentionally has no road button, but newly generated maps
# include the same Roads root and RoadPath3D script used by FarmWar. This API can
# be connected to a future curve-editing tool without changing the map format.
func create_road_from_points(points: PackedVector3Array, road_type: int = 1) -> Path3D:
	if _roads_root == null or points.size() < 2:
		return null
	var road_script = _load_resource_or_null(ROAD_SCRIPT_PATH) as Script
	if road_script == null:
		return null
	var road = Path3D.new()
	road.name = "RoadPath3D_%03d" % (_roads_root.get_child_count() + 1)
	road.set_script(road_script)
	var curve = Curve3D.new()
	for point in points:
		curve.add_point(point)
	road.curve = curve
	_roads_root.add_child(road)
	_set_property_if_present(road, "road_type", road_type)
	return road


# -----------------------------------------------------------------------------
# Save the generated map and authoritative editor data
# -----------------------------------------------------------------------------

func save_current_map() -> void:
	if _map_root == null:
		_set_status("No map to save")
		return

	_end_stroke()
	_sync_package_fields_from_ui()
	var folder = "%s/%s" % [map_save_root.trim_suffix("/"), _map_id]
	var absolute_folder = ProjectSettings.globalize_path(folder)
	var directory_error = DirAccess.make_dir_recursive_absolute(absolute_folder)
	if directory_error != OK:
		_set_status("Could not create save directory (error %d)" % directory_error)
		return

	_update_map_metadata_before_save()
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
	_map_root.set_script(previous_script)

	if pack_error != OK:
		_set_status("Could not pack map scene (error %d)" % pack_error)
		return
	if save_error != OK:
		_set_status("Could not save map scene (error %d)" % save_error)
		return
	_saved_undo_version = _undo_redo.get_version()
	_set_status("Saved: %s" % scene_path)


func _update_map_metadata_before_save() -> void:
	_map_root.set_meta("farmwar_map_format_version", 2)
	_map_root.set_meta("farmwar_map_id", _map_id)
	_map_root.set_meta("farmwar_display_name", _display_name)
	_map_root.set_meta("farmwar_map_version", _map_version)
	_map_root.set_meta("farmwar_map_name", _map_id)
	_map_root.set_meta("farmwar_map_size", _map_size)
	_map_root.set_meta("terrain_origin", _terrain_origin)
	_map_root.set_meta("terrain_vertex_spacing", vertex_spacing)
	_map_root.set_meta("terrain_sample_width", _sample_width)
	_map_root.set_meta("terrain_sample_depth", _sample_depth)
	_map_root.set_meta("terrain_height_samples", _height_samples)
	_map_root.set_meta("surface_mask_image", _surface_mask_image)
	_map_root.set_meta("surface_palette_entries", _surface_entries.duplicate(true))
	_map_root.set_meta("surface_default_id", _get_default_surface_id())
	_map_root.set_meta("manual_grass", _manual_grass)
	_map_root.set_meta("integrated_systems", [
		"explicit_ground_static_body",
		"dynamic_height_terrain",
		"terrain_foundation_and_skirt",
		"surface_mask",
		"manual_grass_multimesh",
		"roads",
		"day_night_gameplay_only",
		"cloud_system",
		"size_aware_far_scenery",
		"tree_resource_multimesh",
		"giant_crop_spawns",
		"wild_animal_spawns",
	])


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

	var icon_saved = _save_map_icon(folder)
	var template_name = (
		"redpine_county"
		if _template_mode == TemplateMode.REDPINE_COUNTY
		else "creston_town"
	)
	var manifest = {
		"format_version": 2,
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
			"tree_count": _trees_root.get_child_count(),
			"ore_count": _ores_root.get_child_count(),
			"spawn_count": _spawns_root.get_child_count(),
		},
		"features": {
			"building_placement_enabled": false,
			"farmland_editor_enabled": false,
			"day_night_enabled_in_gameplay": is_instance_valid(_day_night_system),
			"size_aware_far_scenery": true,
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
	_ground_safety_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_ground_body.add_child(_ground_safety_mesh)
	_update_ground_safety_color()

	_terrain_skirt_mesh = MeshInstance3D.new()
	_terrain_skirt_mesh.name = "TerrainEdgeSkirt"
	_terrain_skirt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
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
