extends SceneTree
const CONFIG = preload("res://data/forest.tres")


func chamber(saturation: float, surface := 0.0) -> Dictionary:
	var settings: ForestSettings = CONFIG.duplicate(true)
	settings.water_resolution = 4
	settings.tree_attempts = 48
	settings.water_step = 5
	settings.start_day = 200
	settings.headwater_m3_s = 0
	settings.headwater_length = 512
	settings.headwater_width = 512
	settings.evaporation_m_s = 0
	settings.soil_profile.saturated_conductivity_m_s = 0
	settings.soil_profile.root_conductivity_m_s = 0
	settings.soil_profile.groundwater_enabled = false
	settings.validate()
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	var zero := PackedFloat64Array()
	var depth := PackedFloat64Array()
	var soil := PackedFloat64Array()
	zero.resize(16)
	depth.resize(16)
	depth.fill(surface)
	soil.resize(16)
	soil.fill(saturation)
	# Controlled closed homogeneous chamber, NOT an annual valley simulation.
	assert(
		water.native.configure(
			4,
			128,
			{
				"source_m3_s": 0.0,
				"rain_m_s": 0.0,
				"max_step_s": 5.0,
				"outlet": false,
				"evaporation_m_s": 0.0,
				"conductivity_m_s": 0.0,
				"root_conductivity_m_s": 0.0
			},
			zero,
			depth,
			soil,
			PackedInt32Array()
		)
	)
	water.sync_fields()
	var trees := ForestTrees.new(land)
	assert(trees.species.size() > 10)
	return {"water": water, "trees": trees, "settings": settings}


func tick(world: Dictionary, days: float) -> void:
	world.water.step(days * ForestClimate.DAY_S)
	world.trees.step(days * ForestClimate.DAY_S, world.water)
	assert(absf(world.water.balance_error()) < 1e-5)


func _initialize() -> void:
	_check_split_clocks()
	_check_presentation_clock()
	var base: ForestSettings = CONFIG
	var deciduous: ForestPlantDefinition = base.plants[1]
	var evergreen: ForestPlantDefinition = base.plants[0]
	assert(deciduous.deciduous and not evergreen.deciduous)
	assert(ForestClimate.leaves(deciduous, 20) == 0)
	assert(ForestClimate.leaves(deciduous, 200) == 1)
	assert(ForestClimate.autumn(deciduous, 275) == 1)
	assert(ForestClimate.leaves(evergreen, 20) == 1)
	assert(ForestClimate.sample(0, 200).daylight_h > ForestClimate.sample(0, 20).daylight_h)
	assert(absf(ForestClimate.sample(ForestClimate.YEAR_S, 135).day - 135) < 1e-9)
	var wet := chamber(1)
	var dry := chamber(0)
	var wet_initial: PackedFloat64Array = wet.trees.size.duplicate()
	var dry_initial: PackedFloat64Array = dry.trees.size.duplicate()
	tick(wet, 1)
	tick(dry, 1)
	var growth := 0.0
	for i in wet.trees.size.size():
		growth += wet.trees.size[i] - wet_initial[i]
	assert(growth > 0, "warm wet trees grow")
	assert(dry.trees.size == dry_initial, "no available root water is a no-growth null")
	assert(wet.trees.transpired_m3 > 0 and dry.trees.transpired_m3 == 0)
	assert(absf(wet.trees.transpired_m3 - float(wet.water.stats.transpired_m3)) < 1e-7)
	assert(wet.trees.root_cells.size() == wet.trees.species.size())
	# Save/continue both coupled states, including stress, age and RNG.
	var hydro_state: Dictionary = wet.water.native.snapshot()
	var tree_state: Dictionary = wet.trees.snapshot()
	var resumed := chamber(1)
	assert(resumed.water.native.restore(hydro_state))
	resumed.water.sync_fields()
	assert(resumed.trees.restore(tree_state))
	tick(wet, .01)
	tick(resumed, .01)
	assert(wet.trees.snapshot() == resumed.trees.snapshot())
	assert(wet.water.native.snapshot() == resumed.water.native.snapshot())
	var corrupt: Dictionary = wet.trees.snapshot()
	corrupt.size[0] = -1.0
	var before: Dictionary = wet.trees.snapshot()
	assert(not wet.trees.restore(corrupt) and wet.trees.snapshot() == before)
	# Resource traits, not species-name branches. Add a third identity unchanged.
	var extra: ForestPlantDefinition = wet.settings.plants[1].duplicate(true)
	extra.species_id = &"new_deciduous"
	extra.validate()
	assert(ForestClimate.leaves(extra, 20) == 0)
	# Constant winter chamber has no growth or deciduous leaf demand.
	var winter := chamber(1)
	winter.settings.start_day = 20
	var winter_initial: PackedFloat64Array = winter.trees.size.duplicate()
	tick(winter, 1)
	assert(winter.trees.size == winter_initial and winter.trees.transpired_m3 == 0)
	# Light control: two co-located crowns, shorter one receives less light.
	wet.trees.positions[1] = wet.trees.positions[0]
	wet.trees.size[0] = 20.0 / wet.settings.plants[wet.trees.species[0]].reference_height_m
	wet.trees.size[1] = 2.0 / wet.settings.plants[wet.trees.species[1]].reference_height_m
	wet.trees._update_light()
	assert(wet.trees.light[0] > wet.trees.light[1])
	_check_canopy_definition(wet.trees)
	var recovery := chamber(1)
	recovery.trees.stress.fill(.5)
	tick(recovery, 1)
	assert(recovery.trees.stress[0] < .5)
	var flooded := chamber(1, 1)
	tick(flooded, 80)
	assert(flooded.trees.deaths > 0 and flooded.trees.alive.count(0) == flooded.trees.deaths)
	# Permanent dry forcing through a warm 50-day assay accumulates stress.
	# For mortality, use a controlled flood assay; winter reduces drought demand.
	tick(dry, 20)
	assert(dry.trees.stress[0] > 0)
	var report := {
		"passed": true,
		"tree_count": wet.trees.species.size(),
		"wet_growth_sum_scale": growth,
		"wet_transpired_m3": wet.trees.transpired_m3,
		"dry_no_growth": true,
		"winter_no_growth": true,
		"deciduous_leaf_cycle": true,
		"evergreen_winter_foliage": true,
		"solar_and_biological_multipliers_from_water": true,
		"split_clock_partition_and_resume": true,
		"shared_speed_scales_calendar_and_biological_age": true,
		"uptake_uses_hydrological_seconds": true,
		"solar_noon_midnight_and_horizon": true,
		"solar_presentation_continuous_read_only_and_bounded": true,
		"shorter_crown_shaded": true,
		"flood_deaths": flooded.trees.deaths,
		"coupled_save_resume_exact": true,
		"corrupt_tree_state_rejected": true,
		"boundary": "Controlled coarse chambers, not an annual full-valley validation"
	}
	var file := FileAccess.open("res://artifacts/ecology-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("ECOLOGY_CHECK ", JSON.stringify(report))
	quit()


func _check_canopy_definition(trees: ForestTrees) -> void:
	# Definition-derived checker, not another sorting algorithm.
	for i in trees.species.size():
		var column := Vector2i(int(trees.positions[i].x / 16), int(trees.positions[i].z / 16))
		var height := trees._height(i)
		var expected_cover := 0.0
		for j in trees.species.size():
			var other := Vector2i(int(trees.positions[j].x / 16), int(trees.positions[j].z / 16))
			if trees.alive[j] and other == column and trees._height(j) > height:
				var definition: ForestPlantDefinition = trees.land.settings.plants[trees.species[j]]
				expected_cover += PI * pow(definition.crown_radius_m * trees.size[j], 2) / 256.0
		assert(absf(trees.light[i] - exp(-expected_cover)) < 1e-12)


func _drain_clock(clock: ForestEcologyClock) -> void:
	while clock.step():
		pass


func _check_presentation_clock() -> void:
	var settings: ForestSettings = CONFIG.duplicate(true)
	var clock := ForestEcologyClock.new(settings)
	clock.request(1.0)
	_drain_clock(clock)
	var previous: float = clock.presentation_sample().hour
	var previous_fixed: float = clock.sample().hour
	var fixed_stalls := 0
	# A full configured day, including midnight; criterion derives from the clock definition.
	var frames := roundi(settings.day_water_s() / .025)
	var hour_per_frame := .025 * settings.day_speed_multiplier / 3600.0
	for frame in frames:
		clock.request(.025)
		_drain_clock(clock)
		var before := clock.snapshot()
		var visible := clock.presentation_sample()
		var delta := fposmod(visible.hour - previous, 24.0)
		assert(
			absf(delta - hour_per_frame) < 1e-9,
			"no plateaus or tick-boundary jumps, even at midnight"
		)
		assert(clock.snapshot() == before, "display sampling cannot advance ecology")
		if clock.sample().hour == previous_fixed:
			fixed_stalls += 1
		previous = visible.hour
		previous_fixed = clock.sample().hour
	assert(
		fixed_stalls > frames * .8, "old fixed-step sampling fails the same smoothness criterion"
	)
	var frozen := clock.presentation_sample()
	var resumed := ForestEcologyClock.new(settings)
	assert(resumed.restore(clock.snapshot()))
	for frame in 20:
		assert(clock.presentation_sample() == frozen, "no requested time means a frozen display")
		assert(resumed.presentation_sample() == frozen, "partial phase survives restore exactly")
	# Unserved time is not permission for the view to run ahead of the simulation.
	clock.request(3.0)
	var debt_before := clock.snapshot()
	assert(clock.presentation_sample() == clock.sample(), "display is bounded by completed time")
	assert(clock.snapshot() == debt_before)
	var loaded_phase := clock.presentation_sample()
	assert(clock.cancel_excess_request() > 0)
	assert(clock.presentation_sample() == loaded_phase, "speed changes cannot rewind the sky")
	var fresh := ForestEcologyClock.new(settings)
	fresh.request(.25)
	assert(fresh.presentation_sample() == fresh.sample(), "startup never displays negative time")


func _check_split_clocks() -> void:
	var settings: ForestSettings = CONFIG.duplicate(true)
	var a := ForestEcologyClock.new(settings)
	var b := ForestEcologyClock.new(settings)
	a.request(settings.day_water_s() + .125)
	_drain_clock(a)
	for i in roundi((settings.day_water_s() + .125) / .125):
		b.request(.125)
		_drain_clock(b)
	assert(a.snapshot() == b.snapshot(), "fixed ecological ticks ignore render partition")
	assert(a.sample().hour == settings.start_hour, "one visible day returns to the same hour")
	assert(absf(a.sample().day - settings.start_day - 36.5) < 1e-8)
	var resumed := ForestEcologyClock.new(settings)
	assert(resumed.restore(a.snapshot()))
	for clock in [a, resumed]:
		clock.request(settings.year_water_s() - settings.day_water_s())
		_drain_clock(clock)
	assert(a.snapshot() == resumed.snapshot() and a.sample() == resumed.sample())
	assert(a.sample().year == 2 and absf(a.sample().day - settings.start_day) < 1e-8)
	var before := a.snapshot()
	var corrupt := before.duplicate(true)
	corrupt.ticks = -1
	assert(not a.restore(corrupt) and a.snapshot() == before)
	var other: ForestSettings = settings.duplicate(true)
	other.year_speed_multiplier *= .5
	assert(not ForestEcologyClock.new(other).restore(before), "changed clock periods rejected")
	var legacy := before.duplicate(true)
	legacy.version = 1
	assert(not a.restore(legacy), "old independent wall-clock semantics are not silently restored")
	_check_shared_speed()
	# Independent solar geometry controls: noon > horizon > midnight; sunrise is z=0.
	var noon := ForestClimate.sample(0, 80, 60, 12)
	var midnight := ForestClimate.sample(0, 80, 60, 0)
	var sunrise := ForestClimate.sample(0, 80, 60, 12 - noon.daylight_h / 2)
	assert(absf(noon.sun_elevation - deg_to_rad(30)) < 1e-8)
	assert(midnight.sun_elevation < 0 and absf(sunrise.sun_elevation) < 1e-8)
	assert(ForestClimate.sample(0, 200, 60, 12).daylight_h > noon.daylight_h)
	# Unit-level uptake control: prescribe IDENTICAL biological dt and 10x water
	# dt directly to the tree model. This is not the scene's shared speed control.
	var slow := chamber(1)
	var fast := chamber(1)
	var age_before: float = slow.trees.age_years[0]
	var size_before: PackedFloat64Array = slow.trees.size.duplicate()
	var clock := ForestEcologyClock.new(slow.settings)
	clock.request(slow.settings.year_water_s())
	while clock.step():
		for world in [slow, fast]:
			var water_dt := .1 if world == slow else 1.0
			world.water.step(water_dt)
			world.trees.step(clock.biological_step_s(), world.water, water_dt)
	assert(absf(slow.trees.age_years[0] - age_before - 1) < 1e-8)
	assert(slow.trees.age_years == fast.trees.age_years and slow.trees.size == fast.trees.size)
	assert(slow.trees.size != size_before, "a compressed year really grows the trees")
	assert(absf(fast.trees.transpired_m3 / slow.trees.transpired_m3 - 10) < 1e-8)
	for world in [slow, fast]:
		assert(absf(world.water.balance_error()) < 1e-5)
		assert(absf(world.water.clock - world.trees.water_elapsed_s) < 1e-8)
	# Save/resume all three clocks, not just hydrology. Partial fixed-step debt survives.
	var hydro: Dictionary = slow.water.native.snapshot()
	var trees: Dictionary = slow.trees.snapshot()
	clock.request(.125)
	var clock_copy := ForestEcologyClock.new(slow.settings)
	assert(clock_copy.restore(clock.snapshot()))
	var copy := chamber(1)
	assert(copy.water.native.restore(hydro))
	copy.water.sync_fields()
	assert(copy.trees.restore(trees))
	for pair in [[slow, clock], [copy, clock_copy]]:
		var continued_clock: ForestEcologyClock = pair[1]
		continued_clock.request(.375)
		while continued_clock.step():
			pair[0].water.step(.25)
			pair[0].trees.step(continued_clock.biological_step_s(), pair[0].water, .25)
	assert(slow.trees.snapshot() == copy.trees.snapshot())
	assert(slow.water.native.snapshot() == copy.water.native.snapshot())
	assert(clock.snapshot() == clock_copy.snapshot())
	# A zero-water tick cannot falsely cure drought.
	var dry := chamber(0)
	dry.water.step(1)
	dry.trees.step(ForestClimate.DAY_S, dry.water, 1)
	var dry_stress: float = dry.trees.stress[0]
	dry.trees.step(ForestClimate.DAY_S, dry.water, 0)
	assert(dry.trees.stress[0] > dry_stress and dry.trees.transpired_m3 == 0)


func _check_shared_speed() -> void:
	var slow := chamber(1)
	var fast := chamber(1)
	var slow_clock := ForestEcologyClock.new(slow.settings)
	var fast_clock := ForestEcologyClock.new(fast.settings)
	var initial_age: float = slow.trees.age_years[0]
	for frame in 20:
		for pair in [[slow, slow_clock, 1.0], [fast, fast_clock, 8.0]]:
			var clock: ForestEcologyClock = pair[1]
			clock.request(.025 * pair[2])
			while clock.step():
				pair[0].water.step(pair[0].settings.ecology_step_s)
				pair[0].trees.step(
					clock.biological_step_s(), pair[0].water, pair[0].settings.ecology_step_s
				)
	assert(fast.water.clock == slow.water.clock * 8)
	assert(slow_clock.elapsed_s == slow.water.clock and fast_clock.elapsed_s == fast.water.clock)
	var age_ratio: float = (
		(fast.trees.age_years[0] - initial_age) / (slow.trees.age_years[0] - initial_age)
	)
	assert(absf(age_ratio - 8) < 1e-8)
	var slow_hour: float = slow_clock.sample().hour - slow.settings.start_hour
	var fast_hour: float = fast_clock.sample().hour - fast.settings.start_hour
	assert(absf(fast_hour / slow_hour - 8) < 1e-8)
	assert(
		absf(fast.trees.elapsed_s - fast.water.clock * fast.settings.year_speed_multiplier) < 1e-8
	)
	var custom: ForestSettings = slow.settings.duplicate(true)
	custom.day_speed_multiplier *= 2.0
	custom.year_speed_multiplier *= .25
	custom.validate()
	var custom_clock := ForestEcologyClock.new(custom)
	custom_clock.request(slow.water.clock)
	_drain_clock(custom_clock)
	assert(absf(custom_clock.sample().hour - custom.start_hour - slow_hour * 2.0) < 1e-8)
	assert(custom_clock.biological_step_s() == slow_clock.biological_step_s() * .25)
