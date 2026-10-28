extends SceneTree
## Generates a procedural test city as streamable chunk scenes, for measuring
## ChunkStreamer. This is throwaway stress-test content, not real level design.
##
## Run from the project root:
##   godot --headless --path . --script res://tools/generate_test_city.gd
##
## Streets run every BLOCK tiles in both directions, with sidewalks either
## side. Each block in between is buildings, a park, or a vacant lot. Lamps
## line the sidewalks and a couple of dummies wander each chunk.

const OUT_DIR := "res://world/test_city"
const CHUNKS := 20
const CHUNK_TILES := 32
const BLOCK := 16
## One lamp per block on each side of the street, mid-block.
const LAMP_OFFSET := 8
const DUMMIES_PER_CHUNK := 2


# Item ids in tiles/tiles.tres.
const ROAD := 0
const SIDEWALK := 1
const DIRT := 2
const GRASS := 3
const BRICK := 4
const TAN := 5
const CRATE := 6
const LOW_WALL := 7

# Loaded at runtime rather than preloaded: the lamp's script uses the
# GameClock autoload, which doesn't exist yet when this script compiles.
var _tiles: MeshLibrary
var _lamp_scene: PackedScene
var _dummy_scene: PackedScene


func _initialize() -> void:
	_tiles = load("res://tiles/tiles.tres")
	_lamp_scene = load("res://scenes/street_lamp.tscn")
	_dummy_scene = load("res://scenes/dummy_enemy.tscn")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var started := Time.get_ticks_msec()
	var bytes := 0
	for cz in CHUNKS:
		for cx in CHUNKS:
			var chunk := _build_chunk(Vector2i(cx, cz))
			var packed := PackedScene.new()
			packed.pack(chunk)
			var path := "%s/chunk_%d_%d.scn" % [OUT_DIR, cx, cz]
			ResourceSaver.save(packed, path)
			bytes += FileAccess.get_file_as_bytes(path).size()
			chunk.free()
	print("Generated %d chunks (%d x %d m) in %.1f s, %.1f MB on disk" % [
		CHUNKS * CHUNKS, CHUNKS * CHUNK_TILES, CHUNKS * CHUNK_TILES,
		(Time.get_ticks_msec() - started) / 1000.0, bytes / 1048576.0])
	quit()


func _build_chunk(coord: Vector2i) -> Node3D:
	var chunk := Node3D.new()
	chunk.name = "Chunk"
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(coord)

	var grid := GridMap.new()
	grid.name = "Tiles"
	grid.mesh_library = _tiles
	grid.cell_size = Vector3.ONE
	grid.cell_center_y = false
	# One octant for the whole chunk: far fewer draw calls than the default 8.
	grid.cell_octant_size = CHUNK_TILES
	chunk.add_child(grid)
	grid.owner = chunk

	var walkable: Array[Vector3i] = []
	for z in CHUNK_TILES:
		for x in CHUNK_TILES:
			var world := coord * CHUNK_TILES + Vector2i(x, z)
			var stack := _tiles_at(world)
			for height in stack.size():
				grid.set_cell_item(Vector3i(x, height, z), stack[height])
			if stack == [SIDEWALK] or stack == [GRASS]:
				walkable.append(Vector3i(x, 0, z))
			_maybe_add_lamp(chunk, world, Vector3(x + 0.5, 0.0, z + 0.5))

	for i in DUMMIES_PER_CHUNK:
		if walkable.is_empty():
			break
		var cell: Vector3i = walkable[rng.randi() % walkable.size()]
		var dummy: Node3D = _dummy_scene.instantiate()
		dummy.position = Vector3(cell.x + 0.5, 0.0, cell.z + 0.5)
		chunk.add_child(dummy)
		dummy.owner = chunk

	# Blood and dust bounce on this. One per chunk keeps the collider count low.
	var particle_floor := GPUParticlesCollisionBox3D.new()
	particle_floor.name = "ParticleFloor"
	particle_floor.size = Vector3(CHUNK_TILES, 1.0, CHUNK_TILES)
	particle_floor.position = Vector3(CHUNK_TILES * 0.5, -0.5, CHUNK_TILES * 0.5)
	chunk.add_child(particle_floor)
	particle_floor.owner = chunk
	return chunk


## The tiles at a world tile coordinate, from the ground up.
func _tiles_at(world: Vector2i) -> Array:
	var local := Vector2i(posmod(world.x, BLOCK), posmod(world.y, BLOCK))
	if local.x <= 2 or local.y <= 2:
		return [ROAD]
	if local.x == 3 or local.x == BLOCK - 1 or local.y == 3 or local.y == BLOCK - 1:
		return [SIDEWALK]

	# Inside a block. Its look is fixed by the block's position.
	var block := Vector2i(floori(world.x / float(BLOCK)), floori(world.y / float(BLOCK)))
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(block)
	var kind := rng.randf()
	var detail := RandomNumberGenerator.new()
	detail.seed = hash(world)
	if kind < 0.6:
		# Two buildings split by an alley down the middle.
		if local.x == 9:
			return [GRASS]
		return [BRICK if (local.x < 9) == (rng.randf() < 0.5) else TAN]
	if kind < 0.85:
		# A park, with the odd low wall.
		return [LOW_WALL] if detail.randf() < 0.04 else [GRASS]
	# A vacant lot with crates lying around.
	var roll := detail.randf()
	if roll < 0.03:
		return [CRATE, CRATE]
	if roll < 0.08:
		return [CRATE]
	return [DIRT]


func _maybe_add_lamp(chunk: Node3D, world: Vector2i, at: Vector3) -> void:
	var local := Vector2i(posmod(world.x, BLOCK), posmod(world.y, BLOCK))
	if local.x != LAMP_OFFSET:
		return
	# Sidewalk just south of a street faces north over it, and vice versa.
	var yaw := 0.0
	if local.y == 3:
		yaw = PI
	elif local.y != BLOCK - 1:
		return
	var lamp: Node3D = _lamp_scene.instantiate()
	lamp.position = at + Vector3(0.0, 0.0, -0.3 if yaw == PI else 0.3)
	lamp.rotation.y = yaw
	chunk.add_child(lamp)
	lamp.owner = chunk
