class_name ForestWaterView
extends MeshInstance3D

## Read-only adapter: fields -> textures. No water or intervention rules here.
var depth_texture: ImageTexture
var model: ForestWatershed


func configure(water: ForestWatershed) -> void:
	model = water
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
	depth_texture = _texture(model.depth)
	material.set_shader_parameter("depth_map", depth_texture)
	material_override = material
	custom_aabb = AABB(
		Vector3(-position.x, -10, -position.z),
		Vector3(model.landscape.settings.extent, 180, model.landscape.settings.extent)
	)


func refresh() -> void:
	depth_texture.update(_image(model.depth))


func _image(values: PackedFloat64Array) -> Image:
	return ForestFieldTexture.image(values, model.resolution)


func _texture(values: PackedFloat64Array) -> ImageTexture:
	return ImageTexture.create_from_image(_image(values))
