extends Node3D
class_name SproutTool

@export var  tool_owner :String = ""
@export var selected_seed_id := "potato"
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func emit():
	#print("OK SHOOT")
	if tool_owner == "":
		return
	play_muzzle_visual()
	if not $RayCast3D.is_colliding():
		return
	var tile := Farmlandmanager.resolve_raycast_tile($RayCast3D as RayCast3D)
	if tile != null:
		var seed_id := selected_seed_id
		if not IngredientCatalog.is_plantable(seed_id):
			var plantable_ids := IngredientCatalog.get_plantable_ids()
			seed_id = "potato" if plantable_ids.has("potato") else (plantable_ids[0] if not plantable_ids.is_empty() else "")
		if not seed_id.is_empty():
			tile.plant(seed_id, tool_owner)


func play_muzzle_visual() -> void:
	var emitter := $SeedEmitter as GPUParticles3D
	# Explicitly restart the one-shot cycle.  Setting emitting alone does not
	# restart a particle system that is already partway through its last cycle.
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = true


func get_held_item_info_text(_item: Dictionary, definition: Dictionary) -> String:
	var tool_name := str(definition.get("name", definition.get("short", "播种炮")))
	var seed_definition := IngredientCatalog.get_definition(selected_seed_id)
	var seed_name := str(seed_definition.get("display_name", selected_seed_id))
	return "%s\n当前播种:%s" % [tool_name, seed_name]
