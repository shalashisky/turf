extends Node
## While the player is wanted, the police send cruisers: they come in along the
## nearest street with their lights going, let out a couple of cops, and now
## and then try to run the player down. Once the player's off the hook, any
## still around drive off.

const CAR := preload("res://scenes/car.tscn")
const COP := preload("res://scenes/npcs/cop.tscn")
const PAINT := Color(0.92, 0.92, 0.9)
## Cruisers come in from, and leave to, this far along their street.
const OFFSCREEN_DISTANCE := 38.0
const STOP_SHORT := 5.0

@export var first_car_delay := 3.0
@export var car_interval := Vector2(10.0, 16.0)
@export var max_cars := 2
@export var crew_size := Vector2i(1, 2)
@export_range(0.0, 1.0) var ram_chance := 0.5

var _cars: Array[Node] = []
var _next_car_in := 0.0


func _ready() -> void:
	Factions.wanted_changed.connect(_on_wanted_changed)


func _on_wanted_changed() -> void:
	if Factions.is_player_wanted():
		_next_car_in = first_car_delay
		return
	for car in _cars:
		if is_instance_valid(car):
			car.leave()


func _process(delta: float) -> void:
	if not Factions.is_player_wanted():
		return
	_next_car_in -= delta
	if _next_car_in > 0.0:
		return
	_next_car_in = randf_range(car_interval.x, car_interval.y)
	for i in range(_cars.size() - 1, -1, -1):
		if not is_instance_valid(_cars[i]) or _cars[i].is_wrecked:
			_cars.remove_at(i)
	if _cars.size() < max_cars:
		_send_car()


func _send_car() -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if player == null or grid == null:
		return
	var route := grid.drop_off_route(player.global_position, OFFSCREEN_DISTANCE, STOP_SHORT)
	if route.is_empty():
		return
	var car: Car = CAR.instantiate()
	car.siren = true
	car.crew_size = crew_size
	car.ram_chance = ram_chance
	car.drive(route.from, route.drop, route.exit, PAINT, _deliver_cop)
	get_tree().current_scene.add_child(car)
	_cars.append(car)


func _deliver_cop(point: Vector3, target: Citizen) -> Citizen:
	var cop: Citizen = COP.instantiate()
	cop.position = point
	get_tree().current_scene.add_child(cop)
	cop.reset_physics_interpolation()
	if target:
		cop.start_fighting(target)
	return cop
