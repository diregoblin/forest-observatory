extends SceneTree
var scene
var output := "res://artifacts/weather-life"
var report := {}


func _initialize():
	create_timer(100).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo(label: String) -> Image:
	for frame in 8:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(label + ".png")) == OK)
	return image


func difference(a: Image, b: Image) -> float:
	var delta := 0.0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			var c := a.get_pixel(x, y) - b.get_pixel(x, y)
			delta += absf(c.r) + absf(c.g) + absf(c.b)
	return delta / (ceilf(a.get_width() / 4.0) * ceilf(a.get_height() / 4.0) * 3)


func models() -> PackedByteArray:
	var saved := {}
	for key in scene._world_models():
		saved[key] = scene._world_models()[key].snapshot()
	return var_to_bytes(saved)


func _run():
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	scene.use_model_worker = false
	root.add_child(scene)
	scene.use_model_worker = false
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.capture_dir = ""
	scene.hud.visible = false
	Engine.max_fps = 30
	var id := -1
	for i in scene.trees.species.size():
		var d: ForestPlantDefinition = scene.settings.plants[scene.trees.species[i]]
		if d.growth_form == &"tree" and scene.trees.alive[i] and scene.trees.size[i] > .8:
			id = i
			break
	assert(id >= 0)
	var base: Vector3 = scene.trees.positions[id]
	scene.camera.position = base + Vector3(-8, 5, 15)
	scene.camera.look_at(base + Vector3.UP * 5)
	await photo("01-standing")
	scene.trees._die(id)
	scene.trees.fallen[id] = 1
	scene.trees.yaw[id] = .4
	scene.vegetation.displayed_tick = -1
	scene.vegetation.refresh_trees(scene._display_climate())
	var fall = scene.vegetation.treefall
	assert(fall.events.has(id))
	var duration: float = fall.events[id].duration
	var frozen = models()
	var start: Transform3D = scene.vegetation.displayed_shapes[id].transform
	scene.vegetation.advance_weather(duration * .25)
	await photo("02-cracking")
	var early: Transform3D = scene.vegetation.displayed_shapes[id].transform
	var saved: Dictionary = scene._world_snapshot()
	assert(saved.scene.treefalls.size() == 1)
	var paused_pose: Dictionary = fall.snapshot()
	scene.vegetation.advance_weather(0)
	assert(fall.snapshot() == paused_pose)
	assert(scene.vegetation.displayed_shapes[id].transform == early)
	scene.vegetation.advance_weather(duration * .5)
	var mid: Transform3D = scene.vegetation.displayed_shapes[id].transform
	assert(start != early and early != mid)
	assert(scene.vegetation.selection_shape(id).transform == mid)
	await photo("03-falling")

	assert(scene._restore_world(saved))
	assert(scene.vegetation.displayed_shapes[id].transform.is_equal_approx(early))
	assert(models() == frozen)
	var before_bad: Dictionary = scene._world_snapshot()
	var bad: Dictionary = before_bad.duplicate(true)
	bad.scene.treefalls[id].duration = NAN
	assert(not scene._restore_world(bad))
	assert(scene._world_snapshot() == before_bad)
	var impacts := 0
	fall.emitted.clear()
	scene.vegetation.advance_weather(duration + 1)
	for event in fall.emitted:
		if event.impact:
			impacts += 1
	assert(impacts == 1 and fall.events.is_empty())
	assert(
		scene.vegetation.displayed_shapes[id].transform.is_equal_approx(
			scene.trees.fallen_transform(id)
		)
	)
	await photo("04-fallen")
	for wav in [fall.crack, fall.impact]:
		var power := 0.0
		var peak := 0.0
		for i in wav.data.size() / 2:
			var value: float = wav.data.decode_s16(i * 2) / 32768.0
			power += value * value
			peak = maxf(peak, absf(value))
		assert(sqrt(power / (wav.data.size() / 2)) > .01 and peak < .99)
	fall.crack.save_to_wav(output.path_join("crack.wav"))
	fall.impact.save_to_wav(output.path_join("impact.wav"))
	report.treefall = {
		"pause_exact": true,
		"save_pose_exact": true,
		"invalid_load_atomic": true,
		"impact_once": true,
		"picking_matches": true,
		"audio_samples_valid": true,
		"audio_driver": AudioServer.get_driver_name()
	}
	# Wet river patch, fixed view, pure field controls and zero precipitation.
	var z := 260.0
	var x: float = scene.land.channel_x(z)
	var point := Vector3(x, scene.land.height_at(x, z), z)
	scene.camera.position = point + Vector3(1, 2.2, 7)
	scene.camera.look_at(point)
	var mat: ShaderMaterial = scene.water_view.material_override
	var wind = scene.vegetation.wind
	wind.submitted_weather = {}
	wind.clear_canopy()
	wind.flush_shelter()
	wind.advance(.2, Vector2.ZERO)
	wind.advance(.1, Vector2.ZERO)
	wind.apply(mat)
	mat.set_shader_parameter("spatial_rain", false)
	mat.set_shader_parameter("rainfall", 0.0)
	mat.set_shader_parameter("ripple_time_s", 2.0)
	var calm := await photo("05-water-calm")
	wind.advance(.2, Vector2(12, 0))
	wind.advance(.1, Vector2(12, 0))
	wind.apply(mat)
	var windy := await photo("06-water-gust")
	var wave_change := difference(calm, windy)
	assert(wave_change > .00005)
	# World-fixed mist, same sky/lighting: dry, humid, then daytime suppression.
	var eye := point+Vector3(18,0,38)
	eye.y=scene.land.height_at(eye.x,eye.z)+2.2
	scene.camera.position=eye
	scene.camera.look_at(point + Vector3.UP * 1.2)
	var mist: ShaderMaterial = scene.atmosphere.lowland_material
	var air := Image.create(2, 2, false, Image.FORMAT_RGBF)
	air.fill(Color(.5, 6, 1))
	var texture := ImageTexture.create_from_image(air)
	mist.set_shader_parameter("air_map", texture)
	mist.set_shader_parameter("night_factor", 1.0)
	var dry := await photo("07-lowland-dry")
	air.fill(Color(.98, 6, 1))
	texture.update(air)
	var humid := await photo("08-lowland-mist")
	var mist_change := difference(dry, humid)
	assert(mist_change > .0005)
	mist.set_shader_parameter("night_factor", 0.0)
	var day := await photo("09-day-clear")
	assert(difference(dry, day) < .0003)
	scene.atmosphere.set_diagnostic_enabled(true)
	assert(not scene.atmosphere.lowland_fog.visible)
	scene.atmosphere.set_diagnostic_enabled(false)
	scene.atmosphere.set_volumetric_enabled(false)
	assert(not scene.atmosphere.lowland_fog.visible)
	assert(models() == frozen)
	report.passed = true
	report.renderer = RenderingServer.get_current_rendering_method()
	report.wind_rgb_difference = wave_change
	report.mist_rgb_difference = mist_change
	report.authoritative_models_unchanged = true
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WEATHER_LIFE ", JSON.stringify(report))
	scene.free()
	quit()
