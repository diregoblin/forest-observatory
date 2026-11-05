shader_type canvas_item;
render_mode unshaded;
uniform sampler2D cloud_density : filter_linear, repeat_enable;
uniform float field_span = 4096.0;
uniform vec2 cloud_offset_m = vec2(0);
void fragment() {
	float field = texture(cloud_density, UV - cloud_offset_m / field_span).r;
	COLOR = vec4(vec3(field), 1);
}
