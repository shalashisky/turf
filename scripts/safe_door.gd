class_name SafeDoor
extends Node3D
## A neighbor's door. When a fight breaks out, neighbors who aren't fighting
## run here and hide inside until it's over: a turf war is won, or nobody
## nearby has been fighting for a few seconds. The player can't get in.
##
## The door faces +Z. Place it flush against a wall with its back to the building.

## How long it has to stay calm before anyone comes back out.
const CALM_BEFORE_RELEASE := 4.0

## Neighbors within this distance run here to hide.
@export var shelter_range := 25.0

var _inside: Array[Neighbor] = []
var _calm_time := 0.0

@onready var _hinge: Node3D = $Hinge
@onready var _knock: Interactable = $Knock


func _ready() -> void:
	add_to_group("safe_doors")
	_knock.interacted.connect(func(_by: Citizen) -> void: _rattle())


## Where a neighbor walks to before ducking inside.
func doorstep() -> Vector3:
	return global_position + global_basis.z.normalized() * 0.7


func shelter(neighbor: Neighbor) -> void:
	_swing()
	neighbor.hide_inside(self)
	_inside.append(neighbor)
	_calm_time = 0.0


## Lets everyone back out onto the doorstep.
func release() -> void:
	if _inside.is_empty():
		return
	_swing()
	var out := global_basis.z.normalized()
	var side := global_basis.x.normalized()
	for i in _inside.size():
		var neighbor := _inside[i]
		if is_instance_valid(neighbor):
			neighbor.come_out(doorstep() + out * 0.4 + side * (i - (_inside.size() - 1) * 0.5) * 0.8, out)
	_inside.clear()


func _process(delta: float) -> void:
	if _inside.is_empty():
		return
	_calm_time = 0.0 if _fight_going_on() else _calm_time + delta
	if _calm_time >= CALM_BEFORE_RELEASE:
		release()


func _fight_going_on() -> bool:
	for war in get_tree().get_nodes_in_group("turf_wars"):
		if war.active:
			return true
	for npc: Npc in get_tree().get_nodes_in_group("npcs"):
		if npc.target and is_instance_valid(npc.target) and not npc.target.is_down \
				and npc.global_position.distance_to(global_position) < shelter_range:
			return true
	return false


func _swing() -> void:
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-95.0), 0.15)
	tween.tween_interval(0.5)
	tween.tween_property(_hinge, "rotation:y", 0.0, 0.2)


## Locked. The door just rattles.
func _rattle() -> void:
	var tween := create_tween()
	for angle in [-4.0, 3.0, -2.0, 0.0]:
		tween.tween_property(_hinge, "rotation:y", deg_to_rad(angle), 0.05)
