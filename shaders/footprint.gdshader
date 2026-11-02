shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

// Soft shallow impressions, not opaque raised pebbles. Instance alpha is age.
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float edge = 1.0 - smoothstep(.48, .96, length(p));
	float grain = .72 + .28 * sin(UV.x * 71.0 + sin(UV.y * 39.0) * 3.0);
	float distance_fade = 1.0 - smoothstep(32.0, 40.0, length(VERTEX));
	ALBEDO = vec3(.19, .155, .11);
	ROUGHNESS = 1.0;
	ALPHA = edge * grain * COLOR.a * .22 * distance_fade;
}
