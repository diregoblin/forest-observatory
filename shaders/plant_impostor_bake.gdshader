shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;
#include "res://shaders/forest_canopy.gdshaderinc"
uniform bool foliage_pass = true;
uniform bool normal_pass = false;
varying float leaf;
varying float component;
varying vec3 plant_position;
void vertex() {
	plant_position=VERTEX;
	canopy_level = UV.y;
	canopy_uv = UV2;
	leaf = 1.0 - COLOR.a;
	component = UV.x;
}
void fragment() {
	// Tiny flowers/fruit are omitted at distance, never shown out of season.
	if (component > .5 || (leaf > .5) != foliage_pass) { discard; }
	vec4 crown_mask = canopy_enabled ? texture(canopy_texture,canopy_uv) : vec4(1);
	canopy_stamp = crown_mask.r;
	if (canopy_level > 2.5 && !FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 tint = canopy_surface(COLOR.rgb,crown_mask);
	if (leaf < .5) {tint=canopy_bark(tint,plant_position);}
	ALBEDO = normal_pass ? normalize(NORMAL) * .5 + .5 : tint;
	ALPHA = 1.0;
}
