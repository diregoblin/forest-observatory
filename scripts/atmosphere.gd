class_name ForestAtmosphere
extends WorldEnvironment

var world_env := Environment.new()
var sun := DirectionalLight3D.new()
var rain_particles := GPUParticles3D.new()
var observer: Camera3D


func configure() -> void:
	environment = world_env
	world_env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(.19, .34, .43)
	sky_mat.sky_horizon_color = Color(.72, .77, .72)
	sky_mat.ground_horizon_color = Color(.60, .65, .56)
	sky_mat.ground_bottom_color = Color(.23, .29, .22)
	sky.sky_material = sky_mat
	world_env.sky = sky
	world_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
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
	sun.directional_shadow_max_distance = 280
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	add_child(sun)


func set_rain(raining: bool) -> void:
	world_env.fog_density = .0014 if raining else .00065
	sun.light_energy = 1.0 if raining else 1.35
	rain_particles.emitting = raining


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
	var drop := QuadMesh.new()
	drop.size = Vector2(.025, .7)
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = Color(.7, .83, .87, .32)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	drop.material = material
	rain_particles.draw_pass_1 = drop
	rain_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rain_particles)


func _process(_dt: float) -> void:
	if observer != null:
		rain_particles.position = observer.position + Vector3.UP * 8 - observer.global_basis.z * 14
