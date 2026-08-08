extends RigidBody3D
class_name PickupItem

signal despawn_requested(item_id: String)

const LIFETIME_SECONDS := 120.0
const MODEL_SCALE := 0.3
const FLOAT_HEIGHT := 0.12
const FLOAT_SPEED := 2.2
const ROTATION_SPEED := 0.65

var item_id := ""
var item_data: Dictionary = {}
var model_path := ""
var landed := false
var lifetime_remaining := LIFETIME_SECONDS
var _elapsed := 0.0
var _model: Node3D

@onready var visual_root: Node3D = $VisualRoot
@onready var model_pivot: Node3D = $VisualRoot/ModelPivot
@onready var fallback_visual: MeshInstance3D = get_node_or_null("VisualRoot/ModelPivot/FallbackVisual") as MeshInstance3D
@onready var glow_ring: MeshInstance3D = $VisualRoot/GlowRing
@onready var pickup_label: Label3D = $VisualRoot/PickupLabel


func _ready() -> void:
	add_to_group("dropped_pickup_items")
	body_entered.connect(_on_body_entered)
	if fallback_visual != null:
		fallback_visual.visible = true
	glow_ring.visible = false
	pickup_label.visible = false


func setup(state: Dictionary) -> void:
	item_id = str(state.get("item_id", ""))
	item_data = (state.get("item", {}) as Dictionary).duplicate(true) if state.get("item", {}) is Dictionary else {}
	model_path = str(state.get("model_path", ""))
	lifetime_remaining = maxf(0.0, float(state.get("lifetime_remaining", LIFETIME_SECONDS)))
	_spawn_model()
	global_position = state.get("position", global_position) as Vector3 if state.get("position", null) is Vector3 else global_position
	var velocity_value: Variant = state.get("velocity", Vector3.ZERO)
	if velocity_value is Vector3:
		linear_velocity = velocity_value as Vector3
	var angular_value: Variant = state.get("angular_velocity", Vector3.ZERO)
	if angular_value is Vector3:
		angular_velocity = angular_value as Vector3
	if bool(state.get("landed", false)):
		_set_landed()


func apply_authoritative_state(state: Dictionary) -> void:
	lifetime_remaining = maxf(0.0, float(state.get("lifetime_remaining", lifetime_remaining)))
	if bool(state.get("landed", false)):
		var position_value: Variant = state.get("position", global_position)
		if position_value is Vector3:
			global_position = position_value as Vector3
		_set_landed()
	elif not landed:
		var position_value: Variant = state.get("position", null)
		if position_value is Vector3 and global_position.distance_squared_to(position_value as Vector3) > 1.0:
			global_position = position_value as Vector3


func get_pickup_state() -> Dictionary:
	return {
		"item_id": item_id,
		"item": item_data.duplicate(true),
		"model_path": model_path,
		"position": global_position,
		"velocity": linear_velocity,
		"angular_velocity": angular_velocity,
		"landed": landed,
		"lifetime_remaining": maxf(0.0, lifetime_remaining - _elapsed),
	}


func get_interaction_hint(_player: GamePlayer) -> String:
	return "[E] 捡起%s" % str(item_data.get("display_name", "物品"))


func interact(player: GamePlayer) -> bool:
	if not landed or not is_instance_valid(player):
		return false
	return player.request_pickup_item(self)


func _process(delta: float) -> void:
	_elapsed += delta
	if not GameAuthority.is_client_proxy() and _elapsed >= lifetime_remaining:
		despawn_requested.emit(item_id)
		set_process(false)
		return
	if not landed:
		return
	var offset := (sin(_elapsed * FLOAT_SPEED) + 1.0) * 0.5 * FLOAT_HEIGHT
	visual_root.position.y = offset
	visual_root.rotate_y(ROTATION_SPEED * delta)


func _physics_process(_delta: float) -> void:
	if not landed and (_elapsed >= 5.0 or sleeping):
		_set_landed()


func _on_body_entered(_body: Node) -> void:
	if not landed and _elapsed >= 0.08:
		_set_landed()


func _set_landed() -> void:
	if landed:
		return
	landed = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze = true
	rotation = Vector3(0.0, rotation.y, 0.0)
	collision_mask = 0
	glow_ring.visible = true
	pickup_label.visible = true


func _spawn_model() -> void:
	if is_instance_valid(_model):
		_model.queue_free()
		_model = null
	if model_path.is_empty():
		return
	var packed_scene := load(model_path) as PackedScene
	if packed_scene == null:
		push_warning("无法加载掉落物模型：" + model_path)
		return
	_model = packed_scene.instantiate() as Node3D
	if _model == null:
		return
	if fallback_visual != null:
		fallback_visual.visible = false
	_prepare_model_runtime(_model)
	model_pivot.add_child(_model)
	model_pivot.scale = Vector3.ONE * MODEL_SCALE
	_disable_model_runtime(_model)


func _prepare_model_runtime(node: Node) -> void:
	if node is VehicleBase:
		(node as VehicleBase).vehicle_deployed = false
	for child in node.get_children():
		_prepare_model_runtime(child)


func _disable_model_runtime(node: Node) -> void:
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node.is_in_group("vehicle_bases"):
		node.remove_from_group("vehicle_bases")
	if node is CollisionObject3D:
		var collision_object := node as CollisionObject3D
		collision_object.collision_layer = 0
		collision_object.collision_mask = 0
	for child in node.get_children():
		_disable_model_runtime(child)
