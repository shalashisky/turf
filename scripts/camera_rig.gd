class_name CameraRig
extends Node3D
## Fixed-angle follow camera. The child Camera3D sets the pitch and distance;
## this rig only follows the target. Its yaw drives camera-relative movement.
## It also feeds the see-through shader on buildings (occlusion_cutout.gdshader).

@export var target: Node3D
@export var follow_speed := 8.0
## Slower vertical follow so jumps don't bounce the whole screen.
@export var vertical_follow_speed := 3.0

@onready var _camera: Camera3D = $Camera3D


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
	var weight := 1.0 - exp(-follow_speed * delta)
	var vertical_weight := 1.0 - exp(-vertical_follow_speed * delta)
	global_position = Vector3(
		lerpf(global_position.x, goal.x, weight),
		lerpf(global_position.y, goal.y, vertical_weight),
		lerpf(global_position.z, goal.z, weight))

	RenderingServer.global_shader_parameter_set("player_position", goal)
	RenderingServer.global_shader_parameter_set("camera_position", _camera.global_position)
