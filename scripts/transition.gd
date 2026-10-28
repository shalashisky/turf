extends CanvasLayer
## Moves the player between scenes, like stepping through a door: fades to
## black, swaps the scene, puts the player at the named entrance, and fades
## back in. Autoloaded as Transition.
##
## Entrances are Marker3D nodes in the "entrances" group, matched by node name.
## The player comes out facing the marker's +Z. Health and the equipped weapon
## (with its ammo) carry over.

const FADE_TIME := 0.25
const MESSAGE_TIME := 4.0

var busy := false

@onready var _fade: ColorRect = $Fade
@onready var _message: Label = $Message


## `while_dark` runs once the screen is black, before the new scene loads.
## `heal` restores the player to full health. `message` shows once the screen
## fades back in.
func go_to(scene_path: String, entrance: String, while_dark := Callable(), heal := false, message := "") -> void:
	if busy:
		return
	busy = true
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var health := player.health if player else -1
	var weapon := player.equipped_weapon if player else null
	var ammo := player.ammo if player else 0

	await _fade_to(1.0)
	if while_dark.is_valid():
		while_dark.call()
	get_tree().change_scene_to_file(scene_path)
	# The new scene is in place and ready after the next frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_arrive(entrance, -1 if heal else health, weapon, ammo)
	await _fade_to(0.0)
	busy = false
	if not message.is_empty():
		show_message(message)


## A line of text in the middle of the screen for a few seconds.
func show_message(text: String) -> void:
	_message.text = text
	_message.modulate.a = 0.0
	_message.show()
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 0.3)
	tween.tween_interval(MESSAGE_TIME)
	tween.tween_property(_message, "modulate:a", 0.0, 0.6)
	tween.tween_callback(_message.hide)


func _arrive(entrance: String, health: int, weapon: Weapon, ammo: int) -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null:
		return
	for marker: Node3D in get_tree().get_nodes_in_group("entrances"):
		if marker.name == entrance:
			player.global_position = marker.global_position
			player.facing = marker.global_basis.z.normalized()
			player.reset_physics_interpolation()
			break
	if health > 0:
		player.health = health
	if weapon:
		player.equip(weapon, ammo)
	if player.camera_rig:
		player.camera_rig.snap_to_target()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished
