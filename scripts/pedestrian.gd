class_name Pedestrian
extends Npc
## Someone out for a walk. Strolls along the sidewalks, turning at corners and
## now and then crossing the street, and runs from any fight that breaks out
## nearby, or from the player while a turf war is on. Once it's calm, they
## make their way back to the nearest sidewalk. They're nobody's neighbor, so
## safe doors won't take them in.

const DIRECTIONS: Array[Vector3] = [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]
## How far around to look for a sidewalk to get back to, in tiles.
const SIDEWALK_SEARCH_RADIUS := 8
## Walkers keep this far right of the middle of the sidewalk, so people going
## opposite ways pass each other.
const LANE_OFFSET := 0.26
## Stuck this long against someone or something, they turn around.
const STUCK_TIME := 0.8

## Strolling speed. move_speed is how fast they run.
@export var walk_speed := 1.4
## How close a fight has to be for them to notice it.
@export var notice_range := 14.0
## How long they keep running after the last thing that scared them.
@export var flee_time := 6.0
## Chance of crossing the street at the end of a stretch of sidewalk, instead of turning.
@export_range(0.0, 1.0) var cross_chance := 0.35
## Chance of stopping for a moment whenever they turn.
@export_range(0.0, 1.0) var pause_chance := 0.2

var _grid: CityGrid
var _dir := Vector3.ZERO
var _crossing := false
var _pause_left := 0.0
var _flee_from := Vector3.ZERO
var _flee_left := 0.0
## A sidewalk tile to head back to after running off it.
var _way_back := Vector3.INF
var _stuck_time := 0.0


func _ready() -> void:
	super()
	_grid = get_tree().get_first_node_in_group("city_grid")
	_pause_left = randf_range(0.0, 2.0)


## Pedestrians don't fight: whoever's fighting near them, they run.
func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim]:
		return
	if global_position.distance_to(victim.global_position) <= notice_range:
		_flee(victim.global_position)


func _react_to_hit(attacker: Citizen) -> void:
	if attacker and not is_down:
		_flee(attacker.global_position)


func _flee(from: Vector3) -> void:
	_flee_from = from
	_flee_left = flee_time
	_crossing = false
	_way_back = Vector3.INF


func _choose_move_direction(delta: float) -> Vector3:
	_keep_away_from_turf_wars()
	if _flee_left > 0.0:
		_flee_left -= delta
		return _direction_away_from(_flee_from)
	return _stroll(delta) * minf(walk_speed / move_speed, 1.0)


func _keep_away_from_turf_wars() -> void:
	for war in get_tree().get_nodes_in_group("turf_wars"):
		if war.active:
			var player := get_tree().get_first_node_in_group("player") as Node3D
			if player and global_position.distance_to(player.global_position) < notice_range:
				_flee(player.global_position)
			return


func _stroll(delta: float) -> Vector3:
	if _grid == null:
		return Vector3.ZERO
	if _pause_left > 0.0:
		_pause_left -= delta
		return Vector3.ZERO
	var here := _grid.tile_at(global_position)
	if here != CityGrid.SIDEWALK and not _crossing:
		return _head_back_to_sidewalk()
	_way_back = Vector3.INF

	if _dir == Vector3.ZERO:
		_dir = _pick_direction()
		if _dir == Vector3.ZERO:
			return Vector3.ZERO
	# Wedged against someone coming the other way, or a lamp post: turn back.
	if Vector2(velocity.x, velocity.z).length() < 0.3:
		_stuck_time += delta
		if _stuck_time > STUCK_TIME:
			_stuck_time = 0.0
			_crossing = false
			_dir = -_dir
	else:
		_stuck_time = 0.0
	var ahead := _grid.tile_at(global_position + _dir * 0.8)
	if _crossing:
		if here == CityGrid.SIDEWALK and ahead != CityGrid.ROAD:
			_crossing = false  # made it across
		elif ahead != CityGrid.ROAD and ahead != CityGrid.SIDEWALK:
			_crossing = false
			_dir = _pick_direction()
	elif ahead != CityGrid.SIDEWALK:
		# End of this stretch: cross the street, or turn the corner.
		if ahead == CityGrid.ROAD and randf() < cross_chance and _street_ends_in_sidewalk():
			_crossing = true
		else:
			_dir = _pick_direction()
			if randf() < pause_chance:
				_pause_left = randf_range(1.0, 3.0)
			return Vector3.ZERO
	return (_dir + _stay_in_lane()).normalized()


## A sidewalk to turn onto from here: anything but straight back, unless
## that's the only way.
func _pick_direction() -> Vector3:
	var options: Array[Vector3] = []
	for direction in DIRECTIONS:
		if direction != -_dir and _grid.tile_at(global_position + direction) == CityGrid.SIDEWALK:
			options.append(direction)
	if options.is_empty() and _grid.tile_at(global_position - _dir) == CityGrid.SIDEWALK:
		options.append(-_dir)
	return options.pick_random() if not options.is_empty() else Vector3.ZERO


## Whether walking straight across the road ahead lands on another sidewalk.
func _street_ends_in_sidewalk() -> bool:
	for distance in range(2, 6):
		var tile := _grid.tile_at(global_position + _dir * distance)
		if tile != CityGrid.ROAD:
			return tile == CityGrid.SIDEWALK
	return false


## A nudge toward the right-hand side of the sidewalk, sideways to the walk.
func _stay_in_lane() -> Vector3:
	var right := Vector3(-_dir.z, 0.0, _dir.x)
	var lane := _grid.tile_center(global_position) + right * LANE_OFFSET
	var offset := lane - global_position
	return offset * right.abs() * 2.0


func _head_back_to_sidewalk() -> Vector3:
	if _way_back == Vector3.INF:
		_way_back = _nearest_sidewalk()
		if _way_back == Vector3.INF:
			return Vector3.ZERO
	_dir = Vector3.ZERO
	return _steer_toward(_way_back)


func _nearest_sidewalk() -> Vector3:
	for radius in range(1, SIDEWALK_SEARCH_RADIUS + 1):
		var best := Vector3.INF
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dz)) != radius:
					continue
				var spot := global_position + Vector3(dx, 0.0, dz)
				if _grid.tile_at(spot) == CityGrid.SIDEWALK:
					var center := _grid.tile_center(spot)
					if best == Vector3.INF or global_position.distance_to(center) < global_position.distance_to(best):
						best = center
		if best != Vector3.INF:
			return best
	return Vector3.INF
