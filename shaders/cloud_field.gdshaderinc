// Engine-generated seamless gradient field: no per-fragment float hash and
// no discontinuity at the repeat boundary. The volume is just a noise lookup;
// clouds themselves remain a perspective-projected horizontal sheet.
float cloud_noise_at(vec3 p) {
	return texture(cloud_noise, p * .125).r;
}
float cloud_field(vec3 p) {
	vec3 warp = vec3(cloud_noise_at(p * .62), cloud_noise_at(p * .62 + 19.7), cloud_noise_at(p * .62 + 37.3));
	p += (warp - .5) * .85;
	return .72 * cloud_noise_at(p) + .21 * cloud_noise_at(p.yzx * 2.13 + 8.1)
		+ .07 * cloud_noise_at(p * 4.3 + 23.4);
}
