extends Node3D

## 手动观察 Zombie 感知、导航、受击反击与近战的独立场景。
## 不接入正式地图、地图编辑器或存档。

const WARRIOR_SCENE := preload("res://character/FutureWarriorAI.tscn")
const ZOMBIE_SCENE := preload("res://character/Zombie.tscn")

var _authority_started := false


func _ready() -> void:
	GlobalVar.gameworld = self
	GameAuthority.start_local_mode({
		"display_name": "ZombieObserver",
		"team": "blue",
		"position": Vector3(0.0, 0.0, 0.0),
		"yaw": 0.0,
		"hp": 200.0,
		"current_tool_id": "torch",
	})
	_authority_started = true
	_build_environment()
	_build_ground()
	_build_navigation()
	_spawn_combatants()
	_build_camera()
	_build_hud()


func _exit_tree() -> void:
	if _authority_started and GameAuthority.is_local_authority():
		GameAuthority.stop_authority()
	if GlobalVar.gameworld == self:
		GlobalVar.gameworld = null


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("#1d242c")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b8c7d9")
	environment.ambient_light_energy = 0.85
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, -25.0, 0.0)
	light.light_energy = 1.2
	light.shadow_enabled = true
	add_child(light)


func _build_ground() -> void:
	var visual := MeshInstance3D.new()
	visual.name = "NavigationGround"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(64.0, 0.1, 64.0)
	visual.mesh = mesh
	visual.position.y = -0.05
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#3e5740")
	material.roughness = 0.95
	visual.material_override = material
	visual.add_to_group("navigation_ground")
	add_child(visual)
	var body := StaticBody3D.new()
	body.collision_layer = GameAuthority.COLLISION_LAYER_GROUND
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(64.0, 0.1, 64.0)
	collision.shape = shape
	collision.position.y = -0.05
	body.add_child(collision)
	add_child(body)


func _build_navigation() -> void:
	var grid := DynamicNavigationChunkGrid.new()
	grid.name = "ZombieObserverNavigation"
	grid.map_origin = Vector2(-32.0, -32.0)
	grid.map_size = Vector2(64.0, 64.0)
	grid.chunk_size = 64.0
	grid.fallback_ground_y = 0.0
	add_child(grid)


func _spawn_combatants() -> void:
	var zombie := ZOMBIE_SCENE.instantiate() as Zombie
	zombie.name = "ObserverZombie"
	zombie.zombie_id = "observer_zombie"
	zombie.position = Vector3(0.0, 0.0, 4.0)
	zombie.rotation.y = PI
	add_child(zombie)

	var warrior := WARRIOR_SCENE.instantiate() as FutureWarriorAI
	warrior.name = "ObserverFutureWarrior"
	warrior.team_id = "blue"
	warrior.server_authoritative = true
	warrior.print_decisions = false
	warrior.starting_grenade_count = 0
	warrior.position = Vector3(0.0, 0.0, -8.0)
	add_child(warrior)


func _build_camera() -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(16.0, 13.0, 20.0)
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.8, 0.0), Vector3.UP)
	camera.current = true


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(20.0, 18.0)
	label.size = Vector2(680.0, 96.0)
	label.text = "Zombie 导航观察场景\nFutureWarriorAI 与 Zombie 已生成。可观察枪击后的反击、寻路、近战、跳跃与死亡动画。"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color.WHITE)
	layer.add_child(label)
