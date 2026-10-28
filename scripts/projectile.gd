class_name Projectile
extends Node3D
## A bullet. Flies straight, and hits the first thing on its path each physics
## step: a citizen takes the weapon's damage, anything else stops it with a
## spark. Passes through the shooter's allies and anyone already down.

const SPARK := preload("res://scenes/effects/block_spark.tscn")
## Level geometry and citizens.
const HIT_MASK := 1 | 2

var shooter: Citizen
var weapon: Weapon
var velocity := Vector3.ZERO
var lifetime := 1.2


func _ready() -> void:
	look_at(global_position + velocity, Vector3.UP)


func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0.0 or not is_instance_valid(shooter):
		queue_free()
		return
	var from := global_position
	var to := from + velocity * delta
	var exclude: Array[RID] = [shooter.get_rid()]
	# A few tries, skipping allies and the downed until something real is hit.
	for attempt in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to, HIT_MASK, exclude)
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty():
			break
		var target := hit.collider as Citizen
		if target and (target.is_down or shooter._is_ally(target)):
			exclude.append(target.get_rid())
			continue
		if target:
			target.hit(shooter, weapon)
		else:
			_spark(hit.position, hit.normal)
		queue_free()
		return
	global_position = to


func _spark(at: Vector3, normal: Vector3) -> void:
	var spark: Node3D = SPARK.instantiate()
	var placed := Transform3D(Basis(Quaternion(Vector3.UP, normal.normalized())), at)
	var parent := get_parent() as Node3D
	spark.transform = parent.global_transform.affine_inverse() * placed if parent else placed
	get_parent().add_child(spark)
