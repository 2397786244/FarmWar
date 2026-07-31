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
		push_error("Terrain bake: could not load %s." % scene_path)
		quit(1)
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	var baker := scene.find_child("TerrainSurfaceBaker", true, false) as TerrainSurfaceBaker
	if baker == null:
		push_error("Terrain bake: %s has no TerrainSurfaceBaker node." % scene_path)
		quit(1)
		return
	baker.bake_surface_mask()
	quit()
