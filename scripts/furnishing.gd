class_name Furnishing
extends Node3D
## Runs the grow house: what the player's set up in it, and the state it was
## left in. The player sets items down on a grid (WorldState.PLACEABLES, like
## grow trays bought at the shop): while one's in hand, the grid shows on the
## floor with the spot it'd go in front of them (or under the cursor), green
## if it fits, red if something's in the way, and the attack button puts it
## there. Placed trays are kept in WorldState.grow_house_trays.
##
## The first time in, the place is a mess: squatters living there, who fight,
## and piles of trash to haul out. Both stay gone once dealt with.

const TRAY := preload("res://scenes/hydro_tray.tscn")
const SQUATTER := preload("res://scenes/npcs/squatter.tscn")
const TRASH := preload("res://scripts/trash_pile.gd")
## Grid cells are this big, in meters.
const CELL := 1.0
## A tray covers this many cells across and deep.
const TRAY_CELLS := Vector2i(2, 1)
## Squatters' weapons, picked at random (null for fists).
const SQUATTER_WEAPONS := [null, null, "res://weapons/knife.tres", "res://weapons/baseball_bat.tres"]
const GOOD_COLOR := Color(0.3, 1.0, 0.4, 0.4)
const BAD_COLOR := Color(1.0, 0.25, 0.2, 0.4)

## The floor that can be built on, in local x/z: inside the walls.
@export var floor_area := Rect2(-6.0, -4.0, 12.0, 8.0)
## Kept clear so there's a way in and out: in front of the door, in x/z.
@export var doorway := Rect2(-1.0, -4.0, 2.0, 2.0)
## Where squatters are lounging when the player first comes in.
@export var squatter_spots: Array[Vector3] = [Vector3(-4.0, 0, 2.5), Vector3(3.0, 0, 2.8), Vector3(-1.5, 0, 0.5)]
## Where the trash is piled, by id.
@export var trash_spots := {
	"gh_trash_1": Vector3(-4.8, 0, -2.6), "gh_trash_2": Vector3(-2.6, 0, -0.4),
	"gh_trash_3": Vector3(1.9, 0, -1.5), "gh_trash_4": Vector3(4.6, 0, 1.0),
	"gh_trash_5": Vector3(-0.4, 0, 2.9), "gh_trash_6": Vector3(-5.0, 0, 3.0),
	"gh_trash_7": Vector3(2.6, 0, 3.2),
}

var _grid: MeshInstance3D
var _ghost: MeshInstance3D
var _ghost_material: StandardMaterial3D
## Where the item in hand would go, and whether it fits there.
var _spot := Vector3.ZERO
var _fits := false


func _ready() -> void:
	add_to_group("furnishing")
	for id: String in WorldState.grow_house_trays:
		_add_tray(id, WorldState.grow_house_trays[id])
	for id: String in trash_spots:
		if not WorldState.trash_cleared.has(id):
			var pile := TRASH.new()
			pile.trash_id = id
			pile.position = trash_spots[id]
			add_child(pile)
	if not WorldState.squatters_cleared:
		for spot in squatter_spots:
			var squatter: Citizen = SQUATTER.instantiate()
			squatter.position = spot
			var weapon_path: Variant = SQUATTER_WEAPONS.pick_random()
			if weapon_path:
				squatter.starting_weapon = load(weapon_path)
			add_child(squatter)
	_grid = _build_grid()
	add_child(_grid)
	_ghost = _build_ghost()
	add_child(_ghost)


func _process(_delta: float) -> void:
	if not WorldState.squatters_cleared and _squatters_left() == 0:
		WorldState.squatters_cleared = true
	var player := get_tree().get_first_node_in_group("player") as Citizen
	var placing := player != null and Inventory.item_in(Inventory.selected) in WorldState.PLACEABLES and player.vehicle == null
	_grid.visible = placing
	_ghost.visible = placing
	if not placing:
		return
	_spot = _snap(to_local(player.placement_point()))
	_fits = _can_place_at(_spot)
	_ghost.position = _spot + Vector3.UP * 0.45
	_ghost_material.albedo_color = GOOD_COLOR if _fits else BAD_COLOR


## Puts one of `item` from the player's hands down where the grid shows it.
func place(item: String) -> void:
	if item != "grow_tray" or not _grid.visible:
		return
	if not _fits:
		Sound.play(&"click", -4.0)
		return
	if not WorldState.add_item(item, -1):
		return
	var id := "grow_house_tray_%d" % Time.get_ticks_usec()
	WorldState.grow_house_trays[id] = _spot
	_add_tray(id, _spot)
	Sound.play_at(&"body_fall", global_transform * _spot, 0.0)


func _add_tray(id: String, at: Vector3) -> void:
	var tray: Node3D = TRAY.instantiate()
	tray.tray_id = id
	tray.position = at
	add_child(tray)


## The middle of the cells a tray would cover, nearest `point`.
func _snap(point: Vector3) -> Vector3:
	var x := roundf(point.x / CELL) * CELL if TRAY_CELLS.x % 2 == 0 else (floorf(point.x / CELL) + 0.5) * CELL
	var z := roundf(point.z / CELL) * CELL if TRAY_CELLS.y % 2 == 0 else (floorf(point.z / CELL) + 0.5) * CELL
	return Vector3(x, 0.0, z)


## Whether a tray fits at `spot`: on the floor, out of the doorway, and not
## on top of anything or anyone.
func _can_place_at(spot: Vector3) -> bool:
	var footprint := Rect2(spot.x - TRAY_CELLS.x * CELL * 0.5, spot.z - TRAY_CELLS.y * CELL * 0.5, TRAY_CELLS.x * CELL, TRAY_CELLS.y * CELL)
	if not floor_area.encloses(footprint) or footprint.intersects(doorway):
		return false
	var box := BoxShape3D.new()
	box.size = Vector3(TRAY_CELLS.x * CELL - 0.1, 0.8, TRAY_CELLS.y * CELL - 0.1)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = box
	query.transform = global_transform * Transform3D(Basis.IDENTITY, spot + Vector3.UP * 0.5)
	query.collision_mask = 1 | 2
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func _squatters_left() -> int:
	var left := 0
	for squatter in get_tree().get_nodes_in_group("squatters"):
		if not squatter.is_down:
			left += 1
	return left


## Lines on the floor every CELL, over the area that can be built on.
func _build_grid() -> MeshInstance3D:
	var lines := ImmediateMesh.new()
	var look := StandardMaterial3D.new()
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.albedo_color = Color(1.0, 1.0, 1.0, 0.25)
	lines.surface_begin(Mesh.PRIMITIVE_LINES, look)
	var y := 0.02
	var x := floor_area.position.x
	while x <= floor_area.end.x + 0.01:
		lines.surface_add_vertex(Vector3(x, y, floor_area.position.y))
		lines.surface_add_vertex(Vector3(x, y, floor_area.end.y))
		x += CELL
	var z := floor_area.position.y
	while z <= floor_area.end.y + 0.01:
		lines.surface_add_vertex(Vector3(floor_area.position.x, y, z))
		lines.surface_add_vertex(Vector3(floor_area.end.x, y, z))
		z += CELL
	lines.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh = lines
	grid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	grid.visible = false
	return grid


## A see-through box the size of a tray, showing where it'd go.
func _build_ghost() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(TRAY_CELLS.x * CELL - 0.05, 0.9, TRAY_CELLS.y * CELL - 0.05)
	_ghost_material = StandardMaterial3D.new()
	_ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_material.albedo_color = GOOD_COLOR
	box.material = _ghost_material
	var ghost := MeshInstance3D.new()
	ghost.mesh = box
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ghost.visible = false
	return ghost
