extends Npc
## Target-practice dummy. Wanders aimlessly until someone hits one of them.
## The one that got hit fights back, and every dummy not already in a fight
## joins in against the attacker, until they're down. An unarmed dummy that
## spots a weapon lying around while fighting goes and grabs it first. Won't
## walk off ledges by itself, but can be shoved off them, water included.

## How often to look around for weapons, in seconds. Saves raycasts.
const WEAPON_SCAN_INTERVAL := 0.25
const CASH_PICKUP := preload("res://scenes/cash_pickup.tscn")
@export_group("Wandering")
@export var wander_speed := 1.5
@export var idle_time_range := Vector2(1.0, 3.0)
@export var walk_time_range := Vector2(1.5, 4.0)

@export_group("Loot")
## Chance of dropping cash on death, and how much.
@export_range(0.0, 1.0) var cash_drop_chance := 0.6
@export var cash_range := Vector2i(5, 20)

@export_group("Weapons")
## Unarmed dummies notice weapon pickups within this distance, if nothing blocks the view.
@export var weapon_sight_range := 8.0
## Also go for weapons while calmly wandering, not just mid-fight.
@export var grab_weapons_while_calm := false

var _wander_dir := Vector3.ZERO
var _state_time_left := 0.0
## Scripted walk, like stepping out of a spawn door, that overrides the AI.
var _walk_out_dir := Vector3.ZERO
var _walk_out_left := 0.0
## The weapon pickup we're heading for, if any.
var _wanted_pickup: WeaponPickup
var _weapon_scan_left := 0.0


func _ready() -> void:
	super()
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)
	died.connect(_on_died)


func hit(attacker: Citizen, weapon: Weapon) -> void:
	super(attacker, weapon)
	if attacker == null or _is_ally(attacker):
		return
	# Always turn on whoever hit us. The rest only join if they're free.
	if not is_down:
		start_fighting(attacker)
		_wander_dir = Vector3.ZERO
	get_tree().call_group("enemies", "provoke", attacker)
	get_tree().call_group("spawn_doors", "activate", attacker)
	if attacker.is_in_group("player"):
		get_tree().call_group("turf_wars", "start")


func _on_died() -> void:
	get_tree().call_group("turf_wars", "count_kill")
	if randf() < cash_drop_chance:
		var cash: CashPickup = CASH_PICKUP.instantiate()
		cash.amount = randi_range(cash_range.x, cash_range.y)
		var parent := get_parent() as Node3D
		cash.position = parent.to_local(global_position) if parent else global_position
		# Deferred: this can run inside a physics callback, where adding an Area3D isn't allowed.
		get_parent().add_child.call_deferred(cash)


## Join the fight against `attacker`, unless already busy fighting someone.
func provoke(attacker: Citizen) -> void:
	if is_down or _still_fighting():
		return
	start_fighting(attacker)
	_wander_dir = Vector3.ZERO


## Walk straight along `direction` for `duration` seconds before the AI takes over.
func walk_out(direction: Vector3, duration: float) -> void:
	_walk_out_dir = direction.normalized()
	_walk_out_left = duration


func push(push_velocity: Vector3) -> void:
	super(push_velocity)
	# Being shoved interrupts whatever it was doing.
	if _wander_dir != Vector3.ZERO:
		_stop_wandering()


## Only empty-handed dummies take weapons, and only when they're looking for one.
func wants_weapon(_weapon: Weapon) -> bool:
	return equipped_weapon == null and (target != null or grab_weapons_while_calm)


func _is_ally(other: Citizen) -> bool:
	return other.is_in_group("enemies")


func _choose_move_direction(delta: float) -> Vector3:
	if _walk_out_left > 0.0:
		_walk_out_left -= delta
		return _walk_out_dir * minf(wander_speed / move_speed, 1.0)
	var fighting := _still_fighting()
	if _windup_left < 0.0 and _update_wanted_pickup(delta):
		return _fetch_weapon()
	return _fight(delta) if fighting else _wander(delta)


## Keeps _wanted_pickup pointing at a weapon we can see and still want.
## Returns whether there is one.
func _update_wanted_pickup(delta: float) -> bool:
	if _wanted_pickup and (not is_instance_valid(_wanted_pickup) or not _wanted_pickup.is_available_to(self)):
		_wanted_pickup = null
	if not wants_weapon(null):
		_wanted_pickup = null
		return false
	# Look around again every so often, so a closer weapon wins.
	_weapon_scan_left -= delta
	if _weapon_scan_left <= 0.0:
		_weapon_scan_left = WEAPON_SCAN_INTERVAL
		_wanted_pickup = _find_visible_pickup()
	return _wanted_pickup != null


func _find_visible_pickup() -> WeaponPickup:
	var best: WeaponPickup = null
	var best_distance := weapon_sight_range
	for pickup: WeaponPickup in get_tree().get_nodes_in_group("weapon_pickups"):
		var distance := global_position.distance_to(pickup.global_position)
		if distance < best_distance and pickup.is_available_to(self) \
				and _can_see(pickup.global_position) and _has_ground_below(pickup.global_position):
			best = pickup
			best_distance = distance
	return best


func _fetch_weapon() -> Vector3:
	# Grab it once close, even if we were already standing on it.
	if _flat_offset_to(_wanted_pickup).length() < 0.6 and _wanted_pickup.try_give_to(self):
		_wanted_pickup = null
		return Vector3.ZERO
	return _steer_toward(_wanted_pickup.global_position)


func _wander(delta: float) -> Vector3:
	_state_time_left -= delta
	if _state_time_left <= 0.0:
		if _wander_dir == Vector3.ZERO:
			var angle := randf() * TAU
			_wander_dir = Vector3(sin(angle), 0.0, cos(angle))
			_state_time_left = randf_range(walk_time_range.x, walk_time_range.y)
		else:
			_stop_wandering()

	if _wander_dir != Vector3.ZERO:
		if is_swimming:
			if is_on_wall():
				request_jump()  # try to climb out
		elif is_on_wall() or _clip_at_ledges(_wander_dir, max_safe_drop) != _wander_dir:
			_stop_wandering()
	# Wandering is a stroll, slower than the chase speed in move_speed.
	return _wander_dir * minf(wander_speed / move_speed, 1.0)


func _stop_wandering() -> void:
	_wander_dir = Vector3.ZERO
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)
