extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	create_timer(60).timeout.connect(func(): quit(1))
	_run.call_deferred()


func stand(resistance := 28.0) -> ForestTrees:
	var s: ForestSettings = CONFIG.duplicate(true)
	s.tree_attempts = 0
	var d: ForestPlantDefinition = s.plants[0].duplicate(true)
	d.wind_resistance_m_s = resistance
	d.reference_height_m = 13.0
	d.crown_radius_m = 3.0
	d.deciduous = false
	s.plants = [d]
	var trees := ForestTrees.new(ForestLandscape.new(s))
	for i in 240:
		trees._append(0, Vector3(350 + i % 20, 30, 240 + i / 20), 1, 25)
	trees._initial_count = trees.species.size()
	var totals := trees._totals()
	trees.initial_c = totals[0]
	trees.initial_n = totals[1]
	trees.initial_p = totals[2]
	return trees


func _run() -> void:
	var weather := ForestWeather.new(CONFIG)
	var climate := ForestClimate.sample(0, 180)
	var direction := ForestWeatherFront.direction(1)
	var p := Vector2.ONE * CONFIG.extent * .5 - direction * 180
	var q := p + direction * 320
	var t := 40.0
	var a := ForestWeatherFront.local(weather.sample(climate, t), p)
	var later := ForestWeatherFront.local(weather.sample(climate, t + 40), q)
	var backward := ForestWeatherFront.local(weather.sample(climate, t - 40), q)
	for key in ["temperature_c", "relative_humidity", "wind_m_s", "cloud_cover"]:
		assert(absf(a[key] - later[key]) < 1e-5, "Downwind front arrives after distance / speed")
	assert(absf(a.temperature_c - backward.temperature_c) > .1, "Backward arrival fails")
	var sectors := {}
	for index in 40:
		var bearing := fposmod(ForestWeatherFront.direction(index).angle(), TAU)
		sectors[floori(bearing / TAU * 8)] = true
	assert(sectors.size() == 8, "Weather wind covers all eight compass sectors")
	var spatial_range := 0.0
	for time in range(0, 700, 10):
		var sample := weather.sample(climate, time)
		var left := ForestWeatherFront.local(sample, p)
		var right := ForestWeatherFront.local(sample, q)
		spatial_range = maxf(spatial_range, absf(left.temperature_c - right.temperature_c))
		assert(left.relative_humidity >= 0 and left.relative_humidity <= 1)
		assert(right.wind_m_s >= 0)
	assert(spatial_range > 1, "Uniform weather fails the front test")
	# Cloud trajectories follow integrated wind through turns, never t * new wind.
	var minimum_alignment := 1.0
	var maximum_speed := 0.0
	for time in [20.0, 84.99, 85.01, 170.0, 340.0, 500.0]:
		var delta := weather.clouds.offset_at(time + .01) - weather.clouds.offset_at(time)
		var wind := weather.clouds._transport_velocity(time)
		minimum_alignment = minf(minimum_alignment, delta.normalized().dot(wind.normalized()))
		maximum_speed = maxf(maximum_speed, delta.length() / .01)
	assert(minimum_alignment > .98 and maximum_speed < 50)
	var around_turn := weather.clouds.offset_at(85.001) - weather.clouds.offset_at(84.999)
	assert(around_turn.length() < .1, "Weather turn cannot teleport clouds")
	# Coarse front fields drive local liquid/snow rates, with an independent
	# interpolation/threshold check at every hydrological cell.
	var sample := weather.sample(climate, 180.0)
	var fields := ForestWeatherFront.grid(sample, CONFIG.extent)
	var actual := weather.clouds.grid(sample)
	var maximum_error := 0.0
	var liquid_sum := 0.0
	for z in CONFIG.water_resolution:
		for x in CONFIG.water_resolution:
			var pos := (Vector2(x, z) + Vector2.ONE * .5) * CONFIG.extent / CONFIG.water_resolution
			var cover := ForestWeatherFront.value(fields.cloud_cover, pos, CONFIG.extent)
			var potential := ForestWeatherFront.value(
				fields.precipitation_potential_m_s, pos, CONFIG.extent
			)
			var density: float = weather.clouds.native.sample_density(
				pos.x, pos.y, CONFIG.extent, sample.cloud_offset_m
			)
			var threshold := .69 - .32 * cover
			var expected := potential * smoothstep(threshold + .10, threshold + .24, density)
			if ForestWeatherFront.value(fields.temperature_c, pos, CONFIG.extent) <= 0:
				expected = 0
			var value: float = actual.rates[z * CONFIG.water_resolution + x]
			maximum_error = maxf(maximum_error, absf(value - expected))
			liquid_sum += value
	assert(maximum_error < 1e-10)
	assert(absf(liquid_sum / actual.rates.size() - actual.mean_liquid_m_s) < 1e-12)
	var winter_weather := ForestWeather.new(CONFIG)
	winter_weather.toggle(false)
	var winter_climate := winter_weather.sample(ForestClimate.sample(0, 15))
	var snow_mask := winter_weather.clouds.weights(winter_climate)
	var liquid_mask := winter_weather.clouds.weights(winter_climate, {}, true)
	assert(snow_mask.count(0) < snow_mask.size(), "Snow particles retain cloud cores")
	assert(liquid_mask.count(0) == liquid_mask.size(), "Snow cannot create liquid rain ripples")
	var calm := stand()
	var brief := stand()
	var storm := stand()
	var strong := stand(45)
	var snags := stand()
	var calm_snags := stand()
	for i in snags.species.size():
		snags._die(i)
		calm_snags._die(i)
	var forcing := climate.duplicate()
	forcing.wind_m_s = 35.0
	forcing.wind_direction = Vector2.from_angle(.6)
	var before := storm._totals()
	storm._windfall(120 * CONFIG.year_speed_multiplier, forcing, 120)
	snags._windfall(120 * CONFIG.year_speed_multiplier, forcing, 120)
	brief._windfall(CONFIG.year_speed_multiplier, forcing, 1)
	strong._windfall(120 * CONFIG.year_speed_multiplier, forcing, 120)
	forcing.wind_m_s = 12.0
	calm._windfall(120 * CONFIG.year_speed_multiplier, forcing, 120)
	calm_snags._windfall(120 * CONFIG.year_speed_multiplier, forcing, 120)
	assert(snags.fallen.count(1) > storm.fallen.count(1))
	assert(
		snags.fallen.count(1) > calm_snags.fallen.count(1),
		"Hurricane increases snag fall beyond background decay"
	)
	var count := storm.fallen.count(1)
	assert(count > 15 and count < 200, "Hurricane-scale gust produces selective windthrow")
	assert(calm.fallen.count(1) == 0 and strong.fallen.count(1) == 0)
	assert(brief.fallen.count(1) < count, "Exposure duration matters in SI seconds")
	var after := storm._totals()
	for e in 3:
		assert(absf(before[e] - after[e]) < 1e-8, "Windthrow conserves C/N/P")
	for i in storm.species.size():
		if storm.fallen[i]:
			assert(not storm.alive[i] and storm.dead_c[i] > 0)
			assert(absf(storm.yaw[i] - .6) < 1e-5)
	var d: ForestPlantDefinition = CONFIG.plants[0]
	assert(ForestTrees.critical_gust(d, climate, .8) < ForestTrees.critical_gust(d, climate, 0))
	assert(
		ForestTrees.critical_gust(d, climate, 0, 1.5) < ForestTrees.critical_gust(d, climate, 0, .7)
	)
	var saved := storm.snapshot()
	var copy := stand()
	assert(copy.restore(saved))
	var malformed := saved.duplicate(true)
	malformed.configuration = 4
	assert(not copy.restore(malformed) and copy.snapshot() == saved)
	var legacy := saved.duplicate(true)
	for traits in legacy.configuration.traits:
		traits.erase("wind_resistance_m_s")
	assert(copy.restore(legacy), "Existing tree saves migrate with new resource resistance")
	var old_weather := weather.snapshot()
	old_weather.version = 2
	old_weather.cloud_configuration[0] = 1
	old_weather.cloud_configuration[5] = Vector2(1.2, .45)
	old_weather.cloud_configuration.resize(6)
	assert(weather.restore(old_weather), "Fixed-transport weather save migrates")
	forcing.wind_m_s = 35.0
	storm._windfall(60 * CONFIG.year_speed_multiplier, forcing, 60)
	copy._windfall(60 * CONFIG.year_speed_multiplier, forcing, 60)
	assert(storm.snapshot() == copy.snapshot(), "Windthrow RNG survives save / restore")
	var timings := []
	for i in 20:
		var started := Time.get_ticks_usec()
		weather.sample(climate, 120 + i * .5)
		timings.append(Time.get_ticks_usec() - started)
	timings.sort()
	var report := {
		"passed": true,
		"front_temperature_range_c": spatial_range,
		"cloud_min_alignment": minimum_alignment,
		"cloud_max_speed_m_s": maximum_speed,
		"rain_oracle_error_m_s": maximum_error,
		"storm_fallen_of_240": count,
		"brief_fallen": brief.fallen.count(1),
		"strong_fallen": strong.fallen.count(1),
		"dead_storm_fallen": snags.fallen.count(1),
		"dead_calm_fallen": calm_snags.fallen.count(1),
		"cnp_conserved": true,
		"exact_save_continuation": true,
		"sample_median_usec": timings[10]
	}
	FileAccess.open("res://artifacts/fronts-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "\t")
	)
	print("FRONTS_CHECK ", JSON.stringify(report))
	quit()
