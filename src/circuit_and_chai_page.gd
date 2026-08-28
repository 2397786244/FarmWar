extends Control
class_name CircuitAndChaiPage

const PAGE_OS08 := "os08"
const PAGE_OS26 := "os26"
const PAGE_WIDTH := 720.0
const PAGE_MARGIN := 24

const OS08_BACKGROUND := Color("#ffffff")
const OS08_INK := Color("#111111")
const OS08_MUTED := Color("#111111")
const OS08_LINE := Color("#111111")

const OS26_BACKGROUND := Color("#f1f5fb")
const OS26_NAVY := Color("#172a4d")
const OS26_BLUE := Color("#2e6de6")
const OS26_CYAN := Color("#1aa7c8")
const OS26_INK := Color("#17233a")
const OS26_MUTED := Color("#5f6e84")
const OS26_PANEL := Color("#ffffff")
const OS26_LINE := Color("#d7e0ee")

const LOGO_OS26 := "res://assets/icons/ChocolateOS/OS26/system/logo.png"

var desktop: Node
var browser_app_id := "browser"
var page_id := PAGE_OS08


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, requested_page_id: String, owner_browser_app_id := "browser") -> void:
	desktop = owner_desktop
	browser_app_id = owner_browser_app_id
	page_id = requested_page_id if requested_page_id in [PAGE_OS08, PAGE_OS26] else PAGE_OS08
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(PAGE_WIDTH, 1050.0 if page_id == PAGE_OS08 else 1320.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if page_id == PAGE_OS26:
		_build_os26()
	else:
		_build_os08()


func _build_os08() -> void:
	var background := ColorRect.new()
	background.color = OS08_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	_add_os08_site_heading(root)
	_add_navigation(root, false)

	var heading := _label("ChocolateOS08", 31, OS08_INK)
	root.add_child(heading)
	var subheading := _label("EARLY DESKTOP SYSTEM / TECHNICAL NOTE 08", 12, OS08_MUTED)
	root.add_child(subheading)
	root.add_child(_os08_rule())

	root.add_child(_label(
		"ChocolateOS08 是 ChocolateOS 系列的早期桌面系统。它把桌面、浏览器和少量基础工具放在清晰而直接的界面中，适合配置有限、需要在农场和工作地点之间移动的电脑。",
		16,
		OS08_INK
	))
	root.add_child(_label(
		"这个版本强调稳定、易读和低密度。系统不会主动改变使用者的工作流程：打开应用、查看资料、读取天气和管理本地电脑数据，都保持简单的窗口操作。",
		15,
		OS08_INK
	))

	root.add_child(_os08_section_title("SYSTEM OVERVIEW"))
	root.add_child(_make_os08_list([
		"桌面：灰色背景、基础图标和浅色底栏。",
		"基础应用：Browser、My Computer、Farm Info、Weather、Network、Settings 和 Recycle Bin。",
		"应用方式：通过 Browser 访问虚拟网页，也可以从 ChocolateOS 应用库安装兼容应用。",
		"数据方式：每台电脑保存自己的浏览器数据和应用数据；电脑损毁后，本地数据不会转移到另一台电脑。",
		"定位：面向日常工作和基础信息查看，不要求高端图形性能。",
	]))

	root.add_child(_os08_section_title("BASIC SYSTEM INFORMATION"))
	root.add_child(_make_os08_table([
		["系统名称", "ChocolateOS08"],
		["界面风格", "低密度桌面、黑色文字、浅色底栏"],
		["逻辑画布", "1280 × 720"],
		["适用设备", "笔记本电脑及基础桌面电脑"],
		["默认语言", "本地化界面，可读取英文网页内容"],
	]))

	root.add_child(_os08_section_title("A SMALL, RELIABLE DESKTOP"))
	root.add_child(_label(
		"OS08 不追求复杂的视觉效果，而是把可见信息留在需要的位置。它可以作为独立的基础工作环境，也可以作为熟悉 ChocolateOS 操作方式的入口。",
		15,
		OS08_INK
	))
	root.add_child(_make_os08_notice("本页是 Circuit & Chai 的系统资料页。这里介绍的是操作系统，不是电脑硬件销售页面。"))
	_add_os08_link(root, "查看 ChocolateOS26 技术说明 →", PAGE_OS26)
	root.add_child(_label("CIRCUIT & CHAI / CHOCOLATEOS ARCHIVE", 11, OS08_MUTED))


func _add_os08_site_heading(root: VBoxContainer) -> void:
	var title := _label("CIRCUIT & CHAI", 18, OS08_INK)
	root.add_child(title)
	var line := _os08_rule()
	root.add_child(line)


func _build_os26() -> void:
	var background := ColorRect.new()
	background.color = OS26_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_add_os26_hero(root)
	_add_navigation(root, true)

	var eyebrow := _label("CHOCOLATEOS PLATFORM BRIEF / 26", 12, OS26_BLUE)
	eyebrow.add_theme_constant_override("outline_size", 0)
	root.add_child(eyebrow)
	var title := _label("ChocolateOS26", 34, OS26_INK)
	root.add_child(title)
	root.add_child(_label(
		"为更复杂的应用、更大的工作流和下一代设备准备的现代桌面系统。",
		17,
		OS26_MUTED
	))

	var highlights := GridContainer.new()
	highlights.columns = 3
	highlights.add_theme_constant_override("h_separation", 10)
	highlights.add_theme_constant_override("v_separation", 10)
	root.add_child(highlights)
	highlights.add_child(_make_os26_feature("01", "MODULAR DESKTOP", "窗口、底栏和应用可以在统一的桌面框架中协同工作。"))
	highlights.add_child(_make_os26_feature("02", "LOCAL DATA", "应用数据按电脑实体保存，便于在不同设备上保持清晰的数据边界。"))
	highlights.add_child(_make_os26_feature("03", "EXTENDED APPS", "支持 Embedded Lab 等需要更高系统能力的应用。"))

	root.add_child(_make_os26_section_heading("系统定位", "OS26 is a modern field workstation platform."))
	root.add_child(_make_os26_panel_text(
		"ChocolateOS26 在保留 OS08 基础操作逻辑的同时，重新设计了桌面层、窗口层和应用兼容机制。它适合固定在工作场所的高端电脑，也适合需要长时间处理资料、研发和设备管理的队伍。",
		"OS08 与 OS26 可以使用同一套应用逻辑，但主题资源、窗口表现和可安装应用列表可以不同。系统不会把本地电脑中的浏览器记录、窗口状态或应用布局自动变成所有电脑都能看到的公共数据。"
	))

	root.add_child(_make_os26_section_heading("运行配置", "以下型号为 ChocolateOS 世界观中的虚构硬件规格。"))
	var requirements := GridContainer.new()
	requirements.columns = 2
	requirements.add_theme_constant_override("h_separation", 12)
	requirements.add_theme_constant_override("v_separation", 12)
	root.add_child(requirements)
	requirements.add_child(_make_os26_requirement_card("最低配置", Color("#eaf2ff"), [
		["处理器", "CircuitCore C4-2400 · 4 核 / 2.4 GHz"],
		["内存", "8 GB FieldRAM"],
		["图形", "VectorLight V2 · 2 GB"],
		["存储", "16 GB 固态存储"],
		["显示", "1280 × 720"],
	]))
	requirements.add_child(_make_os26_requirement_card("推荐配置", Color("#e9fbf8"), [
		["处理器", "CircuitCore C8-4200 · 8 核 / 4.2 GHz"],
		["内存", "16 GB FieldRAM Pro"],
		["图形", "PrismRender P6 · 6 GB"],
		["存储", "64 GB 固态存储"],
		["网络", "ChocolateLink · 1 Gbps"],
	]))

	root.add_child(_make_os26_section_heading("技术进化", "What changed from the early desktop generation."))
	var evolution := VBoxContainer.new()
	evolution.add_theme_constant_override("separation", 8)
	root.add_child(evolution)
	_add_os26_evolution(evolution, "01", "更完整的窗口系统", "支持可调整大小、最小化、最大化、层级聚焦和多应用并行使用，长时间工作时更容易保持上下文。")
	_add_os26_evolution(evolution, "02", "更明确的应用边界", "应用通过受控系统接口读取资料和保存数据，不直接访问玩家、电脑节点或其他应用的内部状态。")
	_add_os26_evolution(evolution, "03", "更强的本地存储", "每台电脑可以独立保存应用布局、浏览器数据和应用数据；电脑实体是这些资料的归属边界。")
	_add_os26_evolution(evolution, "04", "更宽的兼容范围", "系统可以识别应用支持的 OS 和最低版本，并在安装前检查兼容性与依赖关系。")
	_add_os26_evolution(evolution, "05", "为 Embedded Lab 准备", "OS26 可以运行 Embedded Lab，为后续的程序研发、硬盘写入和设备管理功能预留系统能力。")

	root.add_child(_make_os26_section_heading("基础应用与兼容性", "A calm upgrade path from OS08."))
	root.add_child(_make_os26_panel_text(
		"OS26 默认保留 Browser、My Computer、Network、Recycle Bin、Settings 和 Shutdown 等系统应用。Farm Info 与 Weather 可以作为基础信息应用继续使用；更高等级的应用则由系统兼容列表决定是否能够安装。",
		"OS26 的现代化主要体现在系统能力和信息组织方式，而不是把每个界面都做得复杂。桌面仍然服务于农场、工业生产、载具和队伍管理这些实际工作。"
	))

	var note := _make_os26_note("硬件提示", "如果电脑只需要浏览网页、查看天气和管理农场信息，OS08 已经足够。需要 Embedded Lab 或更复杂应用时，再选择满足 OS26 配置要求的设备。")
	root.add_child(note)
	_add_os26_link(root, "返回 ChocolateOS08 资料 →", PAGE_OS08)
	var footer := _label("CIRCUIT & CHAI · CHOCOLATEOS ARCHIVE / FICTIONAL SPECIFICATIONS", 11, OS26_MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)


func _add_os26_hero(root: VBoxContainer) -> void:
	var hero := PanelContainer.new()
	hero.custom_minimum_size.y = 112.0
	hero.add_theme_stylebox_override("panel", _style_box(OS26_NAVY, OS26_NAVY, 0, 12))
	root.add_child(hero)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_bottom", 14)
	hero.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var logo_frame := PanelContainer.new()
	logo_frame.custom_minimum_size = Vector2(78, 78)
	logo_frame.add_theme_stylebox_override("panel", _style_box(Color("#ffffff"), Color("#ffffff"), 0, 10))
	row.add_child(logo_frame)
	var logo := TextureRect.new()
	logo.custom_minimum_size = Vector2(76, 76)
	logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture = load(LOGO_OS26) as Texture2D
	logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_frame.add_child(logo)
	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.alignment = BoxContainer.ALIGNMENT_CENTER
	copy.add_theme_constant_override("separation", 3)
	row.add_child(copy)
	var brand := _label("CIRCUIT & CHAI", 14, Color("#9bdcf3"))
	copy.add_child(brand)
	var title := _label("ChocolateOS26", 28, Color.WHITE)
	copy.add_child(title)
	var sub := _label("MODERN FIELD DESKTOP / SYSTEM PROFILE", 11, Color("#b8c9e8"))
	copy.add_child(sub)
	var version := _label("26", 44, Color("#78d5e9"))
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	version.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(version)


func _add_navigation(root: VBoxContainer, modern: bool) -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	_add_nav_button(nav, "OS08", PAGE_OS08, modern)
	_add_nav_button(nav, "OS26", PAGE_OS26, modern)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var label := _label("系统资料 / SYSTEM NOTES", 11, OS26_MUTED if modern else OS08_MUTED)
	nav.add_child(label)


func _add_nav_button(parent: HBoxContainer, text_value: String, target_page: String, modern: bool) -> void:
	var button := Button.new()
	button.text = text_value
	button.disabled = target_page == page_id
	button.custom_minimum_size = Vector2(74, 32)
	button.focus_mode = Control.FOCUS_NONE
	if modern:
		button.add_theme_color_override("font_color", OS26_BLUE)
		button.add_theme_color_override("font_disabled_color", OS26_MUTED)
		button.add_theme_stylebox_override("normal", _style_box(OS26_PANEL, OS26_LINE, 1, 7))
		button.add_theme_stylebox_override("hover", _style_box(Color("#e7f0ff"), OS26_BLUE, 1, 7))
		button.add_theme_stylebox_override("disabled", _style_box(Color("#dce8f7"), OS26_LINE, 1, 7))
	else:
		button.add_theme_color_override("font_color", OS08_INK)
		button.add_theme_color_override("font_disabled_color", OS08_MUTED)
		button.add_theme_stylebox_override("normal", _style_box(OS08_BACKGROUND, OS08_LINE, 1, 0))
		button.add_theme_stylebox_override("hover", _style_box(Color("#eeeeee"), OS08_LINE, 1, 0))
		button.add_theme_stylebox_override("disabled", _style_box(Color("#eeeeee"), OS08_LINE, 1, 0))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	parent.add_child(button)


func _navigate_to_page(target_page: String) -> void:
	if not is_instance_valid(desktop):
		return
	var path := "/os26" if target_page == PAGE_OS26 else "/os08"
	desktop.call("navigate_browser_from_page", browser_app_id, "www.circuitandchai.com%s" % path)


func _add_os08_link(root: VBoxContainer, text_value: String, target_page: String) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 34.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", OS08_INK)
	button.add_theme_stylebox_override("normal", _style_box(OS08_BACKGROUND, OS08_LINE, 1, 0))
	button.add_theme_stylebox_override("hover", _style_box(Color("#eeeeee"), OS08_LINE, 1, 0))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	root.add_child(button)


func _add_os26_link(root: VBoxContainer, text_value: String, target_page: String) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 38.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", OS26_BLUE)
	button.add_theme_stylebox_override("normal", _style_box(OS26_PANEL, OS26_LINE, 1, 8))
	button.add_theme_stylebox_override("hover", _style_box(Color("#e7f0ff"), OS26_BLUE, 1, 8))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	root.add_child(button)


func _os08_section_title(text_value: String) -> Label:
	var label := _label(text_value, 13, OS08_INK)
	return label


func _make_os08_list(lines: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(OS08_BACKGROUND, OS08_LINE, 1, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	margin.add_child(list)
	for line_value: Variant in lines:
		list.add_child(_label("- " + str(line_value), 14, OS08_INK))
	return panel


func _make_os08_table(rows: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(OS08_BACKGROUND, OS08_LINE, 1, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)
	var table := GridContainer.new()
	table.columns = 2
	table.add_theme_constant_override("h_separation", 18)
	table.add_theme_constant_override("v_separation", 4)
	margin.add_child(table)
	for row_value: Variant in rows:
		var row: Array = row_value as Array
		table.add_child(_label(str(row[0]), 14, OS08_INK))
		var value := _label(str(row[1]), 14, OS08_INK)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		table.add_child(value)
	return panel


func _make_os08_notice(text_value: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(OS08_BACKGROUND, OS08_LINE, 1, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	panel.add_child(margin)
	margin.add_child(_label(text_value, 13, OS08_MUTED))
	return panel


func _os08_rule() -> HSeparator:
	var rule := HSeparator.new()
	rule.add_theme_constant_override("separation", 0)
	rule.add_theme_color_override("separator", OS08_LINE)
	return rule


func _make_os26_feature(number: String, heading: String, text_value: String) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(210, 134)
	panel.add_theme_stylebox_override("panel", _style_box(OS26_PANEL, OS26_LINE, 1, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	box.add_child(_label(number, 12, OS26_CYAN))
	box.add_child(_label(heading, 14, OS26_INK))
	box.add_child(_label(text_value, 12, OS26_MUTED))
	return panel


func _make_os26_section_heading(title_value: String, subtitle_value: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.add_child(_label(title_value, 22, OS26_INK))
	box.add_child(_label(subtitle_value, 12, OS26_BLUE))
	return box


func _make_os26_panel_text(first: String, second: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(OS26_PANEL, OS26_LINE, 1, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	box.add_child(_label(first, 14, OS26_INK))
	box.add_child(_label(second, 14, OS26_MUTED))
	return panel


func _make_os26_requirement_card(title_value: String, tint: Color, rows: Array) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(320, 238)
	panel.add_theme_stylebox_override("panel", _style_box(OS26_PANEL, OS26_LINE, 1, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 7)
	margin.add_child(box)
	var title := _label(title_value, 17, OS26_INK)
	box.add_child(title)
	var bar := ColorRect.new()
	bar.color = tint
	bar.custom_minimum_size.y = 4.0
	box.add_child(bar)
	for row_value: Variant in rows:
		var row: Array = row_value as Array
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		box.add_child(line)
		var key := _label(str(row[0]), 12, OS26_MUTED)
		key.custom_minimum_size.x = 58.0
		line.add_child(key)
		var value := _label(str(row[1]), 12, OS26_INK)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
	return panel


func _add_os26_evolution(parent: VBoxContainer, number: String, heading: String, text_value: String) -> void:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(OS26_PANEL, OS26_LINE, 1, 8))
	parent.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var number_label := _label(number, 13, OS26_CYAN)
	number_label.custom_minimum_size.x = 28.0
	row.add_child(number_label)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	row.add_child(text_box)
	text_box.add_child(_label(heading, 15, OS26_INK))
	text_box.add_child(_label(text_value, 13, OS26_MUTED))


func _make_os26_note(title_value: String, text_value: String) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style_box(Color("#e9f8fb"), Color("#a8dce6"), 1, 10))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 11)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 11)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	margin.add_child(box)
	box.add_child(_label(title_value, 14, OS26_CYAN))
	box.add_child(_label(text_value, 13, OS26_INK))
	return panel


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _style_box(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style
