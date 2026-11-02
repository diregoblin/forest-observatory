shader_type canvas_item;
render_mode unshaded;
#include "res://shaders/soil_diagnostic.gdshaderinc"
uniform float soil_extent = 512.0;

void fragment() {
	COLOR = vec4(soil_diagnostic_colour(UV * soil_extent, soil_extent), 1.0);
}
