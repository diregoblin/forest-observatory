// Shared art direction: restrained, object-anchored microvariation. Derivative
// fading makes fine detail disappear rather than sparkle in distant LoDs.
vec3 forest_surface(vec3 tint, vec3 p, bool plant, float leaf, float up) {
	float fade = 1.0 - smoothstep(.025, .14, length(fwidth(p)));
	float grain = sin(p.x*37.0 + sin(p.z*19.0)) * sin(p.y*31.0 + p.z*23.0);
	if (!plant) {
		float facets = sin(p.x*7.0 + p.y*4.0) * sin(p.z*8.0 - p.y*5.0);
		float lichen = smoothstep(.48,.8,facets) * smoothstep(.1,.8,up);
		return mix(tint * (1.0 + .10*facets + .055*grain*fade), tint*vec3(.87,1.06,.71), lichen*.35);
	}
	float grooves = pow(.5 + .5*sin(p.x*47.0 + p.z*39.0 + sin(p.y*4.0)), 5.0);
	float woody = 1.0 - .18*grooves*fade + .035*grain*fade;
	float leafy = 1.0 + .075*grain*fade;
	return tint * mix(woody,leafy,leaf);
}
