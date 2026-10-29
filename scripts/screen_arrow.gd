class_name ScreenArrow
extends Control
## A big arrow on screen pointing the way from the player to `target`, a spot
## in the world, as it'd look from the camera. Hidden while there's no target
## (Vector3.INF). Pulses a little, to catch the eye.

@export var color := Color(1.0, 0.35, 0.25)
@export var length := 34.0

var target := Vector3.INF


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(length * 2.0, length * 2.0)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var camera := get_viewport().get_camera_3d()
	if target == Vector3.INF or player == null or camera == null:
		return
	var away := target - player.global_position
	# Across and down the screen, from the camera's point of view.
	var across := Vector3(camera.global_basis.x.x, 0.0, camera.global_basis.x.z).normalized()
	var down := Vector3(camera.global_basis.z.x, 0.0, camera.global_basis.z.z).normalized()
	var pointing := Vector2(away.dot(across), away.dot(down))
	if pointing.length() < 0.01:
		return
	pointing = pointing.normalized()
	var side := Vector2(-pointing.y, pointing.x)
	var middle := size * 0.5
	var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() / 120.0)
	var tip := middle + pointing * length * 0.9 * pulse
	var back := middle - pointing * length * 0.5
	var arrow := PackedVector2Array([
		tip, back + side * length * 0.55, middle - pointing * length * 0.15, back - side * length * 0.55,
	])
	draw_colored_polygon(arrow, color)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 3.0)
