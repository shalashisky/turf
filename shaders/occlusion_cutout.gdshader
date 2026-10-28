shader_type spatial;
// Dithers away geometry that sits between the camera and the player, so the
// player stays visible behind buildings. camera_rig.gd sets both globals every
// frame. Works on GridMap tiles because the cut is computed per fragment.

global uniform vec3 player_position;
global uniform vec3 camera_position;

uniform vec4 albedo : source_color = vec4(1.0);
// Radius of the see-through tube around the camera-to-player line, in meters.
uniform float cutout_radius = 1.5;
uniform float cutout_softness = 0.7;
// How much of the occluder is removed at the center. Below 1 leaves a faint ghost.
uniform float max_cut = 0.85;
// Aim the cut at the player's chest, not their feet.
uniform float chest_height = 0.8;
// Geometry within this distance of the player along the camera line is kept,
// so a wall the player is pressed against doesn't vanish.
uniform float player_clearance = 0.5;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = albedo.rgb;

	// Directional shadows render with an orthographic projection. Skip the cut
	// there so the shadows stay whole.
	bool shadow_pass = PROJECTION_MATRIX[3][3] != 0.0;
	// Nothing below the player's feet can block the view of the player.
	bool above_feet = world_position.y > player_position.y + 0.05;
	if (!shadow_pass && above_feet) {
		vec3 target = player_position + vec3(0.0, chest_height, 0.0);
		vec3 ray = target - camera_position;
		float ray_length = length(ray);
		vec3 ray_dir = ray / ray_length;
		float along = dot(world_position - camera_position, ray_dir);
		float off_ray = distance(world_position, camera_position + ray_dir * along);

		float cut = 1.0 - smoothstep(cutout_radius - cutout_softness, cutout_radius, off_ray);
		cut *= 1.0 - smoothstep(ray_length - player_clearance * 2.0, ray_length - player_clearance, along);
		cut *= max_cut;

		float noise = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
		if (cut > noise) {
			discard;
		}
	}
}
