extends Control
## The player's energy, from WorldState, as a bar that turns red when it's low.

const LOW := 0.25
const FULL_COLOR := Color(0.95, 0.8, 0.25)
const LOW_COLOR := Color(0.95, 0.3, 0.2)

@onready var _bar: ProgressBar = $Bar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill").duplicate()


func _ready() -> void:
	_bar.add_theme_stylebox_override("fill", _fill)
	_bar.max_value = WorldState.MAX_ENERGY
	WorldState.energy_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	_bar.value = WorldState.energy
	_fill.bg_color = LOW_COLOR if WorldState.energy / WorldState.MAX_ENERGY <= LOW else FULL_COLOR
