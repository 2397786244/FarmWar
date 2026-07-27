class_name StreetLamp3D
extends StaticBody3D

@export_range(0.0, 16.0, 0.1) var night_light_energy := 9.0

var _light: Light3D
var _beam: GeometryInstance3D


func _ready() -> void:
	_light = find_child("NightLight", true, false) as Light3D
	_beam = find_child("LightBeam", true, false) as GeometryInstance3D
	if _light == null:
		push_warning("StreetLamp3D: NightLight child was not found on %s." % name)
		return
	_light.light_energy = 0.0
	if _beam != null:
		_beam.visible = false
	add_to_group("day_night_lamps")
	_sync_day_night_state()
	call_deferred("_sync_day_night_state")


func _sync_day_night_state() -> void:
	var day_night_system := get_tree().get_first_node_in_group("day_night_systems")
	if day_night_system != null and day_night_system.has_method("get_street_light_factor"):
		set_night_factor(float(day_night_system.call("get_street_light_factor")))


func set_night_factor(night_factor: float) -> void:
	if not is_instance_valid(_light):
		_light = find_child("NightLight", true, false) as Light3D
	if _light != null:
		var factor := clampf(night_factor, 0.0, 1.0)
		_light.light_energy = night_light_energy * factor
		if not is_instance_valid(_beam):
			_beam = find_child("LightBeam", true, false) as GeometryInstance3D
		if _beam != null:
			_beam.visible = factor > 0.01
