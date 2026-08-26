extends Node
class_name PromotionalDummyFireController

## Presentation-only firing loop for map-editor promotional dummies.
##
## The weapon scene is the same scene used by Player, but the dummy must never
## become a gameplay shooter.  We therefore call the weapon's visual-only
## entry point (or its muzzle visual fallback) and keep tool_owner empty.

@export var continuous_fire := false
@export_range(0.03, 10.0, 0.01) var fire_interval := 0.1

var _cooldown_remaining := 0.0


func _ready() -> void:
	# The map editor aligns the dummy weapon at priority 100.  Fire visuals run
	# immediately afterward so the muzzle flash is emitted from the corrected
	# muzzle transform in the same frame.
	process_priority = 110
	set_process(continuous_fire)


func configure(enabled: bool, interval: float) -> void:
	continuous_fire = enabled
	fire_interval = maxf(0.03, interval)
	_cooldown_remaining = 0.0
	set_process(continuous_fire)


func _process(delta: float) -> void:
	if not continuous_fire:
		return
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - delta)
	if _cooldown_remaining > 0.0:
		return
	var weapon := _get_held_weapon()
	if weapon == null:
		return
	_fire_visual(weapon)
	_cooldown_remaining = maxf(0.03, fire_interval)


func _get_held_weapon() -> Node3D:
	var dummy := get_parent() as Node3D
	if dummy == null:
		return null
	var weapon_grip := dummy.get_node_or_null(
		"RightHandSocket/ToolPivot/WeaponGrip"
	) as Node3D
	if weapon_grip == null:
		return null
	for child in weapon_grip.get_children():
		var candidate := child as Node3D
		if candidate != null and (
			candidate.has_method("emit_visual_only")
			or candidate.has_method("play_muzzle_visual")
		):
			return candidate
	return null


func _fire_visual(weapon: Node3D) -> void:
	if weapon.has_method("emit_visual_only"):
		weapon.call("emit_visual_only")
	elif weapon.has_method("play_muzzle_visual"):
		weapon.call("play_muzzle_visual")
