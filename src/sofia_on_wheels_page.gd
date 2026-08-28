extends Control
class_name SofiaOnWheelsPage

const HOME_PAGE := "home"
const MENU_PAGE := "menu"
const ICON_ROOT := "res://assets/icons/food_car/"
const PAGE_WIDTH := 720.0
const PAGE_MARGIN := 24
const CARD_GAP := 12

const BACKGROUND := Color("#fffaf2")
const HEADER := Color("#b8472d")
const HEADER_DARK := Color("#793025")
const PANEL := Color("#ffffff")
const PANEL_SOFT := Color("#fff3e6")
const INK := Color("#302820")
const MUTED := Color("#776e64")
const ACCENT := Color("#b8472d")
const GOLD := Color("#d69332")
const LINE := Color("#e4d6c8")

const PRODUCT_ORDER := [
	"burger", "fries", "taco", "soda", "ice_cream", "egg_tart", "fried_chicken_nuggets"
]

var desktop: Node
var browser_app_id := "browser"
var page_id := HOME_PAGE


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, requested_page_id: String, owner_browser_app_id := "browser") -> void:
	desktop = owner_desktop
	browser_app_id = owner_browser_app_id
	page_id = requested_page_id if requested_page_id in [HOME_PAGE, MENU_PAGE] else HOME_PAGE
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	# Leave enough vertical room for the final menu card and footer to scroll
	# completely into view. The page is intentionally taller than the browser
	# window; the parent ScrollContainer provides the viewport.
	custom_minimum_size = Vector2(PAGE_WIDTH, 1060.0 if page_id == HOME_PAGE else 1200.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", PAGE_MARGIN)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	_add_header(root)
	_add_navigation(root)
	if page_id == MENU_PAGE:
		_build_menu(root)
	else:
		_build_home(root)
	_add_footer(root)


func _add_header(root: VBoxContainer) -> void:
	var header := PanelContainer.new()
	header.custom_minimum_size.y = 104.0
	header.add_theme_stylebox_override("panel", _style_box(HEADER, HEADER_DARK, 1, 4))
	root.add_child(header)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	header.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	margin.add_child(row)

	var icon_frame := PanelContainer.new()
	icon_frame.custom_minimum_size = Vector2(78, 78)
	icon_frame.add_theme_stylebox_override("panel", _style_box(Color("#f8d6a7"), Color("#f8d6a7"), 0, 3))
	row.add_child(icon_frame)
	var truck_icon := TextureRect.new()
	truck_icon.custom_minimum_size = Vector2(76, 76)
	truck_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	truck_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	truck_icon.texture = _load_icon("food_truck")
	truck_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon_frame.add_child(truck_icon)

	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.alignment = BoxContainer.ALIGNMENT_CENTER
	identity.add_theme_constant_override("separation", 2)
	row.add_child(identity)
	var brand := Label.new()
	brand.text = "SOFIA ON WHEELS"
	brand.add_theme_font_size_override("font_size", 28)
	brand.add_theme_color_override("font_color", Color.WHITE)
	identity.add_child(brand)
	var tagline := Label.new()
	tagline.text = "MOBILE KITCHEN · FRESH FOOD ON THE ROAD"
	tagline.add_theme_font_size_override("font_size", 11)
	tagline.add_theme_color_override("font_color", Color("#ffe7c8"))
	identity.add_child(tagline)

	var today := Label.new()
	today.text = "TODAY\nNO EVENT"
	today.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	today.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	today.add_theme_font_size_override("font_size", 12)
	today.add_theme_color_override("font_color", Color("#ffe7c8"))
	row.add_child(today)


func _add_navigation(root: VBoxContainer) -> void:
	var nav := HBoxContainer.new()
	nav.add_theme_constant_override("separation", 8)
	root.add_child(nav)
	_add_nav_button(nav, "首页", HOME_PAGE)
	_add_nav_button(nav, "菜单 / MENU", MENU_PAGE)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nav.add_child(spacer)
	var status := Label.new()
	status.text = "SOFIA'S MOBILE KITCHEN"
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 11)
	status.add_theme_color_override("font_color", MUTED)
	nav.add_child(status)


func _add_nav_button(parent: HBoxContainer, label_text: String, target_page: String) -> void:
	var button := Button.new()
	button.text = label_text
	button.disabled = target_page == page_id
	button.custom_minimum_size = Vector2(112, 34)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", ACCENT)
	button.add_theme_color_override("font_disabled_color", MUTED)
	button.add_theme_stylebox_override("normal", _style_box(PANEL, LINE, 1, 3))
	button.add_theme_stylebox_override("hover", _style_box(PANEL_SOFT, ACCENT, 1, 3))
	button.add_theme_stylebox_override("disabled", _style_box(PANEL_SOFT, LINE, 1, 3))
	button.pressed.connect(_navigate_to_page.bind(target_page))
	parent.add_child(button)


func _build_home(root: VBoxContainer) -> void:
	var welcome := Label.new()
	welcome.text = "现做快餐，跟着车轮去见更多客人。"
	welcome.add_theme_font_size_override("font_size", 24)
	welcome.add_theme_color_override("font_color", INK)
	root.add_child(welcome)

	var intro := Label.new()
	intro.text = "Sofia on Wheels 每天带着热腾腾的街头餐点在各处停留。当前菜单和现场售价如下，今日暂无特别活动。"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 15)
	intro.add_theme_color_override("font_color", MUTED)
	root.add_child(intro)

	root.add_child(_make_event_panel())

	var menu_heading := HBoxContainer.new()
	root.add_child(menu_heading)
	var title := Label.new()
	title.text = "今日菜单"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", INK)
	menu_heading.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_heading.add_child(spacer)
	var view_menu := Button.new()
	view_menu.text = "查看完整菜单 →"
	view_menu.focus_mode = Control.FOCUS_NONE
	view_menu.add_theme_color_override("font_color", ACCENT)
	view_menu.add_theme_stylebox_override("normal", _style_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 2))
	view_menu.pressed.connect(_navigate_to_page.bind(MENU_PAGE))
	menu_heading.add_child(view_menu)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)
	root.add_child(grid)
	var products := _get_menu_products()
	for product: Dictionary in products:
		grid.add_child(_make_product_card(product, Vector2(330, 126)))


func _build_menu(root: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "今日菜单 / MENU"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", INK)
	root.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "当前餐车现场售价 · 每份计价"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", MUTED)
	root.add_child(subtitle)
	root.add_child(_make_event_panel())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", CARD_GAP)
	grid.add_theme_constant_override("v_separation", CARD_GAP)
	root.add_child(grid)
	var products := _get_menu_products()
	for product: Dictionary in products:
		grid.add_child(_make_product_card(product, Vector2(330, 154)))
	if products.is_empty():
		var empty := Label.new()
		empty.text = "当前没有可显示的菜单项目。"
		empty.add_theme_color_override("font_color", MUTED)
		grid.add_child(empty)


func _make_event_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.y = 72.0
	panel.add_theme_stylebox_override("panel", _style_box(PANEL_SOFT, Color("#edcfb4"), 1, 4))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)
	var heading := Label.new()
	heading.text = "当日活动"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", ACCENT)
	row.add_child(heading)
	var detail := Label.new()
	detail.text = "暂无活动"
	detail.add_theme_color_override("font_color", MUTED)
	detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(detail)
	return panel


func _make_product_card(product: Dictionary, card_size: Vector2) -> Control:
	var item_id := str(product.get("id", ""))
	var card := PanelContainer.new()
	card.custom_minimum_size = card_size
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style_box(PANEL, LINE, 1, 4))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	margin.add_child(row)

	var image_frame := PanelContainer.new()
	image_frame.custom_minimum_size = Vector2(96, 96)
	image_frame.add_theme_stylebox_override("panel", _style_box(Color("#f7eee6"), LINE, 1, 3))
	row.add_child(image_frame)
	var image := TextureRect.new()
	image.custom_minimum_size = Vector2(94, 94)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = _load_icon(item_id)
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	image_frame.add_child(image)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 3)
	row.add_child(details)
	var name_label := Label.new()
	name_label.text = str(product.get("name", item_id))
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", INK)
	details.add_child(name_label)
	var price_label := Label.new()
	price_label.text = "售价  $%d / 份" % int(product.get("buy_price", 0))
	price_label.add_theme_font_size_override("font_size", 16)
	price_label.add_theme_color_override("font_color", ACCENT)
	details.add_child(price_label)
	var description := Label.new()
	var dish := DishCatalog.get_definition(item_id)
	description.text = str(dish.get("description", "现做餐点。"))
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_font_size_override("font_size", 12)
	description.add_theme_color_override("font_color", MUTED)
	details.add_child(description)
	return card


func _add_footer(root: VBoxContainer) -> void:
	var separator := HSeparator.new()
	root.add_child(separator)
	var footer := Label.new()
	footer.text = "SOFIA ON WHEELS · 价格以当前餐车菜单为准"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 11)
	footer.add_theme_color_override("font_color", MUTED)
	root.add_child(footer)
	var bottom_padding := Control.new()
	bottom_padding.custom_minimum_size.y = 24.0
	root.add_child(bottom_padding)


func _get_menu_products() -> Array[Dictionary]:
	var by_id: Dictionary = {}
	for product: Dictionary in GlobalVar.get_shop_products("food_car"):
		by_id[str(product.get("id", ""))] = product
	var result: Array[Dictionary] = []
	for item_id_value: Variant in PRODUCT_ORDER:
		var item_id := str(item_id_value)
		if by_id.has(item_id):
			result.append((by_id[item_id] as Dictionary).duplicate(true))
	return result


func _load_icon(item_id: String) -> Texture2D:
	var path := ICON_ROOT + item_id + ".png"
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	return ItemIconCatalog.get_dish_icon(item_id)


func _navigate_to_page(target_page_id: String) -> void:
	if not is_instance_valid(desktop):
		return
	var path := "/menu" if target_page_id == MENU_PAGE else "/"
	desktop.call("navigate_browser_from_page", browser_app_id, "www.sofiaonwheels.com%s" % path)


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
