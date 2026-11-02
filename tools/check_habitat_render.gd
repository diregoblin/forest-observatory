extends Node

var world
var output := "res://artifacts/habitat-render"
var images: Array = []


func start(scene) -> void:
	world = scene
	_run.call_deferred()


func capture(name: String, climate: Dictionary) -> void:
	world.atmosphere.set_season(climate)
	world.painterly_style._process(0)
	world.vegetation.set_weather(climate)
	world.habitat_view.paused = true
	world.habitat_view.refresh(climate)
	world.hud.notice("Изолированная визуальная проверка · " + name)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(output.path_join(name + ".png")) == OK)
	images.append({"name": name, "width": image.get_width(), "height": image.get_height()})
	print("HABITAT_CAPTURE ", name)


func pose(id: int, clip: String, t: float) -> void:
	var view: ForestAnimalsView = world.animals_view
	view.animation_players[id].play(clip)
	view.animation_players[id].seek(t, true)
	view.animation_poses[id] = ForestAnimalMotion.sample(clip, t)
	var actual: Variant = view.batches[id].get_instance_shader_parameter("pose_head")
	assert(
		actual != null and absf(float(actual) - view.animation_poses[id][1]) < 1e-5,
		"AnimationPlayer drives the actual shader pose"
	)


func frame_bounds(bounds: AABB, direction := Vector3(.65, .4, 1.0)) -> void:
	var center := bounds.get_center()
	world.camera.position = center + direction.normalized() * maxf(1.6, bounds.size.length() * 1.55)
	world.camera.look_at(center)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	world._finish_model_work(true)
	world.paused = true
	world.capture_dir = ""
	world.set_process(false)
	Engine.max_fps = 30
	world.hud.set_paused(true)
	world.hud.visible = false
	var frozen: Dictionary = world._world_snapshot().models
	var clear: Dictionary = world.weather.sample(ForestClimate.sample(0, 200), 0)
	clear.rain_fraction = 0.0
	clear.precipitation_m_s = 0.0
	clear.cloud_cover = .12
	clear.weather_time_s = 0.0
	var center := Vector3(190, world.land.height_at(190, 285), 285)
	world.camera.position = center + Vector3(1.3, 1.7, 1.7)
	world.camera.look_at(center)
	world.vegetation.refresh_trees(clear)
	world.terrain.advance_ecology_display(1)
	await capture("01-ground-state", clear)
	var animal := 0
	world.animals_view.refresh(1)
	frame_bounds(world.animals_view.selection_shape(animal).bounds)
	pose(animal, "feed", .0)
	var before_shape: Dictionary = world.animals_view.selection_shape(animal)
	await capture("02-hare-feed-a", clear)
	pose(animal, "feed", .28)
	var after_shape: Dictionary = world.animals_view.selection_shape(animal)
	assert(
		before_shape.faces != after_shape.faces,
		"Picking uses the animated pose, not the static rest mesh"
	)
	await capture("03-hare-feed-b", clear)
	assert(
		world._world_snapshot().models == frozen, "Animation and photographs cannot advance ecology"
	)
	var id := -1
	for i in world.trees.species.size():
		if (
			world.settings.plants[world.trees.species[i]].growth_form == &"tree"
			and world.settings.plants[world.trees.species[i]].reference_height_m < 16
		):
			id = i
			break
	assert(id >= 0)
	world.trees._die(id)
	world.trees.fallen[id] = 1
	world.vegetation.displayed_tick = -1
	world.vegetation.refresh_trees(clear)
	var log_center: Vector3 = world.trees.fallen_transform(id) * Vector3(0, 2, 0)
	world.camera.position = log_center + Vector3(1.5, 3, 2)
	world.camera.look_at(log_center)
	await capture("04-fallen-tree", clear)
	world.camera.view(2)
	await capture("05-clear-creek", clear)
	var wet: Dictionary = clear.duplicate()
	wet.cloud_cover = 1.0
	wet.rain_fraction = 1.0
	wet.precipitation_m_s = world.settings.rainfall_m_s
	wet.wind_m_s = 10.0
	wet.weather_time_s = 12.0
	world.atmosphere.rain_particles.speed_scale = 1
	world.atmosphere.rain_particles.preprocess = 1.4
	world.water_view.material_override.set_shader_parameter("rainfall", 1.0)
	world.water_view.material_override.set_shader_parameter("weather_time", 12.0)
	await capture("06-rain-creek", wet)
	var snow: Dictionary = clear.duplicate()
	snow.temperature_c = -6.0
	snow.cloud_cover = .9
	snow.rain_fraction = 0.0
	snow.precipitation_m_s = world.settings.rainfall_m_s
	snow.snow_water_m = .01
	world.terrain.material.set_shader_param("snow_water_m", .01)
	await capture("07-snow-cover-view-fixture", snow)
	# Actual litter transfer at a real plant, compared at the same camera.
	world.terrain.material.set_shader_param("snow_water_m", 0.0)
	var leaf_id := -1
	for i in world.trees.species.size():
		if (
			world.settings.plants[world.trees.species[i]].deciduous
			and world.trees.leaf_carbon[i] > .01
		):
			leaf_id = i
			break
	assert(leaf_id >= 0)
	var point: Vector3 = world.trees.positions[leaf_id] + Vector3(1.2, 0, .4)
	point.y = world.land.height_at(point.x, point.z)
	world.camera.position = point + Vector3(.5, 1.2, 1)
	world.camera.look_at(point)
	await capture("08-under-crown-before-litter", clear)
	var tree: ForestTrees = world.trees
	tree.elapsed_s = (
		(world.settings.plants[tree.species[leaf_id]].leaf_off_day - world.settings.start_day)
		* ForestClimate.DAY_S
	)
	tree._leaf_turnover(25 * ForestClimate.DAY_S)
	world.terrain.refresh_ecology(world.soil, world.water, world.groundcover)
	world.terrain.advance_ecology_display(1)
	await capture("09-under-crown-after-litter", clear)
	var bird := -1
	for i in world.animals.species.size():
		if world.animals.definitions[world.animals.species[i]].flight_height_m > 0:
			bird = i
			break
	assert(bird >= 0)
	world.animals.actions[bird] = "seek_food"
	world.animals_view.refresh(1)
	frame_bounds(world.animals_view.selection_shape(bird).bounds)
	pose(bird, "fly", 0)
	await capture("10-thrush-flight-a", clear)
	pose(bird, "fly", .08)
	await capture("11-thrush-flight-b", clear)
	world.animals.actions[bird] = "survey"
	world.habitat_view.paused = false
	world.habitat_view.last_sound_s = -10
	world.habitat_view._sounds(clear)
	assert(
		world.habitat_view.sound.stream == world.habitat_view.chirp,
		"A real nearby awake bird selects the spatial chirp"
	)
	assert(
		(
			world.habitat_view.sound.position.distance_to(
				world.animals.positions[bird] + Vector3.UP * 1.8
			)
			< .001
		)
	)
	assert(world.habitat_view.chirp.save_to_wav("res://artifacts/habitat-render/chirp.wav") == OK)
	assert(world.habitat_view.rustle.save_to_wav("res://artifacts/habitat-render/rustle.wav") == OK)
	var swimmer := -1
	for i in world.animals.species.size():
		if world.animals.definitions[world.animals.species[i]].can_swim:
			swimmer = i
			break
	assert(swimmer >= 0)
	var wet_cell := -1
	for k in world.water.depth.size():
		if world.water.depth[k] > .3 and k / world.water.resolution > world.water.resolution / 3:
			wet_cell = k
			break
	assert(wet_cell >= 0)
	var swimming_point := Vector3((wet_cell % world.water.resolution+.5)*world.water.cell_size,0,(wet_cell/world.water.resolution+.5)*world.water.cell_size)
	swimming_point.y = world.land.height_at(swimming_point.x,swimming_point.z)
	world.animals.positions[swimmer] = swimming_point
	world.animals.path_history[swimmer] = {"times":PackedFloat64Array([0]),"points":PackedVector3Array([swimming_point])}
	world.animals.actions[swimmer] = "search_prey"
	world.animals_view.refresh(1)
	assert(world.animals.is_swimming(swimmer))
	assert(world.animals_view.displayed_transforms[swimmer].origin.y > swimming_point.y)
	frame_bounds(world.animals_view.selection_shape(swimmer).bounds)
	pose(swimmer,"swim",.25)
	await capture("12-fox-swimming",clear)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"animationplayer_drives_pose": true,
		"animated_observer_geometry": true,
		"spatial_audio_source_and_stream": true,
		"swimmer_displayed_at_surface":true,
		"views_do_not_advance_models": true,
		"images": images,
		"boundary":
		"Short isolated fixtures; forced fallen tree and snow cover, no long thermal test"
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("HABITAT_RENDER_CHECK ", JSON.stringify(report))
	get_tree().quit()
