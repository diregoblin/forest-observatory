extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	call_deferred("_run")


func fixture(start_day := 200.0, with_myco := true) -> Dictionary:
	var c: ForestSettings = CONFIG.duplicate(true)
	c.tree_attempts = 0
	c.water_resolution = 16
	c.fungi_resolution = 32
	c.fungi_initial_age_s = 0
	c.fungi_plot_centers = PackedVector2Array([Vector2(.5, .5)])
	c.fungal_species = [load("res://data/fungi/boletus_edulis.tres")]
	c.start_day = start_day
	c.headwater_length = c.extent
	c.headwater_width = c.extent
	c.start_hour = 12
	c.plants = [CONFIG.plants[1].duplicate(true)]
	c.plants[0].reproduction_per_year = 0
	c.plants[0].stress_days = 1e8
	var land := ForestLandscape.new(c)
	var water := ForestWatershed.new(land)
	water.depth.fill(0)
	water.soil.fill(.65)
	var soil := ForestSoil.new(water)
	var trees := ForestTrees.new(land, soil)
	var center := c.extent * .5 + .125
	trees._append(0, Vector3(center, land.height_at(center, center), center), 1.0, 20)
	var initial := trees.element_totals()
	trees.initial_c = initial.x
	trees.initial_n = initial.y
	trees.initial_p = initial.z
	trees._initial_count = 1
	var fungi := ForestFungi.new(water, soil)
	if with_myco:
		trees.mycorrhiza = fungi
	return {"settings": c, "water": water, "soil": soil, "trees": trees, "fungi": fungi}


func budget(w: Dictionary) -> PackedFloat64Array:
	var total := PackedFloat64Array([0, 0, 0])
	for model in [w.trees, w.soil, w.fungi]:
		var m: Dictionary = model.metrics()
		total[0] += m.carbon_kg
		total[1] += m.nitrogen_kg
		total[2] += m.phosphorus_kg
	total[0] += (
		w.soil.metrics().respired_kg_c
		+ w.fungi.metrics().respired_kg_c
		- w.trees.photosynthesized_kg_c
	)
	return total


func _run() -> void:
	assert(CONFIG.plants.size() == 29)
	var identities := {}
	var spores := 0
	for d in CONFIG.plants:
		d.validate()
		assert(not identities.has(d.species_id))
		identities[d.species_id] = true
		assert(ForestPlantMeshBuilder.build(d).get_aabb().size.y > .02)
		if d.propagule_kind == &"spore":
			spores += 1
	assert(spores == 3)
	var myco := fixture()
	var null_world := fixture(200, false)
	for w in [myco, null_world]:
		# Local root mineral cell is empty; adjacent, colonized fine cells retain minerals.
		w.soil.withdraw(w.trees.positions[0], Vector3(0, 999, 999))
	var before := budget(myco)
	var size_before: float = myco.trees.size[0]
	myco.trees.step(ForestClimate.DAY_S, myco.water, 0)
	null_world.trees.step(ForestClimate.DAY_S, null_world.water, 0)
	assert(myco.trees.exported_kg_c > 0, "Mycorrhiza charges real host carbon")
	assert(myco.trees.size[0] > size_before, "Delivered nutrients support real growth")
	assert(
		null_world.trees.size[0] == size_before, "Same deficit without the network blocks growth"
	)
	var after := budget(myco)
	for e in 3:
		assert(absf(after[e] - before[e]) < 1e-6, "Paid exchange closes whole-ecosystem CNP")
	var saved_soil: Dictionary = myco.soil.snapshot()
	var saved_fungi: Dictionary = myco.fungi.snapshot()
	var saved_trees: Dictionary = myco.trees.snapshot()
	myco.trees.step(ForestClimate.DAY_S, myco.water, 0)
	var continued: Dictionary = myco.trees.snapshot()
	assert(
		(
			myco.soil.restore(saved_soil)
			and myco.fungi.restore(saved_fungi)
			and myco.trees.restore(saved_trees)
		)
	)
	myco.trees.step(ForestClimate.DAY_S, myco.water, 0)
	assert(myco.trees.snapshot() == continued, "Paid exchanges continue exactly after load")
	var autumn := fixture(250, false)
	autumn.settings.plants[0].height_growth_m_year = 0
	var autumn_before := budget(autumn)
	var autumn_mass: float = autumn.trees.biomass_c[0]
	for day in 45:
		autumn.trees.step(ForestClimate.DAY_S, autumn.water, 0)
	assert(autumn.trees.litter_kg_c > 0 and autumn.trees.biomass_c[0] < autumn_mass)
	assert(autumn.trees.leaf_carbon[0] < 1e-10)
	var autumn_after := budget(autumn)
	for e in 3:
		assert(
			absf(autumn_before[e] - autumn_after[e]) < 1e-5,
			"Leaf fall transfers existing CNP, not decorative litter"
		)
	var cover := ForestGroundcover.new(autumn.water)
	cover.bind_plants(autumn.trees)
	var surface: PackedFloat64Array = autumn.soil.native.surface_fields(
		autumn.water.soil, cover.biomass
	)
	var litter := 0.0
	for i in range(0, surface.size(), 4):
		litter += surface[i]
	assert(litter > 0)
	var frozen: Dictionary = autumn.soil.snapshot()
	var image := ForestFieldTexture.rgba_image(surface, autumn.water.resolution)
	assert(image.get_format() == Image.FORMAT_RGBAF and autumn.soil.snapshot() == frozen)
	var report := {
		"passed": true,
		"species": 29,
		"spore_species": 3,
		"paid_mycorrhiza": true,
		"same_pipeline_no_network_null": true,
		"mycorrhiza_continuation_exact": true,
		"leaf_fall_carbon_kg": autumn.trees.litter_kg_c,
		"leaf_fall_cnp_conserved": true,
		"soil_surface_from_actual_litter": true,
		"display_read_only": true,
		"boundary":
		(
			"Scenario ECM exchange and explicit initial colonies; "
			+ "AM/ericoid exchange and resolved hyphal topology not modeled"
		)
	}
	FileAccess.open("res://artifacts/ecosystem-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ECOSYSTEM_CHECK ", JSON.stringify(report))
	quit()
