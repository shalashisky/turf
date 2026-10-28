extends Node3D
## A door on a building wall that sends out enemies once a fight starts.
## Attacking any enemy sets off every door in the "spawn_doors" group. Each one
## then swings open, lets an enemy walk out, and shuts again, every
## spawn_interval seconds, until the attacker is dead.
##
## The door faces +Z. Place it flush against a wall with its back to the building.

## Enemies spawn this far out from the wall, just clear of it.
const EXIT_DISTANCE := 0.35
const WALK_OUT_TIME := 0.6

@export var enemy_scene: PackedScene = preload("res://scenes/dummy_enemy.tscn")
@export var spawn_interval := 5.0
## Random extra time added to each wait, so doors don't open in sync.
@export var spawn_jitter := 1.5
## Delay between the alarm going off and the first enemy coming out.
@export var first_spawn_delay := 0.8
## Stop sending more while this many of this door's enemies are still alive.
@export var max_alive := 2
## Chance that each enemy comes out armed, with a random pick from weapon_pool.
## Everyone else uses their fists.
@export_range(0.0, 1.0) var armed_chance := 0.5
@export var weapon_pool: Array[Weapon] = [
	preload("res://weapons/baseball_bat.tres"),
	preload("res://weapons/knife.tres"),
	preload("res://weapons/brass_knuckles.tres"),
]
@export var open_angle_degrees := 100.0
## How long the door stays open while the enemy walks out.
@export var hold_open_time := 0.9

## Who the spawned enemies go after. Null while the door is quiet.
var target: Citizen

var _spawn_timer := 0.0
var _alive: Array[Citizen] = []
var _busy := false

@onready var _hinge: Node3D = $Hinge
@onready var _lamp_material: StandardMaterial3D = $Lamp.material_override


func _ready() -> void:
	add_to_group("spawn_doors")
	_set_alarm_lamp(false)


func activate(attacker: Citizen) -> void:
	if attacker == target:
		return
	if target == null:
		_spawn_timer = first_spawn_delay + randf() * spawn_jitter
	target = attacker
	_set_alarm_lamp(true)


func _physics_process(delta: float) -> void:
	if target and (not is_instance_valid(target) or target.is_dead):
		target = null
		_set_alarm_lamp(false)
	if target == null or _busy:
		return

	_alive = _alive.filter(func(enemy: Citizen) -> bool: return is_instance_valid(enemy) and not enemy.is_dead)
	_spawn_timer -= delta
	if _spawn_timer > 0.0 or _alive.size() >= max_alive or _doorway_blocked():
		return
	_spawn_timer = spawn_interval + randf() * spawn_jitter
	_open_and_spawn()


func _open_and_spawn() -> void:
	_busy = true
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-open_angle_degrees), 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_callback(_spawn_enemy)
	tween.tween_interval(hold_open_time)
	tween.tween_property(_hinge, "rotation:y", 0.0, 0.3) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void: _busy = false)


func _spawn_enemy() -> void:
	if target == null:
		return  # the fight ended while the door was opening
	var forward := global_basis.z.normalized()
	var enemy: Citizen = enemy_scene.instantiate()
	if not weapon_pool.is_empty() and randf() < armed_chance:
		enemy.starting_weapon = weapon_pool.pick_random()
	# Place before adding, so the enemy's spawn point is the doorway.
	var at := global_position + forward * EXIT_DISTANCE
	var parent := get_parent() as Node3D
	enemy.position = parent.to_local(at) if parent else at
	get_parent().add_child(enemy)
	enemy.reset_physics_interpolation()
	enemy.facing = forward
	enemy.walk_out(forward, WALK_OUT_TIME)
	enemy.provoke(target)
	_alive.append(enemy)


func _doorway_blocked() -> bool:
	var spawn_point := global_position + global_basis.z.normalized() * EXIT_DISTANCE
	for citizen: Citizen in get_tree().get_nodes_in_group("citizens"):
		if citizen.global_position.distance_to(spawn_point) < 0.7:
			return true
	return false


func _set_alarm_lamp(on: bool) -> void:
	_lamp_material.emission_enabled = on
	_lamp_material.albedo_color = Color(1.0, 0.15, 0.1) if on else Color(0.25, 0.08, 0.08)
