extends Node3D
## A shop counter with a clerk behind it. Talking to them opens the shop menu
## in the dialogue box. Weapons are equipped on the spot. Items go into
## WorldState's inventory.

@export var clerk_name := "Clerk"
## What's for sale. Each entry: {"label": String, "price": int} plus either
## "weapon": Weapon, or "item": String and "count": int.
@export var stock: Array[Dictionary] = [
	{"label": "Baseball Bat", "price": 40, "weapon": preload("res://weapons/baseball_bat.tres")},
	{"label": "Knife", "price": 25, "weapon": preload("res://weapons/knife.tres")},
	{"label": "Brass Knuckles", "price": 30, "weapon": preload("res://weapons/brass_knuckles.tres")},
	{"label": "Pistol", "price": 75, "weapon": preload("res://weapons/pistol.tres")},
	{"label": "Weed Seeds (x3)", "price": 12, "item": "weed_seed", "count": 3},
]

@onready var _use: Interactable = $Use


func _ready() -> void:
	_use.interacted.connect(_on_used)


func _on_used(player: Citizen) -> void:
	if Dialogue.blocks_input():
		return
	var greeting := "What'll it be?"
	while true:
		var options: Array = stock.map(func(entry: Dictionary) -> String:
			return "%s  -  $%d" % [entry.label, entry.price])
		options.append("Nothing, thanks")
		var pick := await Dialogue.choose(clerk_name, null, "%s  (You've got $%d.)" % [greeting, WorldState.money], options)
		if pick >= stock.size():
			break
		var entry: Dictionary = stock[pick]
		if not WorldState.spend_money(entry.price):
			greeting = "Come back when you've got the cash."
			continue
		if entry.has("weapon"):
			player.equip(entry.weapon)
		else:
			WorldState.add_item(entry.item, entry.get("count", 1))
		greeting = "Pleasure doing business. Anything else?"
	Dialogue.close()
