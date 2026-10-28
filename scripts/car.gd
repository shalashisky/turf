class_name Car
extends Vehicle
## A car that brings people in: a gang car in a turf war, or a police cruiser
## after a wanted player. Drives in along a street from off-screen, pulls up
## near the player, and lets out its crew. Then it either drives off down the
## street and away, or now and then tries to run the player down first.
## Whoever takes it (hijack()) gets the driver out of it too.
##
## Set it up with drive() before adding it to the scene.

enum Stage { ARRIVING, UNLOADING, RAMMING, LEAVING }

@export var cruise_speed := 9.0
@export var ram_speed := 12.0
## How fast it can turn while ramming, in radians per second.
@export var ram_turn_rate := 1.6
@export_range(0.0, 1.0) var ram_chance := 0.35
@export var ram_time := 5.0
@export var crew_size := Vector2i(1, 4)
## A light bar on the roof, flashing red and blue.
@export var siren := false

var stage := Stage.ARRIVING

## Called as crew(point, target) for each of the crew getting out.
var _crew: Callable
var _drop_point: Vector3
var _exit_point: Vector3
var _stage_left := 0.0


## Comes in from `from`, stops at `drop`, and leaves by `exit`. Painted
## `color`. Each of the crew is let out by calling crew(point, target), like
## Territory.deliver_member().
func drive(from: Vector3, drop: Vector3, exit: Vector3, color: Color, crew: Callable) -> void:
	position = from
	_drop_point = drop
	_exit_point = exit
	_crew = crew
	occupied = true
	add_to_group("spawned_vehicles")
	paint = color
	aim(drop - from)
	speed = cruise_speed


func _ready() -> void:
	super()
	if siren:
		_add_light_bar()


## Gives up and drives off by the way out, if its own driver's still at the wheel.
func leave() -> void:
	if stage != Stage.LEAVING and occupied:
		_leave()


func _ai_drive(delta: float) -> void:
	# The driver's been thrown out: it just rolls to a stop.
	if not occupied:
		super(delta)
		return
	match stage:
		Stage.ARRIVING:
			_arrive(delta)
		Stage.UNLOADING:
			speed = 0.0
			_stage_left -= delta
			if _stage_left <= 0.0:
				if randf() < ram_chance and _player() != null:
					stage = Stage.RAMMING
					_stage_left = ram_time
				else:
					_leave()
		Stage.RAMMING:
			_ram(delta)
		Stage.LEAVING:
			speed = move_toward(speed, cruise_speed, 8.0 * delta)
			if global_position.distance_to(_exit_point) < 3.0:
				queue_free()
	_drive_step(delta)


func _arrive(delta: float) -> void:
	var left := global_position.distance_to(_drop_point)
	# Ease off for the last few meters and stop at the drop-off.
	speed = minf(cruise_speed, maxf(left * 1.6, 1.0))
	if left < 0.5:
		speed = 0.0
		stage = Stage.UNLOADING
		_stage_left = 1.6
		_let_crew_out()


func _ram(delta: float) -> void:
	var player := _player()
	_stage_left -= delta
	if player == null or _stage_left <= 0.0:
		_leave()
		return
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.1:
		var wanted := to_player.normalized()
		var angle := heading.signed_angle_to(wanted, Vector3.UP)
		heading = heading.rotated(Vector3.UP, clampf(angle, -ram_turn_rate * delta, ram_turn_rate * delta))
	speed = move_toward(speed, ram_speed, 10.0 * delta)


func _leave() -> void:
	stage = Stage.LEAVING
	var away := _exit_point - global_position
	away.y = 0.0
	if away.length() > 0.1:
		heading = away.normalized()


func _let_crew_out() -> void:
	if not _crew.is_valid():
		return
	var player := _player()
	var side := Vector3(-heading.z, 0.0, heading.x)
	for i in randi_range(crew_size.x, crew_size.y):
		# Out of the doors either side, front to back.
		var spot := global_position + side * (1.4 if i % 2 == 0 else -1.4) + heading * (0.8 - floori(i / 2.0) * 1.4)
		_crew.call(spot, player)


func _player() -> Citizen:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	return player if player and not player.is_down else null



func _let_occupant_out(at: Vector3, by: Citizen) -> Citizen:
	return _crew.call(at, by) if _crew.is_valid() else null


func _on_wrecked() -> void:
	for light in find_children("", "OmniLight3D", false, false):
		light.queue_free()


func _add_light_bar() -> void:
	for side in [-1, 1]:
		var color := Color(1, 0.1, 0.1) if side < 0 else Color(0.15, 0.3, 1)
		var lamp := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.6, 0.16, 0.3)
		var glow := StandardMaterial3D.new()
		glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.albedo_color = color
		box.material = glow
		lamp.mesh = box
		lamp.position = Vector3(side * 0.32, 1.43, 0.2)
		add_child(lamp)
		var light := OmniLight3D.new()
		light.light_color = color
		light.omni_range = 7.0
		light.position = Vector3(side * 0.5, 1.8, 0.2)
		add_child(light)
		# Red and blue take turns.
		# Made by the light, so it stops when the light goes.
		var flash := light.create_tween().set_loops()
		flash.tween_property(light, "light_energy", 3.0, 0.05).set_delay(0.0 if side < 0 else 0.25)
		flash.tween_property(light, "light_energy", 0.0, 0.2)
		if side < 0:
			flash.tween_interval(0.25)
