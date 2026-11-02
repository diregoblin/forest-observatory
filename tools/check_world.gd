extends RefCounted


static func run(world) -> void:
	# Exercise the actual composed models, not a second toy save implementation.
	world.paused = true
	var original: Dictionary = world._world_snapshot()
	var budget: PackedFloat64Array = world._ecosystem_budget()
	var path := "res://artifacts/world-roundtrip.bin"
	assert(ForestWorldState.write(path, original) == OK)
	var saved := ForestWorldState.read(path)
	assert(saved == original, "binary checkpoint preserves packed float64 state")
	world._advance_world(world.settings.ecology_step_s)
	var expected: Dictionary = world._world_snapshot().models
	assert(world._restore_world(saved))
	world._advance_world(world.settings.ecology_step_s)
	assert(world._world_snapshot().models == expected, "whole-world save continues exactly")
	var errors := PackedFloat64Array()
	for e in 3:
		errors.append(world._ecosystem_budget()[e] - budget[e])
		assert(absf(errors[e]) < 1e-5, "whole-world finite CNP budget")
	var before: Dictionary = world._world_snapshot()
	var corrupt: Dictionary = before.duplicate(true)
	corrupt.models.animals.version = -1
	assert(not world._restore_world(corrupt))
	var after: Dictionary = world._world_snapshot()
	if after != before:
		for key in before.models:
			if before.models[key] != after.models[key]:
				for field in before.models[key]:
					if before.models[key][field] != after.models[key][field]:
						print("ROLLBACK_DIFFERENCE ", key, ".", field)
	assert(after == before, "late restore rejection rolls all models back")
	corrupt = before.duplicate(true)
	corrupt.models.animals.life_records[0].rested_s = INF
	assert(
		not world._restore_world(corrupt) and world._world_snapshot() == before,
		"Corrupt personal records must roll the whole world back"
	)
	for selection in [
		{"id": 0}, {"kind": &"plant", "id": "oops"}, {"kind": &"animal", "id": 999999}
	]:
		corrupt = before.duplicate(true)
		corrupt.scene.selection = selection
		assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.weather.snow_water_m = 1
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.habitat.traffic[0] = -1.0
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.habitat.detritivore_c[0] = -1
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.animals.home_positions[0].x = NAN
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.clock.ticks += 1
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.models.soil.patches[0].ox += 4
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	corrupt = before.duplicate(true)
	corrupt.scene.camera_position = Vector3(NAN, 0, 0)
	assert(not world._restore_world(corrupt) and world._world_snapshot() == before)
	# Full production sequence, including animal returns after fungal advances.
	for tick in 32:
		world._advance_world(world.settings.ecology_step_s)
	for e in 3:
		errors[e] = world._ecosystem_budget()[e] - budget[e]
		assert(absf(errors[e]) < 1e-4, "multi-day composed ecosystem budget")
	assert(
		world.habitat.traffic.count(0) < world.habitat.traffic.size(),
		"Production animal paths create real traffic"
	)
	var legacy: Dictionary = world._world_snapshot()
	legacy.models.animals.version = 1
	assert(not world._restore_world(legacy), "Old behavior versions are deliberately incompatible")
	world.soil.deposit_elements(world.trees.positions[0], 0, .01, 0, false)
	assert(world._ecosystem_budget()[1] - budget[1] > .009, "budget detects injected nitrogen")
	assert(world._restore_world(original))
	var report := {
		"passed": true,
		"models": world._world_models().keys(),
		"cnp_error_kg": Array(errors),
		"coupled_ticks_for_budget": 33,
		"injected_nitrogen_detected": true,
		"binary_roundtrip": true,
		"exact_continuation": true,
		"atomic_late_rejection": true,
		"personal_record_rejection_atomic": true,
		"older_behavior_version_rejected": true,
		"invalid_scene_rejected": true,
		"invalid_selection_rejected": true,
		"inconsistent_clocks_rejected": true,
		"moved_soil_patch_rejected": true,
		"weather_habitat_home_rejection_atomic": true
	}
	var file := FileAccess.open("res://artifacts/world-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("WORLD_CHECK ", JSON.stringify(report))
