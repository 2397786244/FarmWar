extends SceneTree

const DEFAULT_SCENE := "res://worlds/creston_town/creston_town.tscn"


func _initialize() -> void:
	call_deferred("_bake")


func _bake() -> void:
	var scene_path := DEFAULT_SCENE
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scene="):
			scene_path = argument.trim_prefix("--scene=")
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_error("Grass bake: could not load %s." % scene_path)
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var scatter := scene.find_child("GrassScatter", true, false) as GrassScatter3D
	if scatter == null:
		push_error("Grass bake: %s has no GrassScatter3D node named GrassScatter." % scene_path)
		quit(1)
		return
	scatter.bake_grass()
	quit()
