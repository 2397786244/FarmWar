extends Node

var _failed := false


func _ready() -> void:
	call_deferred("_validate")


func _validate() -> void:
	var original_mode := GameAuthority.mode
	var original_pending := GameAuthority.pending_farm_tile_deltas.duplicate(true)
	GameAuthority.mode = GameAuthority.MODE_SERVER

	var replicator := MultiplayerWorldReplicatorService.new()
	add_child(replicator)
	for index in range(2):
		var drone := (load("res://character/weapons/NormalDrone.tscn") as PackedScene).instantiate() as NormalDrone
		add_child(drone)
		await get_tree().process_frame
		replicator._disable_visual_runtime(drone)
		drone.enable_network_visuals()
		var camera := drone.get_node_or_null("CameraPivot/Camera3D") as Camera3D
		_check(is_instance_valid(camera), "remote drone %d keeps a valid camera node" % index)
		_check(camera != null and not camera.current, "remote drone %d camera stays inactive" % index)
		drone.queue_free()

	var seed_id := str(GlobalVar.plant_item_list[0]) if not GlobalVar.plant_item_list.is_empty() else "tomato"
	var tile := (load("res://items/farm_tile.tscn") as PackedScene).instantiate() as FarmTile
	add_child(tile)
	await get_tree().process_frame
	_check(tile.plant(seed_id, "red"), "authority plants a crop")
	_check(int(Farmlandmanager.get_performance_stats().get("active_tiles", 0)) > 0, "planted crop enters active farm set")
	GameAuthority.pending_farm_tile_deltas.clear()
	var growth_before := tile.growth_value
	Farmlandmanager.step_timer()
	_check(tile.growth_value > growth_before, "active crop advances during manager tick")
	_check(tile.get_node("Label3D").text == "%d%%" % tile.growth_value, "authority growth label updates")
	var growth_delta: Dictionary = {}
	for value: Variant in GameAuthority.pending_farm_tile_deltas.values():
		if value is Dictionary and str((value as Dictionary).get("effect", "")) == "growth":
			growth_delta = value as Dictionary
			break
	_check(not growth_delta.is_empty(), "growth publishes a reliable farm delta")

	var proxy_tile := (load("res://items/farm_tile.tscn") as PackedScene).instantiate() as FarmTile
	add_child(proxy_tile)
	await get_tree().process_frame
	proxy_tile.apply_authoritative_delta(growth_delta)
	_check(proxy_tile.growth_value == tile.growth_value, "client proxy applies growth value")
	_check(proxy_tile.get_node("Label3D").text == tile.get_node("Label3D").text, "client proxy growth label matches authority")

	tile.queue_free()
	proxy_tile.queue_free()
	replicator.queue_free()
	GameAuthority.pending_farm_tile_deltas = original_pending
	GameAuthority.mode = original_mode
	print("Drone/crop sync validation: %s" % ("FAILED" if _failed else "PASS"))
	get_tree().quit(1 if _failed else 0)


func _check(condition: bool, message: String) -> void:
	if condition:
		print("[PASS] %s" % message)
	else:
		_failed = true
		push_error("[FAIL] %s" % message)
