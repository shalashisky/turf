extends CanvasLayer
## A war over a gang's turf. Starts when the player attacks a gang member: the
## turf at stake is the one that gang holds where the player is, or else their
## nearest. The gang's doors on that turf start sending people out, and a bar
## at the top of the screen fills with each gang member taken down. At
## kills_to_win the turf is the player's: those doors shut for good, the
## gang's people there leave for their other turf, anyone hiding comes back
## out, and WorldState remembers it. The gang holds its ground and won't
## follow the player off the turf, and neither can the player leave for long:
## after abandon_time outside it, or going down, the war is lost and progress
## resets. Every so often a gang car drives in with more of them. One war at
## a time.

signal started
signal won

const CAR := preload("res://scenes/car.tscn")
## Cars come in from, and leave to, this far along their street from the
## player: off-screen, but still in the loaded part of the city.
const OFFSCREEN_DISTANCE := 38.0
## Cars stop this far short of the player.
const CAR_STOP_SHORT := 4.0

@export var kills_to_win := 10
@export var victory_message := "This turf is now ours!"
## How long the victory message stays up, in seconds.
@export var message_time := 3.0
## How long the player can be off the turf before the war's lost, in seconds.
@export var abandon_time := 10.0
## Seconds between gang cars arriving with more of them.
@export var car_interval := Vector2(14.0, 24.0)
@export var first_car_delay := 6.0

var active := false
var kills := 0
## Who the war's against, and over which turf.
var enemy_faction := &""
var territory: Territory

## Counts down while the player is off the turf. Negative while they're on it.
var _outside_left := -1.0
var _car_left := 0.0

@onready var _bar_panel: Control = %BarPanel
@onready var _bar: ProgressBar = %Bar
@onready var _bar_label: Label = %BarLabel
@onready var _message: Label = %Message
@onready var _return_warning: Label = %ReturnWarning


func _ready() -> void:
	add_to_group("turf_wars")
	_bar_panel.visible = false
	_message.visible = false
	_return_warning.visible = false


## The player has started a fight with `gang`.
func start(gang: StringName) -> void:
	if active:
		return
	var turf := _turf_at_stake(gang)
	if turf == null:
		return
	active = true
	kills = 0
	enemy_faction = gang
	territory = turf
	territory.at_war = true
	_outside_left = -1.0
	_car_left = first_car_delay
	var player := get_tree().get_first_node_in_group("player") as Citizen
	for door in get_tree().get_nodes_in_group("spawn_doors"):
		if door.territory == territory:
			door.activate(player)
	_refresh_bar()
	_bar_panel.visible = true
	_bar_panel.modulate.a = 0.0
	create_tween().tween_property(_bar_panel, "modulate:a", 1.0, 0.3)
	started.emit()


## A member of `gang` went down.
func count_kill(gang: StringName) -> void:
	if not active or gang != enemy_faction:
		return
	kills += 1
	_refresh_bar()
	if kills >= kills_to_win:
		_win()


func _process(delta: float) -> void:
	if not active:
		return
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null or player.is_down:
		_lose()
		return
	_watch_for_deserters(player, delta)
	if not active:
		return
	_car_left -= delta
	if _car_left <= 0.0:
		_car_left = randf_range(car_interval.x, car_interval.y)
		_send_car(player)


func _watch_for_deserters(player: Citizen, delta: float) -> void:
	if territory.contains(player.global_position):
		_outside_left = -1.0
		_return_warning.visible = false
		return
	if _outside_left < 0.0:
		_outside_left = abandon_time
	_outside_left -= delta
	_return_warning.visible = true
	_return_warning.text = "Get back to the turf war!  %d" % ceili(maxf(_outside_left, 0.0))
	if _outside_left <= 0.0:
		_lose()
		Transition.show_message("You abandoned the turf war.")


## A gang car comes in from off-screen along the street nearest the player
## that runs through the turf, and pulls up short of them.
func _send_car(player: Citizen) -> void:
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid == null:
		return
	var route := grid.drop_off_route(player.global_position, OFFSCREEN_DISTANCE, CAR_STOP_SHORT, territory.contains)
	if route.is_empty():
		return
	var car: Car = CAR.instantiate()
	car.drive(route.from, route.drop, route.exit, territory.color(), territory.deliver_member)
	get_tree().current_scene.add_child(car)


func _win() -> void:
	active = false
	territory.at_war = false
	# Whoever's left of the gang that held it runs for it.
	var losers := territory.owner_faction()
	for member in get_tree().get_nodes_in_group(losers):
		if member is GangMember and not member.is_down \
				and (member.home == territory or territory.contains(member.global_position)):
			member.rout()
	WorldState.set_territory_owner(territory.id, Factions.PLAYER)
	for door in get_tree().get_nodes_in_group("spawn_doors"):
		if door.territory == territory:
			door.shut_for_good()
	territory.handed_over()
	get_tree().call_group("safe_doors", "release")
	won.emit()
	create_tween().tween_property(_bar_panel, "modulate:a", 0.0, 0.5)
	_message.text = victory_message
	_message.visible = true
	_message.modulate.a = 0.0
	_message.scale = Vector2.ONE * 0.6
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 0.25)
	tween.parallel().tween_property(_message, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(message_time)
	tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_message.hide)


func _lose() -> void:
	active = false
	kills = 0
	territory.at_war = false
	_return_warning.visible = false
	for door in get_tree().get_nodes_in_group("spawn_doors"):
		if door.territory == territory:
			door.stand_down()
	create_tween().tween_property(_bar_panel, "modulate:a", 0.0, 0.5)


func _refresh_bar() -> void:
	_bar.max_value = kills_to_win
	_bar.value = kills
	_bar_label.text = "TURF WAR vs %s   %d / %d" % [Factions.display_name(enemy_faction), kills, kills_to_win]


## The turf `gang` holds where the player is standing, or else their nearest.
func _turf_at_stake(gang: StringName) -> Territory:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best: Territory = null
	var best_distance := INF
	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		if turf.owner_faction() != gang:
			continue
		if player and turf.contains(player.global_position):
			return turf
		var distance := turf.center().distance_to(player.global_position) if player else 0.0
		if distance < best_distance:
			best = turf
			best_distance = distance
	return best
