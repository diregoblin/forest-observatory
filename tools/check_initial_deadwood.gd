extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	var settings: ForestSettings = CONFIG.duplicate(true)
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	water.soil.fill(.65)
	var soil := ForestSoil.new(water)
	var trees := ForestTrees.new(land, soil)
	var control_settings: ForestSettings = settings.duplicate(true)
	control_settings.initial_fallen_fraction = 0
	var control := ForestTrees.new(ForestLandscape.new(control_settings), soil)
	assert(control.fallen.count(1) == 0, "Disabled seeding is the standing-forest null")
	assert(trees.positions == control.positions and trees.species == control.species)
	assert(trees.yaw == control.yaw and trees.rng.state == control.rng.state)
	var initial := trees._totals()
	var null_totals := control._totals()
	for e in 3:
		assert(absf(initial[e] - null_totals[e]) < 1e-8, "No free or lost initial C/N/P")
	var tree_count := 0
	var logs := []
	var quadrants := {}
	for id in trees.species.size():
		var d: ForestPlantDefinition = settings.plants[trees.species[id]]
		tree_count += int(d.growth_form == &"tree")
		if not trees.fallen[id]:
			assert(trees.alive[id] == 1)
			continue
		assert(d.growth_form == &"tree", "Herbs/shrubs must not become fallen trees")
		assert(trees.alive[id] == 0 and trees.biomass_c[id] == 0 and trees.leaf_carbon[id] == 0)
		assert(trees.dead_c[id] == control.biomass_c[id] and trees.dead_c[id] > 0)
		assert(trees.dead_n[id] == control.biomass_n[id])
		assert(trees.dead_p[id] == control.biomass_p[id])
		assert(trees.fallen_age_s[id] == 0)
		var pose := trees.fallen_transform(id)
		assert(pose.is_finite() and absf(pose.basis.y.normalized().y) < .7)
		assert(trees.inspect(id).details["Древесина"].begins_with("валежник"))
		var p := trees.positions[id]
		quadrants[Vector2i(int(p.x / (settings.extent * .5)), int(p.z / (settings.extent * .5)))] = true
		logs.append({"id": id, "species": str(d.species_id), "x": p.x, "z": p.z})
	assert(logs.size() == roundi(tree_count * settings.initial_fallen_fraction))
	assert(logs.size() > 0 and quadrants.size() == 4, "Default valley has scattered real logs")
	var saved := trees.snapshot()
	var resumed_water := ForestWatershed.new(land)
	resumed_water.soil.fill(.65)
	var resumed_soil := ForestSoil.new(resumed_water)
	var repeated := ForestTrees.new(land, resumed_soil)
	assert(repeated.snapshot() == saved, "Same seed reproduces initial stocks and logs")
	assert(repeated.restore(saved) and repeated.snapshot() == saved)
	# A pre-feature standing-world snapshot remains authoritative on load: no
	# second seeding pass and no incompatible configuration/version change.
	var standing_save := control.snapshot()
	assert(repeated.restore(standing_save) and repeated.fallen.count(1) == 0)
	assert(repeated.snapshot() == standing_save)
	assert(repeated.restore(saved))
	var soil_before := soil.metrics()
	var before := trees._totals()
	var climate := ForestClimate.sample(0, 200)
	trees._decay_dead(ForestClimate.DAY_S, climate, water)
	var after := trees._totals()
	var soil_after := soil.metrics()
	assert(after[0] < before[0], "Initial logs actually decompose")
	for e in 3:
		var key: String = ["carbon_kg", "nitrogen_kg", "phosphorus_kg"][e]
		assert(absf(before[e] - after[e] - (soil_after[key] - soil_before[key])) < 1e-6)
	# Exact continuation, including decayed stocks and geometry.
	assert(repeated.restore(trees.snapshot()))
	assert(resumed_soil.restore(soil.snapshot()))
	trees._decay_dead(ForestClimate.DAY_S, climate, water)
	repeated._decay_dead(ForestClimate.DAY_S, climate, resumed_water)
	assert(repeated.snapshot() == trees.snapshot())
	assert(resumed_soil.snapshot() == soil.snapshot())
	var report := {
		"passed": true,
		"tree_count": tree_count,
		"initial_logs": logs.size(),
		"fraction": settings.initial_fallen_fraction,
		"quadrants": quadrants.size(),
		"conservative": true,
		"deterministic": true,
		"standing_save_preserved": true,
		"decay_and_continuation": true,
		"logs": logs
	}
	FileAccess.open("res://artifacts/initial-deadwood-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("INITIAL_DEADWOOD ", JSON.stringify(report))
	quit()
