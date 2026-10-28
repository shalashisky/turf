class_name Neighbor
extends Citizen
## A neighbor you can talk to and give presents. How much they like you is
## their reputation in WorldState, under npc_id. Gifts move it up or down
## depending on the item, and hitting them knocks it down.
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

@onready var _talk: Interactable = $Talk


func _ready() -> void:
	super()
	facing = start_facing
	_talk.interacted.connect(_on_talk)
	WorldState.reputation_changed.connect(func(id: String) -> void:
		if id == npc_id:
			_update_prompt())
	died.connect(func() -> void: _talk.prompt = "")
	_update_prompt()


func hit(attacker: Citizen, weapon: Weapon) -> void:
	super(attacker, weapon)
	if attacker and attacker.is_in_group("player"):
		WorldState.change_reputation(npc_id, hit_points)


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
	if is_dead or Dialogue.blocks_input():
		return
	face_toward(player.global_position)
	player.face_toward(global_position)
	await converse(player)
	Dialogue.close()


func _update_prompt() -> void:
	if not is_dead:
		# Reputation shows in the prompt while there's no other UI for it.
		_talk.prompt = "Talk  (rep %d)" % WorldState.reputation_with(npc_id)
