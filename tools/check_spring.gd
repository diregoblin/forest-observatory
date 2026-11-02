extends SceneTree


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var config: ForestSettings = load("res://data/forest.tres").duplicate(true)
	var land := ForestLandscape.new(config)
	var water := ForestWatershed.new(land)
	var head := land.spring_position()
	var mouth := land.spring_mouth()
	var k := water.index_at(head.x, head.y)
	var control_config: ForestSettings = config.duplicate(true)
	control_config.spring_enabled = false
	var old_land := ForestLandscape.new(control_config)
	assert(old_land.height_at(head.x, head.y) - land.height_at(head.x, head.y) > 4)
	assert(land.height_at(head.x, head.y) > land.height_at(mouth.x, mouth.y))
	# A point well outside the trench must keep its exact pre-existing terrain.
	assert(land.height_at(400, 420) == old_land.height_at(400, 420))
	# Renderer and native bed receive the same analytical landscape, not a decal.
	for j in water.resolution:
		for i in water.resolution:
			assert(
				(
					water.bed[j * water.resolution + i]
					== land.height_at((i + .5) * water.cell_size, (j + .5) * water.cell_size)
				)
			)
	assert(is_equal_approx(water.source_flow_m3_s[k], config.spring_flow_m3_s))
	var sum := 0.0
	for rate in water.source_flow_m3_s:
		sum += rate
	assert(absf(sum - config.headwater_m3_s - config.spring_flow_m3_s) < 1e-12)
	# Dry the entire synthetic assay and isolate the side spring, no rain,
	# groundwater, evaporation or infiltration. Its water must really travel.
	var state: Dictionary = water.native.snapshot()
	var empty := PackedFloat64Array()
	empty.resize(water.depth.size())
	var weights := PackedFloat64Array([1.0])
	state.sources = PackedInt32Array([k])
	state.source_weights = weights
	state.options.source_m3_s = config.spring_flow_m3_s
	state.options.groundwater = false
	state.options.conductivity_m_s = 0.0
	state.options.root_conductivity_m_s = 0.0
	state.options.evaporation_m_s = 0.0
	state.evaporation_rate_m_s = 0.0
	state.depth = empty.duplicate()
	state.ground = empty.duplicate()
	state.initial_m3 = water.stats.soil_m3
	assert(water.native.restore(state))
	var dry_control = ClassDB.instantiate(&"ForestHydroNative")
	var no_source: Dictionary = state.duplicate(true)
	no_source.options.source_m3_s = 0.0
	assert(dry_control.restore(no_source))
	assert(water.native.advance(300, false))
	assert(dry_control.advance(300, false))
	water.sync_fields()
	assert(absf(water.stats.input_m3 - config.spring_flow_m3_s * 300) < 1e-9)
	assert(absf(water.balance_error()) < 1e-7)
	var downstream_volume := 0.0
	for z in water.resolution:
		if (z + .5) * water.cell_size > head.y + 16:
			for x in water.resolution:
				downstream_volume += water.depth[z * water.resolution + x] * water.cell_area
	assert(
		downstream_volume > .01,
		"Real spring water must leave its source and travel down the ravine"
	)
	assert(dry_control.metrics().surface_m3 == 0, "Source-off null must remain dry")
	# Weighted snapshot continuation and invalid input rejection are exact/atomic.
	var saved: Dictionary = water.native.snapshot()
	assert(dry_control.restore(saved))
	assert(water.native.advance(7, false) and dry_control.advance(7, false))
	assert(water.native.snapshot() == dry_control.snapshot())
	var bad: Dictionary = dry_control.snapshot()
	bad.source_weights = PackedFloat64Array([-1])
	var before: Dictionary = dry_control.snapshot()
	assert(not dry_control.restore(bad) and dry_control.snapshot() == before)
	var report := {
		"passed": true,
		"head": head,
		"mouth": mouth,
		"spring_m3_s": config.spring_flow_m3_s,
		"total_inflow_m3_s": sum,
		"source_only_300s_downstream_m3": downstream_volume,
		"source_off_null_dry": true,
		"native_bed_matches_landscape": true,
		"weighted_continuation_exact": true,
		"bad_weights_rejected_atomically": true
	}
	FileAccess.open("res://artifacts/spring-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SPRING_CHECK ", JSON.stringify(report))
	quit()
