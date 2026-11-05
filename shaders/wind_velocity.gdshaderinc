// One submitted, canopy-attenuated velocity in m/s for presentation consumers.
uniform bool spatial_wind_enabled = false;
uniform sampler2D wind_previous : filter_linear, repeat_disable;
uniform sampler2D wind_current : filter_linear, repeat_disable;
uniform sampler2D wind_shelter : filter_linear, repeat_disable;
uniform float wind_extent = 512.0;
uniform float wind_blend = 1.0;
vec2 forest_spatial_wind_velocity(vec3 origin, float height_m) {
	if (!spatial_wind_enabled) return vec2(0);
	vec2 uv = clamp(origin.xz/wind_extent,vec2(0),vec2(1));
	vec2 velocity = mix(textureLod(wind_previous,uv,0.0).rg,textureLod(wind_current,uv,0.0).rg,wind_blend);
	vec2 cover = textureLod(wind_shelter,uv,0.0).rg;
	return velocity * mix(cover.r,1.0,smoothstep(0.0,max(1.0,cover.g),max(0.0,height_m)));
}
