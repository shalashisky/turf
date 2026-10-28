class_name TrafficCar
extends Vehicle
## Someone driving around town, by StreetDriver. Most are just folks, some
## run with a gang.
##
## Damage it and the driver reacts: most floor it out of there, but a gang
## car's crew gets out to settle things. Take it from them (hijack()) and
## they get out: folks run off, gangsters fight.
##
## Set it up with start() before adding it to the scene.

const PEDESTRIAN := preload("res://scenes/npcs/pedestrian.tscn")

## The gang the driver runs with, if any.
var gang: StringName = &""

var _start_street: Vector3
var _start_direction: Vector3


## Drives along the street through `street_point` in `direction` (one of the
## four flat axes), starting at `at`.
func start(at: Vector3, street_point: Vector3, direction: Vector3) -> void:
	position = at
	_start_street = street_point
	_start_direction = direction
	aim(direction)
	speed = 7.0
	occupied = true
	add_to_group("spawned_vehicles")
	add_to_group("traffic")


func _ready() -> void:
	super()
	if occupied:
		street_driver = StreetDriver.new(self, _start_street, _start_direction)


func _on_damaged(attacker: Citizen) -> void:
	if attacker == null or not attacker.is_in_group("player") or not occupied or street_driver == null or street_driver.fleeing:
		return
	if gang != &"" and _let_crew_out(attacker):
		return
	street_driver.fleeing = true
	street_driver.go_straight()


## The crew piles out to fight `attacker`, delivered by any turf their gang
## holds. False if their gang holds no turf to call on.
func _let_crew_out(attacker: Citizen) -> bool:
	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		if turf.owner_faction() != gang:
			continue
		occupied = false
		street_driver = null
		var side := StreetDriver.right_of(heading)
		for i in randi_range(1, 3):
			turf.deliver_member(global_position + side * (1.4 if i % 2 == 0 else -1.4) - heading * floori(i / 2.0) * 1.4, attacker)
		_refresh_door()
		return true
	return false


func _let_occupant_out(at: Vector3, by: Citizen) -> Citizen:
	if gang != &"":
		for turf: Territory in get_tree().get_nodes_in_group("territories"):
			if turf.owner_faction() == gang:
				return turf.deliver_member(at, by)
	var person: Citizen = PEDESTRIAN.instantiate()
	person.position = at
	get_tree().current_scene.add_child(person)
	person.reset_physics_interpolation()
	return person
