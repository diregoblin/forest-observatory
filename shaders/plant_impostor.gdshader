shader_type spatial;
render_mode cull_disabled;
#include "res://shaders/forest_leaf_light.gdshaderinc"
uniform sampler2D stem_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D leaf_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D stem_normals : filter_linear_mipmap, repeat_disable;
uniform sampler2D leaf_normals : filter_linear_mipmap, repeat_disable;
uniform bool normal_atlas_enabled = false;
uniform int presentation_style = 0;
uniform bool canopy_enabled = false;
uniform bool botanical_cards = false;
varying float canopy_leaf_weight;
uniform float snow_load = 0.0;
uniform vec4 autumn_color : source_color;
uniform float center_y = 0.5;
varying vec4 plant_state;
varying float azimuth;
varying mat3 plant_basis;

void vertex() {
	plant_state = INSTANCE_CUSTOM;
	plant_basis = mat3(normalize(MODEL_MATRIX[0].xyz), normalize(MODEL_MATRIX[1].xyz), normalize(MODEL_MATRIX[2].xyz));
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 to_camera = MAIN_CAM_INV_VIEW_MATRIX[3].xyz - origin;
	// Select the baked direction relative to the submitted plant yaw.
	vec3 local_camera = inverse(mat3(MODEL_MATRIX)) * to_camera;
	azimuth = mod(floor(-atan(local_camera.x, local_camera.z) / 1.570796327 + .5), 4.0);
	float scale = length(MODEL_MATRIX[1].xyz);
	vec3 up = normalize(MODEL_MATRIX[1].xyz);
	vec3 right = normalize(cross(up,to_camera));
	vec3 position = origin + up * center_y * scale
		+ right * VERTEX.x * scale + up * VERTEX.y * scale;
	mat4 inverse_model = inverse(MODEL_MATRIX);
	VERTEX = (inverse_model * vec4(position, 1)).xyz;
	NORMAL = normalize((inverse_model * vec4(normalize(to_camera), 0)).xyz);
}

void fragment() {
	vec2 uv = vec2((UV.x + azimuth) * .25, UV.y);
	vec4 stem = texture(stem_atlas, uv);
	vec4 leaf = texture(leaf_atlas, uv);
	// Deterministic phenology, same leaf fraction/stress/autumn as the mesh.
	float patch = fract(sin(dot(floor(UV * vec2(32,64)), vec2(12.9898,78.233))) * 43758.5453);
	leaf.a *= step(patch, plant_state.r) * step(.001, plant_state.r);
	leaf.rgb = mix(leaf.rgb, autumn_color.rgb, plant_state.b * .9);
	leaf.rgb = mix(vec3(.32,.23,.13), leaf.rgb, .35 + .65 * plant_state.g);
	stem.rgb *= mix(.68, 1.0, clamp(plant_state.a, 0.0, 1.0));
	float leaf_weight = leaf.a / max(.0001,leaf.a + stem.a*(1.0-leaf.a));
	canopy_leaf_weight = leaf_weight;
	ALBEDO = mix(stem.rgb, leaf.rgb, leaf_weight) * COLOR.rgb;
	if (normal_atlas_enabled) {
		vec3 encoded = mix(texture(stem_normals, uv).rgb, texture(leaf_normals, uv).rgb, leaf_weight);
		vec3 baked = normalize(encoded * 2.0 - 1.0);
		float a = -azimuth * 1.570796327;
		vec3 local_normal = vec3(cos(a)*baked.x + sin(a)*baked.z, baked.y, -sin(a)*baked.x + cos(a)*baked.z);
		vec3 world_normal = normalize(plant_basis * local_normal);
		NORMAL = normalize(mat3(VIEW_MATRIX) * world_normal);
		ALBEDO = mix(ALBEDO, vec3(.85,.9,.93), snow_load * smoothstep(.1,.7,world_normal.y) * mix(.3,1.0,leaf.a));
	}
	ALPHA = max(stem.a, leaf.a);
	ALPHA_SCISSOR_THRESHOLD = .35;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(.16) * leaf.a;
	if (presentation_style > 0) {
		EMISSION = ALBEDO * (presentation_style == 2 ? vec3(.012,.022,.036) : vec3(.020,.034,.065));
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	if (botanical_cards && canopy_leaf_weight > .01) {
		vec3 response=mix(vec3(max(0.0,ndl)),canopy_card_light(ndl),canopy_leaf_weight);
		DIFFUSE_LIGHT += response*ATTENUATION*LIGHT_COLOR/PI;
	} else if (canopy_enabled && canopy_leaf_weight > .01) {
		float feather=max(fwidth(ndl),.055);
		float warm=smoothstep(.05-feather,.55+feather,ndl)*.20;
		vec3 paint=mix(vec3(.70,.83,1),vec3(1.35,1.18,.78),warm);
		vec3 leaf_light=paint*(.20+smoothstep(-.1-feather,.85+feather,ndl));
		vec3 response=mix(vec3(max(0.0,ndl)),leaf_light,canopy_leaf_weight);
		DIFFUSE_LIGHT += response*ATTENUATION*LIGHT_COLOR/PI;
	} else if (presentation_style == 0) {
		DIFFUSE_LIGHT += max(0.0, ndl) * ATTENUATION * LIGHT_COLOR / PI;
	} else {
		ndl = ndl * .70 + .30;
		float feather = max(fwidth(ndl), .025);
		float bands = presentation_style == 2
			? .20 + .40 * smoothstep(.24-feather,.24+feather,ndl) + .40 * smoothstep(.72-feather,.72+feather,ndl)
			: .26 + .40 * smoothstep(.18-feather,.18+feather,ndl) + .34 * smoothstep(.70-feather,.70+feather,ndl);
		DIFFUSE_LIGHT += bands * ATTENUATION * LIGHT_COLOR / PI;
	}
}
