class_name ForestWaterView
extends MeshInstance3D

## Read-only adapter: fields -> textures. No water or intervention rules here.
var depth_texture: ImageTexture
var previous_texture: ImageTexture
var current_image: Image
var previous_image: Image
var bed_image: Image
var display_extent := 1.0
var model: ForestWatershed
var blend_elapsed := 0.0
var sample_interval := 0.1
var surface_subdivisions := 4  # Display only; the SI solver grid is unchanged.
var chunk_grid := 1
var chunks: Array[MeshInstance3D] = []
var current_support := PackedByteArray()
var previous_support := PackedByteArray()


func configure(water: ForestWatershed) -> void:
	model = water
	display_extent = water.landscape.settings.extent
	sample_interval = model.config.water_display_interval_s
	var plane := PlaneMesh.new()
	chunk_grid = mini(8, model.resolution)
	while model.resolution % chunk_grid != 0:
		chunk_grid -= 1
	var span := model.landscape.settings.extent / chunk_grid
	plane.size = Vector2.ONE * span
	plane.subdivide_width = model.resolution / chunk_grid * surface_subdivisions - 1
	plane.subdivide_depth = plane.subdivide_width
	# Only wet chunks submit geometry; all retain the exact original 1 m lattice.
	mesh = null
	position = Vector3.ZERO
	position.x = model.landscape.settings.extent / 2
	position.z = position.x
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("world_extent", model.landscape.settings.extent)
	bed_image = _image(model.bed)
	material.set_shader_parameter("bed_map", ImageTexture.create_from_image(bed_image))
	# Terrain3D samples ground at grid corners; hydro samples cell centres.
	# Reconstruct stage from wet cells, then intersect it with the finer terrain.
	# Interpolating dry bank elevations into stage makes the old 4 m terraces.
	var ground_resolution := model.landscape.settings.terrain_resolution
	var ground := PackedFloat64Array()
	ground.resize(ground_resolution * ground_resolution)
	var ground_step := model.landscape.settings.extent / ground_resolution
	for z in ground_resolution:
		for x in ground_resolution:
			ground[z * ground_resolution + x] = model.landscape.height_at(
				x * ground_step, z * ground_step
			)
	material.set_shader_parameter(
		"ground_map",
		ImageTexture.create_from_image(ForestFieldTexture.image(ground, ground_resolution))
	)
	current_image = _image(model.depth)
	previous_image = current_image
	depth_texture = ImageTexture.create_from_image(current_image)
	previous_texture = _texture(model.depth)
	material.set_shader_parameter("depth_map", depth_texture)
	material.set_shader_parameter("previous_depth_map", previous_texture)
	material.set_shader_parameter("display_alpha", 1.0)
	material_override = material
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for z in chunk_grid:
		for x in chunk_grid:
			var chunk := MeshInstance3D.new()
			chunk.mesh = plane
			chunk.material_override = material
			chunk.position = Vector3((x + .5) * span - position.x, 0, (z + .5) * span - position.z)
			chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			chunk.custom_aabb = AABB(Vector3(-span / 2, -10, -span / 2), Vector3(span, 180, span))
			add_child(chunk)
			chunks.append(chunk)
	current_support = _support(model.depth)
	previous_support = current_support
	_refresh_chunks()


static func _support(depth: Variant) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(depth.size())
	for i in depth.size():
		# Conservative around the shader's float32 .001 threshold.
		result[i] = int(depth[i] >= .000999)
	return result


static func wet_chunks(
	current: PackedByteArray, previous: PackedByteArray, resolution: int, grid: int
) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(grid * grid)
	var cells := resolution / grid
	for z in resolution:
		for x in resolution:
			var i := z * resolution + x
			if current[i] == 0 and previous[i] == 0:
				continue
			# The shader's positive bilinear support extends past the wet cell.
			# Keep a full cell halo, both temporal endpoints, and both sides of seams.
			for cz in range(maxi(0, (z - 1) / cells), mini(grid - 1, (z + 1) / cells) + 1):
				for cx in range(maxi(0, (x - 1) / cells), mini(grid - 1, (x + 1) / cells) + 1):
					result[cz * grid + cx] = 1
	return result


func _refresh_chunks() -> void:
	var mask := wet_chunks(current_support, previous_support, model.resolution, chunk_grid)
	for i in chunks.size():
		if chunks[i].visible != bool(mask[i]):
			chunks[i].visible = bool(mask[i])


func refresh(immediate := false) -> void:
	# Retain the CPU upload image; never download a texture to interpolate it.
	var alpha: float = material_override.get_shader_parameter("display_alpha")
	var pixels := previous_image.get_data().to_float32_array()
	var target := current_image.get_data().to_float32_array()
	for i in pixels.size():
		pixels[i] = lerpf(pixels[i], target[i], alpha)
	previous_image = Image.create_from_data(
		model.resolution, model.resolution, false, Image.FORMAT_RF, pixels.to_byte_array()
	)
	previous_texture.update(previous_image)
	current_image = _image(model.depth)
	if immediate:
		previous_image = current_image
		previous_texture.update(previous_image)
		pixels = current_image.get_data().to_float32_array()
	depth_texture.update(current_image)
	previous_support = _support(pixels)
	current_support = _support(model.depth)
	_refresh_chunks()
	# Sampling follows completed ticks, not the configured 0.1 s upload minimum.
	sample_interval = maxf(model.config.water_display_interval_s, blend_elapsed)
	blend_elapsed = 0.0
	material_override.set_shader_parameter("display_alpha", 1.0 if immediate else 0.0)


func advance_display(dt: float) -> void:
	blend_elapsed += dt
	material_override.set_shader_parameter(
		"display_alpha", 1.0 - exp(-2.0 * blend_elapsed / sample_interval)
	)


func display_stage_at(point: Vector3) -> Vector2:
	# Same wet-cell reconstruction as water.gdshader, from submitted CPU images.
	# Safe while the coupled worker writes its models; no live depth/model reads.
	var n := current_image.get_width()
	var q := Vector2(point.x, point.z) / display_extent * n - Vector2(.5, .5)
	var cell := q.floor()
	var f := q - cell
	var alpha: float = material_override.get_shader_parameter("display_alpha")
	var stage := 0.0
	var support := 0.0
	for z in 2:
		for x in 2:
			var i := clampi(int(cell.x) + x, 0, n - 1)
			var j := clampi(int(cell.y) + z, 0, n - 1)
			var depth := lerpf(
				previous_image.get_pixel(i, j).r, current_image.get_pixel(i, j).r, alpha
			)
			if depth < .001:
				continue
			var weight := (1 - f.x if x == 0 else f.x) * (1 - f.y if z == 0 else f.y)
			stage += weight * (bed_image.get_pixel(i, j).r + depth)
			support += weight
	return Vector2(stage / maxf(support, .000001), support)


func _image(values: PackedFloat64Array) -> Image:
	return ForestFieldTexture.image(values, model.resolution)


func _texture(values: PackedFloat64Array) -> ImageTexture:
	return ImageTexture.create_from_image(_image(values))
