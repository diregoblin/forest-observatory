shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D cloud_field_map : filter_linear, repeat_disable;
uniform bool spatial_weather = false;
uniform float cloud_cover = .48;
uniform float shadow_presence = 1.0;
#include "res://shaders/cloud_opacity.gdshaderinc"
void fragment() {
    vec2 field = texture(cloud_field_map,UV).rg;
    ALPHA = cloud_opacity(field.r, spatial_weather ? field.g : cloud_cover) * shadow_presence;
    // Keep a solid caster; native finite-disc shadow filtering supplies the
    // penumbra. Alpha hashing produced pepper across the low-resolution world.
    ALPHA_SCISSOR_THRESHOLD = .5;
}
