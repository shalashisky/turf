class_name Neighbor
extends Npc
## A neighbor you can talk to and give presents. How much they like you is
## their reputation in WorldState, under npc_id. Gifts move it up or down
## depending on the item, and hitting them knocks it down.
##
## When a fight breaks out nearby, a neighbor runs from it: into the nearest
## SafeDoor if there's one in range, otherwise just away, strolling back home
## once things calm down. Get their reputation up to ally_reputation and
## they'll fight on your side instead.
##
## Each neighbor writes its conversation in converse(), using say() and
## choose(). give_present() runs the gift exchange they all share.

@export var npc_id := "neighbor"
@export var display_name := "Neighbor"
## Shown in the dialogue box, peeking out over it.
@export var portrait: Texture2D
@export var start_facing := Vector3.BACK

@export_group("Reputation")
## Reputation change per gifted item id. Unlisted items get default_gift_points.
@export var gift_reactions := {}
@export var default_gift_points := -5
## Reputation change each time the player hits them.
@export var hit_points := -15

@export_group("Fights")
## How close a fight has to be for this neighbor to react to it.
@export var notice_range := 12.0
## At or above this reputation, they fight alongside the player.
@export var ally_reputation := 100
## How long they keep running after the last blow they noticed.
@export var flee_time := 5.0
## Walking speed when strolling back home. move_speed is their running speed.
@export var stroll_speed := 1.5

## Where they go back to once things calm down.
var _home: Vector3
var _flee_from := Vector3.ZERO
var _flee_left := 0.0
## The safe door they're hiding behind, if any.
var _shelter: SafeDoor
var _hidden_groups: Array[StringName] = []
var _hidden_collision_layer := 0

@onready var _talk: Interactable = $Talk


func _ready() -> void:
	super()
	_home = global_position
	facing = start_facing
	_talk.interacted.connect(_on_talk)
	# The AI that normally refreshes the prompt doesn't run while they're down.
	for change in [knocked_out, got_up, died]:
		change.connect(_update_prompt)
	_update_prompt()


func is_allied() -> bool:
	return WorldState.reputation_with(npc_id) >= ally_reputation


func _react_to_hit(attacker: Citizen) -> void:
	if attacker == null or is_down:
		return
	if attacker.is_in_group("player"):
		WorldState.change_reputation(npc_id, hit_points)
		_flee(attacker.global_position)
	elif is_allied() and not _is_ally(attacker):
		start_fighting(attacker)
	else:
		_flee(attacker.global_position)


## Called through the "neighbors" group whenever any citizen takes a hit.
func notice_fight(attacker: Citizen, victim: Citizen) -> void:
	if is_down or self in [attacker, victim] or _still_fighting():
		return
	if global_position.distance_to(victim.global_position) > notice_range:
		return
	# Allies join in against whoever is fighting the player's side.
	if is_allied():
		var enemy: Citizen = null
		if _on_players_side(attacker):
			enemy = victim
		elif _on_players_side(victim):
			enemy = attacker
		if enemy and not enemy.is_down and not _is_ally(enemy):
			start_fighting(enemy)
			return
	_flee(victim.global_position)


## Friendly factions are allies as usual. Once allied with the player, so are
## the player and the other neighbors.
func _is_ally(other: Citizen) -> bool:
	if is_allied() and (other.is_in_group("player") or other is Neighbor):
		return true
	return super(other)


## The player, or a neighbor who's allied with them.
func _on_players_side(citizen: Citizen) -> bool:
	return citizen.is_in_group("player") or (citizen is Neighbor and citizen.is_allied())


func _choose_move_direction(delta: float) -> Vector3:
	_update_prompt()
	if not _still_fighting() and is_allied():
		var next := _find_enemy_fighting_us()
		if next:
			start_fighting(next)
	if target:
		return _fight(delta)
	if _flee_left > 0.0:
		var door := _nearest_safe_door()
		if door:
			_flee_left = flee_time  # keep running until we're inside
			if global_position.distance_to(door.doorstep()) < 0.8:
				# Deferred: going inside takes us out of the physics world, which
				# can't happen halfway through our own physics step.
				_flee_left = 0.0
				door.shelter.call_deferred(self)
				return Vector3.ZERO
			return _steer_toward(door.doorstep())
		_flee_left -= delta
		return _flee_direction()
	# Calm again: stroll back home.
	var to_home := _home - global_position
	to_home.y = 0.0
	if to_home.length() > 0.6:
		return _steer_toward(_home) * minf(stroll_speed / move_speed, 1.0)
	return Vector3.ZERO


## An enemy nearby that's fighting the player or one of their allies.
func _find_enemy_fighting_us() -> Citizen:
	var best: Citizen = null
	var best_distance := notice_range
	for enemy: Npc in get_tree().get_nodes_in_group("npcs"):
		var their_target := enemy.target
		if their_target == null or not is_instance_valid(their_target) or not _on_players_side(their_target):
			continue
		if enemy == self or _on_players_side(enemy) or _is_ally(enemy):
			continue
		var distance := global_position.distance_to(enemy.global_position)
		if distance < best_distance and not enemy.is_down:
			best = enemy
			best_distance = distance
	return best


## Ducks inside `door`: out of sight, out of the fight, out of reach.
func hide_inside(door: SafeDoor) -> void:
	_shelter = door
	stop_fighting()
	_flee_left = 0.0
	_hidden_groups.clear()
	for group: StringName in ["citizens", "npcs", faction]:
		if is_in_group(group):
			_hidden_groups.append(group)
			remove_from_group(group)
	_hidden_collision_layer = collision_layer
	collision_layer = 0
	visible = false
	process_mode = Node.PROCESS_MODE_DISABLED


## Steps back out of the safe door at `at`, facing `out`.
func come_out(at: Vector3, out: Vector3) -> void:
	process_mode = Node.PROCESS_MODE_INHERIT
	visible = true
	collision_layer = _hidden_collision_layer
	for group in _hidden_groups:
		add_to_group(group)
	_shelter = null
	global_position = at
	facing = out
	velocity = Vector3.ZERO
	_walk_velocity = Vector3.ZERO
	_push_velocity = Vector3.ZERO
	reset_physics_interpolation()


func _nearest_safe_door() -> SafeDoor:
	var best: SafeDoor = null
	var best_distance := INF
	for door: SafeDoor in get_tree().get_nodes_in_group("safe_doors"):
		var distance := global_position.distance_to(door.global_position)
		if distance <= door.shelter_range and distance < best_distance:
			best = door
			best_distance = distance
	return best


func _flee(from: Vector3) -> void:
	_flee_from = from
	_flee_left = flee_time
	stop_fighting()


func _flee_direction() -> Vector3:
	return _direction_away_from(_flee_from)


## The conversation. Each neighbor overrides this.
func converse(_player: Citizen) -> void:
	await say("...")


func say(text: String) -> void:
	await Dialogue.say(display_name, portrait, text)


func choose(text: String, options: Array) -> int:
	return await Dialogue.choose(display_name, portrait, text, options)


## Asks what to give, takes it, and reacts according to gift_reactions.
func give_present() -> void:
	var items := WorldState.held_items()
	if items.is_empty():
		await say(nothing_to_give_line())
		return
	var labels: Array = items.map(func(item: String) -> String:
		return "%s  (%d)" % [WorldState.item_name(item), WorldState.item_count(item)])
	labels.append("Never mind")
	var pick := await choose(what_have_you_got_line(), labels)
	if pick >= items.size():
		return
	var item := items[pick]
	WorldState.add_item(item, -1)
	var points: int = gift_reactions.get(item, default_gift_points)
	WorldState.change_reputation(npc_id, points)
	await say(gift_reaction_line(item, points))


# Lines a neighbor can override to sound like themselves.

func nothing_to_give_line() -> String:
	return "You don't have anything."


func what_have_you_got_line() -> String:
	return "What've you got?"


func gift_reaction_line(_item: String, points: int) -> String:
	if points > 0:
		return "Thanks!"
	if points < 0:
		return "...Why would you give me this?"
	return "Oh. Thanks."


func _on_talk(player: Citizen) -> void:
	if is_down or target or _flee_left > 0.0 or _shelter or Dialogue.blocks_input():
		return
	face_toward(player.global_position)
	player.face_toward(global_position)
	await converse(player)
	Dialogue.close()


## No talking while they're down, fighting, or running. Reputation shows in
## the prompt while there's no other UI for it.
func _update_prompt() -> void:
	var busy := is_down or target != null or _flee_left > 0.0
	var prompt := "" if busy else "Talk  (rep %d)" % WorldState.reputation_with(npc_id)
	if _talk.prompt != prompt:
		_talk.prompt = prompt
