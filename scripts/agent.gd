class_name Agent
extends Pedestrian
## A CIA agent: dark suit, sunglasses, a pistol, and always a partner. One of
## the pair strolls the sidewalks; the other keeps a step behind. They don't
## run from fights. Attack either one and both come after you, and they stick
## up for each other against anyone else too.

## How close a fight involving their partner has to be for them to step in.
@export var backup_range := 18.0
## How far behind the leader the follower keeps.
@export var follow_distance := 1.1

## The agent this one follows. Null for the one in front.
var leader: Agent


func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim] or _still_fighting():
		return
	if global_position.distance_to(victim.global_position) > backup_range:
		return
	if _is_ally(victim) and not _is_ally(attacker) and not attacker.is_down:
		start_fighting(attacker)


func _react_to_hit(attacker: Citizen) -> void:
	if attacker and not is_down and not _is_ally(attacker):
		start_fighting(attacker)


func _choose_move_direction(delta: float) -> Vector3:
	if _still_fighting():
		return _fight(delta)
	if leader and is_instance_valid(leader) and not leader.is_down:
		return _follow_leader()
	leader = null
	return _stroll(delta) * minf(walk_speed / move_speed, 1.0)


func _follow_leader() -> Vector3:
	var spot := leader.global_position - leader.facing * follow_distance
	var to_spot := spot - global_position
	to_spot.y = 0.0
	if to_spot.length() < 0.3:
		facing = leader.facing
		return Vector3.ZERO
	# Walk at the leader's pace, hurrying a little to catch up.
	var pace := minf(walk_speed * (1.0 + to_spot.length() * 0.5) / move_speed, 1.0)
	return _steer_toward(spot) * pace
