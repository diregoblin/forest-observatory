shader_type spatial;
render_mode cull_disabled;
uniform vec4 base_color : source_color = vec4(.15,.27,.13,1.0);
uniform float wind_strength = .08;
uniform bool growth_enabled = false;
uniform sampler2D growth_map : filter_linear;
uniform float world_extent = 512.0;
void vertex() {
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
	ALBEDO = base_color.rgb * COLOR.rgb;
	ROUGHNESS = .92;
	BACKLIGHT = base_color.rgb * .28;
}
