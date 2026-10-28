class_name Territory
extends Node3D
## A gang's turf: a rectangle of the city held by one of Factions.GANGS. Who
## holds it is saved in WorldState under `id`. A gang holding turf keeps it
## populated, its members mostly stay inside it, and every so often it sends a
## few of them to stir up trouble on a rival's turf. The player's crew holds
## turf too, but doesn't need populating.

## How often to check whether the gang needs more people out, in seconds.
const RESTOCK_INTERVAL := 4.0

@export var id := "turf"
@export var starting_owner := &"dummy_gang"
## The ground covered, in world x/z.
@export var area := Rect2()
## Gang members kept out and about.
@export var population := 6
## Chance that each one carries a weapon from weapon_pool instead of fists.
@export_range(0.0, 1.0) var armed_chance := 0.35
@export var weapon_pool: Array = [
	preload("res://weapons/baseball_bat.tres"),
	preload("res://weapons/knife.tres"),
	preload("res://weapons/brass_knuckles.tres"),
	preload("res://weapons/knife.tres"),
	preload("res://weapons/pistol.tres"),
	preload("res://weapons/tec9.tres"),
	preload("res://weapons/molotov.tres"),
]
## New members show up this far from the player: out of sight, but close
## enough to be in the part of the city that's loaded.
@export var spawn_distance := Vector2(18.0, 34.0)
## Seconds between raids on rival turf.
@export var raid_interval := Vector2(35.0, 70.0)
@export var raid_size := Vector2i(2, 3)

## Set by TurfWar while this turf is being fought over. No restocking then:
## the gang's doors send reinforcements instead.
var at_war := false

var _spots: Array[Vector3] = []
var _members: Array[GangMember] = []
var _restock_left := 0.0
var _raid_left := 0.0


func _ready() -> void:
	add_to_group("territories")
	_raid_left = randf_range(raid_interval.x, raid_interval.y)
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid:
		# Off the roads, so they're not forever in front of traffic.
		_spots = grid.open_ground_in(area, [CityGrid.SIDEWALK, 2, 3])
	if _populated():
		for i in population:
			spawn_member()


func owner_faction() -> StringName:
	return WorldState.territory_owner(id, starting_owner)


func color() -> Color:
	return Factions.COLORS.get(owner_faction(), Color.GRAY)


func contains(point: Vector3) -> bool:
	return area.has_point(Vector2(point.x, point.z))


func center() -> Vector3:
	var middle := area.get_center()
	return Vector3(middle.x, 0.0, middle.y)


## A random walkable spot inside the turf.
func random_spot() -> Vector3:
	return _spots.pick_random() if not _spots.is_empty() else center()


## A random walkable spot inside the turf, between `distance.x` and
## `distance.y` from `point`. INF if there isn't one.
func random_spot_near(point: Vector3, distance: Vector2) -> Vector3:
	for attempt in 40:
		var spot := random_spot()
		var away := spot.distance_to(point)
		if away >= distance.x and away <= distance.y:
			return spot
	return Vector3.INF


## Sends out a new member of the gang that holds the turf, out of the player's sight.
func spawn_member() -> GangMember:
	var path: String = Factions.MEMBER_SCENES.get(owner_faction(), "")
	if path.is_empty() or _spots.is_empty():
		return null
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return null
	var spot := random_spot_near(player.global_position, spawn_distance)
	if spot == Vector3.INF:
		return null
	var member: GangMember = load(path).instantiate()
	if not weapon_pool.is_empty() and randf() < armed_chance:
		member.starting_weapon = weapon_pool.pick_random()
	member.home = self
	member.position = to_local(spot)
	add_child(member)
	_members.append(member)
	return member


## Drops off a new member at `point`, like out of a car, already after `target`.
func deliver_member(point: Vector3, target: Citizen) -> GangMember:
	var path: String = Factions.MEMBER_SCENES.get(owner_faction(), "")
	if path.is_empty():
		return null
	var member: GangMember = load(path).instantiate()
	if not weapon_pool.is_empty() and randf() < armed_chance:
		member.starting_weapon = weapon_pool.pick_random()
	member.home = self
	member.position = to_local(point)
	add_child(member)
	member.reset_physics_interpolation()
	if target:
		member.start_fighting(target)
	return member


## The turf just changed hands. The old gang's people head for other turf they hold.
func handed_over() -> void:
	var fallback: Territory = null
	for other: Territory in get_tree().get_nodes_in_group("territories"):
		if other != self and other.owner_faction() == starting_owner:
			fallback = other
	for member in _living_members():
		member.home = fallback
		member.stop_fighting()
	_members.clear()


func _process(delta: float) -> void:
	if not _populated():
		return
	_restock_left -= delta
	if _restock_left <= 0.0:
		_restock_left = RESTOCK_INTERVAL
		if not at_war and _living_members().size() < population:
			spawn_member()
	_raid_left -= delta
	if _raid_left <= 0.0 and not at_war:
		_raid_left = randf_range(raid_interval.x, raid_interval.y)
		_send_raid()


## Whether this turf's gang needs people out on the street.
func _populated() -> bool:
	var gang := owner_faction()
	return Factions.is_gang(gang) and gang != Factions.PLAYER


func _living_members() -> Array[GangMember]:
	var living: Array[GangMember] = []
	for member in _members:
		if is_instance_valid(member) and not member.is_dead:
			living.append(member)
	_members = living
	return _members


## A few idle members go looking for trouble on a rival's turf.
func _send_raid() -> void:
	var rivals: Array[Territory] = []
	for other: Territory in get_tree().get_nodes_in_group("territories"):
		if other != self and Factions.stance(owner_faction(), other.owner_faction()) == Factions.Stance.HOSTILE:
			rivals.append(other)
	if rivals.is_empty():
		return
	# Somewhere on their turf near the player, so the raid happens where it can be seen.
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var target_turf: Territory = rivals.pick_random()
	var spot := target_turf.random_spot_near(player.global_position, Vector2(0.0, 30.0))
	if spot == Vector3.INF:
		return
	var idle := _living_members().filter(func(m: GangMember) -> bool: return m.target == null)
	idle.shuffle()
	for member in idle.slice(0, randi_range(raid_size.x, raid_size.y)):
		member.raid(spot + Vector3(randf_range(-1.5, 1.5), 0.0, randf_range(-1.5, 1.5)))
