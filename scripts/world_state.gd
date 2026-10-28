extends Node
## Game state that has to outlive scene changes and streamed-out chunks:
## crops, inventory, reputation with neighbors, and so on. Autoloaded as WorldState. Saving and loading
## will serialize what's in here.
##
## Crops are stored as timestamps, not ticked every frame, so they keep
## growing while you're somewhere else. Their state is worked out from
## GameClock.absolute_minutes() whenever it's asked for.

signal inventory_changed
signal reputation_changed(npc_id: String)

## Fed growing time from seed to harvest: two in-game days.
const GROW_MINUTES := 2.0 * 24.0 * 60.0
## How long one top-up of the nutrient reservoir feeds a tray.
const NUTRIENT_MINUTES := 24.0 * 60.0
## Buds per harvest.
const HARVEST_YIELD := Vector2i(3, 6)

## How each inventory item is shown to the player.
const ITEM_NAMES := {"weed": "Weed"}
## Reputation runs from hated to best friends.
const REPUTATION_RANGE := Vector2i(-250, 1000)

enum TrayState { EMPTY, GROWING, READY }

var inventory := {}
## How much each neighbor likes the player, by NPC id.
var reputation := {}

## Hydroponic trays by id: {growth, fed_until, updated_at}, all in minutes.
var _trays := {}


func item_count(item: String) -> int:
	return inventory.get(item, 0)


func add_item(item: String, count: int) -> void:
	inventory[item] = maxi(item_count(item) + count, 0)
	inventory_changed.emit()


func item_name(item: String) -> String:
	return ITEM_NAMES.get(item, item.capitalize())


## Items the player has at least one of.
func held_items() -> Array[String]:
	var held: Array[String] = []
	for item: String in inventory:
		if inventory[item] > 0:
			held.append(item)
	return held


func reputation_with(npc_id: String) -> int:
	return reputation.get(npc_id, 0)


func change_reputation(npc_id: String, amount: int) -> void:
	reputation[npc_id] = clampi(reputation_with(npc_id) + amount, REPUTATION_RANGE.x, REPUTATION_RANGE.y)
	reputation_changed.emit(npc_id)


func tray_state(id: String) -> TrayState:
	if not _trays.has(id):
		return TrayState.EMPTY
	return TrayState.READY if tray_growth(id) >= 1.0 else TrayState.GROWING


## How far along the plant is, from 0 (just planted) to 1 (ready).
func tray_growth(id: String) -> float:
	if not _trays.has(id):
		return 0.0
	return minf(_advance(id).growth / GROW_MINUTES, 1.0)


## How full the nutrient reservoir is, from 0 (dry: growth paused) to 1.
func tray_nutrients(id: String) -> float:
	if not _trays.has(id):
		return 0.0
	var left: float = _trays[id].fed_until - GameClock.absolute_minutes()
	return clampf(left / NUTRIENT_MINUTES, 0.0, 1.0)


## Plants a seed with a full reservoir.
func plant_tray(id: String) -> void:
	var now := GameClock.absolute_minutes()
	_trays[id] = {"growth": 0.0, "fed_until": now + NUTRIENT_MINUTES, "updated_at": now}


func top_up_tray(id: String) -> void:
	if _trays.has(id):
		_advance(id)
		_trays[id].fed_until = GameClock.absolute_minutes() + NUTRIENT_MINUTES


## Empties a ready tray into the inventory. Returns how many buds it gave.
func harvest_tray(id: String) -> int:
	if tray_state(id) != TrayState.READY:
		return 0
	_trays.erase(id)
	var buds := randi_range(HARVEST_YIELD.x, HARVEST_YIELD.y)
	add_item("weed", buds)
	return buds


## Brings a tray's growth up to now. It only grows while it has nutrients.
func _advance(id: String) -> Dictionary:
	var tray: Dictionary = _trays[id]
	var now := GameClock.absolute_minutes()
	var fed_until: float = minf(now, tray.fed_until)
	if fed_until > tray.updated_at:
		tray.growth += fed_until - tray.updated_at
	tray.updated_at = now
	return tray
