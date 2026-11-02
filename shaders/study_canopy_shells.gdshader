shader_type spatial;
render_mode cull_disabled;

// An isolated shell-texturing experiment. Hard cutouts write depth; there is
// deliberately no alpha-blending pass or camera-facing geometry.
uniform sampler2D leaf_mask : filter_linear_mipmap, repeat_enable;
uniform vec4 canopy_base : source_color = vec4(.40,.49,.43,1);
uniform vec4 leaf_base : source_color = vec4(.56,.63,.44,1);
uniform vec2 leaf_repeat = vec2(3.0, 1.5);
uniform bool flat_normals = false;
uniform bool cutouts_enabled = true;
varying vec3 crown_view_normal;
varying float leaf_part;
varying float layer_depth;
varying float stamp;

void vertex() {
	crown_view_normal = MODELVIEW_NORMAL_MATRIX * NORMAL;
	leaf_part = 1.0 - COLOR.a; // Existing geometry tag, NOT opacity.
	layer_depth = UV2.x;
}
void fragment() {
	vec2 coordinates = UV * leaf_repeat + vec2(layer_depth * 2.37, layer_depth * 1.73);
	vec4 leaf = texture(leaf_mask, coordinates);
	if (cutouts_enabled && leaf_part > .5 && leaf.a < .5) { discard; }
	stamp = leaf.r;
	vec3 crown = mix(canopy_base.rgb, leaf_base.rgb, stamp * .5);
	// Modest depth tint, not baked directional lighting. The actual sun and
	// outward per-lobe normals continue to determine the warm light response.
	crown *= 1.0 - .25 * layer_depth;
	ALBEDO = mix(COLOR.rgb, crown, leaf_part);
	ROUGHNESS = 1.0;
	NORMAL = normalize(crown_view_normal);
	if (flat_normals) { NORMAL=normalize((VIEW_MATRIX*vec4(vec3(.25,.9,.35),0.0)).xyz); }
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float feather = max(fwidth(ndl), .055);
	float value = .20 + smoothstep(-.1-feather, .85+feather, ndl);
	float warm = smoothstep(.05-feather, .55+feather, ndl) * pow(stamp,4.0) * .7;
	vec3 paint = mix(vec3(.70,.83,1.0), vec3(1.35,1.18,.78), warm);
	vec3 leaf_light = paint * value * (1.0 + .26 * stamp * warm);
	vec3 bark_light = vec3(.25 + .75 * max(0.0, ndl));
	DIFFUSE_LIGHT += mix(bark_light,leaf_light,leaf_part)*ATTENUATION*LIGHT_COLOR/PI;
}
