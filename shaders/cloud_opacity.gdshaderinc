// Shared low-deck coverage: translucent fringes, opaque dense cores.
// Keep the half-coverage contour close to the original cutout silhouette.
float cloud_opacity(float field, float cover) {
	float threshold = mix(.69, .37, cover);
	return smoothstep(threshold - .06, threshold + .10, field);
}
