shader_type canvas_item;
render_mode unshaded;
uniform sampler2D cloud_density : filter_linear, repeat_enable;
uniform float field_span = 4096.0;
uniform vec2 cloud_offset_m = vec2(0);
uniform sampler2D weather_cover : filter_linear, repeat_disable;
uniform bool spatial_weather = false;
uniform float cloud_cover = .18;
uniform float weather_extent = 512.0;
void fragment() {
	float field = texture(cloud_density, UV - cloud_offset_m / field_span).r;
	vec2 weather_uv = .5 + (UV-.5)*field_span/weather_extent;
	float cover = spatial_weather ? texture(weather_cover,clamp(weather_uv,vec2(0),vec2(1))).r : cloud_cover;
	COLOR = vec4(field, cover, 0, 1);
}
