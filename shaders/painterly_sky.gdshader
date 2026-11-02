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

// Engine-generated seamless gradient field: no per-fragment float hash and
// no discontinuity at the repeat boundary. The volume is just a noise lookup;
// clouds themselves remain a perspective-projected horizontal sheet.
float noise(vec3 p) {
	return texture(cloud_noise, p * .125).r;
}
float cloud(vec3 p) {
	vec3 warp = vec3(noise(p * .62), noise(p * .62 + 19.7), noise(p * .62 + 37.3));
	p += (warp - .5) * .85;
	return .72 * noise(p) + .21 * noise(p.yzx * 2.13 + 8.1)
		+ .07 * noise(p * 4.3 + 23.4);
}
void sky() {
	float elevation = max(EYEDIR.y, 0.0);
	vec3 blue = mix(horizon.rgb, zenith.rgb * vec3(.76, 1.04, 1.25),
		pow(elevation, .48));
	float sun_dot = max(dot(EYEDIR, sun_direction), 0.0);
	blue += sun_tint.rgb * pow(sun_dot, 16.0) * .12 * daylight;
	// Reflections need broad sky lighting, not two expensive procedural cloud
	// evaluations per texel on every cubemap face. Visible clouds stay unchanged.
	COLOR = blue;
	if (!AT_CUBEMAP_PASS) {
		// A higher horizontal deck, behind the low sheet: smaller angular detail,
		// stretched wisps, thinner opacity and a different advection rate.
		vec2 high_sheet = EYEDIR.xz / max(EYEDIR.y + .22, .10) * 6.5;
		vec3 high_p = vec3(high_sheet.x * .42, 17.3, high_sheet.y * 1.6)
			+ weather_time * vec3(.003, 0, -.002);
		float high_field = .72 * noise(high_p) + .28 * noise(high_p * 2.07 + 11.8);
		float high_threshold = mix(.67, .52, cloud_cover);
		float high_edge = smoothstep(high_threshold - .03, high_threshold + .09, high_field);
		vec3 high_color = mix(vec3(.14, .17, .25), vec3(.93, .96, 1.0) * sun_tint.rgb, daylight);
		COLOR = mix(blue, high_color, high_edge * upper_cloud_opacity
			* smoothstep(.03, .25, EYEDIR.y));
		// Keep the approved flat layer's foreshortening towards the horizon.
		vec2 sheet = EYEDIR.xz / max(EYEDIR.y + .22, .10) * 2.4;
		vec3 p = vec3(sheet.x, 2.71, sheet.y) + weather_time * vec3(.008, 0, .003);
		float field = cloud(p);
		float threshold = mix(.69, .37, cloud_cover);
		float edge = smoothstep(threshold - .02, threshold + .05, field);
		float shade_field = cloud(p + sun_direction * .22);
		// Broad painted masses, but no hard interior cutouts or bright sticker rim.
		float tones = smoothstep(threshold + .015, threshold + .19, shade_field);
		vec3 shadow = mix(vec3(.10, .13, .22), vec3(.42, .51, .66), daylight);
		vec3 lit = mix(vec3(.21, .24, .34), vec3(1, .98, .88) * sun_tint.rgb, daylight);
		vec3 clouds = mix(lit, shadow, tones * .70);
		clouds *= mix(1.0, .70, smoothstep(.50, .95, cloud_cover));
		float horizon_fade = smoothstep(.015, .18, EYEDIR.y);
		COLOR = mix(COLOR, clouds, edge * horizon_fade * lower_cloud_opacity);
		COLOR += sun_tint.rgb * smoothstep(.9991, .9995, sun_dot) * daylight * .7;
		COLOR = mix(horizon.rgb * .64, COLOR, smoothstep(-.10, .03, EYEDIR.y));
	}
}
