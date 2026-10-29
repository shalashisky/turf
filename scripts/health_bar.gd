extends Control
## The player's health, as a bar with the numbers beside the label. Flashes
## when they take a hit, and darkens toward the end.

const LOW := 0.25
const FULL_COLOR := Color(0.85, 0.18, 0.22)
const LOW_COLOR := Color(0.6, 0.08, 0.1)
const HIT_COLOR := Color(1.0, 0.95, 0.9)

var _shown := -1
var _flash: Tween

@onready var _label: Label = $Label
@onready var _bar: ProgressBar = $Bar
@onready var _fill: StyleBoxFlat = _bar.get_theme_stylebox("fill").duplicate()


func _ready() -> void:
	_bar.add_theme_stylebox_override("fill", _fill)
	_fill.bg_color = FULL_COLOR


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null or player.health == _shown:
		return
	var hurt := _shown >= 0 and player.health < _shown
	_shown = player.health
	_bar.max_value = player.max_health
	_bar.value = player.health
	_label.text = "HEALTH  %d/%d" % [player.health, player.max_health]
	var color := LOW_COLOR if float(player.health) / player.max_health <= LOW else FULL_COLOR
	if _flash:
		_flash.kill()
	if hurt:
		_fill.bg_color = HIT_COLOR
		_flash = create_tween()
		_flash.tween_property(_fill, "bg_color", color, 0.3)
	else:
		_fill.bg_color = color
