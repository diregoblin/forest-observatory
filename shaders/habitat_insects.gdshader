shader_type spatial;
render_mode cull_disabled;
uniform float weather_time = 0.0;
uniform float view_distance_m = 18.0;
uniform float fade_distance_m = 3.0;
void vertex() {
	float phase = INSTANCE_CUSTOM.x;
	float radius = INSTANCE_CUSTOM.y;
	VERTEX += vec3(sin(weather_time * 4.0 + phase) * radius,
		sin(weather_time * 7.0 + phase) * radius * .22,
		cos(weather_time * 3.0 + phase) * radius * .8);
}
void fragment() {
	// Dithered opaque fade: no transparent sorting or far-away insect pixels.
	float fade = clamp((view_distance_m - length(VERTEX)) / max(.01, fade_distance_m), 0.0, 1.0);
	float threshold = fract(sin(dot(floor(FRAGCOORD.xy), vec2(12.9898, 78.233))) * 43758.5453);
	if (fade <= threshold) { discard; }
	ALBEDO = vec3(.5,.32,.08); ROUGHNESS = 1.0;
}
