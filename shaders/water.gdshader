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

// Presentation-only randomness: stable world cells, no frame/model RNG.
vec3 water_hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
	q += dot(q, q.yxz + 33.33);
	return fract((q.xxy + q.yzz) * q.zyx);
}
vec3 water_field(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec2 u = f*f*(3.0-2.0*f);
	vec2 du = 6.0*f*(1.0-f);
	float a = water_hash(cell).x;
	float b = water_hash(cell+vec2(1,0)).x;
	float c = water_hash(cell+vec2(0,1)).x;
	float d = water_hash(cell+vec2(1,1)).x;
	return vec3(mix(b-a,d-c,u.y)*du.x, mix(c-a,d-b,u.x)*du.y,
		mix(mix(a,b,u.x),mix(c,d,u.x),u.y));
}

// A birth, growth and fade per hit, independently phased and re-jittered on
// each cycle. Neighbour cells keep expanding rings continuous across borders.
vec3 rain_detail(vec2 p, float footprint) {
	vec2 cell = floor(p / 1.1);
	vec2 slope = vec2(0);
	float rings = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 id = cell + vec2(float(i),float(j));
			float clock = weather_time * .7 + water_hash(id + 17.3).z;
			float age = fract(clock);
			vec3 hit = water_hash(id + floor(clock) * vec2(17.17,91.71));
			vec2 delta = p - (id + .05 + hit.xy * .9) * 1.1;
			float distance_to_hit = length(delta);
			float radius = .03 + age * .48;
			float x = (distance_to_hit-radius) / max(.035, footprint*.75);
			float envelope = smoothstep(0.0,.08,age) * (1.0-smoothstep(.5,1.0,age));
			envelope *= step(hit.z,.65);
			float ring = exp(-x*x) * envelope;
			rings += ring;
			slope += delta / max(distance_to_hit,.001) * (-x * ring);
		}
	}
	return vec3(slope, rings);
}

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
	float footprint = max(length(dFdx(p)), length(dFdy(p)));
	// Advected, rotated noise gradients instead of infinite sine wave fronts.
	// Three unequal scales prevent either parallel bands or a square lattice.
	mat2 rotation = mat2(vec2(.8,.6),vec2(-.6,.8));
	vec3 coarse = water_field(p*.65 + weather_time*vec2(.17,-.12));
	vec3 medium = water_field(rotation*p*1.31 + vec2(29.4,-13.7)
		+ weather_time*vec2(-.11,.15));
	vec3 fine = water_field(rotation*rotation*p*2.73 + vec2(-7.6,41.3)
		+ weather_time*vec2(.13,.08));
	// Fade frequencies as their cells approach the artistic pixel footprint.
	vec3 resolved = vec3(1.0) - smoothstep(vec3(.25),vec3(.85),footprint*vec3(.65,1.31,2.73));
	vec3 weights = vec3(.5,.32,.18) * resolved;
	float ripple = dot(vec3(coarse.z,medium.z,fine.z)*2.0-1.0, weights);
	vec2 slope = coarse.xy*weights.x + transpose(rotation)*medium.xy*weights.y
		+ transpose(rotation*rotation)*fine.xy*weights.z;
	vec3 rain = vec3(0);
	float rain_visibility = rainfall * (1.0-smoothstep(.035,.14,footprint));
	if (rain_visibility > .001) { rain = rain_detail(p, footprint) * rain_visibility; }
	float glint = smoothstep(.45,.85,ripple);
	// Soft mineral/vegetal palette shared with the banks; water is not metal.
	vec3 shallow = vec3(.135,.245,.195);
	vec3 deep = vec3(.055,.15,.16);
	ALBEDO = mix(shallow,deep,smoothstep(.04,1.5,depth)) + glint*.018 + rain.z*.035;
	ROUGHNESS = .34 + .06*ripple;
	METALLIC = 0.0;
	NORMAL_MAP = vec3(vec2(.5) + slope*.045 + rain.xy*.035, 1.0);
	NORMAL_MAP_DEPTH = .7;
}
