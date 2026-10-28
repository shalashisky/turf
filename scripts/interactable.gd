class_name Interactable
extends Area3D
## Something the player can use by walking up to it and pressing interact.
## While the player is in range, a prompt like "[E] Enter" floats above it.
## Connect to `interacted` to make it do something.

signal interacted(by: Citizen)

## What pressing interact will do, like "Enter" or "Harvest". Empty hides the
## prompt and disables interacting.
@export var prompt := "Use":
	set(value):
		prompt = value
		_update_label()
@export var prompt_height := 1.9

var _player_in_range: Citizen
var _label: Label3D


func _ready() -> void:
	add_to_group("interactables")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.render_priority = 10
	_label.outline_render_priority = 9
	_label.font_size = 40
	_label.outline_size = 12
	_label.pixel_size = 0.005
	_label.modulate = Color(1.0, 0.95, 0.7)
	_label.position.y = prompt_height
	add_child(_label)
	_update_label()


func can_interact(by: Citizen) -> bool:
	return by == _player_in_range and prompt != ""


func interact(by: Citizen) -> void:
	if can_interact(by):
		interacted.emit(by)


func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		_player_in_range = body
		_update_label()


func _on_body_exited(body: Node3D) -> void:
	if body == _player_in_range:
		_player_in_range = null
		_update_label()


func _update_label() -> void:
	if _label == null:
		return
	_label.text = "[E] %s" % prompt
	_label.visible = _player_in_range != null and prompt != ""
