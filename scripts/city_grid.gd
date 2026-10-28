class_name CityGrid
extends GridMap
## Paints the city from LAYOUT, but only when the GridMap is empty.
## Once you paint cells in the editor and save, those cells are used instead.

## Characters map to a column of MeshLibrary item ids in tiles/tiles.tres,
## listed from the ground up, so "C" is two crates stacked.
## MeshLibrary item ids for the tiles other scripts care about.
const ROAD := 0
const SIDEWALK := 1

const TILES_BY_CHAR := {
	".": [0], "=": [1], ",": [2], "g": [3], "#": [4], "B": [5],
	"c": [6], "C": [6, 6], "w": [7],
}

## . road   = sidewalk   , dirt plot   g grass   # brick building   B tan building
## c crate   C two stacked crates   w low wall
const LAYOUT := [
	"BBBBBBBB=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"BBBBBBBB=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"BBBBBBBB=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"=========...=====================...=====================...============",
	"........................................................................",
	"........................................................................",
	"........................................................................",
	"=========...=====================...=====================...============",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g########g#=...=BBBBBBBBgBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,c=...=########g##########=...=BBBBBBBBBBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g##########=...=BBBBBBBBBBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g##########=...=BBBBBBBBBBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g##########=...=BBBBBBBBBBBBBBBBBgB=...=BBBBBBBBgBB",
	",,,,,,,,=...=########g##########=...=BBBBBBBBBBBBBBBBBgB=...=BBBBBBBBgBB",
	"=========...=====================...=====================...============",
	"........................................................................",
	"........................................................................",
	"........................................................................",
	"=========...=====================...=====================...============",
	"########=...=########g#######ggg=...=ggg,,,,gggggggggggg=...=ggggwgggggg",
	"########=...=########g#######Ccg=...=ggg,,,,gggggggggggg=...=ggggggggggg",
	"########=...=########g#######ggg=...=ggg,,,,gggggggggggg=...=ggggggggggg",
	"########=...=########g#######ggg=...=gwwwgggBBBBggggwggg=...=ggggggggggg",
	"########=...=########g#######ggg=...=gggggggBBBBgggwgggg=...=ggggggggggw",
	"########=...=########g##########=...=gggggggBBBBgggwgggg=...=ggggggggggg",
	"########=...=########g########g#=...=ggggggggggggggggggg=...=ggggggggggg",
	"########=...=########g########g#=...=ggggggggggggggggggg=...=ggggggwggwg",
	"########=...=########g########g#=...=ggwgggggggggggggggg=...=gwggggggggg",
	"########=...=########g########g#=...=gggggwggggggggggggg=...=ggggggggggg",
	"########=...=########g########g#=...=ggggggggggggggggggg=...=ggggggggggg",
	"########=...=########g########g#=...=ggggggggggggggggggg=...=ggggggggggg",
	"########=...=########g########g#=...=ggggggggggggggggggg=...=ggggggggggg",
	"=========...=====================...=====================...============",
	"........................................................................",
	"........................................................................",
	"........................................................................",
	"=========...=====================...=====================...============",
	"########=...=cC,,,C,,,,,,,,,,,,,=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"########=...=,,,,,,,,,,,,,,,,,,,=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"########=...=,,,,,,,,,,,,,,,,c,,=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
	"########=...=,,,,,,,,,,,,,,c,,,,=...=BBBBBBBBgBBBBBBBBgB=...=########g##",
]


func _ready() -> void:
	add_to_group("city_grid")
	if get_used_cells().is_empty():
		_paint_layout()
	_add_particle_floor()


## The ground tile under a world position, like ROAD or SIDEWALK, or
## INVALID_CELL_ITEM off the map.
func tile_at(point: Vector3) -> int:
	var cell := local_to_map(to_local(point))
	cell.y = 0
	return get_cell_item(cell)


## The middle of the ground tile under a world position, at that position's height.
func tile_center(point: Vector3) -> Vector3:
	var cell := local_to_map(to_local(point))
	cell.y = 0
	var center := to_global(map_to_local(cell))
	center.y = point.y
	return center


## The streets that run the whole width or height of the map, for cars:
## each is {"along_x": bool, "line": float} where `line` is the world z (for
## streets running along x) or x (along z) down the middle of the road.
func streets() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var cells := get_used_cells()
	if cells.is_empty():
		return result
	var lo := Vector2i(cells[0].x, cells[0].z)
	var hi := lo
	for cell in cells:
		lo = lo.min(Vector2i(cell.x, cell.z))
		hi = hi.max(Vector2i(cell.x, cell.z))
	for along_x in [true, false]:
		var run_start := -1
		var first := lo.y if along_x else lo.x
		var last := hi.y if along_x else hi.x
		for i in range(first, last + 2):
			var all_road := i <= last
			if all_road:
				for j in range(lo.x if along_x else lo.y, (hi.x if along_x else hi.y) + 1):
					var cell := Vector3i(j, 0, i) if along_x else Vector3i(i, 0, j)
					if get_cell_item(cell) != ROAD:
						all_road = false
						break
			if all_road and run_start < 0:
				run_start = i
			elif not all_road and run_start >= 0:
				# The middle of this run of road rows (or columns), in world space.
				var middle := (run_start + i) * 0.5
				var probe := to_global(map_to_local(Vector3i(0, 0, 0)))
				var line := (middle * cell_size.z + probe.z - cell_size.z * 0.5) if along_x \
					else (middle * cell_size.x + probe.x - cell_size.x * 0.5)
				result.append({"along_x": along_x, "line": line})
				run_start = -1
	return result


## The middle of every sidewalk tile, in world space.
func sidewalk_centers() -> Array[Vector3]:
	var centers: Array[Vector3] = []
	for cell in get_used_cells_by_item(SIDEWALK):
		if cell.y == 0:
			var center := to_global(map_to_local(cell))
			center.y = global_position.y
			centers.append(center)
	return centers


## A flat floor at ground level under the whole map, for GPU particles like
## blood to bounce on. Particle heightfields don't pick up GridMap tiles, so
## this stands in for them. Past the map's footprint, particles fall into the water.
func _add_particle_floor() -> void:
	var cells := get_used_cells()
	if cells.is_empty():
		return
	var lo := Vector2(cells[0].x, cells[0].z)
	var hi := lo
	for cell in cells:
		lo = lo.min(Vector2(cell.x, cell.z))
		hi = hi.max(Vector2(cell.x, cell.z))
	var size := (hi - lo + Vector2.ONE) * Vector2(cell_size.x, cell_size.z)
	var center := (lo + hi + Vector2.ONE) * 0.5 * Vector2(cell_size.x, cell_size.z)
	var floor_box := GPUParticlesCollisionBox3D.new()
	floor_box.name = "ParticleFloor"
	floor_box.size = Vector3(size.x, 1.0, size.y)
	floor_box.position = Vector3(center.x, -0.5, center.y)
	add_child(floor_box)


func _paint_layout() -> void:
	# Center the layout on the world origin.
	var half_width: int = LAYOUT[0].length() >> 1
	var half_height: int = LAYOUT.size() >> 1
	for row in LAYOUT.size():
		var line: String = LAYOUT[row]
		for column in line.length():
			var stack: Array = TILES_BY_CHAR.get(line[column], [])
			for height in stack.size():
				set_cell_item(Vector3i(column - half_width, height, row - half_height), stack[height])
