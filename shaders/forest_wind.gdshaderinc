// The CPU submits one advected velocity field in m/s for all visual styles,
// grass and listener audio. Shaders only interpolate it and bend geometry.
uniform bool spatial_wind_enabled = false;
uniform sampler2D wind_previous : filter_linear, repeat_disable;
uniform sampler2D wind_current : filter_linear, repeat_disable;
uniform sampler2D wind_shelter : filter_linear, repeat_disable;
uniform float wind_extent = 512.0;
uniform float wind_blend = 1.0;
uniform float weather_wind = 1.0;
uniform vec2 weather_direction = vec2(1, 0);
uniform float weather_time = 0.0;

vec2 forest_wind_velocity(vec3 origin, float height_m) {
	if (!spatial_wind_enabled) {
		float sway = sin(weather_time*.9 + origin.x*.05 + origin.z*.075)
			+ .4*sin(weather_time*1.7 + origin.x*.14);
		return weather_direction * weather_wind * sway;
	}
	vec2 uv = clamp(origin.xz/wind_extent, vec2(0), vec2(1));
	vec2 velocity = mix(textureLod(wind_previous,uv,0.0).rg,
		textureLod(wind_current,uv,0.0).rg,wind_blend);
	vec2 cover = textureLod(wind_shelter,uv,0.0).rg;
	float attenuation = mix(cover.r,1.0,smoothstep(0.0,max(1.0,cover.g),max(0.0,height_m)));
	return velocity * attenuation / 3.0;
}

vec3 forest_wind_vertex(vec3 point, mat4 pose, float strength, float alive) {
	float scale = max(.001,length(pose[1].xyz));
	vec2 velocity = forest_wind_velocity(pose[3].xyz,max(point.y,0.0)*scale);
	vec3 world_wind = vec3(velocity.x,0,velocity.y);
	vec2 local_wind = vec2(dot(normalize(pose[0].xyz),world_wind),dot(normalize(pose[2].xyz),world_wind));
	vec2 bend = local_wind * pow(max(point.y,0.0),1.2) * strength * alive;
	float maximum = .75 / scale;
	bend *= maximum/(maximum+length(bend));
	return point + vec3(bend.x,0,bend.y);
}
