extends Control
class_name CooperativeLobbyPage

signal back_requested

const LOADOUT_SCENE := preload("res://ui/MultiplayerLoadoutSelect.tscn")
const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_ACCENT := Color("#54D6A2")

var world_data: Dictionary = {}
var world_id := ""
var status_label: Label
var profile_label: Label
var invite_button: Button
var loadout_button: Button
var enter_world_button: Button
var members_label: Label
var members_list: VBoxContainer
var loadout_holder: Control
var loadout_ui: MultiplayerLoadoutSelect
var member_refresh_accumulator := 0.0


func _ready() -> void:
	world_data = SteamService.get_current_lobby_data()
	world_id = str(world_data.get("world_id", ""))
	if not CooperativeSession.session_failed.is_connected(_on_session_failed):
		CooperativeSession.session_failed.connect(_on_session_failed)
	if not SteamService.invite_feedback.is_connected(_on_invite_feedback):
		SteamService.invite_feedback.connect(_on_invite_feedback)
	if not SteamService.cooperative_lobby_members_changed.is_connected(_on_lobby_changed):
		SteamService.cooperative_lobby_members_changed.connect(_on_lobby_changed)
	_build_interface()
	_refresh()
	_refresh_members()


func _process(delta: float) -> void:
	member_refresh_accumulator += delta
	if member_refresh_accumulator >= 1.0:
		member_refresh_accumulator = 0.0
		_refresh_members()
		_refresh()


func _exit_tree() -> void:
	if CooperativeSession.session_failed.is_connected(_on_session_failed):
		CooperativeSession.session_failed.disconnect(_on_session_failed)
	if SteamService.invite_feedback.is_connected(_on_invite_feedback):
		SteamService.invite_feedback.disconnect(_on_invite_feedback)
	if SteamService.cooperative_lobby_members_changed.is_connected(_on_lobby_changed):
		SteamService.cooperative_lobby_members_changed.disconnect(_on_lobby_changed)


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
	title.text = "联机合作准备室"
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
	var world_panel := PanelContainer.new()
	world_panel.custom_minimum_size = Vector2(640, 0)
	world_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	body.add_child(world_panel)
	var world_box := _make_content(world_panel)
	_add_heading(world_box, "世界信息")
	var world_info := Label.new()
	world_info.text = "%s\n%s\n最大人数：%d\n死亡规则：%s" % [
		str(world_data.get("display_name", "合作世界")),
		str(world_data.get("map_name", "未知地图")),
		int(world_data.get("max_players", 4)),
		_death_mode_text(str(world_data.get("death_drop_mode", "save"))),
	]
	world_info.add_theme_font_size_override("font_size", 21)
	world_info.add_theme_color_override("font_color", COLOR_TEXT)
	world_box.add_child(world_info)
	var map_icon := TextureRect.new()
	map_icon.texture = load(str(world_data.get("map_icon_path", ""))) as Texture2D
	map_icon.custom_minimum_size = Vector2(72, 72)
	map_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	world_box.add_child(map_icon)
	var lobby_id_label := Label.new()
	lobby_id_label.text = "Steam Lobby：%d" % SteamService.cooperative_lobby_id
	lobby_id_label.add_theme_font_size_override("font_size", 18)
	lobby_id_label.add_theme_color_override("font_color", COLOR_MUTED)
	world_box.add_child(lobby_id_label)
	invite_button = _make_button("邀请 Steam 好友")
	invite_button.pressed.connect(_on_invite_pressed)
	world_box.add_child(invite_button)
	members_label = Label.new()
	members_label.add_theme_font_size_override("font_size", 21)
	members_label.add_theme_color_override("font_color", COLOR_TEXT)
	world_box.add_child(members_label)
	var members_scroll := ScrollContainer.new()
	members_scroll.custom_minimum_size = Vector2(0, 220)
	members_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	members_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	world_box.add_child(members_scroll)
	members_list = VBoxContainer.new()
	members_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	members_list.add_theme_constant_override("separation", 8)
	members_scroll.add_child(members_list)
	var profile_panel := PanelContainer.new()
	profile_panel.custom_minimum_size = Vector2(640, 0)
	profile_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	profile_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 24))
	body.add_child(profile_panel)
	var profile_box := _make_content(profile_panel)
	_add_heading(profile_box, "个人世界档案")
	profile_label = Label.new()
	profile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	profile_label.add_theme_font_size_override("font_size", 20)
	profile_label.add_theme_color_override("font_color", COLOR_MUTED)
	profile_box.add_child(profile_label)
	loadout_button = _make_button("选择角色和初始道具")
	loadout_button.pressed.connect(_open_loadout)
	profile_box.add_child(loadout_button)
	enter_world_button = _make_button("进入合作世界")
	enter_world_button.pressed.connect(_on_enter_world_pressed)
	profile_box.add_child(enter_world_button)
	var rule_label := Label.new()
	rule_label.text = "角色和初始道具只可在首次加入该世界时选择。之后的装备变化应通过世界内的制作、拾取和升级完成。"
	rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rule_label.add_theme_font_size_override("font_size", 18)
	rule_label.add_theme_color_override("font_color", COLOR_MUTED)
	profile_box.add_child(rule_label)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 14)
	root.add_child(footer)
	var leave_button := _make_button("离开合作 Lobby")
	leave_button.pressed.connect(_on_leave_pressed)
	footer.add_child(leave_button)
	var map_notice := Label.new()
	map_notice.text = "房主启动 Redpine County 后，可通过 Steam Overlay 邀请好友；好友完成首次角色选择后可进入同一世界。"
	map_notice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_notice.add_theme_font_size_override("font_size", 18)
	map_notice.add_theme_color_override("font_color", COLOR_MUTED)
	footer.add_child(map_notice)
	loadout_holder = Control.new()
	loadout_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_holder.visible = false
	add_child(loadout_holder)


func _refresh() -> void:
	var profile := CooperativeWorldStorage.get_local_profile(world_id, SteamService.steam_id)
	var is_host := SteamService.is_current_lobby_host()
	invite_button.disabled = not is_host
	if profile.is_empty():
		profile_label.text = "尚未建立该世界的个人档案。请先选择角色和初始道具。"
		loadout_button.visible = true
		enter_world_button.visible = false
		status_label.text = "%s；%s" % [
			"你是房主，可以通过 Steam Overlay 邀请好友。" if is_host else "你通过 Steam 邀请加入了该世界。",
			"首次加入需要完成角色与初始道具选择。",
		]
		return
	profile_label.text = "已锁定角色：%s\n主武器：%s\n专属道具：%s" % [
		str(profile.get("hero_id", "未知")),
		_list_text(profile.get("primary_weapon_ids", [])),
		_list_text(profile.get("special_tool_ids", [])),
	]
	loadout_button.visible = false
	enter_world_button.visible = true
	if is_host:
		enter_world_button.disabled = false
		enter_world_button.text = "启动合作世界"
		enter_world_button.modulate = Color.WHITE
		status_label.text = "个人档案已锁定。可邀请好友后启动世界。"
		return
	var world_running := SteamService.is_cooperative_world_running()
	enter_world_button.disabled = not world_running
	enter_world_button.text = "进入合作世界" if world_running else "等待房主启动世界"
	enter_world_button.modulate = COLOR_ACCENT if world_running else Color(0.65, 0.70, 0.75, 1.0)
	status_label.text = "房主已启动世界，点击高亮按钮进入。" if world_running else "个人档案已锁定，正在等待房主启动世界。"


func _open_loadout() -> void:
	if loadout_ui != null:
		return
	loadout_holder.visible = true
	loadout_ui = LOADOUT_SCENE.instantiate() as MultiplayerLoadoutSelect
	loadout_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	loadout_ui.ready_submitted.connect(_on_loadout_submitted)
	loadout_ui.back_requested.connect(_close_loadout)
	loadout_holder.add_child(loadout_ui)


func _close_loadout() -> void:
	if loadout_ui != null:
		loadout_ui.queue_free()
		loadout_ui = null
	loadout_holder.visible = false


func _on_loadout_submitted(selection: Dictionary) -> void:
	if not CooperativeWorldStorage.save_local_profile(world_id, SteamService.steam_id, selection):
		status_label.text = "保存个人世界档案失败。"
		return
	if SteamService.is_current_lobby_host() and not CooperativeWorldStorage.save_host_initial_profile(
		world_id,
		SteamService.steam_id,
		selection
	):
		status_label.text = "保存房主世界档案失败。"
		return
	_close_loadout()
	_refresh()


func _on_leave_pressed() -> void:
	CooperativeSession.stop_session()
	SteamService.leave_cooperative_lobby()
	back_requested.emit()


func _on_enter_world_pressed() -> void:
	var profile := CooperativeWorldStorage.get_local_profile(world_id, SteamService.steam_id)
	if profile.is_empty():
		status_label.text = "请先选择角色和初始道具。"
		return
	var started := CooperativeSession.start_host(world_data, profile) if SteamService.is_current_lobby_host() else CooperativeSession.join_hosted_world()
	if not started:
		status_label.text = "无法建立合作会话，请确认 Steam Lobby 与房主状态。"


func _on_session_failed(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message


func _on_invite_pressed() -> void:
	SteamService.invite_friends()


func _on_invite_feedback(message: String) -> void:
	if is_instance_valid(status_label):
		status_label.text = message


func _on_lobby_changed() -> void:
	_refresh()
	_refresh_members()


func _refresh_members() -> void:
	if not is_instance_valid(members_list) or not is_instance_valid(members_label):
		return
	for child in members_list.get_children():
		child.queue_free()
	var members := SteamService.get_cooperative_lobby_members()
	members_label.text = "Lobby 玩家（%d/%d）" % [members.size(), int(world_data.get("max_players", 4))]
	if members.is_empty():
		var empty_label := Label.new()
		empty_label.text = "正在读取 Lobby 成员..."
		empty_label.add_theme_font_size_override("font_size", 18)
		empty_label.add_theme_color_override("font_color", COLOR_MUTED)
		members_list.add_child(empty_label)
		return
	for member: Dictionary in members:
		members_list.add_child(_make_member_row(member))


func _make_member_row(member: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 54)
	row.add_theme_constant_override("separation", 12)
	var avatar := TextureRect.new()
	avatar.texture = member.get("avatar", null) as Texture2D
	avatar.custom_minimum_size = Vector2(46, 46)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(avatar)
	var name_label := Label.new()
	name_label.text = str(member.get("display_name", "Steam 用户"))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 20)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(name_label)
	if bool(member.get("is_host", false)):
		var host_label := Label.new()
		host_label.text = "房主"
		host_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		host_label.add_theme_font_size_override("font_size", 18)
		host_label.add_theme_color_override("font_color", COLOR_ACCENT)
		row.add_child(host_label)
	return row


func _death_mode_text(mode: String) -> String:
	match mode:
		"all":
			return "全部掉落"
		"random":
			return "随机掉落（装备必掉）"
		_:
			return "不掉落"


func _list_text(value: Variant) -> String:
	if not value is Array:
		return "无"
	var names: PackedStringArray = []
	for item: Variant in value:
		names.append(str(item))
	return ", ".join(names) if not names.is_empty() else "无"


func _make_content(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 26)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)
	return box


func _add_heading(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", COLOR_TEXT)
	parent.add_child(label)


func _make_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 56)
	button.add_theme_font_size_override("font_size", 19)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(COLOR_PANEL_2, 16))
	button.add_theme_stylebox_override("hover", _style_box(COLOR_ACCENT.darkened(0.45), 16))
	return button


func _style_box(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	return style
