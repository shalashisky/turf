extends Label
## Whose turf the player is standing on, in that gang's color.

var _check_left := 0.0


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0:
		return
	_check_left = 0.25
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var turf: Territory = null
	if player:
		for candidate: Territory in get_tree().get_nodes_in_group("territories"):
			if candidate.contains(player.global_position):
				turf = candidate
	visible = turf != null
	if turf:
		var gang := turf.owner_faction()
		text = "Your turf" if gang == Factions.PLAYER else "%s turf" % Factions.display_name(gang)
		# Black on a dark street is unreadable, so lighten the panthers' color.
		add_theme_color_override("font_color", turf.color().lerp(Color.WHITE, 0.35 if gang == Factions.PANTHERS else 0.0))
