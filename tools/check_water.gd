extends SceneTree


# Same solver as interactive scene; check definitions (ledger, counterfactuals).
func _initialize() -> void:
	var config: ForestSettings = load("res://data/forest.tres")
	config.validate()
	var land := ForestLandscape.new(config)
	var open := ForestWatershed.new(land)
	var blocked := ForestWatershed.new(land)
	blocked.set_barrier(land.channel_barrier(), true)
	var removed := ForestWatershed.new(land)
	removed.set_barrier(land.channel_barrier(), true)
	var dry := ForestWatershed.new(land)
	dry.depth.fill(0)
	dry.initial_volume = 0
	# A flat still lake: source/outlet and soak are disabled by fully saturated
	# soil except evaporation; equal levels must stay equal under face transfer.
	var transfer_zero := dry._transfer(0, 1, maxf(dry.bed[0], dry.bed[1]), .2) == 0.0
	var max_error := 0.0
	var min_depth := 0.0
	for t in 500:
		open.step(.2)
		blocked.step(.2)
		removed.step(.2)
		if t == 249:
			assert(absf(_upstream(blocked) - _upstream(removed)) < 1e-8, "identical prefix")
			removed.set_barrier(land.channel_barrier(), false)
		for w in [open, blocked, removed]:
			max_error = maxf(max_error, absf(w.balance_error()))
			for h in w.depth:
				min_depth = minf(min_depth, h)
	var effect := _upstream(blocked) - _upstream(open)
	var release_effect := _upstream(blocked) - _upstream(removed)
	assert(transfer_zero, "dry adjacent cells must not transfer")
	assert(max_error < 1e-6, "conservation ledger")
	assert(min_depth >= -1e-12, "no negative water")
	assert(effect > 1.0, "dam must retain more water than open")
	assert(release_effect > 1.0, "removing dam must drain retained water")
	# Known-wrong artifact: add unaccounted water, ledger must reject it.
	removed.depth[0] += .1
	assert(absf(removed.balance_error()) > 1.0, "known-wrong water must be detected")
	var report := {
		"passed": true,
		"max_balance_error_m3": max_error,
		"min_depth_m": min_depth,
		"retained_vs_open_m3": effect,
		"released_vs_intact_m3": release_effect,
		"dry_face_zero": transfer_zero,
		"known_wrong_rejected": true,
		"steps": 500,
		"dt": .2,
		"boundary": "Numerical mechanism/accounting only, not validated hydrology"
	}
	var f := FileAccess.open("res://artifacts/water-check.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	print("WATER_CHECK ", JSON.stringify(report))
	quit()


func _upstream(water: ForestWatershed) -> float:
	var barrier := water.landscape.channel_barrier()
	return water.volume_in(Rect2(0, 0, water.landscape.settings.extent, barrier.start.y))
