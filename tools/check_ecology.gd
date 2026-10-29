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
	wet.trees.size[0] = 1.4
	wet.trees.size[1] = .5
	wet.trees._update_light()
	assert(wet.trees.light[0] > wet.trees.light[1])
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
		"same_calendar_as_water": true,
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
