class_name ForestAtmosphere
extends WorldEnvironment

var world_env := Environment.new()
var sky_mat := ProceduralSkyMaterial.new()
var sun := DirectionalLight3D.new()
var rain_particles := GPUParticles3D.new()
var rain_drop := QuadMesh.new()
var snow_flake := QuadMesh.new()
var observer: Camera3D
var raining := false
var seasonal_energy := 1.35
var solar_energy := 1.35
var cloud_cover := .18
var wind_m_s := 2.0
var displayed_weather := {}
var displayed_day := -1.0
var displayed_hour := -1.0


func configure() -> void:
	environment = world_env
	world_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# The sky changes continuously; avoid quality-mode radiance rebuilds each update.
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	sky_mat.sky_top_color = Color(.19, .34, .43)
	sky_mat.sky_horizon_color = Color(.72, .77, .72)
	sky_mat.ground_horizon_color = Color(.60, .65, .56)
	sky_mat.ground_bottom_color = Color(.23, .29, .22)
	sky.sky_material = sky_mat
	world_env.sky = sky
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.ambient_light_color = Color(.62, .73, .75)
	world_env.ambient_light_energy = .55
	world_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.fog_enabled = true
	world_env.fog_light_color = Color(.66, .73, .69)
	world_env.fog_density = .00065
	world_env.fog_sky_affect = .6
	world_env.ssao_enabled = RenderingServer.get_current_rendering_method() == "forward_plus"
	world_env.ssao_intensity = 1.5
	world_env.ssao_radius = 2.0
	world_env.glow_enabled = true
	world_env.glow_intensity = .35
	sun.rotation_degrees = Vector3(-27, -38, 0)
	sun.light_color = Color(1.0, .85, .62)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	# Thin leaves need a little depth bias; a larger normal offset distorts them.
	sun.shadow_bias = .3
	sun.directional_shadow_max_distance = 280
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func set_rain(raining: bool) -> void:
	self.raining = raining
	world_env.fog_density = .0014 if raining else .00065
	sun.light_energy = solar_energy * (1.0 - .65 * cloud_cover)
	rain_particles.emitting = raining


func set_season(climate: Dictionary) -> void:
	# Especially on pause: don't rebuild sky radiance for an unchanged model sample.
	if climate == displayed_weather:
		return
	displayed_weather = climate.duplicate(true)
	cloud_cover = climate.get("cloud_cover", .18)
	wind_m_s = climate.get("wind_m_s", 2.0)
	raining = climate.get("rain_fraction", 0.0) > .01
	var precip: float = climate.get("precipitation_m_s", 0.0)
	var snowing: bool = climate.temperature_c <= 0 and precip > 1e-9
	rain_particles.emitting = raining or snowing
	rain_particles.amount_ratio = maxf(.03, precip * 1000 * 3600 / 30.0)
	rain_particles.draw_pass_1 = snow_flake if snowing else rain_drop
	if rain_particles.process_material != null:
		rain_particles.process_material.initial_velocity_min = 1.5 if snowing else 18.0
		rain_particles.process_material.initial_velocity_max = 2.5 if snowing else 24.0
	world_env.fog_density = lerpf(.00065, .0025, cloud_cover)
	if rain_particles.process_material != null:
		var wind: Vector2 = climate.get("wind_direction", Vector2.RIGHT) * wind_m_s
		rain_particles.process_material.direction = (
			Vector3(wind.x * .04, -1, wind.y * .04).normalized()
		)
	displayed_day = climate.day
	displayed_hour = climate.hour
	var warmth := clampf((climate.temperature_c + 9.0) / 29.0, 0, 1)
	seasonal_energy = lerpf(.75, 1.35, warmth)
	var height: float = sin(climate.sun_elevation)
	var daylight := smoothstep(-.12, .18, height)
	var twilight := (1.0 - smoothstep(0, .3, absf(height))) * daylight
	sun.rotation = Vector3(-climate.sun_elevation, -climate.sun_azimuth, 0)
	solar_energy = seasonal_energy * sqrt(maxf(0, height))
	sun.light_color = Color(1.0, .48, .20).lerp(
		Color(.78, .85, 1.0).lerp(Color(1.0, .90, .72), warmth), smoothstep(0, .4, height)
	)
	sun.light_energy = solar_energy * (1.0 - .65 * cloud_cover)
	world_env.ambient_light_energy = lerpf(.28, .55, daylight) * (1.0 - .25 * cloud_cover)
	world_env.ambient_light_color = Color(.46, .53, .76).lerp(Color(.62, .73, .75), daylight)
	sky_mat.sky_top_color = Color(.012, .020, .055).lerp(Color(.19, .34, .43), daylight)
	sky_mat.sky_horizon_color = Color(.05, .07, .13).lerp(
		Color(.72, .77, .72).lerp(Color(.95, .43, .22), twilight), daylight
	)
	sky_mat.ground_horizon_color = Color(.035, .05, .08).lerp(Color(.60, .65, .56), daylight)
	sky_mat.ground_bottom_color = Color(.018, .025, .035).lerp(Color(.23, .29, .22), daylight)
	world_env.fog_light_color = Color(.045, .065, .11).lerp(Color(.66, .73, .69), daylight)


func attach_observer(camera: Camera3D) -> void:
	observer = camera
	rain_particles.amount = 900
	rain_particles.lifetime = 1.4
	rain_particles.visibility_aabb = AABB(Vector3(-35, -30, -35), Vector3(70, 60, 70))
	rain_particles.emitting = false
	var motion := ParticleProcessMaterial.new()
	motion.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	motion.emission_box_extents = Vector3(22, 12, 22)
	motion.direction = Vector3(.1, -1, .05)
	motion.spread = 3
	motion.initial_velocity_min = 18
	motion.initial_velocity_max = 24
	motion.gravity = Vector3.ZERO
	rain_particles.process_material = motion
	rain_drop.size = Vector2(.025, .7)
	snow_flake.size = Vector2(.09, .09)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.7, .83, .87, .32)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	rain_drop.material = material
	var snow_material := material.duplicate()
	snow_material.albedo_color = Color(.9, .94, 1, .8)
	snow_flake.material = snow_material
	rain_particles.draw_pass_1 = rain_drop
	rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_particles)


func _process(_dt: float) -> void:
	if observer != null:
		rain_particles.position = observer.position + Vector3.UP * 8 - observer.global_basis.z * 14
