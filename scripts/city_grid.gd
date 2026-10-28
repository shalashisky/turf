extends GridMap
## Paints the test block from LAYOUT, but only when the GridMap is empty.
## Once you paint cells in the editor and save, those cells are used instead.

## Characters map to a column of MeshLibrary item ids in tiles/tiles.tres,
## listed from the ground up, so "C" is two crates stacked.
const TILES_BY_CHAR := {
	".": [0], "=": [1], ",": [2], "g": [3], "#": [4], "B": [5],
	"c": [6], "C": [6, 6], "w": [7],
}

## . road   = sidewalk   , dirt plot   g grass   # brick building   B tan building
## c crate   C two stacked crates   w low wall
const LAYOUT := [
	"########=...=BBBBBBBBBBB",
	"########=...=BBBBBBBBBBB",
	"########=...=BBBBBBBBBBB",
	"########=...=BBBBBBBBBBB",
	"########=...=BBBBBBBBBBB",
	"=========...============",
	"........................",
	"........................",
	"........................",
	"=========...============",
	"#####ggg=...=ggg,,,,gggg",
	"#####Ccg=...=ggg,,,,gggg",
	"#####ggg=...=ggg,,,,gggg",
	"#####ggg=...=gwwwgggBBBB",
	"#####ggg=...=gggggggBBBB",
	"########=...=gggggggBBBB",
]


func _ready() -> void:
	if get_used_cells().is_empty():
		_paint_layout()
	_add_particle_floor()


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
