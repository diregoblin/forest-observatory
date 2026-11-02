shader_type canvas_item;
render_mode unshaded;

// Grading affects the entire rendered world, including water, soil and fauna.
// Nearest integer enlargement is handled by the TextureRect, outside the UI.
void fragment() {
	vec3 color = texture(TEXTURE, UV).rgb;
	float value = dot(color, vec3(.2126, .7152, .0722));
	color = mix(vec3(value), color, 1.18);
	// Cool forest shade, warmer open light; keep the night floor readable.
	float light = smoothstep(.18, .8, value);
	color *= mix(vec3(.94, 1.015, 1.045), vec3(1.035, 1.025, .96), light);
	color = pow(max(color, vec3(0.0)), vec3(1.07));
	// Quantise luminance rather than each RGB channel (preserves seasonal hues).
	float band = floor(value * 31.0 + .5) / 31.0;
	color *= mix(1.0, band / max(value, .001), .60);
	COLOR = vec4(clamp(color, vec3(0.0), vec3(1.0)), 1.0);
}
