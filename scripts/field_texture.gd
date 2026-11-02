class_name ForestFieldTexture
extends RefCounted


## Explicit precision boundary between model float64 and GPU float32 fields.
static func image(values: PackedFloat64Array, resolution: int) -> Image:
	assert(values.size() == resolution * resolution)
	# Bulk native conversion, not a GDScript loop over the simulation grid.
	var pixels := ForestHydroNative.float32_field(values)
	return Image.create_from_data(
		resolution, resolution, false, Image.FORMAT_RF, pixels.to_byte_array()
	)


static func rgba_image(values: PackedFloat64Array, resolution: int) -> Image:
	assert(values.size() == resolution * resolution * 4)
	var pixels := ForestHydroNative.float32_field(values)
	return Image.create_from_data(
		resolution, resolution, false, Image.FORMAT_RGBAF, pixels.to_byte_array()
	)
