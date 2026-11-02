shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/forest_surface.gdshaderinc"
#include "res://shaders/forest_canopy.gdshaderinc"

// Same submitted mesh, geometry tags and phenotype as the baseline shader.
// All species share this material path; no biological state is invented here.
uniform vec4 base_color : source_color = vec4(.15, .27, .13, 1);
uniform float wind_strength = .08;
uniform float weather_wind = 1.0;
uniform vec2 weather_direction = vec2(1.0, 0.0);
uniform float weather_time = 0.0;
uniform float snow_load = 0.0;
uniform float bloom_fraction = 0.0;
varying float component_tag;
uniform bool growth_enabled = false;
uniform sampler2D growth_map : filter_linear;
uniform float world_extent = 512.0;
uniform bool tree_enabled = false;
uniform vec4 autumn_color : source_color = vec4(.95, .62, .12, 1);
varying vec4 tree_state;
varying float leaf_part;
varying float world_up_normal;
varying vec3 local_position;

void vertex() {
	canopy_level = UV.y;
	canopy_uv = UV2;
	tree_state = INSTANCE_CUSTOM;
	world_up_normal = (MODEL_NORMAL_MATRIX * NORMAL).y;
	// Primitive UVs are not plant component tags (e.g. a whole stone sphere).
	component_tag = tree_enabled ? UV.x : 0.0;
	leaf_part = 1.0 - COLOR.a;
	local_position = VERTEX;
	vec3 p = (MODEL_MATRIX * vec4(VERTEX, 1)).xyz;
	if (growth_enabled) {
		float biomass = textureLod(growth_map, p.xz / world_extent, 0.0).r;
		VERTEX *= .15 + biomass;
		COLOR.rgb *= mix(vec3(.66, .53, .31), vec3(1, 1, .85), biomass);
	}
	float sway = sin(weather_time * .9 + p.x * .05 + p.z * .075)
		+ .4 * sin(weather_time * 1.7 + p.x * .14);
	vec2 local_wind = vec2(dot(normalize(MODEL_MATRIX[0].xz), weather_direction), dot(normalize(MODEL_MATRIX[2].xz), weather_direction));
	float alive_wind = tree_enabled ? clamp(tree_state.a, 0.0, 1.0) : 1.0;
	vec2 bend = local_wind * sway * pow(max(VERTEX.y,0.0),1.2) * wind_strength * weather_wind * alive_wind;
	VERTEX.xz += bend;
}

void fragment() {
	vec4 crown_mask = canopy_enabled ? texture(canopy_texture,canopy_uv) : vec4(1);
	canopy_stamp = crown_mask.r;
	if (canopy_level > 2.5 && !FRONT_FACING) { NORMAL = -NORMAL; }
	vec3 tint = canopy_surface(COLOR.rgb,crown_mask);
	if (component_tag > 1.5) {
		float fruit_fill = max(0.0, (tree_state.a - 1.0) * .5);
		float hash = fract(sin(dot(floor(local_position * 21.0),vec3(12.9898,78.233,37.719))) * 43758.5453);
		if (fruit_fill < .001 && bloom_fraction < .05) {discard;}
		if (bloom_fraction > .05 && fruit_fill < .001) {tint = vec3(.94,.89,.67);}
		else if (hash > fruit_fill) {discard;}
	} else if (component_tag > .5 && bloom_fraction < .05) {discard;}
	if (tree_enabled) {
		if (leaf_part > .5) {
			float patch = fract(sin(dot(floor(local_position * 4.0),
				vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			if (tree_state.r < .001 || patch > tree_state.r) { discard; }
			if (component_tag < .5) {tint = mix(tint, autumn_color.rgb, tree_state.b * .9);}
			tint = mix(vec3(.32, .23, .13), tint, .35 + .65 * tree_state.g);
		} else {
			tint *= mix(.68, 1.0, clamp(tree_state.a,0.0,1.0));
		}
	}
	// Broad, mesh-anchored leaf clusters. No screen noise or frame-random dithering.
	float cluster = sin(local_position.x * 2.1 + sin(local_position.z * 1.7))
		* sin(local_position.y * 2.3 + local_position.z * .9);
	float fleck = smoothstep(.1, .4, cluster) - .45;
	if (component_tag < .5 && canopy_level < .5) { tint = forest_surface(tint,local_position,tree_enabled,leaf_part,world_up_normal); }
	if (tree_enabled && leaf_part < .5 && component_tag < .5) {tint=canopy_bark(tint,local_position);}
	ALBEDO = base_color.rgb * tint * (1.0 + .20 * fleck * leaf_part);
	float snow = snow_load * smoothstep(.1, .7, world_up_normal) * (leaf_part > .5 ? 1.0 : .3);
	ALBEDO = mix(ALBEDO, vec3(.85,.9,.93), snow);
	ROUGHNESS = 1.0;
	BACKLIGHT = base_color.rgb * .16 * leaf_part;
	EMISSION = ALBEDO * vec3(.012, .022, .036);
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * .70 + .30;
	float feather = max(fwidth(ndl), .02);
	float bands = .20 + .40 * smoothstep(.24 - feather, .24 + feather, ndl)
		+ .40 * smoothstep(.72 - feather, .72 + feather, ndl);
	vec3 response = canopy_enabled && canopy_level > 2.5 ? canopy_card_light(dot(NORMAL,LIGHT)) :
		(canopy_enabled && canopy_level > .5 ? canopy_light(dot(NORMAL,LIGHT)) : vec3(bands));
	DIFFUSE_LIGHT += response * ATTENUATION * LIGHT_COLOR / PI;
}
