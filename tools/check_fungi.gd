extends SceneTree


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var config: ForestSettings = load("res://data/forest.tres").duplicate(true)
	config.validate()
	var land := ForestLandscape.new(config)
	var water := ForestWatershed.new(land)
	var fungi := ForestFungi.new(water)
	assert(fungi.plots.size() == 3)
	var initial := fungi.snapshot()
	var years := ForestClimate.YEAR_S
	for i in 20:
		fungi.step(years / 100.0, water, ForestClimate.sample(i * years / 100.0))
	var continued := fungi.snapshot()
	var m := fungi.metrics()
	assert(m.carbon_error_kg < 1e-8 and m.edge_biomass_kg < .001)
	assert(fungi.restore(initial))
	for i in 20:
		fungi.step(years / 100.0, water, ForestClimate.sample(i * years / 100.0))
	assert(fungi.snapshot() == continued, "all pools + forcing + clocks continue exactly")
	var invalid := continued.duplicate(true)
	invalid.plots[1].state.fruit[0] = -1.0
	assert(not fungi.restore(invalid))
	assert(fungi.snapshot() == continued, "invalid restore is atomic")
	var core: ForestFungiNative = fungi.plots[0].native
	var before := core.snapshot()
	var dry := PackedFloat64Array()
	var clear := PackedFloat64Array()
	dry.resize(water.resolution * water.resolution)
	clear.resize(dry.size())
	assert(
		core.set_environment(
			dry,
			clear,
			water.resolution,
			water.cell_size,
			fungi.plots[0].origin.x,
			fungi.plots[0].origin.y,
			12
		)
	)
	var forced: Dictionary = core.snapshot()
	assert(forced.activity.count(0.0) == forced.activity.size())
	assert(forced.fruit_suitability.count(0.0) == forced.fruit_suitability.size())
	assert(core.advance(86400))
	var after: Dictionary = core.fields()
	for k in after.fruit.size():
		assert(after.fruit[k] <= before.fruit[k] + 1e-14, "dry soil cannot create new fruit")
	assert(core.restore(before))
	# The view is a consumer: refreshing cannot spend carbon or advance time.
	fungi.sync_fields()
	var view := ForestFungiView.new()
	root.add_child(view)
	view.configure(fungi)
	var state_before := fungi.snapshot()
	var bodies_before := view.body_count
	assert(view.body_count > 0 and view.group_count > 0, "single bodies and clumps render")
	view.refresh()
	assert(view.body_count == bodies_before and fungi.snapshot() == state_before)
	view.queue_free()
	var file := FileAccess.open("res://artifacts/fungi-check.json", FileAccess.WRITE)
	file.store_string(
		JSON.stringify(
			{
				"passed": true,
				"carbon_error_kg": m.carbon_error_kg,
				"continuation_exact": true,
				"invalid_restore_atomic": true,
				"dry_soil_blocks_fruiting": true,
				"view_read_only": true,
				"body_count": bodies_before,
				"group_count": view.group_count,
				"mean_step_ms": m.mean_step_ms
			},
			"  "
		)
	)
	print("FUNGI_CHECK passed")
	quit()
