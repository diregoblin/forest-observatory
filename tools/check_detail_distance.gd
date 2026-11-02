extends "res://tools/check_weather_habitat.gd"


func _run() -> void:
	var w := fixture(true)
	var climate := ForestClimate.sample(0, 160)
	climate.wind_m_s = 2.0
	climate.rain_fraction = 0.0
	w.habitat.step(ForestClimate.DAY_S, climate)
	var view := ForestHabitatView.new()
	var camera := Camera3D.new()
	root.add_child(camera)
	root.add_child(view)
	view.paused = true
	var point: Vector3 = w.trees.positions[0] + Vector3.UP
	camera.position = point
	view.configure(w.habitat, camera)
	var frozen: Dictionary = w.habitat.snapshot()
	var plants: Dictionary = w.trees.snapshot()
	var animals: Dictionary = w.animals.snapshot()
	var counts := []
	var elapsed := []
	for offset in [0.0, 12.0, 30.0, 80.0]:
		camera.position = point + Vector3.UP * offset
		view.refresh(climate)
		var started := Time.get_ticks_usec()
		for i in 200:
			if view.has_method("advance_display"):
				view.advance_display()
			else:
				view.refresh(climate)
		elapsed.append((Time.get_ticks_usec() - started) / 200.0)
		counts.append(view.bugs.multimesh.visible_instance_count)
	assert(
		(
			w.habitat.snapshot() == frozen
			and w.trees.snapshot() == plants
			and w.animals.snapshot() == animals
		)
	)
	var baseline := OS.get_cmdline_user_args().has("--baseline")
	if not baseline:
		assert(counts[0] > 0 and counts[1] > 0 and counts[2] == 0 and counts[3] == 0)
		# Camera-only changes refresh from submitted data, without a biology refresh.
		camera.position = point
		view.advance_display()
		assert(view.bugs.multimesh.visible_instance_count == counts[0])
		camera.position = point + Vector3.UP * 30
		view.advance_display()
		assert(view.bugs.multimesh.visible_instance_count == 0)
		assert(w.habitat.snapshot() == frozen)
		# No live model access is available during these camera-only submissions.
		view.habitat = null
		var batches := [view.footprints, view.homes, view.rootplates]
		var limits := [
			view.footprint_view_distance_m,
			view.home_view_distance_m,
			view.rootplate_view_distance_m
		]
		for index in batches.size():
			var batch: MultiMeshInstance3D = batches[index]
			view._candidates[batch] = [[Transform3D(Basis.IDENTITY, point), Color.WHITE, Color()]]
			view._display_dirty = true
			camera.position = point
			view.advance_display()
			assert(batch.multimesh.visible_instance_count == 1)
			camera.position = point + Vector3.UP * (limits[index] + 1)
			view.advance_display()
			assert(batch.multimesh.visible_instance_count == 0)
		view.insect_view_distance_m = 0
		camera.position = point
		view.advance_display()
		assert(view.bugs.multimesh.visible_instance_count == 0)
		view.habitat = w.habitat
	var report := {
		"passed": true,
		"baseline": baseline,
		"offsets_m": [0, 12, 30, 80],
		"bug_instances": counts,
		"paused_display_usec_mean": elapsed,
		"simulation_unchanged": true,
		"all_detail_ranges_and_worker_safe_camera_update": not baseline,
		"boundary": "CPU submission fixture, not FPS or GPU timing"
	}
	(
		FileAccess
		. open(
			"res://artifacts/detail-distance-%s.json" % ("baseline" if baseline else "check"),
			FileAccess.WRITE
		)
		. store_string(JSON.stringify(report, "  "))
	)
	print("DETAIL_DISTANCE ", JSON.stringify(report))
	view.free()
	camera.free()
	quit()
