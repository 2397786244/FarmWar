extends Resource
class_name VehicleSeatConfig

## A vehicle can expose any number of seats. The current vehicle definitions
## use one driver seat, but passenger seats use the same occupancy pipeline.
@export var seat_id := "driver"
## Leave empty to use DriverSeatPoint for index 0 or SeatPoint_{index} for passengers.
@export var anchor_name := ""
@export var can_drive := true
@export var show_occupant := true
@export var exit_offset := Vector3(1.8, 0.1, 0.0)
## Player models face local -Z while the vehicle visuals face local +Z.
@export var occupant_rotation_degrees := Vector3(0.0, 180.0, 0.0)
## Lower the character origin from the seat marker so the hips sit on it.
@export var occupant_offset := Vector3(0.0, -0.5, 0.0)
