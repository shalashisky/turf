extends Node3D
## The player's bed. Sleeping in it ends the day: it's morning, with full energy.


@onready var _use: Interactable = $Use


func _ready() -> void:
	_use.interacted.connect(_on_used)


func _on_used(_by: Citizen) -> void:
	if Dialogue.blocks_input() or DayCycle.busy:
		return
	var pick := await Dialogue.choose("", null, "Sleep until morning?", ["Sleep", "Not yet"])
	Dialogue.close()
	if pick == 0:
		DayCycle.sleep()
