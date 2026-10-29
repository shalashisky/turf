extends Node3D
## A door into another scene, like a building's interior. Walking into it
## swings it open and takes you through, no button needed: right up against
## it and heading in, not just passing by along the sidewalk.
##
## The door faces +Z. Place it flush against a wall with its back to the
## building. Put arrival markers for this door at least 1.2 m out in front,
## clear of the trigger, so arriving players don't walk straight back through.

## A door doesn't react this soon after its scene loads, in case someone
## arrives standing in the trigger.
const ARMING_DELAY := 0.75
## The player has to be this close to the door's face, this near its middle,
## and walking into it at least this fast.
const REACH := 0.6
const HALF_WIDTH := 0.75
const MIN_INWARD_SPEED := 0.8

@export_file("*.tscn") var target_scene := ""
## Name of the entrance marker to come out at, in the target scene.
@export var target_entrance := ""
@export var open_angle_degrees := 100.0

var _armed := false

@onready var _hinge: Node3D = $Hinge
@onready var _trigger: Area3D = $Trigger


func _ready() -> void:
	add_to_group("entrance_doors")
	get_tree().create_timer(ARMING_DELAY).timeout.connect(func() -> void: _armed = true)


func _physics_process(_delta: float) -> void:
	if not _armed or target_scene.is_empty() or Transition.busy:
		return
	for body in _trigger.get_overlapping_bodies():
		if body.is_in_group("player") and _walking_in(body):
			_go_through()
			return


func _walking_in(body: Node3D) -> bool:
	var at := to_local(body.global_position)
	if at.z > REACH or absf(at.x) > HALF_WIDTH:
		return false
	# Where they're trying to go, even with the door stopping them.
	var trying: Vector3 = body.get("_walk_velocity")
	return trying.dot(-global_basis.z) > MIN_INWARD_SPEED


func _go_through() -> void:
	Sound.play(&"door")
	create_tween().tween_property(_hinge, "rotation:y", deg_to_rad(-open_angle_degrees), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Transition.go_to(target_scene, target_entrance)
