extends PanelContainer
class_name PlatingStationSlot

signal place_requested(ingredient_id: String, is_chopped: bool)

@onready var item_name: Label = $Margin/VBox/ItemName
@onready var item_weight: Label = $Margin/VBox/ItemWeight
@onready var place_button: Button = $Margin/VBox/PlaceButton
@onready var item_icon: ItemIcon = $Margin/VBox/ItemIcon

var ingredient_id := ""
var required_is_chopped := false


func _ready() -> void:
	place_button.pressed.connect(func() -> void: place_requested.emit(ingredient_id, required_is_chopped))


func set_recipe_slot(entry: Dictionary, player_has_ingredient: bool, editable: bool) -> void:
	ingredient_id = str(entry.get("ingredient_id", ""))
	required_is_chopped = bool(entry.get("is_chopped", false))
	item_icon.set_ingredient(ingredient_id, required_is_chopped)
	var occupied := bool(entry.get("placed", false))
	var required_weight := float(entry.get("required_weight_kg", 0.0))
	var has_requirement := not ingredient_id.is_empty() and required_weight > 0.0
	visible = has_requirement
	item_name.text = str(entry.get("display_name", ingredient_id)) if has_requirement else ""
	if not has_requirement:
		item_weight.text = ""
		place_button.text = ""
		place_button.disabled = true
		modulate = Color.WHITE
		return
	item_weight.text = "已放入" if occupied else "放入 %.2f kg" % required_weight
	place_button.text = "已放入" if occupied else "放入 %.2f kg" % required_weight
	place_button.disabled = occupied or not player_has_ingredient or not editable
	modulate = Color("#FFF2A8") if player_has_ingredient and not occupied else Color.WHITE
