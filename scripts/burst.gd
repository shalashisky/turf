extends GPUParticles3D
## One-shot particle effect: fires as soon as it enters the tree and frees
## itself when done. Spawn with Citizen._spawn_effect(), which also points the
## effect's local +Y (the emission direction) where it should spray.


func _ready() -> void:
	emitting = true
	finished.connect(queue_free)
