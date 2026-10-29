extends CanvasLayer
## Pauses the game and shows the whole city map, with each turf in the color
## of whoever holds it, home, the shop, the garage, the player's car, and the
## player. Opened and closed with the "pause" action (Esc, P, or Start).
## Indoors there's no map to show, just the menu.

const MAP_COLOR_SQUARE := 14

var _root: Control
var _map: Control
var _no_map: Label
var _legend: HBoxContainer
var _resume: Button


func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	_root.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _root.visible:
		close()
	elif not Dialogue.blocks_input() and not Transition.busy:
		open()
	get_viewport().set_input_as_handled()


func open() -> void:
	get_tree().paused = true
	_map.refresh()
	var has_map := _map._texture != null
	_map.visible = has_map
	_no_map.visible = not has_map
	_fill_legend()
	_root.show()
	_resume.grab_focus()


func close() -> void:
	_root.hide()
	get_tree().paused = false


func _fill_legend() -> void:
	for child in _legend.get_children():
		child.queue_free()
	var holders: Array[StringName] = []
	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		if turf.owner_faction() not in holders:
			holders.append(turf.owner_faction())
	for holder in holders:
		var swatch := ColorRect.new()
		swatch.color = Factions.COLORS.get(holder, Color.GRAY)
		swatch.custom_minimum_size = Vector2(MAP_COLOR_SQUARE, MAP_COLOR_SQUARE)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_legend.add_child(swatch)
		var name_label := Label.new()
		name_label.text = "You" if holder == Factions.PLAYER else Factions.display_name(holder)
		_legend.add_child(name_label)
	var places := Label.new()
	places.text = "   H home   $ shop   G garage   C your car"
	for neighbor: Neighbor in get_tree().get_nodes_in_group("all_neighbors"):
		places.text += "   %s %s" % [neighbor.display_name.left(1), neighbor.display_name]
	_legend.add_child(places)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	column.add_child(title)

	_map = load("res://scripts/minimap.gd").new()
	_map.whole_map = true
	_map.custom_minimum_size = Vector2(700, 540)
	column.add_child(_map)
	_no_map = Label.new()
	_no_map.text = "No map indoors."
	_no_map.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_no_map.custom_minimum_size = Vector2(400, 80)
	column.add_child(_no_map)

	_legend = HBoxContainer.new()
	_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	_legend.add_theme_constant_override("separation", 6)
	column.add_child(_legend)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	_resume = Button.new()
	_resume.text = "Resume"
	_resume.custom_minimum_size = Vector2(140, 0)
	_resume.pressed.connect(close)
	buttons.add_child(_resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(140, 0)
	quit.pressed.connect(get_tree().quit)
	buttons.add_child(quit)
