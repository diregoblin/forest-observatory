extends SceneTree

## Short rendered cost isolation; each frame is actually drawable, no model ticks.
var output := "res://artifacts/render-profile"
var draws := 0
var scene: Node3D
var legacy_water: MeshInstance3D


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile-output="):
			output = arg.trim_prefix("--profile-output=")
	DirAccess.make_dir_recursive_absolute(output)
	create_timer(15).timeout.connect(func(): quit(1))
	RenderingServer.frame_post_draw.connect(func(): draws += 1)
	_run.call_deferred()


func _summary(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"mean": total / values.size(),
		"p50": sorted[values.size() / 2],
		"p95": sorted[ceili(values.size() * .95) - 1],
		"samples": values
	}


func _phase(view: int, variant: String) -> Dictionary:
	var phase_started := Time.get_unix_time_from_system()
	legacy_water.visible = variant != "after"
	scene.water_view.visible = variant == "after"
	var before_draw := draws
	for frame in 5:
		await process_frame
		await RenderingServer.frame_post_draw
	var gpu := []
	var cpu := []
	var draw_calls := []
	var primitives := []
	var unavailable := 0
	var minimized := 0
	var measured_draw := draws
	var measured_start := Time.get_ticks_usec()
	for frame in 18:
		await process_frame
		await RenderingServer.frame_post_draw
		var times: Dictionary = scene.painterly_style.pixel_renderer.frame_times()
		gpu.append(times.gpu_ms)
		cpu.append(times.cpu_ms)
		draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		unavailable += int(not DisplayServer.window_can_draw())
		minimized += int(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)
	assert(unavailable == 0 and minimized == 0 and draws - measured_draw == 18)
	var measured_wall_ms := (Time.get_ticks_usec() - measured_start) / 1000.0
	if variant in ["before", "after"]:
		root.get_texture().get_image().save_png(
			output.path_join("view-%d-%s.png" % [view, variant])
		)
	return {
		"view": view,
		"variant": variant,
		"gpu_ms": _summary(gpu),
		"cpu_submit_ms": _summary(cpu),
		"draw_calls": _summary(draw_calls),
		"primitives": _summary(primitives),
		"draws": draws - before_draw,
		"unavailable": unavailable,
		"minimized": minimized,
		"paused": scene.paused,
		"started_unix_s": phase_started,
		"finished_unix_s": Time.get_unix_time_from_system(),
		"measured_draws": draws - measured_draw,
		"measured_wall_ms": measured_wall_ms,
		"completed_draw_fps": (draws - measured_draw) * 1000.0 / measured_wall_ms
	}


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	Engine.max_fps = 60
	var script := GDScript.new()
	var baseline_dir := (
		"/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/output/"
		+ "forest-optimization-20261101-v2"
	)
	script.source_code = (
		FileAccess
		. get_file_as_string(baseline_dir.path_join("before-water-view.gd.txt"))
		. replace("class_name ForestWaterView\n", "")
	)
	assert(script.reload() == OK)
	legacy_water = script.new()
	scene.add_child(legacy_water)
	legacy_water.configure(scene.water)
	var plant_state: Dictionary = scene.trees.snapshot()
	var animal_state: Dictionary = scene.animals.snapshot()
	var water_clock: float = scene.water.clock
	var rows := []
	for view in [1, 2, 5]:
		scene._view(view)
		for variant in ["before", "after", "before-repeat"]:
			rows.append(await _phase(view, variant))
	assert(scene.trees.snapshot() == plant_state)
	assert(scene.animals.snapshot() == animal_state and scene.water.clock == water_clock)
	var report := {
		"rows": rows,
		"plants": scene.trees.species.size(),
		"animals": scene.animals.species.size(),
		"cap_fps": Engine.max_fps,
		"window_size": DisplayServer.window_get_size(),
		"pixel_size": scene.painterly_style.pixel_renderer.viewport.size,
		"wet_chunks": scene.water_view.chunks.filter(func(c): return c.visible).size(),
		"total_chunks": scene.water_view.chunks.size(),
		"model_unchanged": true,
		"boundary": "Short paused render isolation, not thermal stability or active-world FPS"
	}
	FileAccess.open(output.path_join("profile.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("RENDER_PROFILE ", JSON.stringify(report))
	quit()
