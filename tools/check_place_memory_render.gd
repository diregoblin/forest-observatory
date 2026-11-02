extends Node

var world
var output := "res://artifacts/place-memory-render"


func start(scene) -> void:
	world = scene
	_run.call_deferred()


func photo(label: String, climate: Dictionary) -> void:
	world.vegetation.set_weather(climate)
	world.atmosphere.set_season(climate)
	world.painterly_style._process(0)
	for frame in 5:
		await RenderingServer.frame_post_draw
	assert(
		get_viewport().get_texture().get_image().save_png(output.path_join(label + ".png")) == OK
	)


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	world._finish_model_work(true)
	world.set_process(false)
	world.paused = true
	world.hud.visible = false
	world.habitat_view.paused = true
	Engine.max_fps = 30
	var clear: Dictionary = world.weather.sample(ForestClimate.sample(0, 200), 0)
	clear.cloud_cover = .15
	clear.precipitation_m_s = 0.0
	clear.rain_fraction = 0.0
	clear.snow_water_m = 0.0
	clear.wind_m_s = 2.0
	var center := Vector3(160, world.land.height_at(160, 285), 285)
	world.camera.position = center + Vector3(10, 13, 17)
	world.camera.look_at(center)
	world.terrain.advance_ecology_display(1)
	await photo("01-before-traffic", clear)
	var id := 0
	# Explicit repeated path fixture. Production consumes this same path structure.
	# Not a claim that 400 live animals crossed here in the rendered seconds.
	world.animals.path_history[id] = {
		"times": PackedFloat64Array([0, 1000]),
		"points": PackedVector3Array([center - Vector3(12, 0, 0), center + Vector3(12, 0, 0)])
	}
	var budget: PackedFloat64Array = world._ecosystem_budget()
	for passage in 400:
		world.animals.ticks += 1
		world.habitat._record_traffic(0, clear)
	print(
		"TRAFFIC_DIAGNOSTIC ",
		Array(world.habitat.traffic).max(),
		" at ",
		world.habitat.traffic.find(Array(world.habitat.traffic).max()),
		" center ",
		world.water.index_at(center.x, center.z),
		" depth ",
		world.water.depth[world.water.index_at(center.x, center.z)]
	)
	assert(
		Array(world.habitat.traffic).max() > .5, "Repeated path must produce a visible real field"
	)
	world.groundcover.refresh()
	world.terrain.refresh_ecology(world.soil, world.water, world.groundcover)
	world.terrain.advance_ecology_display(1)
	world.terrain.refresh_traffic(world.habitat)
	world.vegetation.displayed_tick = -1
	world.vegetation.refresh_trees(clear)
	for e in 3:
		assert(absf(world._ecosystem_budget()[e] - budget[e]) < 1e-5)
	assert(world.terrain.material.get_shader_param("traffic_enabled") == true)
	assert(
		(
			(
				world
				. terrain
				. traffic_texture
				. get_image()
				. get_pixel(
					int(center.x / world.water.cell_size), int(center.z / world.water.cell_size)
				)
				. r
			)
			> .5
		)
	)
	await photo("02-after-repeated-path", clear)
	world.terrain.material.set_shader_param("traffic_enabled", false)
	await photo("02-control-traffic-disabled", clear)
	world.terrain.material.set_shader_param("traffic_enabled", true)
	var tree := -1
	for i in world.trees.species.size():
		var d: ForestPlantDefinition = world.settings.plants[world.trees.species[i]]
		if d.growth_form == &"tree" and not d.deciduous and d.snow_retention >= .6:
			tree = i
			break
	assert(tree >= 0)
	var point: Vector3 = world.trees.positions[tree]
	var height: float = world.trees._height(tree)
	world.camera.position = point + Vector3(height * .8, height * .7, height * 1.2)
	world.camera.look_at(point + Vector3.UP * height * .5)
	await photo("03-crown-no-snow", clear)
	# Accumulate actual SWE through weather, rather than paint a new reservoir.
	var winter := ForestClimate.sample(0, 15)
	world.weather.forced = 1
	world.weather.forced_until_s = 10000.0
	var snowy: Dictionary = world.weather.step(2400, winter)
	assert(world.weather.snow_water_m > .005)
	assert(
		(
			absf(
				world.weather.precipitation_m - world.weather.snow_water_m - world.weather.liquid_m
			)
			< 1e-9
		)
	)
	world.terrain.material.set_shader_param("snow_water_m", world.weather.snow_water_m)
	world.vegetation.refresh_trees(snowy)
	await photo("04-crown-with-snow", snowy)
	for mode in [0, 1]:
		world.painterly_style.set_mode(mode)
		await photo("05-snow-style-" + str(mode), snowy)
	var d: ForestPlantDefinition = world.settings.plants[world.trees.species[tree]]
	var load_index := ForestTrees.snow_load_index(d, snowy)
	assert(load_index > .25)
	assert(
		(
			float(
				world.vegetation.tree_materials[world.trees.species[tree]].get_shader_parameter(
					"snow_load"
				)
			)
			> .25
		)
	)
	var result := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"traffic_from_path_fixture": true,
		"real_cover_transfer_cnp": true,
		"snow_from_weather_bucket": true,
		"snow_water_m": world.weather.snow_water_m,
		"crown_load_index": load_index,
		"boundary": "Repeated-path and cold-front fixtures, not long live GPU observations"
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("PLACE_MEMORY_RENDER ", JSON.stringify(result))
	get_tree().quit()
