shader_type spatial;
render_mode cull_disabled;
uniform sampler2D tuft : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ecology_current : filter_linear, repeat_disable;
uniform sampler2D ecology_previous : filter_linear, repeat_disable;
uniform sampler2D habitat_map : filter_linear, repeat_disable;
uniform sampler2D traffic_map : filter_linear, repeat_disable;
uniform sampler2D rooting_map : filter_linear, repeat_disable;
uniform sampler2D depth_map : filter_linear, repeat_disable;
uniform sampler2D previous_depth_map : filter_linear, repeat_disable;
uniform float display_alpha = 1.0;
uniform float ecology_blend = 1.0;
uniform float ecology_extent = 512.0;
uniform float ground_greenness = .85;
uniform float snow_water_m = 0.0;
uniform float weather_time = 0.0;
uniform float weather_wind = 1.0;
uniform vec2 weather_direction = vec2(1,0);
uniform int presentation_style = 0;
uniform float view_distance = 36.0;
uniform float mid_distance = 20.0;
uniform float far_distance = 28.0;
uniform bool plane_lod_enabled = true;
varying float grass_detail;
varying float grass_wetness;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec2 uv = origin.xz / ecology_extent;
	vec4 site = textureLod(habitat_map, uv, 0.0);
	vec4 eco = mix(textureLod(ecology_previous, uv, 0.0), textureLod(ecology_current, uv, 0.0), ecology_blend);
	float cover = 1.0 - exp(-max(0.0,eco.g) * 7.0);
	float turf = max(cover, dot(site.rgb,vec3(.48,.92,.98)) * ground_greenness) * (1.0-site.a);
	turf *= 1.0 - smoothstep(.025,.35,textureLod(traffic_map,uv,0.0).r);
	turf *= 1.0 - smoothstep(.01,.4,textureLod(rooting_map,uv,0.0).r);
	turf *= 1.0 - smoothstep(.0001,.004,snow_water_m);
	float depth = mix(textureLod(previous_depth_map,uv,0.0).r, textureLod(depth_map,uv,0.0).r, display_alpha);
	turf *= 1.0 - smoothstep(.01,.04,depth);
	// Alpha scissor cannot fade a tuft: it kills all blades at a common
	// opacity threshold. Instead, lower each anchored tuft into the surface
	// across a broad band, with a stable, per-tuft end distance.
	float rank = fract(sin(dot(origin.xz,vec2(12.9898,78.233))) * 43758.5453);
	float fade_end = mix(view_distance * .47, view_distance, rank);
	float fade_start = max(view_distance * .40, fade_end - view_distance * .18);
	float distance_to_eye = length(MAIN_CAM_INV_VIEW_MATRIX[3].xyz-origin);
	grass_detail = 1.0 - smoothstep(fade_start, fade_end, distance_to_eye);
	// Lower the departing plane before the patch swaps its shared mesh.
	// The CPU uses nearest tile XZ distance, so no visible plane is dropped.
	if (plane_lod_enabled && UV2.x > .5) {
		float plane_end = UV2.x > 1.5 ? mid_distance : far_distance;
		grass_detail = min(grass_detail, 1.0-smoothstep(plane_end-5.0,plane_end,distance_to_eye));
	}
	grass_wetness = smoothstep(.4,.95,eco.b);
	VERTEX *= step(INSTANCE_CUSTOM.r, turf);
	VERTEX.y = VERTEX.y * grass_detail - .06 * (1.0 - grass_detail);
	NORMAL = normalize(mix(vec3(0,1,0),NORMAL,grass_detail));
	float sway = sin(weather_time*.9 + origin.x*.05 + origin.z*.075);
	vec2 local_wind = vec2(dot(normalize(MODEL_MATRIX[0].xz),weather_direction),dot(normalize(MODEL_MATRIX[2].xz),weather_direction));
	VERTEX.xz += local_wind * sway * pow(max(VERTEX.y,0.0),1.2) * .12 * weather_wind;
}

void fragment() {
	vec4 blade = texture(tuft,UV);
	ALBEDO = blade.rgb * COLOR.rgb * mix(vec3(.82,.76,.55),vec3(1.0),ground_greenness);
	ALBEDO *= mix(1.0,.64,grass_wetness);
	ALPHA = blade.a;
	ALPHA_SCISSOR_THRESHOLD = .4;
	ROUGHNESS = mix(.94,.52,grass_wetness);
	BACKLIGHT = ALBEDO * .18 * grass_detail;
	if (presentation_style > 0) { EMISSION = ALBEDO * vec3(.012,.022,.036) * grass_detail; }
}

void light() {
	float ndl = dot(NORMAL,LIGHT) * .70 + .30;
	float feather = max(fwidth(ndl),.025);
	float bands = presentation_style == 0 ? max(0.0,dot(NORMAL,LIGHT))
		: .20 + .40*smoothstep(.24-feather,.24+feather,ndl) + .40*smoothstep(.72-feather,.72+feather,ndl);
	// The last short blades converge to the ground's diffuse response, not
	// a differently lit circular carpet. Near grass retains its volume.
	bands = mix(max(0.0,dot(NORMAL,LIGHT)),bands,grass_detail);
	DIFFUSE_LIGHT += bands * ATTENUATION * LIGHT_COLOR / PI;
}
