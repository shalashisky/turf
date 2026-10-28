shader_type spatial;
render_mode blend_mix, cull_back, specular_schlick_ggx;
// Stylized harbor water: rolling waves, deeper color away from anything solid,
// and ragged foam where the surface meets the shore or a swimmer.

uniform vec4 shallow_color : source_color = vec4(0.2, 0.5, 0.55, 0.7);
uniform vec4 deep_color : source_color = vec4(0.04, 0.15, 0.24, 0.95);
uniform vec4 foam_color : source_color = vec4(0.9, 0.95, 1.0, 0.85);
uniform vec4 ripple_color : source_color = vec4(0.35, 0.62, 0.7, 1.0);
// How strongly the drifting ripple lines show.
uniform float ripple_strength = 0.35;
// Distance below the surface, in meters, over which shallow fades to deep.
uniform float depth_fade_distance = 2.0;
uniform float foam_distance = 0.2;
uniform float wave_height = 0.035;
uniform float wave_speed = 1.2;
uniform float ripple_scale = 1.6;

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(cell);
	float b = hash(cell + vec2(1.0, 0.0));
	float c = hash(cell + vec2(0.0, 1.0));
	float d = hash(cell + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float wave(vec2 p, float t) {
	return sin(p.x * 1.3 + t) + sin(p.y * 1.7 + t * 1.3) + 0.5 * sin((p.x + p.y) * 2.3 - t * 0.7);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME * wave_speed;
	float h = wave(world_position.xz, t);
	VERTEX.y += h * wave_height;

	// Normal from the slope of the wave function.
	float e = 0.1;
	float hx = wave(world_position.xz + vec2(e, 0.0), t);
	float hz = wave(world_position.xz + vec2(0.0, e), t);
	NORMAL = normalize(vec3((h - hx) * wave_height / e, 1.0, (h - hz) * wave_height / e));
}

void fragment() {
	// How far behind the surface the scene is, along the view ray.
	float depth = texture(depth_texture, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	behind.xyz /= behind.w;
	float water_depth = VERTEX.z - behind.z;

	vec4 color = mix(shallow_color, deep_color, clamp(water_depth / depth_fade_distance, 0.0, 1.0));

	// Thin drifting ripple lines, traced along one contour of two blended noises.
	vec2 uv = world_position.xz * ripple_scale;
	float n = 0.5 * (value_noise(uv + TIME * 0.3) + value_noise(uv * 1.7 - TIME * 0.25));
	float ripple = 1.0 - smoothstep(0.0, 0.035, abs(n - 0.5));
	color.rgb = mix(color.rgb, ripple_color.rgb, ripple * ripple_strength);

	// Foam where the water meets something solid, with a ragged noisy edge.
	float foam_edge = foam_distance * (0.6 + 0.8 * value_noise(uv * 2.0 + TIME * 0.5));
	float foam = 1.0 - smoothstep(foam_edge * 0.5, foam_edge, water_depth);
	color = mix(color, foam_color, foam);

	ALBEDO = color.rgb;
	ALPHA = color.a;
	ROUGHNESS = 0.15;
	SPECULAR = 0.4;
}
