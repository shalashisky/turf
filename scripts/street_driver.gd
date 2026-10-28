class_name StreetDriver
extends RefCounted
## Drives a Vehicle around town, the way traffic does: keeps to the right-hand
## lane of the streets that run across the whole city, and at each crossing
## goes straight on or turns. Slows down for turns and stops for anything in
## the way. It pulls out around parked cars and wrecks, and if it's held up
## too long by anything else, it loses patience and creeps on through.
##
## Call tick() every physics step: it sets the car's heading and speed, and
## the car moves itself (Vehicle._drive_step()). Used by TrafficCar, and by
## anyone who takes a car (Vehicle.hijack()).

## How far ahead of itself it aims, along its lane. Bigger turns wider.
const LOOKAHEAD := 3.5
## Starts turning this far before the middle of the new lane.
const TURN_EARLY := 2.5
## Half the width of the lane it watches for things in the way.
const PATH_HALF_WIDTH := 1.2
## Stopped for something this long, it creeps on regardless.
const PATIENCE := 4.0
## How fast it creeps on when it's lost patience.
const CREEP_SPEED := 2.0
## Stopped behind a car that isn't going anywhere this long, it goes around.
const OVERTAKE_AFTER := 1.0
## Stuck against something with nothing in the way ahead this long (a wall,
## a car side-on), it backs up for BACK_UP_TIME and tries again.
const STUCK_TIME := 1.2
const BACK_UP_TIME := 0.8

var cruise_speed := 9.0
var turn_speed := 5.0
var flee_speed := 15.0
var acceleration := 6.0
var braking := 14.0
## Turning rate at full lock, in radians per second.
var steering := 2.4
var turn_chance := 0.4
## In a hurry: full speed, and no slowing down for turns.
var fleeing := false

var _car: Vehicle
var _grid: CityGrid
## Down the middle of the street it's on: a point on it, and which way.
var _street_point: Vector3
var _direction: Vector3
## The next crossing street, as a point on it, and what we'll do there.
var _next_turn := Vector3.ZERO
var _next_crossing := Vector3.INF
var _waited := 0.0
var _pushing_through := 0.0
## Whatever's nearest in our lane ahead, if anything.
var _blocker: Node3D
## A stopped car we're going around in the other lane.
var _overtaking: Vehicle
var _waited_for_parked := 0.0
var _stuck := 0.0
var _backing_up := 0.0


## Drives `car` along the street through `street_point` in `direction` (one
## of the four flat axes). Without them, it picks up the nearest street going
## roughly the way the car is pointed.
func _init(car: Vehicle, street_point := Vector3.INF, direction := Vector3.ZERO) -> void:
	_car = car
	_grid = car.get_tree().get_first_node_in_group("city_grid")
	if street_point == Vector3.INF:
		_join_nearest_street()
	else:
		_street_point = street_point
		_direction = direction
	_plan_next_crossing()


func tick(delta: float) -> void:
	var position := _car.global_position
	# Take the turn once we're nearly at the new lane.
	if _next_crossing != Vector3.INF and _next_turn != Vector3.ZERO:
		var new_lane := _next_crossing + right_of(_next_turn) * CityGrid.LANE_OFFSET
		if (new_lane - position).dot(_direction) <= TURN_EARLY:
			_street_point = _next_crossing
			_direction = _next_turn
			_plan_next_crossing()
	elif _next_crossing != Vector3.INF and (position - _next_crossing).dot(_direction) > CityGrid.LANE_OFFSET * 2.0:
		_plan_next_crossing()

	_update_overtaking(delta)
	# Steer for a point a little way down our lane, or the other one to get
	# around something.
	var lane := -CityGrid.LANE_OFFSET if _overtaking else CityGrid.LANE_OFFSET
	var lane_point := _street_point + right_of(_direction) * lane
	var along := (position - lane_point).dot(_direction)
	var aim_at := lane_point + _direction * (along + LOOKAHEAD)
	var wanted := aim_at - position
	wanted.y = 0.0
	if wanted.length() > 0.1:
		var angle := _car.heading.signed_angle_to(wanted.normalized(), Vector3.UP)
		_car.heading = _car.heading.rotated(Vector3.UP, clampf(angle, -steering * delta, steering * delta))

	var target_speed := flee_speed if fleeing else cruise_speed
	if _next_turn != Vector3.ZERO and not fleeing and (_next_crossing - position).dot(_direction) < 12.0:
		target_speed = minf(target_speed, turn_speed)
	target_speed = minf(target_speed, _room_ahead())
	# Wedged against something: back up a little and have another go.
	if target_speed > 1.0 and absf(_car.speed) < 0.3 and _backing_up <= 0.0:
		_stuck += delta
		if _stuck > STUCK_TIME:
			_stuck = 0.0
			_backing_up = BACK_UP_TIME
	else:
		_stuck = 0.0
	if _backing_up > 0.0:
		_backing_up -= delta
		target_speed = -2.5
	var rate := acceleration if target_speed > _car.speed else braking
	_car.speed = move_toward(_car.speed, target_speed, rate * delta)

	# Waiting too long behind something: push on through for a bit.
	if _car.speed < 0.5 and target_speed < 0.5:
		_waited += delta
		if _waited > PATIENCE:
			_pushing_through = 1.5
			_waited = 0.0
	else:
		_waited = 0.0
	_pushing_through = maxf(_pushing_through - delta, 0.0)


## Stopped behind other traffic, rather than parked.
func waiting_in_line() -> bool:
	return is_instance_valid(_blocker) and _blocker is Vehicle and _blocker.street_driver != null and not _overtaking


## Stops planning a turn: straight on from here.
func go_straight() -> void:
	_next_turn = Vector3.ZERO


func _update_overtaking(delta: float) -> void:
	if _overtaking:
		# Back in our lane once it's well behind us.
		if not is_instance_valid(_overtaking) or (_overtaking.global_position - _car.global_position).dot(_direction) < -4.5:
			_overtaking = null
		return
	if not is_instance_valid(_blocker):
		_blocker = null
	var parked := _blocker as Vehicle
	var in_line := parked != null and parked.street_driver != null and parked.street_driver.waiting_in_line()
	if parked and absf(parked.speed) < 0.5 and _car.speed < 1.0 and not in_line:
		_waited_for_parked += delta
		if _waited_for_parked > OVERTAKE_AFTER:
			_overtaking = parked
			_waited_for_parked = 0.0
	else:
		_waited_for_parked = 0.0


## How fast it can go and still stop for whatever is in its lane ahead.
func _room_ahead() -> float:
	var heading := _car.heading
	var look := 4.0 + absf(_car.speed) * 0.9
	var nearest := INF
	_blocker = null
	for group in ["citizens", "vehicles"]:
		for thing: Node3D in _car.get_tree().get_nodes_in_group(group):
			# Anyone up on a car roof isn't in the road.
			if thing == _car or thing == _overtaking or thing.global_position.y > Vehicle.ROOF_HEIGHT:
				continue
			var offset := thing.global_position - _car.global_position
			var ahead := offset.dot(heading)
			if ahead <= 0.0 or ahead > look + 2.5:
				continue
			if absf(offset.dot(right_of(heading))) < PATH_HALF_WIDTH and ahead < nearest:
				nearest = ahead
				_blocker = thing
	if nearest == INF:
		return INF
	if _pushing_through > 0.0:
		return CREEP_SPEED
	# Pull up about 4 m short: the car's half length plus room to spare.
	return maxf((nearest - 4.0) * 1.6, 0.0)


func _join_nearest_street() -> void:
	var position := _car.global_position
	var heading := _car.heading
	var best := INF
	for street in _grid.streets() if _grid else []:
		var along := Vector3.RIGHT if street.along_x else Vector3.BACK
		var away: float = absf((position.z if street.along_x else position.x) - street.line)
		# Prefer streets the car is already pointed along.
		away += (1.0 - absf(heading.dot(along))) * 6.0
		if away < best:
			best = away
			_direction = along if heading.dot(along) >= 0.0 else -along
			_street_point = Vector3(position.x, 0.0, street.line) if street.along_x else Vector3(street.line, 0.0, position.z)


func _plan_next_crossing(turned_around := false) -> void:
	_next_crossing = Vector3.INF
	_next_turn = Vector3.ZERO
	if _grid == null or _direction == Vector3.ZERO:
		return
	# The nearest crossing street ahead of us, and whether there's another past it.
	var here := _car.global_position.dot(_direction)
	var crossings: Array[float] = []
	for street in _grid.streets():
		# Streets across ours run along the other axis.
		if street.along_x == (absf(_direction.x) > 0.5):
			continue
		var at: float = street.line * (_direction.x + _direction.z)
		if at - here > CityGrid.LANE_OFFSET * 2.0:
			crossings.append(at)
	if crossings.is_empty():
		# The end of the line, at the edge of town: turn around.
		if not turned_around:
			_direction = -_direction
			_plan_next_crossing(true)
		return
	crossings.sort()
	var at := crossings[0]
	# A point where the crossing street meets ours.
	var flat_street := Vector3(_street_point.x, 0.0, _street_point.z)
	_next_crossing = flat_street - _direction * flat_street.dot(_direction) + _direction * at
	var last_one := crossings.size() == 1
	if last_one or randf() < turn_chance:
		_next_turn = right_of(_direction) if randf() < 0.5 else -right_of(_direction)


static func right_of(direction: Vector3) -> Vector3:
	return Vector3(-direction.z, 0.0, direction.x)
