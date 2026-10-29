class_name ForestWaterView
extends MeshInstance3D

## Read-only adapter: fields -> textures. No water or intervention rules here.
var depth_texture: ImageTexture
var previous_texture: ImageTexture
var current_image: Image
var model: ForestWatershed
var blend_elapsed := 0.0
var sample_interval := 0.1


func configure(water: ForestWatershed) -> void:
	model = water
	sample_interval = model.config.water_display_interval_s
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * (model.landscape.settings.extent - model.cell_size)
	plane.subdivide_width = model.resolution - 2
	plane.subdivide_depth = model.resolution - 2
	mesh = plane
	position = Vector3.ZERO
	position.x = model.landscape.settings.extent / 2
	position.z = position.x
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/water.gdshader")
	material.set_shader_parameter("world_extent", model.landscape.settings.extent)
	material.set_shader_parameter("bed_map", _texture(model.bed))
	current_image = _image(model.depth)
	depth_texture = ImageTexture.create_from_image(current_image)
	previous_texture = _texture(model.depth)
	material.set_shader_parameter("depth_map", depth_texture)
	material.set_shader_parameter("previous_depth_map", previous_texture)
	material.set_shader_parameter("display_alpha", 1.0)
	material_override = material
	custom_aabb = AABB(
		Vector3(-position.x, -10, -position.z),
		Vector3(model.landscape.settings.extent, 180, model.landscape.settings.extent)
	)


func refresh() -> void:
	# Retain the CPU upload image; never download a texture to interpolate it.
	previous_texture.update(current_image)
	current_image = _image(model.depth)
	depth_texture.update(current_image)
	blend_elapsed = 0.0
	material_override.set_shader_parameter("display_alpha", 0.0)


func advance_display(dt: float) -> void:
	blend_elapsed += dt
	material_override.set_shader_parameter(
		"display_alpha", minf(1.0, blend_elapsed / sample_interval)
	)


func _image(values: PackedFloat64Array) -> Image:
	return ForestFieldTexture.image(values, model.resolution)


func _texture(values: PackedFloat64Array) -> ImageTexture:
	return ImageTexture.create_from_image(_image(values))
