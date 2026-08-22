extends Resource
class_name VehicleSeatConfig

## All current player models use the same local facing convention and the
## same root-to-hip correction when they are shown in a vehicle seat. Keep
## these values in one place so a driver seat resource cannot silently drift
## away from the shared player presentation path.
const DEFAULT_OCCUPANT_ROTATION_DEGREES := Vector3(0.0, 180.0, 0.0)
const DEFAULT_OCCUPANT_OFFSET := Vector3(0.0, -0.5, 0.0)
const DEFAULT_SEATED_POSITION_OFFSET := Vector3(0.0, -0.4, 0.0)

## A vehicle can expose any number of seats. The current vehicle definitions
## use one driver seat, but passenger seats use the same occupancy pipeline.
@export var seat_id := "driver"
## Leave empty to use DriverSeatPoint for index 0 or SeatPoint_{index} for passengers.
@export var anchor_name := ""
@export var can_drive := true
@export var show_occupant := true
@export var exit_offset := Vector3(1.8, 0.1, 0.0)
## Player models face local -Z while the vehicle visuals face local +Z.
@export var occupant_rotation_degrees := DEFAULT_OCCUPANT_ROTATION_DEGREES
## DriverSeatPoint/ProspectorSeat marks the seat contact height. Lower the
## player root from that marker so the visible character's hips/butt rest on
## the seat instead of placing the character root at the cushion marker.
@export var occupant_offset := DEFAULT_OCCUPANT_OFFSET
## Additional universal lowering applied after the seat-specific root-to-hip
## correction. Keep this separate so driver and dynamically-created passenger
## seats share the same seated surface adjustment.
@export var seated_position_offset := DEFAULT_SEATED_POSITION_OFFSET
