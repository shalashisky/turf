class_name DirectionalSprite
extends Sprite3D
## Picks frames from an 8-direction sheet. Rows are facings, clockwise from
## "facing the camera": s, se, e, ne, n, nw, w, sw. Column 0 is the idle pose
## and columns 1..walk_frames are the walk cycle.

const DIRECTION_COUNT := 8

@export var walk_frames := 3
@export var walk_fps := 8.0
## Column shown while in the air. The mid-stride pose doubles as a jump pose.
@export var airborne_column := 2

var _walk_time := 0.0


func show_facing(facing: Vector3, moving: bool, airborne: bool, delta: float) -> void:
	# Facing as seen by the camera, so the sprite stays right if it ever rotates.
	var camera := get_viewport().get_camera_3d()
	var camera_yaw := camera.global_rotation.y if camera else 0.0
	var local := facing.rotated(Vector3.UP, -camera_yaw)
	var slice := TAU / DIRECTION_COUNT
	var row := wrapi(roundi(atan2(local.x, local.z) / slice), 0, DIRECTION_COUNT)

	var column := 0
	if airborne:
		column = airborne_column
	elif moving:
		_walk_time += delta
		column = 1 + int(_walk_time * walk_fps) % walk_frames
	else:
		_walk_time = 0.0
	frame = row * hframes + column
