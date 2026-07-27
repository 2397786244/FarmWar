extends Control
class_name MultiplayerLoadoutSelect

signal selection_changed(selection: Dictionary)
signal ready_submitted(selection: Dictionary)
signal back_requested

const HERO_CONFIG_PATH := "res://data/hero_definitions.json"
const PRIMARY_WEAPON_CONFIG_PATH := "res://data/primary_weapon_definitions.json"
const SPECIAL_TOOL_CONFIG_PATH := "res://data/special_tool_definitions.json"
const HERO_SPECIAL_CONFIG_PATH := "res://data/hero_special_tools.json"

const PAGE_HERO := 0
const PAGE_PRIMARY := 1
const PAGE_SPECIAL := 2

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_SELECTED := Color("#54D6A2")
const COLOR_BLUE := Color("#5DA9FF")
const COLOR_RED := Color("#FF6B6B")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_DISABLED := Color("#5E6A78")

var heroes: Array[Dictionary] = []
var primary_weapons: Array[Dictionary] = []
var special_tools_by_id: Dictionary = {}
var hero_special_ids: Dictionary = {}

var page := PAGE_HERO
#var selected_team := "blue"
var focused_hero_id := ""
var selected_hero_id := ""
var focused_primary_id := ""
var selected_primary_ids: Array[String] = []
var focused_special_id := ""
var selected_special_ids: Array[String] = []
var is_ready := false

var title_label: Label
var step_label: Label
var left_title: Label
var list_box: VBoxContainer
var slot_row: HBoxContainer
var detail_title: Label
var detail_meta: Label
var detail_body: RichTextLabel
var choose_button: Button
var next_button: Button
var back_button: Button
var status_label: Label


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_load_all_configs()
	_build_interface()
	_select_initial_values()
	_refresh_page()


func reset_for_lobby() -> void:
	page = PAGE_HERO
	#selected_team = "blue"
	focused_hero_id = ""
	selected_hero_id = ""
	focused_primary_id = ""
	selected_primary_ids.clear()
	focused_special_id = ""
	selected_special_ids.clear()
	is_ready = false
	_select_initial_values()
	_refresh_page()


func get_selection() -> Dictionary:
	return {
		#"team": selected_team,  # TODO:队伍不能有玩家来选择，可能会导致冲突,由服务器分配指定队伍
		"hero_id": selected_hero_id,
		"primary_weapon_ids": selected_primary_ids.duplicate(),
		"special_tool_ids": selected_special_ids.duplicate(),
		"ready": is_ready,
	}


func set_player_ready_state(ready: bool) -> void:
	is_ready = ready
	_refresh_footer()


func _load_all_configs() -> void:
	heroes = _read_array_config(HERO_CONFIG_PATH, "heroes")
	primary_weapons = _read_array_config(PRIMARY_WEAPON_CONFIG_PATH, "weapons").filter(
		func(weapon: Dictionary) -> bool:
			return bool(weapon.get("loadout_selectable", true))
	)
	special_tools_by_id.clear()
	for tool: Dictionary in _read_array_config(SPECIAL_TOOL_CONFIG_PATH, "tools"):
		var tool_id := str(tool.get("id", ""))
		if not tool_id.is_empty():
			special_tools_by_id[tool_id] = tool
	var mapping := _read_dict_config(HERO_SPECIAL_CONFIG_PATH)
	hero_special_ids = mapping.get("heroes", {})


func _read_array_config(path: String, key: String) -> Array[Dictionary]:
	var data := _read_dict_config(path)
	var source: Variant = data.get(key, [])
	var result: Array[Dictionary] = []
	if not source is Array:
		push_error("Config field '%s' must be an array: %s" % [key, path])
		return result
	for entry: Variant in source:
		if entry is Dictionary:
			result.append((entry as Dictionary).duplicate(true))
	return result


func _read_dict_config(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Config file missing: " + path)
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Could not open config: " + path)
		return {}
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	if err != OK:
		push_error(
			"Invalid JSON %s line %d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return {}
	if not json.data is Dictionary:
		push_error("Config root must be an object: " + path)
		return {}
	return (json.data as Dictionary).duplicate(true)


func _select_initial_values() -> void:
	if focused_hero_id.is_empty() and not heroes.is_empty():
		focused_hero_id = str(heroes[0].get("id", ""))
	if selected_hero_id.is_empty():
		selected_hero_id = _first_available_hero_id()
	if focused_hero_id.is_empty():
		focused_hero_id = selected_hero_id
	if focused_primary_id.is_empty() and not primary_weapons.is_empty():
		focused_primary_id = str(primary_weapons[0].get("id", ""))
	_select_initial_special_focus()


func _first_available_hero_id() -> String:
	for hero: Dictionary in heroes:
		var hero_id := str(hero.get("id", ""))
		#if _is_hero_available(hero, selected_team):  # TODO
		return hero_id
	return ""


func _select_initial_special_focus() -> void:
	if selected_hero_id.is_empty():
		focused_special_id = ""
		return
	var ids := _get_special_ids_for_selected_hero()
	if ids.is_empty():
		focused_special_id = ""
	elif focused_special_id.is_empty() or not ids.has(focused_special_id):
		focused_special_id = str(ids[0])


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = COLOR_BG
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_top", 38)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_bottom", 38)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 22)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)

	var title_box := VBoxContainer.new()
	title_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_box)

	title_label = Label.new()
	title_label.text = "多人游戏准备"
	title_label.add_theme_font_size_override("font_size", 48)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	title_box.add_child(title_label)

	step_label = Label.new()
	step_label.add_theme_font_size_override("font_size", 24)
	step_label.add_theme_color_override("font_color", COLOR_MUTED)
	title_box.add_child(step_label)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_label.custom_minimum_size.x = 360
	status_label.add_theme_font_size_override("font_size", 24)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	header.add_child(status_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 22)
	root.add_child(body)

	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size.x = 470
	left_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	body.add_child(left_panel)

	var left_margin := MarginContainer.new()
	left_margin.add_theme_constant_override("margin_left", 22)
	left_margin.add_theme_constant_override("margin_top", 22)
	left_margin.add_theme_constant_override("margin_right", 22)
	left_margin.add_theme_constant_override("margin_bottom", 22)
	left_panel.add_child(left_margin)

	var left_root := VBoxContainer.new()
	left_root.add_theme_constant_override("separation", 16)
	left_margin.add_child(left_root)

	left_title = Label.new()
	left_title.add_theme_font_size_override("font_size", 32)
	left_title.add_theme_color_override("font_color", COLOR_TEXT)
	left_root.add_child(left_title)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left_root.add_child(scroll)

	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 10)
	scroll.add_child(list_box)

	var right_panel := PanelContainer.new()
	right_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	body.add_child(right_panel)

	var right_margin := MarginContainer.new()
	right_margin.add_theme_constant_override("margin_left", 34)
	right_margin.add_theme_constant_override("margin_top", 28)
	right_margin.add_theme_constant_override("margin_right", 34)
	right_margin.add_theme_constant_override("margin_bottom", 28)
	right_panel.add_child(right_margin)

	var right_root := VBoxContainer.new()
	right_root.add_theme_constant_override("separation", 18)
	right_margin.add_child(right_root)

	slot_row = HBoxContainer.new()
	slot_row.add_theme_constant_override("separation", 14)
	right_root.add_child(slot_row)

	detail_title = Label.new()
	detail_title.add_theme_font_size_override("font_size", 42)
	detail_title.add_theme_color_override("font_color", COLOR_TEXT)
	right_root.add_child(detail_title)

	detail_meta = Label.new()
	detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_meta.add_theme_font_size_override("font_size", 24)
	detail_meta.add_theme_color_override("font_color", COLOR_MUTED)
	right_root.add_child(detail_meta)

	detail_body = RichTextLabel.new()
	detail_body.bbcode_enabled = true
	detail_body.fit_content = false
	detail_body.scroll_active = true
	detail_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_body.add_theme_font_size_override("normal_font_size", 25)
	detail_body.add_theme_color_override("default_color", COLOR_TEXT)
	right_root.add_child(detail_body)

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 16)
	root.add_child(footer)

	back_button = _make_action_button("返回")
	back_button.pressed.connect(_on_back_pressed)
	footer.add_child(back_button)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	choose_button = _make_action_button("选择这个")
	choose_button.pressed.connect(_on_choose_pressed)
	footer.add_child(choose_button)

	next_button = _make_action_button("下一步")
	next_button.pressed.connect(_on_next_pressed)
	footer.add_child(next_button)


func _refresh_page() -> void:
	_clear_container(list_box)
	_clear_container(slot_row)

	match page:
		PAGE_HERO:
			step_label.text = "第 1 步 / 3 · 选择队伍和角色"
			left_title.text = "队伍与角色"
			_build_hero_list()
			_build_hero_detail()
		PAGE_PRIMARY:
			step_label.text = "第 2 步 / 3 · 选择 3 个通用主武器"
			left_title.text = "通用主武器"
			_build_weapon_slots()
			_build_primary_list()
			_build_primary_detail()
		PAGE_SPECIAL:
			step_label.text = "第 3 步 / 3 · 选择 2 个职业专属道具"
			left_title.text = "职业专属"
			_build_special_slots()
			_build_special_list()
			_build_special_detail()

	_refresh_footer()
	selection_changed.emit(get_selection())


func _build_hero_list() -> void:
	## TODO: 队伍的选择被清理了，请你检查是否都清理掉了
	#var team_row := HBoxContainer.new()
	#team_row.add_theme_constant_override("separation", 10)
	#list_box.add_child(team_row)
	#var blue_button := _make_list_button("蓝队", selected_team == "blue", true)
	#blue_button.add_theme_stylebox_override(
		#"normal",
		#_style_box(COLOR_BLUE if selected_team == "blue" else COLOR_PANEL_2, 16)
	#)
	#blue_button.pressed.connect(_set_team.bind("blue"))
	#team_row.add_child(blue_button)
	#var red_button := _make_list_button("红队", selected_team == "red", true)
	#red_button.add_theme_stylebox_override(
		#"normal",
		#_style_box(COLOR_RED if selected_team == "red" else COLOR_PANEL_2, 16)
	#)
	#red_button.pressed.connect(_set_team.bind("red"))
	#team_row.add_child(red_button)

	for hero: Dictionary in heroes:
		var hero_id := str(hero.get("id", ""))
		var available = true  # TODO，这里需要修复调整
		var label := str(hero.get("name", hero_id))
		if not available:
			label += "  · 暂未配置"
		elif hero_id == selected_hero_id:
			label += "  · 已选择"
		var button := _make_list_button(label, hero_id == focused_hero_id, available)
		button.pressed.connect(_focus_hero.bind(hero_id))
		list_box.add_child(button)


func _build_primary_list() -> void:
	for weapon: Dictionary in primary_weapons:
		var item_id := str(weapon.get("id", ""))
		var label := str(weapon.get("name", item_id))
		if selected_primary_ids.has(item_id):
			label += "  · 已入槽"
		var button := _make_list_button(label, item_id == focused_primary_id, true)
		button.pressed.connect(_focus_primary.bind(item_id))
		list_box.add_child(button)


func _build_special_list() -> void:
	var ids := _get_special_ids_for_selected_hero()
	for item_id: String in ids:
		var tool := _get_special_tool(item_id)
		var label := str(tool.get("name", item_id))
		if selected_special_ids.has(item_id):
			label += "  · 已入槽"
		var button := _make_list_button(label, item_id == focused_special_id, true)
		button.pressed.connect(_focus_special.bind(item_id))
		list_box.add_child(button)
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "该角色还没有配置专属道具。"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_font_size_override("font_size", 24)
		empty.add_theme_color_override("font_color", COLOR_MUTED)
		list_box.add_child(empty)


func _build_weapon_slots() -> void:
	_add_slot_title("主武器槽")
	for index in range(3):
		var item_id := selected_primary_ids[index] if index < selected_primary_ids.size() else ""
		slot_row.add_child(_make_slot(index + 1, _get_primary_name(item_id), item_id))


func _build_special_slots() -> void:
	_add_slot_title("专属槽")
	for index in range(2):
		var item_id := selected_special_ids[index] if index < selected_special_ids.size() else ""
		slot_row.add_child(_make_slot(index + 1, _get_special_name(item_id), item_id))


func _add_slot_title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 116
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	slot_row.add_child(label)


func _make_slot(index: int, item_name: String, item_id: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(178, 96)
	panel.add_theme_stylebox_override(
		"panel",
		_style_box(COLOR_PANEL_2 if not item_id.is_empty() else Color("#141E2E"), 18)
	)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	margin.add_child(box)
	var label := Label.new()
	label.text = item_name if not item_name.is_empty() else "空槽 %d" % index
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 20)
	label.add_theme_color_override("font_color", COLOR_TEXT if not item_id.is_empty() else COLOR_MUTED)
	box.add_child(label)
	return panel


func _build_hero_detail() -> void:
	var hero := _get_hero(focused_hero_id)
	if hero.is_empty():
		_set_detail("未选择角色", "", "左侧选择一个角色。")
		return
	var available = true
	## TODO： 这里似乎也要修改，因为可能涉及到角色名和队伍颜色的搭配。不过队伍名由服务器的RPC确认函数来返回如何
	#var scene_path = _hero_scene_path(hero, selected_team)
	var body := str(hero.get("description", ""))
	if body.is_empty():
		body = "角色介绍内容暂时留空，后续可在 hero_definitions.json 中补充。"
	var meta := "%s角色场景" % [
		str(hero.get("role", "")),
		#"蓝" if selected_team == "blue" else "红",
		#scene_path if available else "暂未配置"
	]
	_set_detail(str(hero.get("name", focused_hero_id)), meta, body)


func _build_primary_detail() -> void:
	var weapon := _get_primary_weapon(focused_primary_id)
	if weapon.is_empty():
		_set_detail("未选择主武器", "", "左侧选择一个主武器。")
		return
	var body := str(weapon.get("description", ""))
	if body.is_empty():
		body = "武器具体介绍暂时留空，后续可在 primary_weapon_definitions.json 中补充。"
	var meta := "威力：%s    射速：%s    冷却：%ss\n场景：%s" % [
		str(weapon.get("power", 0)),
		str(weapon.get("fire_rate", 0)),
		str(weapon.get("cooldown", 0)),
		str(weapon.get("tool_scene", "")),
	]
	_set_detail(str(weapon.get("name", focused_primary_id)), meta, body)


func _build_special_detail() -> void:
	var tool := _get_special_tool(focused_special_id)
	if tool.is_empty():
		_set_detail("未选择专属道具", "", "左侧选择一个职业专属道具。")
		return
	var body := str(tool.get("description", ""))
	if body.is_empty():
		body = "专属武器 / 道具介绍暂时留空，后续可在 special_tool_definitions.json 中补充。"
	var meta := "冷却：%ss    最大使用次数：%s\n场景：%s" % [
		str(tool.get("cooldown", 0)),
		str(tool.get("max_uses", 0)),
		str(tool.get("tool_scene", "")),
	]
	_set_detail(str(tool.get("name", focused_special_id)), meta, body)


func _set_detail(title: String, meta: String, body: String) -> void:
	detail_title.text = title
	detail_meta.text = meta
	detail_body.text = body


func _refresh_footer() -> void:
	choose_button.disabled = is_ready
	choose_button.visible = page != PAGE_HERO
	next_button.disabled = is_ready
	match page:
		PAGE_HERO:
			choose_button.text = "选择这个角色"
			next_button.text = "下一步"
			next_button.disabled = next_button.disabled or selected_hero_id.is_empty()
			status_label.text = _status_text()
		PAGE_PRIMARY:
			choose_button.text = "选择这个"
			next_button.text = "下一步"
			next_button.disabled = next_button.disabled or selected_primary_ids.size() != 3
			status_label.text = "主武器 %d / 3" % selected_primary_ids.size()
		PAGE_SPECIAL:
			choose_button.text = "选择这个"
			next_button.text = "准备好了"
			next_button.disabled = next_button.disabled or selected_special_ids.size() != 2
			status_label.text = "专属道具 %d / 2%s" % [
				selected_special_ids.size(),
				" · 已准备" if is_ready else ""
			]


func _status_text() -> String:
	var hero_name := _get_hero_name(selected_hero_id)
	if hero_name.is_empty():
		return "请选择角色"
	return "%s"  # % ["蓝" if selected_team == "blue" else "红", hero_name]


#func _set_team(team: String) -> void:
	#if selected_team == team:
		#return
	#selected_team = team
	#if not _is_hero_available(_get_hero(selected_hero_id), selected_team):
		#selected_hero_id = _first_available_hero_id()
	#focused_hero_id = selected_hero_id
	#selected_special_ids.clear()
	#focused_special_id = ""
	#_select_initial_special_focus()
	#_refresh_page()


func _focus_hero(hero_id: String) -> void:
	focused_hero_id = hero_id
	var hero := _get_hero(hero_id)
	#if _is_hero_available(hero, selected_team):
	selected_hero_id = hero_id
	selected_special_ids.clear()
	focused_special_id = ""
	_select_initial_special_focus()
	_refresh_page()


func _focus_primary(item_id: String) -> void:
	focused_primary_id = item_id
	_refresh_page()


func _focus_special(item_id: String) -> void:
	focused_special_id = item_id
	_refresh_page()


func _on_choose_pressed() -> void:
	match page:
		PAGE_HERO:
			var hero := _get_hero(focused_hero_id)
			#if _is_hero_available(hero, selected_team):  
			selected_hero_id = focused_hero_id
			selected_special_ids.clear()
			focused_special_id = ""
			_select_initial_special_focus()
		PAGE_PRIMARY:
			_toggle_id_in_limited_list(focused_primary_id, selected_primary_ids, 3)
		PAGE_SPECIAL:
			_toggle_id_in_limited_list(focused_special_id, selected_special_ids, 2)
	_refresh_page()


func _on_next_pressed() -> void:
	if page == PAGE_HERO and selected_hero_id.is_empty():
		return
	if page == PAGE_PRIMARY and selected_primary_ids.size() != 3:
		return
	if page == PAGE_SPECIAL:
		if selected_special_ids.size() != 2:
			return
		is_ready = true
		_refresh_footer()
		ready_submitted.emit(get_selection())
		return
	page += 1
	if page == PAGE_SPECIAL:
		_select_initial_special_focus()
	_refresh_page()


func _on_back_pressed() -> void:
	if is_ready:
		return
	if page > PAGE_HERO:
		page -= 1
		_refresh_page()
	else:
		back_requested.emit()


func _toggle_id_in_limited_list(item_id: String, target: Array[String], limit: int) -> void:
	if item_id.is_empty():
		return
	if target.has(item_id):
		target.erase(item_id)
	elif target.size() < limit:
		target.append(item_id)


func _get_hero(hero_id: String) -> Dictionary:
	for hero: Dictionary in heroes:
		if str(hero.get("id", "")) == hero_id:
			return hero
	return {}


func _get_primary_weapon(item_id: String) -> Dictionary:
	for weapon: Dictionary in primary_weapons:
		if str(weapon.get("id", "")) == item_id:
			return weapon
	return {}


func _get_special_tool(item_id: String) -> Dictionary:
	return special_tools_by_id.get(item_id, {})


func _get_special_ids_for_selected_hero() -> Array[String]:
	var result: Array[String] = []
	var source: Variant = hero_special_ids.get(selected_hero_id, [])
	if not source is Array:
		return result
	for item: Variant in source:
		result.append(str(item))
	return result


func _get_hero_name(hero_id: String) -> String:
	var hero := _get_hero(hero_id)
	return str(hero.get("name", "")) if not hero.is_empty() else ""


func _get_primary_name(item_id: String) -> String:
	var weapon := _get_primary_weapon(item_id)
	return str(weapon.get("name", "")) if not weapon.is_empty() else ""


func _get_special_name(item_id: String) -> String:
	var tool := _get_special_tool(item_id)
	return str(tool.get("name", "")) if not tool.is_empty() else ""


#func _is_hero_available(hero: Dictionary, team: String) -> bool:
	#if hero.is_empty():
		#return false
	#return FileAccess.file_exists(_hero_scene_path(hero, team))


func _hero_scene_path(hero: Dictionary, team: String) -> String:
	return str(hero.get("%s_scene" % team, ""))


func _make_list_button(text: String, selected: bool, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size = Vector2(0, 62)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", COLOR_TEXT if enabled else COLOR_DISABLED)
	button.add_theme_stylebox_override(
		"normal",
		_style_box(COLOR_SELECTED if selected else COLOR_PANEL_2, 16)
	)
	button.add_theme_stylebox_override("hover", _style_box(Color("#2C405D"), 16))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_SELECTED, 16))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#172030"), 16))
	return button


func _make_action_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 58)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 18))
	button.add_theme_stylebox_override("hover", _style_box(Color("#314766"), 18))
	button.add_theme_stylebox_override("pressed", _style_box(COLOR_SELECTED, 18))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#172030"), 18))
	return button


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _clear_container(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
