extends Control
## A small map in the corner that scrolls with the player. The whole city is
## drawn once from the CityGrid, then each frame the part around the player is
## shown, with turf shaded in each gang's color. MapBlips off the edge of the
## view are pinned to its border, pointing the way.
##
## With whole_map set, it shows the entire city instead, fitted to its size,
## like on the pause menu.

const WATER_COLOR := Color(0.08, 0.2, 0.32)
const BORDER_COLOR := Color(1, 0.88, 0.55)
const PLAYER_COLOR := Color(1, 0.9, 0.2)

## Pixels per tile.
@export var zoom := 3.0
## Shows the whole city, scaled to fit, rather than the part around the player.
@export var whole_map := false

var _texture: ImageTexture
## The map's top-left corner, in world x/z.
var _origin := Vector2.ZERO


func _ready() -> void:
	refresh()
	clip_contents = true


## Draws the city again from the CityGrid in the scene, if there is one.
func refresh() -> void:
	_texture = null
	var grid := get_tree().get_first_node_in_group("city_grid") as CityGrid
	if grid:
		_texture = ImageTexture.create_from_image(grid.map_image(WATER_COLOR))
		_origin = grid.world_rect().position


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER_COLOR)
	var player := get_tree().get_first_node_in_group("player") as Citizen
	if _texture == null or player == null:
		return
	var center := Vector2(player.global_position.x, player.global_position.z)
	var view := Rect2(Vector2.ZERO, size)
	if whole_map:
		var map_size := Vector2(_texture.get_size())
		zoom = minf(size.x / map_size.x, size.y / map_size.y)
		center = _origin + map_size * 0.5

	# The part of the city map around the player.
	var view_tiles := size / zoom
	var source := Rect2(center - _origin - view_tiles * 0.5, view_tiles)
	var texture_rect := Rect2(Vector2.ZERO, Vector2(_texture.get_size()))
	var shown := source.intersection(texture_rect)
	if shown.has_area():
		draw_texture_rect_region(_texture, Rect2((shown.position - source.position) * zoom, shown.size * zoom), shown)

	var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0)
	for turf: Territory in get_tree().get_nodes_in_group("territories"):
		var turf_rect := Rect2(_to_view(turf.area.position, center), turf.area.size * zoom).intersection(view)
		if turf_rect.has_area():
			var tint := turf.color()
			draw_rect(turf_rect, Color(tint, 0.32))
			draw_rect(turf_rect, Color(tint, 0.9), false, 1.5)
			# Fought over: flashing red in a turf war, or the attacking gang's
			# color when one of the player's is under attack.
			var flash := _flash_color(turf)
			if flash.a > 0.0:
				draw_rect(turf_rect, Color(flash, 0.2 + 0.5 * pulse))
				draw_rect(turf_rect, Color(flash, 0.6 + 0.4 * pulse), false, 3.0)

	var font := ThemeDB.fallback_font
	for blip: MapBlip in get_tree().get_nodes_in_group("map_blips"):
		if not blip.is_visible_in_tree():
			continue
		var at := _to_view(Vector2(blip.global_position.x, blip.global_position.z), center)
		# Off the edge: pin it to the border, along the line toward it, so
		# blips off in different directions don't pile up in a corner.
		var half := size * 0.5 - Vector2(8, 8)
		var offset := at - size * 0.5
		if absf(offset.x) > half.x or absf(offset.y) > half.y:
			var fit := minf(half.x / maxf(absf(offset.x), 0.001), half.y / maxf(absf(offset.y), 0.001))
			at = size * 0.5 + offset * fit
		draw_circle(at, 7.0, Color.BLACK)
		draw_circle(at, 6.0, blip.color)
		draw_string(font, at + Vector2(-3.5, 4.0), blip.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.BLACK)

	var middle := _to_view(Vector2(player.global_position.x, player.global_position.z), center)
	var forward := Vector2(player.facing.x, player.facing.z).normalized()
	var vehicle := player.get("vehicle") as Vehicle
	if vehicle:
		forward = Vector2(vehicle.heading.x, vehicle.heading.z).normalized()
	var side := Vector2(-forward.y, forward.x)
	var arrow := PackedVector2Array([middle + forward * 7.0, middle - forward * 4.0 + side * 4.5, middle - forward * 4.0 - side * 4.5])
	draw_colored_polygon(arrow, PLAYER_COLOR)
	draw_polyline(arrow + PackedVector2Array([arrow[0]]), Color.BLACK, 1.0)
	draw_rect(view, BORDER_COLOR, false, 3.0)


func _flash_color(turf: Territory) -> Color:
	if turf.at_war:
		return Color(1.0, 0.1, 0.1)
	if turf.under_attack_by != &"":
		# Black doesn't flash on a dark map: lift it.
		return Factions.COLORS.get(turf.under_attack_by, Color.WHITE).lightened(0.15)
	return Color(0.0, 0.0, 0.0, 0.0)


## World x/z to a point on the minimap, with the player in the middle.
func _to_view(world: Vector2, center: Vector2) -> Vector2:
	return size * 0.5 + (world - center) * zoom
