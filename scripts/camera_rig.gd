class_name CameraRig
extends Node3D
## Fixed-angle follow camera. The child Camera3D sets the pitch and distance;
## this rig only follows the target. Its yaw drives camera-relative movement.
## While the target drives a car, the camera pulls back and looks ahead of it.
## It also feeds the see-through shader on buildings (occlusion_cutout.gdshader).

@export var target: Node3D
@export var follow_speed := 8.0
## Slower vertical follow so jumps don't bounce the whole screen.
@export var vertical_follow_speed := 3.0
@export_group("Driving")
## How much farther back the camera sits at the car's top speed.
@export var driving_zoom := 1.6
## Looks this many seconds ahead of the car.
@export var driving_lead_time := 0.5
@export var zoom_speed := 1.5

var _zoom := 1.0

@onready var _camera: Camera3D = $Camera3D
@onready var _camera_offset := _camera.position


func _ready() -> void:
	snap_to_target()


## Jump straight to the target, for teleports and scene changes.
func snap_to_target() -> void:
	if target:
		global_position = target.global_position


func _process(delta: float) -> void:
	if target == null:
		return
	var goal := target.get_global_transform_interpolated().origin
	# Pull back with speed while driving, and look ahead down the road.
	var vehicle := target.get("vehicle") as Vehicle
	var wanted_zoom := 1.0
	if vehicle:
		var top_speed: float = vehicle.get("max_speed") if vehicle.get("max_speed") else 16.0
		wanted_zoom = lerpf(1.25, driving_zoom, clampf(absf(vehicle.speed) / top_speed, 0.0, 1.0))
		var ahead := vehicle.heading * vehicle.speed * driving_lead_time
		RenderingServer.global_shader_parameter_set("player_position", goal)
		goal += ahead
	_zoom = lerpf(_zoom, wanted_zoom, 1.0 - exp(-zoom_speed * delta))
	_camera.position = _camera_offset * _zoom
	var weight := 1.0 - exp(-follow_speed * delta)
	var vertical_weight := 1.0 - exp(-vertical_follow_speed * delta)
	global_position = Vector3(
		lerpf(global_position.x, goal.x, weight),
		lerpf(global_position.y, goal.y, vertical_weight),
		lerpf(global_position.z, goal.z, weight))

	if vehicle == null:
		RenderingServer.global_shader_parameter_set("player_position", goal)
	RenderingServer.global_shader_parameter_set("camera_position", _camera.global_position)
