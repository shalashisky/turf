class_name Car
extends CharacterBody3D
## A gang car in a turf war. Drives in along a street from off-screen, pulls up
## near the player, and lets out its crew. Then it either drives off down the
## street and away, or now and then tries to run the player down first.
## Anyone it hits at speed takes damage and gets thrown (Citizen.struck_by_vehicle).
##
## The car faces -Z. Set it up with drive() before adding it to the scene.

enum Stage { ARRIVING, UNLOADING, RAMMING, LEAVING }

@export var cruise_speed := 9.0
@export var ram_speed := 12.0
## How fast it can turn while ramming, in radians per second.
@export var ram_turn_rate := 1.6
@export_range(0.0, 1.0) var ram_chance := 0.35
@export var ram_time := 5.0
## Below this speed, bumping into someone doesn't hurt them.
@export var harmful_speed := 3.5
@export var crew_size := Vector2i(1, 4)

var stage := Stage.ARRIVING

var _territory: Territory
var _drop_point: Vector3
var _exit_point: Vector3
var _heading := Vector3.FORWARD
var _speed := 0.0
var _stage_left := 0.0
## Recently hit citizens, so one bump doesn't count every frame.
var _hit_cooldowns := {}

@onready var _body_mesh: MeshInstance3D = $Body


## Comes in from `from`, stops at `drop`, and leaves by `exit`, delivering
## members of whichever gang holds `territory`.
func drive(from: Vector3, drop: Vector3, exit: Vector3, territory: Territory) -> void:
	position = from
	_drop_point = drop
	_exit_point = exit
	_territory = territory
	_heading = (drop - from).normalized()
	_speed = cruise_speed


func _ready() -> void:
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var paint := StandardMaterial3D.new()
	paint.albedo_color = _territory.color() if _territory else Color.GRAY
	paint.roughness = 0.35
	_body_mesh.material_override = paint
	_face(_heading)
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	match stage:
		Stage.ARRIVING:
			_arrive(delta)
		Stage.UNLOADING:
			_speed = 0.0
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
			_speed = move_toward(_speed, cruise_speed, 8.0 * delta)
			if global_position.distance_to(_exit_point) < 3.0 or not _on_map():
				queue_free()
	velocity = _heading * _speed
	move_and_slide()
	global_position.y = 0.0
	_face(_heading)
	_hit_whoever_we_bumped()
	for who in _hit_cooldowns.keys():
		_hit_cooldowns[who] -= delta
		if _hit_cooldowns[who] <= 0.0:
			_hit_cooldowns.erase(who)


func _arrive(delta: float) -> void:
	var left := global_position.distance_to(_drop_point)
	# Ease off for the last few meters and stop at the drop-off.
	_speed = minf(cruise_speed, maxf(left * 1.6, 1.0))
	if left < 0.5:
		_speed = 0.0
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
		var angle := _heading.signed_angle_to(wanted, Vector3.UP)
		_heading = _heading.rotated(Vector3.UP, clampf(angle, -ram_turn_rate * delta, ram_turn_rate * delta))
	_speed = move_toward(_speed, ram_speed, 10.0 * delta)


func _leave() -> void:
	stage = Stage.LEAVING
	var away := _exit_point - global_position
	away.y = 0.0
	if away.length() > 0.1:
		_heading = away.normalized()


func _let_crew_out() -> void:
	if _territory == null:
		return
	var player := _player()
	var side := Vector3(-_heading.z, 0.0, _heading.x)
	for i in randi_range(crew_size.x, crew_size.y):
		# Out of the doors either side, front to back.
		var spot := global_position + side * (1.4 if i % 2 == 0 else -1.4) + _heading * (0.8 - floori(i / 2.0) * 1.4)
		_territory.deliver_member(spot, player)


func _hit_whoever_we_bumped() -> void:
	if _speed < harmful_speed:
		return
	for i in get_slide_collision_count():
		var who := get_slide_collision(i).get_collider() as Citizen
		if who and not who.is_down and not _hit_cooldowns.has(who):
			_hit_cooldowns[who] = 1.0
			who.struck_by_vehicle(_heading * _speed)
			_speed *= 0.6


func _face(direction: Vector3) -> void:
	if direction.length() > 0.01:
		rotation.y = atan2(-direction.x, -direction.z)


func _player() -> Citizen:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	return player if player and not player.is_down else null


func _on_map() -> bool:
	return absf(global_position.x) < 45.0 and absf(global_position.z) < 33.0
