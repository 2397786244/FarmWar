extends PanelContainer
class_name IngredientPickupSlot

signal take_requested(slot_index: int)

@export var slot_index := -1
@onready var item_name: Label = $Margin/VBox/ItemName
@onready var item_weight: Label = $Margin/VBox/ItemWeight
@onready var take_button: Button = $Margin/VBox/TakeButton
@onready var item_icon: ItemIcon = $Margin/VBox/ItemIcon


func _ready() -> void:
	take_button.pressed.connect(func(): take_requested.emit(slot_index))


func set_ingredient(entry: Dictionary) -> void:
	item_icon.set_ingredient(str(entry.get("ingredient_id", "")))
	var weight_kg := float(entry.get("weight_kg", 0.0))
	var has_ingredient := not entry.is_empty() and weight_kg > 0
	item_name.text = str(entry.get("display_name", entry.get("ingredient_id", ""))) if has_ingredient else ""
	item_weight.text = "%.2f kg" % weight_kg if has_ingredient else ""
	take_button.text = "领取 %.2f kg" % minf(
		IngredientCatalog.get_pickup_unit_kg(str(entry.get("ingredient_id", ""))), weight_kg
	) if has_ingredient else ""
	take_button.disabled = not has_ingredient
