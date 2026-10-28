extends Node
## Keeps the streets around the player busy. Cars pull out onto the streets
## out of sight, on the loaded part of the city, and drive around until they're
## too far away (WorldBubble clears them up). Most are just folks; some are
## gang cars in the colors of whoever holds the turf they turned up on.

const TRAFFIC_CAR := preload("res://scenes/traffic_car.tscn")
## Everyday car colors.
const PAINTS: Array[Color] = [
	Color(0.85, 0.82, 0.74), Color(0.55, 0.12, 0.1), Color(0.18, 0.28, 0.5),
	Color(0.25, 0.4, 0.3), Color(0.6, 0.5, 0.3), Color(0.15, 0.15, 0.16),
	Color(0.7, 0.68, 0.66), Color(0.45, 0.3, 0.2), Color(0.35, 0.55, 0.6),
]

@export var streamer: ChunkStreamer
@export var count := 7
## New cars appear this far from the player.
@export var spawn_distance := Vector2(24.0, 32.0)
@export_range(0.0, 1.0) var gang_chance := 0.2
@export var spawn_interval := 0.5
## Never this close to another car.
@export var spacing := 9.0

var _spawn_left := 0.0


func _process(delta: float) -> void:
	_spawn_left -= delta
	if _spawn_left > 0.0:
		return
	_spawn_left = spawn_interval
	if get_tree().get_nodes_in_group("traffic").size() < count:
		_spawn_one()


func _spawn_one() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if player == null or grid == null:
		return
	var center := player.global_position
	var streets := grid.streets()
	for attempt in 10:
		var street: Dictionary = streets.pick_random()
		var across: float = (center.z if street.along_x else center.x) - street.line
		var distance := randf_range(spawn_distance.x, spawn_distance.y)
		if absf(across) > distance:
			continue
		var along := Vector3.RIGHT if street.along_x else Vector3.BACK
		var on_street := Vector3(center.x, 0.0, street.line) if street.along_x else Vector3(street.line, 0.0, center.z)
		on_street += along * sqrt(distance * distance - across * across) * (1.0 if randf() < 0.5 else -1.0)
		var direction := along if randf() < 0.5 else -along
		var spot := on_street + Vector3(-direction.z, 0.0, direction.x) * CityGrid.LANE_OFFSET
		if grid.tile_at(spot) != CityGrid.ROAD or (streamer and not streamer.is_loaded_at(spot)) or _crowded(spot):
			continue
		var car: TrafficCar = TRAFFIC_CAR.instantiate()
		car.start(spot, on_street, direction)
		_choose_driver(car, spot)
		get_tree().current_scene.add_child(car)
		return


func _choose_driver(car: TrafficCar, spot: Vector3) -> void:
	car.paint = PAINTS.pick_random()
	if randf() >= gang_chance:
		return
	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		var holder := turf.owner_faction()
		if turf.contains(spot) and Factions.is_gang(holder) and holder != Factions.PLAYER:
			car.gang = holder
			car.paint = turf.color()
			return


func _crowded(spot: Vector3) -> bool:
	for car: Node3D in get_tree().get_nodes_in_group("vehicles"):
		if car.global_position.distance_to(spot) < spacing:
			return true
	return false
