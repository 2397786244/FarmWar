extends ChocolateOSAppBase
class_name ChocolateOSFarmInfoApp

const REFRESH_INTERVAL_SECONDS := 1.0
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")

var refresh_elapsed := 0.0
var last_farm_revision := -1
var last_inventory_revision := -1
var team_label: Label
var owned_label: Label
var planted_label: Label
var money_label: Label
var total_weight_label: Label
var status_label: Label
var inventory_list: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func on_launch(context: ChocolateOSAppContext) -> void:
	super.on_launch(context)
	refresh_elapsed = 0.0
	_refresh_state(true)


func on_resume() -> void:
	refresh_elapsed = 0.0
	_refresh_state(true)


func _process(delta: float) -> void:
	if app_context == null:
		return
	refresh_elapsed += delta
	if refresh_elapsed < REFRESH_INTERVAL_SECONDS:
		return
	refresh_elapsed = 0.0
	_refresh_state(false)


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#f5f5f5")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var heading := Label.new()
	heading.text = "Farm Info"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("#252525"))
	root.add_child(heading)

	team_label = Label.new()
	team_label.text = "当前队伍：同步中…"
	team_label.add_theme_font_size_override("font_size", 17)
	root.add_child(team_label)

	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", 8)
	root.add_child(stats)
	owned_label = _create_stat_card(stats, "队伍 FarmTile", "—")
	planted_label = _create_stat_card(stats, "已种植 FarmTile", "—")

	var inventory_header := HBoxContainer.new()
	root.add_child(inventory_header)
	var inventory_title := Label.new()
	inventory_title.text = "队伍库存"
	inventory_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_title.add_theme_font_size_override("font_size", 19)
	inventory_title.add_theme_color_override("font_color", Color("#303030"))
	inventory_header.add_child(inventory_title)
	money_label = Label.new()
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.add_theme_font_size_override("font_size", 17)
	inventory_header.add_child(money_label)
	total_weight_label = Label.new()
	total_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_weight_label.custom_minimum_size.x = 150.0
	total_weight_label.add_theme_font_size_override("font_size", 17)
	inventory_header.add_child(total_weight_label)

	var line := HSeparator.new()
	root.add_child(line)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	inventory_list = VBoxContainer.new()
	inventory_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inventory_list.add_theme_constant_override("separation", 3)
	scroll.add_child(inventory_list)

	status_label = Label.new()
	status_label.text = "农场统计同步中…"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color("#666666"))
	root.add_child(status_label)


func _create_stat_card(parent: Control, title: String, value: String) -> Label:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.custom_minimum_size.y = 68.0
	panel.add_theme_stylebox_override(
		"panel", _stylebox(Color("#ffffff"), Color("#b5b5b5"), 1, 3)
	)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)
	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_color_override("font_color", Color("#555555"))
	box.add_child(title_label)
	var value_label := Label.new()
	value_label.text = value
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.add_theme_font_size_override("font_size", 25)
	value_label.add_theme_color_override("font_color", Color("#202020"))
	box.add_child(value_label)
	return value_label


func _refresh_state(force: bool) -> void:
	if app_context == null:
		return
	var result := app_context.query("farm.read")
	if not bool(result.get("ok", false)):
		status_label.text = "无法读取农场统计"
		return
	if not bool(result.get("ready", false)):
		team_label.text = "当前队伍：统计同步中…"
		owned_label.text = "—"
		planted_label.text = "—"
		money_label.text = "队伍金钱  —"
		total_weight_label.text = "总重量  —"
		_clear_inventory_rows()
		status_label.text = "农场统计同步中…"
		return

	var farm_revision := int(result.get("farm_revision", 0))
	var inventory_revision := int(result.get("inventory_revision", 0))
	var farm_changed := force or farm_revision != last_farm_revision
	var inventory_changed := force or inventory_revision != last_inventory_revision
	if not farm_changed and not inventory_changed:
		return
	last_farm_revision = farm_revision
	last_inventory_revision = inventory_revision
	if farm_changed:
		_render_farm_summary(result)
	if inventory_changed:
		_render_inventory(result)
	status_label.text = "数据每秒更新 · 统计版本 %d" % farm_revision


func _render_farm_summary(state: Dictionary) -> void:
	var team := str(state.get("team", ""))
	team_label.text = "当前队伍：%s" % _team_display_name(team)
	team_label.add_theme_color_override("font_color", _team_color(team))
	owned_label.text = str(int(state.get("owned_farm_tiles", 0)))
	planted_label.text = str(int(state.get("planted_farm_tiles", 0)))


func _render_inventory(state: Dictionary) -> void:
	money_label.text = "队伍金钱  %d" % int(round(float(state.get("team_money", 0.0))))
	total_weight_label.text = "总重量  %.2f kg" % float(state.get("total_weight_kg", 0.0))
	_clear_inventory_rows()
	var entries_value: Variant = state.get("inventory_entries", [])
	if not entries_value is Array or (entries_value as Array).is_empty():
		var empty := Label.new()
		empty.text = "队伍库存为空"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#777777"))
		inventory_list.add_child(empty)
		return
	for entry_value: Variant in entries_value as Array:
		if entry_value is Dictionary:
			inventory_list.add_child(_create_inventory_row(entry_value as Dictionary))


func _clear_inventory_rows() -> void:
	for child: Node in inventory_list.get_children():
		inventory_list.remove_child(child)
		child.queue_free()


func _create_inventory_row(entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 42.0
	row.add_theme_stylebox_override(
		"panel", _stylebox(Color("#ffffff"), Color("#d0d0d0"), 1, 2)
	)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	row.add_child(box)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemIcon
	icon.custom_minimum_size = Vector2(36.0, 36.0)
	box.add_child(icon)
	icon.set_item_id(str(entry.get("item_id", "")))
	var name_label := Label.new()
	name_label.text = str(entry.get("display_name", entry.get("item_id", "")))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(name_label)
	var amount_label := Label.new()
	amount_label.custom_minimum_size.x = 150.0
	amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if str(entry.get("unit", "kg")) == "kg":
		amount_label.text = "%.2f kg" % float(entry.get("amount", 0.0))
	else:
		amount_label.text = "%d 件" % roundi(float(entry.get("amount", 0.0)))
	box.add_child(amount_label)
	return row


func _team_display_name(team: String) -> String:
	match team:
		"red": return "红队"
		"blue": return "蓝队"
		_: return "未分配"


func _team_color(team: String) -> Color:
	return Color("#d94141") if team == "red" else Color("#3976d5") if team == "blue" else Color("#555555")


func _stylebox(fill: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
