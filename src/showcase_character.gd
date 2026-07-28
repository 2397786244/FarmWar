extends Node3D
class_name ShowcaseCharacter

const RIGHT_HAND_GRIP_OFFSET := Vector3(0.22, -0.25, 0.55)
const RIGHT_ELBOW_POLE_OFFSET := Vector3(0.62, 0.08, -0.18)

@onready var appearance_root: Node3D = $AppearanceRoot
@onready var floor_prop_root: Node3D = $FloorPropRoot

var idle_animation_player: AnimationPlayer
var hand_socket: BoneAttachment3D
var tool_pivot: Node3D
var held_prop: Node3D
var right_arm_ik: TwoBoneIK3D
var right_hand_target: Marker3D
var right_elbow_pole: Marker3D


func setup(profile: Dictionary) -> void:
	# Run after the imported AnimationPlayer so the final held-model correction
	# sees the current frame's wrist transform.
	process_priority = 100
	var held_in_hand := str(profile.get("prop_mode", "floor")) == "hand"
	var character_scene := load(str(profile.get("character", ""))) as PackedScene
	var prop_scene := load(str(profile.get("prop", ""))) as PackedScene
	if character_scene == null or prop_scene == null:
		push_error("Main menu showcase profile has an invalid scene path.")
		return

	var appearance := character_scene.instantiate() as Node3D
	appearance_root.add_child(appearance)
	var skeleton := appearance.find_child("Skeleton3D", true, false) as Skeleton3D
	if skeleton != null and held_in_hand:
		_create_hand_socket(skeleton)
		_setup_right_arm_ik(skeleton)
	elif skeleton == null:
		push_warning("Showcase character is missing Skeleton3D: %s" % profile.get("character", ""))

	idle_animation_player = appearance.find_child(
		"AnimationPlayer", true, false
	) as AnimationPlayer
	_play_idle()

	var prop := prop_scene.instantiate() as Node3D
	_disable_prop_gameplay(prop)
	if held_in_hand:
		if not is_instance_valid(tool_pivot):
			push_error(
				"Cannot attach showcase prop to Hand.R: %s"
				% profile.get("character", "")
			)
			prop.free()
			return
		tool_pivot.add_child(prop)
		held_prop = prop
	else:
		floor_prop_root.add_child(prop)
	prop.position = profile.get("prop_position", Vector3.ZERO) as Vector3
	prop.rotation_degrees = profile.get("prop_rotation", Vector3.ZERO) as Vector3
	prop.scale = profile.get("prop_scale", Vector3.ONE) as Vector3
	if held_in_hand:
		_schedule_prop_upright(prop)


func _create_hand_socket(skeleton: Skeleton3D) -> void:
	var hand_bone_index := skeleton.find_bone("Hand.R")
	if hand_bone_index < 0:
		push_warning("Showcase character skeleton is missing Hand.R.")
		return
	hand_socket = BoneAttachment3D.new()
	hand_socket.name = "RightHandSocket"
	skeleton.add_child(hand_socket)
	hand_socket.bone_idx = hand_bone_index
	hand_socket.bone_name = "Hand.R"
	hand_socket.override_pose = false
	hand_socket.transform = Transform3D.IDENTITY
	tool_pivot = Node3D.new()
	tool_pivot.name = "ToolPivot"
	hand_socket.add_child(tool_pivot)
	tool_pivot.transform = Transform3D.IDENTITY


func _setup_right_arm_ik(skeleton: Skeleton3D) -> void:
	var upper_arm_index := skeleton.find_bone("UpperArm.R")
	var forearm_index := skeleton.find_bone("Forearm.R")
	var hand_index := skeleton.find_bone("Hand.R")
	if upper_arm_index < 0 or forearm_index < 0 or hand_index < 0:
		push_warning("Showcase character is missing right-arm IK bones.")
		return

	var shoulder_world := skeleton.global_transform * skeleton.get_bone_global_pose(upper_arm_index)
	var hand_world := skeleton.global_transform * skeleton.get_bone_global_pose(hand_index)
	var side_direction := hand_world.origin - shoulder_world.origin
	side_direction.y = 0.0
	if side_direction.length_squared() < 0.001:
		side_direction = Vector3.LEFT
	else:
		side_direction = side_direction.normalized()
	# The imported showcase characters face +Z toward the studio camera.
	var presentation_forward := appearance_root.global_transform.basis.z.normalized()

	right_hand_target = Marker3D.new()
	right_hand_target.name = "RightHandIKTarget"
	add_child(right_hand_target)
	right_hand_target.global_position = shoulder_world.origin \
		+ side_direction * RIGHT_HAND_GRIP_OFFSET.x \
		+ Vector3.UP * RIGHT_HAND_GRIP_OFFSET.y \
		+ presentation_forward * RIGHT_HAND_GRIP_OFFSET.z

	right_elbow_pole = Marker3D.new()
	right_elbow_pole.name = "RightElbowPole"
	add_child(right_elbow_pole)
	right_elbow_pole.global_position = shoulder_world.origin \
		+ side_direction * RIGHT_ELBOW_POLE_OFFSET.x \
		+ Vector3.UP * RIGHT_ELBOW_POLE_OFFSET.y \
		+ presentation_forward * RIGHT_ELBOW_POLE_OFFSET.z

	right_arm_ik = TwoBoneIK3D.new()
	right_arm_ik.name = "ShowcaseRightArmIK"
	skeleton.add_child(right_arm_ik)
	right_arm_ik.setting_count = 1
	right_arm_ik.set_root_bone_name(0, "UpperArm.R")
	right_arm_ik.set_middle_bone_name(0, "Forearm.R")
	right_arm_ik.set_end_bone_name(0, "Hand.R")
	right_arm_ik.set_use_virtual_end(0, false)
	right_arm_ik.set_extend_end_bone(0, false)
	right_arm_ik.set_pole_direction(
		0,
		SkeletonModifier3D.SECONDARY_DIRECTION_PLUS_X
	)
	right_arm_ik.set_target_node(0, right_arm_ik.get_path_to(right_hand_target))
	right_arm_ik.set_pole_node(0, right_arm_ik.get_path_to(right_elbow_pole))
	right_arm_ik.active = true
	right_arm_ik.influence = 1.0


func _process(_delta: float) -> void:
	# Showcase appearances are presentation-only and remain in Idle indefinitely.
	if idle_animation_player != null and not idle_animation_player.is_playing():
		_play_idle()
	# Idle continuously changes Hand.R. Reapply the same global-up correction
	# used by Player after the skeleton animation and right-arm IK have updated.
	if is_instance_valid(held_prop):
		_upright_prop(held_prop)


func _play_idle() -> void:
	if idle_animation_player != null and idle_animation_player.has_animation(&"Idle"):
		idle_animation_player.play(&"Idle")


func _schedule_prop_upright(prop: Node3D) -> void:
	_upright_prop(prop)
	call_deferred("_upright_prop", prop)


func _upright_prop(prop: Node3D) -> void:
	if not is_instance_valid(prop) or not prop.is_inside_tree():
		return
	var world_basis := prop.global_transform.basis.orthonormalized()
	var model_world_up := world_basis.y.normalized()
	var mesh := _find_first_mesh_instance(prop)
	if mesh != null:
		model_world_up = mesh.global_transform.basis.y.normalized()
	if model_world_up.length_squared() < 0.001 \
			or model_world_up.is_equal_approx(Vector3.UP):
		return
	var correction := Quaternion(model_world_up, Vector3.UP)
	if absf(correction.w) > 0.99999:
		return
	var corrected_world_basis := Basis(correction) * world_basis
	var parent := prop.get_parent() as Node3D
	var parent_basis := parent.global_transform.basis.orthonormalized() \
			if parent != null else Basis.IDENTITY
	prop.rotation = (parent_basis.inverse() * corrected_world_basis).get_euler()


func _find_first_mesh_instance(node: Node) -> MeshInstance3D:
	for child in node.get_children():
		if child is MeshInstance3D:
			return child as MeshInstance3D
		var nested := _find_first_mesh_instance(child)
		if nested != null:
			return nested
	return null


func _disable_prop_gameplay(node: Node) -> void:
	if node.get_script() != null:
		node.set_script(null)
	node.process_mode = Node.PROCESS_MODE_DISABLED
	if node is CollisionObject3D:
		(node as CollisionObject3D).collision_layer = 0
		(node as CollisionObject3D).collision_mask = 0
	if node is CollisionShape3D:
		(node as CollisionShape3D).disabled = true
	elif node is CollisionPolygon3D:
		(node as CollisionPolygon3D).disabled = true
	elif node is GPUParticles3D:
		(node as GPUParticles3D).emitting = false
	elif node is Camera3D:
		(node as Camera3D).current = false
	elif node is Label3D:
		(node as Label3D).visible = false
	for child in node.get_children():
		_disable_prop_gameplay(child)
