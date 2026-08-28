extends Control
class_name MercerSeedPage

const HOME_PAGE := "home"
const SEED_GUIDE_PAGE := "seed_guide"
const ICON_ROOT := "res://assets/icons/mercersed/"
const PAGE_WIDTH := 720.0
const PAGE_MARGIN := 28

const BACKGROUND := Color("#edf7e8")
const SURFACE := Color("#f8fcf5")
const SURFACE_ALT := Color("#e5f1df")
const SOFT_GREEN := Color("#dcefd3")
const INK := Color("#263b29")
const MUTED := Color("#58705a")
const ACCENT := Color("#3d7447")
const ACCENT_DARK := Color("#285235")
const WARNING := Color("#7b692b")
const WARNING_BG := Color("#f6f4dc")

const CROP_NOTES := {
	"tomato": "需求稳定、用途广，适合作为日常轮作里的可靠选择。",
	"corn": "投入低、周转快，适合在需要稳定补充现金流时安排。",
	"wheat": "基础粮食作物，销售稳定，也方便留作面粉和烘焙原料。",
	"pumpkin": "成熟快但需要更宽的生长空间，适合填补短周期空地。",
	"watermelon": "单次收成醒目，成熟周期短，适合在有空闲地块时快速周转。",
	"pepper": "调味需求稳定，周期比基础作物长，适合和快熟作物错峰安排。",
	"eggplant": "用途稳定、投入适中，适合与番茄等常见蔬菜搭配种植。",
	"strawberry": "高价值水果，但等待时间长，最好安排在较安全、便于照看的土地。",
	"beet": "价格和周期都比较均衡，适合新农场用来熟悉中等投入作物。",
	"cabbage": "成本低、成熟快，是补足基础蔬菜库存的稳妥选择。",
	"cotton": "不用于厨房，适合有加工计划的队伍；先确认后续纤维需求再扩大面积。",
	"lettuce": "适合沙拉和日常料理，需求规律，适合作为基础蔬菜持续供应。",
	"mint": "香草价值较高但等待更久，适合和短周期作物搭配，避免土地闲置。",
	"peanut": "坚果类用途多，周期适中，适合在料理和原料订单之间灵活调配。",
	"sugarcane": "成本低、用途明确，可以为糖和甜点原料提供连续补给。",
	"tobacco": "稀有经济作物，投入和风险都高；不要把全部土地押在同一批收成上。",
	"grape": "首次结果后可以再次采收，适合愿意长期维护同一片土地的队伍。",
	"kiwi": "可重复采收、周期略长，适合做稳定的长期水果供应。",
	"hazelnut": "高价值坚果，等待时间较长，应优先安排在不容易被破坏的地块。",
	"pistachio": "稀有且投入高，适合有稳定保护能力和长期计划的农场。",
	"walnut": "成熟后可持续收获，适合把一部分土地作为长期资产经营。",
	"soybean": "投入低、用途灵活，适合在粮食、料理和加工需求之间周转。",
	"blackpepper": "调味作物单价高但投入也高，建议小批量种植并配合稳定订单。",
	"potato": "成熟快、用途广，是短周期补货和填充空闲地块的好选择。",
}

const CATEGORY_NAMES := {
	"vegetable": "蔬菜",
	"grain": "谷物",
	"fruit": "水果",
	"fiber_crop": "纤维作物",
	"herb": "香草",
	"nut": "坚果",
	"sweetener_crop": "甜味原料",
	"leaf_crop": "叶片经济作物",
	"legume": "豆类",
	"spice": "香辛作物",
}

var desktop: Node
var browser_app_id := "browser"
var page_id := HOME_PAGE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, requested_page_id: String, owner_browser_app_id := "browser") -> void:
	desktop = owner_desktop
	browser_app_id = owner_browser_app_id
	page_id = requested_page_id if requested_page_id in [HOME_PAGE, SEED_GUIDE_PAGE] else HOME_PAGE
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(PAGE_WIDTH, 1040.0 if page_id == HOME_PAGE else 2700.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	if page_id == SEED_GUIDE_PAGE:
		_build_seed_guide()
	else:
		_build_home()


func _build_home() -> void:
	var margin := _make_page_margin(30, 30)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)
	_add_site_header(root)
	_add_navigation(root)

	var title := _label("农场用品与种子公告", 28, INK)
	root.add_child(title)
	root.add_child(_label(
		"Leah Mercer 整理的农场用品、种子和种植记录。这里的建议来自实际耕作经验，价格以当前柜台为准。",
		15,
		MUTED
	))

	root.add_child(_make_notice(
		"店铺公告",
		"本周柜台继续提供基础种子、蔬菜种子、水果种子、纤维作物和经济作物。第一次安排大面积种植前，建议先看一遍成熟周期和收成用途，再决定要不要把土地全部投入同一种作物。",
		SURFACE
	))
	root.add_child(_make_notice(
		"种子兑换骗局提醒",
		"最近有人冒充农场用品店，用私下转账或所谓“半价稀有种子兑换码”收钱。Mercer Seed & Supply 不通过私信兑换种子，也不会要求把队伍资金交给个人账户。看见可疑消息时，请直接回到实体柜台核对。",
		WARNING_BG
	))

	var store_heading := _label("店铺信息", 21, ACCENT_DARK)
	root.add_child(store_heading)
	root.add_child(_make_info_list([
		["服务", "种子与农场用品咨询、种植周期建议、基础作物搭配"],
		["供应", "基础、普通、高级和稀有作物种子均按当前柜台规则提供"],
		["交易", "请在实体店完成购买或兑换；不要相信未登记的线上种子页面"],
		["建议", "长周期作物要预留保护和照料时间，短周期作物适合填补空闲土地"],
	]))

	root.add_child(_make_notice(
		"Leah 的今日建议",
		"先用小麦、玉米、土豆或卷心菜熟悉土地节奏，再把一部分安全地块交给草莓、烟草、开心果等长周期作物。稳定的基础收成，通常比一次押满稀有作物更容易安排。",
		SOFT_GREEN
	))
	_add_link_button(root, "查看完整种子指南 →", SEED_GUIDE_PAGE)
	var footer := _label("MERCER SEED & SUPPLY · FARM NOTES", 11, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)


func _build_seed_guide() -> void:
	var margin := _make_page_margin(24, 28)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)
	_add_site_header(root)
	_add_navigation(root)
	var heading := _label("种子指南", 29, INK)
	root.add_child(heading)
	root.add_child(_label(
		"每格种植成本来自当前播种规则；收购参考价用于帮助你估算收成方向。成熟周期越长，越需要提前安排保护、库存和销售计划。",
		14,
		MUTED
	))
	root.add_child(_make_tier_summary())
	root.add_child(_label("作物目录", 21, ACCENT_DARK))

	var crop_ids := IngredientCatalog.get_plantable_ids()
	var index := 0
	for crop_id: String in crop_ids:
		root.add_child(_make_crop_row(crop_id, index))
		index += 1

	root.add_child(_make_notice(
		"经营提示",
		"不要只看单次收成的价格。把种植成本、等待期间的风险、成熟后是否可以继续采收，以及队伍当前真正需要的原料一起考虑，通常能比单看高价作物更稳妥。",
		SOFT_GREEN
	))
	_add_link_button(root, "返回农场用品公告 →", HOME_PAGE)
	var footer := _label("MERCER SEED & SUPPLY · SEED GUIDE", 11, MUTED)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(footer)
	var bottom_padding := Control.new()
	bottom_padding.custom_minimum_size.y = 30.0
	root.add_child(bottom_padding)
	# Keep the scrollable page tall enough for every crop row, even when
	# translated notes wrap to an extra line at a narrower browser width.
	custom_minimum_size.y = maxf(custom_minimum_size.y, root.get_combined_minimum_size().y + 52.0)


func _add_site_header(root: VBoxContainer) -> void:
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 3)
	root.add_child(header)
	var brand := _label("MERCER SEED & SUPPLY", 25, ACCENT_DARK)
	header.add_child(brand)
	var subtitle := _label("LEAH MERCER'S FARM NOTES", 11, MUTED)
	header.add_child(subtitle)
	var rule := ColorRect.new()
	rule.color = SOFT_GREEN
	rule.custom_minimum_size.y = 5.0
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(rule)


func _add_navigation(root: VBoxContainer) -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 15)
	root.add_child(nav)
	_add_nav_button(nav, "公告", HOME_PAGE)
	_add_nav_button(nav, "种子指南", SEED_GUIDE_PAGE)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var status := _label("实体店公告 / FARM SUPPLY", 11, MUTED)
	nav.add_child(status)


func _add_nav_button(parent: HBoxContainer, text_value: String, target_page: String) -> void:
	var button := Button.new()
	button.text = text_value
	button.disabled = target_page == page_id
	button.custom_minimum_size.y = 30.0
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", ACCENT)
	button.add_theme_color_override("font_disabled_color", INK)
	button.add_theme_stylebox_override("normal", _flat_style(SURFACE, 0))
	button.add_theme_stylebox_override("hover", _flat_style(SOFT_GREEN, 0))
	button.add_theme_stylebox_override("disabled", _flat_style(SOFT_GREEN, 0))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	parent.add_child(button)


func _add_link_button(root: VBoxContainer, text_value: String, target_page: String) -> void:
	var button := Button.new()
	button.text = text_value
	button.custom_minimum_size.y = 34.0
	button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", ACCENT_DARK)
	button.add_theme_stylebox_override("normal", _flat_style(Color(0, 0, 0, 0), 0))
	button.add_theme_stylebox_override("hover", _flat_style(SOFT_GREEN, 0))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	root.add_child(button)


func _navigate_to_page(target_page: String) -> void:
	if not is_instance_valid(desktop):
		return
	var path := "/seed-guide" if target_page == SEED_GUIDE_PAGE else "/"
	desktop.call("navigate_browser_from_page", browser_app_id, "www.mercerseed.com%s" % path)


func _make_notice(title_value: String, text_value: String, background_color: Color) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _flat_style(background_color, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	box.add_child(_label(title_value, 16, ACCENT_DARK))
	box.add_child(_label(text_value, 14, INK))
	return panel


func _make_info_list(rows: Array) -> Control:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 1)
	for row_value: Variant in rows:
		var row: Array = row_value as Array
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 14)
		line.custom_minimum_size.y = 31.0
		list.add_child(line)
		var key := _label(str(row[0]), 13, ACCENT)
		key.custom_minimum_size.x = 52.0
		line.add_child(key)
		var value := _label(str(row[1]), 13, INK)
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.add_child(value)
	return list


func _make_tier_summary() -> Control:
	var summary := PanelContainer.new()
	summary.add_theme_stylebox_override("panel", _flat_style(SURFACE, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	summary.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	box.add_child(_label("四档种植投入", 15, ACCENT_DARK))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 15)
	box.add_child(line)
	for tier: Array in [
		["基础", "$1/格"], ["普通", "$2/格"], ["高级", "$4/格"], ["稀有", "$8/格"],
	]:
		var item := VBoxContainer.new()
		item.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		item.add_theme_constant_override("separation", 2)
		line.add_child(item)
		item.add_child(_label(str(tier[0]), 13, ACCENT))
		item.add_child(_label(str(tier[1]), 12, MUTED))
	return summary


func _make_crop_row(crop_id: String, index: int) -> Control:
	var definition := IngredientCatalog.get_definition(crop_id)
	var source: Dictionary = definition.get("source", {}) as Dictionary
	var category := str(definition.get("category", ""))
	var cost := IngredientCatalog.get_planting_cost(crop_id)
	var tier := _tier_name(cost)
	var product := GlobalVar.get_shop_product(crop_id)
	var buy_price := int(product.get("buy_price", 0))
	var sell_price := int(product.get("sell_price", 0))
	var growth_seconds := float(source.get("growth_time_seconds", 0.0))
	var regrowth_seconds := float(source.get("regrowth_time_seconds", 0.0))
	var row_background := SURFACE if index % 2 == 0 else Color(0, 0, 0, 0)
	var row := PanelContainer.new()
	row.custom_minimum_size.y = 91.0
	row.add_theme_stylebox_override("panel", _flat_style(row_background, 0))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	row.add_child(margin)
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	margin.add_child(layout)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(68, 68)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _load_seed_icon(crop_id)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layout.add_child(icon)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 2)
	layout.add_child(details)
	var name_line := HBoxContainer.new()
	name_line.add_theme_constant_override("separation", 8)
	details.add_child(name_line)
	var name_label := _label(str(definition.get("display_name", crop_id)), 17, INK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_line.add_child(name_label)
	name_line.add_child(_label(tier, 12, _tier_color(cost)))
	var category_label := _label("%s · %s" % [_category_name(category), "可重复采收" if bool(source.get("reharvestable", false)) else "一次采收"], 12, ACCENT)
	details.add_child(category_label)
	var price_label := _label(
		"种子成本 $%d/格 · 采购参考 $%d/kg · 收购参考 $%d/kg" % [cost, buy_price, sell_price],
		12,
		INK
	)
	details.add_child(price_label)
	var cycle_text := "成熟约 %s" % _format_duration(growth_seconds)
	if bool(source.get("reharvestable", false)) and regrowth_seconds > 0.0:
		cycle_text += " · 后续约 %s" % _format_duration(regrowth_seconds)
	var cycle_label := _label(cycle_text, 12, MUTED)
	details.add_child(cycle_label)
	var note := _label(str(CROP_NOTES.get(crop_id, "按队伍需求安排种植，并为成熟期预留照料时间。")), 12, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(note)
	return row


func _load_seed_icon(crop_id: String) -> Texture2D:
	# Mercer Seed's web assets are a deliberate copy of the harvest-drop item
	# icons. Keep this page independent from the inventory icon directory.
	var path := ICON_ROOT + crop_id + ".png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _tier_name(cost: int) -> String:
	match cost:
		1: return "基础"
		2: return "普通"
		4: return "高级"
		_: return "稀有"


func _tier_color(cost: int) -> Color:
	match cost:
		1: return Color("#527456")
		2: return Color("#3f7b50")
		4: return Color("#31724b")
		_: return Color("#6d642c")


func _category_name(category: String) -> String:
	return str(CATEGORY_NAMES.get(category, "农作物"))


func _format_duration(seconds: float) -> String:
	var total := maxi(0, roundi(seconds))
	if total < 60:
		return "%d秒" % total
	return "%d分%02d秒" % [total / 60, total % 60]


func _make_page_margin(top: int, bottom: int) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", top)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", bottom)
	return margin


func _label(text_value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _flat_style(background: Color, border_width: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = Color(0, 0, 0, 0)
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.content_margin_left = 5.0
	style.content_margin_right = 5.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style
