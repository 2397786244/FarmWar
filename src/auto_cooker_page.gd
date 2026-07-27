extends Control
class_name AutoCookerPage

const INTERACTION_DISTANCE := 4.0
const UI_REFRESH_INTERVAL := 0.25
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")

@onready var window: PanelContainer = $Window
@onready var recipe_list: VBoxContainer = $Window/Margin/HBox/RecipePanel/Margin/VBox/RecipeListScroll/RecipeList
@onready var detail_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/DetailTitle
@onready var status_label: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Status
@onready var input_slots: Array[Label] = [
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot0Panel/Slot0,
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot1Panel/Slot1,
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot2Panel/Slot2,
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot3Panel/Slot3,
]
@onready var output_name: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemName
@onready var output_quantity: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemQuantity
@onready var progress: ProgressBar = $Window/Margin/HBox/DetailPanel/Margin/VBox/Progress
@onready var start_button: Button = $Window/Margin/HBox/DetailPanel/Margin/VBox/StartButton

var player: GamePlayer
var cooker: AutoCooker
var selected_recipe_id := ""
var refresh_accumulator := 0.0
var recipe_list_dirty := true
var displayed_cooker_recipe_id := ""
var input_icons: Array[ItemIcon] = []
var output_icon: ItemIcon


func _ready() -> void:
	_install_slot_icons()
	window.visible = false
	$Window/Margin/HBox/DetailPanel/Margin/VBox/CloseButton.pressed.connect(close)
	start_button.pressed.connect(_on_primary_action_pressed)


func is_open() -> bool:
	return window.visible


func open_for(next_cooker: AutoCooker, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_cooker) or not is_instance_valid(next_player):
		return
	cooker = next_cooker
	player = next_player
	if selected_recipe_id.is_empty() and not cooker.recipe_id.is_empty():
		selected_recipe_id = cooker.recipe_id
	recipe_list_dirty = true
	window.visible = true
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.show_companion()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_request("acquire")
	_refresh()


func close() -> void:
	if is_instance_valid(cooker):
		_request("release")
	window.visible = false
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.hide_companion()
	if is_instance_valid(player) and not player.is_remote_proxy:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	if not is_open() or not is_instance_valid(cooker) or not is_instance_valid(player):
		return
	if _is_out_of_interaction_range():
		close()
		return
	refresh_accumulator += delta
	if refresh_accumulator >= UI_REFRESH_INTERVAL:
		refresh_accumulator = 0.0
		_refresh()


func refresh_if_open() -> void:
	if is_open():
		_refresh()


func take_completed_output() -> void:
	if is_open() and is_instance_valid(cooker) and cooker.complete:
		_request("take")


func apply_authoritative_action_result(result: Dictionary) -> void:
	if not is_open() or not is_instance_valid(player) or int(result.get("peer_id", 0)) != player.authority_peer_id:
		return
	if not bool(result.get("ok", false)):
		status_label.text = str(result.get("reason", "操作失败"))
		return
	if str(result.get("action", "")) == "start":
		var inputs: Variant = result.get("personal_inputs", [])
		if inputs is Array:
			for input in inputs:
				if input is Dictionary:
					_remove_backpack_ingredient(str((input as Dictionary).get("ingredient_id", "")), float((input as Dictionary).get("weight_kg", 0.0)))
	elif str(result.get("action", "")) == "take":
		var output: Variant = result.get("result", {})
		if output is Dictionary:
			player.add_personal_dish(str((output as Dictionary).get("dish_id", "")), int((output as Dictionary).get("quantity", 0)), float((output as Dictionary).get("total_weight_kg", 0.0)))
	status_label.text = ""
	_refresh()


func _on_primary_action_pressed() -> void:
	if not is_instance_valid(cooker):
		return
	if cooker.complete:
		_request("take")
		return
	_request("start", selected_recipe_id)


func _refresh() -> void:
	if not is_instance_valid(cooker) or not is_instance_valid(player):
		return
	if displayed_cooker_recipe_id != cooker.recipe_id:
		displayed_cooker_recipe_id = cooker.recipe_id
		if not cooker.recipe_id.is_empty():
			selected_recipe_id = cooker.recipe_id
		recipe_list_dirty = true
	if recipe_list_dirty:
		_rebuild_recipe_list()
		recipe_list_dirty = false
	var recipe := AutoCookerRecipeCatalog.get_recipe(selected_recipe_id)
	detail_title.text = str(recipe.get("display_name", "选择左侧料理"))
	for slot in input_slots:
		slot.text = ""
		(slot.get_parent() as Control).visible = false
	for icon in input_icons:
		icon.set_ingredient("")
	var inputs := AutoCookerRecipeCatalog.get_ingredients(selected_recipe_id)
	for input_index in range(mini(inputs.size(), input_slots.size())):
		var input: Dictionary = inputs[input_index]
		var definition := IngredientCatalog.get_definition(str(input.get("ingredient_id", "")))
		var required_weight := float(input.get("weight_kg", 0.0))
		var available_weight := _available_weight(str(input.get("ingredient_id", "")))
		var label := input_slots[input_index]
		input_icons[input_index].set_ingredient(str(input.get("ingredient_id", "")))
		label.text = "%s\n%.2f / %.2f kg" % [str(definition.get("display_name", "")), available_weight, required_weight]
		(label.get_parent() as Control).visible = true
	var result: Variant = recipe.get("result", {})
	var result_data := result as Dictionary if result is Dictionary else {}
	output_icon.set_dish(str(result_data.get("dish_id", "")))
	output_name.text = str(result_data.get("display_name", "料理产出")) if not result_data.is_empty() else "料理产出"
	output_quantity.text = "产出 %d 份" % int(result_data.get("quantity", 0)) if not result_data.is_empty() else ""
	progress.value = cooker.get_progress() * 100.0
	progress.visible = cooker.cooking
	var is_idle := cooker.recipe_id.is_empty() and not cooker.cooking and not cooker.complete
	start_button.disabled = cooker.cooking or (not cooker.complete and (not is_idle or recipe.is_empty() or not _has_recipe_inputs(recipe)))
	start_button.text = "领取成品" if cooker.complete else "制作中" if cooker.cooking else "开始制作"
	if cooker.cooking:
		status_label.text = "自动制作中 %d%%，关闭界面后仍会继续。" % roundi(cooker.get_progress() * 100.0)
	elif cooker.complete:
		status_label.text = "料理已完成，请按 [E] 领取。"
	elif status_label.text.begins_with("自动制作中"):
		status_label.text = ""


func _rebuild_recipe_list() -> void:
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()
	for recipe: Dictionary in AutoCookerRecipeCatalog.get_recipes():
		var recipe_id := str(recipe.get("recipe_id", ""))
		var available := _has_recipe_inputs(recipe)
		var selected := recipe_id == selected_recipe_id
		var button := Button.new()
		button.custom_minimum_size = Vector2(285, 68)
		button.text = "%s  %s\n     产出 %d 份" % ["[x]" if selected else "[ ]", str(recipe.get("display_name", recipe_id)), int((recipe.get("result", {}) as Dictionary).get("quantity", 0))]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", Color("#FFE08A") if selected else Color("#FFF0A3") if available else Color("#B6BDC4"))
		button.disabled = not cooker.recipe_id.is_empty() and recipe_id != cooker.recipe_id
		button.toggle_mode = true
		button.button_pressed = selected
		button.pressed.connect(func() -> void:
			selected_recipe_id = recipe_id
			recipe_list_dirty = true
			_refresh()
		)
		recipe_list.add_child(button)


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	for input: Dictionary in AutoCookerRecipeCatalog.get_ingredients(str(recipe.get("recipe_id", ""))):
		if _available_weight(str(input.get("ingredient_id", ""))) + 0.001 < float(input.get("weight_kg", 0.0)):
			return false
	return true


func _request(action_name: String, recipe_id := "") -> void:
	if not is_instance_valid(cooker) or not is_instance_valid(player):
		return
	var action := {"station_kind":"auto_cooker", "action":action_name, "recipe_id":recipe_id, "station_path":str(cooker.get_path()), "station_position":cooker.global_position}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var response: Dictionary = GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	apply_authoritative_action_result(response)


func _available_weight(ingredient_id: String) -> float:
	var total := GlobalVar.check_team_item_amount(player.team, ingredient_id)
	for item in player.backpack_items:
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id and not bool(item.get("is_chopped", false)):
			total += float(item.get("weight_kg", 0.0))
	return total


func _remove_backpack_ingredient(ingredient_id: String, weight_kg: float) -> void:
	var remaining := weight_kg
	for index in range(player.backpack_items.size()):
		var item := player.get_backpack_item(index)
		if str(item.get("kind", "")) != "ingredient" or str(item.get("ingredient_id", "")) != ingredient_id or bool(item.get("is_chopped", false)):
			continue
		var removed := minf(remaining, float(item.get("weight_kg", 0.0)))
		if removed > 0.0:
			player.remove_personal_ingredient_from_slot(index, ingredient_id, removed, false)
			remaining -= removed
		if remaining <= 0.001:
			return


func _is_out_of_interaction_range() -> bool:
	var player_position := player.global_position
	var cooker_position := cooker.global_position
	return Vector2(player_position.x, player_position.z).distance_to(
		Vector2(cooker_position.x, cooker_position.z)
	) > INTERACTION_DISTANCE


func _install_slot_icons() -> void:
	for label in input_slots:
		var panel := label.get_parent() as PanelContainer
		panel.remove_child(label)
		var row := HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		panel.add_child(row)
		var icon := ITEM_ICON_SCENE.instantiate() as ItemIcon
		icon.custom_minimum_size = Vector2(40, 40)
		row.add_child(icon)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		input_icons.append(icon)
	var output_box := output_name.get_parent() as VBoxContainer
	output_icon = ITEM_ICON_SCENE.instantiate() as ItemIcon
	output_icon.custom_minimum_size = Vector2(46, 46)
	output_box.add_child(output_icon)
	output_box.move_child(output_icon, output_name.get_index())
