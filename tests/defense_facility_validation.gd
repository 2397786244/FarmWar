extends Node

const MAP_FACILITY_CATALOG := preload("res://src/map_facility_catalog.gd")
const DEFENSE_SCENES := {
	"tall_brick": "res://character/weapons/TallBrick.tscn",
	"tall_log_wall": "res://character/weapons/TallLogWall.tscn",
	"tall_mesh_wall": "res://character/weapons/TallMeshWall.tscn",
	"wire_mesh_gate": "res://character/weapons/WireMeshGate.tscn",
	"chain_link_fence": "res://character/weapons/ChainLinkFence.tscn",
	"road_barrier_left": "res://buildings/RoadBarrierLeft.tscn",
}
const DESTRUCTION_PARTICLE_COLORS := {
	"tall_log_wall": Color(0.458824, 0.270588, 0.168627, 1),
	"tall_brick": Color(0.352941, 0.094118, 0.12549, 1),
	"tall_mesh_wall": Color(0.466667, 0.490196, 0.501961, 1),
	"wire_mesh_gate": Color(0.466667, 0.490196, 0.501961, 1),
}

var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var assets := MAP_FACILITY_CATALOG.get_assets("defense")
	_check(assets.size() == 6, "defense catalog contains six facilities")
	var catalog_entry: Dictionary = MAP_FACILITY_CATALOG.get_asset_by_id("chain_link_fence")
	_check(str(catalog_entry.get("label", "")) == "地面铁丝网", "chain link fence has a Chinese map editor label")
	_check(str(catalog_entry.get("path", "")) == DEFENSE_SCENES["chain_link_fence"], "chain link fence scene is in the defense catalog")

	for tool_id: String in DEFENSE_SCENES:
		var packed := load(DEFENSE_SCENES[tool_id]) as PackedScene
		_check(packed != null, "%s scene loads" % tool_id)
		if packed == null:
			continue
		var facility := packed.instantiate() as Node3D
		_check(facility != null, "%s scene instantiates" % tool_id)
		if facility == null:
			continue
		add_child(facility)
		await get_tree().process_frame
		_check(_has_property(facility, "auto_respawn"), "%s exposes auto respawn" % tool_id)
		_check(_has_property(facility, "respawn_seconds"), "%s exposes respawn seconds" % tool_id)
		_check(is_equal_approx(float(facility.get("respawn_seconds")), 60.0), "%s defaults to 60 second respawn" % tool_id)
		_check(facility.has_method("apply_network_destroyed"), "%s can enter destroyed state" % tool_id)
		_check(facility.has_method("apply_network_respawned"), "%s can restore from respawn" % tool_id)
		if DESTRUCTION_PARTICLE_COLORS.has(tool_id):
			var configured_color: Variant = facility.get("destruction_particle_color")
			_check(
				configured_color is Color \
					and (configured_color as Color).is_equal_approx(DESTRUCTION_PARTICLE_COLORS[tool_id]),
				"%s has the configured destruction particle color" % tool_id
			)
			var effect_count_before := get_tree().get_nodes_in_group("map_defense_break_effects").size()
			facility.call("apply_network_destroyed")
			await get_tree().process_frame
			_check(
				get_tree().get_nodes_in_group("map_defense_break_effects").size() == effect_count_before + 1,
				"%s spawns a destruction particle effect" % tool_id
			)
			facility.call("apply_network_respawned", float(facility.get("max_hp")))
		if tool_id == "chain_link_fence":
			_check(not bool(facility.get("active")), "map-authored chain link fence waits for runtime activation")
			facility.call("activate_tool")
			_check(bool(facility.get("active")), "chain link fence activates as a defense facility")
			facility.call("apply_network_destroyed")
			_check(bool(facility.get("destroyed")) and not bool(facility.get("active")), "chain link fence deactivates when destroyed")
			facility.call("apply_network_respawned", 300.0)
			_check(not bool(facility.get("destroyed")) and bool(facility.get("active")), "chain link fence reactivates after respawn")
		facility.queue_free()
	await get_tree().process_frame
	_finish()


func _has_property(object: Object, property_name: String) -> bool:
	for property_info: Dictionary in object.get_property_list():
		if str(property_info.get("name", "")) == property_name:
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("[DefenseFacilityValidation] PASS")
		get_tree().quit(0)
		return
	for failure: String in failures:
		push_error("[DefenseFacilityValidation] " + failure)
	get_tree().quit(1)
