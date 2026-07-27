extends Resource
class_name VehicleConfig

@export_group("Visual")
@export var visual_scene: PackedScene
@export var visual_offset := Vector3.ZERO
@export var visual_rotation := Vector3.ZERO
@export var open_cabin := false
@export var animate_steering_wheel := false
## Vehicle movement is expressed in the vehicle base's local space. Imported
## vehicle scenes in this project use +Z as their front.
@export var forward_axis := Vector3.FORWARD
@export var wheel_spin_axis := Vector3.RIGHT
@export var steering_wheel_axis := Vector3.FORWARD

@export_group("Seats")
@export var seats: Array[VehicleSeatConfig] = []

@export_group("Camera")
@export var camera_offset := Vector3(0.0, 3.2, 7.0)
@export var camera_base_fov := 72.0
@export var camera_max_fov := 86.0
@export var camera_speed_for_max_fov := 16.0
@export var camera_fov_response := 5.0
@export var camera_orbit_target_height := 1.2
@export_range(-360.0, 360.0, 1.0) var camera_orbit_yaw_degrees := 180.0
@export_range(-80.0, 80.0, 1.0) var camera_orbit_pitch_degrees := -12.0
@export_range(-89.0, 0.0, 1.0) var camera_orbit_min_pitch_degrees := -40.0
@export_range(0.0, 89.0, 1.0) var camera_orbit_max_pitch_degrees := 20.0

@export_group("Dimensions")
@export var collision_size := Vector3(1.8, 1.2, 3.6)
@export var collision_offset := Vector3(0.0, 0.65, 0.0)
@export var hitbox_size := Vector3(2.0, 1.5, 3.8)
@export var hitbox_offset := Vector3(0.0, 0.75, 0.0)
@export var wheel_radius := 0.42
@export var wheel_base := 2.4
@export var wheel_track := 1.5

@export_group("Driving")
@export var max_forward_speed := 16.0
@export var max_reverse_speed := 6.0
@export var acceleration := 8.0
@export var brake_deceleration := 16.0
@export var rolling_deceleration := 3.0
@export var max_steering_angle_degrees := 30.0
@export var min_steering_angle_degrees := 9.0
@export var steering_response := 5.0
## Maps input steering to the imported vehicle's visual/local turn direction.
@export var steering_turn_sign := -1.0
@export var ground_stick_speed := 2.0

@export_group("Two Wheel")
## Node names searched inside the two-wheel vehicle's visual scene.
@export var two_wheel_front_node_name := "Wheel_Front"
@export var two_wheel_rear_node_name := "Wheel_Rear"
## The physics body remains upright; only the visual leans into a turn.
@export_range(0.0, 45.0, 1.0, "degrees") var two_wheel_max_lean_degrees := 20.0
@export_range(0.1, 20.0, 0.1) var two_wheel_lean_response := 7.0
## Adjust per imported model if its local forward roll axis is reversed.
@export var two_wheel_lean_sign := -1.0

@export_group("Durability")
@export var max_hp := 300.0

@export_group("Cargo")
## Maximum cargo weight carried by this vehicle. Zero disables cargo support.
@export_range(0.0, 500.0, 1.0, "suffix:kg") var cargo_capacity_kg := 0.0
## Local-space front-centre of the lower cargo layer for open vehicles.
@export var cargo_placement_origin := Vector3.ZERO
## Visual scene path is used so vehicles remain valid before the crate scene exists.
@export_file("*.tscn") var cargo_crate_scene_path := "res://assets/saved_glbs/cargo_crates.tscn"
@export_range(1, 8, 1) var cargo_columns := 3
@export_range(1, 12, 1) var cargo_rows := 5
@export_range(1, 4, 1) var cargo_layers := 2
## Physical crate dimensions also define the spacing of the displayed stack.
@export var cargo_crate_size := Vector3.ONE
## Multiplier for cargo lost by the percentage of max HP received as damage.
## At 1.0, losing 10% max HP removes 10% of the vehicle's cargo capacity.
@export_range(0.0, 1.0, 0.01) var cargo_loss_per_hp_damage_ratio := 1.0
