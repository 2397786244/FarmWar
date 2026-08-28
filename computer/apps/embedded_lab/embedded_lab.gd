extends ChocolateOSAppBase
class_name ChocolateOSEmbeddedLabApp

const TECH_NODE_SCRIPT := preload("res://computer/apps/embedded_lab/embedded_lab_tech_node.gd")
const TECH_GRAPH_SCRIPT := preload("res://computer/apps/embedded_lab/embedded_lab_graph.gd")

var refresh_elapsed := 0.0
var current_state: Dictionary = {}
var hard_drives: Array = []
var team_money := 0.0
var selected_program_id := ""
var graph: EmbeddedLabTechGraph
var graph_nodes: Dictionary = {}
var detail_title: Label
var detail_description: Label
var detail_requirements: Label
var action_button: Button
var money_label: Label
var notice_label: Label
var burn_list: VBoxContainer
var burn_count_label: Label
var burn_rows: Dictionary = {}
var burn_view_signature := ""
var burn_rebuild_queued := false
var pending_burn_key := ""


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func on_launch(context: ChocolateOSAppContext) -> void:
	super.on_launch(context)
	_refresh_state()


func on_resume() -> void:
	_refresh_state()


func _process(delta: float) -> void:
	if app_context == null:
		return
	refresh_elapsed += delta
	if refresh_elapsed < 0.5:
		return
	refresh_elapsed = 0.0
	_refresh_state()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color("#d6dbe1")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 7)
	margin.add_child(root)

	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 32.0
	root.add_child(header)
	var title := Label.new()
	title.text = "Embedded Lab"
	title.add_theme_font_size_override("font_size", 23)
	title.add_theme_color_override("font_color", Color("#20252b"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	money_label = Label.new()
	money_label.text = "队伍资金：$0"
	money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	money_label.add_theme_font_size_override("font_size", 16)
	money_label.add_theme_color_override("font_color", Color("#3f4b57"))
	header.add_child(money_label)

	var subtitle := Label.new()
	subtitle.text = "研发嵌入式程序模块，并将已解锁的程序写入硬盘。"
	subtitle.add_theme_color_override("font_color", Color("#59636e"))
	root.add_child(subtitle)

	var tabs := TabContainer.new()
	tabs.name = "LabTabs"
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var development_page := VBoxContainer.new()
	development_page.name = "开发"
	development_page.add_theme_constant_override("separation", 5)
	tabs.add_child(development_page)
	_build_development_page(development_page)

	var burn_page := VBoxContainer.new()
	burn_page.name = "烧录"
	burn_page.add_theme_constant_override("separation", 6)
	tabs.add_child(burn_page)
	_build_burn_page(burn_page)

	notice_label = Label.new()
	notice_label.text = ""
	notice_label.custom_minimum_size.y = 20.0
	notice_label.add_theme_color_override("font_color", Color("#4c5965"))
	root.add_child(notice_label)


func _build_development_page(page: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "点击科技节点查看详情。蓝色外圈表示当前开发进度。"
	hint.add_theme_color_override("font_color", Color("#5c6670"))
	page.add_child(hint)

	var graph_panel := PanelContainer.new()
	graph_panel.custom_minimum_size.y = 286.0
	graph_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	graph_panel.add_theme_stylebox_override("panel", _stylebox(Color("#eef0f2"), Color("#aeb5bc"), 1, 3))
	page.add_child(graph_panel)
	var graph_scroll := ScrollContainer.new()
	graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	graph_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	graph_panel.add_child(graph_scroll)
	graph = TECH_GRAPH_SCRIPT.new()
	graph_scroll.add_child(graph)
	_build_graph_nodes()

	var detail_panel := PanelContainer.new()
	detail_panel.custom_minimum_size.y = 93.0
	detail_panel.add_theme_stylebox_override("panel", _stylebox(Color("#f5f6f7"), Color("#aeb5bc"), 1, 3))
	page.add_child(detail_panel)
	var detail_box := VBoxContainer.new()
	detail_box.add_theme_constant_override("separation", 2)
	detail_panel.add_child(detail_box)
	var detail_header := HBoxContainer.new()
	detail_box.add_child(detail_header)
	detail_title = Label.new()
	detail_title.text = "请选择一个程序"
	detail_title.add_theme_font_size_override("font_size", 16)
	detail_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_header.add_child(detail_title)
	action_button = Button.new()
	action_button.text = "开始开发"
	action_button.custom_minimum_size = Vector2(132.0, 30.0)
	action_button.pressed.connect(_start_selected_program)
	detail_header.add_child(action_button)
	detail_description = Label.new()
	detail_description.text = ""
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.add_theme_color_override("font_color", Color("#3f4851"))
	detail_box.add_child(detail_description)
	detail_requirements = Label.new()
	detail_requirements.text = ""
	detail_requirements.add_theme_font_size_override("font_size", 12)
	detail_requirements.add_theme_color_override("font_color", Color("#68727c"))
	detail_box.add_child(detail_requirements)


func _build_graph_nodes() -> void:
	for row in range(4):
		var track_id := str(EmbeddedLabCatalog.TRACKS[row].get("track_id", ""))
		for column in range(5):
			var definitions := EmbeddedLabCatalog.get_track_definitions(track_id)
			if column >= definitions.size():
				continue
			var definition := definitions[column]
			var node: EmbeddedLabTechNode = TECH_NODE_SCRIPT.new()
			node.position = graph.node_position(row, column)
			node.selected.connect(_select_program)
			graph.add_child(node)
			graph_nodes[str(definition.get("program_id", ""))] = node
	if selected_program_id.is_empty() and not graph_nodes.is_empty():
		selected_program_id = str(EmbeddedLabCatalog.get_all_programs()[0].get("program_id", ""))


func _build_burn_page(page: VBoxContainer) -> void:
	var hint := Label.new()
	hint.text = "已解锁的程序可以写入任意硬盘；已有固件会被新的 program_id 替换。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color("#5c6670"))
	page.add_child(hint)
	var separator := HSeparator.new()
	page.add_child(separator)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)
	burn_list = VBoxContainer.new()
	burn_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	burn_list.add_theme_constant_override("separation", 5)
	scroll.add_child(burn_list)


func _refresh_state() -> void:
	if app_context == null:
		return
	var result := app_context.query("embedded_lab.read")
	if not bool(result.get("ok", false)):
		if is_instance_valid(notice_label):
			notice_label.text = "无法读取 Embedded Lab 状态"
		return
	var state_value: Variant = result.get("state", {})
	if state_value is Dictionary:
		current_state = (state_value as Dictionary).duplicate(true)
	team_money = float(result.get("team_money", 0.0))
	var drives_value: Variant = result.get("hard_drives", [])
	hard_drives = (drives_value as Array).duplicate(true) if drives_value is Array else []
	_refresh_development_view()
	_refresh_burn_view()


func _refresh_development_view() -> void:
	var unlocked := _unlocked_ids()
	var active := _active_research()
	for definition: Dictionary in EmbeddedLabCatalog.get_all_programs():
		var program_id := str(definition.get("program_id", ""))
		var is_unlocked := unlocked.has(program_id)
		var is_active := str(active.get("program_id", "")) == program_id
		var is_available := _prerequisites_met(definition, unlocked)
		var progress := float(active.get("elapsed_seconds", 0.0)) / maxf(0.01, float(active.get("duration_seconds", 1.0))) if is_active else 0.0
		var node := graph_nodes.get(program_id, null) as EmbeddedLabTechNode
		if node != null:
			node.configure(definition, is_unlocked, is_available, is_active, progress)
	money_label.text = "队伍资金：$%d" % roundi(team_money)
	_refresh_selected_details(unlocked, active)


func _refresh_selected_details(unlocked: Array[String], active: Dictionary) -> void:
	var definition := EmbeddedLabCatalog.get_definition(selected_program_id)
	if definition.is_empty():
		return
	var program_id := str(definition.get("program_id", ""))
	var is_unlocked := unlocked.has(program_id)
	var is_active := str(active.get("program_id", "")) == program_id
	var available := _prerequisites_met(definition, unlocked)
	detail_title.text = "%s  [%s]" % [definition.get("display_name", "程序"), definition.get("short_label", "P1")]
	detail_description.text = str(definition.get("description", ""))
	var prerequisites: Array = definition.get("prerequisites", []) as Array
	var prerequisite_text := "无前置程序" if prerequisites.is_empty() else "前置：%s" % _program_names(prerequisites)
	detail_requirements.text = "%s  ·  开发费用 $%d  ·  开发时间 %s" % [
		prerequisite_text,
		int(definition.get("cost", 0)),
		EmbeddedLabCatalog.format_duration(float(definition.get("duration_seconds", 0.0))),
	]
	if is_active:
		var remaining := maxf(0.0, float(active.get("duration_seconds", 0.0)) - float(active.get("elapsed_seconds", 0.0)))
		action_button.text = "开发中 %s" % EmbeddedLabCatalog.format_duration(remaining)
		action_button.disabled = true
	elif is_unlocked:
		action_button.text = "已解锁"
		action_button.disabled = true
	elif not available:
		action_button.text = "需要前置程序"
		action_button.disabled = true
	elif team_money + 0.001 < float(definition.get("cost", 0)):
		action_button.text = "资金不足"
		action_button.disabled = true
	else:
		action_button.text = "开始开发"
		action_button.disabled = false


func _refresh_burn_view() -> void:
	if not is_instance_valid(burn_list):
		return
	var unlocked := _unlocked_ids()
	var available_drives := _available_hard_drives()
	var next_signature := _make_burn_view_signature(unlocked, available_drives)
	# The app polls its authoritative state twice per second. Recreating every
	# OptionButton on every poll closes an open popup and can free the button
	# while its pressed signal is being delivered. Keep the controls alive until
	# the actual unlocked-program/drive list changes.
	if next_signature == burn_view_signature:
		_update_burn_controls(available_drives)
		return
	burn_view_signature = next_signature
	if burn_rebuild_queued:
		return
	burn_rebuild_queued = true
	call_deferred("_rebuild_burn_view")


func _make_burn_view_signature(unlocked: Array[String], available_drives: Array) -> String:
	var parts: Array[String] = ["unlocked:" + ",".join(unlocked)]
	for drive: Dictionary in available_drives:
		parts.append("drive:%d:%s:%s" % [
			int(drive.get("slot_index", -1)),
			str(drive.get("drive_instance_id", "")),
			str(drive.get("program_id", "")),
		])
	return "\n".join(parts)


func _rebuild_burn_view() -> void:
	burn_rebuild_queued = false
	if not is_instance_valid(burn_list):
		return
	var old_selected_slots: Dictionary = {}
	for program_key: Variant in burn_rows.keys():
		var old_row_value: Variant = burn_rows[program_key]
		if not old_row_value is Dictionary:
			continue
		var old_option := (old_row_value as Dictionary).get("drive_option", null) as OptionButton
		if old_option != null and old_option.selected >= 0:
			old_selected_slots[str(program_key)] = int(old_option.get_item_metadata(old_option.selected))
	for child: Node in burn_list.get_children():
		burn_list.remove_child(child)
		child.queue_free()
	burn_rows.clear()

	var unlocked := _unlocked_ids()
	var available_drives := _available_hard_drives()
	var blank_drive_count := 0
	for drive: Dictionary in available_drives:
		if str(drive.get("program_id", "")).is_empty():
			blank_drive_count += 1
	burn_count_label = Label.new()
	burn_count_label.text = "可写入硬盘：%d（空白 %d，已有程序 %d）" % [
		available_drives.size(), blank_drive_count, available_drives.size() - blank_drive_count
	]
	burn_count_label.add_theme_color_override("font_color", Color("#4d5862"))
	burn_list.add_child(burn_count_label)
	for definition: Dictionary in EmbeddedLabCatalog.get_all_programs():
		var program_id := str(definition.get("program_id", ""))
		if not unlocked.has(program_id):
			continue
		var row_state := _create_burn_row(
			definition,
			available_drives,
			int(old_selected_slots.get(program_id, -1))
		)
		var row_panel := row_state.get("panel", null) as PanelContainer
		if row_panel != null:
			burn_list.add_child(row_panel)
		burn_rows[program_id] = row_state
	if unlocked.is_empty():
		var empty := Label.new()
		empty.text = "还没有已解锁的程序，请先在“开发”中完成研发。"
		empty.add_theme_color_override("font_color", Color("#69737c"))
		burn_list.add_child(empty)
	_update_burn_controls(available_drives)


func _create_burn_row(
		definition: Dictionary,
		available_drives: Array,
		selected_slot_index := -1
	) -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 48.0
	panel.add_theme_stylebox_override("panel", _stylebox(Color("#f4f5f6"), Color("#b7bec5"), 1, 3))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var title := Label.new()
	title.text = "%s  [%s]" % [definition.get("display_name", "程序"), definition.get("short_label", "P1")]
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", definition.get("color", Color("#333333")) as Color)
	row.add_child(title)
	var drive_option := OptionButton.new()
	drive_option.custom_minimum_size.x = 220.0
	drive_option.tooltip_text = "选择要写入的硬盘；已有程序（包括应用程序）会被替换"
	var selected_item_index := -1
	for drive: Dictionary in available_drives:
		var current_program := _drive_program_text(drive)
		# Keep the visible label compact. The slot index remains in metadata for
		# the authority request, but is not shown because it can become unwieldy
		# as inventory slots grow.
		drive_option.add_item(current_program)
		drive_option.set_item_metadata(drive_option.item_count - 1, int(drive.get("slot_index", -1)))
		if int(drive.get("slot_index", -1)) == selected_slot_index:
			selected_item_index = drive_option.item_count - 1
	if available_drives.is_empty():
		drive_option.add_item("没有可用硬盘")
		drive_option.disabled = true
	else:
		# OptionButton starts with selected == -1 in Godot. Without an explicit
		# selection the row looks usable but _burn_program returns immediately.
		drive_option.select(selected_item_index if selected_item_index >= 0 else 0)
	row.add_child(drive_option)
	var burn_button := Button.new()
	burn_button.text = "写入/覆盖"
	burn_button.custom_minimum_size.x = 94.0
	burn_button.disabled = available_drives.is_empty()
	burn_button.tooltip_text = "将程序写入所选硬盘；空白硬盘、应用程序硬盘和旧固件硬盘都可以覆盖"
	burn_button.pressed.connect(_burn_program.bind(
		str(definition.get("program_id", "")), drive_option, burn_button
	))
	row.add_child(burn_button)
	return {
		"panel": panel,
		"drive_option": drive_option,
		"burn_button": burn_button,
		"program_id": str(definition.get("program_id", "")),
	}


func _update_burn_controls(available_drives: Array) -> void:
	var has_drives := not available_drives.is_empty()
	for program_key: Variant in burn_rows.keys():
		var row_value: Variant = burn_rows[program_key]
		if not row_value is Dictionary:
			continue
		var row := row_value as Dictionary
		var drive_option := row.get("drive_option", null) as OptionButton
		var burn_button := row.get("burn_button", null) as Button
		if drive_option == null or burn_button == null:
			continue
		var waiting := not pending_burn_key.is_empty()
		drive_option.disabled = not has_drives or waiting
		burn_button.disabled = not has_drives or drive_option.selected < 0 or waiting
		burn_button.text = "写入中…" if waiting else "写入/覆盖"


func _burn_request_key(program_id: String, slot_index: int) -> String:
	return "%s|%d" % [program_id, slot_index]


func _start_selected_program() -> void:
	var definition := EmbeddedLabCatalog.get_definition(selected_program_id)
	if definition.is_empty() or app_context == null:
		return
	action_button.disabled = true
	notice_label.text = "正在提交研发请求……"
	app_context.command("embedded_lab", "start_research", {"program_id": selected_program_id})


func _burn_program(program_id: String, drive_option: OptionButton, burn_button: Button) -> void:
	if app_context == null or drive_option == null or burn_button == null:
		return
	if not pending_burn_key.is_empty() or drive_option.item_count <= 0:
		return
	if drive_option.selected < 0:
		drive_option.select(0)
	if drive_option.selected < 0:
		return
	var slot_index := int(drive_option.get_item_metadata(drive_option.selected))
	if slot_index < 0:
		return
	pending_burn_key = _burn_request_key(program_id, slot_index)
	_update_burn_controls(_available_hard_drives())
	notice_label.text = "正在写入硬盘……"
	var submitted := app_context.command("embedded_lab", "burn_program", {
		"program_id": program_id,
		"slot_index": slot_index,
	})
	if not submitted:
		pending_burn_key = ""
		notice_label.text = "无法提交硬盘写入请求。"
		_update_burn_controls(_available_hard_drives())


func apply_authoritative_result(result: Dictionary) -> void:
	var action := str(result.get("action", ""))
	if action == "embedded_lab_burn_program":
		pending_burn_key = ""
	if not bool(result.get("ok", false)):
		notice_label.text = _reason_text(str(result.get("reason", "操作失败")))
		_refresh_state()
		return
	match action:
		"embedded_lab_start_research":
			notice_label.text = "已开始开发 %s" % str(result.get("program_id", "程序"))
		"embedded_lab_burn_program":
			var replaced_program_id := str(result.get("replaced_program_id", ""))
			if replaced_program_id.is_empty():
				notice_label.text = "程序已写入硬盘。"
			else:
				notice_label.text = "已将原有固件替换为新程序。"
		"embedded_lab_sync":
			notice_label.text = ""
	_refresh_state()


func _select_program(program_id: String) -> void:
	if not program_id.is_empty():
		selected_program_id = program_id
		_refresh_development_view()


func _unlocked_ids() -> Array[String]:
	var result: Array[String] = []
	var value: Variant = current_state.get("unlocked_program_ids", [])
	if value is Array:
		for item: Variant in value:
			result.append(str(item))
	return result


func _active_research() -> Dictionary:
	var value: Variant = current_state.get("active_research", {})
	return (value as Dictionary) if value is Dictionary else {}


func _prerequisites_met(definition: Dictionary, unlocked: Array[String]) -> bool:
	var prerequisites: Variant = definition.get("prerequisites", [])
	if not prerequisites is Array:
		return true
	for prerequisite: Variant in prerequisites as Array:
		if not unlocked.has(str(prerequisite)):
			return false
	return true


func _program_names(program_ids: Array) -> String:
	var names: Array[String] = []
	for program_id: Variant in program_ids:
		var definition := EmbeddedLabCatalog.get_definition(str(program_id))
		names.append(str(definition.get("display_name", program_id)))
	return ", ".join(names)


func _available_hard_drives() -> Array:
	var result: Array = []
	for drive_value: Variant in hard_drives:
		if drive_value is Dictionary:
			result.append((drive_value as Dictionary).duplicate(true))
	return result


func _drive_program_text(drive: Dictionary) -> String:
	var program_id := str(drive.get("program_id", ""))
	return HardDriveProgramCatalog.option_text_for(program_id)


func _reason_text(reason: String) -> String:
	match reason:
		"embedded_lab_incompatible_os": return "Embedded Lab 只能在 ChocolateOS26 上运行。"
		"embedded_lab_busy": return "当前已有其他程序正在开发。"
		"embedded_lab_already_unlocked": return "这个程序已经解锁。"
		"embedded_lab_prerequisite_missing": return "还没有完成所需的前置程序。"
		"insufficient_money": return "队伍资金不足。"
		"blank_hard_drive_not_found": return "没有找到可用硬盘。"
		"hard_drive_slot_invalid": return "所选硬盘无效。"
		"hard_drive_already_programmed": return "所选硬盘已经写入程序。"
		_: return "Embedded Lab 操作失败：%s" % reason


func _stylebox(color: Color, border_color: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = border_color
	box.set_border_width_all(border_width)
	box.set_corner_radius_all(radius)
	return box
