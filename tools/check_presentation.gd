extends Node

## Opt-in Forward+ assay. No disk saves/configuration or user game are touched.
var world
var samples: Array[Dictionary] = []
var recording := false


func _process(dt: float) -> void:
	if recording:
		var timings: Dictionary = world.painterly_style.pixel_renderer.frame_times()
		samples.append(
			{
				"frame_ms": dt * 1000,
				"main_ms": world.last_process_usec / 1000.0,
				"render_cpu_ms": timings.cpu_ms,
				"render_gpu_ms": timings.gpu_ms
			}
		)


func measure(label: String, worker: bool, speed: float) -> Dictionary:
	world._finish_model_work(true)
	world.use_model_worker = worker
	world._set_speed(speed)
	await get_tree().create_timer(1).timeout
	world._finish_model_work(true)
	var start: float = world.water.clock
	var wall := Time.get_ticks_usec()
	samples.clear()
	recording = true
	await get_tree().create_timer(6).timeout
	recording = false
	world._finish_model_work(true)
	var frames := []
	var main := []
	var render_cpu := []
	var render_gpu := []
	for sample in samples:
		frames.append(sample.frame_ms)
		main.append(sample.main_ms)
		render_cpu.append(sample.render_cpu_ms)
		render_gpu.append(sample.render_gpu_ms)
	frames.sort()
	main.sort()
	render_cpu.sort()
	render_gpu.sort()
	var elapsed := (Time.get_ticks_usec() - wall) / 1e6
	return {
		"mode": label,
		"frames": frames.size(),
		"delivered_fps": frames.size() / elapsed,
		"frame_p95_ms": frames[int(frames.size() * .95)],
		"frame_max_ms": frames.back(),
		"main_p95_ms": main[int(main.size() * .95)],
		"main_max_ms": main.back(),
		"render_cpu_p95_ms": render_cpu[int(render_cpu.size() * .95)],
		"render_gpu_p95_ms": render_gpu[int(render_gpu.size() * .95)],
		"achieved_shared_speed": (world.water.clock - start) / elapsed
	}


func start(scene) -> void:
	world = scene
	var report := {"renderer": RenderingServer.get_current_rendering_method(), "timings": []}
	# Both paths use the same ecology/renderer. Isolates main-thread vs worker cost.
	report.timings.append(await measure("synchronous-reference-1x", false, 1))
	report.timings.append(await measure("worker-1x", true, 1))
	report.timings.append(await measure("worker-8x", true, 8))
	world._toggle_pause()
	world._check_clock_alignment()
	world._set_speed(1)
	world.capture_dir = "res://artifacts"
	# Hold light fixed for the following geometry/soil assays, not a weather claim.
	world.season_preview = 3
	world.atmosphere.set_season(world._display_climate())
	for identity in [&"rowan", &"male_fern"]:
		for id in world.trees.species.size():
			if world.settings.plants[world.trees.species[id]].species_id != identity:
				continue
			if not world.trees.alive[id]:
				continue
			world.vegetation.refresh_trees(world._display_climate())
			var bounds: AABB = world.vegetation.selection_shape(id).bounds
			var center := bounds.get_center()
			world.camera.position = (
				center + Vector3(.7, .6, 1).normalized() * maxf(2, bounds.size.length() * 1.3)
			)
			world.camera.look_at(center)
			world.observation.selected = {"kind": &"plant", "id": id}
			await world._save_frame("ecosystem-%s.png" % identity)
			break
	world.observation.selected.clear()
	world.fungi.sync_fields()
	world.fungi_view.refresh()
	for index in world.fungi_view.batches.size():
		var batch: MultiMeshInstance3D = world.fungi_view.batches[index]
		assert(batch.multimesh.instance_count > 0)
		var center := batch.multimesh.get_instance_transform(0).origin + Vector3.UP * .1
		world.camera.position = center + Vector3(.65, .55, .85)
		world.camera.look_at(center)
		world.hud.notice("Грибной участок: %s" % world.settings.fungus_for_plot(index).display_name)
		await world._save_frame("ecosystem-fungus-%d.png" % index)
	# Paired causal leaf assay: only existing leaf carbon is transferred. Same camera,
	# light, water and cover. Hidden plant meshes make the surface comparison legible.
	var selected := -1
	var largest := 0.0
	for id in world.trees.species.size():
		var d: ForestPlantDefinition = world.settings.plants[world.trees.species[id]]
		if d.species_id == &"birch" and world.trees.leaf_carbon[id] > largest:
			largest = world.trees.leaf_carbon[id]
			selected = id
	assert(selected >= 0)
	var position: Vector3 = world.trees.positions[selected]
	var target := position + Vector3(1.5, .08, 1.5)
	world.camera.position = target + Vector3(4, 5, 4)
	world.camera.look_at(target)
	world.vegetation.visible = false
	world.animals_view.visible = false
	world.hud.notice("Изолированный опыт опада: неизменные свет, вода и камера; растения скрыты")
	world.terrain.refresh_ecology(world.soil, world.water, world.groundcover)
	world.terrain.advance_ecology_display(1)
	await world._save_frame("ecosystem-soil-before.png")
	var before: PackedFloat64Array = world._ecosystem_budget()
	var old_time: float = world.trees.elapsed_s
	world.trees.elapsed_s = (250 - world.settings.start_day) * ForestClimate.DAY_S
	world.trees._leaf_turnover(45 * ForestClimate.DAY_S)
	world.trees.elapsed_s = old_time
	var after: PackedFloat64Array = world._ecosystem_budget()
	for e in 3:
		assert(absf(before[e] - after[e]) < 1e-5)
	world.terrain.refresh_ecology(world.soil, world.water, world.groundcover)
	world.terrain.advance_ecology_display(1)
	await world._save_frame("ecosystem-soil-after.png")
	report["leaf_assay_transferred_carbon_kg"] = world.trees.litter_kg_c
	report["leaf_assay_cnp_conserved"] = true
	report["boundary"] = (
		"Isolated Forward+ preview on this host; 60 FPS cap. "
		+ "Paired soil assay holds light/camera fixed, not a full seasonal validation."
	)
	FileAccess.open("res://artifacts/presentation-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("PRESENTATION_CHECK ", JSON.stringify(report))
	get_tree().quit()
