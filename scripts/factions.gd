extends Node
## Who's on whose side, autoloaded as Factions. Every citizen belongs to a
## faction (Citizen.faction), and is put in a group with that faction's name.
## Members of the same faction stick together. The gangs, the player's crew
## included, are all at each other's throats, and the police are against every
## gang. Pairs not covered are neutral.
##
## Also tracks whether the police want the player: they do for a while after
## seeing the player attack someone they protect.

enum Stance { FRIENDLY, NEUTRAL, HOSTILE }

const PLAYER := &"player"
const DUMMY_GANG := &"dummy_gang"
const PANTHERS := &"panthers"
const YELLOWS := &"yellows"
const POLICE := &"police"
const CIVILIANS := &"civilians"
const NEIGHBORS := &"neighbors"
const CIA := &"cia"
const HOMELESS := &"homeless"
const DRUGGIES := &"druggies"

## Gangs that hold turf. The player's crew counts as one.
const GANGS: Array[StringName] = [PLAYER, DUMMY_GANG, PANTHERS, YELLOWS]

## Exceptions to the gang rules, either way round.
const RELATIONS := {
	[POLICE, CIVILIANS]: Stance.FRIENDLY,
	[POLICE, NEIGHBORS]: Stance.FRIENDLY,
	[POLICE, HOMELESS]: Stance.FRIENDLY,
}

const NAMES := {
	PLAYER: "Your Crew",
	DUMMY_GANG: "Dummy Gang",
	PANTHERS: "Black Panthers",
	YELLOWS: "The Yellows",
	POLICE: "Police",
	CIVILIANS: "Civilians",
	NEIGHBORS: "Neighbors",
	CIA: "CIA",
	HOMELESS: "Homeless",
	DRUGGIES: "Druggies",
}

## Gang member scenes, for gangs that hold turf and send people out of doors.
const MEMBER_SCENES := {
	PLAYER: "res://scenes/npcs/crew.tscn",
	DUMMY_GANG: "res://scenes/dummy_enemy.tscn",
	PANTHERS: "res://scenes/npcs/panther.tscn",
	YELLOWS: "res://scenes/npcs/yellow.tscn",
}

## Turf colors on the map.
const COLORS := {
	PLAYER: Color(0.9, 0.2, 0.2),
	DUMMY_GANG: Color(0.25, 0.45, 0.95),
	PANTHERS: Color(0.08, 0.08, 0.1),
	YELLOWS: Color(0.95, 0.82, 0.15),
}

## How long the police stay after the player, in seconds since the last offense.
const WANTED_TIME := 30.0
## Anyone this close who can see a deal go down, sees it.
const DEAL_WITNESS_RANGE := 14.0

signal wanted_changed

var _wanted_until := 0.0


func stance(a: StringName, b: StringName) -> Stance:
	if a == b:
		return Stance.FRIENDLY
	if RELATIONS.has([a, b]):
		return RELATIONS[[a, b]]
	if RELATIONS.has([b, a]):
		return RELATIONS[[b, a]]
	# Gangs fight each other, and the police fight the gangs. The player is
	# left to the police's own judgement (see Cop).
	if is_gang(a) and is_gang(b):
		return Stance.HOSTILE
	if POLICE in [a, b] and (is_gang(a) or is_gang(b)) and PLAYER not in [a, b]:
		return Stance.HOSTILE
	return Stance.NEUTRAL


## The player just sold weed at `at`. Cops who see it make the player wanted
## and come for them. If it's on another gang's turf and one of that gang
## sees, they take it as a declaration of war.
func witness_deal(seller: Citizen, at: Vector3) -> void:
	var turf := Territory.at(at)
	var holder: StringName = turf.owner_faction() if turf else &""
	var gang_saw := false
	for witness: Citizen in get_tree().get_nodes_in_group("citizens"):
		if witness == seller or witness.is_down or not witness is Npc:
			continue
		if witness.global_position.distance_to(at) > DEAL_WITNESS_RANGE or not witness._can_see(at):
			continue
		if witness is Cop:
			report_player_crime()
			witness.start_fighting(seller)
		elif witness.faction == holder and is_gang(holder) and holder != PLAYER:
			gang_saw = true
	if gang_saw:
		Transition.show_message("The %s saw you dealing on their turf!" % display_name(holder))
		get_tree().call_group("turf_wars", "start", holder)


func is_gang(faction: StringName) -> bool:
	return faction in GANGS


func display_name(faction: StringName) -> String:
	return NAMES.get(faction, String(faction).capitalize())


func is_player_wanted() -> bool:
	return _now() < _wanted_until


## The police saw the player commit a crime.
func report_player_crime() -> void:
	var was_wanted := is_player_wanted()
	_wanted_until = _now() + WANTED_TIME
	if not was_wanted:
		wanted_changed.emit()


func clear_wanted() -> void:
	if is_player_wanted():
		_wanted_until = 0.0
		wanted_changed.emit()


func wanted_seconds_left() -> float:
	return maxf(_wanted_until - _now(), 0.0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
