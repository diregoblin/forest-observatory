extends "res://tools/preview_ground_turf.gd"


func _run() -> void:
	root.size = Vector2i(960, 600)
	Engine.max_fps = 20
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.capture_dir = ""
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.atmosphere.rain_particles.emitting = false
	var point := Vector3(196.6849, 22.21007, 227.8804)
	scene.camera.position = point + Vector3(10, 2, 13)
	scene.camera.look_at(point + Vector3(0, 4.5, 0))
	var wind: ForestWindField = scene.vegetation.wind
	for step in 15:
		wind.advance(.1, Vector2(8, 2))
	var materials: Array = scene.vegetation.tree_materials.values()
	materials.append(scene.turf_cards.material)
	for mat in materials:
		wind.apply(mat)
	for frame in 50:
		await RenderingServer.frame_post_draw
	# Repeated ABBA after both branches have rendered; GPU time includes the
	# world SubViewport plus composition, with the same frozen scene and field.
	scene.turf_cards.set_process(false)
	var baseline_path := OS.get_environment("FOREST_WIND_BASELINE")
	assert(
		not baseline_path.is_empty(), "Set FOREST_WIND_BASELINE to the saved original source tree"
	)
	var originals := {}
	for name in ["pixel_foliage", "turf_cards"]:
		var shader := Shader.new()
		shader.code = FileAccess.get_file_as_string(
			baseline_path.path_join("shaders/" + name + ".gdshader")
		)
		assert(not shader.code.is_empty())
		originals[name] = shader
	var current := {}
	for mat in materials:
		current[mat] = mat.shader
	var rows := []
	for spatial in [false, true, true, false, true, false, false, true]:
		for mat in materials:
			mat.shader = (
				current[mat]
				if spatial
				else originals[
					"turf_cards" if mat == scene.turf_cards.material else "pixel_foliage"
				]
			)
			if spatial:
				wind.apply(mat)
		for frame in 8:
			await RenderingServer.frame_post_draw
		var samples := []
		for frame in 20:
			await RenderingServer.frame_post_draw
			samples.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
		samples.sort()
		rows.append(
			{
				"spatial": spatial,
				"gpu_median_ms": samples[10],
				"gpu_max_ms": samples[19],
				"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				"primitives": Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
			}
		)
	var off := 0.0
	var on := 0.0
	for row in rows:
		assert(row.draw_calls == rows[0].draw_calls and row.primitives == rows[0].primitives)
		if row.spatial:
			on += row.gpu_median_ms / 4
		else:
			off += row.gpu_median_ms / 4
	var report := {
		"passed": true,
		"pixel_mode": true,
		"resolution": "960x600",
		"baseline_source": baseline_path,
		"paired_mean_of_medians_ms": {"original_source": off, "spatial": on, "delta": on - off},
		"rows": rows,
		"boundary": "Short frozen-scene GPU comparison; no FPS or long-duration claim."
	}
	FileAccess.open("res://artifacts/spatial-wind/benchmark.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("WIND_BENCHMARK ", JSON.stringify(report))
	scene.free()
	quit()
