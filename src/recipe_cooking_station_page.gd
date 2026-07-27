extends Control
class_name RecipeCookingStationPage

const INTERACTION_DISTANCE := 4.0
const UI_REFRESH_INTERVAL := 0.25
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")

@onready var window: PanelContainer = $Window
@onready var recipe_panel_title: Label = $Window/Margin/HBox/RecipePanel/Margin/VBox/Title
@onready var recipe_list: VBoxContainer = $Window/Margin/HBox/RecipePanel/Margin/VBox/RecipeListScroll/RecipeList
@onready var page_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Title
@onready var detail_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/DetailTitle
@onready var status_label: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Status
@onready var input_list: VBoxContainer = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots
@onready var output_caption: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/Caption
@onready var output_name: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemName
@onready var output_weight: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemWeight
@onready var progress: ProgressBar = $Window/Margin/HBox/DetailPanel/Margin/VBox/Progress
@onready var start_button: Button = $Window/Margin/HBox/DetailPanel/Margin/VBox/StartButton

var player: GamePlayer
var station: RecipeCookingStation
var selected_recipe_id := ""
var refresh_accumulator := 0.0
var recipe_buttons: Dictionary = {}
var availability_signature := ""
var output_icon: ItemIcon
var last_ui_activity_msec := 0
var last_lock_heartbeat_msec := 0
var detail_recipe_id := ""


func get_station_kind() -> String:
	return ""


func get_page_title() -> String:
	return "厨具"


func _ready() -> void:
	window.visible = false
	recipe_panel_title.text = "可制作菜谱"
	page_title.text = get_page_title()
	output_caption.text = "成品菜"
	$Window/Margin/HBox/DetailPanel/Margin/VBox/CloseButton.pressed.connect(close)
	start_button.pressed.connect(_on_primary_action_pressed)
	_install_output_icon()
	_clear_ingredient_cards()


func is_open() -> bool:
	return window.visible


func _process(delta: float) -> void:
	if not is_open() or not is_instance_valid(station):
		return
	if player.is_respawning or Time.get_ticks_msec() - last_ui_activity_msec >= KitchenAppliance.USER_LOCK_TIMEOUT_MSEC:
		close()
		return
	if Time.get_ticks_msec() - last_lock_heartbeat_msec >= 10000:
		_send_lock_heartbeat()
	if _is_out_of_interaction_range():
		close()
		return
	refresh_accumulator += delta
	if refresh_accumulator >= UI_REFRESH_INTERVAL:
		refresh_accumulator = 0.0
		_refresh()


func open_for(next_station: RecipeCookingStation, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_station) or not is_instance_valid(next_player):
		return
	station = next_station
	player = next_player
	page_title.text = next_station.get_station_display_name()
	var recipes := RecipeCatalog.get_recipes_for_station(station.get_recipe_station_key())
	if not station.recipe_id.is_empty():
		selected_recipe_id = station.recipe_id
	elif selected_recipe_id.is_empty() and not recipes.is_empty():
		selected_recipe_id = str(recipes[0].get("recipe_id", ""))
	window.visible = true
	_touch_ui_activity()
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.show_companion()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_recipe_buttons()
	_request_action("acquire")
	_refresh(true)


func close() -> void:
	if not is_open():
		return
	_request_action("release")
	window.visible = false
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.hide_companion()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func apply_authoritative_action_result(result: Dictionary) -> void:
	if not is_open() or not is_instance_valid(player) or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	if not bool(result.get("ok", false)):
		status_label.text = _reason_text(str(result.get("reason", "操作失败")))
		return
	if str(result.get("action", "")) == "start":
		_remove_consumed_personal_ingredients(result.get("consumed_personal_ingredients", []))
	status_label.text = ""
	_refresh(true)


func refresh_if_open() -> void:
	if is_open():
		_refresh(true)


func try_take_completed_output() -> bool:
	if not is_open() or not is_instance_valid(station) or not station.complete:
		return false
	_request_action("take")
	return true


func _on_primary_action_pressed() -> void:
	if not is_instance_valid(station):
		return
	_touch_ui_activity()
	_request_action("take" if station.complete else "start")


func _refresh(force_buttons := false) -> void:
	if not is_instance_valid(station) or not is_instance_valid(player):
		return
	if not station.recipe_id.is_empty():
		selected_recipe_id = station.recipe_id
	progress.visible = station.cooking
	progress.value = station.get_progress() * 100.0
	var signature := _get_availability_signature()
	if force_buttons or signature != availability_signature:
		availability_signature = signature
		_update_recipe_buttons()
	_refresh_recipe_detail()
	var recipe := RecipeCatalog.get_recipe(selected_recipe_id)
	var is_idle := station.recipe_id.is_empty() and not station.cooking and not station.complete
	start_button.disabled = station.cooking or (not station.complete and (not is_idle or recipe.is_empty() or not _has_recipe_inputs(recipe)))
	start_button.text = "收取成品" if station.complete else "%s中" % station.get_cooking_verb() if station.cooking else "开始%s" % station.get_cooking_verb()
	if station.complete:
		status_label.text = "成品已完成，请领取。"
	elif station.cooking:
		status_label.text = "%s会在关闭界面后继续。" % station.get_cooking_verb()
	elif status_label.text.ends_with("会在关闭界面后继续。") or status_label.text == "成品已完成，请领取。":
		status_label.text = ""


func _build_recipe_buttons() -> void:
	for child in recipe_list.get_children():
		child.queue_free()
	recipe_buttons.clear()
	for recipe: Dictionary in RecipeCatalog.get_recipes_for_station(station.get_recipe_station_key()):
		var recipe_id := str(recipe.get("recipe_id", ""))
		var result := RecipeCatalog.get_result(recipe_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(285, 66)
		button.text = "%s\n产出 %d 份" % [str(recipe.get("display_name", recipe_id)), int(result.get("quantity", 0))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 17)
		button.pressed.connect(_select_recipe.bind(recipe_id))
		recipe_list.add_child(button)
		recipe_buttons[recipe_id] = button
	availability_signature = ""


func _update_recipe_buttons() -> void:
	for recipe_id_value: Variant in recipe_buttons:
		var recipe_id := str(recipe_id_value)
		var button := recipe_buttons[recipe_id] as Button
		var available := _has_recipe_inputs(RecipeCatalog.get_recipe(recipe_id))
		button.button_pressed = recipe_id == selected_recipe_id
		button.disabled = not station.recipe_id.is_empty() and recipe_id != station.recipe_id
		button.add_theme_color_override("font_color", Color("#FFF0A3") if available else Color("#AEB6BE"))


func _select_recipe(recipe_id: String) -> void:
	if not station.recipe_id.is_empty() and station.recipe_id != recipe_id:
		return
	selected_recipe_id = recipe_id
	_touch_ui_activity()
	_update_recipe_buttons()
	_refresh_recipe_detail()


func _refresh_recipe_detail() -> void:
	if detail_recipe_id == selected_recipe_id:
		return
	detail_recipe_id = selected_recipe_id
	_clear_ingredient_cards()
	var recipe := RecipeCatalog.get_recipe(selected_recipe_id)
	if recipe.is_empty():
		detail_title.text = "请选择左侧菜谱"
		output_icon.set_item_id("")
		output_name.text = ""
		output_weight.text = ""
		return
	detail_title.text = str(recipe.get("display_name", selected_recipe_id))
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(selected_recipe_id):
		_add_ingredient_card(ingredient)
	var result := RecipeCatalog.get_result(selected_recipe_id)
	var dish_id := str(result.get("dish_id", ""))
	output_icon.set_item_id(dish_id)
	output_name.text = str(result.get("display_name", dish_id))
	output_weight.text = "%d 份 / %.2f kg" % [int(result.get("quantity", 0)), float(result.get("total_weight_kg", 0.0))]


func _add_ingredient_card(ingredient: Dictionary) -> void:
	var ingredient_id := str(ingredient.get("ingredient_id", ""))
	var definition := IngredientCatalog.get_definition(ingredient_id)
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(180, 54)
	row.add_theme_constant_override("separation", 8)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemIcon
	icon.custom_minimum_size = Vector2(44, 44)
	icon.set_ingredient(ingredient_id)
	row.add_child(icon)
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 17)
	var chopped_prefix := "切碎的" if bool(ingredient.get("is_chopped", false)) else ""
	label.text = "%s%s  %.2f kg" % [chopped_prefix, str(definition.get("display_name", ingredient_id)), float(ingredient.get("weight_kg", 0.0))]
	row.add_child(label)
	input_list.add_child(row)


func _clear_ingredient_cards() -> void:
	for child in input_list.get_children():
		input_list.remove_child(child)
		child.queue_free()


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	if recipe.is_empty() or not is_instance_valid(player):
		return false
	for ingredient: Dictionary in RecipeCatalog.get_ingredients_per_batch(str(recipe.get("recipe_id", selected_recipe_id))):
		var ingredient_id := str(ingredient.get("ingredient_id", ""))
		var is_chopped := bool(ingredient.get("is_chopped", false))
		var available := _player_ingredient_weight(ingredient_id, is_chopped) + GlobalVar.check_team_item_amount(player.team, ingredient_id)
		if available + 0.001 < float(ingredient.get("weight_kg", 0.0)):
			return false
	return true


func _player_ingredient_weight(ingredient_id: String, is_chopped: bool) -> float:
	var total := 0.0
	for item: Dictionary in player.backpack_items:
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id and _item_is_chopped(item) == is_chopped:
			total += float(item.get("weight_kg", 0.0))
	return total


func _get_availability_signature() -> String:
	var parts: Array[String] = [station.recipe_id, str(station.cooking), str(station.complete), selected_recipe_id]
	for recipe: Dictionary in RecipeCatalog.get_recipes_for_station(station.get_recipe_station_key()):
		var recipe_id := str(recipe.get("recipe_id", ""))
		parts.append("%s:%s" % [recipe_id, str(_has_recipe_inputs(recipe))])
	return "|".join(parts)


func _request_action(action_name: String) -> void:
	if not is_instance_valid(station) or not is_instance_valid(player):
		return
	if action_name != "release":
		_touch_ui_activity()
	var action := {
		"station_kind": get_station_kind(),
		"action": action_name,
		"recipe_id": selected_recipe_id if action_name == "start" else "",
		"station_path": str(station.get_path()),
		"station_position": station.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	player.apply_authoritative_recipe_station_action_result(result)
	apply_authoritative_action_result(result)


func _remove_consumed_personal_ingredients(entries_value: Variant) -> void:
	if not entries_value is Array:
		return
	for entry_value: Variant in entries_value:
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var remaining := float(entry.get("weight_kg", 0.0))
		var ingredient_id := str(entry.get("ingredient_id", ""))
		var is_chopped := bool(entry.get("is_chopped", false))
		for index in range(player.backpack_items.size()):
			var item := player.get_backpack_item(index)
			if str(item.get("kind", "")) != "ingredient" or str(item.get("ingredient_id", "")) != ingredient_id or _item_is_chopped(item) != is_chopped:
				continue
			var amount := minf(remaining, float(item.get("weight_kg", 0.0)))
			player.remove_personal_ingredient_from_slot(index, ingredient_id, amount, is_chopped)
			remaining -= amount
			if remaining <= 0.001:
				break
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.refresh()


func _item_is_chopped(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) or str(item.get("preparation", "")) == "chopped" or str(item.get("model_state", "")) == "chopped"


func _touch_ui_activity() -> void:
	last_ui_activity_msec = Time.get_ticks_msec()


func _send_lock_heartbeat() -> void:
	last_lock_heartbeat_msec = Time.get_ticks_msec()
	if not is_instance_valid(station) or not is_instance_valid(player):
		return
	var action := {"station_kind": get_station_kind(), "action": "acquire", "station_path": str(station.get_path()), "station_position": station.global_position}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
	else:
		apply_authoritative_action_result(GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action))


func _reason_text(reason: String) -> String:
	match reason:
		"station_in_use": return "这台厨具正在被另一名玩家使用。"
		"ingredients_unavailable": return "个人背包与队伍库存的材料不足。"
		"invalid_recipe_for_station": return "所选菜谱不能在这台厨具制作。"
		_: return reason


func _is_out_of_interaction_range() -> bool:
	return not is_instance_valid(player) or not is_instance_valid(station) or Vector2(player.global_position.x, player.global_position.z).distance_to(Vector2(station.global_position.x, station.global_position.z)) > INTERACTION_DISTANCE


func _install_output_icon() -> void:
	var output_box := output_name.get_parent() as VBoxContainer
	output_icon = ITEM_ICON_SCENE.instantiate() as ItemIcon
	output_icon.custom_minimum_size = Vector2(46, 46)
	output_box.add_child(output_icon)
	output_box.move_child(output_icon, output_name.get_index())
