extends Label
## Controls cheat sheet and the player's state, for testing.

var player: Citizen


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		player = get_tree().get_first_node_in_group("player")
		if player == null:
			return
	text = "WASD / left stick: move\n" \
		+ "Mouse / right stick: aim (auto-aim on attack otherwise)\n" \
		+ "LMB / J / X / RT: attack\n" \
		+ "RMB / K / LT: block\n" \
		+ "Space / A: jump\n" \
		+ "E / Y: interact (get in and out of cars, hijack occupied ones)\n" \
		+ "In the car: RT / W drive, LT / S brake, left / right steer\n" \
		+ "[ / ]: skip time back / ahead (debug)\n" \
		+ "R: toggle rain (debug)\n" \
		+ "Esc / P / Start: pause, with the full map\n" \
		+ "1-0 / wheel / LB RB: pick from the hotbar\n" \
		+ "Aim mode: %s" % player.aim_mode_name()

