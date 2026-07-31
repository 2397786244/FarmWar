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


func _ready() -> void:
	_build_interface()
	SteamService.initialization_completed.connect(_on_steam_initialization_completed)
	SteamService.cooperative_lobby_error.connect(_on_lobby_error)
	SteamService.cooperative_lobby_created.connect(_on_lobby_created)
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
	var map_label := Label.new()
	map_label.text = "地图：Redpine County（1024 × 1024 加拿大 PvE）"
	map_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_label.add_theme_font_size_override("font_size", 19)
	map_label.add_theme_color_override("font_color", COLOR_MUTED)
	var map_row := HBoxContainer.new()
	map_row.add_theme_constant_override("separation", 12)
	var map_icon := _make_map_icon("res://worlds/redpine_county/map_icon.svg")
	map_row.add_child(map_icon)
	map_row.add_child(map_label)
	new_box.add_child(map_row)
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
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.icon = load(str(world.get("map_icon_path", ""))) as Texture2D
		button.expand_icon = false
		button.custom_minimum_size.y = 94
		button.pressed.connect(_on_continue_world_pressed.bind(str(world.get("world_id", ""))))
		saved_worlds_box.add_child(button)


func _on_create_pressed() -> void:
	var world := CooperativeWorldStorage.create_world({
		"display_name": world_name_edit.text.strip_edges(),
		"map_id": "redpine_county",
		"map_name": "Redpine County",
		"map_icon_path": "res://worlds/redpine_county/map_icon.svg",
		"map_scene_path": "res://worlds/redpine_county/redpine_county.tscn",
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
	selected_world_id = world_id
	status_label.text = "正在为“%s”创建 Steam 好友 Lobby..." % str(world.get("display_name", "合作世界"))
	if not SteamService.create_cooperative_lobby(world):
		status_label.text = "Steam Lobby 创建失败。"


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


func _make_map_icon(path: String) -> TextureRect:
	var icon := TextureRect.new()
	icon.texture = load(path) as Texture2D
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


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
