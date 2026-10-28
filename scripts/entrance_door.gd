extends Node3D
## A door you can walk through into another scene, like a building's interior.
## Press interact nearby to swing it open and step through.
##
## The door faces +Z. Place it flush against a wall with its back to the building.

@export_file("*.tscn") var target_scene := ""
## Name of the entrance marker to come out at, in the target scene.
@export var target_entrance := ""
@export var prompt := "Enter"
@export var open_angle_degrees := 100.0

@onready var _hinge: Node3D = $Hinge
@onready var _use: Interactable = $Use


func _ready() -> void:
	_use.prompt = prompt
	_use.interacted.connect(_on_used)


func _on_used(_by: Citizen) -> void:
	if target_scene.is_empty() or Transition.busy:
		return
	create_tween().tween_property(_hinge, "rotation:y", deg_to_rad(-open_angle_degrees), 0.2) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	Transition.go_to(target_scene, target_entrance)
