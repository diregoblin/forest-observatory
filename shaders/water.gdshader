shader_type spatial;
uniform float rainfall = 0.0;
uniform float weather_time = 0.0;
render_mode cull_disabled;
varying vec3 world_pos;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform sampler2D previous_depth_map : filter_linear, repeat_disable;
uniform sampler2D bed_map : filter_linear, repeat_disable;
uniform sampler2D ground_map : filter_linear, repeat_disable;
uniform float display_alpha = 1.0;
uniform float world_extent = 512.0;
float display_depth(vec2 uv) {
	return mix(textureLod(previous_depth_map, uv, 0.0).r,
		textureLod(depth_map, uv, 0.0).r, display_alpha);
}
// Positive bilinear weights preserve a flat lake and cannot overshoot wet stages.
// Dry cell beds never pull the free surface up a bank. This is reconstruction,
// not additional physical resolution or additional water in the solver ledger.
vec2 stage_at(vec2 p) {
	vec2 size = vec2(textureSize(depth_map, 0));
	vec2 q = p / world_extent * size - 0.5;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float stage = 0.0;
	float support = 0.0;
	for (int j = 0; j < 2; j++) {
		for (int i = 0; i < 2; i++) {
			vec2 uv = (cell + vec2(float(i), float(j)) + 0.5) / size;
			float d = display_depth(uv);
			float w = (i == 0 ? 1.0-f.x : f.x) * (j == 0 ? 1.0-f.y : f.y);
			w *= step(0.001, d);
			stage += w * (textureLod(bed_map, uv, 0.0).r + d);
			support += w;
		}
	}
	return vec2(stage / max(support, 0.000001), support);
}
float ground_at(vec2 p) {
	vec2 size = vec2(textureSize(ground_map, 0));
	return textureLod(ground_map, p / world_extent + 0.5/size, 0.0).r;
}
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 stage = stage_at(world_pos.xz);
	VERTEX.y = (stage.y > 0.00001 ? stage.x : ground_at(world_pos.xz)) + .045;
	world_pos.y = VERTEX.y;
}
void fragment() {
	vec2 stage = stage_at(world_pos.xz);
	float depth = stage.x - ground_at(world_pos.xz);
	if (stage.y < 0.001 || depth < 0.035) discard;
	vec2 p = world_pos.xz;
	float ripple = sin(p.x*1.1 + p.y*.45 + weather_time*1.4) * sin(p.y*1.6 - weather_time*1.1);
	ripple += sin(length(fract(p*1.7)-.5)*32.0-weather_time*18.0) * rainfall * .35;
	float glint = pow(max(0.0, ripple), 12.0);
	// Soft mineral/vegetal palette shared with the banks; water is not metal.
	vec3 shallow = vec3(.135,.245,.195);
	vec3 deep = vec3(.055,.15,.16);
	ALBEDO = mix(shallow,deep,smoothstep(.04,1.5,depth)) + glint*.035;
	ROUGHNESS = .34 + .06*ripple;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(.5+.045*sin(p.y*2.3-weather_time*1.5), .5+.045*cos(p.x*1.7+weather_time), 1.0);
	NORMAL_MAP_DEPTH = .7;
}
