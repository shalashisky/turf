extends Node3D
## A door into another scene, like a building's interior. Walking into it
## swings it open and takes you through, no button needed.
##
## The door faces +Z. Place it flush against a wall with its back to the
## building. Put arrival markers for this door at least 1.2 m out in front,
## clear of the trigger, so arriving players don't walk straight back through.

## A door doesn't react this soon after its scene loads, in case someone
## arrives standing in the trigger.
const ARMING_DELAY := 0.75

@export_file("*.tscn") var target_scene := ""
## Name of the entrance marker to come out at, in the target scene.
@export var target_entrance := ""
@export var open_angle_degrees := 100.0

var _armed := false

@onready var _hinge: Node3D = $Hinge
@onready var _trigger: Area3D = $Trigger


func _ready() -> void:
	add_to_group("entrance_doors")
	_trigger.body_entered.connect(_on_body_entered)
	get_tree().create_timer(ARMING_DELAY).timeout.connect(func() -> void: _armed = true)


func _on_body_entered(body: Node3D) -> void:
	if not _armed or not body.is_in_group("player") or target_scene.is_empty() or Transition.busy:
		return
	create_tween().tween_property(_hinge, "rotation:y", deg_to_rad(-open_angle_degrees), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Transition.go_to(target_scene, target_entrance)
