shader_type sky;
render_mode use_debanding, disable_fog;

// A horizontal procedural cloud sheet, not raymarched volumetric weather.
// The day's light/palette are supplied by the existing atmosphere view.
uniform vec4 zenith : source_color = vec4(.12, .38, .72, 1);
uniform vec4 horizon : source_color = vec4(.73, .83, .88, 1);
uniform vec4 sun_tint : source_color = vec4(1, .90, .72, 1);
uniform vec3 sun_direction = vec3(.4, .6, .2);
uniform float daylight = 1.0;
uniform float cloud_cover = .48;
uniform float weather_time = 0.0;
uniform sampler3D cloud_noise : filter_linear, repeat_enable;
uniform float upper_cloud_opacity = .32;
uniform float lower_cloud_opacity = 1.0;
uniform vec3 cloud_anchor = vec3(256,0,256);
uniform float cloud_height = 154.0;
uniform bool world_clouds = false;
uniform sampler2D cloud_field_map : filter_linear, repeat_disable;
uniform float cloud_span = 4096.0;
uniform sampler2D cloud_density : filter_linear, repeat_enable;
uniform vec2 cloud_offset_m = vec2(0);

#include "res://shaders/cloud_field.gdshaderinc"
#include "res://shaders/cloud_opacity.gdshaderinc"
void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 blue = mix(horizon.rgb, zenith.rgb * vec3(.76, 1.04, 1.25),
		pow(elevation, .48));
	float sun_dot = max(dot(EYEDIR, sun_direction), 0.0);
	blue += sun_tint.rgb * pow(sun_dot, 16.0) * .12 * daylight;
	// Reflections need broad sky lighting, not per-texel cloud evaluations
	// on every cubemap face.
	COLOR = blue;
	if (!AT_CUBEMAP_PASS) {
		// Fade both decks out before the low-sheet ray hits its .08 grazing
		// clamp. Otherwise repeated samples stretch into a wall at the horizon.
		float horizon_fade = smoothstep(.08, .22, EYEDIR.y);
		// A higher horizontal deck, behind the low sheet: smaller angular detail,
		// stretched wisps, thinner opacity and a different advection rate.
		vec2 high_sheet = EYEDIR.xz / max(EYEDIR.y + .22, .10) * 6.5;
		vec3 high_p = vec3(high_sheet.x * .42, 17.3, high_sheet.y * 1.6)
			+ weather_time * vec3(.003, 0, -.002);
		float high_field = .72 * cloud_noise_at(high_p) + .28 * cloud_noise_at(high_p * 2.07 + 11.8);
		float high_threshold = mix(.67, .52, cloud_cover);
		float high_edge = smoothstep(high_threshold - .03, high_threshold + .09, high_field);
		vec3 high_color = mix(vec3(.14, .17, .25), vec3(.93, .96, 1.0) * sun_tint.rgb, daylight);
		COLOR = mix(blue, high_color, high_edge * upper_cloud_opacity
			* horizon_fade);
		// Keep the approved flat layer's foreshortening towards the horizon.
		vec2 sheet = EYEDIR.xz / max(EYEDIR.y + .22, .10) * 2.4;
		if (world_clouds) {
			// Use the same world deck as its shadow caster; soften only the horizon.
			sheet = (POSITION.xz-cloud_anchor.xz) * (2.4/cloud_height)
				+ EYEDIR.xz / max(EYEDIR.y,.08) * (2.4*(cloud_height-POSITION.y)/cloud_height);
		}
		vec2 deck_uv = .5 + sheet * (cloud_height/(2.4*cloud_span));
		float field = texture(cloud_density, deck_uv - cloud_offset_m/cloud_span).r;
		if (world_clouds && all(greaterThanEqual(deck_uv, vec2(0)))
			&& all(lessThanEqual(deck_uv, vec2(1)))) {
			field = texture(cloud_field_map, deck_uv).r;
		}
		float threshold = mix(.69, .37, cloud_cover);
		float edge = cloud_opacity(field, cloud_cover);
		// Broad, screen-stable painted core; coverage is shared with the native
		// caster instead of independently regenerated noise.
		float shade_field = field;
		// Broad painted masses, but no hard interior cutouts or bright sticker rim.
		float tones = smoothstep(threshold + .015, threshold + .19, shade_field);
		vec3 shadow = mix(vec3(.10, .13, .22), vec3(.42, .51, .66), daylight);
		vec3 lit = mix(vec3(.21, .24, .34), vec3(1, .98, .88) * sun_tint.rgb, daylight);
		// Thin fringes reveal the sky, not a saturated bright sticker outline.
		vec3 clouds = mix(lit, shadow, .24 + tones * .46);
		clouds *= mix(1.0, .70, smoothstep(.50, .95, cloud_cover));
		COLOR = mix(COLOR, clouds, edge * horizon_fade * lower_cloud_opacity);
		COLOR += sun_tint.rgb * smoothstep(.9991, .9995, sun_dot) * daylight * .7;
		COLOR = mix(horizon.rgb * .64, COLOR, smoothstep(-.10, .03, EYEDIR.y));
	}
}
