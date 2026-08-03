extends Control
class_name MultiplayerBattleRoomPage

signal leave_requested

const COLOR_BG := Color("#0F1724")
const COLOR_PANEL := Color("#182438")
const COLOR_PANEL_2 := Color("#22324A")
const COLOR_BLUE := Color("#5DA9FF")
const COLOR_RED := Color("#FF6B6B")
const COLOR_READY := Color("#54D6A2")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")

@export var map_name := "Creston Town"

var selection: Dictionary = {}
var map_definition: Dictionary = {}
var map_loading_images_directory := "res://assets/loading/creston_town"
var players: Array[Dictionary] = []
var header_label: Label
var map_label: Label
var info_label: Label
var blue_list: VBoxContainer
var red_list: VBoxContainer

### WARNING： 开发阶段的测试
var MAP = "res://worlds/creston_town/creston_town.tscn"
var is_loading_world:bool = false
###

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_build_interface()
	_seed_placeholder_players()
	_refresh()

func _process(delta: float) -> void:
	if not is_loading_world:
		return

	var progress := []
	var status = ResourceLoader.load_threaded_get_status(MAP, progress)
	if not progress.is_empty():
		MapLoading.update_progress(float(progress[0]) * 0.25, "正在加载地图资源")

	if status == ResourceLoader.THREAD_LOAD_LOADED:
		is_loading_world = false
		var scene = ResourceLoader.load_threaded_get(MAP) as PackedScene
		if scene == null:
			push_error("多人地图加载完成但不是 PackedScene: " + MAP)
			return
		#scene.set_player(selection)
		GlobalVar.pending_player_selection = selection
		get_tree().change_scene_to_packed(scene)
		
		
	elif status == ResourceLoader.THREAD_LOAD_FAILED:
		is_loading_world = false
		push_error("多人地图加载失败: " + MAP)
	

func setup_from_selection(new_selection: Dictionary, auto_load_map := false) -> void:
	selection = new_selection.duplicate(true)
	_seed_placeholder_players()
	_refresh()
	if auto_load_map:
		load_multiplayer_map()


func apply_match_start_info(info: Dictionary) -> void:
	var configured_map_id := str(info.get("map_id", ""))
	if not configured_map_id.is_empty():
		var local_map := GameMapRegistry.get_map_by_package_name(configured_map_id)
		if not local_map.is_empty() and bool(local_map.get("is_compatible", false)):
			map_definition = local_map.duplicate(true)
			map_name = str(local_map.get("display_name", info.get("map_name", map_name)))
			MAP = str(local_map.get("scene_path", MAP))
			map_loading_images_directory = str(local_map.get("loading_images_directory", ""))
		else:
			map_name = str(info.get("map_name", configured_map_id))
			MAP = str(info.get("map_scene_path", ""))
			map_loading_images_directory = ""
	var authoritative_players: Variant = info.get("authoritative_players", [])
	if not authoritative_players is Array:
		return
	var local_peer_id := MultiplayerNetwork.get_unique_peer_id()
	for item: Variant in authoritative_players:
		if not item is Dictionary:
			continue
		var player_info := (item as Dictionary)
		if int(player_info.get("peer_id", 0)) != local_peer_id:
			continue
		selection.merge(player_info, true)
		return

func set_players(new_players: Array) -> void:
	players.clear()
	for item: Variant in new_players:
		if item is Dictionary:
			players.append((item as Dictionary).duplicate(true))
	_refresh()


func load_multiplayer_map() -> void:
	if is_loading_world:
		return
	if MAP.is_empty() or not ResourceLoader.exists(MAP):
		info_label.text = "本地没有服务器地图“%s”，请安装相同的 maps 地图包。" % map_name
		push_error("无法加载多人地图，本地地图不存在：" + MAP)
		return
	is_loading_world = true
	info_label.text = "正在加载地图：%s ..." % map_name
	MapLoading.begin_loading(
		map_name,
		map_loading_images_directory,
		"res://data/loading_tips.json"
	)
	var err := ResourceLoader.load_threaded_request(MAP)
	if err != OK:
		push_error("无法开始加载多人地图: " + MAP)
		is_loading_world = false
		MapLoading.finish_loading()


func _seed_placeholder_players() -> void:
	var team := str(selection.get("team", ""))
	if team.is_empty():
		players = []
		return
	var hero := str(selection.get("hero_id", ""))
	players = [
		{
			"display_name": str(selection.get("display_name", "You")),
			"team": team,
			"ready": true,
			"hero": hero,
		}
	]


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

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
	header.add_theme_constant_override("separation", 20)
	root.add_child(header)

	var header_text := VBoxContainer.new()
	header_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(header_text)

	header_label = Label.new()
	header_label.text = "战局准备"
	header_label.add_theme_font_size_override("font_size", 52)
	header_label.add_theme_color_override("font_color", COLOR_TEXT)
	header_text.add_child(header_label)

	map_label = Label.new()
	map_label.add_theme_font_size_override("font_size", 26)
	map_label.add_theme_color_override("font_color", COLOR_MUTED)
	header_text.add_child(map_label)

	info_label = Label.new()
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.custom_minimum_size.x = 420
	info_label.add_theme_font_size_override("font_size", 26)
	info_label.add_theme_color_override("font_color", COLOR_MUTED)
	header.add_child(info_label)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 24)
	root.add_child(body)

	blue_list = _make_team_panel(body, "蓝队", COLOR_BLUE)
	red_list = _make_team_panel(body, "红队", COLOR_RED)

	var footer := Label.new()
	footer.text = "所有玩家准备完成后，服务器会开始战局。"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 24)
	footer.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(footer)


func _make_team_panel(parent: Node, title: String, color: Color) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 28))
	parent.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title_label := Label.new()
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", 38)
	title_label.add_theme_color_override("font_color", color)
	box.add_child(title_label)
	return box


func _refresh() -> void:
	if map_label == null:
		return
	var blue_count := 0
	var red_count := 0
	for player: Dictionary in players:
		if str(player.get("team", "")) == "blue":
			blue_count += 1
		elif str(player.get("team", "")) == "red":
			red_count += 1
	map_label.text = "地图：%s" % map_name
	info_label.text = "蓝队 %d / 5    红队 %d / 5" % [blue_count, red_count]

	_clear_player_rows(blue_list)
	_clear_player_rows(red_list)
	_fill_team_rows(blue_list, "blue")
	_fill_team_rows(red_list, "red")


func _clear_player_rows(list: VBoxContainer) -> void:
	for child in list.get_children():
		if child.get_meta("player_row", false):
			list.remove_child(child)
			child.queue_free()


func _fill_team_rows(list: VBoxContainer, team: String) -> void:
	var team_players: Array[Dictionary] = []
	for player: Dictionary in players:
		if str(player.get("team", "")) == team:
			team_players.append(player)
	for index in range(5):
		var player := team_players[index] if index < team_players.size() else {}
		var row := _make_player_row(player, index + 1)
		row.set_meta("player_row", true)
		list.add_child(row)


func _make_player_row(player: Dictionary, index: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 76)
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL_2, 18))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.text = str(player.get("display_name", player.get("name", "空位 %d" % index)))
	name_label.add_theme_font_size_override("font_size", 26)
	name_label.add_theme_color_override("font_color", COLOR_TEXT if not player.is_empty() else COLOR_MUTED)
	row.add_child(name_label)

	var ready_label := Label.new()
	ready_label.text = "✓ 已准备" if bool(player.get("ready", false)) else "○ 未准备"
	ready_label.custom_minimum_size.x = 150
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ready_label.add_theme_font_size_override("font_size", 24)
	ready_label.add_theme_color_override("font_color", COLOR_READY if bool(player.get("ready", false)) else COLOR_MUTED)
	row.add_child(ready_label)
	return panel


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
