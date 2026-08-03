extends Control
class_name SinglePlayerWorldPage

signal back_requested
signal map_activated(map_definition: Dictionary)

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_ACCENT := Color("#54D6A2")

var map_list: ItemList
var description_label: Label
var enter_hint_label: Label
var maps: Array[Dictionary] = []


func _ready() -> void:
	_build_interface()
	_refresh_maps()


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 80)
	margin.add_theme_constant_override("margin_top", 56)
	margin.add_theme_constant_override("margin_right", 80)
	margin.add_theme_constant_override("margin_bottom", 56)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	var title := Label.new()
	title.text = "单人游戏 · 选择地图"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)
	enter_hint_label = Label.new()
	enter_hint_label.text = "单击查看信息；双击兼容地图进入游戏。"
	enter_hint_label.add_theme_font_size_override("font_size", 20)
	enter_hint_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(enter_hint_label)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	map_list = ItemList.new()
	map_list.custom_minimum_size = Vector2(580, 0)
	map_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_list.allow_reselect = true
	map_list.fixed_icon_size = Vector2i(96, 96)
	map_list.icon_mode = ItemList.ICON_MODE_LEFT
	map_list.same_column_width = false
	map_list.item_selected.connect(_on_map_selected)
	map_list.item_activated.connect(_on_map_activated)
	body.add_child(map_list)
	var details_panel := PanelContainer.new()
	details_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL))
	body.add_child(details_panel)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 14)
	details_panel.add_child(details)
	var heading := Label.new()
	heading.text = "地图信息"
	heading.add_theme_font_size_override("font_size", 28)
	heading.add_theme_color_override("font_color", COLOR_TEXT)
	details.add_child(heading)
	description_label = Label.new()
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.add_theme_font_size_override("font_size", 20)
	description_label.add_theme_color_override("font_color", COLOR_MUTED)
	details.add_child(description_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	root.add_child(footer)
	var refresh_button := _make_button("刷新地图列表")
	refresh_button.pressed.connect(_refresh_maps)
	footer.add_child(refresh_button)
	var back_button := _make_button("返回")
	back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back_button)


func _refresh_maps() -> void:
	maps = GameMapRegistry.list_singleplayer_maps()
	map_list.clear()
	for definition: Dictionary in maps:
		var label := "%s\n%s" % [
			str(definition.get("display_name", "未命名地图")),
			"%d × %d" % [
				(definition.get("size", Vector2i.ZERO) as Vector2i).x,
				(definition.get("size", Vector2i.ZERO) as Vector2i).y,
			],
		]
		if not bool(definition.get("is_compatible", false)):
			label += " · 需要补全基础系统"
		var index := map_list.add_item(label, _load_icon(str(definition.get("icon_path", ""))))
		map_list.set_item_disabled(index, not bool(definition.get("is_compatible", false)))
	if maps.is_empty():
		description_label.text = "尚未发现可用地图。"
	else:
		map_list.select(0)
		_on_map_selected(0)


func _on_map_selected(index: int) -> void:
	if index < 0 or index >= maps.size():
		return
	var definition := maps[index]
	var size := definition.get("size", Vector2i.ZERO) as Vector2i
	var errors: Array = definition.get("validation_errors", []) as Array
	description_label.text = "%s\n地图 ID：%s\n尺寸：%d × %d\n来源：%s" % [
		str(definition.get("display_name", "未命名地图")),
		str(definition.get("map_id", "")), size.x, size.y,
		_map_source_text(str(definition.get("source", ""))),
	]
	if not errors.is_empty():
		description_label.text += "\n\n暂不可进入：\n- " + "\n- ".join(errors)


func _map_source_text(source: String) -> String:
	match source:
		"builtin":
			return "内置地图"
		"portable":
			return "手动安装地图（可执行文件旁 maps）"
		"runtime_editor":
			return "本地编辑器存档（需导出）"
		_:
			return source if not source.is_empty() else "未知来源"


func _on_map_activated(index: int) -> void:
	if index < 0 or index >= maps.size():
		return
	var definition := maps[index]
	if not bool(definition.get("is_compatible", false)):
		return
	map_activated.emit(definition.duplicate(true))


func _load_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not path.begins_with("res://"):
		var image := Image.load_from_file(path)
		return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	return load(path) as Texture2D


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(210, 48)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL))
	button.add_theme_stylebox_override("hover", _style_box(Color("#C56D31")))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_ACCENT))
	return button


func _style_box(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style
