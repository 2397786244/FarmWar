extends Control
class_name CooperativeWorldPage

signal back_requested

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_ACCENT := Color("#54D6A2")

var status_label: Label
var world_name_edit: LineEdit
var max_players_option: OptionButton
var death_mode_option: OptionButton
var create_button: Button
var saved_worlds_box: VBoxContainer
var selected_world_id := ""
var delete_world_dialog: ConfirmationDialog
var pending_delete_world_id := ""
var pending_delete_world_name := ""
var map_list: ItemList
var map_details_label: Label
var maps: Array[Dictionary] = []


func _ready() -> void:
	_build_interface()
	SteamService.initialization_completed.connect(_on_steam_initialization_completed)
	SteamService.cooperative_lobby_error.connect(_on_lobby_error)
	SteamService.cooperative_lobby_created.connect(_on_lobby_created)
	_refresh_maps()
	_refresh_worlds()
	_refresh_steam_status()
	if not GlobalVar.cooperative_return_notice.is_empty():
		status_label.text = GlobalVar.cooperative_return_notice
		GlobalVar.cooperative_return_notice = ""


func _exit_tree() -> void:
	if SteamService.initialization_completed.is_connected(_on_steam_initialization_completed):
		SteamService.initialization_completed.disconnect(_on_steam_initialization_completed)
	if SteamService.cooperative_lobby_error.is_connected(_on_lobby_error):
		SteamService.cooperative_lobby_error.disconnect(_on_lobby_error)
	if SteamService.cooperative_lobby_created.is_connected(_on_lobby_created):
		SteamService.cooperative_lobby_created.disconnect(_on_lobby_created)


func _build_interface() -> void:
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
	root.custom_minimum_size = Vector2(1320, 0)
	root.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	var title := Label.new()
	title.text = "联机合作"
	title.add_theme_font_size_override("font_size", 42)
	title.add_theme_color_override("font_color", COLOR_TEXT)
	root.add_child(title)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 20)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(status_label)
	var body := HBoxContainer.new()
	body.custom_minimum_size = Vector2(1320, 0)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	root.add_child(body)
	var new_panel := _make_panel()
	new_panel.custom_minimum_size = Vector2(640, 0)
	new_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(new_panel)
	var new_box := _make_panel_content(new_panel)
	_add_heading(new_box, "创建新世界")
	_add_description(new_box, "世界由房主保存在本机；建立 Steam Lobby 后在游戏中邀请好友加入。")
	world_name_edit = LineEdit.new()
	world_name_edit.text = "我的合作农场"
	world_name_edit.placeholder_text = "世界名称"
	world_name_edit.custom_minimum_size = Vector2(0, 54)
	world_name_edit.add_theme_font_size_override("font_size", 24)
	new_box.add_child(world_name_edit)
	var map_heading := Label.new()
	map_heading.text = "选择地图"
	map_heading.add_theme_font_size_override("font_size", 21)
	map_heading.add_theme_color_override("font_color", COLOR_TEXT)
	new_box.add_child(map_heading)
	map_list = ItemList.new()
	map_list.custom_minimum_size = Vector2(0, 210)
	map_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list.allow_reselect = true
	map_list.fixed_icon_size = Vector2i(72, 72)
	map_list.icon_mode = ItemList.ICON_MODE_LEFT
	map_list.same_column_width = false
	map_list.item_selected.connect(_on_map_selected)
	new_box.add_child(map_list)
	map_details_label = Label.new()
	map_details_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_details_label.custom_minimum_size = Vector2(0, 74)
	map_details_label.add_theme_font_size_override("font_size", 17)
	map_details_label.add_theme_color_override("font_color", COLOR_MUTED)
	new_box.add_child(map_details_label)
	max_players_option = OptionButton.new()
	max_players_option.add_item("最大人数：1")
	max_players_option.add_item("最大人数：2")
	max_players_option.add_item("最大人数：3")
	max_players_option.add_item("最大人数：4")
	max_players_option.select(3)
	max_players_option.custom_minimum_size = Vector2(0, 52)
	max_players_option.add_theme_font_size_override("font_size", 23)
	new_box.add_child(max_players_option)
	death_mode_option = OptionButton.new()
	death_mode_option.add_item("死亡掉落：全部物品")
	death_mode_option.add_item("死亡掉落：随机掉落（装备必掉）")
	death_mode_option.add_item("死亡掉落：不掉落")
	death_mode_option.select(2)
	death_mode_option.custom_minimum_size = Vector2(0, 52)
	death_mode_option.add_theme_font_size_override("font_size", 23)
	new_box.add_child(death_mode_option)
	var lock_hint := Label.new()
	lock_hint.text = "创建后，地图、人数上限和死亡规则锁定；角色与初始道具由每位玩家首次进入该世界时确定。"
	lock_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lock_hint.add_theme_font_size_override("font_size", 21)
	lock_hint.add_theme_color_override("font_color", COLOR_MUTED)
	new_box.add_child(lock_hint)
	create_button = _make_button("创建世界并开启 Steam Lobby")
	create_button.pressed.connect(_on_create_pressed)
	new_box.add_child(create_button)
	var saved_panel := _make_panel()
	saved_panel.custom_minimum_size = Vector2(640, 0)
	saved_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(saved_panel)
	var saved_box := _make_panel_content(saved_panel)
	_add_heading(saved_box, "继续已保存的世界")
	_add_description(saved_box, "续档会读取原有规则，并创建一个新的好友可加入 Steam Lobby。")
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	saved_box.add_child(scroll)
	saved_worlds_box = VBoxContainer.new()
	saved_worlds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saved_worlds_box.add_theme_constant_override("separation", 10)
	scroll.add_child(saved_worlds_box)
	delete_world_dialog = ConfirmationDialog.new()
	delete_world_dialog.title = "删除合作存档"
	delete_world_dialog.confirmed.connect(_confirm_delete_world)
	delete_world_dialog.canceled.connect(_clear_pending_delete)
	add_child(delete_world_dialog)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	root.add_child(footer)
	var back_button := _make_button("返回")
	back_button.pressed.connect(func() -> void: back_requested.emit())
	footer.add_child(back_button)


func _refresh_worlds() -> void:
	for child in saved_worlds_box.get_children():
		child.queue_free()
	var worlds := CooperativeWorldStorage.list_worlds()
	if worlds.is_empty():
		_add_description(saved_worlds_box, "还没有本地合作世界。")
		return
	for world: Dictionary in worlds:
		var host_summary: Dictionary = world.get("host_summary", {})
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.custom_minimum_size = Vector2(0, 94)
		row.add_theme_constant_override("separation", 10)
		saved_worlds_box.add_child(row)
		var button := _make_button("%s\n%s · %d 人 · %s" % [
			str(world.get("display_name", "未命名世界")),
			"%s · 第 %d 天 · 团队金钱 %s · 房主 %s HP %.0f/%.0f · %s" % [
				str(world.get("map_name", "未知地图")),
				int(world.get("game_day", 1)),
				_format_money(float(world.get("team_money", 0.0))),
				str(host_summary.get("display_name", "房主")),
				float(host_summary.get("current_hp", 200.0)),
				float(host_summary.get("max_hp", 200.0)),
				str(host_summary.get("location_label", "未知位置")),
			],
			int(world.get("max_players", 4)),
			_death_mode_text(str(world.get("death_drop_mode", "save"))),
		])
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = _load_icon(str(world.get("map_icon_path", "")))
		button.expand_icon = false
		button.custom_minimum_size.y = 94
		button.pressed.connect(_on_continue_world_pressed.bind(str(world.get("world_id", ""))))
		row.add_child(button)
		var delete_button := _make_delete_button()
		delete_button.tooltip_text = "删除这个合作世界存档及其玩家档案"
		delete_button.pressed.connect(_on_delete_world_pressed.bind(
			str(world.get("world_id", "")),
			str(world.get("display_name", "未命名世界")),
		))
		row.add_child(delete_button)


func _on_create_pressed() -> void:
	var map_definition := _selected_map_definition()
	if map_definition.is_empty():
		status_label.text = "请选择一个可用的地图。"
		return
	if not bool(map_definition.get("is_compatible", false)):
		status_label.text = "当前地图缺少基础系统，不能创建合作世界。"
		return
	var world := CooperativeWorldStorage.create_world({
		"display_name": world_name_edit.text.strip_edges(),
		"map_id": str(map_definition.get("map_id", "")),
		"map_name": str(map_definition.get("display_name", "未命名地图")),
		"map_icon_path": str(map_definition.get("icon_path", "")),
		"map_scene_path": str(map_definition.get("scene_path", "")),
		"map_version": str(map_definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
		"map_hash": str(map_definition.get("map_hash", "")),
		"map_source": str(map_definition.get("source", "builtin")),
		"max_players": max_players_option.selected + 1,
		"death_drop_mode": _selected_death_mode(),
		"host_steam_id": SteamService.steam_id,
		"host_display_name": SteamService.persona_name,
	})
	if world.is_empty():
		status_label.text = "无法创建本地世界存档。"
		return
	status_label.text = "正在创建 Steam 好友 Lobby..."
	create_button.disabled = true
	if not SteamService.create_cooperative_lobby(world):
		create_button.disabled = false


func _on_continue_world_pressed(world_id: String) -> void:
	var world := CooperativeWorldStorage.select_world(world_id)
	if world.is_empty():
		status_label.text = "读取该世界失败。"
		return
	var map_validation := GameMapRegistry.validate_world_map(world)
	if not bool(map_validation.get("valid", false)):
		status_label.text = str(map_validation.get("error", "本地没有该世界所需的地图，无法开服。"))
		return
	var local_map: Dictionary = map_validation.get("map", {}) as Dictionary
	if not local_map.is_empty():
		world["map_name"] = str(local_map.get("display_name", world.get("map_name", "未知地图")))
		world["map_icon_path"] = str(local_map.get("icon_path", world.get("map_icon_path", "")))
		world["map_scene_path"] = str(local_map.get("scene_path", world.get("map_scene_path", "")))
		world["map_version"] = str(local_map.get("map_version", world.get("map_version", "")))
		world["map_hash"] = str(local_map.get("map_hash", world.get("map_hash", "")))
	selected_world_id = world_id
	status_label.text = "正在为“%s”创建 Steam 好友 Lobby..." % str(world.get("display_name", "合作世界"))
	if not SteamService.create_cooperative_lobby(world):
		status_label.text = "Steam Lobby 创建失败。"


func _on_delete_world_pressed(world_id: String, display_name: String) -> void:
	if world_id.is_empty() or not is_instance_valid(delete_world_dialog):
		return
	pending_delete_world_id = world_id
	pending_delete_world_name = display_name
	delete_world_dialog.dialog_text = "确定要删除“%s”吗？\n世界进度、玩家档案和该存档中的所有内容都会被永久删除。" % display_name
	delete_world_dialog.popup_centered(Vector2i(620, 220))


func _confirm_delete_world() -> void:
	var world_id := pending_delete_world_id
	var display_name := pending_delete_world_name
	_clear_pending_delete()
	if world_id.is_empty():
		return
	if CooperativeWorldStorage.delete_world(world_id):
		if selected_world_id == world_id:
			selected_world_id = ""
		status_label.text = "已删除合作存档：“%s”。" % display_name
		_refresh_worlds()
	else:
		status_label.text = "删除合作存档失败，请检查存档文件是否被占用。"


func _clear_pending_delete() -> void:
	pending_delete_world_id = ""
	pending_delete_world_name = ""


func _on_lobby_created(_lobby_id: int, _world: Dictionary) -> void:
	status_label.text = "Steam Lobby 已建立，正在进入合作准备室。"


func _on_lobby_error(message: String) -> void:
	status_label.text = message
	create_button.disabled = not SteamService.initialized


func _on_steam_initialization_completed(success: bool, message: String) -> void:
	status_label.text = message
	create_button.disabled = not success


func _refresh_steam_status() -> void:
	if SteamService.initialized:
		status_label.text = "Steam 已登录：%s" % SteamService.persona_name
		create_button.disabled = false
	elif SteamService.initialization_finished:
		status_label.text = SteamService.initialization_message
		create_button.disabled = true
	else:
		status_label.text = "正在初始化 Steam..."
		create_button.disabled = true


func _selected_death_mode() -> String:
	match death_mode_option.selected:
		0:
			return "all"
		1:
			return "random"
		_:
			return "save"


func _death_mode_text(mode: String) -> String:
	match mode:
		"all":
			return "全部掉落"
		"random":
			return "随机掉落（装备必掉）"
		_:
			return "不掉落"


func _format_money(amount: float) -> String:
	return "%.0f" % maxf(0.0, amount)


func _refresh_maps() -> void:
	if not is_instance_valid(map_list):
		return
	maps = GameMapRegistry.list_singleplayer_maps()
	map_list.clear()
	var first_compatible := -1
	for index in range(maps.size()):
		var definition: Dictionary = maps[index]
		var size_value: Variant = definition.get("size", Vector2i.ZERO)
		var size := size_value as Vector2i if size_value is Vector2i else Vector2i.ZERO
		var label := "%s\n%d × %d" % [str(definition.get("display_name", "未命名地图")), size.x, size.y]
		if str(definition.get("source", "")) == "portable":
			label += " · 手动安装"
		if not bool(definition.get("is_compatible", false)):
			label += " · 基础系统不完整"
		else:
			if first_compatible < 0:
				first_compatible = index
		var item_index := map_list.add_item(label, _load_icon(str(definition.get("icon_path", ""))))
		map_list.set_item_disabled(item_index, not bool(definition.get("is_compatible", false)))
	if first_compatible >= 0:
		map_list.select(first_compatible)
		_on_map_selected(first_compatible)
	else:
		map_details_label.text = "没有可用于合作模式的地图。请先在地图编辑器中保存地图，并确保基础系统完整。"


func _selected_map_definition() -> Dictionary:
	if not is_instance_valid(map_list):
		return {}
	var selected := map_list.get_selected_items()
	if selected.is_empty():
		return {}
	var index := int(selected[0])
	return maps[index].duplicate(true) if index >= 0 and index < maps.size() else {}


func _on_map_selected(index: int) -> void:
	if not is_instance_valid(map_details_label) or index < 0 or index >= maps.size():
		return
	var definition: Dictionary = maps[index]
	var size_value: Variant = definition.get("size", Vector2i.ZERO)
	var size := size_value as Vector2i if size_value is Vector2i else Vector2i.ZERO
	var source_text := _map_source_text(str(definition.get("source", "")))
	map_details_label.text = "%s · %s\n地图 ID：%s · 版本：%s" % [
		"可用" if bool(definition.get("is_compatible", false)) else "不可用",
		source_text,
		str(definition.get("map_id", "")),
		str(definition.get("map_version", GameMapRegistry.DEFAULT_MAP_VERSION)),
	]
	map_details_label.text += "\n尺寸：%d × %d" % [size.x, size.y]
	var errors: Array = definition.get("validation_errors", []) as Array
	if not errors.is_empty():
		map_details_label.text += "\n" + "；".join(errors)


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


func _load_icon(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not path.begins_with("res://"):
		var image := Image.load_from_file(path)
		return ImageTexture.create_from_image(image) if image != null and not image.is_empty() else null
	return load(path) as Texture2D


func _make_map_icon(path: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = _load_icon(path)
	icon.custom_minimum_size = Vector2(56, 56)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	return icon


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	return panel


func _make_panel_content(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	return box


func _add_heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	parent.add_child(label)


func _add_description(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", COLOR_MUTED)
	parent.add_child(label)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 54)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 16))
	button.add_theme_stylebox_override("hover", _style_box(Color("#314766"), 16))
	return button


func _make_delete_button() -> Button:
	var button := Button.new()
	button.text = "删除存档"
	button.custom_minimum_size = Vector2(156, 94)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("#FFECEC"))
	button.add_theme_stylebox_override("normal", _style_box(Color("#8B1E2D"), 16))
	button.add_theme_stylebox_override("hover", _style_box(Color("#C6283D"), 16))
	button.add_theme_stylebox_override("pressed", _style_box(Color("#6D1421"), 16))
	button.add_theme_stylebox_override("focus", _style_box(Color("#C6283D"), 16))
	return button


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
