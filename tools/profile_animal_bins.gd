extends SceneTree

const HASH_ANIMALS = preload("res://tools/reference/animal_hash_bins.gd")
const WARMUP := 3
const MEASURED := 20
const REPEATS := 2


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var samples := []
	var compared_ticks := 0
	var trace := HashingContext.new()
	assert(trace.start(HashingContext.HASH_SHA256) == OK)
	for repeat_id in REPEATS:
		var worlds := {}
		for variant in ["hash", "flat"]:
			var world = load("res://scripts/forest.gd").new()
			if variant == "hash":
				world.animals = HASH_ANIMALS.new(world.land, world.trees, world.water, world.soil)
				world.habitat.animals = world.animals
			world.paused = true
			root.add_child(world)
			world.set_process(false)
			world.use_model_worker = false
			worlds[variant] = world
		assert(worlds.hash._world_snapshot().models == worlds.flat._world_snapshot().models)
		for tick in WARMUP + MEASURED:
			var sample := {"repeat": repeat_id, "tick": tick}
			var order := ["flat", "hash"] if (tick + repeat_id) % 2 else ["hash", "flat"]
			sample["order"] = order
			for variant in order:
				var world = worlds[variant]
				world.ecology_clock.request(world.settings.ecology_step_s)
				assert(world.ecology_clock.step())
				world._coupled_tick(world.ecology_clock.sample())
				sample[variant] = world.tick_profile_usec.duplicate()
			# Compare every completed tick, not just the final animal positions.
			# This includes food, all C/N/P owners, paths, events and RNG state.
			var expected: Dictionary = worlds.hash._world_snapshot().models
			var actual: Dictionary = worlds.flat._world_snapshot().models
			assert(expected == actual, "Model divergence at repeat %s tick %s" % [repeat_id, tick])
			var expected_bytes := var_to_bytes(expected)
			assert(expected_bytes == var_to_bytes(actual))
			assert(trace.update(expected_bytes) == OK)
			compared_ticks += 1
			if tick >= WARMUP:
				samples.append(sample)
		for world in worlds.values():
			world.free()
	var report := {
		"passed": true,
		"paired_samples": samples,
		"model_equal_ticks": compared_ticks,
		"model_trace_sha256": trace.finish().hex_encode(),
		"warmup_per_repeat": WARMUP,
		"measured_per_repeat": MEASURED,
		"repeats": REPEATS,
		"boundary":
		"Headless coupled-tick wall time; alternating order, untouched desktop load. Not rendered FPS."
	}
	FileAccess.open("res://artifacts/animal-bins-profile.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ANIMAL_BINS_PROFILE passed=", report.passed, " equal_ticks=", compared_ticks)
	quit()
