extends CanvasLayer
## Moves the player between scenes, like stepping through a door: fades to
## black, swaps the scene, puts the player at the named entrance, and fades
## back in. Autoloaded as Transition.
##
## Entrances are Marker3D nodes in the "entrances" group, matched by node name.
## The player comes out facing the marker's +Z. Health and the equipped
## weapon carry over.

const FADE_TIME := 0.25

var busy := false

@onready var _fade: ColorRect = $Fade


func go_to(scene_path: String, entrance: String) -> void:
	if busy:
		return
	busy = true
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var health := player.health if player else -1
	var weapon := player.equipped_weapon if player else null

	await _fade_to(1.0)
	get_tree().change_scene_to_file(scene_path)
	# The new scene is in place and ready after the next frame.
	await get_tree().process_frame
	await get_tree().process_frame
	_arrive(entrance, health, weapon)
	await _fade_to(0.0)
	busy = false


func _arrive(entrance: String, health: int, weapon: Weapon) -> void:
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player == null:
		return
	for marker: Node3D in get_tree().get_nodes_in_group("entrances"):
		if marker.name == entrance:
			player.global_position = marker.global_position
			player.facing = marker.global_basis.z.normalized()
			player.reset_physics_interpolation()
			break
	if health >= 0:
		player.health = health
	if weapon:
		player.equip(weapon)
	if player.camera_rig:
		player.camera_rig.snap_to_target()


func _fade_to(alpha: float) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", alpha, FADE_TIME)
	await tween.finished
