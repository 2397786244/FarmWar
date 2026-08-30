extends MeshInstance3D
class_name BulletTracerSegment


@export_category("Tracer Visual")
@export var tracer_color := Color("#FFD06A")
@export_range(0.005, 0.20, 0.005) var radius: float = 0.035
@export_range(0.10, 10.0, 0.10) var minimum_length: float = 0.35
@export_range(0.10, 20.0, 0.10) var maximum_length: float = 3.5
@export_range(1.0, 10.0, 0.1) var length_multiplier: float = 1.25
@export_range(1.0, 30.0, 0.5) var emission_energy: float = 12.0
@export var tracing_enabled := true

var bullet_root: Node3D
var previous_position: Vector3 = Vector3.ZERO
var tracer_mesh: CylinderMesh


func _ready() -> void:
	bullet_root = get_parent() as Node3D

	if bullet_root == null:
		push_error(
			"[BulletTracerSegment] Parent must be a Node3D bullet."
		)
		queue_free()
		return

	# 脱离父节点坐标系，直接以世界坐标绘制。
	top_level = true

	previous_position = bullet_root.global_position

	tracer_mesh = CylinderMesh.new()
	tracer_mesh.top_radius = radius
	tracer_mesh.bottom_radius = radius * 0.65
	tracer_mesh.height = minimum_length
	tracer_mesh.radial_segments = 6
	tracer_mesh.rings = 1
	mesh = tracer_mesh

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.albedo_color = Color(
		tracer_color.r,
		tracer_color.g,
		tracer_color.b,
		0.82
	)

	material.emission_enabled = true
	material.emission = tracer_color
	material.emission_energy_multiplier = emission_energy

	# 保持被墙体、地面正常遮挡。
	material.no_depth_test = false

	# 子弹拖尾不需要接收阴影、雾或灯光影响。
	material.disable_receive_shadows = true
	material.disable_fog = true

	material_override = material
	visible = false


var frame_counter: int = 0


## Refreshes the tracer from the current parent position.
##
## Networked hitscan visuals are collision-free presentation nodes. Their root
## is moved manually by MultiplayerWorldReplicator, and some of those roots
## have their own physics processing disabled. Keeping the geometry update in a
## callable method makes the tail independent of the root's process state and
## also lets the replicator refresh it immediately after moving the visual.
func refresh_visual() -> void:
	_refresh_from_parent()


## Arms a tracer after its projectile has been placed at the throw/fire origin.
##
## Projectile visuals are often process-disabled on remote clients, so the
## caller must explicitly prime the trace instead of relying on the first
## physics callback to establish a previous position. The segment remains
## hidden until the projectile has actually moved, avoiding a stray line at
## the spawn point.
func start_tracing() -> void:
	if not is_instance_valid(bullet_root):
		bullet_root = get_parent() as Node3D
	if bullet_root == null:
		return
	tracing_enabled = true
	frame_counter = 2
	previous_position = bullet_root.global_position
	visible = false


## Stops a tracer when a projectile is still held or has come to rest.
func stop_tracing() -> void:
	tracing_enabled = false
	visible = false
	frame_counter = 0


func _physics_process(_delta: float) -> void:
	_refresh_from_parent()


func _refresh_from_parent() -> void:
	if not tracing_enabled:
		visible = false
		return
	if not is_instance_valid(bullet_root):
		queue_free()
		return

	if frame_counter <= 1:
		frame_counter += 1
		previous_position = bullet_root.global_position
		return

	var current_position := bullet_root.global_position
	var movement := current_position - previous_position
	var movement_length := movement.length()

	if movement_length <= 0.001:
		# Do not hide a freshly refreshed segment when the parent was moved by
		# the authority visual loop just before this node's own physics tick.
		# The segment will be replaced on the next movement or freed with the
		# transient projectile.
		previous_position = current_position
		return

	visible = true

	var direction := movement / movement_length

	var tracer_length := clampf(
		movement_length * length_multiplier,
		minimum_length,
		maximum_length
	)

	# 光条尾部略落后于子弹，头部落在当前子弹位置。
	var end_position := current_position
	var start_position := (
		current_position
		- direction * tracer_length
	)

	global_position = (start_position + end_position) * 0.5
	global_basis = _make_basis_y_point_to(direction)

	tracer_mesh.height = tracer_length
	previous_position = current_position


func _make_basis_y_point_to(direction: Vector3) -> Basis:
	var y_axis := direction.normalized()

	var reference_axis := Vector3.FORWARD
	if absf(y_axis.dot(reference_axis)) > 0.98:
		reference_axis = Vector3.RIGHT

	var x_axis := reference_axis.cross(y_axis).normalized()
	var z_axis := x_axis.cross(y_axis).normalized()

	return Basis(x_axis, y_axis, z_axis)
