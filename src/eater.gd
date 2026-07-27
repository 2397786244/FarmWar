extends Node3D
class_name EaterTool

@export var tool_owner := ""
@export_range(1, 16, 1) var bullet_limit := 2
@export_range(1, 128, 1) var mature_plot_limit := 20

@onready var absorption_area: Area3D = $Area3D
@onready var absorption_point: Node3D = $RayCast3D


func emit() -> void:
	if tool_owner.is_empty():
		return

	var bullets: Array[BoomBullet] = []
	var mature_plots: Array[FarmTile] = []
	for body in absorption_area.get_overlapping_bodies():
		if not is_instance_valid(body):
			continue
		if body is BoomBullet:
			var bullet := body as BoomBullet
			if bullet.get_bullet_owner() != tool_owner and not bullet.start_absorbing:
				bullets.append(bullet)
	for plot_value: Variant in Farmlandmanager.get_plots_in_radius(
		global_position,
		CombatBalance.get_float("eater", "range")
	):
		var plot := plot_value as FarmTile
		if is_instance_valid(plot) and plot.land_owner == tool_owner and plot.can_harvest:
			mature_plots.append(plot)

	bullets.sort_custom(_sort_nearest_first)
	mature_plots.sort_custom(_sort_nearest_first)

	var source := absorption_point.global_position
	for index in range(mini(bullet_limit, bullets.size())):
		if is_instance_valid(bullets[index]):
			bullets[index].begin_absorbing(source)

	for index in range(mini(mature_plot_limit, mature_plots.size())):
		if is_instance_valid(mature_plots[index]):
			mature_plots[index].harvest(source)


func _sort_nearest_first(a: Node3D, b: Node3D) -> bool:
	return global_position.distance_squared_to(a.global_position) < \
		global_position.distance_squared_to(b.global_position)
