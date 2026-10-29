shader_type spatial;
render_mode cull_disabled;
varying vec3 world_pos;
uniform sampler2D depth_map : filter_linear;
uniform sampler2D bed_map : filter_linear;
uniform float world_extent = 512.0;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 uv = world_pos.xz / world_extent;
	VERTEX.y = textureLod(bed_map, uv, 0.0).r + textureLod(depth_map, uv, 0.0).r + .045;
	world_pos.y = VERTEX.y;
}
void fragment() {
	float depth = texture(depth_map, world_pos.xz / world_extent).r;
	if (depth < 0.035) discard;
	vec2 p = world_pos.xz;
	float ripple = sin(p.x*1.1 + p.y*.45 + TIME*1.4) * sin(p.y*1.6 - TIME*1.1);
	float glint = pow(max(0.0, ripple), 12.0);
	vec3 shallow = vec3(.12,.26,.23);
	vec3 deep = vec3(.045,.145,.17);
	ALBEDO = mix(shallow,deep,smoothstep(.04,1.5,depth)) + glint*.09;
	ROUGHNESS = .21 + .05*ripple;
	METALLIC = .25;
	NORMAL_MAP = vec3(.5+.045*sin(p.y*2.3-TIME*1.5), .5+.045*cos(p.x*1.7+TIME), 1.0);
	NORMAL_MAP_DEPTH = .7;
}
