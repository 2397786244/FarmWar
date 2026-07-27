extends CanvasLayer

const DEFAULT_TIPS_PATH := "res://data/loading_tips.json"
const DEFAULT_IMAGES_DIRECTORY := "res://assets/loading/creston_town"

var _root: Control
var _background: TextureRect
var _map_label: Label
var _status_label: Label
var _tip_label: Label
var _progress_bar: ProgressBar
var _active := false
var _current_map_name := ""


func _ready() -> void:
	layer = 1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	_root.visible = false


func begin_loading(
	map_name: String,
	images_directory := DEFAULT_IMAGES_DIRECTORY,
	tips_path := DEFAULT_TIPS_PATH
) -> void:
	_active = true
	_current_map_name = map_name
	_root.modulate = Color.WHITE
	_root.visible = true
	_map_label.text = map_name
	_tip_label.text = _pick_random_tip(tips_path)
	_set_random_background(images_directory)
	update_progress(0.0, "正在准备地图")


func ensure_loading(
	map_name: String,
	images_directory := DEFAULT_IMAGES_DIRECTORY,
	tips_path := DEFAULT_TIPS_PATH
) -> void:
	if not _active:
		begin_loading(map_name, images_directory, tips_path)


func update_progress(progress: float, status: String) -> void:
	if not _active:
		return
	var percent := clampf(progress, 0.0, 1.0) * 100.0
	_progress_bar.value = percent
	_status_label.text = "%s  %d%%" % [status, roundi(percent)]


func finish_loading() -> void:
	if not _active:
		return
	update_progress(1.0, "地图准备完成")
	await get_tree().create_timer(0.2, true, false, true).timeout
	var fade := create_tween()
	fade.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	fade.tween_property(_root, "modulate:a", 0.0, 0.25)
	await fade.finished
	_root.visible = false
	_root.modulate = Color.WHITE
	_active = false


func is_loading() -> bool:
	return _active


func _build_interface() -> void:
	_root = Control.new()
	_root.name = "MapLoadingRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var fallback := ColorRect.new()
	fallback.color = Color("#263D2E")
	fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(fallback)

	_background = TextureRect.new()
	_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_background)

	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.03, 0.025, 0.52)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.anchor_left = 0.08
	content.anchor_top = 0.68
	content.anchor_right = 0.92
	content.anchor_bottom = 0.92
	content.add_theme_constant_override("separation", 12)
	_root.add_child(content)

	_map_label = Label.new()
	_map_label.add_theme_font_size_override("font_size", 32)
	_map_label.add_theme_color_override("font_color", Color.WHITE)
	content.add_child(_map_label)

	_tip_label = Label.new()
	_tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tip_label.add_theme_font_size_override("font_size", 18)
	_tip_label.add_theme_color_override("font_color", Color("#EAF1E8"))
	content.add_child(_tip_label)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", Color("#D8E2D5"))
	content.add_child(_status_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0.0, 18.0)
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false
	var background_style := StyleBoxFlat.new()
	background_style.bg_color = Color(0.02, 0.03, 0.025, 0.78)
	background_style.corner_radius_top_left = 3
	background_style.corner_radius_top_right = 3
	background_style.corner_radius_bottom_left = 3
	background_style.corner_radius_bottom_right = 3
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = Color("#E6B94D")
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	_progress_bar.add_theme_stylebox_override("background", background_style)
	_progress_bar.add_theme_stylebox_override("fill", fill_style)
	content.add_child(_progress_bar)


func _set_random_background(directory: String) -> void:
	_background.texture = null
	if not DirAccess.dir_exists_absolute(directory):
		return
	var image_paths := PackedStringArray()
	for file_name in DirAccess.get_files_at(directory):
		var extension := file_name.get_extension().to_lower()
		if extension in ["png", "jpg", "jpeg", "webp"]:
			image_paths.append(directory.path_join(file_name))
	if image_paths.is_empty():
		return
	var selected_path := image_paths[randi_range(0, image_paths.size() - 1)]
	_background.texture = load(selected_path) as Texture2D


func _pick_random_tip(tips_path: String) -> String:
	var tips: Array = []
	if FileAccess.file_exists(tips_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(tips_path))
		if parsed is Array:
			tips = parsed
	if tips.is_empty():
		return "提示：合理分配背包与队伍库存中的原材料。"
	return str(tips[randi_range(0, tips.size() - 1)])
