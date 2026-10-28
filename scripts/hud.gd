extends Label
## Controls cheat sheet and the current aim mode, for testing.

@export var player: Node


func _process(_delta: float) -> void:
	text = "WASD / left stick: move\n" \
		+ "Mouse / right stick: aim (auto-aim on attack otherwise)\n" \
		+ "LMB / J / X / RT: attack\n" \
		+ "RMB / K / LT: block\n" \
		+ "Space / A: jump\n" \
		+ "E / Y: interact\n" \
		+ "[ / ]: skip time back / ahead (debug)\n" \
		+ "Aim mode: %s\n" % player.aim_mode_name() \
		+ "Weapon: %s\n" % player.current_weapon().display_name \
		+ "Weed: %d   Seeds: %d   $%d" % [WorldState.item_count("weed"), WorldState.item_count("weed_seed"), WorldState.money]
