extends SceneTree


func _initialize() -> void:
	var config: ForestSettings = load("res://data/forest.tres").duplicate(true)
	config.validate()
	var land := ForestLandscape.new(config)
	var open := ForestWatershed.new(land)
	var blocked := ForestWatershed.new(land)
	blocked.set_barrier(land.channel_barrier(), true)
	var removed := ForestWatershed.new(land)
	removed.set_barrier(land.channel_barrier(), true)
	var max_error := 0.0
	var min_depth := 0.0
	for t in 200:
		for w in [open, blocked, removed]:
			w.step(3.0)
			max_error = maxf(max_error, absf(_independent_balance(w)))
			assert(w.stats.finite)
			for h in w.depth:
				min_depth = minf(min_depth, h)
		if t == 99:
			assert(absf(_upstream(blocked) - _upstream(removed)) < 1e-8, "identical prefix")
			removed.set_barrier(land.channel_barrier(), false)
	var effect := _upstream(blocked) - _upstream(open)
	var release_effect := _upstream(blocked) - _upstream(removed)
	assert(max_error < 1e-5, "independent surface + soil + pending ledger")
	assert(min_depth >= -1e-12, "no negative water")
	assert(effect > 1.0, "dam must retain more water than open")
	assert(release_effect > 1.0, "removing dam must drain retained water")
	# Independent checker must detect a corrupt display/export snapshot.
	removed.depth[0] += .1
	assert(absf(_independent_balance(removed)) > 1.0, "known wrong snapshot detected")
	# Snapshot mutations do not write into the native authoritative state.
	assert(absf(removed.balance_error()) < 1e-5)
	removed.sync_fields()
	# Save between soil ticks, with nonzero reserved infiltration and momentum.
	removed.raining = true
	assert(removed.native.set_evaporation(config.evaporation_m_s * .7))
	removed.step(17)
	var pending := 0.0
	for v in removed.pending_water_m:
		pending += v
	assert(pending > 0 and removed.stats.soil_elapsed_s > 0)
	var save_path := "res://artifacts/hydro-check-state.bin"
	assert(removed.save_state(save_path) == OK)
	var resumed := ForestWatershed.new(land)
	assert(resumed.load_state(save_path))
	assert(resumed.raining)
	var other_config: ForestSettings = config.duplicate(true)
	other_config.seed += 1
	var other := ForestWatershed.new(ForestLandscape.new(other_config))
	assert(not other.load_state(save_path), "different landscape rejected")
	for i in 20:
		removed.step(3.0)
		resumed.step(3.0)
	assert(removed.depth == resumed.depth and removed.soil == resumed.soil)
	assert(removed.flux_x == resumed.flux_x and removed.flux_z == resumed.flux_z)
	assert(removed.ground_water_m == resumed.ground_water_m)
	assert(
		removed.stats == resumed.stats, "complete continuation includes pending soil and counters"
	)
	var corrupt: Dictionary = removed.native.snapshot()
	var wrong: PackedFloat64Array = corrupt.depth
	wrong[0] += .1
	corrupt.depth = wrong
	assert(not resumed.native.restore(corrupt), "corrupt checkpoint rejected atomically")
	assert(resumed.stats == resumed.native.metrics(), "failed restore preserves current state")
	removed.raining = false
	var seep_before: float = removed.stats.seeped_m3
	removed.step(120)
	var dry_weather_seep: float = removed.stats.seeped_m3 - seep_before
	assert(
		dry_weather_seep > 0, "stored groundwater returns to actual valley surface after rain stops"
	)
	assert(absf(_independent_balance(removed)) < 1e-5)
	var report := {
		"passed": true,
		"backend": "C++ local inertia + two-layer bucket soil",
		"resolution": config.water_resolution,
		"cell_m": open.cell_size,
		"max_balance_error_m3": max_error,
		"min_depth_m": min_depth,
		"retained_vs_open_m3": effect,
		"released_vs_intact_m3": release_effect,
		"water_steps": open.stats.water_steps,
		"soil_ticks": open.stats.soil_ticks,
		"model_s": open.clock,
		"pending_reserve_at_checkpoint_m3": pending * removed.cell_area,
		"known_wrong_rejected": true,
		"save_resume_exact": true,
		"wrong_landscape_rejected": true,
		"dry_weather_valley_returnflow_m3": dry_weather_seep,
		"boundary": "Numerical mechanism/accounting only, not calibrated field hydrology"
	}
	var f := FileAccess.open("res://artifacts/water-check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print("WATER_CHECK ", JSON.stringify(report))
	quit()


func _independent_balance(water: ForestWatershed) -> float:
	var reserve := 0.0
	for k in water.depth.size():
		reserve += (
			(
				water.depth[k]
				+ water.top_water_m[k]
				+ water.root_water_m[k]
				+ water.pending_water_m[k]
				+ water.ground_water_m[k]
			)
			* water.cell_area
		)
	return (
		reserve
		+ water.outflow
		+ water.evaporated
		+ water.deep_drain
		+ float(water.stats.transpired_m3)
		- water.initial_volume
		- water.inflow
	)


func _upstream(water: ForestWatershed) -> float:
	var barrier := water.landscape.channel_barrier()
	return water.volume_in(Rect2(0, 0, water.landscape.settings.extent, barrier.start.y))
