extends PanelContainer
class_name SChatPage

const FEED_BATCH_SIZE := 6
const PAGE_WIDTH := 720.0
const PAGE_MARGIN := 18
const CARD_INNER_MARGIN := 14.0
const TEXT_COLOR := Color("#1f2933")
const MUTED_COLOR := Color("#6b7280")
const ACCENT_COLOR := Color("#3f6f9f")
const ACCENT_SOFT := Color("#eaf2fa")
const BORDER_COLOR := Color("#d9e0e7")

var desktop: Node
var browser_app_id := "browser"
var posts: Array[Dictionary] = []
var feed: VBoxContainer
var load_more_button: Button
var next_post_index := 0
var liked_post_ids: Dictionary = {}
var like_buttons: Dictionary = {}
var like_base_counts: Dictionary = {}


func setup(owner_desktop: Node, owner_app_id: String, saved_likes: Variant = []) -> void:
	desktop = owner_desktop
	browser_app_id = owner_app_id
	liked_post_ids.clear()
	if saved_likes is Array:
		for post_id_value: Variant in saved_likes:
			var post_id := str(post_id_value)
			if not post_id.is_empty():
				liked_post_ids[post_id] = true
	posts = SChatCatalog.get_posts()
	next_post_index = 0
	_build_page()


func _build_page() -> void:
	like_buttons.clear()
	like_base_counts.clear()
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(PAGE_WIDTH, 0.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	add_theme_stylebox_override("panel", _style_box(Color.WHITE, BORDER_COLOR, 1, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_top", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_right", PAGE_MARGIN)
	margin.add_theme_constant_override("margin_bottom", PAGE_MARGIN)
	margin.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(root)

	feed = VBoxContainer.new()
	feed.name = "PostFeed"
	feed.add_theme_constant_override("separation", 12)
	feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feed.mouse_filter = Control.MOUSE_FILTER_PASS
	root.add_child(feed)

	load_more_button = Button.new()
	load_more_button.custom_minimum_size.y = 38.0
	load_more_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_more_button.focus_mode = Control.FOCUS_NONE
	load_more_button.text = "加载更多动态"
	load_more_button.add_theme_color_override("font_color", ACCENT_COLOR)
	load_more_button.add_theme_stylebox_override("normal", _style_box(Color("#f7fafc"), BORDER_COLOR, 1, 5))
	load_more_button.add_theme_stylebox_override("hover", _style_box(ACCENT_SOFT, ACCENT_COLOR, 1, 5))
	load_more_button.pressed.connect(_append_next_batch)
	root.add_child(load_more_button)
	_append_next_batch()


func _append_next_batch() -> void:
	if not is_instance_valid(feed):
		return
	var end_index := mini(next_post_index + FEED_BATCH_SIZE, posts.size())
	for index in range(next_post_index, end_index):
		feed.add_child(_build_post_card(posts[index]))
	next_post_index = end_index
	if load_more_button != null:
		load_more_button.visible = next_post_index < posts.size()
		if next_post_index >= posts.size():
			load_more_button.text = "已经显示全部动态"


func _build_post_card(post: Dictionary) -> PanelContainer:
	var post_id := str(post.get("post_id", ""))
	var card := PanelContainer.new()
	card.name = "Post_" + post_id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	card.add_theme_stylebox_override("panel", _style_box(Color.WHITE, BORDER_COLOR, 1, 7))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_top", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_right", CARD_INNER_MARGIN)
	margin.add_theme_constant_override("margin_bottom", CARD_INNER_MARGIN)
	card.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var profile := SChatCatalog.get_profile(str(post.get("npc_id", "")))
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 46.0
	header.add_theme_constant_override("separation", 10)
	column.add_child(header)
	var avatar := TextureRect.new()
	avatar.custom_minimum_size = Vector2(46.0, 46.0)
	avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	avatar.texture = load(str(profile.get("avatar", SChatCatalog.DEFAULT_AVATAR_PATH))) as Texture2D
	avatar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(avatar)
	var identity := VBoxContainer.new()
	identity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation", 1)
	header.add_child(identity)
	var name_label := Label.new()
	name_label.text = str(profile.get("display_name", "Community member"))
	name_label.add_theme_font_size_override("font_size", 17)
	name_label.add_theme_color_override("font_color", TEXT_COLOR)
	identity.add_child(name_label)
	var handle_label := Label.new()
	handle_label.text = "%s · s.chat" % str(profile.get("handle", "@unknown"))
	handle_label.add_theme_font_size_override("font_size", 12)
	handle_label.add_theme_color_override("font_color", MUTED_COLOR)
	identity.add_child(handle_label)
	var theme_label := Label.new()
	theme_label.text = _theme_title(str(post.get("theme_id", "")))
	theme_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	theme_label.add_theme_font_size_override("font_size", 12)
	theme_label.add_theme_color_override("font_color", ACCENT_COLOR)
	header.add_child(theme_label)

	var text_label := Label.new()
	text_label.text = str(post.get("text", ""))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.add_theme_font_size_override("font_size", 16)
	text_label.add_theme_color_override("font_color", TEXT_COLOR)
	text_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(text_label)

	var image_paths := SChatCatalog.get_image_paths(post)
	if not image_paths.is_empty():
		column.add_child(_build_post_images(image_paths))

	var links_value: Variant = post.get("links", [])
	if links_value is Array and not (links_value as Array).is_empty():
		var links_box := HBoxContainer.new()
		links_box.add_theme_constant_override("separation", 8)
		column.add_child(links_box)
		var links_title := Label.new()
		links_title.text = "相关链接"
		links_title.add_theme_color_override("font_color", MUTED_COLOR)
		links_box.add_child(links_title)
		for link_value: Variant in links_value:
			var link := str(link_value)
			if link.is_empty():
				continue
			var link_button := LinkButton.new()
			link_button.text = link
			link_button.focus_mode = Control.FOCUS_NONE
			link_button.tooltip_text = "打开网页"
			link_button.add_theme_color_override("font_color", Color("#1769c2"))
			link_button.add_theme_color_override("font_hover_color", Color("#0b57b7"))
			link_button.add_theme_color_override("font_pressed_color", Color("#08488f"))
			link_button.add_theme_color_override("font_focus_color", Color("#1769c2"))
			link_button.pressed.connect(_on_link_pressed.bind(link))
			links_box.add_child(link_button)

	var action_divider := HSeparator.new()
	column.add_child(action_divider)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	column.add_child(actions)
	var engagement := SChatCatalog.get_engagement(post)
	actions.add_child(_make_like_button(post_id, int(engagement.get("likes", 0))))
	actions.add_child(_make_readonly_action(
		"评论", int(engagement.get("comments", 0)), SChatCatalog.COMMENT_ICON_PATH
	))
	actions.add_child(_make_readonly_action(
		"转发", int(engagement.get("reposts", 0)), SChatCatalog.REPOST_ICON_PATH
	))
	return card


func _build_post_images(image_paths: Array[String]) -> Control:
	if image_paths.size() == 1:
		var center := CenterContainer.new()
		center.custom_minimum_size.y = 360.0
		center.add_child(_make_image_frame(image_paths[0], Vector2(360.0, 360.0)))
		return center
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	for image_path: String in image_paths:
		row.add_child(_make_image_frame(image_path, Vector2(326.0, 326.0)))
	return row


func _make_image_frame(image_path: String, frame_size: Vector2) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = frame_size
	frame.add_theme_stylebox_override("panel", _style_box(Color("#f1f4f7"), BORDER_COLOR, 1, 4))
	var image := TextureRect.new()
	image.custom_minimum_size = frame_size
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.texture = load(image_path) as Texture2D
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(image)
	return frame


func _make_like_button(post_id: String, base_likes: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(126.0, 34.0)
	button.flat = true
	button.focus_mode = Control.FOCUS_NONE
	_add_action_icon(button, SChatCatalog.LIKE_ICON_PATH)
	button.tooltip_text = "点赞 / 取消点赞"
	button.add_theme_font_size_override("font_size", 13)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color", Color("#5b6570"))
	button.add_theme_stylebox_override("normal", _style_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4))
	button.add_theme_stylebox_override("hover", _style_box(Color("#fff0f2"), Color("#f1b8c0"), 1, 4))
	button.pressed.connect(_on_like_pressed.bind(post_id, button))
	like_buttons[post_id] = button
	like_base_counts[post_id] = base_likes
	_refresh_like_button(post_id, button)
	return button


func _make_readonly_action(label_text: String, count: int, icon_path: String) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(112.0, 34.0)
	button.flat = true
	button.disabled = true
	button.focus_mode = Control.FOCUS_NONE
	_add_action_icon(button, icon_path)
	button.text = "    %s %s" % [label_text, SChatCatalog.format_count(count)]
	button.tooltip_text = "%s仅供查看" % label_text
	button.add_theme_font_size_override("font_size", 13)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_color_override("font_color_disabled", Color("#6b7280"))
	button.add_theme_stylebox_override("disabled", _style_box(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 4))
	return button


func _add_action_icon(button: Button, icon_path: String) -> void:
	# Button.icon has no scalable max-width property in the current Godot
	# version. A child TextureRect keeps the supplied 128px asset crisp while
	# rendering it at the compact size used by the action row.
	var icon := TextureRect.new()
	icon.position = Vector2(7.0, 7.0)
	icon.size = Vector2(20.0, 20.0)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(icon_path) as Texture2D
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(icon)


func _on_like_pressed(post_id: String, button: Button) -> void:
	if liked_post_ids.has(post_id):
		liked_post_ids.erase(post_id)
	else:
		liked_post_ids[post_id] = true
	_refresh_like_button(post_id, button)
	if is_instance_valid(desktop) and desktop.has_method("set_browser_s_chat_like_state"):
		desktop.call("set_browser_s_chat_like_state", browser_app_id, liked_post_ids.keys())


func restore_liked_post_ids(saved_likes: Variant) -> void:
	liked_post_ids.clear()
	if saved_likes is Array:
		for post_id_value: Variant in saved_likes:
			var post_id := str(post_id_value)
			if not post_id.is_empty():
				liked_post_ids[post_id] = true
	for post_id: Variant in like_buttons.keys():
		var button := like_buttons[post_id] as Button
		_refresh_like_button(str(post_id), button)


func _refresh_like_button(post_id: String, button: Button) -> void:
	if button == null or not is_instance_valid(button):
		return
	var base_likes := int(like_base_counts.get(post_id, 0))
	var is_liked := liked_post_ids.has(post_id)
	button.text = "    赞 %s" % SChatCatalog.format_count(base_likes + (1 if is_liked else 0))
	button.modulate = Color("#cc596a") if is_liked else Color.WHITE


func _on_link_pressed(url: String) -> void:
	if is_instance_valid(desktop) and desktop.has_method("navigate_browser_from_page"):
		desktop.call("navigate_browser_from_page", browser_app_id, url)


func _theme_title(theme_id: String) -> String:
	match theme_id:
		"rain_after", "cafe_indoor", "greenhouse", "lakeside", "makeup_reveal", "workstation_manicure":
			return "生活记录"
		"fake_supply_promo", "fake_discount_news":
			return "社区消息"
		"truck_selfie", "rural_wheat", "mountain_lake", "smalltown_main_street", "smalltown_residential":
			return "沿途记录"
		"home_dinner", "mashed_potato_plate":
			return "家庭厨房"
		"farm_advice":
			return "农场建议"
		"vehicle_service":
			return "载具服务"
		"firearms_guide":
			return "枪械装备"
		"nature_notes":
			return "自然观察"
		"night_shift":
			return "夜班记录"
		"logistics_notice":
			return "物流公告"
		"roadside_rescue":
			return "道路救援"
		"workshop_notes":
			return "工坊笔记"
		"electronics_tech":
			return "电子技术"
		"food_truck_diary":
			return "餐车日记"
		_: return "日常动态"


func _style_box(background: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 5.0
	style.content_margin_bottom = 5.0
	return style
