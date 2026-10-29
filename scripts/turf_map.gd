extends Node3D
## Carves the city into turf (Territory) and hands it out to the gangs. The
## blocks between the streets that cross the whole city are grouped two by
## two, and each group becomes one big turf, two halves, or four single-block
## turfs, so the map's a patchwork to be taken a piece at a time. Every turf
## goes to the gang whose home ground it's nearest, except the player's crew,
## who start out with just the turf around the player's house.
##
## The patchwork is the same every game (SEED), so turf ids stay put for
## WorldState to remember who holds what.

const SEED := 1987
## Chances for each group of four blocks: one big turf, or two halves (the
## rest are four single blocks).
const WHOLE_CHANCE := 0.45
const HALVES_CHANCE := 0.3
## Gang members out per block of turf, plus BASE_POPULATION.
const BASE_POPULATION := 1
## Kills to take a turf: KILLS_BASE, plus KILLS_PER_BLOCK for each block.
const KILLS_BASE := 4
const KILLS_PER_BLOCK := 3

## Where each gang's turf is centered, in world x/z. Every turf goes to the
## nearest.
@export var gang_homes := {
	&"dummy_gang": Vector2(-45.0, -50.0),
	&"panthers": Vector2(-85.0, 60.0),
	&"yellows": Vector2(85.0, -20.0),
}
## The crew's starting turf is the one with this point in it.
@export var crew_home := Vector2(-95.0, -90.0)


func _ready() -> void:
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid == null:
		return
	var xs := _block_edges(grid, false)
	var zs := _block_edges(grid, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for gz in range(0, zs.size() - 1, 2):
		for gx in range(0, xs.size() - 1, 2):
			var wide := mini(2, xs.size() - 1 - gx)
			var deep := mini(2, zs.size() - 1 - gz)
			for piece in _split(rng.randf(), wide, deep):
				var cell: Rect2i = piece
				cell.position += Vector2i(gx, gz)
				_add_turf(xs, zs, cell)


## The x (or z) edges of the city's blocks: the middles of the streets that
## run the whole way across, plus the edges of the map. A street right by
## the edge would leave a sliver, so it's left out.
func _block_edges(grid: CityGrid, along_x: bool) -> Array[float]:
	var rect := grid.world_rect()
	var low := rect.position.y if along_x else rect.position.x
	var high := rect.end.y if along_x else rect.end.x
	var lines: Array[float] = [low]
	for street in grid.streets():
		if street.along_x == along_x and street.line - low > 12.0 and high - street.line > 12.0:
			lines.append(street.line)
	lines.append(high)
	lines.sort()
	return lines


## How a group of blocks `wide` by `deep` is split up, as cells of blocks.
func _split(roll: float, wide: int, deep: int) -> Array[Rect2i]:
	if roll < WHOLE_CHANCE:
		return [Rect2i(0, 0, wide, deep)]
	if roll < WHOLE_CHANCE + HALVES_CHANCE and deep > 1:
		return [Rect2i(0, 0, wide, 1), Rect2i(0, 1, wide, 1)]
	var singles: Array[Rect2i] = []
	for z in deep:
		for x in wide:
			singles.append(Rect2i(x, z, 1, 1))
	return singles


func _add_turf(xs: Array[float], zs: Array[float], cell: Rect2i) -> void:
	var area := Rect2(xs[cell.position.x], zs[cell.position.y], 0.0, 0.0)
	area.end = Vector2(xs[cell.end.x], zs[cell.end.y])
	var blocks := cell.size.x * cell.size.y
	var turf := Territory.new()
	turf.name = "Turf_%d_%d" % [cell.position.x, cell.position.y]
	turf.id = "turf_%d_%d" % [cell.position.x, cell.position.y]
	turf.area = area
	turf.population = BASE_POPULATION + blocks
	turf.kills_to_take = KILLS_BASE + KILLS_PER_BLOCK * blocks
	turf.starting_owner = Factions.PLAYER if area.has_point(crew_home) else _nearest_gang(area.get_center())
	add_child(turf)


func _nearest_gang(point: Vector2) -> StringName:
	var best: StringName = &""
	var best_distance := INF
	for gang: StringName in gang_homes:
		var distance := point.distance_to(gang_homes[gang])
		if distance < best_distance:
			best = gang
			best_distance = distance
	return best
