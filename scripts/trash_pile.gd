class_name TrashPile
extends Node3D
## A heap of junk left by squatters: bags, boxes and boards in a pile. In the
## way of anything set down on it, and of walking through. Clearing it (the
## player's interact) takes energy and it's gone for good: WorldState remembers
## it by `trash_id`. Built in code, a little different each time.

## Energy it takes to haul a pile out.
const CLEAR_ENERGY := 6.0
const COLORS: Array[Color] = [
	Color(0.12, 0.12, 0.13), Color(0.2, 0.18, 0.15), Color(0.42, 0.33, 0.22),
	Color(0.3, 0.32, 0.27), Color(0.5, 0.45, 0.38),
]

@export var trash_id := "trash"
## How much ground it covers, across.
@export var spread := 1.1

var _use: Interactable
var _cleared := false


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(trash_id)
	var body := StaticBody3D.new()
	add_child(body)
	for i in rng.randi_range(4, 7):
		var size := Vector3(rng.randf_range(0.25, 0.6), rng.randf_range(0.15, 0.5), rng.randf_range(0.25, 0.6))
		var junk := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		var look := StandardMaterial3D.new()
		look.albedo_color = COLORS[rng.randi() % COLORS.size()]
		look.roughness = 0.9
		box.material = look
		junk.mesh = box
		var reach := spread * 0.35
		junk.position = Vector3(rng.randf_range(-reach, reach), size.y * 0.5, rng.randf_range(-reach, reach))
		junk.rotation.y = rng.randf_range(0.0, TAU)
		add_child(junk)
	var shape := CollisionShape3D.new()
	var bounds := BoxShape3D.new()
	bounds.size = Vector3(spread, 0.6, spread)
	shape.shape = bounds
	shape.position.y = 0.3
	body.add_child(shape)

	_use = Interactable.new()
	_use.collision_layer = 0
	_use.collision_mask = 2
	_use.prompt_height = 1.4
	var reach_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = spread * 0.5 + 0.9
	reach_shape.shape = sphere
	_use.add_child(reach_shape)
	add_child(_use)
	_use.prompt = "Clear trash  (-%d energy)" % CLEAR_ENERGY
	_use.interacted.connect(_clear)


func _clear(_by: Citizen) -> void:
	if _cleared:
		return
	_cleared = true
	_use.prompt = ""
	WorldState.trash_cleared[trash_id] = true
	WorldState.use_energy(CLEAR_ENERGY)
	Sound.play_at(&"swing", global_position + Vector3.UP * 0.5)
	var puff: Node3D = preload("res://scenes/effects/dust_puff.tscn").instantiate()
	puff.position = Vector3.UP * 0.3
	add_child(puff)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector3(1.2, 0.05, 1.2), 0.35).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)
