extends Citizen
## Target-practice dummy. Wanders aimlessly until someone hits one of them,
## then every dummy turns on the attacker: chases them down, winds up, and
## swings, until the attacker dies. An unarmed dummy that spots a weapon lying
## around while fighting goes and grabs it first. Won't walk off ledges by itself but can be
## shoved off them, water included. While swimming it tries to jump out
## whenever it bumps into something.

## How often to look around for weapons, in seconds. Saves raycasts.
const WEAPON_SCAN_INTERVAL := 0.25
## How far ahead of the dummy's center to check the ground. Past the capsule's
## 0.3 m radius, so it stops with its whole body still on solid ground.
const PROBE_DISTANCE := 0.45

@export_group("Wandering")
@export var wander_speed := 1.5
@export var idle_time_range := Vector2(1.0, 3.0)
@export var walk_time_range := Vector2(1.5, 4.0)
## Won't step down ledges taller than this, unless chasing someone below.
@export var max_wander_drop := 0.3

@export_group("Fighting")
## Pause before each swing, stretched up tall, so the target sees it coming.
@export var attack_windup := 0.35
## Extra random wait between swings, on top of the weapon's cooldown.
@export var attack_delay_range := Vector2(0.2, 0.8)
## Start the windup once the target is within this fraction of the weapon's reach.
@export var engage_reach_factor := 0.8

@export_group("Weapons")
## Unarmed dummies notice weapon pickups within this distance, if nothing blocks the view.
@export var weapon_sight_range := 8.0
## Also go for weapons while calmly wandering, not just mid-fight.
@export var grab_weapons_while_calm := false

## Who we're fighting. Null while wandering.
var target: Citizen

var _wander_dir := Vector3.ZERO
var _state_time_left := 0.0
## Counts down during a windup. Negative when not winding up.
var _windup_left := -1.0
var _next_attack_wait := 0.0
## Scripted walk, like stepping out of a spawn door, that overrides the AI.
var _walk_out_dir := Vector3.ZERO
var _walk_out_left := 0.0
## The weapon pickup we're heading for, if any.
var _wanted_pickup: WeaponPickup
var _weapon_scan_left := 0.0


func _ready() -> void:
	super()
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)


func hit(attacker: Citizen, weapon: Weapon) -> void:
	super(attacker, weapon)
	if attacker and not _is_ally(attacker):
		get_tree().call_group("enemies", "provoke", attacker)
		get_tree().call_group("spawn_doors", "activate", attacker)


## Turn on `attacker` and fight them until they're dead.
func provoke(attacker: Citizen) -> void:
	if is_dead or attacker == target:
		return
	target = attacker
	_wander_dir = Vector3.ZERO
	_next_attack_wait = randf_range(attack_delay_range.x, attack_delay_range.y)


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
	if target and (not is_instance_valid(target) or target.is_dead):
		target = null
		_windup_left = -1.0
	if _windup_left < 0.0 and _update_wanted_pickup(delta):
		return _fetch_weapon()
	return _fight(delta) if target else _wander(delta)


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


func _fight(delta: float) -> Vector3:
	var to_target := _flat_offset_to(target)
	var distance := to_target.length()
	if distance > 0.01:
		facing = to_target / distance
	_next_attack_wait -= delta

	if _windup_left >= 0.0:
		_windup_left -= delta
		if _windup_left < 0.0:
			attack()
			_next_attack_wait = current_weapon().cooldown + randf_range(attack_delay_range.x, attack_delay_range.y)
		else:
			_squash(Vector2(0.88, 1.12))  # hold the stretched-up telegraph pose
		return Vector3.ZERO

	if distance <= current_weapon().reach * engage_reach_factor:
		if _next_attack_wait <= 0.0 and can_attack():
			_windup_left = attack_windup
		return Vector3.ZERO

	return _steer_toward(target.global_position)


## Direction to walk to reach `point`: hops up onto things in the way,
## follows drops down to it, never walks into the water, and tries to climb
## out when swimming.
func _steer_toward(point: Vector3) -> Vector3:
	var offset := point - global_position
	offset.y = 0.0
	if offset.length() < 0.01:
		return Vector3.ZERO
	var direction := offset.normalized()
	if is_swimming:
		if is_on_wall():
			request_jump()  # try to climb out
		return direction
	if point.y > global_position.y + 0.5:
		if is_on_wall():
			request_jump()
		return direction
	var allowed_drop := maxf(max_wander_drop, global_position.y - point.y + 0.5)
	return _clip_at_ledges(direction, allowed_drop)


## Line of sight from our eyes to `point`, blocked by level geometry.
func _can_see(point: Vector3) -> bool:
	var eyes := global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(eyes, point + Vector3.UP * 0.8, WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _has_ground_below(point: Vector3) -> bool:
	var from := point + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, WORLD_LAYER)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


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
		elif is_on_wall() or _clip_at_ledges(_wander_dir, max_wander_drop) != _wander_dir:
			_stop_wandering()
	# Wandering is a stroll, slower than the chase speed in move_speed.
	return _wander_dir * minf(wander_speed / move_speed, 1.0)


func _stop_wandering() -> void:
	_wander_dir = Vector3.ZERO
	_state_time_left = randf_range(idle_time_range.x, idle_time_range.y)


## Removes the parts of `motion` that would carry the dummy over a drop deeper
## than `max_drop`. Each axis is checked on its own, so motion along an edge
## survives while motion over it is cut.
func _clip_at_ledges(motion: Vector3, max_drop: float) -> Vector3:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var along := motion.dot(axis)
		if along != 0.0 and _ground_drop_at(axis * signf(along) * PROBE_DISTANCE) > max_drop:
			motion -= axis * along
	return motion


## How far the ground at `offset` sits below the dummy's feet. INF when there's
## no ground underneath, like over water, or when the spot is inside solid geometry.
func _ground_drop_at(offset: Vector3) -> float:
	var from := global_position + offset + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 50.0, WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return global_position.y - hit.position.y if hit else INF
