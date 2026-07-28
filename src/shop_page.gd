extends PanelContainer

signal closed

const COLOR_PANEL := Color("#18324A")
const COLOR_PANEL_DARK := Color("#102436")
const COLOR_ACCENT := Color("#63D9A6")
const COLOR_GOLD := Color("#FFD166")
const COLOR_TEXT := Color("#F4F7FA")
const COLOR_MUTED := Color("#AFC2D0")
const COLOR_BUY := Color("#2E9E72")
const COLOR_SELL := Color("#D8843B")

var current_shop: Shop
var current_team := ""
var current_player: GamePlayer

var title_label: Label
var subtitle_label: Label
var money_label: Label
var status_label: Label
var buy_list: VBoxContainer
var sell_list: VBoxContainer
var tab_container: TabContainer
var market_session_acquired := false
var _market_session_refresh_left := 0.0


func _ready() -> void:
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_interface()
	visible = false
	GlobalVar.storage_changed.connect(_on_storage_changed)


func show_shop(shop: Shop, team: String, player: GamePlayer = null) -> void:
	if not is_instance_valid(shop):
		return
	current_shop = shop
	current_team = team
	current_player = player
	market_session_acquired = shop.shop_category != "livestock_market"
	_market_session_refresh_left = 0.0
	visible = true
	_refresh_interface()
	if shop.shop_category == "livestock_market":
		_submit_market_session_action("open")


func close_shop() -> void:
	if not visible:
		return
	if market_session_acquired and is_instance_valid(current_shop) \
			and current_shop.shop_category == "livestock_market":
		_submit_market_session_action("close")
	visible = false
	market_session_acquired = false
	current_shop = null
	current_team = ""
	current_player = null
	closed.emit()


func _process(delta: float) -> void:
	if not visible or not market_session_acquired or not is_instance_valid(current_shop) \
			or current_shop.shop_category != "livestock_market":
		return
	_market_session_refresh_left -= delta
	if _market_session_refresh_left <= 0.0:
		_market_session_refresh_left = 5.0
		_submit_market_session_action("refresh")


# 保留旧函数名，避免已有代码调用时失效。
func disp_page(shop: Shop = current_shop, team: String = current_team) -> void:
	if is_instance_valid(shop) and not team.is_empty():
		show_shop(shop, team, current_player)


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_pressed() and not event.is_echo() and event.is_action("ui_cancel"):
		close_shop()
		get_viewport().set_input_as_handled()


func _build_interface() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()

	custom_minimum_size = Vector2(760.0, 680.0)
	add_theme_stylebox_override("panel", _style_box(COLOR_PANEL, 18, 3, COLOR_ACCENT))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)

	var header := HBoxContainer.new()
	root.add_child(header)

	title_label = Label.new()
	title_label.text = "田野交易站"
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.add_theme_font_size_override("font_size", 34)
	title_label.add_theme_color_override("font_color", COLOR_TEXT)
	header.add_child(title_label)

	money_label = Label.new()
	money_label.add_theme_font_size_override("font_size", 24)
	money_label.add_theme_color_override("font_color", COLOR_GOLD)
	header.add_child(money_label)

	var close_button := Button.new()
	close_button.text = "  ×  "
	close_button.tooltip_text = "关闭商店（E / Esc）"
	close_button.add_theme_font_size_override("font_size", 22)
	close_button.pressed.connect(close_shop)
	header.add_child(close_button)

	subtitle_label = Label.new()
	subtitle_label.text = "食材按 kg 交易；防御装备按件交易"
	subtitle_label.add_theme_font_size_override("font_size", 17)
	subtitle_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(subtitle_label)
	root.add_child(HSeparator.new())

	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_theme_font_size_override("font_size", 22)
	root.add_child(tab_container)

	var buy_scroll := _create_shop_tab("购买")
	buy_list = buy_scroll.get_child(0) as VBoxContainer
	var sell_scroll := _create_shop_tab("出售")
	sell_list = sell_scroll.get_child(0) as VBoxContainer

	status_label = Label.new()
	status_label.text = "选择数量后进行交易"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 18)
	status_label.add_theme_color_override("font_color", COLOR_MUTED)
	root.add_child(status_label)


func _create_shop_tab(tab_name: String) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.name = tab_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	return scroll


func _refresh_interface() -> void:
	if current_team.is_empty() or not is_instance_valid(current_shop):
		return
	title_label.text = current_shop.get_shop_title()
	if current_shop.uses_personal_dish_inventory():
		subtitle_label.text = "快餐按份购买，直接存入个人背包"
	elif current_shop.uses_personal_weapon_inventory():
		subtitle_label.text = "使用队伍金钱购买，武器直接存入购买者背包"
	elif current_shop.shop_category == "livestock_market":
		subtitle_label.text = "购买需要本队已完工且有空位的对应棚舍；出售只读取个人背包"
	else:
		subtitle_label.text = "食材按 kg 交易；防御装备按件交易"
	money_label.text = "金币  %d" % GlobalVar.check_team_item_amount(current_team, "money")
	_fill_product_list(buy_list, true)
	_fill_product_list(sell_list, false)


func _fill_product_list(container: VBoxContainer, is_buy: bool) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()
	for product: Dictionary in current_shop.get_shop_list():
		var allowed := bool(product["can_buy"] if is_buy else product["can_sell"])
		if allowed:
			container.add_child(_create_product_row(product, is_buy))


func _create_product_row(product: Dictionary, is_buy: bool) -> Control:
	var row_panel := PanelContainer.new()
	row_panel.custom_minimum_size = Vector2(0.0, 62.0)
	row_panel.add_theme_stylebox_override("panel", _style_box(COLOR_PANEL_DARK, 10))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	row_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	var name_label := Label.new()
	name_label.text = str(product["name"])
	name_label.custom_minimum_size.x = 150.0
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 21)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	row.add_child(name_label)

	var owned := _get_owned_amount(product)
	var owned_label := Label.new()
	var unit := str(product.get("unit", "item"))
	owned_label.text = "持有 %s" % _format_quantity(owned, unit)
	owned_label.custom_minimum_size.x = 100.0
	owned_label.add_theme_color_override("font_color", COLOR_MUTED)
	row.add_child(owned_label)

	var price := int(product["buy_price"] if is_buy else product["sell_price"])
	var price_label := Label.new()
	if str(product.get("kind", "")) == "livestock" and not is_buy:
		price_label.text = "%d-%d 金币/件" % [price, price * 3]
	else:
		price_label.text = "%d 金币/%s" % [price, "kg" if unit == "kg" else "件"]
	price_label.custom_minimum_size.x = 105.0
	price_label.add_theme_color_override("font_color", COLOR_GOLD)
	row.add_child(price_label)

	var quantity := SpinBox.new()
	var step := _get_trade_step(product)
	quantity.min_value = step
	quantity.step = step
	quantity.max_value = 1.0 if str(product.get("kind", "")) in ["weapon", "livestock"] \
		else (99.0 if is_buy else maxf(step, owned))
	quantity.value = step
	quantity.suffix = " kg" if unit == "kg" else " 件"
	quantity.custom_minimum_size.x = 110.0
	row.add_child(quantity)

	var trade_button := Button.new()
	trade_button.text = "购买" if is_buy else "出售"
	trade_button.custom_minimum_size = Vector2(92.0, 42.0)
	trade_button.disabled = (not is_buy and owned <= 0) or not market_session_acquired
	trade_button.add_theme_color_override("font_color", COLOR_TEXT)
	trade_button.add_theme_stylebox_override(
		"normal", _style_box(COLOR_BUY if is_buy else COLOR_SELL, 8)
	)
	trade_button.pressed.connect(
		_on_trade_pressed.bind(str(product["id"]), str(product["name"]), is_buy, quantity)
	)
	row.add_child(trade_button)
	return row_panel


func _on_trade_pressed(
	item_id: String,
	display_name: String,
	is_buy: bool,
	quantity: SpinBox
) -> void:
	if not is_instance_valid(current_shop):
		close_shop()
		return
	var amount := quantity.value
	var unit := str(GlobalVar.get_shop_product(item_id).get("unit", "item"))
	var success := false
	var request := {
		"action": "trade",
		"item_id": item_id,
		"amount": amount,
		"is_buy": is_buy,
		"shop_category": current_shop.shop_category,
		"shop_path": str(current_shop.get_path()),
		"shop_position": current_shop.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_shop_transaction(request)
		status_label.text = "交易请求已发送，等待服务器确认：%s × %s" % [display_name, _format_quantity(amount, unit)]
		status_label.add_theme_color_override("font_color", COLOR_MUTED)
		return
	elif GameAuthority.is_local_authority():
		var result: Dictionary = GameAuthority.local_shop_transaction(GameAuthority.LOCAL_PLAYER_ID, request)
		apply_transaction_result(result)
		return
	else:
		success = current_shop.buy(current_team, item_id, amount) if is_buy \
			else current_shop.sell(current_team, item_id, amount)
	if success:
		status_label.text = "%s成功：%s × %s" % ["购买" if is_buy else "出售", display_name, _format_quantity(amount, unit)]
		status_label.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		status_label.text = "交易失败：金币不足、库存不足或该商品不可交易"
		status_label.add_theme_color_override("font_color", Color("#FF8D8D"))
	_refresh_interface()


func _on_storage_changed(team: String, _item_name: String, _new_amount: float) -> void:
	if visible and team == current_team:
		_refresh_interface()


func apply_transaction_result(result: Dictionary) -> void:
	if not visible or not is_instance_valid(current_shop):
		return
	if str(result.get("team", "")) != current_team \
			or str(result.get("shop_category", "general")) != current_shop.shop_category:
		return
	var session_action := str(result.get("session_action", ""))
	if not session_action.is_empty():
		_apply_market_session_result(result, session_action)
		return
	var product := GlobalVar.get_shop_product(str(result.get("item_id", "")))
	var display_name := str(product.get("name", result.get("item_id", "")))
	var amount := float(result.get("amount", 0.0))
	var unit := str(product.get("unit", "item"))
	if bool(result.get("ok", false)):
		status_label.text = "%s成功：%s × %s" % [
			"购买" if bool(result.get("is_buy", true)) else "出售",
			display_name,
			_format_quantity(amount, unit),
		]
		status_label.add_theme_color_override("font_color", COLOR_ACCENT)
	else:
		var message := _transaction_failure_message(str(result.get("reason", "")))
		status_label.text = "交易失败：%s" % message
		status_label.add_theme_color_override("font_color", Color("#FF8D8D"))
		_show_player_notice(message)
	_refresh_interface()


func _submit_market_session_action(action: String) -> void:
	if not is_instance_valid(current_shop):
		return
	var request := {
		"action": action,
		"shop_category": "livestock_market",
		"shop_path": str(current_shop.get_path()),
		"shop_position": current_shop.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_shop_transaction(request)
	elif GameAuthority.is_local_authority():
		var result := GameAuthority.local_shop_transaction(GameAuthority.LOCAL_PLAYER_ID, request)
		apply_transaction_result(result)


func _apply_market_session_result(result: Dictionary, action: String) -> void:
	if action == "close":
		return
	if bool(result.get("ok", false)):
		market_session_acquired = true
		_market_session_refresh_left = 5.0
		if action == "open":
			status_label.text = "牲畜市场已打开"
			status_label.add_theme_color_override("font_color", COLOR_ACCENT)
		_refresh_interface()
		return
	market_session_acquired = false
	var message := _transaction_failure_message(str(result.get("reason", "market_in_use")))
	_show_player_notice(message)
	status_label.text = message
	status_label.add_theme_color_override("font_color", Color("#FF8D8D"))
	close_shop()


func _transaction_failure_message(reason: String) -> String:
	match reason:
		"market_in_use":
			return "另一名队员正在使用牲畜市场"
		"market_out_of_range":
			return "距离牲畜市场过远"
		"market_session_required":
			return "牲畜市场操作权已失效，请重新打开"
		"chicken_chop_not_built":
			return "本队鸡舍尚未建造完成"
		"livestock_chop_not_built":
			return "本队牲畜棚尚未建造完成"
		"chicken_chop_full":
			return "本队鸡舍已满，无法购买活鸡"
		"livestock_chop_full":
			return "本队牲畜棚已满，无法购买猪或牛"
		"insufficient_money":
			return "队伍金钱不足"
		"personal_bag_full":
			return "个人背包格子或载重不足"
		"personal_item_insufficient":
			return "个人背包中没有足够的该活体动物"
		_:
			return "金币不足、背包空间不足或持有数量不足"


func _show_player_notice(message: String) -> void:
	if is_instance_valid(current_player):
		current_player.show_gameplay_notice(message)


func _format_quantity(amount: float, unit: String) -> String:
	return "%.2f kg" % amount if unit == "kg" else "%d 件" % roundi(amount)


func _get_trade_step(product: Dictionary) -> float:
	if str(product.get("unit", "item")) != "kg":
		return 1.0
	return IngredientCatalog.get_pickup_unit_kg(str(product.get("id", "")))


func _get_owned_amount(product: Dictionary) -> float:
	var item_id := str(product.get("id", ""))
	if str(product.get("kind", "")) == "dish" and is_instance_valid(current_player):
		for item: Dictionary in current_player.backpack_items:
			if str(item.get("kind", "")) == "dish" and str(item.get("dish_id", "")) == item_id:
				return float(item.get("servings", 0))
		return 0.0
	if str(product.get("kind", "")) == "weapon" and is_instance_valid(current_player):
		var count := 0
		for item: Dictionary in current_player.backpack_items:
			if str(item.get("kind", "")) in ["tool", "weapon"] \
					and str(item.get("tool_id", "")) == item_id:
				count += 1
		return float(count)
	if str(product.get("kind", "")) == "livestock" and is_instance_valid(current_player):
		var count := 0
		for item: Dictionary in current_player.backpack_items:
			if str(item.get("kind", "")) == "tool" and str(item.get("tool_id", "")) == item_id:
				count += 1
		return float(count)
	return GlobalVar.check_team_item_amount(current_team, item_id)


func _style_box(
	color: Color,
	radius: int,
	border_width: int = 0,
	border_color: Color = Color.TRANSPARENT
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = radius
	style.corner_radius_top_right = radius
	style.corner_radius_bottom_left = radius
	style.corner_radius_bottom_right = radius
	if border_width > 0:
		style.border_width_left = border_width
		style.border_width_top = border_width
		style.border_width_right = border_width
		style.border_width_bottom = border_width
		style.border_color = border_color
	return style
