extends Node

@export var recipe_id := "black_pepper_beef_patty"
@export var required_servings := 40
@export_enum("all", "red", "blue") var target_team := "all"

var emitted := false


func _process(_delta: float) -> void:
	if emitted:
		return
	if GameAuthority.is_local_authority() or GameAuthority.is_server_authority():
		emitted = not FoodOrderEmitter.emit_recipe_order(target_team, recipe_id, required_servings).is_empty()
