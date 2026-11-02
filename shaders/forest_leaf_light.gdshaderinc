// Shared by true leaf cards and their normal-atlas LoD.
vec3 canopy_card_light(float ndl) {
	float through_leaf = max(ndl, -ndl * .35);
	return mix(vec3(.73,.85,1),vec3(1.03,1.02,.90),max(0.0,ndl))
		* (.25 + .65 * through_leaf);
}
