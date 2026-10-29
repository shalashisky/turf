class_name Squatter
extends Npc
## Someone living rough in a place that isn't theirs, like the player's grow
## house before it's cleared out. Lounges about, and jumps whoever they're
## hostile to (Factions.SQUATTERS: the player and their crew) on sight.


func _ready() -> void:
	super()
	add_to_group("squatters")
	died.connect(func() -> void: remove_from_group("squatters"))


func _choose_move_direction(delta: float) -> Vector3:
	if _still_fighting() or _scan_for_hostiles(delta):
		return _fight(delta)
	return Vector3.ZERO
