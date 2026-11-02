extends "res://tools/preview_ground_turf.gd"

var caption: Label
var samples := []


func difference(a: Image, b: Image) -> float:
	# Exclude the changing fixture caption from every visual comparison.
	var total := 0.0
	var count := 0
	for y in range(80, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			total += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return total / count


func _initialize() -> void:
	output = "res://artifacts/terrain-features"
	super._initialize()


func capture(label: String) -> Image:
	caption.text = "Terrain3D 1.1 · изолированная проба · " + label
	scene.painterly_style._process(0)
	for frame in 10:
		await RenderingServer.frame_post_draw
	var gpu := []
	for frame in 12:
		await RenderingServer.frame_post_draw
		gpu.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	gpu.sort()
	samples.append(
		{
			"label": label,
			"gpu_ms_p50": gpu[gpu.size() / 2],
			"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		}
	)
	FileAccess.open(output.path_join("samples.json"), FileAccess.WRITE).store_string(
		JSON.stringify(samples, "  ")
	)
	return image


func packed_normal(with_ao: bool) -> ImageTexture:
	# Numeric packing from our existing maps, following the upstream 1.1 format.
	var source: Image = (
		load("res://art/ground-turf/normal-roughness-ao.png").get_image().duplicate()
	)
	source.convert(Image.FORMAT_RGBA8)
	source.resize(256, 256)
	var result := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in 256:
		for x in 256:
			var p := source.get_pixel(x, y)
			var normal := Vector3(p.r * 2 - 1, p.g * 2 - 1, 0)
			normal.z = sqrt(maxf(.001, 1 - normal.x * normal.x - normal.y * normal.y))
			var magnitude := sqrt(p.a) * .5 + .5 if with_ao else 1.0
			normal = normal.normalized() * magnitude * .5 + Vector3.ONE * .5
			result.set_pixel(x, y, Color(normal.x, normal.y, normal.z, p.b))
	result.generate_mipmaps()
	return ImageTexture.create_from_image(result)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene._finish_model_work(true)
	scene.capture_step = 8
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.turf_cards.set_process(false)
	scene.hud.visible = false
	Engine.max_fps = 20
	var layer := CanvasLayer.new()
	root.add_child(layer)
	caption = Label.new()
	caption.position = Vector2(16, 16)
	caption.add_theme_color_override("font_shadow_color", Color.BLACK)
	caption.add_theme_constant_override("shadow_offset_x", 1)
	caption.add_theme_constant_override("shadow_offset_y", 1)
	layer.add_child(caption)
	var frozen := model_bytes()
	var climate := ForestClimate.sample(0, 155, 60, 12)
	climate.cloud_cover = .18
	climate.weather_time_s = 0.0
	scene.atmosphere.set_season(climate)
	scene.atmosphere.rain_particles.emitting = false
	scene.painterly_style.set_mode(0)
	scene.terrain.advance_ecology_display(1)
	var point := Vector3(200, scene.terrain.data.get_surface_height(Vector3(200, 0, 196)), 196)
	scene.camera.position = point + Vector3(0, .45, 2.0)
	scene.camera.look_at(point)
	for view in [
		scene.vegetation, scene.turf_cards, scene.animals_view, scene.habitat_view, scene.fungi_view
	]:
		view.visible = false
	await capture("00-ecological-material")
	var terrain = scene.terrain
	var asset := Terrain3DTextureAsset.new()
	asset.set_asset_name("Native turf material study")
	asset.albedo_texture = load("res://art/ground-turf/albedo-height.png")
	asset.normal_texture = packed_normal(false)
	asset.uv_scale = 2.0 / 1.6
	asset.displacement_scale = 1.0
	asset.ao_strength = 1.0
	asset.ao_light_affect = .25
	terrain.assets.set_texture_asset(0, asset)
	terrain.material.shader_override_enabled = false
	terrain.material.auto_shader_enabled = true
	terrain.material.set_shader_param("auto_base_texture", 0)
	terrain.material.set_shader_param("auto_overlay_texture", 0)
	var no_ao := await capture("01-native-no-packed-ao")
	asset.normal_texture = packed_normal(true)
	var ao := await capture("02-native-packed-ao")
	var ao_repeat := await capture("02a-native-packed-ao-null-control")
	var null_change := difference(ao, ao_repeat)
	var ao_change := difference(no_ao, ao)
	assert(ao_change > maxf(.00001, null_change * 3), "AO must exceed the unchanged render control")
	terrain.tessellation_level = 2
	terrain.material.displacement_scale = 0.0
	var flat := await capture("03-tessellated-flat")
	terrain.material.displacement_scale = .12
	var displaced := await capture("04-displaced-12cm-range")
	var displacement_change := difference(flat, displaced)
	assert(displacement_change > .0001, "Nonzero native displacement must differ from zero")
	# Clipmap tessellation adds inner LODs, not a global 4^n multiplier on all
	# submitted triangles. The zero/nonzero pair checks the actual native effect.
	assert(terrain.tessellation_level == 2)
	# Native texture displacement is visual, not a new collision/hydrology height.
	assert(is_equal_approx(terrain.data.get_surface_height(point), point.y))
	terrain.material.show_contours = true
	await capture("05-contours")
	terrain.material.show_contours = false
	terrain.material.displacement_scale = 0.0
	terrain.tessellation_level = 0
	# Same viewpoint, brief return controls. This is not matched-density FPS evidence.
	scene.camera.position = point + Vector3(0, 1.65, 0)
	scene.camera.look_at(point + Vector3(0, 1, -30))
	for i in 18:
		scene.turf_cards._process(0)
	scene.turf_cards.visible = false
	await capture("06-grass-off-a")
	scene.turf_cards.visible = true
	await capture("07-current-cards")
	scene.turf_cards.visible = false
	var particles = (
		load("res://addons/terrain_3d/extras/particle_example/Terrain3DParticles.tscn")
		. instantiate()
	)
	particles.cell_width = 24.0
	particles.grid_width = 3
	particles.instance_spacing = .30
	particles.process_material = particles.process_material.duplicate(true)
	particles.process_material.set_shader_parameter("texture_filter", -1)
	particles.process_material.set_shader_parameter("wind_strength", .2)
	terrain.add_child(particles)
	particles._physics_process(0)
	await capture("08-upstream-particle-grass")
	var particle_count: int = particles.particle_count
	var particle_nodes: int = particles.particle_nodes.size()
	particles.queue_free()
	await process_frame
	scene.turf_cards.visible = true
	await capture("09-current-cards-return")
	scene.turf_cards.visible = false
	await capture("10-grass-off-return")
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"unchanged_models": true,
		"ao_mean_rgb_difference": ao_change,
		"unchanged_render_mean_rgb_difference": null_change,
		"displacement_mean_rgb_difference": displacement_change,
		"native_displacement_keeps_base_surface_height": true,
		"particle_count": particle_count,
		"particle_nodes": particle_nodes,
		"samples": samples,
		"boundary":
		(
			"Isolated native material and upstream grass study, not shipped defaults "
			+ "or matched-quality FPS. Particle example uses TIME and lacks our "
			+ "snow/soil/water/ecology masks."
		)
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("TERRAIN_FEATURES ", JSON.stringify(report))
	scene.free()
	layer.free()
	quit()
