extends Control
class_name ItemIcon

@onready var texture_rect: TextureRect = $Texture
@onready var placeholder: Label = $Placeholder

var _pending_texture: Texture2D
var _pending_has_item := false


func _ready() -> void:
	_apply_texture()


func set_item(item: Dictionary) -> void:
	_set_texture(ItemIconCatalog.get_item_icon(item), not item.is_empty())


func set_item_id(item_id: String) -> void:
	_set_texture(ItemIconCatalog.get_icon_for_id(item_id), not item_id.is_empty())


func set_ingredient(ingredient_id: String, chopped := false) -> void:
	_set_texture(ItemIconCatalog.get_ingredient_icon(ingredient_id, chopped), not ingredient_id.is_empty())


func set_dish(dish_id: String) -> void:
	_set_texture(ItemIconCatalog.get_dish_icon(dish_id), not dish_id.is_empty())


func _set_texture(texture: Texture2D, has_item: bool) -> void:
	_pending_texture = texture
	_pending_has_item = has_item
	if is_node_ready():
		_apply_texture()


func _apply_texture() -> void:
	if not is_instance_valid(texture_rect) or not is_instance_valid(placeholder):
		return
	texture_rect.texture = _pending_texture
	texture_rect.visible = _pending_has_item and _pending_texture != null
	placeholder.visible = _pending_has_item and _pending_texture == null
