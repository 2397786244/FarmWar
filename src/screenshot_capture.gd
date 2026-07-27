extends Node3D
@onready var viewport: SubViewport = $SubViewport
@onready var camera: Camera3D = $SubViewport/CaptureCamera3D
@export var working:bool = false
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	#print(OS.get_data_dir())
	viewport.world_3d = get_viewport().world_3d
	camera.current = true

# 每5秒截一个图？
var counter = 0
var frame_idx:int = 0
# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if not working:return
	counter += delta
	if counter >= 10:
		counter = 0
		await RenderingServer.frame_post_draw
		var image = viewport.get_texture().get_image()
		image.save_png("user://promo_capture_{0}.png".format([frame_idx]))
		frame_idx += 1
		print("SAVE!!")
