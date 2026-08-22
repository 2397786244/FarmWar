extends Node3D
class_name MuzzleFlashVisual

## Presentation-only muzzle flash.  The existing GPUParticles3D remains the
## primary particle effect; this node adds a short low-poly flame and light.

const DEFAULT_FIREPOWER := 30.0
const POWER_MIN := 20.0
const POWER_MAX := 100.0
const VISIBILITY_BOOST := 1.30
const FLAME_EMISSION_ENERGY := 24.0
const CORE_EMISSION_ENERGY := 50.0
# Keep the glow power responsive to projectile power, but cap the actual
# material multiplier at 50x while preserving projectile-power scaling.
const GLOW_EMISSION_BASE_ENERGY := 24.0
const GLOW_EMISSION_MAX_ENERGY := 50.0
const FLAME_CENTER_FORWARD_OFFSET := -0.35
const CORE_CENTER_FORWARD_OFFSET := -0.17
const CORE_TINT_STRENGTH := 0.18

@export var particle_path: NodePath = NodePath("../MuzzleFlash")
@export var flash_color := Color(1.0, 0.55, 0.08, 1.0)
@export_range(0.1, 3.0, 0.05) var flash_scale := 1.0
@export_range(0.03, 0.22, 0.005) var flash_duration := 0.13
@export_range(0.0, 60.0, 0.1) var flash_light_energy := 8.0
@export_range(0.1, 16.0, 0.1) var flash_light_range := 4.0

var _particles: GPUParticles3D
var _flame: MeshInstance3D
var _core: MeshInstance3D
var _flash_light: OmniLight3D
var _flame_material: StandardMaterial3D
var _core_material: StandardMaterial3D
var _glow_material: StandardMaterial3D
var _muzzle_particle_color := Color(1.0, 0.55, 0.08, 1.0)
var _tween: Tween


func _ready() -> void:
	_particles = get_node_or_null(particle_path) as GPUParticles3D
	if _particles != null:
		# Keep the authored particle resource available for color sampling and
		# future tuning, but never render the legacy particle burst itself.
		_particles.visible = false
		_particles.emitting = false
	_refresh_particle_glow_color()
	_build_visuals()
	_hide_flash()


func play(firepower: float = DEFAULT_FIREPOWER) -> void:
	if not is_inside_tree():
		return
	_sync_to_muzzle()
	_refresh_particle_glow_color()
	_build_visuals()
	_sync_to_muzzle()
	if _particles != null:
		# Keep the authored particle node and material available for compatibility
		# and color sampling, but do not restart its simulation. The shared flame,
		# core and light are now the complete firing presentation.
		_particles.visible = false
		_particles.emitting = false
	if _flame == null or _core == null or _flash_light == null:
		return
	if _tween != null:
		_tween.kill()
	var power_profile := _get_power_profile(firepower)
	var world_scale_compensation := _get_world_scale_compensation()
	var visual_scale := flash_scale \
		* VISIBILITY_BOOST \
		* float(power_profile.get("scale", 1.0)) \
		* world_scale_compensation
	var effective_duration := clampf(
		flash_duration * float(power_profile.get("duration", 1.0)),
		0.08,
		0.22
	)
	_flame.visible = true
	_core.visible = true
	_flash_light.visible = true
	_flame.position = Vector3(
		0.0,
		0.0,
		FLAME_CENTER_FORWARD_OFFSET * world_scale_compensation
	)
	_core.position = Vector3(
		0.0,
		0.0,
		CORE_CENTER_FORWARD_OFFSET * world_scale_compensation
	)
	# Keep the light exactly on the authored muzzle marker. The flame extends
	# forward, but the illumination anchor must never appear detached from the
	# weapon or read as a light coming from the player's feet.
	_flash_light.position = Vector3.ZERO
	_flame.transparency = 0.0
	_core.transparency = 0.0
	_flame.scale = Vector3.ONE * (visual_scale * 0.66)
	_core.scale = Vector3.ONE * (visual_scale * 0.82)
	_apply_material_brightness(float(power_profile.get("emission", 1.0)))
	_flash_light.light_color = flash_color
	_flash_light.light_energy = flash_light_energy \
		* float(power_profile.get("energy", 1.0)) \
		* (0.9 + flash_scale * 0.1)
	_flash_light.omni_range = flash_light_range \
		* float(power_profile.get("range", 1.0)) \
		* (0.9 + flash_scale * 0.1)
	# The visual children are created at runtime. Flush their inherited world
	# transform before enabling them so the first rendered frame cannot use the
	# weapon's old/root transform.
	_flame.force_update_transform()
	_core.force_update_transform()
	_flash_light.force_update_transform()

	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(
		_flame,
		"scale",
		Vector3.ONE * visual_scale,
		effective_duration * 0.35
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(
		_core,
		"scale",
		Vector3.ONE * (visual_scale * 0.9),
		effective_duration * 0.2
	).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(_flame, "transparency", 1.0, effective_duration)
	_tween.tween_property(_core, "transparency", 1.0, effective_duration * 0.8)
	_tween.tween_property(_flash_light, "light_energy", 0.0, effective_duration)
	_tween.chain().tween_callback(_hide_flash)


func _build_visuals() -> void:
	if (
		_flame != null
		and _core != null
		and _flash_light != null
		and _glow_material != null
	):
		return

	_flame_material = _make_emissive_material(
		flash_color,
		0.96,
		FLAME_EMISSION_ENERGY
	)
	var flame_mesh := CylinderMesh.new()
	# CylinderMesh uses different top and bottom radii to form the original
	# low-poly truncated cone. Its local +Y axis is rotated to the weapon's -Z
	# firing axis below.
	flame_mesh.top_radius = 0.012
	flame_mesh.bottom_radius = 0.22
	flame_mesh.height = 0.64
	flame_mesh.radial_segments = 6
	_flame = MeshInstance3D.new()
	_flame.name = "FlashFlame"
	_flame.mesh = flame_mesh
	_flame.material_override = _flame_material
	_flame.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_flame.position = Vector3(0.0, 0.0, FLAME_CENTER_FORWARD_OFFSET)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.ignore_occlusion_culling = false
	add_child(_flame)

	var core_color := _get_core_color()
	_core_material = _make_emissive_material(core_color, 1.0, CORE_EMISSION_ENERGY)
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.04
	core_mesh.height = 0.08
	_core = MeshInstance3D.new()
	_core.name = "FlashCore"
	_core.mesh = core_mesh
	_core.material_override = _core_material
	_core.position = Vector3(0.0, 0.0, CORE_CENTER_FORWARD_OFFSET)
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_core.ignore_occlusion_culling = false
	add_child(_core)

	# The particle draw material is the source of truth for the glow color. The
	# Apply the particle-colored high-energy pass only to the conical flame. The
	# FlashCore keeps its separate near-white core material.
	_glow_material = _make_emissive_material(
		_muzzle_particle_color,
		0.72,
		GLOW_EMISSION_BASE_ENERGY
	)
	_glow_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_glow_material.render_priority = 101
	_flame.material_overlay = _glow_material

	_flash_light = OmniLight3D.new()
	_flash_light.name = "FlashLight"
	_flash_light.light_color = flash_color
	_flash_light.shadow_enabled = false
	_flash_light.omni_range = flash_light_range
	_flash_light.position = Vector3.ZERO
	add_child(_flash_light)


func _sync_to_muzzle() -> void:
	# Flush the complete weapon/pivot chain. This is important when the fire
	# input arrives in the same frame as a weapon swap, camera turn, or remote
	# snapshot; otherwise the newly created light can render at the old root.
	var chain: Array[Node3D] = []
	var current: Node = self
	while current is Node3D:
		chain.push_front(current as Node3D)
		current = current.get_parent()
	for node: Node3D in chain:
		node.force_update_transform()
	var muzzle := get_parent() as Node3D
	if muzzle != null:
		# MuzzleFlashVisual has no authored offset; make that invariant explicit
		# so a stale local transform can never move the flash to the actor root.
		global_transform = muzzle.global_transform


func _get_world_scale_compensation() -> float:
	var basis := global_transform.basis
	var inherited_scale := maxf(
		basis.x.length(),
		maxf(basis.y.length(), basis.z.length())
	)
	if inherited_scale <= 0.001:
		return 1.0
	return clampf(1.0 / inherited_scale, 0.5, 4.0)


func _get_power_profile(firepower: float) -> Dictionary:
	var safe_firepower := maxf(firepower, DEFAULT_FIREPOWER)
	var power_t := clampf(
		(safe_firepower - POWER_MIN) / (POWER_MAX - POWER_MIN),
		0.0,
		1.0
	)
	return {
		# Stronger rounds produce a larger flame, but never scale linearly enough
		# to cover the first-person view.
		"scale": lerpf(1.02, 1.68, power_t),
		# The light keeps a stronger power response for a short firing cue while
		# using the authored 8.0 base energy as its starting point.
		"energy": lerpf(1.30, 3.20, power_t),
		"range": lerpf(1.05, 1.65, power_t),
		"duration": lerpf(0.95, 1.18, power_t),
		"emission": lerpf(1.15, 2.10, power_t),
	}


func _apply_material_brightness(emission_multiplier: float) -> void:
	if _flame_material != null:
		_flame_material.albedo_color = Color(
			flash_color.r,
			flash_color.g,
			flash_color.b,
			0.92
		)
		_flame_material.emission = flash_color
		_flame_material.emission_energy_multiplier = (
			FLAME_EMISSION_ENERGY * emission_multiplier
		)
	if _core_material != null:
		var core_color := _get_core_color()
		_core_material.albedo_color = Color(
			core_color.r,
			core_color.g,
			core_color.b,
			1.0
		)
		_core_material.emission = core_color
		_core_material.emission_energy_multiplier = (
			CORE_EMISSION_ENERGY * emission_multiplier
		)
	if _glow_material != null:
		_glow_material.albedo_color = Color(
			_muzzle_particle_color.r,
			_muzzle_particle_color.g,
			_muzzle_particle_color.b,
			0.72
		)
		_glow_material.emission = _muzzle_particle_color
		_glow_material.emission_energy_multiplier = minf(
			GLOW_EMISSION_MAX_ENERGY,
			GLOW_EMISSION_BASE_ENERGY * emission_multiplier
		)


func _get_core_color() -> Color:
	# The hottest part of a muzzle flash reads as near-white. Keep a small
	# amount of the weapon tint so ordinary firearms stay warm-white while
	# FlameGun and FreezeGun remain subtly red-white and blue-white.
	return Color(
		lerpf(1.0, flash_color.r, CORE_TINT_STRENGTH),
		lerpf(1.0, flash_color.g, CORE_TINT_STRENGTH),
		lerpf(1.0, flash_color.b, CORE_TINT_STRENGTH),
		1.0
	)


func _refresh_particle_glow_color() -> void:
	var detected_color := _read_muzzle_particle_color()
	if detected_color.a <= 0.001:
		detected_color = flash_color
	_muzzle_particle_color = Color(
		clampf(detected_color.r, 0.0, 1.0),
		clampf(detected_color.g, 0.0, 1.0),
		clampf(detected_color.b, 0.0, 1.0),
		1.0
	)
	if _glow_material != null:
		_glow_material.albedo_color = Color(
			_muzzle_particle_color.r,
			_muzzle_particle_color.g,
			_muzzle_particle_color.b,
			0.72
		)
		_glow_material.emission = _muzzle_particle_color


func _read_muzzle_particle_color() -> Color:
	if _particles == null:
		return flash_color

	var particle_color := Color.WHITE
	var process_material := _particles.process_material as ParticleProcessMaterial
	if process_material != null:
		particle_color = process_material.color

	var particle_mesh := _particles.draw_pass_1 as PrimitiveMesh
	if particle_mesh != null:
		var particle_material := particle_mesh.material as BaseMaterial3D
		if particle_material != null:
			var material_color := particle_material.albedo_color
			particle_color = Color(
				material_color.r * particle_color.r,
				material_color.g * particle_color.g,
				material_color.b * particle_color.b,
				material_color.a * particle_color.a
			)

	return particle_color


func _make_emissive_material(color: Color, alpha: float, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# The muzzle flash must be occluded by the weapon and nearby geometry.
	material.no_depth_test = false
	material.render_priority = 100
	material.albedo_color = Color(color.r, color.g, color.b, alpha)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


func _hide_flash() -> void:
	if _flame != null:
		_flame.visible = false
		_flame.transparency = 1.0
	if _core != null:
		_core.visible = false
		_core.transparency = 1.0
	if _flash_light != null:
		_flash_light.visible = false
		_flash_light.light_energy = 0.0
