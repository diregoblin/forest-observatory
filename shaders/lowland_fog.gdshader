shader_type fog;
uniform sampler2D ground_map : filter_linear, repeat_disable;
uniform sampler2D air_map : filter_linear, repeat_disable;
uniform float world_extent = 512.0;
uniform float lowland_level = 30.0;
uniform float night_factor = 0.0;
uniform vec2 drift_m = vec2(0);
void fog() {
	vec2 uv = WORLD_POSITION.xz/world_extent;
	float ground = texture(ground_map,uv+.5/vec2(textureSize(ground_map,0))).r;
	// RGB: prescribed local RH, temperature C, wind speed m/s.
	vec3 air = texture(air_map,uv).rgb;
	float humid = smoothstep(.72,.95,air.r);
	float cool = 1.0-smoothstep(8.0,22.0,air.g);
	float calm = 1.0-smoothstep(2.0,9.0,air.b);
	float lowland = 1.0-smoothstep(lowland_level-5.0,lowland_level+10.0,ground);
	float height = WORLD_POSITION.y-ground;
	vec2 p = (WORLD_POSITION.xz-drift_m)*.06;
	float patch = .7+.3*sin(p.x+sin(p.y*.7))*sin(p.y*.8);
	float layer = exp(-max(0.0,height)*.6)*smoothstep(-.8,.1,height);
	DENSITY = .16*humid*cool*calm*night_factor*lowland*layer*patch;
	ALBEDO = vec3(.73,.80,.82);
}
