extends Node3D
## A sodium street lamp that comes on at dusk and goes off at dawn, following
## GameClock. Each lamp switches a little later than the last, so the street
## lights up gradually, and flickers on while it warms up.
##
## The arm reaches out along +Z. Place lamps at the curb, facing the street.

@export var on_hour := 19.5
@export var off_hour := 6.5
## Each lamp switches up to this many in-game minutes after on_hour and off_hour.
@export var stagger_minutes := 25.0
@export var brightness := 2.5
## Real seconds to reach full brightness after the flicker.
@export var warm_up_time := 1.2

var _lit := false
var _delay_hours := 0.0
var _tween: Tween

@onready var _light: OmniLight3D = $Light
@onready var _head: GeometryInstance3D = $Head


func _ready() -> void:
	_delay_hours = randf() * stagger_minutes / 60.0
	_lit = _should_be_lit()
	_light.light_energy = brightness if _lit else 0.0
	_update_bulb()


func _process(_delta: float) -> void:
	var lit := _should_be_lit()
	if lit != _lit:
		_lit = lit
		_switch()
	_update_bulb()


func _should_be_lit() -> bool:
	var hour := GameClock.hour_of_day()
	return hour >= on_hour + _delay_hours or hour < off_hour + _delay_hours


func _switch() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	if _lit:
		# Sputter a couple of times, then warm up to full.
		_tween.tween_property(_light, "light_energy", brightness * 0.5, 0.06)
		_tween.tween_property(_light, "light_energy", 0.0, 0.1)
		_tween.tween_property(_light, "light_energy", brightness * 0.3, 0.05)
		_tween.tween_property(_light, "light_energy", 0.05, 0.15)
		_tween.tween_property(_light, "light_energy", brightness, warm_up_time) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	else:
		_tween.tween_property(_light, "light_energy", 0.0, 0.4)


## The bulb glows in step with the light it gives off.
func _update_bulb() -> void:
	_head.set_instance_shader_parameter("glow", 2.5 * _light.light_energy / brightness)
