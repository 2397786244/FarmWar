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
			_try_plant_with_cost(tile, seed_id)


func _try_plant_with_cost(tile: FarmTile, seed_id: String) -> bool:
	if tile == null or GameAuthority.should_send_network_requests():
		return false
	var planting_cost := IngredientCatalog.get_planting_cost(seed_id)
	if planting_cost <= 0 or GlobalVar.check_team_item_amount(tool_owner, "money") + 0.001 < planting_cost:
		return false
	if not GlobalVar.remove_item(tool_owner, "money", float(planting_cost)):
		return false
	if tile.plant(seed_id, tool_owner):
		return true
	GlobalVar.add_item(tool_owner, "money", float(planting_cost))
	return false


func play_muzzle_visual() -> void:
	var emitter := $SeedEmitter as GPUParticles3D
	# Explicitly restart the one-shot cycle.  Setting emitting alone does not
	# restart a particle system that is already partway through its last cycle.
	emitter.emitting = false
	emitter.restart()
	emitter.emitting = true


func get_held_item_info_text(_item: Dictionary, definition: Dictionary) -> String:
	# The seed carousel is the single source of visual seed-selection feedback.
	# Keep the lower-left gameplay notice intentionally short and do not expose
	# the crop name or planting cost there.
	return "播种枪"
