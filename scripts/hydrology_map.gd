class_name ForestHydrologyMap
extends TextureRect

## Read-only diagnostic map. North at top, same cells as the solver.
var image_texture: ImageTexture


func refresh(water: ForestWatershed) -> void:
	if not visible:
		return
	var n := water.resolution
	var image := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var capacity := (
		water.config.soil_profile.aquifer_depth_m * water.config.soil_profile.specific_yield
	)
	for k in water.depth.size():
		var saturation := clampf(water.ground_water_m[k] / capacity, 0, 1)
		var color := Color(.26, .19, .12).lerp(Color(.08, .56, .72), saturation)
		if water.depth[k] > .01:
			color = Color(.10, .30, .64)
		if water.seepage_m_s[k] > 1e-10:
			color = Color(1.0, .66, .15)
		image.set_pixel(k % n, k / n, color)
	if image_texture == null:
		image_texture = ImageTexture.create_from_image(image)
		texture = image_texture
	else:
		image_texture.update(image)
