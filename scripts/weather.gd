extends Node
## The weather, for now just rain. Showers come and go on their own: a spell
## of dry weather, then rain that builds up, keeps on for a while, and dies
## away. The ground stays wet a while after. Runs on in-game time, and carries
## on while the player's indoors.
##
## Rain (the falling drops), DayNight (grey skies) and CityGrid (wet streets)
## all follow `intensity` and `wetness`. R toggles the rain, for debugging.

signal changed

## In-game hours of dry weather between showers, and how long showers last.
@export var dry_hours := Vector2(5.0, 18.0)
@export var shower_hours := Vector2(1.0, 4.0)
## The first shower of the game comes this many in-game hours in.
@export var first_shower_hours := Vector2(1.0, 4.0)
## In-game hours for rain to build up to full, or die away.
@export var ramp_hours := 0.35
## In-game hours for the streets to dry out after the rain stops.
@export var drying_hours := 1.5

var raining := false
## How hard it's raining right now, 0 to 1.
var intensity := 0.0
## How wet the ground is, 0 to 1. Soaks up fast, dries slowly.
var wetness := 0.0

var _hours_left := 0.0


func _ready() -> void:
	_hours_left = randf_range(first_shower_hours.x, first_shower_hours.y)


func _process(delta: float) -> void:
	if GameClock.paused:
		return
	var hours := delta / (GameClock.seconds_per_minute * 60.0)
	_hours_left -= hours
	if _hours_left <= 0.0:
		_set_raining(not raining)
	intensity = move_toward(intensity, 1.0 if raining else 0.0, hours / ramp_hours)
	if intensity > wetness:
		wetness = move_toward(wetness, intensity, hours / ramp_hours)
	else:
		wetness = move_toward(wetness, intensity, hours / drying_hours)


func _unhandled_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_R:
		_set_raining(not raining)


func _set_raining(rain: bool) -> void:
	raining = rain
	var span := shower_hours if rain else dry_hours
	_hours_left = randf_range(span.x, span.y)
	changed.emit()
