extends "res://tools/check_weather_habitat.gd"


func _run() -> void:
	var w := fixture(true)
	var herb: ForestPlantDefinition = load("res://data/plants/wood_sorrel.tres").duplicate(true)
	w.settings.plants.append(herb)
	var point: Vector3 = w.trees.positions[0]
	w.trees._append(1, point, 1, 2)
	var plant_id: int = w.trees.species.size() - 1
	var initial := budget(w)
	var stock: float = w.trees.biomass_c[plant_id]
	var source_soil: float = w.soil.metrics().carbon_kg
	w.animals.path_history[0] = {
		"times": PackedFloat64Array([0, 1000]),
		"points": PackedVector3Array([point - Vector3(5, 0, 0), point + Vector3(5, 0, 0)])
	}
	w.animals.ticks = 1
	var climate := ForestClimate.sample(0, 150)
	w.habitat._record_traffic(0, climate)
	assert(w.habitat.traffic.count(0) == w.habitat.traffic.size(), "Flight cannot trample ground")
	w.animals.definitions[0].flight_height_m = 0
	w.animals.ticks += 1
	w.animals.path_history[0].points = PackedVector3Array([point, point])
	w.habitat._record_traffic(0, climate)
	assert(
		w.habitat.traffic.count(0) == w.habitat.traffic.size(),
		"Stationary body cannot create trails"
	)
	w.animals.ticks += 1
	w.animals.path_history[0].points = PackedVector3Array(
		[point - Vector3(5, 0, 0), point + Vector3(5, 0, 0)]
	)
	w.habitat._record_traffic(0, climate)
	var k: int = w.trees.root_cells[plant_id]
	assert(w.habitat.traffic[k] > 0 and w.trees.biomass_c[plant_id] < stock)
	assert(w.soil.metrics().carbon_kg > source_soil, "Crushed tissue returns to actual soil")
	same_budget(initial, budget(w))
	var pressure: float = w.habitat.traffic[k]
	var after_c: float = w.trees.biomass_c[plant_id]
	w.habitat._record_traffic(0, climate)
	assert(
		w.habitat.traffic[k] == pressure and w.trees.biomass_c[plant_id] == after_c,
		"No duplicate path consumption"
	)
	w.habitat._record_traffic(ForestClimate.DAY_S * 45, climate)
	assert(
		w.habitat.traffic[k] < pressure and w.trees.biomass_c[plant_id] == after_c,
		"Trail fades, but no invented regrowth"
	)
	var saved: Dictionary = w.habitat.snapshot()
	var broken := saved.duplicate(true)
	broken.traffic[k] = NAN
	assert(not w.habitat.restore(broken) and w.habitat.snapshot() == saved)
	assert(w.habitat.restore(saved))
	# Real finite seed bank establishes near a real dead trunk.
	var nurse := fixture()
	var d: ForestPlantDefinition = nurse.settings.plants[0]
	d.nurse_log_affinity = 1
	d.dispersal_m = 15
	d.germination_fraction = 1
	d.recruitment_light = 0
	var seed: float = d.seed_cost_kg_c * 30
	nurse.trees.biomass_c[0] -= seed
	nurse.trees.biomass_n[0] -= seed / d.cn_ratio
	nurse.trees.biomass_p[0] -= seed / d.cp_ratio
	nurse.trees.seed_c[0] += seed
	nurse.trees.seed_n[0] += seed / d.cn_ratio
	nurse.trees.seed_p[0] += seed / d.cp_ratio
	nurse.trees._die(1)
	nurse.trees.fallen[1] = 1
	nurse.trees.yaw[1] = 0
	var before := budget(nurse)
	var near_count := 0
	var null_near := 0
	var log_start: Vector3 = nurse.trees.positions[1]
	var log_end: Vector3 = log_start + Vector3.RIGHT * nurse.trees._height(1)
	for i in 100:
		var candidate: Vector3 = nurse.trees._seed_candidate(0, d, PackedInt32Array([1]))
		assert(
			(
				(
					Vector2(
						candidate.x - nurse.trees.positions[0].x,
						candidate.z - nurse.trees.positions[0].z
					)
					. length()
				)
				<= d.dispersal_m
			)
		)
		if (
			Geometry3D.get_closest_point_to_segment(candidate, log_start, log_end).distance_to(
				candidate
			)
			< 1.5
		):
			near_count += 1
		var control: Vector3 = nurse.trees._seed_candidate(0, d, PackedInt32Array())
		if (
			Geometry3D.get_closest_point_to_segment(control, log_start, log_end).distance_to(
				control
			)
			< 1.5
		):
			null_near += 1
	assert(near_count > 95 and null_near < 30, "Without a log there is no nurse-site bias")
	for i in 30:
		nurse.trees._recruit(ForestClimate.YEAR_S, climate, nurse.water, nurse.trees.species.size())
	assert(nurse.trees.recruits > 0 and nurse.trees.seed_c[0] < seed)
	assert(nurse.trees.recruits <= 30, "No more recruits than funded seeds")
	same_budget(before, budget(nurse))
	var empty := fixture()
	empty.settings.plants[0].nurse_log_affinity = 1
	empty.trees._die(1)
	empty.trees.fallen[1] = 1
	empty.trees._recruit(ForestClimate.YEAR_S, climate, empty.water, 2)
	assert(empty.trees.recruits == 0, "A log does not create seed carbon")
	var conifer: ForestPlantDefinition = load("res://data/plants/spruce.tres")
	var winter := ForestClimate.sample(0, 15)
	winter.wind_m_s = 8.0
	winter.snow_water_m = 0.0
	assert(ForestTrees.snow_load_index(conifer, winter) == 0)
	assert(ForestTrees.windfall_rate(conifer, winter, 0) == 0)
	winter.snow_water_m = .02
	assert(ForestTrees.snow_load_index(conifer, winter) > .9)
	assert(ForestTrees.windfall_rate(conifer, winter, 0) > 0)
	var snowy := fixture()
	snowy.settings.plants[0].deciduous = false
	var cnp := budget(snowy)
	snowy.trees._windfall(ForestClimate.YEAR_S * 100, winter)  # Forced rare-event assay, not a real forecast.
	assert(snowy.trees.fallen.count(1) == 2)
	same_budget(cnp, budget(snowy))
	var report := {
		"passed": true,
		"real_paths_trample_finite_cover": true,
		"flying_stationary_duplicate_controls": true,
		"trail_fades_without_free_regrowth": true,
		"nurse_log_bias_and_funded_recruits": true,
		"no_seed_no_recruit_control": true,
		"snow_load_and_calm_windfall": true,
		"cnp_conserved": true,
		"corrupt_traffic_atomic": true,
		"boundary":
		"Scenario coefficients and grid-scale trail, not calibrated trampling or branch mechanics"
	}
	FileAccess.open("res://artifacts/place-memory-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("PLACE_MEMORY_CHECK ", JSON.stringify(report))
	quit()
