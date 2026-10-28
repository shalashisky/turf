extends Node
## Game state that has to outlive scene changes and streamed-out chunks:
## crops, money, reputation with neighbors, turf, and so on. What the player
## carries lives in the Inventory hotbar; the item functions here go to it. Autoloaded as WorldState. Saving and loading
## will serialize what's in here.
##
## Crops are stored as timestamps, not ticked every frame, so they keep
## growing while you're somewhere else. Their state is worked out from
## GameClock.absolute_minutes() whenever it's asked for.

signal inventory_changed
signal money_changed
signal energy_changed
## Energy just hit zero. DayCycle makes the player pass out.
signal out_of_energy
signal reputation_changed(npc_id: String)

## Fed growing time from seed to harvest: two in-game days.
const GROW_MINUTES := 2.0 * 24.0 * 60.0
## How long one top-up of the nutrient reservoir feeds a tray.
const NUTRIENT_MINUTES := 24.0 * 60.0
## Buds per harvest.
const HARVEST_YIELD := Vector2i(3, 6)
## A bag of weed sells for about this, give or take the day's price swing.
const WEED_BASE_PRICE := 22
const WEED_PRICE_SWING := Vector2(0.7, 1.5)
## Selling on a rival gang's turf pays this much more.
const RIVAL_TURF_MARKUP := 1.3
const MAX_ENERGY := 100.0
## Energy each action costs.
const ATTACK_ENERGY := 1.0
const PLANT_WORK_ENERGY := 4.0

## How each inventory item is shown to the player.
const ITEM_NAMES := {"weed": "Weed", "weed_seed": "Weed Seed"}
## Reputation runs from hated to best friends.
const REPUTATION_RANGE := Vector2i(-250, 1000)

enum TrayState { EMPTY, GROWING, READY }

var money := 250
## Spent on attacking and tending plants; refilled by sleeping.
var energy := MAX_ENERGY
## Who holds each Territory, by territory id. Territories not listed are
## still held by their starting gang.
var territory_owners := {}
## How much each neighbor likes the player, by NPC id.
var reputation := {}
## Where the player's car was left and how it was doing, so it's still there
## after going indoors: {"transform", "health", "wrecked_on_day"}. Empty
## until the city scene is first left.
var player_car := {}

## Hydroponic trays by id: {growth, fed_until, updated_at}, all in minutes.
var _trays := {}


func item_count(item: String) -> int:
	return Inventory.count(item)


## Gives the player `count` of `item`, or takes them away if it's negative.
## False if there's no room for them, or not that many to take.
func add_item(item: String, count: int) -> bool:
	if count < 0:
		return Inventory.remove_item(item, -count)
	return Inventory.add_item(item, count)


## What a bag of weed sells for today. It changes from day to day, the same
## for everyone on a given day.
func weed_price() -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(GameClock.day_index * 7919 + 13)
	return roundi(WEED_BASE_PRICE * rng.randf_range(WEED_PRICE_SWING.x, WEED_PRICE_SWING.y))


## What a bag sells for at `point`: more on a rival gang's turf, for the risk.
func weed_price_at(point: Vector3) -> int:
	var turf := Territory.at(point)
	var rival := turf != null and turf.owner_faction() != Factions.PLAYER
	return roundi(weed_price() * (RIVAL_TURF_MARKUP if rival else 1.0))


func use_energy(amount: float) -> void:
	if energy <= 0.0:
		return
	energy = maxf(energy - amount, 0.0)
	energy_changed.emit()
	if energy <= 0.0:
		out_of_energy.emit()


## Refills energy to `fraction` of the maximum.
func restore_energy(fraction: float) -> void:
	energy = MAX_ENERGY * fraction
	energy_changed.emit()


func add_money(amount: int) -> void:
	money = maxi(money + amount, 0)
	money_changed.emit()


## Takes `amount` if the player has it. Returns whether they did.
func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	add_money(-amount)
	return true


func territory_owner(territory_id: String, starting_owner: StringName) -> StringName:
	return territory_owners.get(territory_id, starting_owner)


func set_territory_owner(territory_id: String, faction: StringName) -> void:
	territory_owners[territory_id] = faction


func item_name(item: String) -> String:
	return ITEM_NAMES.get(item, item.capitalize())


## Items the player has at least one of.
func held_items() -> Array[String]:
	var held: Array[String] = []
	for i in Inventory.SLOTS:
		var item := Inventory.item_in(i)
		if item != "" and item not in held:
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


## Plants a seed with a full reservoir. Needs a weed seed in the inventory.
## Returns whether it planted.
func plant_tray(id: String) -> bool:
	if item_count("weed_seed") <= 0:
		return false
	add_item("weed_seed", -1)
	var now := GameClock.absolute_minutes()
	_trays[id] = {"growth": 0.0, "fed_until": now + NUTRIENT_MINUTES, "updated_at": now}
	return true


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
