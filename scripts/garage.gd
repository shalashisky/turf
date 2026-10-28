class_name Garage
extends Node3D
## The player's lock-up garage. Its roll-up door opens when the player walks
## up to it, or drives up to the doorway, and closes once they've gone. Parking the car inside fixes it up good
## as new, and it's where the car turns up again the morning after it's been
## wrecked (PlayerCar). Marked "G" on the minimap.
##
## The node sits in the middle of the doorway, on the building line, and the
## garage runs back from there along -Z. It's built in code, from the
## see-through building shader, so the player can still be seen inside.

const CUTOUT_SHADER := preload("res://shaders/occlusion_cutout.gdshader")
const WALL := 0.2
const DOOR_HEIGHT := 2.4
## How long the door takes to roll up or down.
const DOOR_TIME := 0.6

@export var width := 4.0
@export var depth := 6.0
@export var height := 3.0
@export var wall_color := Color(0.4, 0.4, 0.43)
@export var door_color := Color(0.62, 0.6, 0.52)
## The door opens for the player on foot this close to the doorway...
@export var open_distance := 3.5
## ...or driving up to it from in front, this far out.
@export var drive_up_distance := 6.0

var _body: StaticBody3D
var _door: MeshInstance3D
var _door_shape: CollisionShape3D
var _bay: Area3D
var _open := false
var _tween: Tween


func _ready() -> void:
	add_to_group("garages")
	_body = StaticBody3D.new()
	add_child(_body)
	var walls := _cutout_material(wall_color)
	var side := (width - WALL) * 0.5
	_add_box(Vector3(WALL, height, depth), Vector3(-side, height * 0.5, -depth * 0.5), walls)
	_add_box(Vector3(WALL, height, depth), Vector3(side, height * 0.5, -depth * 0.5), walls)
	_add_box(Vector3(width, height, WALL), Vector3(0.0, height * 0.5, -depth + WALL * 0.5), walls)
	_add_box(Vector3(width, WALL, depth), Vector3(0.0, height + WALL * 0.5, -depth * 0.5), walls)
	# Over the doorway.
	_add_box(Vector3(width, height - DOOR_HEIGHT, WALL), Vector3(0.0, (height + DOOR_HEIGHT) * 0.5, -WALL * 0.5), walls)
	var door_size := Vector3(width - WALL * 2.0, DOOR_HEIGHT, 0.08)
	_door_shape = _add_box(door_size, Vector3(0.0, DOOR_HEIGHT * 0.5, -WALL * 0.5), _cutout_material(door_color))
	_door = _door_shape.get_meta("mesh")

	var light := OmniLight3D.new()
	light.position = Vector3(0.0, height - 0.4, -depth * 0.5)
	light.light_color = Color(1.0, 0.9, 0.7)
	light.light_energy = 0.8
	light.omni_range = 5.0
	add_child(light)

	_bay = Area3D.new()
	_bay.collision_layer = 0
	_bay.collision_mask = 1
	var bay_shape := CollisionShape3D.new()
	var bay_box := BoxShape3D.new()
	bay_box.size = Vector3(width - WALL * 2.0, 2.0, depth - 1.0)
	bay_shape.shape = bay_box
	bay_shape.position = Vector3(0.0, 1.0, -depth * 0.5)
	_bay.add_child(bay_shape)
	add_child(_bay)

	var blip := MapBlip.new()
	blip.label = "G"
	blip.color = Color(0.95, 0.6, 0.25)
	add_child(blip)


func _process(_delta: float) -> void:
	var near := _player_coming()
	if near != _open:
		_set_open(near)
	_fix_parked_car()


func _player_coming() -> bool:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null:
		return false
	if player.vehicle == null:
		return player.global_position.distance_to(global_position) < open_distance
	# In a car: only when it's lined up in front of the doorway, or inside.
	var from_door := to_local(player.global_position)
	return absf(from_door.x) < width and from_door.z < drive_up_distance and from_door.z > -depth


## Whether `car` is parked inside.
func holds(car: Node3D) -> bool:
	return _bay.overlaps_body(car)


## Where the car sits inside, facing out of the door.
func parking_transform() -> Transform3D:
	return global_transform * Transform3D(Basis(Vector3.UP, PI), Vector3(0.0, 0.0, -depth * 0.5 - 0.2))


func _fix_parked_car() -> void:
	for body in _bay.get_overlapping_bodies():
		var car := body as PlayerCar
		if car and not car.is_wrecked and absf(car.speed) < 0.5 and car.health < car.max_health:
			car.repair()
			Transition.show_message("Car repaired")


func _set_open(open: bool) -> void:
	_open = open
	if _tween:
		_tween.kill()
	# Rolls up into a thin bundle under the lintel.
	_tween = create_tween().set_parallel()
	_tween.tween_property(_door, "scale:y", 0.05 if open else 1.0, DOOR_TIME)
	_tween.tween_property(_door, "position:y", DOOR_HEIGHT - 0.06 if open else DOOR_HEIGHT * 0.5, DOOR_TIME)
	_door_shape.set_deferred("disabled", open)


## A solid box, drawn and collided with. Returns its collision shape, with
## the mesh under the "mesh" meta.
func _add_box(size: Vector3, at: Vector3, material: Material) -> CollisionShape3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	box.material = material
	mesh.mesh = box
	mesh.position = at
	add_child(mesh)
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	shape.position = at
	shape.set_meta("mesh", mesh)
	_body.add_child(shape)
	return shape


func _cutout_material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = CUTOUT_SHADER
	material.set_shader_parameter("albedo", color)
	return material
