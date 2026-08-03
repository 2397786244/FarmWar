extends Node

# Creston map-only inventory smoke test. Edit this exported list in the inspector
# to grant any valid tool, ingredient, chopped ingredient, or prepared dish.
# Ingredients use weight_kg. Dishes accept servings or weight_kg, which is rounded
# to the closest whole serving using the dish definition's standard serving weight.
@export var enabled := true
@export var grant_once := true
@export var grant_delay_seconds := 1.0
@export var grant_entries: Array[Dictionary] = [
	{"kind": "ingredient", "ingredient_id": "water", "weight_kg": 3.0},
	{"kind": "ingredient", "ingredient_id": "oil", "weight_kg": 3.0},
	{"kind": "ingredient", "ingredient_id": "wheat_flour", "weight_kg": 3.0},
	{"kind": "ingredient", "ingredient_id": "yeast", "weight_kg": 3.0},
]

var elapsed_seconds := 0.0
var granted := false


func _process(delta: float) -> void:
	if CooperativeSession.is_active():
		return
	if not enabled or granted or not (GameAuthority.is_local_authority() or GameAuthority.is_server_authority()):
		return
	elapsed_seconds += delta
	if elapsed_seconds < grant_delay_seconds:
		return
	if GameAuthority.grant_test_backpack_entries_to_all(grant_entries):
		granted = grant_once
