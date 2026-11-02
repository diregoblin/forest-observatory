extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	_run.call_deferred()


func fixture(bird := false) -> Dictionary:
	var s: ForestSettings = CONFIG.duplicate(true)
	s.tree_attempts = 0
	s.water_resolution = 16
	s.headwater_length = s.extent
	s.headwater_width = s.extent
	s.headwater_m3_s = 0
	s.spring_enabled = false
	s.start_day = 150
	var plant: ForestPlantDefinition = load("res://data/plants/rowan.tres").duplicate(true)
	plant.stress_days = 1e8
	plant.minimum_channel_distance = 0
	plant.recruitment_light = 0
	s.plants = [plant]
	var land := ForestLandscape.new(s)
	var water := ForestWatershed.new(land)
	water.depth.fill(0)
	water.soil.fill(.65)
	var soil := ForestSoil.new(water)
	var trees := ForestTrees.new(land, soil)
	for point in [Vector2(360, 240), Vector2(365, 242)]:
		trees._append(0, Vector3(point.x, land.height_at(point.x, point.y), point.y), 1, 25)
	trees._initial_count = trees.species.size()
	var totals := trees._totals()
	trees.initial_c = totals[0]
	trees.initial_n = totals[1]
	trees.initial_p = totals[2]
	var d: ForestAnimalDefinition = load("res://data/animals/thrush.tres").duplicate(true)
	d.initial_count = 1 if bird else 0
	var animals := ForestAnimals.new(land, trees, water, soil, [d])
	var habitat := ForestHabitat.new(trees, water, soil, animals)
	animals.habitat = habitat
	trees.habitat = habitat
	return {
		"settings": s,
		"land": land,
		"water": water,
		"soil": soil,
		"trees": trees,
		"animals": animals,
		"habitat": habitat
	}


func budget(w: Dictionary) -> PackedFloat64Array:
	var values := PackedFloat64Array([0, 0, 0])
	for model in [w.trees, w.soil, w.habitat]:
		var m: Dictionary = model.metrics()
		values[0] += m.carbon_kg
		values[1] += m.nitrogen_kg
		values[2] += m.phosphorus_kg
	values[0] += (
		w.soil.metrics().respired_kg_c + w.habitat.respired_kg_c - w.trees.photosynthesized_kg_c
	)
	return values


func same_budget(a: PackedFloat64Array, b: PackedFloat64Array) -> void:
	for e in 3:
		assert(absf(a[e] - b[e]) < 1e-6, "C/N/P conserved through real transfers")


func _run() -> void:
	var w := fixture()
	var soil_before: Dictionary = w.soil.snapshot()
	var range_c := Vector2(INF, -INF)
	for z in 16:
		for x in 16:
			var point := Vector3((x + .5) * 32, 0, (z + .5) * 32)
			var c: float = w.soil.sample(point).organic_c_kg_m2
			range_c.x = minf(range_c.x, c)
			range_c.y = maxf(range_c.y, c)
	assert(range_c.y - range_c.x > .5, "Real initial soil stocks are heterogeneous")
	var bad := PackedFloat64Array()
	bad.resize(256)
	bad.fill(1)
	bad[12] = NAN
	assert(not w.soil.native.initialize_pattern(bad, bad, bad))
	assert(w.soil.snapshot() == soil_before, "Bad pattern cannot partly mutate soil")
	var initial := budget(w)
	var climate := ForestClimate.sample(0, 150)
	climate.wind_m_s = 2.0
	climate.rain_fraction = 0.0
	climate.weather_time_s = 0.0
	w.habitat.step(ForestClimate.DAY_S, climate)
	assert(w.habitat.metrics().carbon_kg > 0, "Flowers feed finite local insect pools")
	same_budget(initial, budget(w))
	var pollen: float = w.habitat.pollination_at(w.trees.positions[0])
	var blank := fixture()
	blank.settings.plants[0].flower_start_day = 220
	var barren: Dictionary = blank.soil.snapshot()
	barren.cells.surface_c.fill(0)
	assert(blank.soil.restore(barren))
	blank.habitat.step(ForestClimate.DAY_S, climate)
	assert(blank.habitat.metrics().carbon_kg == 0, "No flowers/logs: no invented insects")
	assert(pollen > blank.habitat.pollination_at(blank.trees.positions[0]))
	var before_eating := budget(w)
	var food: Vector3 = w.habitat.harvest_insects(w.trees.positions[0], .00001)
	assert(food.x > 0)
	var after_eating := budget(w)
	for e in 3:
		assert(absf(before_eating[e] - after_eating[e] - food[e]) < 1e-6)
	var fallen := fixture()
	var before_fall := budget(fallen)
	fallen.trees._update_light()
	var covered: float = fallen.trees._light_at(360, 240)
	fallen.trees._windfall(ForestClimate.YEAR_S, climate)
	assert(fallen.trees.fallen.count(1) == 0, "Calm weather cannot blow down live trees")
	var storm := climate.duplicate()
	storm.wind_m_s = 10000.0  # Deterministic forced-event control, not a plausible wind scenario.
	storm.wind_direction = Vector2.RIGHT
	fallen.trees._windfall(ForestClimate.YEAR_S, storm)
	assert(fallen.trees.fallen.count(1) == 2)
	fallen.trees._update_light()
	assert(fallen.trees._light_at(360, 240) > covered, "Fallen trees leave a light gap")
	assert(fallen.trees.fallen_transform(0).basis.y.normalized().dot(Vector3.UP) < .7)
	fallen.trees._decay_dead(ForestClimate.DAY_S, climate, fallen.water)
	fallen.habitat.step(ForestClimate.DAY_S, climate)
	assert(fallen.habitat.metrics().carbon_kg > 0, "Dead wood supports real insect biomass")
	same_budget(before_fall, budget(fallen))
	var seeded := fixture(true)
	# Transfer, rather than inject, a finite initial ripe crop into this control.
	var c := .05
	var d: ForestPlantDefinition = seeded.settings.plants[0]
	seeded.trees.biomass_c[0] -= c
	seeded.trees.biomass_n[0] -= c / d.cn_ratio
	seeded.trees.biomass_p[0] -= c / d.cp_ratio
	seeded.trees.seed_c[0] = c
	seeded.trees.seed_n[0] = c / d.cn_ratio
	seeded.trees.seed_p[0] = c / d.cp_ratio
	seeded.trees.fruit_c[0] = c
	var seed_budget := budget(seeded)
	seeded.habitat.carry_seed(0, 0)
	assert(seeded.trees.reserved_seed_c[0] > 0)
	seeded.animals.positions[0] = Vector3(410, seeded.land.height_at(410, 280), 280)
	seeded.habitat.step(ForestClimate.DAY_S * 3, climate)
	assert(seeded.habitat.seed_drops == 1 and seeded.habitat.transported_recruits == 1)
	assert(seeded.trees.positions[-1].distance_to(seeded.animals.positions[0]) < .11)
	assert(seeded.trees.reserved_seed_c[0] == 0)
	same_budget(seed_budget, budget(seeded))
	var saved: Dictionary = seeded.habitat.snapshot()
	var corrupt := saved.duplicate(true)
	corrupt.wood_c[0] = -1
	assert(not seeded.habitat.restore(corrupt) and seeded.habitat.snapshot() == saved)
	assert(seeded.habitat.restore(saved))
	var dust := fixture()
	var dust_cell: int = dust.habitat.cell(dust.trees.positions[0])
	dust.habitat.pollinator_c[dust_cell] = 9e-46
	dust.habitat.pollinator_n[dust_cell] = 9e-47
	dust.habitat.pollinator_p[dust_cell] = 9e-48
	var dust_state: Dictionary = dust.habitat.snapshot()
	assert(dust.habitat.harvest_insects(dust.trees.positions[0], 1) == Vector3.ZERO)
	assert(
		dust.habitat.snapshot() == dust_state,
		"Float32 subnormal rounding cannot overdraft float64 reserves"
	)
	# Flight crosses wet cells; the same movement with a ground trait cannot.
	seeded.water.depth.fill(2)
	var bird_point: Vector3 = seeded.animals.positions[0]
	seeded.animals.home_positions[0] = bird_point
	seeded.animals.definitions[0].flight_height_m = 0
	assert(not seeded.animals._move(0, Vector3.RIGHT, .5))
	seeded.animals.definitions[0].can_swim = true
	var swim_before: Vector3 = seeded.animals.positions[0]
	var carbon_before: float = seeded.animals.biomass_c[0]
	assert(seeded.animals._move(0, Vector3.RIGHT, .5))
	var swim_distance: float = (
		Vector2(
			seeded.animals.positions[0].x - swim_before.x,
			seeded.animals.positions[0].z - swim_before.z
		)
		. length()
	)
	assert(absf(swim_distance - .2) < .0001 and seeded.animals.is_swimming(0))
	assert(
		(
			absf(
				(
					carbon_before
					- seeded.animals.biomass_c[0]
					- swim_distance * seeded.animals.definitions[0].movement_carbon_kg_m * 2.5
				)
			)
			< 1e-9
		)
	)
	assert(load("res://data/animals/fox.tres").can_swim)
	seeded.animals.definitions[0].can_swim = false
	seeded.animals.definitions[0].flight_height_m = 1.8
	assert(seeded.animals._move(0, Vector3.RIGHT, .5))
	assert(seeded.animals.positions[0].x > bird_point.x)
	seeded.water.depth.fill(0)
	seeded.animals.definitions[0].fruit_diet = false
	seeded.animals.definitions[0].flight_height_m = 0
	seeded.habitat.last_track_positions = seeded.animals.positions.duplicate()
	seeded.habitat.tracks.clear()
	seeded.habitat._record_tracks(climate)
	seeded.animals.positions[0] += Vector3(1, 0, 0)
	seeded.habitat._record_tracks(climate)
	assert(seeded.habitat.tracks.size() == 1)
	var rain := climate.duplicate()
	rain.rain_fraction = 1.0
	seeded.habitat.elapsed_s += ForestClimate.DAY_S * 20
	seeded.habitat._record_tracks(rain, ForestClimate.DAY_S * 20)
	assert(seeded.habitat.tracks.is_empty(), "Later rain must erase existing prints")
	_check_weather(w)
	var report := {
		"passed": true,
		"soil_carbon_range_kg_m2": [range_c.x, range_c.y],
		"insect_food_null": true,
		"finite_insect_food": true,
		"windfall_null_and_gap": true,
		"transported_seed_established": true,
		"cnp_conserved": true,
		"corrupt_habitat_rejected": true,
		"snow_water_conserved": true,
		"weather_exact_continuation": true,
		"native_variable_rain": true,
		"flight_crosses_water_ground_null": true,
		"swim_speed_and_energy_cost": true,
		"later_rain_erases_tracks": true
	}
	FileAccess.open("res://artifacts/weather-habitat-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WEATHER_HABITAT_CHECK ", JSON.stringify(report))
	quit()


func _check_weather(w: Dictionary) -> void:
	var weather := ForestWeather.new(w.settings)
	var winter := ForestClimate.sample(0, 20)
	weather.toggle(false)
	weather.step(20, winter)
	assert(weather.snow_water_m > 0 and weather.liquid_m == 0)
	weather.toggle(true)
	var before_snow := weather.snow_water_m
	weather.step(100, ForestClimate.sample(0, 200))
	assert(weather.snow_water_m < before_snow and weather.liquid_m > 0)
	assert(absf(weather.precipitation_m - weather.liquid_m - weather.snow_water_m) < 1e-12)
	var saved := weather.snapshot()
	var reference := ForestWeather.new(w.settings)
	assert(reference.restore(saved))
	for i in 100:
		var climate := ForestClimate.sample(i * 1200, 150)
		assert(weather.step(.5, climate) == reference.step(.5, climate))
	assert(weather.snapshot() == reference.snapshot())
	var corrupt := saved.duplicate(true)
	corrupt.snow_water_m += .1
	assert(not reference.restore(corrupt))
	var original: Dictionary = w.water.native.snapshot()
	var before: float = w.water.native.metrics().input_m3
	assert(w.water.native.advance_forced(.5, .0001))
	var injected: float = w.water.native.metrics().input_m3 - before
	assert(absf(injected - w.settings.extent * w.settings.extent * .0001 * .5) < 1e-8)
	assert(
		w.water.native.snapshot().options == original.options,
		"Transient forcing must not change persisted coefficients"
	)
