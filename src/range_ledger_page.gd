extends Control
class_name RangeLedgerPage

const PAGE_CATALOG := "catalog"
const PAGE_FUTURE_SERIES := "future_series"
const PAGE_SAFETY := "safety"
const IMAGE_ROOT := "res://assets/icons/rangeledger/"

const INK := Color("#e9e9e9")
const MUTED := Color("#a6a6a6")
const RED := Color("#d44a4a")
const RED_DARK := Color("#711f27")
const PAPER := Color("#101010")
const PANEL := Color("#1b1b1b")
const LINE := Color("#4a4a4a")
const IMAGE_PANEL := Color("#292929")
const WARNING := Color("#f06d6d")

const PRODUCTS := {
	"mpx": {
		"name": "MPX 冲锋枪",
		"category": "紧凑型冲锋枪",
		"range": "100 米",
		"summary": "适合近中距离快速反应，体积紧凑，便于在仓库和狭窄道路中携带；淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"m4": {
		"name": "M4 卡宾枪",
		"category": "现代卡宾枪",
		"range": "中远距离",
		"summary": "射击表现均衡，适合需要在不同环境中保持稳定火力的队伍；淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"ak47": {
		"name": "AK47 突击步枪",
		"category": "现代突击步枪",
		"power": "50",
		"range": "120 米",
		"summary": "双手持握的中远距离步枪，单发伤害50，射速7.14发/秒，弹匣容量30发；黄金版、锈铁、淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"ar15": {
		"name": "AR15 步枪",
		"category": "现代步枪",
		"range": "较远距离",
		"summary": "更偏向远距离使用的步枪，适合开阔地形和需要保持距离的场合；淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"shotgun": {
		"name": "双管猎枪",
		"category": "双管猎枪",
		"range": "近距离",
		"summary": "近距离瞬间压制力强，适合室内、车辆周围和短距离防卫；锈铁为同属性外观版本。",
	},
	"remington870": {
		"name": "Remington870",
		"category": "泵动霰弹枪",
		"power": "65 × 4",
		"range": "50 米",
		"summary": "近距离泵动霰弹枪，每次发射4颗弹丸，每颗伤害65；锈铁、淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"p90": {
		"name": "P90 冲锋枪",
		"category": "紧凑型高射速冲锋枪",
		"power": "32",
		"range": "90 米",
		"summary": "双手持握的紧凑型高射速冲锋枪，单发伤害32，射速12.5发/秒，弹匣容量50发；乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"hunting_rifle": {
		"name": "栓动猎枪",
		"category": "栓动步枪",
		"range": "120 米",
		"summary": "射击节奏较慢，但适合在较远距离进行有计划的单发射击。",
	},
	"crossbow": {
		"name": "弩",
		"category": "弩具",
		"range": "120 米",
		"summary": "适合安静处理远处目标；淬火钢为同属性外观版本。使用前应确认箭矢准备和周围安全。",
	},
	"suppressed_pistol": {
		"name": "消音手枪",
		"category": "单手手枪",
		"range": "100 米",
		"summary": "便于随身携带和快速拔取，适合需要降低声响的短时行动；淬火钢、乡村迷彩和雪地迷彩为同属性外观版本。",
	},
	"m17": {
		"name": "M17 手枪",
		"category": "战术手枪",
		"power": "31",
		"range": "80 米",
		"summary": "单手持握的战术手枪，配备可切换战术手电筒；雪地迷彩、乡村迷彩和淬火钢为同属性外观版本。",
	},
	"future_m4": {
		"name": "FutureM4",
		"category": "未来型卡宾枪",
		"power": "48",
		"range": "中远距离",
		"show_price": false,
		"summary": "目前发现的未知型号之一。它由突然出现在战区的武装士兵携带，威力略高于现代卡宾枪；武器来源和使用者身份仍在调查。",
	},
	"future_mpx": {
		"name": "FutureMPX",
		"category": "未来型冲锋枪",
		"power": "35",
		"range": "100 米",
		"show_price": false,
		"summary": "另一种未知型号，曾由不明工程人员和武装士兵携带。它的威力略高于现代冲锋枪，但出现地点、技术来源和行动目的都没有得到确认。",
	},
	"ammo_supply_box": {
		"name": "200 发弹药盒",
		"category": "弹药补给",
		"range": "弹药资源",
		"summary": "用于补充队伍弹药储备；出发前根据常用武器和任务时长核对数量。",
	},
	"grenade": {
		"name": "手雷",
		"category": "投掷装备",
		"range": "爆炸范围",
		"summary": "投掷前确认队友位置和掩体情况，使用后与爆炸区域保持安全距离。",
	},
}

const PAGE_DEFINITIONS := {
	PAGE_CATALOG: {
		"title": "枪械目录",
		"eyebrow": "FIREARM REFERENCE",
		"intro": "常规枪械的外观、价格和适用射程参考。",
		"products": ["mpx", "m4", "ak47", "ar15", "shotgun", "remington870", "p90", "hunting_rifle", "crossbow", "suppressed_pistol", "m17"],
	},
	PAGE_FUTURE_SERIES: {
		"title": "Future 系列调查档案",
		"eyebrow": "UNIDENTIFIED ARMAMENT CASE FILE",
		"intro": "这些武器尚未进入武器商店目录。以下内容来自对未知武装人员装备的现场记录。",
		"products": ["future_m4", "future_mpx"],
	},
	PAGE_SAFETY: {
		"title": "安全与补给",
		"eyebrow": "SAFETY & SUPPLY NOTES",
		"intro": "弹药与投掷装备的价格参考，以及使用前需要确认的事项。",
		"products": ["ammo_supply_box", "grenade"],
	},
}

var desktop: Node
var browser_app_id := "browser"
var page_id := PAGE_CATALOG


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, requested_page_id: String, owner_browser_app_id := "browser") -> void:
	desktop = owner_desktop
	browser_app_id = owner_browser_app_id
	page_id = requested_page_id if PAGE_DEFINITIONS.has(requested_page_id) else PAGE_CATALOG
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(720.0, 760.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var background := ColorRect.new()
	background.color = PAPER
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# The two-column grid is 340 * 2 + 12 wide. Keep the content width at
	# exactly 692px inside the 720px browser page so it never creates a hidden
	# horizontal overflow behind the vertical scrollbar.
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var masthead := PanelContainer.new()
	masthead.custom_minimum_size.y = 72.0
	masthead.add_theme_stylebox_override("panel", _style_box(Color("#080808"), RED_DARK, 1, 0))
	root.add_child(masthead)
	var masthead_margin := MarginContainer.new()
	masthead_margin.add_theme_constant_override("margin_left", 18)
	masthead_margin.add_theme_constant_override("margin_right", 18)
	masthead_margin.add_theme_constant_override("margin_top", 10)
	masthead_margin.add_theme_constant_override("margin_bottom", 10)
	masthead.add_child(masthead_margin)
	var masthead_row := HBoxContainer.new()
	masthead_row.alignment = BoxContainer.ALIGNMENT_CENTER
	masthead_margin.add_child(masthead_row)
	var brand := Label.new()
	brand.text = "RANGE LEDGER"
	brand.add_theme_font_size_override("font_size", 25)
	brand.add_theme_color_override("font_color", RED)
	masthead_row.add_child(brand)
	var brand_gap := Control.new()
	brand_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	masthead_row.add_child(brand_gap)
	var stamp := Label.new()
	stamp.text = "FIELD ARMAMENT ARCHIVE"
	stamp.add_theme_font_size_override("font_size", 11)
	stamp.add_theme_color_override("font_color", MUTED)
	masthead_row.add_child(stamp)

	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 6)
	root.add_child(nav)
	_add_nav_button(nav, "枪械目录", PAGE_CATALOG)
	_add_nav_button(nav, "Future 系列", PAGE_FUTURE_SERIES)
	_add_nav_button(nav, "安全与补给", PAGE_SAFETY)
	var nav_gap := Control.new()
	nav_gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(nav_gap)
	var readonly := Label.new()
	readonly.text = "只读资料 · 不提供在线购买"
	readonly.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	readonly.add_theme_color_override("font_color", WARNING)
	readonly.add_theme_font_size_override("font_size", 13)
	nav.add_child(readonly)

	var definition: Dictionary = PAGE_DEFINITIONS[page_id]
	var eyebrow := Label.new()
	eyebrow.text = str(definition.get("eyebrow", "REFERENCE"))
	eyebrow.add_theme_font_size_override("font_size", 12)
	eyebrow.add_theme_color_override("font_color", RED)
	root.add_child(eyebrow)

	var heading := Label.new()
	heading.text = str(definition.get("title", "枪械目录"))
	heading.add_theme_font_size_override("font_size", 30)
	heading.add_theme_color_override("font_color", INK)
	root.add_child(heading)

	var intro := Label.new()
	intro.text = str(definition.get("intro", ""))
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", MUTED)
	root.add_child(intro)

	var rule := HSeparator.new()
	root.add_child(rule)
	if page_id == PAGE_FUTURE_SERIES:
		root.add_child(_make_future_case_note())

	var products_grid := GridContainer.new()
	products_grid.columns = 2
	products_grid.add_theme_constant_override("h_separation", 12)
	products_grid.add_theme_constant_override("v_separation", 12)
	root.add_child(products_grid)
	for product_id_value: Variant in definition.get("products", []):
		var product_id := str(product_id_value)
		products_grid.add_child(_make_product_card(product_id))

	var footer := Label.new()
	footer.text = "RANGE LEDGER / 价格仅用于资料展示。实际交易请在实体商店完成。"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_color_override("font_color", MUTED)
	footer.add_theme_font_size_override("font_size", 12)
	root.add_child(footer)
	var bottom_padding := Control.new()
	bottom_padding.custom_minimum_size.y = 24.0
	root.add_child(bottom_padding)

	# Size the page from the largest grid plus a real bottom gutter. Without this
	# explicit room the nested VBox can be clipped by the browser viewport before
	# the final card and footer become reachable.
	match page_id:
		PAGE_CATALOG:
			custom_minimum_size.y = 1320.0
		PAGE_FUTURE_SERIES:
			custom_minimum_size.y = 900.0
		_:
			custom_minimum_size.y = 820.0


func _add_nav_button(parent: HBoxContainer, label: String, target_page_id: String) -> void:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(112.0, 34.0)
	button.disabled = target_page_id == page_id
	button.add_theme_color_override("font_color", RED)
	button.add_theme_color_override("font_disabled_color", Color("#777777"))
	button.pressed.connect(_navigate_to_page.bind(target_page_id))
	parent.add_child(button)


func _navigate_to_page(target_page_id: String) -> void:
	if not is_instance_valid(desktop):
		return
	var path = {
		PAGE_CATALOG: "/catalog",
		PAGE_FUTURE_SERIES: "/future-series",
		PAGE_SAFETY: "/safety",
	}.get(target_page_id, "/catalog")
	desktop.call("navigate_browser_from_page", browser_app_id, "www.rangeledger.com%s" % path)


func _make_product_card(product_id: String) -> Control:
	var data: Dictionary = PRODUCTS.get(product_id, {}) as Dictionary
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(340.0, 226.0)
	card.add_theme_stylebox_override("panel", _style_box(PANEL, LINE, 1, 3))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(126.0, 126.0)
	image_frame.add_theme_stylebox_override("panel", _style_box(IMAGE_PANEL, LINE, 1, 2))
	row.add_child(image_frame)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(124.0, 124.0)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = load(IMAGE_ROOT + product_id + ".png") as Texture2D
	image.tooltip_text = str(data.get("name", product_id))
	image_frame.add_child(image)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	row.add_child(details)
	var name_label := Label.new()
	name_label.text = str(data.get("name", product_id))
	name_label.add_theme_font_size_override("font_size", 19)
	name_label.add_theme_color_override("font_color", INK)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(name_label)
	var category := Label.new()
	category.text = str(data.get("category", "装备"))
	category.add_theme_font_size_override("font_size", 12)
	category.add_theme_color_override("font_color", RED)
	details.add_child(category)

	if bool(data.get("show_price", true)):
		var price := _get_price(product_id)
		var sell_price := _get_sell_price(product_id)
		var price_label := Label.new()
		price_label.text = "售价参考：$%d\n回收参考：$%d" % [price, sell_price]
		price_label.add_theme_color_override("font_color", INK)
		price_label.add_theme_font_size_override("font_size", 13)
		details.add_child(price_label)
	else:
		var origin_label := Label.new()
		origin_label.text = "状态：未列入武器商店\n来源：调查中的未知装备"
		origin_label.add_theme_color_override("font_color", WARNING)
		origin_label.add_theme_font_size_override("font_size", 12)
		details.add_child(origin_label)

	if data.has("power"):
		var performance_label := Label.new()
		performance_label.text = "威力参考：%s\n适用范围：%s" % [str(data.get("power", "—")), str(data.get("range", "—"))]
		performance_label.add_theme_color_override("font_color", INK)
		performance_label.add_theme_font_size_override("font_size", 13)
		details.add_child(performance_label)
	else:
		var range_label := Label.new()
		range_label.text = "适用范围：%s" % str(data.get("range", "—"))
		range_label.add_theme_color_override("font_color", MUTED)
		range_label.add_theme_font_size_override("font_size", 12)
		details.add_child(range_label)

	var summary := Label.new()
	summary.text = str(data.get("summary", ""))
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary.add_theme_color_override("font_color", MUTED)
	summary.add_theme_font_size_override("font_size", 12)
	details.add_child(summary)
	return card


func _make_future_case_note() -> Control:
	var note := PanelContainer.new()
	note.custom_minimum_size.y = 108.0
	note.add_theme_stylebox_override("panel", _style_box(Color("#1b1214"), RED_DARK, 1, 2))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	note.add_child(margin)
	var text := Label.new()
	text.text = "调查摘要 04\n近期多次发现携带 Future 系列武器的武装士兵与工程师，他们似乎是突然出现在本地战区的敌对人员。政府仍在调查这些人来自哪里、为何出现以及是否有统一目的。目前只能确认：其装备威力略高于现代型号，无法通过现有供应渠道采购。"
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color", Color("#e5caca"))
	text.add_theme_font_size_override("font_size", 13)
	margin.add_child(text)
	return note


func _get_price(product_id: String) -> int:
	var product := GlobalVar.get_shop_product(product_id)
	return int(product.get("buy_price", 0))


func _get_sell_price(product_id: String) -> int:
	var product := GlobalVar.get_shop_product(product_id)
	return int(product.get("sell_price", 0))


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
