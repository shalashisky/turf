class_name ChunkStreamer
extends Node3D
## Streams the world in square chunks around a target, usually the player.
##
## Each chunk is a scene named chunk_<x>_<z>.scn in chunk_directory, covering
## chunk_size x chunk_size meters, with its origin at its minimum corner.
## Chunks within load_radius are kept in the scene. Chunks out to
## prefetch_radius are loaded in the background, so they're ready by the time
## they're needed. A placed chunk is only removed once it's beyond
## unload_radius, so walking back and forth over a border doesn't thrash.
## Radii count chunks, with diagonal neighbors at distance 1.
##
## Loading happens on worker threads. Instantiating stays on the main thread:
## GridMap isn't safe to build on a worker thread in Godot 4.7, and errors
## come out of _octant_update if you try.

signal chunk_placed(coord: Vector2i)
signal chunk_removed(coord: Vector2i)

@export var target: Node3D
@export_dir var chunk_directory := "res://world/test_city"
@export var chunk_size := 32.0
@export var load_radius := 1
@export var prefetch_radius := 2
@export var unload_radius := 2
## Placing a chunk costs a frame spike, so spread them out: at most this many per frame.
@export var max_placements_per_frame := 1
## Freeing a chunk costs even more than placing one, so spread those out too.
@export var max_removals_per_frame := 1

## Placed chunks: Vector2i -> Node3D.
var _placed := {}
## Background loads in flight: Vector2i -> path.
var _loading := {}
## Loaded and ready to place: Vector2i -> PackedScene. Holding the reference
## keeps the scene cached while it's close by.
var _loaded := {}
## Coordinates past the edge of the world, so we stop asking the disk.
var _missing := {}
var _center := Vector2i.ZERO


func _ready() -> void:
	if target == null:
		return
	# Place the starting chunks right away, so the target has ground to stand on.
	_center = chunk_of(target.global_position)
	for coord in _coords_by_distance(load_radius):
		var path := chunk_path(coord)
		if ResourceLoader.exists(path):
			_loaded[coord] = load(path)
			_place(coord)


func _process(_delta: float) -> void:
	if target == null:
		return
	_center = chunk_of(target.global_position)
	_request_nearby()
	_collect_finished_loads()
	_place_ready_chunks()
	_remove_far_chunks()


func chunk_of(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / chunk_size), floori(point.z / chunk_size))


func chunk_path(coord: Vector2i) -> String:
	return "%s/chunk_%d_%d.scn" % [chunk_directory, coord.x, coord.y]


func placed_count() -> int:
	return _placed.size()


func _request_nearby() -> void:
	for coord in _coords_by_distance(prefetch_radius):
		if _placed.has(coord) or _loading.has(coord) or _loaded.has(coord) or _missing.has(coord):
			continue
		var path := chunk_path(coord)
		if not ResourceLoader.exists(path):
			_missing[coord] = true
			continue
		ResourceLoader.load_threaded_request(path)
		_loading[coord] = path


func _collect_finished_loads() -> void:
	for coord: Vector2i in _loading.keys():
		var path: String = _loading[coord]
		match ResourceLoader.load_threaded_get_status(path):
			ResourceLoader.THREAD_LOAD_LOADED:
				_loaded[coord] = ResourceLoader.load_threaded_get(path)
				_loading.erase(coord)
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				push_warning("Couldn't load chunk %s" % path)
				_loading.erase(coord)
				_missing[coord] = true


func _place_ready_chunks() -> void:
	var placed := 0
	for coord in _coords_by_distance(load_radius):
		if placed >= max_placements_per_frame:
			return
		if not _placed.has(coord) and _loaded.has(coord):
			_place(coord)
			placed += 1


func _place(coord: Vector2i) -> void:
	var chunk: Node3D = _loaded[coord].instantiate()
	chunk.name = "Chunk_%d_%d" % [coord.x, coord.y]
	# Position before adding, so everything inside spawns where it belongs.
	chunk.position = Vector3(coord.x * chunk_size, 0.0, coord.y * chunk_size)
	_add_chunk(coord, chunk)


func _add_chunk(coord: Vector2i, chunk: Node3D) -> void:
	add_child(chunk)
	_placed[coord] = chunk
	chunk_placed.emit(coord)


func _remove_far_chunks() -> void:
	var far: Array[Vector2i] = []
	for coord: Vector2i in _placed.keys():
		if _distance(coord, _center) > unload_radius:
			far.append(coord)
	# Farthest first.
	far.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _center).length_squared() > (b - _center).length_squared())
	for coord in far.slice(0, max_removals_per_frame):
		_placed[coord].queue_free()
		_placed.erase(coord)
		chunk_removed.emit(coord)
	# Let go of loaded scenes we've moved well away from, so they leave memory.
	for coord: Vector2i in _loaded.keys():
		if not _placed.has(coord) and _distance(coord, _center) > prefetch_radius:
			_loaded.erase(coord)


## Coordinates within `radius` of the center chunk, nearest first.
func _coords_by_distance(radius: int) -> Array[Vector2i]:
	var coords: Array[Vector2i] = []
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			coords.append(_center + Vector2i(dx, dz))
	coords.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - _center).length_squared() < (b - _center).length_squared())
	return coords


func _distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))
