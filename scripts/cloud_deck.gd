extends MeshInstance3D

## One small noise render shared by the sky and a native shadow-only deck.
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
var noise_texture: NoiseTexture3D = preload("res://art/clouds/noise.tres")


func configure(world_extent: float) -> void:
	extent = world_extent
	height = extent * .5
	position = Vector3(extent * .5, height, extent * .5)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * extent * 8
	# Large unsplit triangles deform when a directional shadow pancake clips
	# their distant vertices. Small cells preserve the local casting plane.
	plane.subdivide_width = 63
	plane.subdivide_depth = 63
	mesh = plane
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	field.name = "CloudField"
	field.size = Vector2i(512, 512)
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
	field_material.set_shader_parameter("cloud_noise", noise_texture)
	noise_texture.changed.connect(_refresh_field)
	field_material.set_shader_parameter("cloud_height", height)
	field_material.set_shader_parameter("field_span", extent * 8)
	rect.material = field_material
	field.add_child(rect)
	shadow_material.shader = preload("res://shaders/cloud_shadow.gdshader")
	shadow_material.set_shader_parameter("cloud_field_map", field.get_texture())
	material_override = shadow_material


func submit(climate: Dictionary, sun_direction: Vector3) -> void:
	if not enabled:
		visible = false
		field.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	var time: float = climate.get("weather_time_s", 0.0)
	if time != last_time:
		last_time = time
		field_material.set_shader_parameter("weather_time", time)
		field.render_target_update_mode = SubViewport.UPDATE_ONCE
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
	material.set_shader_parameter("cloud_span", extent * 8)
	material.set_shader_parameter("world_clouds", true)


func set_enabled(value: bool) -> void:
	enabled = value
	if enabled:
		last_time = -INF
	else:
		visible = false
		field.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _refresh_field() -> void:
	# NoiseTexture3D is generated asynchronously, including on a paused launch.
	if enabled:
		field.render_target_update_mode = SubViewport.UPDATE_ONCE
