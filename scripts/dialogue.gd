extends CanvasLayer
## Visual-novel style dialogue box, autoloaded as Dialogue.
##
## Conversations are plain GDScript with await, so they can branch however
## they like:
##     await Dialogue.say("Rap Dawg", portrait, "Hey man")
##     var pick := await Dialogue.choose("Rap Dawg", portrait, "Sup?", ["Not much", "Bye"])
##     Dialogue.close()
##
## The game is paused while the box is open. Interact, attack, or ui_accept
## move the conversation on. Options are picked with the arrows, the stick,
## or the mouse.

signal _line_finished
signal _option_picked(index: int)

const CHARACTERS_PER_SECOND := 45.0
## Ignore input this long after opening and after closing, so the button
## press that opened or closed the box doesn't also do something else.
const INPUT_GRACE_MS := 200
const FOCUSED_PREFIX := "▶ "
const OPTION_COLOR := Color(0.85, 0.85, 0.8)
const OPTION_FOCUS_COLOR := Color(1.0, 0.85, 0.35)

var is_open := false

var _typing: Tween
var _typing_done := true
var _pending_options: Array = []
var _option_buttons: Array[Button] = []
var _opened_at := 0
var _closed_at := -INPUT_GRACE_MS

@onready var _speaker: Label = %Speaker
@onready var _text: RichTextLabel = %Text
@onready var _portrait: TextureRect = %Portrait
@onready var _options: GridContainer = %Options
@onready var _more: Label = %More


func _ready() -> void:
	visible = false


## Whether dialogue should keep the player from acting right now.
func blocks_input() -> bool:
	return is_open or Time.get_ticks_msec() - _closed_at < INPUT_GRACE_MS


## Shows a line and waits until the player moves on.
func say(speaker: String, portrait: Texture2D, text: String) -> void:
	_show_line(speaker, portrait, text, [])
	await _line_finished


## Shows a line with options. Returns the index of the one picked.
func choose(speaker: String, portrait: Texture2D, text: String, options: Array) -> int:
	_show_line(speaker, portrait, text, options)
	return await _option_picked


func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	_closed_at = Time.get_ticks_msec()


func _show_line(speaker: String, portrait: Texture2D, text: String, options: Array) -> void:
	if not is_open:
		is_open = true
		visible = true
		get_tree().paused = true
		_opened_at = Time.get_ticks_msec()
	_speaker.text = speaker
	_portrait.texture = portrait
	_portrait.visible = portrait != null
	_clear_options()
	_more.visible = false
	_pending_options = options

	# Type the line out.
	_text.text = text
	_text.visible_ratio = 0.0
	_typing_done = false
	if _typing:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, text.length() / CHARACTERS_PER_SECOND)
	_typing.tween_callback(_finish_typing)


func _finish_typing() -> void:
	if _typing_done:
		return
	_typing_done = true
	if _typing:
		_typing.kill()
	_text.visible_ratio = 1.0
	if _pending_options.is_empty():
		_more.visible = true
		return
	# Long menus go in two columns so they fit in the box.
	_options.columns = 2 if _pending_options.size() > 3 else 1
	for i in _pending_options.size():
		var button := Button.new()
		button.text = _pending_options[i]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.flat = true
		button.add_theme_font_size_override("font_size", 24)
		button.add_theme_color_override("font_color", OPTION_COLOR)
		for state in ["font_focus_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			button.add_theme_color_override(state, OPTION_FOCUS_COLOR)
		button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		button.focus_entered.connect(_refresh_focus_marks)
		button.mouse_entered.connect(button.grab_focus)
		button.pressed.connect(_option_picked.emit.bind(i))
		_options.add_child(button)
		_option_buttons.append(button)
	_option_buttons[0].grab_focus()


func _refresh_focus_marks() -> void:
	for i in _option_buttons.size():
		var button := _option_buttons[i]
		var label: String = _pending_options[i]
		button.text = FOCUSED_PREFIX + label if button.has_focus() else label


func _clear_options() -> void:
	for button in _option_buttons:
		button.queue_free()
	_option_buttons.clear()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	var advance := event.is_action_pressed("interact") or event.is_action_pressed("attack") \
		or event.is_action_pressed("ui_accept")
	if not advance:
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() - _opened_at < INPUT_GRACE_MS:
		return
	if not _typing_done:
		_finish_typing()
	elif _option_buttons.is_empty():
		_line_finished.emit()
	else:
		for button in _option_buttons:
			if button.has_focus():
				button.pressed.emit()
				return
