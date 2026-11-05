shader_type particles;
render_mode disable_velocity;
uniform sampler2D rain_mask : filter_linear, repeat_disable;
uniform bool spatial_rain = false;
uniform float world_extent = 512.0;
uniform float fall_speed = 21.0;
uniform vec3 fall_direction = vec3(.1,-1,.05);
float hash(float v) { return fract(sin(v * 127.1 + 311.7) * 43758.5453); }
void start() {
	float id = float(NUMBER) + float(RANDOM_SEED % 10000u);
	TRANSFORM = EMISSION_TRANSFORM;
	TRANSFORM[3].xyz += vec3(hash(id)*44.0-22.0, hash(id+7.0)*24.0-12.0,
		hash(id+19.0)*44.0-22.0);
	VELOCITY = normalize(fall_direction) * fall_speed * mix(.85,1.15,hash(id+29.0));
	CUSTOM.x = hash(id+43.0);
	COLOR = vec4(1);
}
void process() {
	TRANSFORM[3].xyz += VELOCITY * DELTA;
	vec2 uv = TRANSFORM[3].xz / world_extent;
	float weight = 1.0;
	if (spatial_rain) {
		weight = texture(rain_mask, clamp(uv,vec2(0),vec2(1))).r;
		weight *= float(all(greaterThanEqual(uv,vec2(0))) && all(lessThanEqual(uv,vec2(1))));
	}
	// Stable per-drop thinning displays the submitted model intensity.
	COLOR.a = step(CUSTOM.x, weight) * step(.0001,weight);
}
