extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func chamber(
	poor := false, scarce := false, plant_path := "res://data/plants/wood_sorrel.tres"
) -> Dictionary:
	var settings: ForestSettings = CONFIG.duplicate(true)
	settings.water_resolution = 4
	settings.tree_attempts = 64
	settings.start_day = 180
	settings.fungi_resolution = 16
	settings.fungi_cell_m = .25
	settings.fungi_plot_centers = PackedVector2Array([Vector2(.375, .557)])
	settings.fungi_initial_age_s = 0
	settings.headwater_m3_s = 0
	settings.headwater_length = 512
	settings.headwater_width = 512
	settings.evaporation_m_s = 0
	settings.soil_profile.saturated_conductivity_m_s = 0
	settings.soil_profile.root_conductivity_m_s = 0
	settings.soil_profile.groundwater_enabled = false
	# Explicit productive herb assay. A fresh identity uses the identical model.
	var herb: ForestPlantDefinition = load(plant_path).duplicate(true)
	herb.species_id = &"controlled_new_herb"
	herb.initial_age_years = Vector2(.3, .3)
	herb.mature_age_years = .1
	herb.reproduction_per_year = 2
	herb.germination_fraction = 1
	herb.seed_cost_kg_c = .00001
	herb.dispersal_m = 12
	herb.minimum_channel_distance = 0
	herb.deciduous = false
	herb.edible_fraction = .25
	herb.lifespan_years = 5
	herb.life_cycle = &"perennial"
	settings.plants = [herb]
	settings.validate()
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	var zeros := PackedFloat64Array()
	zeros.resize(16)
	var wet := zeros.duplicate()
	wet.fill(.7)
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
			zeros,
			zeros,
			wet,
			PackedInt32Array()
		)
	)
	water.sync_fields()
	var soil := ForestSoil.new(water)
	if poor:
		assert(soil.native.configure(4, 128, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO))
	if scarce:
		assert(
			soil.native.configure(
				4, 128, Vector3(2, 0, 0), Vector3(0, .02, .002), Vector3(.05, 0, 0)
			)
		)
	var plants := ForestTrees.new(land, soil)
	var fungi := ForestFungi.new(water, soil)
	var cover := ForestGroundcover.new(water)
	cover.bind_plants(plants)
	return {
		"land": land, "water": water, "soil": soil, "plants": plants, "fungi": fungi, "cover": cover
	}


func tick(w: Dictionary, days: float, reverse := false) -> void:
	var dt := days * ForestClimate.DAY_S
	w.water.step(.5)
	w.soil.step(dt, w.water)
	if reverse:
		w.fungi.step(dt, w.water, ForestClimate.sample(w.plants.elapsed_s, 180))
		w.plants.step(dt, w.water, .5)
	else:
		w.plants.step(dt, w.water, .5)
		w.fungi.step(dt, w.water, ForestClimate.sample(w.plants.elapsed_s - dt, 180))
	w.cover.step(dt, w.water)


func totals(w: Dictionary) -> PackedFloat64Array:
	var t := PackedFloat64Array([0.0, 0.0, 0.0])
	for model in [w.soil, w.plants, w.fungi]:
		var m: Dictionary = model.metrics()
		t[0] += m.carbon_kg
		t[1] += m.nitrogen_kg
		t[2] += m.phosphorus_kg
	return t


func _initialize() -> void:
	var w := chamber()
	var initial := totals(w)
	var base_count: int = w.plants.species.size()
	for k in 12:
		tick(w, 5)
	assert(
		w.plants.recruits > 0 and w.plants.species.size() > base_count,
		"finite seeds produce real appended individuals"
	)
	var m: Dictionary = w.plants.metrics()
	var final := totals(w)
	var respiration: float = w.soil.metrics().respired_kg_c + w.fungi.metrics().respired_kg_c
	assert(absf(final[0] + respiration - initial[0] - m.photosynthesized_kg_c) < 1e-7)
	assert(
		absf(final[1] - initial[1]) < 1e-7 and absf(final[2] - initial[2]) < 1e-7,
		"closed combined N/P ledger"
	)
	assert(
		(
			absf(m.carbon_error_kg) < 1e-9
			and absf(m.nitrogen_error_kg) < 1e-9
			and absf(m.phosphorus_error_kg) < 1e-9
		)
	)
	var stable_id := 0
	var before_c: float = w.plants.biomass_c[stable_id]
	var meal: Vector3 = w.plants.harvest(stable_id, 999)
	assert(
		(
			meal.x > 0
			and meal.x < before_c
			and absf(before_c - w.plants.biomass_c[stable_id] - meal.x) < 1e-12
		)
	)
	assert(w.plants.species.size() > base_count and w.plants.inspect(stable_id).id == stable_id)
	w.soil.deposit(w.plants.positions[stable_id], meal, true)
	# An animal may return litter AFTER the fungal tick. Checkpoints must
	# project current authoritative soil, not the fungus' stale solver mirrors.
	var fungal_center: Vector2 = w.fungi.observation_center()
	w.soil.deposit_elements(Vector3(fungal_center.x, 0, fungal_center.y), .012, .0008, .00008)
	var soil_before_observation: Dictionary = w.soil.snapshot()
	var fungal_after_late_deposit: Dictionary = w.fungi.snapshot()
	assert(
		w.soil.snapshot() == soil_before_observation, "fungal checkpoint is a read-only projection"
	)
	# Save/continue includes recruits and the fine-grid authoritative soil.
	var saved := {
		"water": w.water.native.snapshot(),
		"soil": soil_before_observation,
		"plants": w.plants.snapshot(),
		"fungi": fungal_after_late_deposit
	}
	var resumed := chamber()
	assert(resumed.water.native.restore(saved.water))
	resumed.water.sync_fields()
	assert(resumed.soil.restore(saved.soil))
	assert(resumed.plants.restore(saved.plants))
	assert(resumed.fungi.restore(saved.fungi))
	assert(
		resumed.fungi.snapshot() == saved.fungi,
		"late soil deposit survives immediate fungal snapshot/restore exactly"
	)
	for k in 3:
		tick(w, 1)
		tick(resumed, 1)
	assert(
		(
			w.soil.snapshot() == resumed.soil.snapshot()
			and w.plants.snapshot() == resumed.plants.snapshot()
			and w.fungi.snapshot() == resumed.fungi.snapshot()
		),
		"exact continued recruited world"
	)
	var bad: Dictionary = w.plants.snapshot()
	bad.biomass_n[0] = -1
	var before: Dictionary = w.plants.snapshot()
	assert(not w.plants.restore(bad) and w.plants.snapshot() == before)
	var soil_bad: Dictionary = w.soil.snapshot()
	soil_bad.patches[0].organic_c[0] = -1
	var soil_before: Dictionary = w.soil.snapshot()
	assert(not w.soil.restore(soil_bad) and w.soil.snapshot() == soil_before)
	var plants_before: Dictionary = w.plants.snapshot()
	var cover_before: PackedFloat64Array = w.cover.biomass.duplicate()
	w.cover.refresh()
	assert(
		w.plants.snapshot() == plants_before and w.cover.biomass == cover_before,
		"cover is read-only and cannot invent food"
	)
	var poor := chamber(true)
	# Later fungal mortality would correctly recycle its existing N/P into poor
	# soil, so the strict null is the first plant pass, before that recycling.
	tick(poor, 5)
	assert(
		poor.plants.photosynthesized_kg_c == 0,
		"zero N/P blocks new plant biomass through the same growth path"
	)
	_check_annual_season()
	_check_deadwood()
	_check_order_independence()
	var ordering := _check_guild_order()
	var file := FileAccess.open("res://artifacts/understory-check.json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"passed": true,
				"recruits": w.plants.recruits,
				"cnp_closed": true,
				"harvest_actual": true,
				"nutrient_null": true,
				"recruited_world_resume_exact": true,
				"fungal_late_soil_deposit_checkpoint_exact": true,
				"invalid_restore_atomic": true,
				"groundcover_read_only": true,
				"deadwood_finite_and_conservative": true,
				"annual_autumn_death_winter_bank_spring_recruitment": true,
				"annual_no_seed_null": true,
				"same_type_proportional_competition": true,
				"guild_order_relative_carbon_change": ordering,
				"boundary":
				"Prototype CNP stoichiometry and split guild allocation, not calibrated ecology"
			},
			"  "
		)
	)
	print("UNDERSTORY_CHECK passed recruits=", w.plants.recruits, " guild_order=", ordering)
	quit()


func _check_order_independence() -> void:
	var w := chamber()
	var positions := PackedVector3Array([Vector3(10, 0, 10), Vector3(10, 0, 10)])
	var before: Dictionary = w.soil.snapshot()
	var n := PackedFloat64Array([1e6, 2e6])
	var p := PackedFloat64Array([1e6, 2e6])
	var result: Dictionary = w.soil.withdraw_nutrients(positions, n, p)
	assert(absf(result.nitrogen[1] / result.nitrogen[0] - 2) < 1e-12)
	assert(w.soil.restore(before))
	var reversed: Dictionary = w.soil.withdraw_nutrients(
		positions, PackedFloat64Array([2e6, 1e6]), PackedFloat64Array([2e6, 1e6])
	)
	assert(
		(
			absf(result.nitrogen[0] - reversed.nitrogen[1]) < 1e-12
			and absf(result.phosphorus[1] - reversed.phosphorus[0]) < 1e-12
		),
		"identity order cannot steal resources"
	)


func _check_guild_order() -> Dictionary:
	# Purposefully co-locate consumers and deplete the fine-cell nutrient stock.
	# Compare the actual production step (.304 biological days) with a half step.
	var runs: Array[Dictionary] = []
	for run in 3:
		var w := chamber(false, true)
		var center: Vector2 = w.fungi.observation_center()
		w.plants.positions[0] = Vector3(center.x, 0, center.y)
		w.plants.root_cells[0] = int(center.y / 128) * 4 + int(center.x / 128)
		# Debit nutrients with the same public bounded withdrawal used by roots.
		w.soil.withdraw(Vector3(center.x, 0, center.y), Vector3(0, 999, 999))
		# A tiny finite replenishment creates competition without negative stores.
		w.soil.deposit_elements(Vector3(center.x, 0, center.y), 0, 1e-6, 1e-7, false)
		runs.append(w)
	var step_days := .5 * 52560.0 / ForestClimate.DAY_S
	for k in 60:
		tick(runs[0], step_days, false)
		tick(runs[1], step_days, true)
		tick(runs[2], step_days / 2, false)
		tick(runs[2], step_days / 2, false)
	var carbon := PackedFloat64Array()
	for w in runs:
		carbon.append(w.plants.metrics().carbon_kg + w.fungi.metrics().carbon_kg)
	var relative := absf(carbon[0] - carbon[1]) / maxf(carbon[0], 1e-12)
	var half_step := absf(carbon[0] - carbon[2]) / maxf(carbon[0], 1e-12)
	assert(
		relative < .05 and half_step < .05,
		"guild ordering and half-step changes remain bounded in the declared scarcity assay"
	)
	return {
		"reversed_order": relative,
		"half_step": half_step,
		"focal_plant_c_difference_kg":
		absf(runs[0].plants.biomass_c[0] - runs[1].plants.biomass_c[0]),
		"biological_step_days": step_days,
		"boundary": "Scarce shared fine-cell nutrient assay; not every long trajectory or community"
	}


func _check_deadwood() -> void:
	var w := chamber(false, false, "res://data/plants/spruce.tres")
	var initial := totals(w)
	var carbon: float = w.plants.biomass_c[0]
	var soil_carbon: float = w.soil.metrics().carbon_kg
	w.plants._die(0)
	assert(w.plants.dead_c[0] == carbon and w.plants.biomass_c[0] == 0 and w.plants.alive[0] == 0)
	assert(
		w.soil.metrics().carbon_kg == soil_carbon,
		"death retains a finite deadwood reserve, not immediate soil carbon"
	)
	w.plants._decay_dead(ForestClimate.YEAR_S, ForestClimate.sample(0, 180), w.water)
	var remaining: float = w.plants.dead_c[0]
	assert(remaining > 0 and remaining < carbon, "wood decays gradually, not all-or-nothing")
	assert(absf(w.soil.metrics().carbon_kg - soil_carbon - carbon + remaining) < 1e-8)
	var current := totals(w)
	for element in 3:
		assert(
			absf(current[element] - initial[element]) < 1e-7,
			"deadwood transfers conserve every element"
		)
	var resumed := chamber(false, false, "res://data/plants/spruce.tres")
	assert(resumed.soil.restore(w.soil.snapshot()) and resumed.plants.restore(w.plants.snapshot()))
	assert(resumed.plants.dead_c == w.plants.dead_c)
	for x in [w, resumed]:
		x.plants._decay_dead(ForestClimate.YEAR_S, ForestClimate.sample(0, 180), x.water)
	assert(
		(
			w.soil.snapshot() == resumed.soil.snapshot()
			and w.plants.snapshot() == resumed.plants.snapshot()
		),
		"deadwood continuation is exact"
	)


func _check_annual_season() -> void:
	var seeded := chamber(false, false, "res://data/plants/balsam.tres")
	var seedless := chamber(false, false, "res://data/plants/balsam.tres")
	for w in [seeded, seedless]:
		var definition: ForestPlantDefinition = w.land.settings.plants[0]
		definition.life_cycle = &"annual"
		definition.deciduous = true
		definition.leaf_on_day = 120
		definition.leaf_off_day = 240
		definition.leaf_transition_days = 15
	seedless.land.settings.plants[0].reproduction_per_year = 0
	# Start in summer, old enough to form finite seed reserves before autumn.
	for k in 8:
		for w in [seeded, seedless]:
			tick(w, 5)
	assert(
		(
			seeded.plants.metrics().seed_carbon_kg > 0
			and seeded.plants.inspect(0).stage == "семенная стадия"
		)
	)
	for k in 9:
		for w in [seeded, seedless]:
			tick(w, 5)
	assert(
		seeded.plants.alive.count(1) == 0 and seeded.plants.dead_c[0] > 0,
		"annual mothers and summer recruits die by phenological season end"
	)
	assert(
		seeded.plants.age_years[0] < 1 and seeded.plants.seed_c[0] > 0,
		"autumn death is seasonal, not a disguised one-year age cutoff"
	)
	var autumn_recruits: int = seeded.plants.recruits
	# 180 + 85 + 220 biological days reaches the next spring day120.
	for k in 22:
		for w in [seeded, seedless]:
			tick(w, 10)
	assert(
		(
			seeded.plants.alive.count(1) == 0
			and seeded.plants.recruits == autumn_recruits
			and seeded.plants.seed_c[0] > 0
		),
		"winter preserves a finite seed bank, never living annual stems"
	)
	for k in 10:
		for w in [seeded, seedless]:
			tick(w, 1)
	assert(
		seeded.plants.recruits > autumn_recruits and seeded.plants.alive.count(1) > 0,
		"old seed bank creates next spring's appended IDs"
	)
	assert(seeded.plants.alive[0] == 0, "spring recruits do not revive the dead mother ID")
	assert(
		seedless.plants.recruits == 0 and seedless.plants.metrics().seed_carbon_kg == 0,
		"same annual pipeline without seed production cannot recruit"
	)
