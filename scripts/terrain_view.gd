class_name ForestTerrainView
extends Terrain3D

var traffic_texture: ImageTexture
var rooting_texture: ImageTexture
var ecology_previous: ImageTexture
var ecology_current: ImageTexture
var ecology_display_s := 1.0
var ground_greenness := -1.0


func set_surface_season(climate: Dictionary) -> void:
	var greenness := clampf((float(climate.get("temperature_c", 12)) + 4.0) / 18.0, 0, 1)
	if not is_equal_approx(greenness, ground_greenness):
		ground_greenness = greenness
		material.set_shader_param("ground_greenness", greenness)


func configure(land: ForestLandscape, camera: Camera3D) -> void:
	var settings := land.settings
	var terrain := self
	terrain.name = "Terrain3D"
	terrain.region_size = 256
	terrain.vertex_spacing = settings.extent / settings.terrain_resolution
	terrain.mesh_size = 32
	terrain.mesh_lods = 6
	# The lightweight ecological material has no texture displacement.
	terrain.tessellation_level = 0
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
	texture.set_asset_name("Лесная почва")
	var tex := Image.create(128, 128, true, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 47
	for y in 128:
		for x in 128:
			var value := rng.randf_range(.7, 1.0)
			tex.set_pixel(x, y, Color(value, value, value, .5))
	tex.generate_mipmaps()
	texture.albedo_texture = ImageTexture.create_from_image(tex)
	var normals := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	normals.fill(Color(.5, .5, 1.0, .9))
	normals.generate_mipmaps()
	texture.normal_texture = ImageTexture.create_from_image(normals)
	texture.uv_scale = .25
	terrain.assets.set_texture_asset(0, texture)
	terrain.data.import_images([h, null, color], Vector3.ZERO, 0.0, 1.0)
	terrain.material.world_background = 0
	terrain.material.shader_override = load("res://shaders/soil_ecology.gdshader")
	terrain.material.shader_override_enabled = true
	terrain.material.set_shader_param("ecology_extent", settings.extent)
	# Shared, CPU-baked micro-turf: two mipmapped maps, no grass mesh instances
	# or authoritative ecology changes. The mask remains in the terrain shader.
	terrain.material.set_shader_param(
		"turf_albedo_height", load("res://art/ground-turf/albedo-height.png")
	)
	terrain.material.set_shader_param(
		"turf_normal_roughness_ao", load("res://art/ground-turf/normal-roughness-ao.png")
	)
	terrain.material.set_shader_param("turf_enabled", true)
	# Static site/substrate mask shared with initial plant communities. This is
	# visual substrate, not a new hydrological soil-texture constitutive model.
	var n := settings.water_resolution
	var mask := Image.create(n, n, false, Image.FORMAT_RGBAF)
	for z in n:
		for x in n:
			var site := land.habitat_at(
				(x + .5) * settings.extent / n, (z + .5) * settings.extent / n
			)
			mask.set_pixel(x, z, Color(site.x, site.y, site.z, site.w))
	terrain.material.set_shader_param("habitat_map", ImageTexture.create_from_image(mask))
	# This scene has one terrain texture; never blend with an unassigned layer.
	terrain.material.set_shader_param("auto_overlay_texture", 0)


func refresh_ecology(soil: ForestSoil, water: ForestWatershed, cover: ForestGroundcover) -> void:
	var values: PackedFloat64Array = soil.native.surface_fields(water.soil, cover.biomass)
	var image := ForestFieldTexture.rgba_image(values, water.resolution)
	if ecology_current == null:
		ecology_current = ImageTexture.create_from_image(image)
		ecology_previous = ImageTexture.create_from_image(image)
	else:
		var spare := ecology_previous
		ecology_previous = ecology_current
		ecology_current = spare
		ecology_current.update(image)
	ecology_display_s = 0
	material.set_shader_param("ecology_previous", ecology_previous)
	material.set_shader_param("ecology_current", ecology_current)
	material.set_shader_param("ecology_enabled", true)
	material.set_shader_param("ecology_blend", 0.0)


func advance_ecology_display(dt: float) -> void:
	ecology_display_s = minf(1, ecology_display_s + dt)
	material.set_shader_param("ecology_blend", ecology_display_s)


func set_soil_layer(texture: ImageTexture, enabled: bool) -> void:
	if texture != null:
		material.set_shader_param("soil_layer_map", texture)
	material.set_shader_param("soil_layer_enabled", enabled)


func refresh_traffic(habitat: ForestHabitat) -> void:
	var image := ForestFieldTexture.image(habitat.traffic, habitat.water.resolution)
	if traffic_texture == null:
		traffic_texture = ImageTexture.create_from_image(image)
	else:
		traffic_texture.update(image)
	material.set_shader_param("traffic_map", traffic_texture)
	material.set_shader_param("traffic_enabled", true)
	var rooted := ForestFieldTexture.image(habitat.rooting, habitat.water.resolution)
	if rooting_texture == null:
		rooting_texture = ImageTexture.create_from_image(rooted)
	else:
		rooting_texture.update(rooted)
	material.set_shader_param("rooting_map", rooting_texture)
