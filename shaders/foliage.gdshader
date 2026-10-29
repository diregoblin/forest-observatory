shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(.15,.27,.13,1.0);
uniform float wind_strength = .08;
uniform bool growth_enabled = false;
uniform sampler2D growth_map : filter_linear;
uniform float world_extent = 512.0;
uniform bool tree_enabled = false;
uniform vec4 autumn_color : source_color = vec4(.95,.62,.12,1.0);
varying vec4 tree_state;
varying float leaf_part;
varying vec3 local_position;
void vertex() {
	tree_state = INSTANCE_CUSTOM;
	leaf_part = 1.0 - COLOR.a;
	local_position = VERTEX;
	vec3 p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	if (growth_enabled) {
		float biomass = textureLod(growth_map, p.xz/world_extent, 0.0).r;
		VERTEX *= .15 + biomass;
		COLOR.rgb *= mix(vec3(.66,.53,.31), vec3(1.0,1.0,.85),biomass);
	}
	float sway = sin(TIME*.9+p.x*.05+p.z*.075) + .4*sin(TIME*1.7+p.x*.14);
	VERTEX.x += sway * pow(max(VERTEX.y,0.0),1.2) * wind_strength;
}
void fragment() {
	vec3 tint = COLOR.rgb;
	if (tree_enabled) {
		if (leaf_part > .5) {
			// Display actual phenology/stress. Hash is fixed in mesh coordinates.
			float patch = fract(sin(dot(floor(local_position * 4.0),vec3(12.9898,78.233,37.719))) * 43758.5453);
			if (tree_state.r < .001 || patch > tree_state.r) { discard; }
			tint = mix(tint, autumn_color.rgb, tree_state.b * .9);
			tint = mix(vec3(.32,.23,.13), tint, .35 + .65 * tree_state.g);
		} else {
			tint *= mix(.68,1.0,tree_state.a);
		}
	}
	ALBEDO = base_color.rgb * tint;
	ROUGHNESS = .92;
	BACKLIGHT = base_color.rgb * .28;
}
