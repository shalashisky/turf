shader_type spatial;
// Street lamp bulb. Each lamp sets its own glow through an instance uniform,
// so every lamp shares this one material instead of needing its own copy.

uniform vec4 albedo : source_color = vec4(0.45, 0.42, 0.35, 1.0);
uniform vec4 emission_color : source_color = vec4(1.0, 0.52, 0.12, 1.0);
instance uniform float glow = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = emission_color.rgb * glow;
}
