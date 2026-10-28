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
		+ "E / Y: interact\n" \
		+ "[ / ]: skip time back / ahead (debug)\n" \
		+ "Aim mode: %s\n" % player.aim_mode_name() \
		+ "Weapon: %s\n" % _weapon_text() \
		+ "Weed: %d   Seeds: %d   $%d" % [WorldState.item_count("weed"), WorldState.item_count("weed_seed"), WorldState.money]


func _weapon_text() -> String:
	var weapon: Weapon = player.current_weapon()
	if weapon.swing_style == Weapon.SwingStyle.SHOOT:
		return "%s  (%d shots)" % [weapon.display_name, player.ammo]
	return weapon.display_name
