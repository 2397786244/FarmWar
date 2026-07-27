extends CharacterBody3D

var is_absorbing:bool = false
var target_source:Vector3
const SPEED = 30.0
var start_distance:float
var accumulate_counter = 0
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _physics_process(delta: float) -> void:
	if is_absorbing:
		accumulate_counter += delta
		if accumulate_counter >= 0.5:
			queue_free()
			return
		var need_vec = (target_source - self.global_position)
		var dist = need_vec.length()
		if dist < 0.2:
			queue_free()
			return
		var normalized_vec = need_vec.normalized()	
		self.velocity = velocity.move_toward(normalized_vec * SPEED, delta * 50)
		#self.velocity.y -= 9.8 * delta
		var scale_ratio = clampf(dist / start_distance,0.2,1.0)
		self.scale = Vector3(scale_ratio,scale_ratio,scale_ratio)
		move_and_slide()
		return
		
		
func set_appearance(seed_name:String, harvested_positions: Array = []):
	var crop_layout := FarmTile.get_crop_layout(seed_name)
	if crop_layout.is_empty():
		return
	var packed_scene := load(FarmTile.get_harvest_drop_scene_path(seed_name)) as PackedScene
	if packed_scene == null:
		return
	var positions: Array = crop_layout.get("positions", [])
	if not harvested_positions.is_empty():
		positions = harvested_positions
	for crop_position_value: Variant in positions:
		if not crop_position_value is Vector3:
			continue
		var crop_position := crop_position_value as Vector3
		var crop := packed_scene.instantiate() as Node3D
		if crop == null:
			continue
		add_child(crop)
		crop.position = crop_position
	
func absorb(source:Vector3):
	is_absorbing = true
	target_source = source
	self.velocity = (source - self.global_position)
	start_distance = (source - self.global_position).length()
