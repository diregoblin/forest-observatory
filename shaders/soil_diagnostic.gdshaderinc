// Sparse two-resolution diagnostic display, shared by terrain and HUD.
// Atlas holds only actual fine owners; no interpolated/invented fine reserves.
uniform sampler2D soil_layer_map : source_color, filter_nearest, repeat_disable;
uniform sampler2D soil_fine_map : source_color, filter_nearest, repeat_disable;
uniform sampler2D soil_fine_layout : filter_nearest, repeat_disable;
uniform int soil_fine_count = 0;
uniform float soil_base_cell_m = 4.0;
uniform bool soil_grid_enabled = false;

vec3 soil_grid(vec3 colour, vec2 cell) {
	vec2 pixel = max(fwidth(cell), vec2(0.00001));
	vec2 edge = min(fract(cell), 1.0 - fract(cell));
	vec2 lines = 1.0 - smoothstep(pixel * 0.2, pixel * 0.8, edge);
	// Suppress subpixel grids instead of aliasing when the observer is far away.
	float visible = 1.0 - smoothstep(0.25, 0.8, max(pixel.x, pixel.y));
	return mix(colour, colour * 0.55, max(lines.x, lines.y) * visible);
}

vec3 soil_diagnostic_colour(vec2 point, float extent) {
	vec3 colour = texture(soil_layer_map, point / extent).rgb;
	vec2 cell = point / soil_base_cell_m;
	for (int index = 0; index < soil_fine_count; index++) {
		// origin XZ, square width in metres, first atlas row.
		vec4 rect = texelFetch(soil_fine_layout, ivec2(0, index), 0);
		// resolution, cell size in metres.
		vec2 grid = texelFetch(soil_fine_layout, ivec2(1, index), 0).xy;
		vec2 local = point - rect.xy;
		if (all(greaterThanEqual(local, vec2(0.0))) && all(lessThan(local, vec2(rect.z)))) {
			cell = local / grid.y;
			ivec2 pixel = ivec2(floor(cell)) + ivec2(0, int(rect.w));
			colour = texelFetch(soil_fine_map, pixel, 0).rgb;
			break;
		}
	}
	return soil_grid_enabled ? soil_grid(colour, cell) : colour;
}
