extends Control

const SELECTOR_SCENE := preload("res://ui/sprout_seed_selector.tscn")

var failures := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var selector := SELECTOR_SCENE.instantiate() as SproutSeedSelector
	_check(selector != null, "seed selector scene loads")
	if selector == null:
		_finish()
		return
	add_child(selector)
	await get_tree().process_frame

	var seed_ids := IngredientCatalog.get_plantable_ids()
	_check(seed_ids.size() >= 4, "plantable seed list is available")
	var selected_index := seed_ids.find("potato")
	if selected_index < 0:
		selected_index = 0
	selector.refresh(seed_ids, selected_index)
	await get_tree().process_frame

	_check(selector.visible, "selector becomes visible after refresh")
	var carousel := selector.get_node_or_null("Carousel") as Control
	_check(carousel != null, "selector contains a clipped carousel")
	if carousel != null:
		var slot_nodes := carousel.get_children()
		_check(slot_nodes.size() == 3, "selector renders previous, current and next positions")
		if slot_nodes.size() == 3:
			var center_icon := slot_nodes[1] as TextureRect
			var outer_icon := slot_nodes[0] as TextureRect
			_check(center_icon != null and is_equal_approx(center_icon.modulate.a, 1.0), "center seed is opaque")
			_check(outer_icon != null and outer_icon.modulate.a < center_icon.modulate.a, "outer seed fades")

	_check(selector.get_node_or_null("LeftArrowHint") is Label, "left arrow hint is shown")
	_check(selector.get_node_or_null("RightArrowHint") is Label, "right arrow hint is shown")
	var selected_label := selector.get_node_or_null("SelectedSeedName") as Label
	_check(selected_label != null and not selected_label.text.is_empty(), "selected seed name is shown")
	selector.reset()
	_check(not selector.visible, "selector hides after reset")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("[SproutSeedSelectorValidation] PASS all checks")
	else:
		push_error("[SproutSeedSelectorValidation] FAIL count=%d" % failures)
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[SproutSeedSelectorValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[SproutSeedSelectorValidation] FAIL: %s" % description)
