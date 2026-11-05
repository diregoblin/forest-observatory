extends MeshInstance3D

## Shared immutable cloud input, model-sampled rain mask and shadow-only deck.
## Native shadowing also reaches standard materials and volumetric fog; no
## post-process darkening of ambient light, and no simulation/model access.
var field := SubViewport.new()
var field_material := ShaderMaterial.new()
var shadow_material := ShaderMaterial.new()
var extent := 512.0
var height := 154.0
var last_time := -INF
var enabled := false
var shadows_enabled := true
var clouds: ForestCloudField
var source_texture: ImageTexture
var rain_mask: ImageTexture
var liquid_rain_mask: ImageTexture
var cloud_offset := Vector2.ZERO
var cover_texture: ImageTexture


func configure(world_extent: float, source: ForestCloudField = null) -> void:
	extent = world_extent
	if source == null:
		var configuration := ForestSettings.new()
		configuration.extent = extent
		source = ForestCloudField.new(configuration)
	# Own derived trajectory caches; only the immutable tile is shared with the model.
	clouds = ForestCloudField.new(source.settings)
	source_texture = ImageTexture.create_from_image(ForestCloudField.tile)
	rain_mask = ImageTexture.create_from_image(
		ForestFieldTexture.image(clouds.weights({}), clouds.settings.water_resolution)
	)
	liquid_rain_mask = ImageTexture.create_from_image(
		ForestFieldTexture.image(clouds.weights({}, {}, true), clouds.settings.water_resolution)
	)
	var cover_image := Image.create(
		clouds.settings.weather_resolution,
		clouds.settings.weather_resolution,
		false,
		Image.FORMAT_RF
	)
	cover_image.fill(Color(.18, 0, 0))
	cover_texture = ImageTexture.create_from_image(cover_image)
	height = extent * .5
	position = Vector3(extent * .5, height, extent * .5)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * clouds.span_m
	# Large unsplit triangles deform when a directional shadow pancake clips
	# their distant vertices. Small cells preserve the local casting plane.
	plane.subdivide_width = 63
	plane.subdivide_depth = 63
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	field.name = "CloudField"
	field.size = Vector2i.ONE * ForestCloudField.tile.get_width() * 2
	field.disable_3d = true
	field.use_hdr_2d = true
	field.gui_disable_input = true
	field.handle_input_locally = false
	field.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(field)
	RenderingServer.viewport_set_measure_render_time(field.get_viewport_rid(), true)
	var rect := ColorRect.new()
	rect.size = Vector2(field.size)
	field_material.shader = preload("res://shaders/cloud_field_map.gdshader")
	field_material.set_shader_parameter("cloud_density", source_texture)
	field_material.set_shader_parameter("field_span", clouds.span_m)
	field_material.set_shader_parameter("weather_extent", extent)
	field_material.set_shader_parameter("weather_cover", cover_texture)
	rect.material = field_material
	field.add_child(rect)
	shadow_material.shader = preload("res://shaders/cloud_shadow.gdshader")
	shadow_material.set_shader_parameter("cloud_field_map", field.get_texture())
	material_override = shadow_material


func submit(climate: Dictionary, sun_direction: Vector3) -> void:
	var time: float = climate.get("weather_time_s", 0.0)
	if time != last_time or cloud_offset != climate.get("cloud_offset_m", clouds.offset(climate)):
		last_time = time
		cloud_offset = climate.get("cloud_offset_m", clouds.offset(climate))
		field_material.set_shader_parameter("cloud_offset_m", cloud_offset)
		if enabled:
			field.render_target_update_mode = SubViewport.UPDATE_ONCE
	var fields := ForestWeatherFront.grid(climate, extent)
	cover_texture.update(ForestFieldTexture.image(fields.cloud_cover, fields.resolution))
	field_material.set_shader_parameter("spatial_weather", climate.has("front_extent_m"))
	field_material.set_shader_parameter("cloud_cover", climate.get("cloud_cover", .18))
	shadow_material.set_shader_parameter("spatial_weather", climate.has("front_extent_m"))
	# Pure sampling of immutable input. This never advances the weather owner.
	rain_mask.update(
		ForestFieldTexture.image(clouds.weights(climate, fields), clouds.settings.water_resolution)
	)
	liquid_rain_mask.update(
		ForestFieldTexture.image(
			clouds.weights(climate, fields, true), clouds.settings.water_resolution
		)
	)
	if not enabled:
		visible = false
		field.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var cover: float = climate.get("cloud_cover", 0.0)
	shadow_material.set_shader_parameter("cloud_cover", cover)
	# Below this elevation the projected shadows are outside our finite field.
	var presence := smoothstep(.18, .30, sun_direction.y)
	shadow_material.set_shader_parameter("shadow_presence", presence)
	visible = enabled and shadows_enabled and cover > .02 and presence > .01


func configure_sky(material: ShaderMaterial) -> void:
	material.set_shader_parameter("cloud_field_map", field.get_texture())
	material.set_shader_parameter("cloud_anchor", Vector3(extent * .5, 0, extent * .5))
	material.set_shader_parameter("cloud_height", height)
	material.set_shader_parameter("cloud_span", clouds.span_m)
	material.set_shader_parameter("cloud_density", source_texture)
	material.set_shader_parameter("world_clouds", true)


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		last_time = -INF
	else:
		visible = false
		field.render_target_update_mode = SubViewport.UPDATE_DISABLED
