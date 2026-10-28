extends Node3D
## A gunshot's flash: a burst of light and a bright flare that's gone in a blink.

const LIFETIME := 0.07

@onready var _light: OmniLight3D = $Light
@onready var _flare: Node3D = $Flare


func _ready() -> void:
	_flare.rotation.z = randf() * TAU
	_flare.scale = Vector3.ONE * randf_range(0.8, 1.2)
	var tween := create_tween()
	tween.tween_property(_light, "light_energy", 0.0, LIFETIME)
	tween.parallel().tween_property(_flare, "scale", Vector3.ONE * 0.2, LIFETIME)
	tween.tween_callback(queue_free)
