// Shared by baseline, painterly, pixel and impostor baking. UV.x remains the
// component tag; UV.y marks shell depth; UV2 is fixed leaf-mask coordinates.
#include "res://shaders/forest_leaf_light.gdshaderinc"
uniform bool canopy_enabled = false;
uniform float bark_markings = 0.0;
uniform sampler2D canopy_texture : filter_linear_mipmap, repeat_enable;
uniform vec4 canopy_color : source_color = vec4(.40,.49,.43,1);
varying vec2 canopy_uv;
varying float canopy_level;
varying float canopy_stamp;

vec3 canopy_surface(vec3 tint, vec4 leaf) {
	if (canopy_enabled && canopy_level > .5) {
		// Fade unresolved holes rather than losing the entire crown when a
		// mip's average alpha falls below .5. No screen-random dither or blend.
		float footprint = length(fwidth(canopy_uv));
		// A single blade must not turn into an opaque card in the shadow map.
		float threshold = canopy_level > 2.5 ? .5 : mix(.5,.15,smoothstep(.018,.10,footprint));
		if (leaf.a < threshold) { discard; }
		if (canopy_level > 2.5) {
			return tint * (.86 + .22 * leaf.r);
		}
		return canopy_color.rgb * (.94 + .13 * leaf.r) * (1.0 - .20 * (canopy_level - 1.0));
	}
	return tint;
}
vec3 canopy_light(float ndl) {
	float feather = max(fwidth(ndl), .055);
	float value = .20 + smoothstep(-.1-feather,.85+feather,ndl);
	float warm = smoothstep(.05-feather,.55+feather,ndl) * pow(canopy_stamp,4.0) * .7;
	return mix(vec3(.70,.83,1),vec3(1.35,1.18,.78),warm) * value * (1.0+.26*canopy_stamp*warm);
}

vec3 canopy_bark(vec3 tint, vec3 p) {
	float stripe = smoothstep(.80,.97,sin(p.y*22.0+sin(p.z*8.0)))
		* smoothstep(.25,.65,sin(p.x*35.0+p.z*29.0));
	return mix(tint,tint*vec3(.13,.15,.14),stripe*bark_markings);
}
