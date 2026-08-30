extends Control
class_name SinglePlayerWorldPage

signal back_requested
signal world_requested(world_id: String)

const LOADOUT_SCENE := preload("res://ui/MultiplayerLoadoutSelect.tscn")
const COLOR_BG := Color("#15171A")
const COLOR_PANEL := Color("#1D2024")
const COLOR_CONTROL := Color("#272B30")
const COLOR_HOVER := Color("#32373D")
const COLOR_SELECTED := Color("#3C4249")
const COLOR_BORDER := Color("#4B5159")
const COLOR_TEXT := Color("#F0F1F2")
const COLOR_MUTED := Color("#A4A8AD")

var world_name_edit: LineEdit
var map_list: ItemList
var create_button: Button
var save_list: VBoxContainer
var status_label: Label
var delete_dialog: ConfirmationDialog
var maps: Array[Dictionary] = []
var pending_world_config: Dictionary = {}
var pending_delete_world_id := ""
var loadout_ui: MultiplayerLoadoutSelect
var hero_names: Dictionary = {}
var primary_names: Dictionary = {}
var special_names: Dictionary = {}


func _ready() -> void:
	_load_display_names()
	_build_interface()
	_refresh_maps()
	_refresh_worlds()


func show_status(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message


func _build_interface() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var title := Label.new()
	title.text = "单人世界"
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var back_button := _make_button("返回", 110)
	back_button.pressed.connect(func() -> void: back_requested.emit())
	header.add_child(back_button)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	root.add_child(columns)
	columns.add_child(_build_create_column())
	columns.add_child(_build_saved_column())
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.custom_minimum_size.y = 26
	status_label.add_theme_font_size_override("font_size", 17)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(status_label)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "删除存档"
	delete_dialog.dialog_text = "确定删除这个单人存档？"
	delete_dialog.ok_button_text = "删除"
	delete_dialog.cancel_button_text = "取消"
	delete_dialog.confirmed.connect(_confirm_delete_world)
	add_child(delete_dialog)


func _build_create_column() -> Control:
	var panel := PanelContainer.new()
	panel.name = "CreateWorldPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 0.92
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, COLOR_BORDER, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	box.add_child(_section_title("创建新世界"))
	world_name_edit = LineEdit.new()
	world_name_edit.name = "WorldNameEdit"
	world_name_edit.placeholder_text = "世界名称"
	world_name_edit.max_length = 40
	world_name_edit.custom_minimum_size.y = 46
	world_name_edit.add_theme_font_size_override("font_size", 19)
	world_name_edit.add_theme_color_override("font_color", COLOR_TEXT)
	world_name_edit.add_theme_color_override("font_placeholder_color", COLOR_MUTED)
	world_name_edit.add_theme_stylebox_override("normal", _style_box(COLOR_CONTROL, COLOR_BORDER, 1))
	world_name_edit.add_theme_stylebox_override("focus", _style_box(COLOR_HOVER, COLOR_BORDER, 1))
	world_name_edit.text_changed.connect(func(_text: String) -> void: _refresh_create_enabled())
	box.add_child(world_name_edit)
	var map_scroll := ScrollContainer.new()
	map_scroll.name = "MapScroll"
	map_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(map_scroll)
	map_list = ItemList.new()
	map_list.name = "MapList"
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.custom_minimum_size.y = 260
	map_list.fixed_icon_size = Vector2i(72, 72)
	map_list.icon_mode = ItemList.ICON_MODE_LEFT
	map_list.same_column_width = false
	map_list.add_theme_font_size_override("font_size", 19)
	map_list.add_theme_color_override("font_color", COLOR_TEXT)
	map_list.add_theme_stylebox_override("panel", _style_box(COLOR_CONTROL, COLOR_BORDER, 1))
	map_list.add_theme_stylebox_override("selected", _style_box(COLOR_SELECTED, COLOR_BORDER, 1))
	map_list.add_theme_stylebox_override("selected_focus", _style_box(COLOR_SELECTED, COLOR_BORDER, 1))
	map_list.add_theme_stylebox_override("hovered", _style_box(COLOR_HOVER, COLOR_BORDER, 1))
	map_list.item_selected.connect(func(_index: int) -> void: _refresh_create_enabled())
	map_scroll.add_child(map_list)
	create_button = _make_button("创建并选择角色", 230)
	create_button.name = "CreateWorldButton"
	create_button.pressed.connect(_begin_create_world)
	box.add_child(create_button)
	return panel


func _build_saved_column() -> Control:
	var panel := PanelContainer.new()
	panel.name = "SavedWorldPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio = 1.08
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, COLOR_BORDER, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	box.add_child(_section_title("已有存档"))
	var scroll := ScrollContainer.new()
	scroll.name = "SavedWorldScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	save_list = VBoxContainer.new()
	save_list.name = "SavedWorldList"
	save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_list.add_theme_constant_override("separation", 10)
	scroll.add_child(save_list)
	return panel


func _refresh_maps() -> void:
	maps = GameMapRegistry.list_singleplayer_maps()
	map_list.clear()
	for definition: Dictionary in maps:
		var size := definition.get("size", Vector2i.ZERO) as Vector2i
		var label := "%s\n%d × %d" % [
			str(definition.get("display_name", "未命名地图")), size.x, size.y,
		]
		var index := map_list.add_item(label, _load_icon(str(definition.get("icon_path", ""))))
		map_list.set_item_disabled(index, not bool(definition.get("is_compatible", false)))
	if not maps.is_empty():
		for index in range(maps.size()):
			if bool(maps[index].get("is_compatible", false)):
				map_list.select(index)
				break
	_refresh_create_enabled()


func _refresh_worlds() -> void:
	_clear_container(save_list)
	var worlds := SinglePlayerWorldStorage.list_worlds()
	if worlds.is_empty():
		var empty := Label.new()
		empty.text = "暂无存档"
		empty.add_theme_font_size_override("font_size", 18)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		save_list.add_child(empty)
		return
	for world: Dictionary in worlds:
		save_list.add_child(_make_world_card(world))


func _make_world_card(world: Dictionary) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_CONTROL, COLOR_BORDER, 1))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var summary := VBoxContainer.new()
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.add_theme_constant_override("separation", 4)
	row.add_child(summary)
	var title := Label.new()
	title.text = str(world.get("display_name", "未命名世界"))
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	summary.add_child(title)
	var lock := SinglePlayerWorldStorage.get_loadout_lock(world)
	var hero_id := str(lock.get("hero_id", ""))
	var meta := Label.new()
	meta.text = "%s  ·  %s  ·  %s" % [
		str(world.get("map_name", world.get("map_id", ""))),
		str(hero_names.get(hero_id, hero_id)),
		_format_saved_time(int(world.get("updated_unix", 0))),
	]
	meta.add_theme_font_size_override("font_size", 16)
	meta.add_theme_color_override("font_color", COLOR_MUTED)
	summary.add_child(meta)
	var world_status := Label.new()
	world_status.text = "%s  ·  %s" % [
		_format_world_clock(world),
		_format_saved_weather(world),
	]
	world_status.add_theme_font_size_override("font_size", 15)
	world_status.add_theme_color_override("font_color", COLOR_MUTED)
	summary.add_child(world_status)
	var items := Label.new()
	items.text = "%s  /  %s" % [
		_join_loadout_names(lock.get("primary_weapon_ids", []), primary_names),
		_join_loadout_names(lock.get("special_tool_ids", []), special_names),
	]
	items.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	items.add_theme_font_size_override("font_size", 15)
	items.add_theme_color_override("font_color", COLOR_MUTED)
	summary.add_child(items)
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	row.add_child(actions)
	var enter_button := _make_button("进入", 92)
	enter_button.pressed.connect(_enter_world.bind(str(world.get("world_id", ""))))
	actions.add_child(enter_button)
	var delete_button := _make_button("删除", 92)
	delete_button.pressed.connect(_ask_delete_world.bind(str(world.get("world_id", ""))))
	actions.add_child(delete_button)
	return panel


func _refresh_create_enabled() -> void:
	if not is_instance_valid(create_button):
		return
	var selected := map_list.get_selected_items() if is_instance_valid(map_list) else PackedInt32Array()
	create_button.disabled = world_name_edit.text.strip_edges().is_empty() or selected.is_empty()


func _begin_create_world() -> void:
	var display_name := world_name_edit.text.strip_edges()
	var selected := map_list.get_selected_items()
	if display_name.is_empty():
		show_status("请输入世界名称。")
		return
	if selected.is_empty() or selected[0] < 0 or selected[0] >= maps.size():
		show_status("请选择地图。")
		return
	var definition := maps[selected[0]]
	if not bool(definition.get("is_compatible", false)):
		show_status("该地图不可用。")
		return
	var validation := GameMapRegistry.validate_map_definition(definition)
	if not bool(validation.get("is_compatible", false)):
		show_status("该地图不可用。")
		return
	definition = validation
	pending_world_config = {
		"display_name": display_name.left(40),
		"map_id": str(definition.get("map_id", "")),
		"map_name": str(definition.get("display_name", "")),
		"map_icon_path": str(definition.get("icon_path", "")),
		"map_scene_path": str(definition.get("scene_path", "")),
		"loading_images_directory": str(definition.get("loading_images_directory", "")),
		"map_version": str(definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(definition.get("map_hash", "")),
		"map_source": str(definition.get("source", "builtin")),
	}
	_open_loadout()


func _open_loadout() -> void:
	if is_instance_valid(loadout_ui):
		return
	loadout_ui = LOADOUT_SCENE.instantiate() as MultiplayerLoadoutSelect
	loadout_ui.presentation_mode = "singleplayer"
	loadout_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_ui.z_index = 20
	loadout_ui.ready_submitted.connect(_complete_create_world)
	loadout_ui.back_requested.connect(_cancel_loadout)
	add_child(loadout_ui)


func _complete_create_world(selection: Dictionary) -> void:
	var created := SinglePlayerWorldStorage.create_world(pending_world_config, selection)
	if created.is_empty():
		show_status("存档创建失败。")
		if is_instance_valid(loadout_ui):
			loadout_ui.set_player_ready_state(false)
		return
	var world_id := str(created.get("world_id", ""))
	pending_world_config.clear()
	if is_instance_valid(loadout_ui):
		loadout_ui.queue_free()
	loadout_ui = null
	world_requested.emit(world_id)


func _cancel_loadout() -> void:
	pending_world_config.clear()
	if is_instance_valid(loadout_ui):
		loadout_ui.queue_free()
	loadout_ui = null


func _enter_world(world_id: String) -> void:
	var world := SinglePlayerWorldStorage.load_world(world_id)
	if world.is_empty():
		show_status("存档不存在或已损坏。")
		_refresh_worlds()
		return
	var validation := GameMapRegistry.validate_world_map(world)
	if not bool(validation.get("valid", false)):
		show_status(str(validation.get("error", "存档地图不可用。")))
		return
	world_requested.emit(world_id)


func _ask_delete_world(world_id: String) -> void:
	pending_delete_world_id = world_id
	delete_dialog.popup_centered(Vector2i(420, 180))


func _confirm_delete_world() -> void:
	if pending_delete_world_id.is_empty():
		return
	var deleted := SinglePlayerWorldStorage.delete_world(pending_delete_world_id)
	pending_delete_world_id = ""
	show_status("存档已删除。" if deleted else "删除存档失败。")
	_refresh_worlds()


func _load_display_names() -> void:
	for entry: Dictionary in _read_array("res://data/hero_definitions.json", "heroes"):
		hero_names[str(entry.get("id", ""))] = str(entry.get("name", entry.get("id", "")))
	for entry: Dictionary in _read_array("res://data/primary_weapon_definitions.json", "weapons"):
		primary_names[str(entry.get("id", ""))] = str(entry.get("name", entry.get("id", "")))
	for entry: Dictionary in _read_array("res://data/special_tool_definitions.json", "tools"):
		special_names[str(entry.get("id", ""))] = str(entry.get("name", entry.get("id", "")))


func _read_array(path: String, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	var value: Variant = JSON.parse_string(file.get_as_text())
	if not value is Dictionary or not (value as Dictionary).get(key, []) is Array:
		return result
	for entry: Variant in (value as Dictionary).get(key, []):
		if entry is Dictionary:
			result.append(entry as Dictionary)
	return result


func _join_loadout_names(value: Variant, names: Dictionary) -> String:
	if not value is Array:
		return ""
	var result: Array[String] = []
	for item: Variant in value as Array:
		var item_id := str(item)
		result.append(str(names.get(item_id, item_id)))
	return "、".join(result)


func _format_saved_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "--"
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [
		date.get("year", 0), date.get("month", 0), date.get("day", 0),
		date.get("hour", 0), date.get("minute", 0),
	]


func _format_world_clock(world: Dictionary) -> String:
	var clock := WorldPersistence.get_saved_world_clock_state(world) \
		if is_instance_valid(WorldPersistence) and WorldPersistence.has_method("get_saved_world_clock_state") else {}
	var elapsed_seconds := float(clock.get("elapsed_seconds", world.get("world_elapsed_seconds", 0.0)))
	var total_hours := float(clock.get("total_hours", 8.0 + elapsed_seconds / 1440.0 * 24.0))
	var day_index := int(clock.get(
		"day_index", floori(total_hours / 24.0)
	))
	var hour := fposmod(float(clock.get("hour", total_hours)), 24.0)
	var total_minutes := clampi(roundi(hour * 60.0), 0, 1439)
	return "第%d天 %02d:%02d" % [day_index + 1, int(total_minutes / 60), total_minutes % 60]


func _format_saved_weather(world: Dictionary) -> String:
	var world_state_value: Variant = world.get("world_state", {})
	var world_state: Dictionary = world_state_value as Dictionary if world_state_value is Dictionary else {}
	var weather_value: Variant = world_state.get("weather", {})
	var weather: Dictionary = weather_value as Dictionary if weather_value is Dictionary else {}
	var weather_type := str(weather.get("current_weather_type", weather.get("weather_type", "")))
	if weather_type.is_empty():
		var clock := WorldPersistence.get_saved_world_clock_state(world) \
			if is_instance_valid(WorldPersistence) and WorldPersistence.has_method("get_saved_world_clock_state") else {}
		var day_index := int(clock.get("day_index", maxi(0, int(world.get("game_day", 1)) - 1)))
		var days_value: Variant = weather.get("forecast_days", [])
		if days_value is Array:
			for day_value: Variant in days_value:
				if day_value is Dictionary and int((day_value as Dictionary).get("day_index", -1)) == day_index:
					weather_type = str((day_value as Dictionary).get("weather_type", ""))
	return "晴天" if weather_type == "clear" else "雨天" if weather_type == "rain" else "日食" if weather_type == "eclipse" else "天气未知"


func _section_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	return label


func _make_button(text: String, width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(width, 44)
	button.add_theme_font_size_override("font_size", 18)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_CONTROL, COLOR_BORDER, 1))
	button.add_theme_stylebox_override("hover", _style_box(COLOR_HOVER, COLOR_BORDER, 1))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_SELECTED, COLOR_BORDER, 1))
	button.add_theme_stylebox_override("disabled", _style_box(COLOR_PANEL, COLOR_BORDER, 1))
	return button


func _style_box(color: Color, border_color: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border_color
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 3
	style.corner_radius_top_right = 3
	style.corner_radius_bottom_left = 3
	style.corner_radius_bottom_right = 3
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _load_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if path.begins_with("res://"):
		return load(path) as Texture2D
	var image := Image.load_from_file(path)
	return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		child.queue_free()
