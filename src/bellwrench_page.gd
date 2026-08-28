extends Control
class_name BellwrenchPage

const DOMAIN := "www.bellwrench.com"
const PAGE_VEHICLES := "vehicles"
const PAGE_SERVICE := "service"
const PAGE_UPGRADES := "upgrades"
const PAGE_FARM_BASE := "farm_base"
const PAGE_WIDTH := 720.0

# Bellwrench uses flat charcoal surfaces. Accents are restricted to text and
# status labels; panels and buttons intentionally have no border widths.
const BACKGROUND := Color("#24272a")
const SURFACE := Color("#303438")
const SURFACE_ALT := Color("#383d42")
const SURFACE_DARK := Color("#1d2023")
const TEXT := Color("#f1f3f4")
const MUTED := Color("#aeb5bb")
const RED := Color("#e06a62")
const ORANGE := Color("#d7a05c")
const GREEN := Color("#8fb58f")

const VEHICLE_ORDER := [
	"atv",
	"mini_car",
	"van",
	"farm_base",
	"sedan",
	"sport_car",
]

const VEHICLES := {
	"atv": {
		"name": "越野摩托车",
		"price": 20000,
		"config": "res://vehicles/atv_config.tres",
	},
	"mini_car": {
		"name": "迷你车",
		"price": 22000,
		"config": "res://vehicles/mini_car_config.tres",
	},
	"van": {
		"name": "厢式货车",
		"price": 26000,
		"config": "res://vehicles/van_config.tres",
	},
	"farm_base": {
		"name": "农场基础载具",
		"price": 30000,
		"config": "res://vehicles/farm_base_vehicle_config.tres",
	},
	"sedan": {
		"name": "轿车",
		"price": 32000,
		"config": "res://vehicles/sedan_config.tres",
	},
	"sport_car": {
		"name": "运动型跑车",
		"price": 39000,
		"config": "res://vehicles/sport_car_config.tres",
	},
}

const COMMON_UPGRADES := [
	{
		"id": "high_performance_motor",
		"name": "高性能电机",
		"description": "提高动力输出和最高速度，适合希望缩短道路运输时间的载具。",
	},
	{
		"id": "composite_armor_panel",
		"name": "复合装甲板",
		"description": "增加载具的防护能力和 HP，使载具在危险环境中更耐用。",
	},
	{
		"id": "vehicle_control_module",
		"name": "车辆控制模块",
		"description": "优化动力与转向响应，让载具在狭窄道路和复杂地形中更容易控制。",
	},
	{
		"id": "battery_pack",
		"name": "电池包",
		"description": "提供额外储能，延长载具电子系统和相关模块的续航时间。",
	},
]

const FARM_BASE_UPGRADES := [
	{
		"id": "vehicle_harvest_reel",
		"name": "收割模块",
		"description": "让 FarmBaseVehicle 能够配合农场作业处理成熟作物。",
	},
	{
		"id": "vehicle_extended_seat",
		"name": "扩展座椅",
		"description": "为 FarmBaseVehicle 的外部平台增加乘员位置。",
	},
	{
		"id": "vehicle_roof_headlights",
		"name": "车顶大灯",
		"description": "在车顶增加辅助照明，扩大夜间和低能见度环境下的照明范围。",
	},
	{
		"id": "vehicle_machine_gun",
		"name": "车载机枪",
		"description": "安装在 FarmBaseVehicle 平台上的防卫模块，需要在载具店完成固定和调试。",
	},
	{
		"id": "vehicle_nitro_boost",
		"name": "氮气加速装置",
		"description": "提供短时间的额外加速能力，仅适用于 FarmBaseVehicle。",
	},
	{
		"id": "vehicle_roof_cooling_system",
		"name": "车载冷却系统",
		"description": "帮助 FarmBaseVehicle 的高负载设备维持更稳定的工作温度。",
	},
	{
		"id": "vehicle_signal_augment",
		"name": "车载信号增强塔",
		"description": "增强 FarmBaseVehicle 的车载信号覆盖和设备联络能力。",
	},
]

const NAV_ITEMS := [
	[PAGE_VEHICLES, "车辆目录"],
	[PAGE_SERVICE, "维修服务"],
	[PAGE_UPGRADES, "升级模块"],
	[PAGE_FARM_BASE, "FarmBase 专区"],
]

var desktop: Node
var browser_app_id := "browser"
var page_id := PAGE_VEHICLES


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, requested_page_id: String, owner_browser_app_id := "browser") -> void:
	desktop = owner_desktop
	browser_app_id = owner_browser_app_id
	page_id = requested_page_id if requested_page_id in [
		PAGE_VEHICLES, PAGE_SERVICE, PAGE_UPGRADES, PAGE_FARM_BASE,
	] else PAGE_VEHICLES
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(PAGE_WIDTH, _page_height())

	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_add_header(root)
	_add_navigation(root)

	match page_id:
		PAGE_SERVICE:
			_build_service(root)
		PAGE_UPGRADES:
			_build_upgrades(root)
		PAGE_FARM_BASE:
			_build_farm_base(root)
		_:
			_build_vehicles(root)

	var footer := _label("BELLWRENCH · 资料展示页 · 维修和安装请前往实体载具店", 11, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)
	var bottom_padding := Control.new()
	bottom_padding.custom_minimum_size.y = 20.0
	root.add_child(bottom_padding)


func _add_header(root: VBoxContainer) -> void:
	var header := _flat_panel(SURFACE_DARK, 88.0, 0)
	root.add_child(header)
	var margin := _inner_margin(header, 18, 16, 18, 16)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)
	var brand_box := VBoxContainer.new()
	brand_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(brand_box)
	brand_box.add_child(_label("BELLWRENCH", 27, TEXT))
	brand_box.add_child(_label("VEHICLE SERVICE / FIELD GARAGE", 11, ORANGE))
	var status := _label("只读目录\n实体店服务", 12, MUTED)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(status)


func _add_navigation(root: VBoxContainer) -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	root.add_child(nav)
	for item: Array in NAV_ITEMS:
		_add_nav_button(nav, str(item[1]), str(item[0]))


func _add_nav_button(parent: HBoxContainer, text_value: String, target_page_id: String) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size = Vector2(154.0, 34.0)
	button.disabled = target_page_id == page_id
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", 13)
	button.add_theme_color_override("font_color", TEXT)
	button.add_theme_color_override("font_hover_color", TEXT)
	button.add_theme_color_override("font_pressed_color", TEXT)
	button.add_theme_color_override("font_disabled_color", ORANGE)
	button.add_theme_stylebox_override("normal", _flat_style(SURFACE, 0))
	button.add_theme_stylebox_override("hover", _flat_style(SURFACE_ALT, 0))
	button.add_theme_stylebox_override("pressed", _flat_style(SURFACE_DARK, 0))
	button.add_theme_stylebox_override("disabled", _flat_style(SURFACE_DARK, 0))
	button.add_theme_stylebox_override("focus", _flat_style(SURFACE_ALT, 0))
	button.pressed.connect(_navigate_to_page.bind(target_page_id))
	parent.add_child(button)


func _build_vehicles(root: VBoxContainer) -> void:
	root.add_child(_label("可购买载具", 29, TEXT))
	root.add_child(_label(
		"选择适合当前工作方式的车辆。以下内容只展示参考售价和最高速度。",
		14,
		MUTED,
	))
	var grid := _make_grid(2)
	root.add_child(grid)
	for vehicle_id_value: Variant in VEHICLE_ORDER:
		grid.add_child(_make_vehicle_card(str(vehicle_id_value)))
	root.add_child(_flat_notice(
		"资料说明",
		"参考售价用于帮助队伍规划资金；实际购买、交付和后续维修均需要在载具商店或维修店完成。",
		GREEN,
	))


func _make_vehicle_card(vehicle_id: String) -> Control:
	var data: Dictionary = VEHICLES.get(vehicle_id, {}) as Dictionary
	var card := _flat_panel(SURFACE, 122.0, 0)
	var margin := _inner_margin(card, 14, 13, 14, 13)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(_label(str(data.get("name", vehicle_id)), 19, TEXT))
	name_box.add_child(_label("Bellwrench 参考目录", 11, MUTED))
	row.add_child(name_box)
	var details := VBoxContainer.new()
	details.custom_minimum_size.x = 150.0
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(details)
	details.add_child(_label("参考售价  $%s" % _format_money(int(data.get("price", 0))), 15, ORANGE))
	details.add_child(_label("最高速度  %s m/s" % _get_vehicle_speed(vehicle_id), 14, TEXT))
	return card


func _build_service(root: VBoxContainer) -> void:
	root.add_child(_label("维修服务", 29, TEXT))
	root.add_child(_label(
		"先检测，再报价，最后由维修技师完成处理。网页只提供服务规则和价格参考。",
		14,
		MUTED,
	))
	var steps := _make_grid(3)
	root.add_child(steps)
	for step: Array in [
		["01", "检测", "确认载具当前状况和需要处理的部位。"],
		["02", "报价", "根据损坏程度和服务类型给出现场报价。"],
		["03", "维修", "确认后由载具店完成修复和功能检查。"],
	]:
		steps.add_child(_make_step_card(str(step[0]), str(step[1]), str(step[2])))

	root.add_child(_label("维修参考价格", 20, TEXT))
	var repair_grid := VBoxContainer.new()
	repair_grid.add_theme_constant_override("separation", 6)
	root.add_child(repair_grid)
	for row_data: Array in [
		["轻微损伤", "$200 – $500", "适合小范围外观或轻度功能损伤"],
		["中度损伤", "$600 – $1,500", "需要对多个部位进行检查和修复"],
		["重度损伤", "$1,500 – $4,000", "完成大范围损坏修复后再进行安全检查"],
	]:
		repair_grid.add_child(_make_service_row(str(row_data[0]), str(row_data[1]), str(row_data[2])))

	root.add_child(_flat_notice(
		"改色与升级安装",
		"改色需要在实体店选择颜色并确认报价。所有配件安装、调试和兼容性检查都由载具店完成，本网页不接受在线订单。",
		ORANGE,
	))


func _make_step_card(number: String, title: String, description: String) -> Control:
	var card := _flat_panel(SURFACE, 126.0, 0)
	var margin := _inner_margin(card, 12, 12, 12, 12)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)
	content.add_child(_label(number, 12, RED))
	content.add_child(_label(title, 18, TEXT))
	content.add_child(_label(description, 12, MUTED))
	return card


func _make_service_row(title: String, price: String, description: String) -> Control:
	var row := _flat_panel(SURFACE, 62.0, 0)
	var margin := _inner_margin(row, 14, 10, 14, 10)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var title_label := _label(title, 16, TEXT)
	title_label.custom_minimum_size.x = 130.0
	layout.add_child(title_label)
	var price_label := _label(price, 15, ORANGE)
	price_label.custom_minimum_size.x = 135.0
	layout.add_child(price_label)
	var note := _label(description, 12, MUTED)
	note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(note)
	return row


func _build_upgrades(root: VBoxContainer) -> void:
	root.add_child(_label("通用升级模块", 29, TEXT))
	root.add_child(_label(
		"四种通用模块适用于六种可购买载具，包括农场基础载具。每个部件都需要在载具店安装。",
		14,
		MUTED,
	))
	var compatibility := _flat_notice(
		"通用兼容范围",
		"农场基础载具 · 越野摩托车 · 迷你车 · 厢式货车 · 轿车 · 运动型跑车",
		GREEN,
	)
	root.add_child(compatibility)
	var grid := _make_grid(2)
	root.add_child(grid)
	for upgrade: Dictionary in COMMON_UPGRADES:
		grid.add_child(_make_upgrade_card(upgrade, "通用升级"))
	root.add_child(_flat_notice(
		"FarmBaseVehicle 专属模块",
		"收割模块、扩展座椅、车顶大灯、车载机枪、氮气加速、车载冷却系统和车载信号增强塔请查看 FarmBase 专区。",
		RED,
	))


func _build_farm_base(root: VBoxContainer) -> void:
	root.add_child(_label("FarmBaseVehicle 专区", 29, TEXT))
	root.add_child(_label(
		"这些配件只为农场基础载具设计，安装后由载具店负责调试和维护。",
		14,
		MUTED,
	))
	var grid := _make_grid(2)
	root.add_child(grid)
	for upgrade: Dictionary in FARM_BASE_UPGRADES:
		grid.add_child(_make_upgrade_card(upgrade, "仅限 FarmBaseVehicle"))
	root.add_child(_flat_notice(
		"安装提醒",
		"配件制作或获得后，请将载具和配件一起交给载具店。玩家不能直接在场外安装这些模块。",
		ORANGE,
	))


func _make_upgrade_card(upgrade: Dictionary, compatibility: String) -> Control:
	var card := _flat_panel(SURFACE, 174.0, 0)
	var margin := _inner_margin(card, 13, 12, 13, 12)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	margin.add_child(content)
	content.add_child(_label(str(upgrade.get("name", "升级模块")), 18, TEXT))
	content.add_child(_label(compatibility, 11, RED))
	var description := _label(str(upgrade.get("description", "")), 12, MUTED)
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(description)
	var price := _get_item_price(str(upgrade.get("id", "")))
	content.add_child(_label("部件参考价  $%s" % _format_money(price), 13, ORANGE))
	content.add_child(_label("需要在载具店安装", 12, GREEN))
	return card


func _flat_notice(title: String, description: String, accent: Color) -> Control:
	var panel := _flat_panel(SURFACE_DARK, 90.0, 0)
	var margin := _inner_margin(panel, 14, 12, 14, 12)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 4)
	margin.add_child(content)
	content.add_child(_label(title, 15, accent))
	var text := _label(description, 13, TEXT)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(text)
	return panel


func _make_grid(columns: int) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = columns
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	return grid


func _flat_panel(color: Color, minimum_height: float, radius: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, minimum_height)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _flat_style(color, radius))
	return panel


func _inner_margin(parent: Control, left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", left)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", right)
	margin.add_theme_constant_override("margin_bottom", bottom)
	parent.add_child(margin)
	return margin


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label


func _get_vehicle_speed(vehicle_id: String) -> String:
	var data: Dictionary = VEHICLES.get(vehicle_id, {}) as Dictionary
	var config := load(str(data.get("config", ""))) as VehicleConfig
	if config == null:
		return "—"
	return "%.0f" % config.max_forward_speed


func _get_item_price(item_id: String) -> int:
	if not is_instance_valid(GlobalVar):
		return 0
	var product := GlobalVar.get_shop_product(item_id)
	return int(product.get("buy_price", 0))


func _format_money(value: int) -> String:
	var raw := str(maxi(0, value))
	var result := ""
	while raw.length() > 3:
		result = "," + raw.right(3) + result
		raw = raw.left(raw.length() - 3)
	return raw + result


func _page_height() -> float:
	match page_id:
		PAGE_SERVICE:
			return 930.0
		PAGE_UPGRADES:
			return 1080.0
		PAGE_FARM_BASE:
			return 1340.0
		_:
			return 900.0


func _navigate_to_page(target_page_id: String) -> void:
	if not is_instance_valid(desktop):
		return
	var path: String = str({
		PAGE_VEHICLES: "/vehicles",
		PAGE_SERVICE: "/service",
		PAGE_UPGRADES: "/upgrades",
		PAGE_FARM_BASE: "/farm-base",
	}.get(target_page_id, "/vehicles"))
	desktop.call("navigate_browser_from_page", browser_app_id, DOMAIN + path)


func _flat_style(color: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 4.0
	style.content_margin_right = 4.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style
