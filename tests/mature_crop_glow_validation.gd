extends Node3D

const FARM_TILE_SCENE := preload("res://items/farm_tile.tscn")

var failures := 0
var _tile: FarmTile


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	GameAuthority.start_local_mode({
		"display_name": "MatureCropGlowValidation",
		"team": "red",
		"position": Vector3.ZERO,
	})
	GlobalVar.gameworld = self

	_check(str(ProjectSettings.get_setting("application/config/version", "")) == "0.3.5", "project version is 0.3.5")
	_tile = FARM_TILE_SCENE.instantiate() as FarmTile
	_check(_tile != null, "FarmTile scene loads")
	if _tile == null:
		_finish()
		return
	add_child(_tile)
	await get_tree().process_frame

	var glow := _tile.get_node_or_null("MatureCropGlow") as MatureCropGlow
	_check(glow != null, "FarmTile contains MatureCropGlow")
	if glow == null:
		_finish()
		return
	_check(not glow.is_active(), "mature glow starts hidden")
	_check(is_equal_approx(glow.get_glow_height(), 0.24), "mature glow height is 0.24 m")
	_check(glow.get_outer_size().is_equal_approx(Vector2(2.04, 2.04)), "mature glow surrounds the tile perimeter")
	_check(
		glow.find_children("*", "GPUParticles3D", true, false).is_empty()
			and glow.find_children("*", "CPUParticles3D", true, false).is_empty(),
		"mature glow does not use a particle system"
	)
	var glow_mesh := MatureCropGlow._get_shared_mesh()
	_check(glow_mesh != null and glow_mesh.get_surface_count() == 1, "mature glow builds one shared mesh surface")
	_check(
		glow_mesh != null and is_equal_approx(glow_mesh.get_aabb().size.y, 0.24),
		"mature glow mesh uses the configured vertical height"
	)

	_check(_tile.apply_authoritative_plant("potato", "red", 20, false), "immature crop is planted")
	_check(not _tile.can_harvest and not glow.is_active(), "immature crop keeps the glow hidden")

	_check(_tile.apply_authoritative_plant("potato", "red", 100, true), "mature crop is planted")
	_check(_tile.can_harvest and glow.is_active(), "mature crop enables the glow")

	var mature_state := _tile.get_authoritative_state()
	var immature_state := mature_state.duplicate(true)
	immature_state["farm_revision"] = int(mature_state.get("farm_revision", 0)) + 1
	immature_state["growth_value"] = 20
	immature_state["can_harvest"] = false
	_tile.apply_authoritative_state(immature_state)
	_check(not _tile.can_harvest and not glow.is_active(), "authoritative immature state hides the glow")

	var restored_mature_state := mature_state.duplicate(true)
	restored_mature_state["farm_revision"] = int(immature_state.get("farm_revision", 0)) + 1
	_tile.apply_authoritative_state(restored_mature_state)
	_check(_tile.can_harvest and glow.is_active(), "authoritative mature state restores the glow")

	_tile.apply_authoritative_harvest()
	_check(_tile.seed_record.is_empty() and not glow.is_active(), "normal harvest hides the glow")

	_check(_tile.apply_authoritative_plant("grape", "red", 100, true), "reharvestable crop is planted mature")
	_check(glow.is_active(), "reharvestable mature crop enables the glow")
	_tile.apply_authoritative_harvest()
	_check(not _tile.can_harvest and not glow.is_active(), "regrowth hides the glow")

	_finish()


func _finish() -> void:
	if failures == 0:
		print("[MatureCropGlowValidation] PASS all checks")
	else:
		push_error("[MatureCropGlowValidation] FAIL count=%d" % failures)
	if is_instance_valid(_tile):
		_tile.queue_free()
	get_tree().quit(0 if failures == 0 else 1)


func _check(condition: bool, description: String) -> void:
	if condition:
		print("[MatureCropGlowValidation] PASS: %s" % description)
	else:
		failures += 1
		push_error("[MatureCropGlowValidation] FAIL: %s" % description)
