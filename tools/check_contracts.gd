extends SceneTree


func _initialize() -> void:
	var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
	settings.validate()
	for definition in settings.plants:
		var mesh := ForestPlantMeshBuilder.build(definition)
		assert(mesh.get_surface_count() == 1)
		assert(mesh.surface_get_array_len(0) > 0)
		var has_foliage := false
		for module in definition.modules:
			has_foliage = has_foliage or module.foliage
		assert(has_foliage, "seasonal foliage geometry must survive resource loading")
		var colors: PackedColorArray = mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		var leaf_vertices := 0
		var stem_vertices := 0
		for color in colors:
			if color.a < .5:
				leaf_vertices += 1
			else:
				stem_vertices += 1
		assert(leaf_vertices > 0 and stem_vertices > 0, "both leaf and stem tags reach the shader")
	# A third identity uses the identical builder and resource schema.
	var extra: ForestPlantDefinition = settings.plants[0].duplicate(true)
	extra.species_id = &"test_shrub"
	extra.display_name = "Test shrub"
	extra.scale_range = Vector2(.2, .4)
	settings.plants.append(extra)
	settings.validate()
	assert(ForestPlantMeshBuilder.build(extra).get_surface_count() == 1)
	var landscape := ForestLandscape.new(settings)
	var water := ForestWatershed.new(landscape)
	var base_x := water.crest_x.duplicate()
	var base_z := water.crest_z.duplicate()
	var horizontal := landscape.channel_barrier()
	var vertical := ForestBarrier.new()
	vertical.barrier_id = &"test_vertical"
	vertical.start = Vector2(128, 32)
	vertical.end = Vector2(128, 160)
	vertical.crest = 1000
	water.set_barrier(vertical, true)
	assert(water.crest_x != base_x and water.crest_z == base_z)
	water.set_barrier(horizontal, true)
	assert(water.barriers.size() == 2)
	water.set_barrier(vertical, false)
	assert(water.crest_x == base_x and water.crest_z != base_z)
	water.set_barrier(horizontal, false)
	assert(water.crest_x == base_x and water.crest_z == base_z)
	var image := ForestFieldTexture.image(water.depth, water.resolution)
	assert(image.get_width() == water.resolution)
	for i in range(0, water.depth.size(), 47):
		assert(
			(
				absf(image.get_pixel(i % water.resolution, i / water.resolution).r - water.depth[i])
				< 1e-6
			)
		)
	var individuals := ForestTrees.new(landscape)
	var before := individuals.snapshot()
	var plants_a := ForestGroundcover.new(water)
	var plants_b := ForestGroundcover.new(water)
	plants_a.bind_plants(individuals)
	plants_b.bind_plants(individuals)
	plants_a.step(3 * settings.ecology_interval, water)
	for i in 360:
		plants_b.step(settings.ecology_interval / 120, water)
	assert(plants_a.ticks == 0 and plants_b.ticks == 0, "cover has no second biological clock")
	assert(
		plants_a.biomass == plants_b.biomass and individuals.snapshot() == before,
		"cover is derived/read-only"
	)
	var clock_a := ForestEcologyClock.new(settings)
	var clock_b := ForestEcologyClock.new(settings)
	clock_a.request(3 * settings.ecology_step_s)
	while clock_a.step():
		pass
	for i in 360:
		clock_b.request(settings.ecology_step_s / 120)
		while clock_b.step():
			pass
	assert(
		clock_a.ticks == 3 and clock_b.ticks == 3,
		"actual model clock independent of request partition"
	)
	var report := {
		"passed": true,
		"third_species_shared_builder": true,
		"multiple_oriented_barriers": true,
		"float64_to_gpu_field": true,
		"ecology_model_clock": true,
		"derived_cover_read_only": true
	}
	var file := FileAccess.open("res://artifacts/contracts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("CONTRACT_CHECK ", JSON.stringify(report))
	quit()
