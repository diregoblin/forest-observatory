class_name ForestTerrainView
extends Terrain3D


func configure(land: ForestLandscape, camera: Camera3D) -> void:
	var settings := land.settings
	var terrain := self
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.vertex_spacing = settings.extent / settings.terrain_resolution
	terrain.mesh_size = 32
	terrain.mesh_lods = 6
	terrain.collision_mode = 0
	terrain.set_camera(camera)
	var h := Image.create(
		settings.terrain_resolution, settings.terrain_resolution, false, Image.FORMAT_RF
	)
	var color := Image.create(
		settings.terrain_resolution, settings.terrain_resolution, false, Image.FORMAT_RGBA8
	)
	for z in settings.terrain_resolution:
		for x in settings.terrain_resolution:
			h.set_pixel(
				x,
				z,
				Color(land.height_at(x * terrain.vertex_spacing, z * terrain.vertex_spacing), 0, 0)
			)
			color.set_pixel(
				x, z, land.ground_color(x * terrain.vertex_spacing, z * terrain.vertex_spacing)
			)
	var texture := Terrain3DTextureAsset.new()
	texture.name = "Лесная почва"
	var tex := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for y in 128:
		for x in 128:
			var value := rng.randf_range(.7, 1.0)
			tex.set_pixel(x, y, Color(value, value, value, .5))
	tex.generate_mipmaps()
	texture.albedo_texture = ImageTexture.create_from_image(tex)
	texture.uv_scale = .25
	terrain.assets.set_texture(0, texture)
	terrain.data.import_images([h, null, color], Vector3.ZERO, 0.0, 1.0)
	terrain.material.world_background = 0
