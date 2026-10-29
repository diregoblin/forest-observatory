extends SceneTree


func _initialize() -> void:
	var settings: ForestSettings = load("res://data/forest.tres").duplicate(true)
	settings.validate()
	for definition in settings.plants:
		var mesh := ForestPlantMeshBuilder.build(definition)
		assert(mesh.get_surface_count() == 1)
		assert(mesh.surface_get_array_len(0) > 0)
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
	var plants_a := ForestGroundcover.new(water)
	var plants_b := ForestGroundcover.new(water)
	plants_a.step(180, water)
	for i in 360:
		plants_b.step(.5, water)
	assert(plants_a.ticks == 3 and plants_a.ticks == plants_b.ticks)
	assert(plants_a.biomass == plants_b.biomass, "ecology independent of frame partition")
	var report := {
		"passed": true,
		"third_species_shared_builder": true,
		"multiple_oriented_barriers": true,
		"float64_to_gpu_field": true,
		"ecology_model_clock": true
	}
	var file := FileAccess.open("res://artifacts/contracts.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("CONTRACT_CHECK ", JSON.stringify(report))
	quit()
