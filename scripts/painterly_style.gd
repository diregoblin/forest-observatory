extends Node

## Scene-wide presentation modes. The models and original materials stay intact.
signal mode_changed(title: String)

enum Mode { BASELINE, PAINTERLY, PIXEL }

var atmosphere: ForestAtmosphere
var vegetation: ForestVegetation
var enabled := false
var mode := Mode.BASELINE
var pixel_renderer = preload("res://scripts/pixel_renderer.gd").new()
var original_shaders: Dictionary = {}
var original_sky: Material
var original_ssao := 1.5
var sky_material := ShaderMaterial.new()
var sky_values := {}
var material_revision := -1
var impostor_style_revision := -1
var impostor_style_mode := -1
var foliage_shader: Shader = preload("res://shaders/painterly_foliage.gdshader")
var pixel_shader: Shader = preload("res://shaders/pixel_foliage.gdshader")


func configure(a: ForestAtmosphere, v: ForestVegetation, observer: Camera3D = null) -> void:
	atmosphere = a
	vegetation = v
	original_sky = atmosphere.world_env.sky.sky_material
	original_ssao = atmosphere.world_env.ssao_intensity
	sky_material.shader = load("res://shaders/painterly_sky.gdshader")
	sky_material.set_shader_parameter("cloud_noise", preload("res://art/clouds/noise.tres"))
	if atmosphere.cloud_deck != null:
		atmosphere.cloud_deck.configure_sky(sky_material)
	add_child(pixel_renderer)
	if observer != null:
		pixel_renderer.configure(observer)
	set_mode(Mode.PIXEL if observer != null else Mode.PAINTERLY)


func set_enabled(value: bool) -> void:
	set_mode(Mode.PAINTERLY if value else Mode.BASELINE)


func set_mode(value: Mode) -> void:
	mode = value
	enabled = mode != Mode.BASELINE
	pixel_renderer.set_enabled(mode == Mode.PIXEL)
	atmosphere.set_cloud_style_enabled(enabled)
	atmosphere.world_env.sky.sky_material = sky_material if enabled else original_sky
	atmosphere.world_env.ssao_intensity = .80 if enabled else original_ssao
	for material in original_shaders:
		material.shader = _styled_shader() if enabled else original_shaders[material]
	_process(0)
	mode_changed.emit(mode_title())


func cycle_mode() -> void:
	set_mode((mode + 1) % Mode.size() as Mode)


func mode_title() -> String:
	return ["Исходный", "Живописный", "Пиксельный"][mode]


func _styled_shader() -> Shader:
	return pixel_shader if mode == Mode.PIXEL else foliage_shader


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F8:
		cycle_mode()


func _process(_dt: float) -> void:
	if (
		vegetation != null
		and (vegetation.material_revision != impostor_style_revision or mode != impostor_style_mode)
	):
		for asset in vegetation.impostor_assets.values():
			asset.material.set_shader_parameter("presentation_style", mode)
		impostor_style_revision = vegetation.material_revision
		impostor_style_mode = mode
	if not enabled or atmosphere == null:
		return
	# World reload can replace view batches. Never read/mutate the simulation here.
	if material_revision != vegetation.material_revision:
		material_revision = vegetation.material_revision
		var current := {}
		for node in vegetation.get_children():
			if node.has_meta(&"plant_impostor") or node.is_queued_for_deletion():
				continue
			if node is not MultiMeshInstance3D or node.material_override is not ShaderMaterial:
				continue
			var material: ShaderMaterial = node.material_override
			if current.has(material):
				continue
			current[material] = original_shaders.get(material, material.shader)
			material.shader = _styled_shader()
		original_shaders = current
	var daylight := clampf(atmosphere.world_env.ambient_light_energy / .55, 0, 1)
	# Ambient has a nonzero night floor, so solar energy owns the cloud day/night.
	daylight *= smoothstep(0, .12, atmosphere.solar_energy)
	var zenith := atmosphere.sky_mat.sky_top_color.lerp(Color(.10, .32, .74), daylight * .72)
	var horizon := atmosphere.sky_mat.sky_horizon_color.lerp(Color(.59, .76, .89), daylight * .60)
	_set_sky_parameter(&"zenith", zenith)
	_set_sky_parameter(&"horizon", horizon)
	_set_sky_parameter(&"sun_tint", atmosphere.sun.light_color)
	_set_sky_parameter(&"sun_direction", atmosphere.sun.global_basis.z.normalized())
	_set_sky_parameter(&"daylight", daylight)
	_set_sky_parameter(&"cloud_cover", atmosphere.cloud_cover)
	_set_sky_parameter(&"weather_time", atmosphere.displayed_weather.get("weather_time_s", 0.0))


func _set_sky_parameter(name: StringName, value: Variant) -> void:
	if not sky_values.has(name) or sky_values[name] != value:
		sky_values[name] = value
		sky_material.set_shader_parameter(name, value)
