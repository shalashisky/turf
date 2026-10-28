class_name MapBlip
extends Marker3D
## A marked place on the minimap, like home or the shop.

## One character shown inside the blip.
@export var label := "?"
@export var color := Color.WHITE


func _ready() -> void:
	add_to_group("map_blips")
