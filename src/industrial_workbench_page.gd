extends Control
class_name IndustrialWorkbenchPage

const INTERACTION_DISTANCE := 4.0
const UI_REFRESH_INTERVAL := 0.25
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")

@onready var window: PanelContainer = $Window
@onready var recipe_list: VBoxContainer = $Window/Margin/HBox/RecipePanel/Margin/VBox/RecipeListScroll/RecipeList
@onready var page_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Title
@onready var detail_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/DetailTitle
@onready var status_label: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Status
@onready var input_list: VBoxContainer = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots
@onready var output_icon_host: Control = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/OutputIcon
@onready var output_name: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemName
@onready var output_quantity: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemQuantity
@onready var progress: ProgressBar = $Window/Margin/HBox/DetailPanel/Margin/VBox/Progress
@onready var start_button: Button = $Window/Margin/HBox/DetailPanel/Margin/VBox/StartButton

var player: GamePlayer
var workbench: IndustrialWorkbench
var selected_recipe_id := ""
var refresh_accumulator := 0.0
var recipe_buttons: Dictionary = {}
var recipe_buttons_workbench_id := ""
var detail_recipe_id := ""
var output_icon: ItemIcon
var last_ui_activity_msec := 0
var last_lock_heartbeat_msec := 0
var last_error_msec := 0


func _ready() -> void:
	UITheme.apply(self)
	window.visible = false
	output_icon = ITEM_ICON_SCENE.instantiate() as ItemIcon
	output_icon.custom_minimum_size = Vector2(64, 64)
	output_icon_host.add_child(output_icon)
	$Window/Margin/HBox/DetailPanel/Margin/VBox/CloseButton.pressed.connect(close)
	start_button.pressed.connect(_on_primary_action_pressed)
	UITheme.apply_button(start_button)
	UITheme.apply_progress(progress, UITheme.TONE_INFO)
	UITheme.set_status(status_label, UITheme.TONE_INFO)


func is_open() -> bool:
	return window.visible


func open_for(next_workbench: IndustrialWorkbench, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_workbench) or not is_instance_valid(next_player):
		return
	workbench = next_workbench
	player = next_player
	page_title.text = next_workbench.get_workbench_display_name()
	var recipes := IndustrialRecipeCatalog.get_recipes_for_workbench(workbench.get_workbench_id())
	if not workbench.recipe_id.is_empty():
		selected_recipe_id = workbench.recipe_id
	elif selected_recipe_id.is_empty() or not _recipe_exists_in_list(selected_recipe_id, recipes):
		selected_recipe_id = str(recipes[0].get("recipe_id", "")) if not recipes.is_empty() else ""
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


func refresh_if_open() -> void:
	if is_open():
		_refresh(true)


func try_take_completed_output() -> bool:
	if not is_open() or not is_instance_valid(workbench) or not workbench.can_take_output():
		return false
	_touch_ui_activity()
	_request_action("take")
	return true


func apply_authoritative_action_result(result: Dictionary) -> void:
	if not is_instance_valid(player) or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	var state_value: Variant = result.get("station_state", {})
	if state_value is Dictionary:
		_apply_state(state_value as Dictionary)
	var slots_value: Variant = result.get("player_slots", null)
	if slots_value is Array:
		player.apply_cargo_backpack_slots(slots_value as Array)
	if not bool(result.get("ok", false)):
		status_label.text = _reason_text(str(result.get("reason", "操作失败")))
		UITheme.set_status(status_label, UITheme.TONE_ERROR)
		last_error_msec = Time.get_ticks_msec()
		return
	if str(result.get("action", "")) == "take":
		status_label.text = "成品已领取。" if str(result.get("delivery", "backpack")) == "backpack" else "成品已放到身边。"
		last_error_msec = Time.get_ticks_msec()
	else:
		status_label.text = ""
		UITheme.set_status(status_label, UITheme.TONE_INFO)
	_refresh(true)


func apply_authoritative_workbench_state(state: Dictionary) -> void:
	_apply_state(state)
	if is_open():
		_refresh(true)


func _apply_state(state: Dictionary) -> void:
	if not is_instance_valid(workbench):
		return
	var state_path := str(state.get("station_path", ""))
	if not state_path.is_empty() and state_path != str(workbench.get_path()):
		return
	workbench.apply_authoritative_workbench_state(state)


func _process(delta: float) -> void:
	if not is_open() or not is_instance_valid(workbench) or not is_instance_valid(player):
		return
	if player.is_respawning or Time.get_ticks_msec() - last_ui_activity_msec >= IndustrialWorkbench.USER_LOCK_TIMEOUT_MSEC:
		close()
		return
	if Time.get_ticks_msec() - last_lock_heartbeat_msec >= 10000:
		_request_action("acquire")
	if _is_out_of_interaction_range():
		close()
		return
	refresh_accumulator += delta
	if refresh_accumulator >= UI_REFRESH_INTERVAL:
		refresh_accumulator = 0.0
		_refresh()


func _on_primary_action_pressed() -> void:
	if not is_instance_valid(workbench):
		return
	_touch_ui_activity()
	if workbench.complete:
		_request_action("take")
	else:
		_request_action("start", selected_recipe_id)


func _request_action(action_name: String, next_recipe_id := "") -> void:
	if not is_instance_valid(player) or not is_instance_valid(workbench):
		return
	if action_name != "release":
		last_lock_heartbeat_msec = Time.get_ticks_msec()
	var action := {
		"station_kind": "industrial_workbench",
		"action": action_name,
		"recipe_id": next_recipe_id,
		"station_path": str(workbench.get_path()),
		"station_position": workbench.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	player.apply_authoritative_industrial_workbench_action_result(result)
	apply_authoritative_action_result(result)


func _refresh(force_buttons := false) -> void:
	if not is_instance_valid(workbench) or not is_instance_valid(player):
		return
	if not workbench.recipe_id.is_empty():
		selected_recipe_id = workbench.recipe_id
	progress.visible = workbench.processing
	progress.value = workbench.get_progress() * 100.0
	if force_buttons and recipe_buttons_workbench_id != workbench.get_workbench_id():
		_build_recipe_buttons()
	_update_recipe_buttons()
	_refresh_recipe_detail()
	var recipe := IndustrialRecipeCatalog.get_recipe(selected_recipe_id)
	var is_idle := workbench.recipe_id.is_empty() and not workbench.processing and not workbench.complete
	var can_start := is_idle and not recipe.is_empty() and _has_recipe_inputs(recipe)
	start_button.disabled = workbench.processing or (not workbench.complete and not can_start)
	start_button.text = "领取成品" if workbench.complete else "加工中" if workbench.processing else "开始制作"
	if workbench.complete and Time.get_ticks_msec() - last_error_msec > 1600:
		status_label.text = "加工完成，请领取成品。"
	elif workbench.processing and Time.get_ticks_msec() - last_error_msec > 1600:
		status_label.text = "加工会在关闭界面后继续。"
	elif is_idle and Time.get_ticks_msec() - last_error_msec > 1600:
		status_label.text = ""


func _build_recipe_buttons() -> void:
	for child in recipe_list.get_children():
		child.queue_free()
	recipe_buttons.clear()
	recipe_buttons_workbench_id = ""
	if not is_instance_valid(workbench):
		return
	recipe_buttons_workbench_id = workbench.get_workbench_id()
	for recipe in IndustrialRecipeCatalog.get_recipes_for_workbench(workbench.get_workbench_id()):
		var recipe_id := str(recipe.get("recipe_id", ""))
		var output := IndustrialRecipeCatalog.make_output_result(recipe_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(310, 62)
		button.text = "%s\n产出 %s" % [str(recipe.get("display_name", recipe_id)), _format_output(output)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.add_theme_font_size_override("font_size", 16)
		UITheme.apply_button(button)
		button.pressed.connect(_select_recipe.bind(recipe_id))
		recipe_list.add_child(button)
		recipe_buttons[recipe_id] = button


func _update_recipe_buttons() -> void:
	for recipe_id_value in recipe_buttons.keys():
		var recipe_id := str(recipe_id_value)
		var button := recipe_buttons[recipe_id] as Button
		button.button_pressed = recipe_id == selected_recipe_id
		button.disabled = not workbench.recipe_id.is_empty() and recipe_id != workbench.recipe_id
		UITheme.set_tone(
			button,
			UITheme.TONE_NEUTRAL if _has_recipe_inputs(IndustrialRecipeCatalog.get_recipe(recipe_id)) else UITheme.TONE_MUTED
		)


func _select_recipe(recipe_id: String) -> void:
	if not is_instance_valid(workbench) or (not workbench.recipe_id.is_empty() and workbench.recipe_id != recipe_id):
		return
	selected_recipe_id = recipe_id
	_touch_ui_activity()
	_refresh(true)


func _refresh_recipe_detail() -> void:
	if detail_recipe_id == selected_recipe_id:
		# Availability text still changes while another player deposits/withdraws
		# materials, so refresh the existing rows instead of rebuilding icons.
		_refresh_input_availability()
		return
	detail_recipe_id = selected_recipe_id
	_clear_input_rows()
	var recipe := IndustrialRecipeCatalog.get_recipe(selected_recipe_id)
	if recipe.is_empty():
		detail_title.text = "请选择左侧项目"
		output_icon.set_item_id("")
		output_name.text = ""
		output_quantity.text = ""
		return
	detail_title.text = "%s  |  %ds" % [str(recipe.get("display_name", selected_recipe_id)), roundi(IndustrialRecipeCatalog.get_duration_seconds(selected_recipe_id))]
	for input in IndustrialRecipeCatalog.get_inputs(selected_recipe_id):
		_add_input_row(input)
	var output := IndustrialRecipeCatalog.make_output_result(selected_recipe_id)
	_set_output_icon(output)
	output_name.text = str(output.get("display_name", output.get("id", "")))
	output_quantity.text = _format_output(output)


func _add_input_row(input: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(235, 50)
	row.add_theme_constant_override("separation", 8)
	var icon := ITEM_ICON_SCENE.instantiate() as ItemIcon
	icon.custom_minimum_size = Vector2(42, 42)
	_set_icon_for_input(icon, input)
	row.add_child(icon)
	var label := Label.new()
	label.name = "Info"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 15)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(label)
	input_list.add_child(row)
	_refresh_input_label(row, input)


func _refresh_input_availability() -> void:
	var index := 0
	for child in input_list.get_children():
		if index >= IndustrialRecipeCatalog.get_inputs(selected_recipe_id).size():
			break
		if child is HBoxContainer:
			_refresh_input_label(child as HBoxContainer, IndustrialRecipeCatalog.get_inputs(selected_recipe_id)[index])
		index += 1


func _refresh_input_label(row: HBoxContainer, input: Dictionary) -> void:
	var label := row.get_node_or_null("Info") as Label
	if label == null:
		return
	var ingredient_id := str(input.get("id", ""))
	var definition := IngredientCatalog.get_definition(ingredient_id)
	var amount := float(input.get("amount", 0.0))
	var unit := str(input.get("unit", "kg"))
	var personal_amount := _player_input_amount(ingredient_id, unit)
	var team_amount := GlobalVar.check_team_item_amount(player.team, ingredient_id)
	var enough := personal_amount + team_amount + 0.001 >= amount
	label.text = "%s\n需 %s  |  身 %s + 队 %s" % [
		str(definition.get("display_name", ingredient_id)),
		IndustrialRecipeCatalog.format_quantity(amount, unit),
		IndustrialRecipeCatalog.format_quantity(personal_amount, unit),
		IndustrialRecipeCatalog.format_quantity(team_amount, unit),
	]
	UITheme.set_tone(label, UITheme.TONE_NEUTRAL if enough else UITheme.TONE_WARNING)


func _set_icon_for_input(icon: ItemIcon, input: Dictionary) -> void:
	icon.set_ingredient(str(input.get("id", "")))


func _set_output_icon(output: Dictionary) -> void:
	var kind := str(output.get("kind", "ingredient"))
	var output_id := str(output.get("id", ""))
	if kind == "ingredient":
		output_icon.set_ingredient(output_id)
	else:
		output_icon.set_item_id(output_id)


func _clear_input_rows() -> void:
	for child in input_list.get_children():
		child.queue_free()


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	if recipe.is_empty() or not is_instance_valid(player):
		return false
	for input in IndustrialRecipeCatalog.get_inputs(str(recipe.get("recipe_id", ""))):
		var ingredient_id := str(input.get("id", ""))
		var amount := float(input.get("amount", 0.0))
		var unit := str(input.get("unit", "kg"))
		if _player_input_amount(ingredient_id, unit) + GlobalVar.check_team_item_amount(player.team, ingredient_id) + 0.001 < amount:
			return false
	return true


func _player_input_amount(ingredient_id: String, unit: String) -> float:
	if not is_instance_valid(player):
		return 0.0
	var weight := 0.0
	for item in player.backpack_items:
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id:
			weight += maxf(0.0, float(item.get("weight_kg", 0.0)))
	return weight if unit == "kg" else weight / IngredientCatalog.get_pickup_unit_kg(ingredient_id)


func _format_output(output: Dictionary) -> String:
	return IndustrialRecipeCatalog.format_quantity(float(output.get("amount", 0.0)), str(output.get("unit", "item")))


func _recipe_exists_in_list(recipe_id: String, recipes: Array[Dictionary]) -> bool:
	for recipe in recipes:
		if str(recipe.get("recipe_id", "")) == recipe_id:
			return true
	return false


func _touch_ui_activity() -> void:
	last_ui_activity_msec = Time.get_ticks_msec()


func _is_out_of_interaction_range() -> bool:
	return not is_instance_valid(player) or not is_instance_valid(workbench) \
		or player.global_position.distance_to(workbench.get_interaction_position()) > INTERACTION_DISTANCE + 1.0


func _reason_text(reason: String) -> String:
	match reason:
		"unknown_player": return "玩家状态不可用。"
		"unknown_station": return "找不到工业工作台。"
		"wrong_team": return "不能使用敌方工作台。"
		"station_in_use": return "队友正在使用这个工作台。"
		"station_out_of_range": return "离工作台太远。"
		"ingredients_insufficient": return "输入材料不足。"
		"invalid_or_busy_recipe": return "配方无效或工作台正忙。"
		"output_not_ready": return "成品还没有完成。"
		"personal_bag_full": return "背包容量不足，成品仍留在工作台。"
		"equipment_already_owned": return "你已经拥有这件装备，成品仍留在工作台。"
		"delivery_failed": return "无法交付成品，成品仍留在工作台。"
	return reason if not reason.is_empty() else "操作失败。"
