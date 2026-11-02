shader_type canvas_item;
render_mode unshaded;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform float field_span = 2048.0;
uniform float cloud_height = 154.0;
uniform float weather_time = 0.0;
#include "res://shaders/cloud_field.gdshaderinc"
void fragment() {
	vec2 sheet = (UV-.5) * field_span * (2.4/cloud_height);
	float field = cloud_field(vec3(sheet.x,2.71,sheet.y) + weather_time*vec3(.008,0,.003));
	COLOR = vec4(vec3(field),1);
}
