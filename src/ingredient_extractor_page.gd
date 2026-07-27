extends Control
class_name IngredientExtractorPage

const INTERACTION_DISTANCE := 4.0
const ITEM_ICON_SCENE := preload("res://ui/item_icon.tscn")

@onready var window: PanelContainer = $Window
@onready var recipe_list: VBoxContainer = $Window/Margin/HBox/RecipePanel/Margin/VBox/RecipeListScroll/RecipeList
@onready var detail_title: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/DetailTitle
@onready var status_label: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Status
@onready var input_slots: Array[Label] = [
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot0Panel/Slot0,
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot1Panel/Slot1,
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/InputSlots/Slot2Panel/Slot2,
]
@onready var output_name: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemName
@onready var output_weight: Label = $Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/ItemWeight
@onready var progress: ProgressBar = $Window/Margin/HBox/DetailPanel/Margin/VBox/Progress
@onready var start_button: Button = $Window/Margin/HBox/DetailPanel/Margin/VBox/StartButton

var player: GamePlayer
var extractor: IngredientExtractor
var selected_recipe_id := ""
var refresh_accumulator := 0.0
var input_icons: Array[ItemIcon] = []
var output_icon: ItemIcon


func _ready() -> void:
	_install_slot_icons()
	window.visible = false
	$Window/Margin/HBox/DetailPanel/Margin/VBox/CloseButton.pressed.connect(close)
	start_button.pressed.connect(_on_primary_action_pressed)


func is_open() -> bool:
	return window.visible


func _process(delta: float) -> void:
	if not is_open() or not is_instance_valid(extractor):
		return
	if _is_out_of_interaction_range():
		close()
		return
	refresh_accumulator += delta
	if refresh_accumulator >= 0.25:
		refresh_accumulator = 0.0
		_refresh()


func refresh_if_open() -> void:
	if is_open():
		_refresh()


func open_for(next_extractor: IngredientExtractor, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_extractor) or not is_instance_valid(next_player):
		return
	extractor = next_extractor
	player = next_player
	if selected_recipe_id.is_empty():
		selected_recipe_id = extractor.recipe_id
		if selected_recipe_id.is_empty() and not ExtractorRecipeCatalog.get_recipes().is_empty():
			selected_recipe_id = str(ExtractorRecipeCatalog.get_recipes()[0].get("recipe_id", ""))
	window.visible = true
	var backpack := player.get_node_or_null("SubViewport/PlayerBackpack") as PlayerBackpack
	if backpack != null:
		backpack.show_companion()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_request_action("acquire")
	_refresh()


func close() -> void:
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
		status_label.text = str(result.get("reason", "操作失败"))
		return
	status_label.text = ""
	_refresh()


func try_take_completed_output() -> bool:
	if not is_open() or not is_instance_valid(extractor) or not extractor.complete:
		return false
	_request_action("take")
	return true


func _on_primary_action_pressed() -> void:
	if not is_instance_valid(extractor):
		return
	if extractor.complete:
		_request_action("take")
		return
	_request_action("start", selected_recipe_id)


func _refresh() -> void:
	if not is_instance_valid(extractor) or not is_instance_valid(player):
		return
	progress.visible = extractor.cooking
	progress.value = extractor.get_progress() * 100.0
	if not extractor.recipe_id.is_empty():
		selected_recipe_id = extractor.recipe_id
	_rebuild_recipe_list()
	var recipe := ExtractorRecipeCatalog.get_recipe(selected_recipe_id)
	detail_title.text = ExtractorRecipeCatalog.get_display_name(selected_recipe_id) if not recipe.is_empty() else "选择左侧提取方案"
	for slot in input_slots:
		slot.text = ""
		(slot.get_parent() as Control).visible = false
	for icon in input_icons:
		icon.set_ingredient("")
	var inputs := ExtractorRecipeCatalog.get_inputs(selected_recipe_id)
	var first_slot := 1 if inputs.size() == 1 else 0
	for input_index in range(inputs.size()):
		var input: Dictionary = inputs[input_index]
		var definition := IngredientCatalog.get_definition(str(input.get("ingredient_id", "")))
		var label := input_slots[first_slot + input_index]
		input_icons[first_slot + input_index].set_ingredient(str(input.get("ingredient_id", "")))
		label.text = "%s\n%.2f kg" % [str(definition.get("display_name", "")), float(input.get("weight_kg", 0.0))]
		(label.get_parent() as Control).visible = true
	var output_id := str(recipe.get("output_ingredient_id", ""))
	var output_definition := IngredientCatalog.get_definition(output_id)
	output_icon.set_ingredient(output_id)
	output_name.text = str(output_definition.get("display_name", "")) if not output_definition.is_empty() else "产物"
	output_weight.text = "产出 %.2f kg" % float(recipe.get("output_weight_kg", 0.0)) if not recipe.is_empty() else ""
	var is_idle := extractor.recipe_id.is_empty() and not extractor.cooking and not extractor.complete
	start_button.disabled = extractor.cooking or (not extractor.complete and (not is_idle or recipe.is_empty() or not _has_recipe_inputs(recipe)))
	start_button.text = "收取产物" if extractor.complete else "提取中" if extractor.cooking else "开始提取"
	if extractor.cooking:
		status_label.text = "提取会在关闭界面后继续。"
	elif extractor.complete:
		status_label.text = "提取完成，请按 [E] 领取产物。"
	elif status_label.text.begins_with("提取"):
		status_label.text = ""


func _rebuild_recipe_list() -> void:
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()
	for recipe: Dictionary in ExtractorRecipeCatalog.get_recipes():
		var recipe_id := str(recipe.get("recipe_id", ""))
		var available := _has_recipe_inputs(recipe)
		var button := Button.new()
		button.custom_minimum_size = Vector2(285, 68)
		# The bracket is a fixed visual reservation for a future ingredient icon.
		button.text = "[ ]  %s\n     产出 %.2f kg" % [
			ExtractorRecipeCatalog.get_display_name(recipe_id),
			float(recipe.get("output_weight_kg", 0.0)),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", Color("#FFF0A3") if available else Color("#B6BDC4"))
		button.disabled = not extractor.recipe_id.is_empty() and recipe_id != extractor.recipe_id
		button.toggle_mode = true
		button.button_pressed = recipe_id == selected_recipe_id
		button.pressed.connect(func() -> void:
			selected_recipe_id = recipe_id
			_refresh()
		)
		recipe_list.add_child(button)


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	for input: Dictionary in ExtractorRecipeCatalog.get_inputs(str(recipe.get("recipe_id", ""))):
		var ingredient_id := str(input.get("ingredient_id", ""))
		var available := _player_ingredient_weight(ingredient_id) + GlobalVar.check_team_item_amount(player.team, ingredient_id)
		if available + 0.001 < float(input.get("weight_kg", 0.0)):
			return false
	return not recipe.is_empty()


func _player_ingredient_weight(ingredient_id: String) -> float:
	var total := 0.0
	for item: Dictionary in player.backpack_items:
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id \
				and not _item_is_chopped(item):
			total += float(item.get("weight_kg", 0.0))
	return total


func _request_action(action_name: String, recipe_id := "") -> void:
	if not is_instance_valid(extractor) or not is_instance_valid(player):
		return
	var action := {
		"station_kind": "extractor",
		"action": action_name,
		"recipe_id": recipe_id,
		"station_path": str(extractor.get_path()),
		"station_position": extractor.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	player.apply_authoritative_extractor_action_result(result)
	apply_authoritative_action_result(result)


func _item_is_chopped(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) or str(item.get("preparation", "")) == "chopped" \
		or str(item.get("model_state", "")) == "chopped"


func _is_out_of_interaction_range() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(extractor):
		return true
	var player_position := player.global_position
	var extractor_position := extractor.global_position
	return Vector2(player_position.x, player_position.z).distance_to(
		Vector2(extractor_position.x, extractor_position.z)
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
		icon.custom_minimum_size = Vector2(44, 44)
		row.add_child(icon)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		input_icons.append(icon)
	var output_box := output_name.get_parent() as VBoxContainer
	output_icon = ITEM_ICON_SCENE.instantiate() as ItemIcon
	output_icon.custom_minimum_size = Vector2(46, 46)
	output_box.add_child(output_icon)
	output_box.move_child(output_icon, output_name.get_index())
