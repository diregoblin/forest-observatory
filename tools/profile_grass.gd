extends "res://tools/preview_ground_turf.gd"

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")


func _initialize() -> void:
	output = "res://artifacts/grass-budget"
	super._initialize()


func _stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"samples": values,
		"n": values.size(),
		"mean": total / values.size(),
		"p50": sorted[sorted.size() / 2],
		"p95": sorted[ceili(sorted.size() * .95) - 1],
		"max": sorted[-1]
	}


func phase(label: String, mesh: Mesh, enabled: bool) -> Dictionary:
	var cards: ForestTurfCards = scene.turf_cards
	cards.visible = enabled
	cards.material.set_shader_parameter("plane_lod_enabled", label.ends_with("lod"))
	for patch in cards.patches.values():
		if label.ends_with("lod"):
			var key: Vector2i = cards.patches.find_key(patch)
			var distance_sq := cards._tile_distance_squared(key)
			patch.multimesh.mesh = cards.detail_meshes[
				2
				if distance_sq >= cards.FAR_M * cards.FAR_M
				else (1 if distance_sq >= cards.MID_M * cards.MID_M else 0)
			]
		else:
			patch.multimesh.mesh = mesh
	for frame in 8:
		await RenderingServer.frame_post_draw
	var gpu := []
	var cpu := []
	var primitives := []
	var unavailable := 0
	var started := Time.get_ticks_usec()
	for frame in 20:
		await RenderingServer.frame_post_draw
		var timing: Dictionary = scene.painterly_style.pixel_renderer.frame_times()
		gpu.append(timing.gpu_ms)
		cpu.append(timing.cpu_ms)
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		if not DisplayServer.window_can_draw():
			unavailable += 1
	assert(unavailable == 0)
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)
	return {
		"label": label,
		"paused": scene.paused,
		"drawn_frames": 28,
		"sample_wall_s": (Time.get_ticks_usec() - started) * .000001,
		"unavailable_frames": unavailable,
		"gpu_ms": _stats(gpu),
		"render_cpu_ms": _stats(cpu),
		"submitted_primitives": _stats(primitives),
		"world_viewport_size": scene.painterly_style.pixel_renderer.viewport.size,
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	}


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.atmosphere.set_process(false)
	scene.hud.visible = false
	scene.atmosphere.rain_particles.emitting = false
	Engine.max_fps = 15
	var frozen := model_bytes()
	var cards: ForestTurfCards = scene.turf_cards
	cards.set_process(false)
	scene.terrain.advance_ecology_display(1)
	var full := ForestTurfCards._mesh()
	var lod := cards.card_mesh
	assert(full.surface_get_arrays(0) == lod.surface_get_arrays(0))
	var rows := []
	for scenario in ["eye-pixel", "creek-pixel", "eye-fullres"]:
		scene.painterly_style.set_mode(1 if scenario == "eye-fullres" else 2)
		if scenario == "creek-pixel":
			scene.camera.view(2)
		else:
			var point := Vector3(200, scene.terrain.data.get_height(Vector3(200, 0, 196)), 196)
			scene.camera.position = point + Vector3(0, 1.65, 0)
			var target := point + Vector3(0, 0, -40)
			target.y = scene.terrain.data.get_height(target) + .5
			scene.camera.look_at(target)
		for frame in 45:
			cards._process(0)
		scene.painterly_style._process(0)
		# Return to both controls: a single noisy faster frame is not a win.
		for variant in ["off-a", "full-a", "lod", "full-b", "off-b"]:
			rows.append(
				await phase(
					scenario + "-" + variant,
					lod if variant == "lod" else full,
					not variant.begins_with("off")
				)
			)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"engine": Engine.get_version_info(),
		"seed": scene.settings.seed,
		"root_size": root.size,
		"fps_cap": Engine.max_fps,
		"unchanged_models": true,
		"rows": rows,
		"boundary": "Short paused isolated render timings, not simulation/frame/input FPS."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("GRASS_BUDGET PASS")
	scene.free()
	quit()
