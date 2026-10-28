class_name Cop
extends Pedestrian
## A beat cop. Walks the sidewalks like anyone else and never starts a fight,
## but steps in when they see one: against gangsters fighting anyone, against
## whoever attacks someone they protect, and against the player if they see
## the player hurt anyone but a gangster. They stay
## after the player as long as Factions says the player is wanted.

## How close a fight has to be for them to see it.
@export var witness_range := 16.0


func is_hostile_to(other: Citizen) -> bool:
	if other.is_in_group("player"):
		return Factions.is_player_wanted()
	return super(other)


## A wanted player's not getting away in a car.
func _pulls_out_of_cars(who: Citizen) -> bool:
	return who.is_in_group("player") and Factions.is_player_wanted()


func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim]:
		return
	if global_position.distance_to(victim.global_position) > witness_range:
		return
	if attacker.is_in_group("player"):
		# Beating on gangsters is fine by them. Anyone else is a crime.
		if not Factions.is_gang(victim.faction):
			Factions.report_player_crime()
			start_fighting(attacker)
		return
	if not _still_fighting() and not _is_ally(attacker) and (_is_ally(victim) or is_hostile_to(attacker)):
		start_fighting(attacker)


func _react_to_hit(attacker: Citizen) -> void:
	if attacker == null or is_down:
		return
	if attacker.is_in_group("player"):
		Factions.report_player_crime()
	start_fighting(attacker)


func _choose_move_direction(delta: float) -> Vector3:
	# Let the player go once they're no longer wanted.
	if target and target.is_in_group("player") and not Factions.is_player_wanted():
		stop_fighting()
	if _still_fighting() or _scan_for_hostiles(delta):
		return _fight(delta)
	return _stroll(delta) * minf(walk_speed / move_speed, 1.0)
