extends Node
## Ends the player's day, autoloaded as DayCycle. Sleeping in bed starts the
## next morning at home, rested. Running out of energy, or still being up at
## 2:00 AM, makes the player pass out instead: they wake up at home with only
## some of their energy back, and if they dropped somewhere other than home,
## someone helped themselves to part of their cash.

const HOME_SCENE := "res://scenes/interiors/grow_house.tscn"
## The entrance marker by the bed, where the player wakes up.
const BED_ENTRANCE := "WakeUp"
## Share of energy back after passing out, instead of sleeping properly.
const PASS_OUT_ENERGY := 0.6
## Share of cash taken by whoever finds you passed out in the street.
const ROBBED_SHARE := Vector2(0.25, 0.5)
## How long the player lies there before the screen goes dark.
const COLLAPSE_TIME := 1.5

var busy := false


func _ready() -> void:
	WorldState.out_of_energy.connect(
		pass_out.bind("You pushed yourself too hard and passed out."))
	GameClock.out_of_time.connect(
		pass_out.bind("You stayed out way too late and passed out."))


func sleep() -> void:
	if busy or Transition.busy:
		return
	busy = true
	await Transition.go_to(HOME_SCENE, BED_ENTRANCE, _next_morning.bind(1.0), true,
		"%s. You feel rested." % GameClock.date_text_for(GameClock.day_index + 1))
	busy = false


func pass_out(reason: String) -> void:
	if busy or Transition.busy:
		return
	busy = true
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player and not player.is_down:
		player.knock_out()
	var at_home := get_tree().current_scene.scene_file_path == HOME_SCENE
	var robbed := 0
	if not at_home and WorldState.money > 0:
		robbed = maxi(roundi(WorldState.money * randf_range(ROBBED_SHARE.x, ROBBED_SHARE.y)), 1)
		WorldState.add_money(-robbed)
	await get_tree().create_timer(COLLAPSE_TIME).timeout
	var message := reason
	if robbed > 0:
		message += "\nSomeone took $%d while you were out." % robbed
	await Transition.go_to(HOME_SCENE, BED_ENTRANCE, _next_morning.bind(PASS_OUT_ENERGY), true, message)
	busy = false


func _next_morning(energy: float) -> void:
	GameClock.start_next_day()
	WorldState.restore_energy(energy)
	Factions.clear_wanted()
