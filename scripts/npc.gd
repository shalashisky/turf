class_name Npc
extends Citizen
## A computer-controlled citizen. Holds the AI that dummies, neighbors, and
## whoever comes later share: fighting a target (chase, wind up, swing),
## sticking up for their faction and going after hostile ones, and getting
## around safely (hopping up onto things, following drops, staying out of the
## water, climbing back out of it). Subclasses decide when to fight and what
## to do the rest of the time.

## How far ahead of the center to check the ground. Past the capsule's 0.3 m
## radius, so it stops with its whole body still on solid ground.
const PROBE_DISTANCE := 0.45
## How often to look around for hostile citizens, in seconds. Saves raycasts.
const HOSTILE_SCAN_INTERVAL := 0.5

## Won't step down ledges taller than this, unless heading for something below.
@export var max_safe_drop := 0.3

@export_group("Faction")
## Joins in when a friendly citizen within this range is attacked. 0 for never.
@export var defend_range := 15.0
## Attacks citizens of hostile factions it can see within this range. 0 for never.
@export var aggro_range := 0.0

@export_group("Fighting")
## Pause before each swing, stretched up tall, so the target sees it coming.
@export var attack_windup := 0.35
## Extra random wait between swings, on top of the weapon's cooldown.
@export var attack_delay_range := Vector2(0.2, 0.8)
## Start the windup once the target is within this fraction of the weapon's reach.
@export var engage_reach_factor := 0.8
## Chance of holding a guard up between swings, so attacks have to be timed.
@export_range(0.0, 1.0) var block_chance := 0.5
## How long that guard stays up, in seconds.
@export var block_time_range := Vector2(0.5, 1.2)

## Who we're fighting. Null when not fighting.
var target: Citizen

## Counts down during a windup. Negative when not winding up.
var _windup_left := -1.0
var _next_attack_wait := 0.0
var _block_left := 0.0
var _hostile_scan_left := 0.0


func _ready() -> void:
	super()
	add_to_group("npcs")
	_hostile_scan_left = randf() * HOSTILE_SCAN_INTERVAL


## Called through the "npcs" group whenever any citizen takes a hit. By
## default, joins in to defend a friendly victim. Subclasses react their own way.
func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim] or _still_fighting() or defend_range <= 0.0:
		return
	if global_position.distance_to(victim.global_position) > defend_range:
		return
	if _is_ally(victim) and not _is_ally(attacker) and not attacker.is_down:
		start_fighting(attacker)


func start_fighting(who: Citizen) -> void:
	target = who
	_next_attack_wait = randf_range(attack_delay_range.x, attack_delay_range.y)


func stop_fighting() -> void:
	target = null
	_windup_left = -1.0
	_block_left = 0.0
	set_blocking(false)


## Lets go of a target that's gone or down. Returns whether we still have one.
func _still_fighting() -> bool:
	if target and (not is_instance_valid(target) or target.is_down):
		stop_fighting()
	return target != null


## Every so often, picks a fight with the nearest hostile citizen in sight
## within aggro_range. Returns whether we're now fighting someone.
func _scan_for_hostiles(delta: float) -> bool:
	if aggro_range <= 0.0 or _still_fighting():
		return target != null
	_hostile_scan_left -= delta
	if _hostile_scan_left > 0.0:
		return false
	_hostile_scan_left = HOSTILE_SCAN_INTERVAL
	var best: Citizen = null
	var best_distance := aggro_range
	for other: Citizen in get_tree().get_nodes_in_group("citizens"):
		if other == self or other.is_down or not _attacks_on_sight(other):
			continue
		var distance := global_position.distance_to(other.global_position)
		if distance < best_distance and _can_see(other.global_position):
			best = other
			best_distance = distance
	if best:
		start_fighting(best)
	return best != null


## Whether to pick a fight with `other` just for being there. By default,
## anyone hostile.
func _attacks_on_sight(other: Citizen) -> bool:
	return is_hostile_to(other)


## Chase the target, then wind up and swing once in reach.
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
			# Sometimes cover up afterwards instead of standing there open.
			if randf() < block_chance:
				_block_left = randf_range(block_time_range.x, block_time_range.y)
		else:
			_squash(Vector2(0.88, 1.12))  # hold the stretched-up telegraph pose
		return Vector3.ZERO

	_block_left -= delta
	set_blocking(_block_left > 0.0)
	# Guns need a clear line of fire, so keep closing in until there is one.
	var in_range := distance <= attack_reach() * engage_reach_factor
	if in_range and can_shoot() and not _can_see(target.global_position):
		in_range = false
	if in_range:
		if _next_attack_wait <= 0.0 and _block_left <= 0.0 and can_attack():
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
	var allowed_drop := maxf(max_safe_drop, global_position.y - point.y + 0.5)
	return _clip_at_ledges(direction, allowed_drop)


## Straight away from `point`, swerving around drops and the water.
func _direction_away_from(point: Vector3) -> Vector3:
	var away := global_position - point
	away.y = 0.0
	if away.length() < 0.01:
		away = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0))
	away = away.normalized()
	if is_swimming:
		return away
	for turn in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75]:
		var direction := _clip_at_ledges(away.rotated(Vector3.UP, turn), max_safe_drop)
		if direction.length() > 0.5:
			return direction.normalized()
	return Vector3.ZERO


## Line of sight from our eyes to `point`, blocked by level geometry.
func _can_see(point: Vector3) -> bool:
	var eyes := global_position + Vector3.UP * 1.2
	var query := PhysicsRayQueryParameters3D.create(eyes, point + Vector3.UP * 0.8, WORLD_LAYER)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _has_ground_below(point: Vector3) -> bool:
	var from := point + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 3.0, WORLD_LAYER)
	return not get_world_3d().direct_space_state.intersect_ray(query).is_empty()


## Removes the parts of `motion` that would carry us over a drop deeper than
## `max_drop`. Each axis is checked on its own, so motion along an edge
## survives while motion over it is cut.
func _clip_at_ledges(motion: Vector3, max_drop: float) -> Vector3:
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var along := motion.dot(axis)
		if along != 0.0 and _ground_drop_at(axis * signf(along) * PROBE_DISTANCE) > max_drop:
			motion -= axis * along
	return motion


## How far the ground at `offset` sits below our feet. INF when there's no
## ground underneath, like over water, or when the spot is inside solid geometry.
func _ground_drop_at(offset: Vector3) -> float:
	var from := global_position + offset + Vector3.UP * 0.5
	var query := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 50.0, WORLD_LAYER)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return global_position.y - hit.position.y if hit else INF
