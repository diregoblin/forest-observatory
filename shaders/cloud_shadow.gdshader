shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D cloud_field_map : filter_linear, repeat_disable;
uniform float cloud_cover = .48;
uniform float shadow_presence = 1.0;
void fragment() {
    float field = texture(cloud_field_map,UV).r;
    float threshold = mix(.69,.37,cloud_cover);
    ALPHA = smoothstep(threshold-.02,threshold+.05,field) * shadow_presence;
    ALPHA_SCISSOR_THRESHOLD = .5;
}
