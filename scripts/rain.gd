extends Node3D
## Rain falling around the player, as hard as Weather says: streaks that come
## down at a slant and splash where they hit the ground. Drops land on the
## city chunks' particle floors (CityGrid.build_chunk()).

## The rain falls over this much ground around the player, in meters.
@export var area := Vector2(44.0, 34.0)
@export var drops := 3000
## Drops start this high: under the camera, so none fall right past the lens.
@export var height := 9.0
@export var fall_speed := 22.0
## The wind blows the rain this far sideways for every meter it falls.
@export var slant := Vector3(0.18, 0.0, 0.08)

var _rain: GPUParticles3D
var _splashes: GPUParticles3D
var _grid: CityGrid


func _ready() -> void:
	# Where there's rain to put out fires (Fire.rain_on()).
	add_to_group("rain")
	_grid = get_tree().get_first_node_in_group("city_grid")
	_splashes = _build_splashes()
	add_child(_splashes)
	_rain = _build_rain()
	add_child(_rain)
	_rain.sub_emitter = _rain.get_path_to(_splashes)


func _process(_delta: float) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player:
		# Upwind of the player, so the slanted drops land around them.
		global_position = Vector3(player.global_position.x, 0.0, player.global_position.z) - slant * height
	_rain.amount_ratio = Weather.intensity
	_rain.emitting = Weather.intensity > 0.01
	if _grid:
		_grid.set_wetness(Weather.wetness)


func _build_rain() -> GPUParticles3D:
	var rain := GPUParticles3D.new()
	rain.name = "Drops"
	rain.emitting = false
	rain.amount = drops
	var lifetime := height / fall_speed * 1.15
	rain.lifetime = lifetime
	rain.position.y = height
	rain.visibility_aabb = AABB(Vector3(-area.x, -height - 2.0, -area.y), Vector3(area.x * 2.0, height + 4.0, area.y * 2.0))
	rain.layers = 2

	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(area.x * 0.5, 0.5, area.y * 0.5)
	var fall := (Vector3.DOWN + slant).normalized()
	process.direction = fall
	process.spread = 0.0
	process.initial_velocity_min = fall_speed * 0.9
	process.initial_velocity_max = fall_speed * 1.1
	process.gravity = Vector3.ZERO
	process.collision_mode = ParticleProcessMaterial.COLLISION_HIDE_ON_CONTACT
	process.sub_emitter_mode = ParticleProcessMaterial.SUB_EMITTER_AT_COLLISION
	process.sub_emitter_amount_at_collision = 1
	rain.process_material = process

	var streak := QuadMesh.new()
	streak.size = Vector2(0.03, 0.7)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(0.72, 0.8, 0.92, 0.5)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	look.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Clear of the haze, so they show in daylight too, and faded out close
	# to the camera, where they'd look huge.
	look.disable_fog = true
	look.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	look.distance_fade_min_distance = 5.0
	look.distance_fade_max_distance = 9.0
	streak.material = look
	rain.draw_pass_1 = streak
	return rain


func _build_splashes() -> GPUParticles3D:
	var splashes := GPUParticles3D.new()
	splashes.name = "Splashes"
	# Only ever set off by drops landing (the drops' sub-emitter). Left on, it
	# would spray splashes of its own around its origin, at the player's feet.
	splashes.emitting = false
	splashes.amount = 1200
	splashes.lifetime = 0.25
	splashes.layers = 2
	splashes.visibility_aabb = AABB(Vector3(-area.x, -2.0, -area.y), Vector3(area.x * 2.0, 4.0, area.y * 2.0))

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3.UP
	process.spread = 65.0
	process.initial_velocity_min = 0.6
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0.0, -9.0, 0.0)
	splashes.process_material = process

	var droplet := QuadMesh.new()
	droplet.size = Vector2(0.05, 0.05)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.albedo_color = Color(0.8, 0.86, 0.95, 0.55)
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	droplet.material = look
	splashes.draw_pass_1 = droplet
	return splashes
