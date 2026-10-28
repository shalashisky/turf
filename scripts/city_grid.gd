class_name CityGrid
extends Node3D
## The city's ground, read from world/city_layout.txt (made by
## tools/make_city_layout.py). Answers questions about any spot on the map,
## whether or not that part is loaded, and builds the scenery for one chunk at
## a time for the ChunkStreamer (see build_chunk()): the tiles, street lamps
## along the curbs, and a floor for particles to land on.
##
## The map is centered on the world origin, one tile per meter.

## MeshLibrary item ids for the tiles other scripts care about.
const ROAD := 0
const SIDEWALK := 1
const INVALID_TILE := -1
## Cars keep this far right of the middle of the road, on the five-tile
## streets: one lane each way, with room to spare for the lamp posts.
const LANE_OFFSET := 1.1

## Layout characters to MeshLibrary item ids in tiles/tiles.tres, listed from
## the ground up, so "C" is two crates stacked.
## . road   = sidewalk   , dirt plot   g grass   # brick building   B tan building
## c crate   C two stacked crates   w low wall
const TILES_BY_CHAR := {
	".": [0], "=": [1], ",": [2], "g": [3], "#": [4], "B": [5],
	"c": [6], "C": [6, 6], "w": [7],
}
const MAP_COLORS := {
	0: Color(0.24, 0.24, 0.27),
	1: Color(0.6, 0.58, 0.55),
	2: Color(0.42, 0.3, 0.18),
	3: Color(0.33, 0.45, 0.22),
	4: Color(0.62, 0.28, 0.2),
	5: Color(0.78, 0.66, 0.48),
	6: Color(0.5, 0.36, 0.2),
	7: Color(0.5, 0.5, 0.52),
}
## Colors of the see-through building tiles, set when the city loads. (They're
## also saved in tiles.tres, but the editor has a habit of dropping shader
## parameters from it.)
const CUTOUT_COLORS := {
	4: Color(0.55, 0.25, 0.18),
	5: Color(0.72, 0.62, 0.45),
	6: Color(0.5, 0.36, 0.2),
	7: Color(0.48, 0.48, 0.5),
}
const LAYOUT_PATH := "res://world/city_layout.txt"
## Wet ground is this much darker, and paved ground this smooth.
const WET_DARKENING := 0.35
const WET_ROUGHNESS := 0.15
## Street lamps stand this far from the middle of their sidewalk tile, out at
## the curb, clear of people walking by.
const LAMP_CURB_OFFSET := 0.58
## No lamp within this distance of a door.
const LAMP_DOOR_CLEARANCE := 1.4
## Nor in front of a garage, across the road, where the car pulls in and out:
## this far either side of the doorway, and this far out from it.
const LAMP_GARAGE_CLEARANCE := Vector2(3.5, 9.0)

@export var chunk_tiles := 32
## A lamp every this many tiles along each curb.
@export var lamp_spacing := 8

## Map size in tiles.
var size := Vector2i.ZERO

var _rows: PackedStringArray
var _tiles: MeshLibrary
var _lamp_scene: PackedScene
var _streets: Array[Dictionary] = []
## The dry look of the ground tiles, to go back to: {item: [albedo, roughness]}.
var _dry_ground := {}
var _wetness := 0.0
## Tiles whose lamps were knocked over today. They're back tomorrow.
var _knocked_lamps := {}


func _ready() -> void:
	add_to_group("city_grid")
	_tiles = load("res://tiles/tiles.tres")
	for item: int in CUTOUT_COLORS:
		var material := _tiles.get_item_mesh(item).surface_get_material(0) as ShaderMaterial
		if material:
			material.set_shader_parameter("albedo", CUTOUT_COLORS[item])
	_lamp_scene = load("res://scenes/street_lamp.tscn")
	_rows = FileAccess.get_file_as_string(LAYOUT_PATH).strip_edges().split("\n")
	size = Vector2i(_rows[0].length(), _rows.size())
	GameClock.day_started.connect(func(_day: int) -> void: _knocked_lamps.clear())
	# The tile materials are shared and outlive this scene: dry them off.
	tree_exiting.connect(set_wetness.bind(0.0))


## Makes the ground look wet: darker and shiny, from 0 (dry) to 1 (soaked).
func set_wetness(wetness: float) -> void:
	if absf(wetness - _wetness) < 0.01 and not (wetness == 0.0 and _wetness != 0.0):
		return
	_wetness = wetness
	for item: int in [ROAD, SIDEWALK, 2, 3]:
		var material := _tiles.get_item_mesh(item).surface_get_material(0) as StandardMaterial3D
		if material == null:
			continue
		if not _dry_ground.has(item):
			_dry_ground[item] = [material.albedo_color, material.roughness]
		var dry: Array = _dry_ground[item]
		material.albedo_color = (dry[0] as Color).darkened(WET_DARKENING * wetness)
		# Paved ground shines when it's wet; dirt and grass only a little.
		var wet_roughness := WET_ROUGHNESS if item in [ROAD, SIDEWALK] else 0.6
		material.roughness = lerpf(dry[1], wet_roughness, wetness)


## The map's footprint in world x/z.
func world_rect() -> Rect2:
	return Rect2(-size.x / 2.0, -size.y / 2.0, size.x, size.y)


## The ground tile under a world position, like ROAD or SIDEWALK, or
## INVALID_TILE off the map.
func tile_at(point: Vector3) -> int:
	var stack := _stack_at(_tile_of(point))
	return stack[0] if not stack.is_empty() else INVALID_TILE


## The middle of the tile under a world position, at that position's height.
func tile_center(point: Vector3) -> Vector3:
	return Vector3(floorf(point.x) + 0.5, point.y, floorf(point.z) + 0.5)


## The middle of every sidewalk tile, in world space.
func sidewalk_centers() -> Array[Vector3]:
	return open_ground_in(world_rect(), [SIDEWALK])


## The middle of every tile in `area` someone can walk on: road, sidewalk,
## dirt or grass, or just the tile kinds in `kinds` if given.
func open_ground_in(area: Rect2, kinds: Array = [0, 1, 2, 3]) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	var first := _tile_of(Vector3(area.position.x, 0.0, area.position.y))
	var last := _tile_of(Vector3(area.end.x - 0.01, 0.0, area.end.y - 0.01))
	for y in range(maxi(first.y, 0), mini(last.y, size.y - 1) + 1):
		for x in range(maxi(first.x, 0), mini(last.x, size.x - 1) + 1):
			var stack := _stack_at(Vector2i(x, y))
			if stack.size() == 1 and stack[0] in kinds:
				spots.append(_tile_world_center(Vector2i(x, y)))
	return spots


## The streets that run the whole width or height of the map, for cars:
## each is {"along_x": bool, "line": float} where `line` is the world z (for
## streets running along x) or x (along z) down the middle of the road.
func streets() -> Array[Dictionary]:
	if _streets.is_empty():
		_streets = _find_streets()
	return _streets


## Where a car should come in, stop and leave to drop people off near
## `near`: along the nearest street (that `accept` takes, given a point on
## it), in the right-hand lane, coming in and leaving `distance` away along
## the street. A Dictionary with "from", "drop" and "exit", or empty.
func drop_off_route(near: Vector3, distance: float, stop_short: float, accept := Callable()) -> Dictionary:
	var best_drop := Vector3.INF
	var best_along := Vector3.ZERO
	var best_distance := INF
	for street in streets():
		var along := Vector3.RIGHT if street.along_x else Vector3.BACK
		var nearest := Vector3(near.x, 0.0, street.line) if street.along_x else Vector3(street.line, 0.0, near.z)
		if accept.is_valid() and not accept.call(nearest):
			continue
		var away := nearest.distance_to(near)
		if away < best_distance:
			best_distance = away
			best_drop = nearest
			best_along = along
	if best_drop == Vector3.INF:
		return {}
	# Come in from one end, off-screen, and leave by the other.
	var ends := [best_drop - best_along * distance, best_drop + best_along * distance]
	ends.shuffle()
	var heading: Vector3 = (ends[1] - ends[0]).normalized()
	var lane := Vector3(-heading.z, 0.0, heading.x) * LANE_OFFSET
	return {"from": ends[0] + lane, "drop": best_drop - heading * stop_short + lane, "exit": ends[1] + lane}


## A lamp knocked over at `point` stays down until tomorrow, even if its
## chunk is unloaded and built again.
func forget_lamp(point: Vector3) -> void:
	_knocked_lamps[_tile_of(point)] = true


func _find_streets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for along_x in [true, false]:
		var count := size.y if along_x else size.x
		var run_start := -1
		for i in range(count + 1):
			var all_road := i < count and _is_all_road(i, along_x)
			if all_road and run_start < 0:
				run_start = i
			elif not all_road and run_start >= 0:
				var middle := (run_start + i) * 0.5
				var line := middle - (size.y if along_x else size.x) / 2.0
				result.append({"along_x": along_x, "line": line})
				run_start = -1
	return result


## The whole map as a picture, one pixel per tile, for the minimap.
func map_image(water: Color) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(water)
	for y in size.y:
		for x in size.x:
			var stack := _stack_at(Vector2i(x, y))
			if not stack.is_empty():
				image.set_pixel(x, y, MAP_COLORS.get(stack[-1], Color.MAGENTA))
	return image


## Whether chunk `coord` covers any of the map.
func has_chunk(coord: Vector2i) -> bool:
	var chunk_rect := Rect2(coord.x * chunk_tiles, coord.y * chunk_tiles, chunk_tiles, chunk_tiles)
	return chunk_rect.intersects(world_rect())


## Builds the scenery for chunk `coord`: a node to place at the chunk's
## corner (coord * chunk_tiles in world x/z).
func build_chunk(coord: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	var grid := GridMap.new()
	grid.name = "Tiles"
	grid.mesh_library = _tiles
	grid.cell_size = Vector3.ONE
	grid.cell_center_y = false
	# One octant for the whole chunk: far fewer draw calls than the default.
	grid.cell_octant_size = chunk_tiles
	chunk.add_child(grid)

	var doors := _door_positions()
	var corner := _tile_of(Vector3(coord.x * chunk_tiles, 0.0, coord.y * chunk_tiles))
	for z in chunk_tiles:
		for x in chunk_tiles:
			var tile := corner + Vector2i(x, z)
			var stack := _stack_at(tile)
			for height in stack.size():
				grid.set_cell_item(Vector3i(x, height, z), stack[height])
			if stack == [SIDEWALK]:
				_maybe_add_lamp(chunk, tile, Vector3(x + 0.5, 0.0, z + 0.5), doors)

	# Blood and dust bounce on this. One per chunk keeps the collider count low.
	var particle_floor := GPUParticlesCollisionBox3D.new()
	particle_floor.size = Vector3(chunk_tiles, 1.0, chunk_tiles)
	particle_floor.position = Vector3(chunk_tiles * 0.5, -0.5, chunk_tiles * 0.5)
	chunk.add_child(particle_floor)
	return chunk


func _maybe_add_lamp(chunk: Node3D, tile: Vector2i, at: Vector3, doors: Array[Vector3]) -> void:
	for toward_road: Vector2i in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var along := tile.x if toward_road.x == 0 else tile.y
		if posmod(along, lamp_spacing) != (lamp_spacing >> 1) or _stack_at(tile + toward_road) != [ROAD]:
			continue
		var direction := Vector3(toward_road.x, 0.0, toward_road.y)
		var world := _tile_world_center(tile) + direction * LAMP_CURB_OFFSET
		if _knocked_lamps.has(_tile_of(world)):
			return
		for door in doors:
			if world.distance_to(door) < LAMP_DOOR_CLEARANCE:
				return
		for garage: Node3D in get_tree().get_nodes_in_group("garages"):
			var from_garage := garage.to_local(world)
			if absf(from_garage.x) < LAMP_GARAGE_CLEARANCE.x and from_garage.z > -1.0 and from_garage.z < LAMP_GARAGE_CLEARANCE.y:
				return
		var lamp: Node3D = _lamp_scene.instantiate()
		lamp.position = at + direction * LAMP_CURB_OFFSET
		# The lamp's arm reaches along its +Z, out over the road.
		lamp.rotation.y = atan2(direction.x, direction.z)
		chunk.add_child(lamp)
		return


func _door_positions() -> Array[Vector3]:
	var doors: Array[Vector3] = []
	for group in ["spawn_doors", "safe_doors", "entrance_doors"]:
		for door: Node3D in get_tree().get_nodes_in_group(group):
			doors.append(door.global_position)
	return doors


func _is_all_road(index: int, along_x: bool) -> bool:
	var count := size.x if along_x else size.y
	for j in count:
		var tile := Vector2i(j, index) if along_x else Vector2i(index, j)
		if _stack_at(tile) != [ROAD]:
			return false
	return true


## Layout tile under a world position. Tile (0, 0) is the map's top-left corner.
func _tile_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x) + (size.x >> 1), floori(point.z) + (size.y >> 1))


func _tile_world_center(tile: Vector2i) -> Vector3:
	return Vector3(tile.x - (size.x >> 1) + 0.5, 0.0, tile.y - (size.y >> 1) + 0.5)


func _stack_at(tile: Vector2i) -> Array:
	if tile.x < 0 or tile.y < 0 or tile.x >= size.x or tile.y >= size.y:
		return []
	return TILES_BY_CHAR.get(_rows[tile.y][tile.x], [])
