class_name Water
extends Node3D
## Water around the map. Citizens inside the volume swim at the surface, which
## sits at this node's height. Invisible walls keep swimmers from leaving.

@onready var _volume: Area3D = $Volume


func _ready() -> void:
	_volume.body_entered.connect(_on_body_entered)
	_volume.body_exited.connect(_on_body_exited)


func surface_height() -> float:
	return global_position.y


func _on_body_entered(body: Node3D) -> void:
	if body is Citizen:
		body.enter_water(self)


func _on_body_exited(body: Node3D) -> void:
	if body is Citizen:
		body.exit_water(self)
