extends Node3D
## A sodium street lamp that comes on at dusk and goes off at dawn, following
## GameClock. Each lamp switches a little later than the last, so the street
## lights up gradually, and flickers on while it warms up.
##
## The arm reaches out along +Z. Place lamps at the curb, facing the street.
##
## A car going fast enough knocks it over (knock_over()): it topples, goes
## dark, fades out and is gone, and stays gone until the next day.

## How long a knocked-over lamp takes to be gone, falling and fading included.
const FALLEN_TIME := 2.0
const FADE_TIME := 0.6
const FALL_TIME := 0.55
## How far over it ends up: not quite flat, since the arm props it up.
const FALLEN_ANGLE := 1.5

@export var on_hour := 19.5
@export var off_hour := 6.5
## Each lamp switches up to this many in-game minutes after on_hour and off_hour.
@export var stagger_minutes := 25.0
@export var brightness := 2.5
## Real seconds to reach full brightness after the flicker.
@export var warm_up_time := 1.2

var _lit := false
var _fallen := false
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


## Knocked over by something going at `push`: it topples that way.
func knock_over(push: Vector3) -> void:
	if _fallen:
		return
	_fallen = true
	var grid := get_tree().get_first_node_in_group("city_grid")
	if grid:
		grid.forget_lamp(global_position)
	# Out of the way right now; the falling happens after this physics step.
	$Body.collision_layer = 0
	$Body.queue_free()
	_fall.call_deferred(push)


func _fall(push: Vector3) -> void:
	set_process(false)
	if _tween:
		_tween.kill()
	_light.light_energy = 0.0
	_head.set_instance_shader_parameter("glow", 0.0)

	# Topple over the base, the way it was hit, picking up speed as it goes,
	# then bounce once where it lands.
	var flat := Vector3(push.x, 0.0, push.z)
	if flat.length() < 0.01:
		flat = global_basis.z
	var axis := Vector3.UP.cross(flat.normalized()).normalized()
	var standing := basis
	var tip_over := func(angle: float) -> void:
		basis = Basis(axis, angle) * standing
	var tween := create_tween()
	tween.tween_method(tip_over, 0.0, FALLEN_ANGLE, FALL_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_method(tip_over, FALLEN_ANGLE, FALLEN_ANGLE - 0.12, 0.1).set_ease(Tween.EASE_OUT)
	tween.tween_method(tip_over, FALLEN_ANGLE - 0.12, FALLEN_ANGLE, 0.12).set_ease(Tween.EASE_IN)
	tween.tween_interval(FALLEN_TIME - FADE_TIME - FALL_TIME - 0.22)
	for part: GeometryInstance3D in [$Pole, $Arm, $Head]:
		tween.parallel().tween_property(part, "transparency", 1.0, FADE_TIME).set_delay(FALLEN_TIME - FADE_TIME - FALL_TIME - 0.22)
	tween.tween_callback(queue_free)


## The bulb glows in step with the light it gives off.
func _update_bulb() -> void:
	_head.set_instance_shader_parameter("glow", 2.5 * _light.light_energy / brightness)
