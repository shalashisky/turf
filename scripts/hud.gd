extends Label
## Controls cheat sheet and the current aim mode, for testing.

@export var player: Node


func _process(_delta: float) -> void:
	text = "WASD / left stick: move\n" \
		+ "Mouse / right stick: aim (auto-aim on attack otherwise)\n" \
		+ "LMB / J / X / RT: attack\n" \
		+ "Space / A: jump\n" \
		+ "Aim mode: %s\n" % player.aim_mode_name() \
		+ "Weapon: %s" % player.current_weapon().display_name
