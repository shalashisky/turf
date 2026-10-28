extends Control
## The hotbar along the bottom of the screen: the player's Inventory slots,
## each with its icon and how many (shots, bags, dollars), and the one in
## hand outlined. Picking a slot shows its name above the bar for a moment,
## with the day's price when it's weed.

const SLOT_SIZE := 52.0
const GAP := 6.0
const ICON_SIZE := 40.0
const NAME_TIME := 2.0
const SLOT_COLOR := Color(0.08, 0.08, 0.1, 0.75)
const BORDER_COLOR := Color(0.6, 0.6, 0.65, 0.9)
const SELECTED_COLOR := Color(1.0, 0.88, 0.55)

var _name_left := 0.0
var _name_text := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var width := Inventory.SLOTS * SLOT_SIZE + (Inventory.SLOTS - 1) * GAP
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -width * 0.5
	offset_right = width * 0.5
	offset_top = -SLOT_SIZE - 14.0
	offset_bottom = -14.0
	Inventory.changed.connect(queue_redraw)
	Inventory.selection_changed.connect(_show_name)
	_show_name()


func _process(delta: float) -> void:
	if _name_left > 0.0:
		_name_left -= delta
		queue_redraw()
	if _rush_left() > 0.0:
		queue_redraw()


func _rush_left() -> float:
	var player := get_tree().get_first_node_in_group("player")
	return player.get("rush_left") if player and player.get("rush_left") else 0.0


func _show_name() -> void:
	var stack: Variant = Inventory.selected_slot()
	_name_text = Inventory.name_of(stack)
	var item := Inventory.item_in(Inventory.selected)
	if item == "weed":
		_name_text += "  -  $%d a bag today, more on rival turf" % WorldState.weed_price()
	elif item in WorldState.CONSUMABLES:
		_name_text += "  -  attack (LMB / RT) to use"
	_name_left = NAME_TIME if _name_text != "" else 0.0
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for i in Inventory.SLOTS:
		var box := Rect2(Vector2(i * (SLOT_SIZE + GAP), 0.0), Vector2(SLOT_SIZE, SLOT_SIZE))
		draw_rect(box, SLOT_COLOR)
		var stack: Variant = Inventory.slots[i]
		var icon := Inventory.icon_of(stack)
		if icon:
			# Fitted in the slot, keeping its shape, pixels kept crisp.
			var scale := minf(ICON_SIZE / icon.get_width(), ICON_SIZE / icon.get_height())
			var icon_size := icon.get_size() * scale
			draw_texture_rect(icon, Rect2(box.get_center() - icon_size * 0.5, icon_size), false)
		var amount := Inventory.amount_of(stack)
		if amount >= 0:
			var text := ("$%d" % amount) if stack.has("cash") else str(amount)
			draw_string_outline(font, box.position + Vector2(3.0, SLOT_SIZE - 5.0), text, HORIZONTAL_ALIGNMENT_RIGHT, SLOT_SIZE - 6.0, 14, 4, Color.BLACK)
			draw_string(font, box.position + Vector2(3.0, SLOT_SIZE - 5.0), text, HORIZONTAL_ALIGNMENT_RIGHT, SLOT_SIZE - 6.0, 14, Color.WHITE)
		# Which key picks it: 1 to 9, then 0.
		draw_string(font, box.position + Vector2(4.0, 13.0), str((i + 1) % 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.5))
		var selected := i == Inventory.selected
		draw_rect(box, SELECTED_COLOR if selected else BORDER_COLOR, false, 3.0 if selected else 1.5)

	var rush := _rush_left()
	if rush > 0.0:
		var label := "RUSH  %ds" % ceili(rush)
		draw_string_outline(font, Vector2(0.0, -34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color.BLACK)
		draw_string(font, Vector2(0.0, -34.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.95, 1.0))

	if _name_left > 0.0 and _name_text != "":
		var alpha := clampf(_name_left / 0.4, 0.0, 1.0)
		var at := Vector2(0.0, -10.0)
		draw_string_outline(font, at, _name_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, 5, Color(0, 0, 0, alpha))
		draw_string(font, at, _name_text, HORIZONTAL_ALIGNMENT_CENTER, size.x, 18, Color(1, 1, 1, alpha))
