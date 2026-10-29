extends Node3D
## A car going up: a fireball, a burst of fire and smoke, a flash that lights up the
## street, and a scorch on the ground. Frees itself when it's done.

@export var flash_energy := 12.0

@onready var _flash: OmniLight3D = $Flash


func _ready() -> void:
	Sound.play_at(&"explosion", global_position, 6.0, 0.1)
	for burst in [$Fire, $Smoke]:
		burst.emitting = true
	# A ball of fire that swells and burns away.
	var fireball: MeshInstance3D = $Fireball
	var ball := create_tween().set_parallel()
	ball.tween_property(fireball, "scale", Vector3.ONE * 2.6, 0.35).from(Vector3.ONE * 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	ball.tween_property(fireball, "transparency", 1.0, 0.35).from(0.0).set_ease(Tween.EASE_IN)
	var tween := create_tween()
	tween.tween_property(_flash, "light_energy", 0.0, 0.6).from(flash_energy) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.8)
	tween.tween_callback(queue_free)
