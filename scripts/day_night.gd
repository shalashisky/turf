extends Node
## Lights the world to match GameClock: the sun arcs across the sky by day, a
## dimmer bluish moon takes over at night, and the sun color, sky and ambient
## light blend between keyframes for dawn, day, sunset, dusk and night.

## One look per keyframe, at an hour of the day (0-24). Times in between blend.
## Light energy dips near zero around 5:45 and 20:45, where the sun hands over
## to the moon, so the jump in light direction isn't visible.
const KEYFRAMES := [
	# hour, light color, light energy, ambient energy, sky top, sky horizon
	[0.0, Color(0.5, 0.6, 1.0), 0.3, 0.45, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.17)],
	[5.0, Color(0.5, 0.6, 1.0), 0.3, 0.45, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.17)],
	[5.75, Color(0.8, 0.6, 0.7), 0.05, 0.45, Color(0.1, 0.1, 0.25), Color(0.5, 0.35, 0.4)],
	[6.5, Color(1.0, 0.62, 0.42), 0.7, 0.6, Color(0.25, 0.3, 0.55), Color(0.98, 0.62, 0.45)],
	[8.5, Color(1.0, 0.92, 0.8), 0.95, 0.7, Color(0.32, 0.52, 0.85), Color(0.75, 0.82, 0.9)],
	[12.0, Color(1.0, 0.98, 0.92), 1.05, 0.75, Color(0.3, 0.55, 0.9), Color(0.78, 0.86, 0.95)],
	[16.5, Color(1.0, 0.88, 0.68), 0.95, 0.7, Color(0.32, 0.48, 0.8), Color(0.92, 0.78, 0.6)],
	[18.75, Color(1.0, 0.55, 0.32), 0.85, 0.65, Color(0.25, 0.2, 0.42), Color(0.95, 0.58, 0.4)],
	[20.0, Color(0.85, 0.45, 0.45), 0.35, 0.5, Color(0.1, 0.08, 0.22), Color(0.45, 0.25, 0.35)],
	[20.75, Color(0.6, 0.55, 0.9), 0.05, 0.45, Color(0.04, 0.04, 0.12), Color(0.15, 0.12, 0.25)],
	[22.0, Color(0.5, 0.6, 1.0), 0.3, 0.45, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.17)],
	[24.0, Color(0.5, 0.6, 1.0), 0.3, 0.45, Color(0.02, 0.03, 0.08), Color(0.07, 0.08, 0.17)],
]
## When the sun is up. Outside this the light acts as the moon.
const SUNRISE := 5.75
const SUNSET := 20.75

@export var light: DirectionalLight3D
@export var world_environment: WorldEnvironment
## Sun height at sunrise and sunset, and at midday, in degrees. Kept off the
## horizon so shadows don't stretch across the whole map.
@export var sun_low_elevation := 15.0
@export var sun_high_elevation := 62.0
@export var moon_elevation := 45.0
## The sun swings this far either side of due south, in degrees. Light from
## the camera's side keeps the sprites' faces lit.
@export var sun_swing := 60.0

var _sky: ProceduralSkyMaterial


func _ready() -> void:
	_sky = world_environment.environment.sky.sky_material


func _process(_delta: float) -> void:
	var hour := GameClock.hour_of_day()
	_apply_keyframes(hour)
	_aim_light(hour)


func _apply_keyframes(hour: float) -> void:
	var next := 1
	while next < KEYFRAMES.size() - 1 and KEYFRAMES[next][0] <= hour:
		next += 1
	var a: Array = KEYFRAMES[next - 1]
	var b: Array = KEYFRAMES[next]
	var t := smoothstep(a[0], b[0], hour)

	light.light_color = (a[1] as Color).lerp(b[1], t)
	light.light_energy = lerpf(a[2], b[2], t)
	world_environment.environment.ambient_light_energy = lerpf(a[3], b[3], t)
	var top := (a[4] as Color).lerp(b[4], t)
	var horizon := (a[5] as Color).lerp(b[5], t)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = top.darkened(0.5)


func _aim_light(hour: float) -> void:
	var elevation: float
	var azimuth: float
	if hour >= SUNRISE and hour < SUNSET:
		var t := inverse_lerp(SUNRISE, SUNSET, hour)
		elevation = lerpf(sun_low_elevation, sun_high_elevation, sin(t * PI))
		azimuth = lerpf(sun_swing, -sun_swing, t)  # rises in the east, sets in the west
	else:
		var night_length := 24.0 - SUNSET + SUNRISE
		var t := fposmod(hour - SUNSET, 24.0) / night_length
		elevation = moon_elevation
		azimuth = lerpf(sun_swing * 0.6, -sun_swing * 0.6, t)
	light.rotation = Vector3(deg_to_rad(-elevation), deg_to_rad(azimuth), 0.0)
