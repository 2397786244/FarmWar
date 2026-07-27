extends StaticBody3D
class_name GovernmentBoard

@export var interaction_hint := "按E打开公告栏"
@export_multiline var notice_text := "近期树林内发现黑熊出没，请居民小心"


func _ready() -> void:
	var interaction_area := get_node_or_null("InteractionArea") as Area3D
	if interaction_area == null:
		push_warning("%s: InteractionArea is missing." % name)
		return
	interaction_area.collision_layer = 512
	interaction_area.collision_mask = 8
	interaction_area.monitoring = true
	interaction_area.monitorable = true
	interaction_area.add_to_group("government_board_interaction_areas")


func get_interaction_hint(_player: GamePlayer = null) -> String:
	return interaction_hint


func get_notice_text() -> String:
	return notice_text
