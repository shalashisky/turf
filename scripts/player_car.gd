class_name PlayerCar
extends Vehicle
## The player's own car. It starts out in the player's Garage, and stays
## wherever it's left, even after going indoors (WorldState.player_car).
##
## Gone for the day if it blows up (the player's thrown clear) or someone
## steals it and gets clean away. Either way, the next morning it's back in
## the garage, good as new.

## A thief this far from the player has got away with it.
const GETAWAY_DISTANCE := 60.0

## Where it's parked at the start of the game, and comes back to: in the
## garage, if there is one.
var _home: Transform3D
## The day it was wrecked or stolen, or -1.
var _gone_on_day := -1


func _ready() -> void:
	var garage := get_tree().get_first_node_in_group("garages") as Garage
	if garage:
		transform = get_parent().global_transform.affine_inverse() * garage.parking_transform()
	_home = transform
	var saved: Dictionary = WorldState.player_car
	var gone := false
	if not saved.is_empty():
		_gone_on_day = saved.gone_on_day
		if _gone_on_day < 0:
			transform = saved.transform
			health = saved.health
		elif _gone_on_day < GameClock.day_index:
			_gone_on_day = -1
		else:
			gone = true
	super()
	var blip := MapBlip.new()
	blip.label = "C"
	blip.color = paint.lightened(0.3)
	add_child(blip)
	GameClock.day_started.connect(_on_day_started)
	if gone:
		_vanish()


func _exit_tree() -> void:
	# Leaving with a thief at the wheel: it's gone.
	if driver and not driver.is_in_group("player"):
		_gone_on_day = GameClock.day_index
	WorldState.player_car = {"transform": transform, "health": health, "gone_on_day": _gone_on_day}
	super()


func _physics_process(delta: float) -> void:
	super(delta)
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if driver and not driver.is_in_group("player") and player \
			and global_position.distance_to(player.global_position) > GETAWAY_DISTANCE:
		driver.queue_free()
		driver = null
		street_driver = null
		_gone_on_day = GameClock.day_index
		Transition.show_message("Your car got stolen")
		_vanish()


func _on_taken(who: Citizen) -> void:
	if not who.is_in_group("player"):
		Transition.show_message("Someone's stealing your car!")


func _on_wrecked() -> void:
	_gone_on_day = GameClock.day_index


## The wreck has faded: nothing here until it's back in the morning.
func _on_wreck_faded() -> void:
	_vanish()


func _vanish() -> void:
	is_wrecked = true
	visible = false
	collision_layer = 0
	remove_from_group("vehicles")
	_refresh_door()


func _on_day_started(_day: int) -> void:
	if _gone_on_day < 0:
		return
	_gone_on_day = -1
	transform = _home
	heading = -global_basis.z
	speed = 0.0
	repair()
	visible = true
	collision_layer = 1
	add_to_group("vehicles")
	_refresh_door()
	reset_physics_interpolation()
