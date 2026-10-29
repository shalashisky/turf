class_name Fire
extends Node3D
## A patch of burning fuel on the ground, from a Molotov. Anyone who steps in
## it catches fire (Citizen.set_on_fire()), and cars in it burn up
## (Vehicle.damage()), all as an attack by whoever threw it. It burns down
## and goes out, shrinking as it dies, and leaves a scorch mark that fades.
##
## Rain puts it out: the harder it's raining, the faster it burns down, and in
## a downpour a fresh one barely catches. Only outdoors, where the rain falls.

## How often it burns whoever's in it.
const TICK := 0.25
## The last this many seconds, it shrinks and dies down.
const DYING_TIME := 2.0
## Rain makes it burn down up to this many times faster.
const RAIN_QUENCH := 6.0
## Rain this hard, and a fresh fire only flares up for a moment.
const DOWNPOUR := 0.7
const FIZZLE_TIME := 1.0
const SCORCH_TIME := 6.0

@export var radius := 2.2
@export var burn_time := 8.0
@export var vehicle_damage_per_second := 14.0

## Who threw it. Burns count as their attack.
var thrower: Citizen

var _left := 0.0
var _tick_left := 0.0
var _out := false
var _flames: GPUParticles3D
var _light: OmniLight3D
var _scorch: MeshInstance3D
var _crackle: AudioStreamPlayer3D


## How hard the rain is coming down on `node`: Weather's rain if it's out in
## the city, where it rains, and none indoors.
static func rain_on(node: Node) -> float:
	return Weather.intensity if node.get_tree().get_first_node_in_group("rain") else 0.0


## Flames for something burning: a patch of fire, or a person on fire.
static func make_flames(size: Vector3, amount: int) -> GPUParticles3D:
	var flames := GPUParticles3D.new()
	flames.name = "Flames"
	flames.amount = amount
	flames.lifetime = 0.6
	flames.layers = 2
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = size
	process.direction = Vector3.UP
	process.spread = 15.0
	process.initial_velocity_min = 1.2
	process.initial_velocity_max = 2.6
	process.gravity = Vector3(0.0, 1.5, 0.0)
	process.damping_min = 1.0
	process.damping_max = 2.0
	process.scale_min = 0.7
	process.scale_max = 1.3
	var shrink := Curve.new()
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.1))
	var shrink_texture := CurveTexture.new()
	shrink_texture.curve = shrink
	process.scale_curve = shrink_texture
	var colors := Gradient.new()
	colors.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	# Deep colors: bright ones wash out to white on screen.
	colors.colors = PackedColorArray([Color(0.95, 0.75, 0.15), Color(0.95, 0.4, 0.04), Color(0.7, 0.1, 0.02, 0.85), Color(0.12, 0.08, 0.06, 0.0)])
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = colors
	process.color_ramp = color_texture
	flames.process_material = process
	var square := QuadMesh.new()
	square.size = Vector2(0.28, 0.28)
	var look := StandardMaterial3D.new()
	look.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	look.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	look.vertex_color_use_as_albedo = true
	look.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	square.material = look
	flames.draw_pass_1 = square
	return flames


func _ready() -> void:
	add_to_group("fires")
	_left = FIZZLE_TIME if rain_on(self) >= DOWNPOUR else burn_time

	_scorch = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.01
	disc.radial_segments = 16
	var soot := StandardMaterial3D.new()
	soot.albedo_color = Color(0.05, 0.04, 0.04, 0.7)
	soot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc.material = soot
	_scorch.mesh = disc
	_scorch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_scorch.position.y = 0.012
	add_child(_scorch)

	_flames = make_flames(Vector3(radius * 0.7, 0.05, radius * 0.7), 130)
	add_child(_flames)
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.2)
	_light.omni_range = radius + 4.0
	_light.position.y = 1.0
	add_child(_light)
	_crackle = Sound.loop_on(self, &"fire_loop", -2.0)


func _physics_process(delta: float) -> void:
	if _out:
		return
	_left -= delta * (1.0 + rain_on(self) * RAIN_QUENCH)
	var strength := clampf(_left / DYING_TIME, 0.0, 1.0)
	_flames.amount_ratio = strength
	_light.light_energy = strength * randf_range(2.6, 3.6)
	_crackle.volume_db = linear_to_db(maxf(strength, 0.001)) - 2.0
	if _left <= 0.0:
		_go_out()
		return
	_tick_left -= delta
	if _tick_left > 0.0:
		return
	_tick_left = TICK
	var reach := radius * lerpf(0.4, 1.0, strength)
	var blamed := thrower if is_instance_valid(thrower) else null
	for citizen: Citizen in get_tree().get_nodes_in_group("citizens"):
		if _flat_distance(citizen) < reach and citizen.global_position.y < global_position.y + 1.5:
			citizen.set_on_fire(blamed)
	for car: Vehicle in get_tree().get_nodes_in_group("vehicles"):
		# Measured to the car's middle: it's in the fire if any of it is.
		if _flat_distance(car) < reach + 1.4:
			car.damage(vehicle_damage_per_second * TICK, blamed)


func _go_out() -> void:
	_out = true
	_flames.emitting = false
	_crackle.stop()
	_light.light_energy = 0.0
	var tween := create_tween()
	tween.tween_interval(SCORCH_TIME)
	tween.tween_property(_scorch, "transparency", 1.0, 1.5)
	tween.tween_callback(queue_free)


func _flat_distance(node: Node3D) -> float:
	return Vector2(node.global_position.x - global_position.x, node.global_position.z - global_position.z).length()
