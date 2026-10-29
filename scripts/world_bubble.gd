extends Node
## Keeps the world's life near the player, where the city is loaded. Anyone
## spawned (pedestrians, gang members, traffic and other cars) who ends up off the loaded
## chunks, or too far from the player, is removed: the spawners bring new
## people in nearer by. People who belong somewhere for good, like neighbors,
## are paused instead, and carry on once their part of the city loads again.

const CHECK_INTERVAL := 0.25

@export var streamer: ChunkStreamer
## Spawned people this far from the player are removed even on loaded ground.
@export var despawn_distance := 46.0

var _check_left := 0.0


func _process(delta: float) -> void:
	_check_left -= delta
	if _check_left > 0.0 or streamer == null:
		return
	_check_left = CHECK_INTERVAL
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	for citizen: Citizen in get_tree().get_nodes_in_group("citizens"):
		if citizen == player:
			continue
		var in_bubble := streamer.is_loaded_at(citizen.global_position) \
			and citizen.global_position.distance_to(player.global_position) < despawn_distance
		if citizen is Neighbor:
			_pause(citizen, not in_bubble)
		elif not in_bubble:
			citizen.queue_free()
	# Cars don't need ground under them, so they go by distance alone: cars
	# coming in from off-screen may start out past the loaded chunks.
	for car: Vehicle in get_tree().get_nodes_in_group("spawned_vehicles"):
		if car.global_position.distance_to(player.global_position) > despawn_distance + 10.0:
			car.queue_free()
	# Wake up paused neighbors whose ground is back.
	for neighbor: Neighbor in get_tree().get_nodes_in_group("bubble_paused"):
		if streamer.is_loaded_at(neighbor.global_position) \
				and neighbor.global_position.distance_to(player.global_position) < despawn_distance:
			_pause(neighbor, false)


func _pause(citizen: Citizen, paused: bool) -> void:
	if paused == citizen.is_in_group("bubble_paused"):
		return
	if paused:
		citizen.add_to_group("bubble_paused")
		# Still shown, far off as they are, so their blip stays on the map.
		citizen.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		citizen.remove_from_group("bubble_paused")
		citizen.process_mode = Node.PROCESS_MODE_INHERIT
