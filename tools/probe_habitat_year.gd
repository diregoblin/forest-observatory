extends Node

## Bounded CPU-only integration observation using the shipping coupled tick.
## Population outcomes are diagnostics, not assertions of ecological calibration.
var world
var samples: Array = []
var initial := PackedFloat64Array()
var started_ms := 0
var maximum_error := PackedFloat64Array([0, 0, 0])
var restore_checks := 0
var target_days := 365.0
var wall_budget_s := 900.0
var output_prefix := "res://artifacts/habitat-year"


func start(scene) -> void:
	world = scene
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe-days="):
			target_days = float(arg.trim_prefix("--probe-days="))
		if arg.begins_with("--probe-wall-s="):
			wall_budget_s = float(arg.trim_prefix("--probe-wall-s="))
		if arg.begins_with("--probe-output="):
			output_prefix = "res://artifacts/" + arg.trim_prefix("--probe-output=")
	assert(target_days > 0 and target_days <= 365 and wall_budget_s > 0 and wall_budget_s <= 900)
	world._finish_model_work(true)
	world.paused = true
	world.set_process(false)
	initial = world._ecosystem_budget()
	started_ms = Time.get_ticks_msec()
	_run.call_deferred()


func sample_state() -> Dictionary:
	var counts := {}
	var eaten := {}
	for d in world.animals.definitions:
		counts[str(d.species_id)] = 0
		eaten[str(d.species_id)] = 0.0
	for id in world.animals.species.size():
		var d: ForestAnimalDefinition = world.animals.definitions[world.animals.species[id]]
		counts[str(d.species_id)] += world.animals.alive[id]
		eaten[str(d.species_id)] += world.animals.life_records[id].consumed_c_kg
	var budget: PackedFloat64Array = world._ecosystem_budget()
	for e in 3:
		maximum_error[e] = maxf(maximum_error[e], absf(budget[e] - initial[e]))
		assert(maximum_error[e] < .05, "Whole-world C/N/P drift exceeds 50 g in a full valley")
	var insect: Dictionary = world.habitat.metrics()
	var report := {
		"tick": world.ecology_clock.ticks,
		"biological_days": world.animals.elapsed_s / ForestClimate.DAY_S,
		"day": world.ecology_clock.sample().day,
		"water_s": world.water.clock,
		"animals": counts,
		"food_kg_c": eaten,
		"living_plants": world.trees.alive.count(1),
		"fallen": world.trees.fallen.count(1),
		"insects": insect,
		"snow_water_m": world.weather.snow_water_m,
		"seed_cargo": world.habitat.seed_carriers.size(),
		"tracks": world.habitat.tracks.size(),
		"traffic_peak": Array(world.habitat.traffic).max(),
		"wall_s": (Time.get_ticks_msec() - started_ms) * .001,
		"maximum_cnp_error_kg": Array(maximum_error)
	}
	return report


func _run() -> void:
	var target := ceili(
		(
			target_days
			* ForestClimate.DAY_S
			/ world.settings.year_speed_multiplier
			/ world.settings.ecology_step_s
		)
	)
	for tick in target:
		world.ecology_clock.request(world.settings.ecology_step_s)
		assert(world.ecology_clock.step())
		world._coupled_tick(world.ecology_clock.sample())
		if (tick + 1) % 120 == 0 or tick + 1 == target:
			var report := sample_state()
			samples.append(report)
			var state := ForestWorldState.capture(
				world._world_models(), world._world_configuration(), {}
			)
			for key in world._world_models():
				if not world._world_models()[key].restore(state.models[key]):
					ForestWorldState.write(output_prefix + "-invalid.bin", state)
					push_error("Self snapshot rejected by " + key + " at tick " + str(tick + 1))
					get_tree().quit(1)
					return
			assert(
				ForestWorldState.restore(
					world._world_models(), world._world_configuration(), state
				),
				"A live full-world state must remain loadable"
			)
			restore_checks += 1
			FileAccess.open(output_prefix + "-progress.json", FileAccess.WRITE).store_string(
				JSON.stringify(report, "  ")
			)
			print("HABITAT_YEAR_PROGRESS ", JSON.stringify(report))
			await get_tree().process_frame
			if Time.get_ticks_msec() - started_ms > wall_budget_s * 1000:
				break
	var final := sample_state()
	var result := {
		"passed": true,
		"completed_year": target_days == 365 and world.ecology_clock.ticks >= target,
		"completed_target": world.ecology_clock.ticks >= target,
		"target_days": target_days,
		"wall_budget_s": wall_budget_s,
		"target_ticks": target,
		"restore_checks": restore_checks,
		"final": final,
		"samples": samples,
		"boundary":
		"One deterministic scenario, at most fifteen CPU minutes; no claim of calibrated population equilibrium"
	}
	FileAccess.open(output_prefix + "-probe.json", FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("HABITAT_YEAR_PROBE ", JSON.stringify(final))
	get_tree().quit()
