class_name ForestFieldTexture
extends RefCounted


## Explicit precision boundary between model float64 and GPU float32 fields.
static func image(values: PackedFloat64Array, resolution: int) -> Image:
	assert(values.size() == resolution * resolution)
	var pixels := PackedFloat32Array()
	pixels.resize(values.size())
	for i in values.size():
		pixels[i] = values[i]
	return Image.create_from_data(
		resolution, resolution, false, Image.FORMAT_RF, pixels.to_byte_array()
	)
