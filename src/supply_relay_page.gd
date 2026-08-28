extends Control
class_name SupplyRelayPage

const CARD_SIZE := Vector2(110.0, 116.0)
const CARD_GAP := 6.0
const STRIP_SIZE := Vector2(606.0, 150.0)
const ROLL_DURATION := 5.0
const PURPLE := Color("#42136b")
const PURPLE_DARK := Color("#26083f")
const PURPLE_LIGHT := Color("#7e4ba6")
const PAPER := Color("#f5edf8")
const INK := Color("#26142e")
const MUTED := Color("#d5bce2")
const GOLD := Color("#f5d36b")

var desktop: Node
var site_id := SupplyRelayCatalog.SUPPLY_RELAY_SITE
var money_label: Label
var status_label: Label
var draw_button: Button
var result_label: Label
var strip_viewport: Control
var strip_content: HBoxContainer
var rolling := false
var pending_request := false
var last_result: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP


func setup(owner_desktop: Node, next_site_id: String) -> void:
	desktop = owner_desktop
	site_id = next_site_id if SupplyRelayCatalog.is_known_site(next_site_id) \
		else SupplyRelayCatalog.SUPPLY_RELAY_SITE
	_build_page()


func _build_page() -> void:
	for child: Node in get_children():
		child.queue_free()
	custom_minimum_size = Vector2(720.0, 760.0)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var background := ColorRect.new()
	background.color = PURPLE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "GET YOUR SUPPLY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", PAPER)
	root.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Pay a fixed amount and receive one random supply reward."
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 17)
	subtitle.add_theme_color_override("font_color", PAPER)
	root.add_child(subtitle)

	var description := Label.new()
	description.text = "Possible outcomes include weapons, ammunition resources, and military equipment.\nEach roll gives one result from the supply pool."
	description.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_theme_color_override("font_color", PAPER)
	root.add_child(description)

	if SupplyRelayCatalog.is_real_site(site_id):
		var official := Label.new()
		official.text = "OFFICIAL NOTICE: We recently found counterfeit websites impersonating Supply Relay and attempting to scam players. Please check the address carefully and use this official supply page only."
		official.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		official.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		official.add_theme_font_size_override("font_size", 14)
		official.add_theme_color_override("font_color", GOLD)
		root.add_child(official)

	var strip_center := CenterContainer.new()
	strip_center.custom_minimum_size.y = 164.0
	root.add_child(strip_center)
	strip_viewport = Control.new()
	strip_viewport.name = "SupplyRollViewport"
	strip_viewport.custom_minimum_size = STRIP_SIZE
	strip_viewport.clip_contents = true
	strip_viewport.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_center.add_child(strip_viewport)
	var strip_frame := Panel.new()
	strip_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	strip_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_frame.add_theme_stylebox_override("panel", _style_box(Color("#32104f"), PAPER, 1, 1))
	strip_viewport.add_child(strip_frame)
	strip_content = HBoxContainer.new()
	strip_content.position = Vector2(8.0, 17.0)
	strip_content.add_theme_constant_override("separation", int(CARD_GAP))
	strip_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_viewport.add_child(strip_content)
	var marker := ColorRect.new()
	marker.position = Vector2((STRIP_SIZE.x - 2.0) * 0.5, 8.0)
	marker.size = Vector2(2.0, 134.0)
	marker.color = GOLD
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_viewport.add_child(marker)
	var marker_top := Label.new()
	marker_top.text = "▼"
	marker_top.position = Vector2(STRIP_SIZE.x * 0.5 - 12.0, -2.0)
	marker_top.size = Vector2(24.0, 22.0)
	marker_top.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker_top.add_theme_color_override("font_color", GOLD)
	marker_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_viewport.add_child(marker_top)
	var marker_bottom := Label.new()
	marker_bottom.text = "▲"
	marker_bottom.position = Vector2(STRIP_SIZE.x * 0.5 - 12.0, 132.0)
	marker_bottom.size = Vector2(24.0, 22.0)
	marker_bottom.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker_bottom.add_theme_color_override("font_color", GOLD)
	marker_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip_viewport.add_child(marker_bottom)
	_build_idle_strip()

	result_label = Label.new()
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_label.add_theme_font_size_override("font_size", 18)
	result_label.add_theme_color_override("font_color", Color("#ff5b5b"))
	result_label.visible = false
	root.add_child(result_label)

	var how := Label.new()
	how.text = "HOW IT WORKS\n• Pay $500 per roll.\n• One random supply result is selected.\n• Official rewards are sent to your team's inventory."
	if not SupplyRelayCatalog.is_real_site(site_id):
		how.text = "HOW IT WORKS\n• Pay $500 per roll.\n• One random supply result is selected.\n• Confirmation is generated after the roll."
	how.add_theme_color_override("font_color", PAPER)
	how.add_theme_font_size_override("font_size", 16)
	how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(how)

	var money_row := HBoxContainer.new()
	money_row.alignment = BoxContainer.ALIGNMENT_CENTER
	money_row.add_theme_constant_override("separation", 20)
	root.add_child(money_row)
	money_label = Label.new()
	money_label.add_theme_color_override("font_color", GOLD)
	money_label.add_theme_font_size_override("font_size", 18)
	money_row.add_child(money_label)

	draw_button = Button.new()
	draw_button.text = "PUT $500"
	draw_button.custom_minimum_size = Vector2(260.0, 58.0)
	draw_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	draw_button.add_theme_font_size_override("font_size", 28)
	draw_button.add_theme_color_override("font_color", INK)
	draw_button.add_theme_stylebox_override("normal", _style_box(PAPER, PURPLE_DARK, 2, 2))
	draw_button.add_theme_stylebox_override("hover", _style_box(Color("#ffffff"), PURPLE_LIGHT, 2, 2))
	draw_button.pressed.connect(_on_draw_pressed)
	root.add_child(draw_button)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", MUTED)
	root.add_child(status_label)
	_refresh_money()
	result_label.text = ""
	status_label.text = "READY"


func _build_idle_strip() -> void:
	if not is_instance_valid(strip_content):
		return
	for child: Node in strip_content.get_children():
		strip_content.remove_child(child)
		child.queue_free()
	var pool: Array = SupplyRelayCatalog.get_reward_pool()
	if pool.is_empty():
		return
	for index in range(5):
		var entry: Dictionary = pool[index % pool.size()] as Dictionary
		strip_content.add_child(_make_reward_card(
			str(entry.get("item_id", "")), int(entry.get("amount", 1)), false, abs(index - 2)
		))
	strip_content.position.x = (STRIP_SIZE.x - 5.0 * CARD_SIZE.x - 4.0 * CARD_GAP) * 0.5


func _make_reward_card(item_id: String, amount: int, focused: bool, focus_distance := 0) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = CARD_SIZE
	card.size = CARD_SIZE
	card.set_meta("supply_item_id", item_id)
	card.set_meta("supply_amount", amount)
	_set_card_focus(card, focused, focus_distance)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(column)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(94.0, 76.0)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.texture = ItemIconCatalog.get_icon_for_id(item_id)
	if icon.texture == null:
		var fallback := Label.new()
		fallback.text = _fallback_code(item_id)
		fallback.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		fallback.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fallback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		fallback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		fallback.add_theme_font_size_override("font_size", 16)
		fallback.add_theme_color_override("font_color", PURPLE_DARK)
		fallback.mouse_filter = Control.MOUSE_FILTER_IGNORE
		icon.add_child(fallback)
	column.add_child(icon)
	var name_label := Label.new()
	name_label.text = SupplyRelayCatalog.get_display_name(item_id)
	name_label.custom_minimum_size.x = 102.0
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.clip_text = true
	name_label.add_theme_font_size_override("font_size", 12)
	name_label.add_theme_color_override("font_color", INK)
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(name_label)
	if amount != 1:
		var amount_label := Label.new()
		amount_label.text = "× %d" % amount
		amount_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		amount_label.add_theme_font_size_override("font_size", 11)
		amount_label.add_theme_color_override("font_color", INK)
		amount_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(amount_label)
	return card


func _set_card_focus(card: PanelContainer, focused: bool, focus_distance: int) -> void:
	if not is_instance_valid(card):
		return
	var alpha := 1.0 if focus_distance == 0 else (0.76 if focus_distance == 1 else 0.42)
	card.modulate = Color(1.0, 1.0, 1.0, alpha)
	var border := GOLD if focused else Color("#bcaac4")
	var background := Color("#fff9d9") if focused else Color("#eee9ed")
	card.add_theme_stylebox_override("panel", _style_box(background, border, 2 if focused else 1, 2))


func _apply_winning_card_focus(winning_index: int) -> void:
	if not is_instance_valid(strip_content):
		return
	for index in range(strip_content.get_child_count()):
		var card := strip_content.get_child(index) as PanelContainer
		if card == null:
			continue
		_set_card_focus(card, index == winning_index, abs(index - winning_index))


func _fallback_code(item_id: String) -> String:
	match item_id:
		"ammo_supply_box": return "AMMO\nBOX"
		"suppressed_pistol": return "SILENT\nPISTOL"
		"chest_armor_military_vest": return "MIL\nVEST"
		"backpack_military": return "MIL\nPACK"
		"grenade": return "GRENADE"
		"shotgun": return "SHOTGUN"
		"m4": return "M4"
		"ar15": return "AR15"
		_: return item_id.to_upper()


func _on_draw_pressed() -> void:
	if pending_request or rolling or not is_instance_valid(desktop):
		return
	pending_request = true
	draw_button.disabled = true
	result_label.visible = false
	result_label.text = ""
	status_label.text = "CONTACTING SUPPLY RELAY..."
	desktop.call("request_supply_draw", site_id)


func apply_supply_result(result: Dictionary) -> void:
	if not pending_request or str(result.get("site_id", "")) != site_id:
		return
	_refresh_money()
	if not bool(result.get("ok", false)):
		pending_request = false
		draw_button.disabled = false
		status_label.text = "REQUEST FAILED: %s" % str(result.get("reason_text", result.get("reason", "UNKNOWN ERROR")))
		return
	last_result = result.duplicate(true)
	status_label.text = "ROLLING..."
	_start_roll(last_result)


func _start_roll(result: Dictionary) -> void:
	if not is_instance_valid(strip_content) or not is_instance_valid(strip_viewport):
		_finish_roll(result)
		return
	rolling = true
	for child: Node in strip_content.get_children():
		strip_content.remove_child(child)
		child.queue_free()
	var pool: Array = SupplyRelayCatalog.get_reward_pool()
	var winning_index := 17
	for index in range(25):
		var entry: Dictionary = pool[randi_range(0, pool.size() - 1)] as Dictionary
		if index == winning_index:
			entry = {
				"item_id": str(result.get("reward_item_id", "")),
				"amount": int(result.get("reward_amount", 1)),
			}
		strip_content.add_child(_make_reward_card(
			str(entry.get("item_id", "")), int(entry.get("amount", 1)), false
		))
	strip_content.position.x = 8.0
	call_deferred("_animate_roll", result, winning_index)


func _animate_roll(result: Dictionary, winning_index: int) -> void:
	if not is_instance_valid(strip_content) or not is_instance_valid(strip_viewport):
		_finish_roll(result)
		return
	var cell_step := CARD_SIZE.x + CARD_GAP
	var target_x := strip_viewport.size.x * 0.5 - (8.0 + float(winning_index) * cell_step + CARD_SIZE.x * 0.5)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUINT)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(strip_content, "position:x", target_x, ROLL_DURATION)
	tween.tween_callback(Callable(self, "_finish_roll").bind(result, winning_index))


func _finish_roll(result: Dictionary, winning_index: int = -1) -> void:
	# The center card is not highlighted while the strip is moving. Apply the
	# yellow focus only after the easing tween has fully completed.
	_apply_winning_card_focus(winning_index)
	rolling = false
	pending_request = false
	draw_button.disabled = false
	_refresh_money()
	var reward_text := SupplyRelayCatalog.get_reward_text(
		str(result.get("reward_item_id", "")), int(result.get("reward_amount", 1))
	)
	result_label.text = "「%s」已经送到了您队伍的库存中。" % reward_text
	result_label.visible = true
	if bool(result.get("reward_delivered", false)):
		status_label.text = "SENT TO YOUR TEAM'S INVENTORY."
	else:
		status_label.text = "ORDER CONFIRMATION GENERATED."


func _refresh_money() -> void:
	if not is_instance_valid(money_label):
		return
	var team := ""
	if is_instance_valid(desktop) and desktop.get("player") != null:
		var owner := desktop.get("player") as Node
		if owner != null:
			team = str(owner.get("team"))
	money_label.text = "TEAM FUNDS: $%d" % roundi(GlobalVar.check_team_item_amount(team, "money")) \
		if not team.is_empty() else "TEAM FUNDS: --"


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
