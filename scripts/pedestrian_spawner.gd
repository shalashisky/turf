extends Node3D
## Keeps the streets populated with some kind of sidewalk walker: pedestrians,
## cops, and so on. Puts them on random sidewalks at the start, and tops them
## back up as they die off, out of the player's sight and never in the middle
## of a turf war.

@export var scene: PackedScene = preload("res://scenes/npcs/pedestrian.tscn")
@export var count := 24
## Outfits to pick from. Empty keeps the scene's own.
@export var looks: Array[Texture2D] = [
	preload("res://art/pedestrian_1_8dir.png"),
	preload("res://art/pedestrian_2_8dir.png"),
	preload("res://art/pedestrian_3_8dir.png"),
]
## Weapons to hand out, one picked at random each (list one twice to make it
## more likely). Empty keeps the scene's own.
@export var weapons: Array = []
## How many spawn together. Followers get the first one as their `leader`,
## for scenes that have one (like Agent).
@export var group_size := 1
## New ones only appear at least this far from the player.
@export var min_spawn_distance := 18.0
## How often to check whether more are needed, in seconds.
@export var check_interval := 3.0

var _sidewalks: Array[Vector3] = []
var _check_left := 0.0


func _ready() -> void:
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid:
		_sidewalks = grid.sidewalk_centers()
	for i in floori(count / float(maxi(group_size, 1))):
		_spawn()


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = check_interval
	for war in get_tree().get_nodes_in_group("turf_wars"):
		if war.active:
			return
	if _living() + group_size <= count:
		_spawn()


func _living() -> int:
	var living := 0
	for child in get_children():
		if child is Citizen and not child.is_dead:
			living += 1
	return living


func _spawn() -> void:
	if _sidewalks.is_empty():
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	for attempt in 12:
		var spot: Vector3 = _sidewalks.pick_random()
		if player and spot.distance_to(player.global_position) < min_spawn_distance:
			continue
		var first: Citizen = null
		for i in group_size:
			var walker: Citizen = scene.instantiate()
			if not looks.is_empty():
				walker.get_node("Sprite").texture = looks.pick_random()
			if not weapons.is_empty():
				walker.starting_weapon = weapons.pick_random()
			walker.position = to_local(spot + Vector3(0.0, 0.0, 0.7 * i))
			if first and "leader" in walker:
				walker.leader = first
			add_child(walker)
			if first == null:
				first = walker
		return
