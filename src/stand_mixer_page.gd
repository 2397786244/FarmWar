extends Control
class_name StandMixerPage

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
var mixer: StandMixer
var selected_recipe_id := ""
var refresh_accumulator := 0.0
var input_icons: Array[ItemIcon] = []
var output_icon: ItemIcon


func _ready() -> void:
	_install_slot_icons()
	window.visible = false
	$Window/Margin/HBox/RecipePanel/Margin/VBox/Title.text = "搅拌配方"
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Title.text = "立式搅拌机"
	$Window/Margin/HBox/DetailPanel/Margin/VBox/Process/OutputSlot/Margin/VBox/Caption.text = "搅拌产物"
	$Window/Margin/HBox/DetailPanel/Margin/VBox/CloseButton.pressed.connect(close)
	start_button.text = "开始搅拌"
	start_button.pressed.connect(_on_primary_action_pressed)


func is_open() -> bool:
	return window.visible


func _process(delta: float) -> void:
	if not is_open() or not is_instance_valid(mixer):
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


func open_for(next_mixer: StandMixer, next_player: GamePlayer) -> void:
	if not is_instance_valid(next_mixer) or not is_instance_valid(next_player):
		return
	mixer = next_mixer
	player = next_player
	if selected_recipe_id.is_empty():
		selected_recipe_id = mixer.recipe_id
		if selected_recipe_id.is_empty() and not MixerRecipeCatalog.get_recipes().is_empty():
			selected_recipe_id = str(MixerRecipeCatalog.get_recipes()[0].get("recipe_id", ""))
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
	if not is_open() or not is_instance_valid(mixer) or not mixer.complete:
		return false
	_request_action("take")
	return true


func _on_primary_action_pressed() -> void:
	if not is_instance_valid(mixer):
		return
	_request_action("take" if mixer.complete else "start", selected_recipe_id)


func _refresh() -> void:
	if not is_instance_valid(mixer) or not is_instance_valid(player):
		return
	progress.visible = mixer.cooking
	progress.value = mixer.get_progress() * 100.0
	if not mixer.recipe_id.is_empty():
		selected_recipe_id = mixer.recipe_id
	_rebuild_recipe_list()
	var recipe := MixerRecipeCatalog.get_recipe(selected_recipe_id)
	detail_title.text = MixerRecipeCatalog.get_display_name(selected_recipe_id) if not recipe.is_empty() else "选择左侧搅拌方案"
	for slot in input_slots:
		slot.text = ""
		(slot.get_parent() as Control).visible = false
	for icon in input_icons:
		icon.set_ingredient("")
	var inputs := MixerRecipeCatalog.get_inputs(selected_recipe_id)
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
	var is_idle := mixer.recipe_id.is_empty() and not mixer.cooking and not mixer.complete
	start_button.disabled = mixer.cooking or (not mixer.complete and (not is_idle or recipe.is_empty() or not _has_recipe_inputs(recipe)))
	start_button.text = "收取产物" if mixer.complete else "搅拌中" if mixer.cooking else "开始搅拌"
	if mixer.cooking:
		status_label.text = "搅拌会在关闭界面后继续。"
	elif mixer.complete:
		status_label.text = "搅拌完成，请按 [E] 领取产物。"
	elif status_label.text.begins_with("搅拌"):
		status_label.text = ""


func _rebuild_recipe_list() -> void:
	for child in recipe_list.get_children():
		recipe_list.remove_child(child)
		child.queue_free()
	for recipe: Dictionary in MixerRecipeCatalog.get_recipes():
		var recipe_id := str(recipe.get("recipe_id", ""))
		var available := _has_recipe_inputs(recipe)
		var button := Button.new()
		button.custom_minimum_size = Vector2(285, 68)
		button.text = "[ ]  %s\n     产出 %.2f kg" % [
			MixerRecipeCatalog.get_display_name(recipe_id),
			float(recipe.get("output_weight_kg", 0.0)),
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 17)
		button.add_theme_color_override("font_color", Color("#FFF0A3") if available else Color("#B6BDC4"))
		button.disabled = not mixer.recipe_id.is_empty() and recipe_id != mixer.recipe_id
		button.toggle_mode = true
		button.button_pressed = recipe_id == selected_recipe_id
		button.pressed.connect(func() -> void:
			selected_recipe_id = recipe_id
			_refresh()
		)
		recipe_list.add_child(button)


func _has_recipe_inputs(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	for input: Dictionary in MixerRecipeCatalog.get_inputs(str(recipe.get("recipe_id", ""))):
		var ingredient_id := str(input.get("ingredient_id", ""))
		var available := _player_ingredient_weight(ingredient_id) + GlobalVar.check_team_item_amount(player.team, ingredient_id)
		if available + 0.001 < float(input.get("weight_kg", 0.0)):
			return false
	return true


func _player_ingredient_weight(ingredient_id: String) -> float:
	var total := 0.0
	for item: Dictionary in player.backpack_items:
		if str(item.get("kind", "")) == "ingredient" and str(item.get("ingredient_id", "")) == ingredient_id \
				and not _item_is_chopped(item):
			total += float(item.get("weight_kg", 0.0))
	return total


func _request_action(action_name: String, recipe_id := "") -> void:
	if not is_instance_valid(mixer) or not is_instance_valid(player):
		return
	var action := {
		"station_kind": "mixer",
		"action": action_name,
		"recipe_id": recipe_id,
		"station_path": str(mixer.get_path()),
		"station_position": mixer.global_position,
	}
	if GameAuthority.should_send_network_requests():
		MultiplayerNetwork.submit_ingredient_pickup_action(action)
		return
	var result := GameAuthority.local_ingredient_pickup_action(player.authority_peer_id, action)
	player.apply_authoritative_mixer_action_result(result)
	apply_authoritative_action_result(result)


func _item_is_chopped(item: Dictionary) -> bool:
	return bool(item.get("is_chopped", false)) or str(item.get("preparation", "")) == "chopped" \
			or str(item.get("model_state", "")) == "chopped"


func _is_out_of_interaction_range() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(mixer):
		return true
	return Vector2(player.global_position.x, player.global_position.z).distance_to(
		Vector2(mixer.global_position.x, mixer.global_position.z)
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
