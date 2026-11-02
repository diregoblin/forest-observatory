extends SceneTree

var scene
var active := false
var output := "res://artifacts/surface-hitches-current.json"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--active":
			active = true
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	_run.call_deferred()


func stats(samples: Array) -> Dictionary:
	var sorted := samples.duplicate()
	sorted.sort()
	return {
		"p50": sorted[sorted.size() / 2],
		"p95": sorted[ceili(sorted.size() * .95) - 1],
		"max": sorted[-1],
		"samples": samples
	}


func _run() -> void:
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	Engine.max_fps = 60
	var methods := {}
	var climate: Dictionary = scene._display_climate()
	for method in ["habitat", "soil", "fungi", "water", "hud"]:
		var samples := []
		for iteration in 8:
			var started := Time.get_ticks_usec()
			match method:
				"habitat":
					scene.habitat_view.refresh(climate)
				"soil":
					scene.terrain.refresh_ecology(scene.soil, scene.water, scene.groundcover)
					scene.terrain.refresh_traffic(scene.habitat)
				"fungi":
					scene.fungi.sync_fields()
				"water":
					scene.water.sync_fields()
					scene.water_view.refresh()
				"hud":
					scene._refresh_hud()
			samples.append(Time.get_ticks_usec() - started)
		methods[method] = stats(samples)
	var rows := []
	scene.paused = not active
	for view in [1, 2, 5]:
		scene._view(view)
		for i in 5:
			await RenderingServer.frame_post_draw
		var process := []
		var frame_ms := []
		var last := Time.get_ticks_usec()
		for i in 70:
			scene.camera.position.x += .03
			scene._process(1.0 / 60)
			process.append(scene.last_process_usec)
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			frame_ms.append((now - last) / 1000.0)
			last = now
		scene._finish_model_work(true)
		rows.append(
			{
				"view": view,
				"process_usec": stats(process),
				"frame_ms": stats(frame_ms),
				"can_draw": DisplayServer.window_can_draw(),
				"ticks": scene.ecology_clock.ticks,
				"water_s": scene.water.clock
			}
		)
	var report := {
		"methods_usec": methods,
		"rows": rows,
		"plants": scene.trees.species.size(),
		"paused": scene.paused,
		"renderer": RenderingServer.get_current_rendering_method(),
		"completed_ticks": scene.ecology_clock.ticks
	}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("SURFACE_PROFILE ", output, " ", methods)
	quit()
