extends Node
## What the player's carrying: a hotbar of SLOTS slots, like Stardew Valley's
## or Minecraft's. The player picks a slot with the number keys, the mouse
## wheel or the shoulder buttons, and holds whatever's in it (see Player).
## Autoloaded as Inventory, so it outlives scene changes.
##
## Each slot is empty (null) or holds one stack:
##   {"weapon": Weapon, "ammo": int}  a weapon. Guns and Molotovs keep their
##                                    ammo, and the same kind stacks up.
##   {"item": String, "count": int}   goods, like weed and seeds, by item id
##                                    (WorldState.ITEM_NAMES).
##   {"cash": true}                   the player's money, WorldState.money.

signal changed
signal selection_changed

const SLOTS := 10
const ITEM_ICONS := {
	"weed": preload("res://art/weed_bag.png"),
	"weed_seed": preload("res://art/seed_packet.png"),
	"burger": preload("res://art/burger.png"),
	"cocaine": preload("res://art/cocaine.png"),
}
const CASH_ICON := preload("res://art/cash.png")

var slots: Array = []
var selected := 0


func _ready() -> void:
	slots.resize(SLOTS)
	slots[0] = {"cash": true}
	slots[1] = {"item": "weed", "count": 5}
	slots[2] = {"item": "weed_seed", "count": 3}
	# Loaded after WorldState: tell it when the player's things change.
	WorldState.money_changed.connect(changed.emit)
	changed.connect(WorldState.inventory_changed.emit)


func selected_slot() -> Variant:
	return slots[selected]


func select(index: int) -> void:
	index = posmod(index, SLOTS)
	if index != selected:
		selected = index
		selection_changed.emit()


func set_slot(index: int, stack: Variant) -> void:
	slots[index] = stack
	changed.emit()


## The weapon in slot `index`, if that's what's in it.
func weapon_in(index: int) -> Weapon:
	var stack: Variant = slots[index]
	return stack.weapon if stack is Dictionary and stack.has("weapon") else null


## The item id in slot `index`, or "" if it isn't goods.
func item_in(index: int) -> String:
	var stack: Variant = slots[index]
	return stack.item if stack is Dictionary and stack.has("item") else ""


## How many of `item` the player has, across all slots.
func count(item: String) -> int:
	var total := 0
	for stack: Variant in slots:
		if stack is Dictionary and stack.get("item", "") == item:
			total += stack.count
	return total


## Adds `amount` of `item`, onto a stack of it if there is one, or else into
## the first free slot. False if there's no room.
func add_item(item: String, amount: int) -> bool:
	if amount <= 0:
		return true
	for stack: Variant in slots:
		if stack is Dictionary and stack.get("item", "") == item:
			stack.count += amount
			changed.emit()
			return true
	var free := slots.find(null)
	if free < 0:
		return false
	slots[free] = {"item": item, "count": amount}
	changed.emit()
	return true


## Takes away `amount` of `item`. Stacks that run out leave their slot empty.
## False, and nothing taken, if there isn't that much.
func remove_item(item: String, amount: int) -> bool:
	if count(item) < amount:
		return false
	for i in SLOTS:
		var stack: Variant = slots[i]
		if amount <= 0:
			break
		if stack is Dictionary and stack.get("item", "") == item:
			var taken := mini(stack.count, amount)
			stack.count -= taken
			amount -= taken
			if stack.count <= 0:
				slots[i] = null
	changed.emit()
	return true


## Whether `weapon` would go in: onto a stack of the same gun or throwable,
## or into a free slot. Not a second of the same melee weapon.
func has_room_for(weapon: Weapon) -> bool:
	if _stack_for(weapon) >= 0:
		return true
	return slots.find(null) >= 0 and not (weapon.max_ammo <= 0 and has_weapon(weapon))


func has_weapon(weapon: Weapon) -> bool:
	for i in SLOTS:
		if weapon_in(i) == weapon:
			return true
	return false


## Puts `weapon` away with `ammo` shots (full if negative). Returns the slot it
## went in, or -1 if there was no room.
func add_weapon(weapon: Weapon, ammo := -1) -> int:
	if ammo < 0:
		ammo = weapon.max_ammo
	var stack := _stack_for(weapon)
	if stack >= 0:
		slots[stack].ammo += ammo
		changed.emit()
		return stack
	if not has_room_for(weapon):
		return -1
	var free := slots.find(null)
	slots[free] = {"weapon": weapon, "ammo": ammo}
	changed.emit()
	return free


## What to call the stack in a slot.
func name_of(stack: Variant) -> String:
	if not stack is Dictionary:
		return ""
	if stack.has("weapon"):
		return stack.weapon.display_name
	if stack.has("item"):
		return WorldState.item_name(stack.item)
	return "Cash"


## The picture for the stack in a slot.
func icon_of(stack: Variant) -> Texture2D:
	if not stack is Dictionary:
		return null
	if stack.has("weapon"):
		return stack.weapon.texture
	if stack.has("item"):
		return ITEM_ICONS.get(stack.item)
	return CASH_ICON


## The number to show on a slot: shots, how many, or dollars. -1 for none.
func amount_of(stack: Variant) -> int:
	if not stack is Dictionary:
		return -1
	if stack.has("weapon"):
		return stack.ammo if stack.weapon.max_ammo > 0 else -1
	if stack.has("item"):
		return stack.count
	return WorldState.money


## The slot with a stack `weapon` can join, or -1. Only guns and throwables
## stack, topping up their ammo.
func _stack_for(weapon: Weapon) -> int:
	if weapon.max_ammo <= 0:
		return -1
	for i in SLOTS:
		if weapon_in(i) == weapon:
			return i
	return -1
