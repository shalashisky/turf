class_name ThrownMolotov
extends Node3D
## A Molotov in flight. Arcs from the thrower's hand to where it was aimed,
## and shatters on whatever it hits first (ground, wall, car or person),
## leaving a Fire on the ground there. Whoever it hits is set alight.

const FIRE := preload("res://scenes/fire.tscn")
const GRAVITY := 18.0
## Level geometry and citizens.
const HIT_MASK := 1 | 2
const SPIN_SPEED := 14.0

## Who threw it. Its fire burns as their attack.
var thrower: Citizen

var _velocity := Vector3.ZERO
var _life := 3.0
var _spin := 0.0

@onready var _sprite: Sprite3D = $Sprite3D


## Sets it flying from `from` so it lands at `to`.
func launch(from: Vector3, to: Vector3) -> void:
	position = from
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	var flight_time := clampf(flat.length() / 9.0, 0.4, 0.9)
	_velocity = flat / flight_time
	_velocity.y = (to.y - from.y) / flight_time + 0.5 * GRAVITY * flight_time


func _physics_process(delta: float) -> void:
	_life -= delta
	# Tumbling end over end, drawn flat to the camera.
	_spin += SPIN_SPEED * delta
	var camera := get_viewport().get_camera_3d()
	if camera:
		_sprite.global_basis = camera.global_basis * Basis(Vector3.BACK, _spin)
	_velocity.y -= GRAVITY * delta
	var from := global_position
	var to := from + _velocity * delta
	var exclude: Array[RID] = []
	if is_instance_valid(thrower):
		exclude.append(thrower.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		var victim := hit.collider as Citizen
		if victim:
			victim.set_on_fire(thrower if is_instance_valid(thrower) else null)
		_shatter(hit.position)
	elif to.y <= 0.0 or _life <= 0.0:
		_shatter(Vector3(to.x, 0.0, to.z))
	else:
		global_position = to


func _shatter(at: Vector3) -> void:
	Sound.play_at(&"glass", at)
	var fire: Fire = FIRE.instantiate()
	fire.thrower = thrower if is_instance_valid(thrower) else null
	# Fuel runs down to the ground, whatever it hit.
	fire.position = Vector3(at.x, 0.0, at.z)
	get_parent().add_child(fire)
	queue_free()
