extends Control
## A small map of the city in the corner. The tiles are drawn once from the
## CityGrid; each Territory is shaded in its gang's color, and MapBlips and
## the player's arrow are drawn on top, every frame.

const TILE_COLORS := {
	0: Color(0.24, 0.24, 0.27),  # road
	1: Color(0.6, 0.58, 0.55),  # sidewalk
	2: Color(0.42, 0.3, 0.18),  # dirt
	3: Color(0.33, 0.45, 0.22),  # grass
	4: Color(0.62, 0.28, 0.2),  # brick building
	5: Color(0.78, 0.66, 0.48),  # tan building
	6: Color(0.5, 0.36, 0.2),  # crate
	7: Color(0.5, 0.5, 0.52),  # low wall
}
const WATER_COLOR := Color(0.08, 0.2, 0.32)
const BORDER_COLOR := Color(1, 0.88, 0.55)
const PLAYER_COLOR := Color(1, 0.9, 0.2)

var _texture: ImageTexture
## The map's top-left corner, in world space (x, z).
var _origin := Vector2.ZERO
## Map size in tiles.
var _tiles := Vector2.ONE


func _ready() -> void:
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid:
		_build(grid)


func _process(_delta: float) -> void:
	queue_redraw()


func _build(grid: CityGrid) -> void:
	var cells := grid.get_used_cells()
	if cells.is_empty():
		return
	var lo := Vector2i(cells[0].x, cells[0].z)
	var hi := lo
	for cell in cells:
		lo = lo.min(Vector2i(cell.x, cell.z))
		hi = hi.max(Vector2i(cell.x, cell.z))
	var size := hi - lo + Vector2i.ONE
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(WATER_COLOR)
	# Ground level first, then anything stacked on top wins.
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y)
	for cell in cells:
		var color: Color = TILE_COLORS.get(grid.get_cell_item(cell), Color.MAGENTA)
		image.set_pixel(cell.x - lo.x, cell.z - lo.y, color)
	_texture = ImageTexture.create_from_image(image)
	var corner := grid.to_global(grid.map_to_local(Vector3i(lo.x, 0, lo.y)))
	_origin = Vector2(corner.x, corner.z) - Vector2(grid.cell_size.x, grid.cell_size.z) * 0.5
	_tiles = Vector2(size)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER_COLOR)
	if _texture == null:
		return
	var zoom := minf(size.x / _tiles.x, size.y / _tiles.y)
	var offset := (size - _tiles * zoom) * 0.5
	draw_texture_rect(_texture, Rect2(offset, _tiles * zoom), false)

	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		var corner := offset + (turf.area.position - _origin) * zoom
		var turf_rect := Rect2(corner, turf.area.size * zoom).intersection(Rect2(offset, _tiles * zoom))
		var tint := turf.color()
		draw_rect(turf_rect, Color(tint, 0.32))
		draw_rect(turf_rect, Color(tint, 0.9), false, 1.5)

	var font := ThemeDB.fallback_font
	for blip: MapBlip in get_tree().get_nodes_in_group("map_blips"):
		var at := _to_map(blip.global_position, zoom, offset)
		draw_circle(at, 7.0, Color.BLACK)
		draw_circle(at, 6.0, blip.color)
		draw_string(font, at + Vector2(-3.5, 4.0), blip.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

	var player := get_tree().get_first_node_in_group("player") as Citizen
	if player:
		var at := _to_map(player.global_position, zoom, offset)
		var forward := Vector2(player.facing.x, player.facing.z).normalized()
		var side := Vector2(-forward.y, forward.x)
		var arrow := PackedVector2Array([at + forward * 7.0, at - forward * 4.0 + side * 4.5, at - forward * 4.0 - side * 4.5])
		draw_colored_polygon(arrow, PLAYER_COLOR)
		draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.0)
	draw_rect(Rect2(Vector2.ZERO, size), BORDER_COLOR, false, 3.0)


func _to_map(world: Vector3, zoom: float, offset: Vector2) -> Vector2:
	return offset + (Vector2(world.x, world.z) - _origin) * zoom
