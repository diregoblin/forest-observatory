extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.use_model_worker = false
	scene.trees.use_native_light = not OS.get_cmdline_user_args().has("--reference-light")
	var samples := []
	var plant_samples := []
	for tick in 13:
		scene.ecology_clock.request(scene.settings.ecology_step_s)
		assert(scene.ecology_clock.step())
		scene._coupled_tick(scene.ecology_clock.sample())
		if tick > 2:
			samples.append(scene.tick_profile_usec.duplicate())
			plant_samples.append(scene.trees.step_profile_usec.duplicate())
	FileAccess.open("res://artifacts/model-stages-state.bin", FileAccess.WRITE).store_var(
		scene._world_snapshot().models
	)
	var means := {}
	var total := 0.0
	for key in samples[0]:
		var sum := 0.0
		for sample in samples:
			sum += sample[key] / 1000.0
		means[key] = sum / samples.size()
		total += means[key]
	var report := {
		"samples_us": samples,
		"plant_phase_samples_us": plant_samples,
		"mean_ms": means,
		"sum_mean_ms": total,
		"seed": scene.settings.seed,
		"plant_count": scene.trees.species.size(),
		"boundary":
		(
			"10 initial coupled CPU ticks after 3 warmup ticks, headless, default full model. "
			+ "No GPU/render FPS claim; not aged second-day state."
		)
	}
	var result_path := "res://artifacts/plant-phases-profile.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--result="):
			result_path = arg.trim_prefix("--result=")
	FileAccess.open(result_path, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("MODEL_STAGES_PROFILE ", JSON.stringify(report))
	scene.free()
	quit()
