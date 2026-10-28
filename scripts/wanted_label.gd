extends Label
## "WANTED" while the police are after the player, with the seconds left.


func _process(_delta: float) -> void:
	visible = Factions.is_player_wanted()
	if visible:
		text = "WANTED  %d" % ceili(Factions.wanted_seconds_left())
		# Blink.
		modulate.a = 0.6 + 0.4 * absf(sin(Time.get_ticks_msec() / 250.0))
