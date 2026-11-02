extends SceneTree
# gdlint: disable=max-line-length

var scene
var output := "res://artifacts/mosaic-fps-before.json"
var rows := []
var live := false
var baseline := false
var same_map := false
var compare := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--baseline":
			baseline = true
		if arg == "--same-map":
			same_map = true
		if arg == "--compare":
			compare = true
		if arg == "--live":
			live = true
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	create_timer(40).timeout.connect(func(): quit(1))
	_run.call_deferred()


func stats(values: Array) -> Dictionary:
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for value in values:
		total += value
	return {
		"mean": total / values.size(),
		"p95": sorted[ceili(values.size() * .95) - 1],
		"max": sorted[-1],
		"samples": values
	}


func phase(view: int, variant: String) -> void:
	for key in scene.vegetation.tree_groups:
		var node = scene.vegetation.tree_groups[key]
		var low: bool = scene.settings.plants[key.x].growth_form != &"tree"
		node.visible = not (variant == "no_low_plants" and low)
		node.cast_shadow = (
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if variant == "no_plant_shadows"
			else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		)
	for frame in 5:
		await RenderingServer.frame_post_draw
	var wall := []
	var process := []
	var gpu := []
	var calls := []
	var primitives := []
	var unavailable := 0
	var last := Time.get_ticks_usec()
	for frame in 120 if variant.begins_with("active") else 18:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		wall.append((now - last) / 1000.0)
		last = now
		process.append(scene.last_process_usec / 1000.0)
		gpu.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		unavailable += int(
			(
				not DisplayServer.window_can_draw()
				or DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED
			)
		)
	rows.append(
		{
			"view": view,
			"variant": variant,
			"wall_ms": stats(wall),
			"process_ms": stats(process),
			"gpu_ms": stats(gpu),
			"draw_calls": stats(calls),
			"primitives": stats(primitives),
			"unavailable": unavailable,
			"ticks": scene.ecology_clock.ticks,
			"water_s": scene.water.clock
		}
	)
	if variant == "all_repeat":
		root.get_texture().get_image().save_png(output.get_basename() + "-view-%d.png" % view)
	print(
		"MOSAIC_PHASE ",
		view,
		" ",
		variant,
		" wall=",
		stats(wall).mean,
		" gpu=",
		stats(gpu).mean,
		" process=",
		stats(process).mean
	)


func _run() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/forest.gd")
	var rollback := "/run/media/pavel/Storage/tmp/forest-fps-mosaic-20261101/before/scripts/"
	if baseline:
		source = FileAccess.get_file_as_string(rollback + "forest.gd")
		source = source.replace(
			"var vegetation := ForestVegetation.new()",
			"var vegetation: ForestVegetation = make_baseline_vegetation()"
		)
		var old_view := 'extends "res://scripts/vegetation.gd"\nfunc _batch_key(species: int, position: Vector3) -> Vector3i:\n\tvar span := land.settings.extent / BATCH_GRID\n\treturn Vector3i(species, floori(position.x / span), floori(position.z / span))\nfunc _create_impostor(_species: int, _key: Vector3i, _near: MultiMeshInstance3D) -> void:\n\tpass\n'
		source += (
			"\nfunc make_baseline_vegetation():\n\tvar s := GDScript.new()\n\ts.source_code = "
			+ JSON.stringify(old_view)
			+ "\n\tassert(s.reload() == OK)\n\treturn s.new()\n"
		)
	if same_map or baseline:
		var old_land := FileAccess.get_file_as_string(rollback + "landscape.gd")
		var method_start := old_land.find("func habitat_at(")
		var method_end := old_land.find("func stand_at(", method_start)
		var land_source := (
			'extends "res://scripts/landscape.gd"\n'
			+ old_land.substr(method_start, method_end - method_start)
		)
		source = source.replace(
			"var land := ForestLandscape.new(settings)",
			"var land: ForestLandscape = make_baseline_land()"
		)
		source += (
			"\nfunc make_baseline_land():\n\tvar s := GDScript.new()\n\ts.source_code = "
			+ JSON.stringify(land_source)
			+ "\n\tassert(s.reload() == OK)\n\treturn s.new(settings)\n"
		)
	var start := source.find("func _process(dt: float)")
	var end := source.find("func _finish_model_work", start)
	var process_source := source.substr(start, end - start)
	var calls := [
		"atmosphere.set_season(_display_climate())",
		"animals_view.refresh(clampf(ecology_clock.pending_s / settings.ecology_step_s, 0, 1))",
		"_refresh_observation()",
		"vegetation.advance_display(dt, _display_climate())",
		"habitat_view.refresh(_display_climate())",
		"_refresh_hud()"
	]
	for i in calls.size():
		var needle: String = calls[i]
		var lines := process_source.split("\n")
		for j in lines.size():
			if lines[j].strip_edges() != needle:
				continue
			var indent := lines[j].substr(0, lines[j].length() - lines[j].strip_edges().length())
			lines[j] = (
				indent
				+ "var profile_%d := Time.get_ticks_usec()\n" % i
				+ lines[j]
				+ "\n"
				+ indent
				+ (
					"stage_max[%d] = maxf(stage_max.get(%d, 0), Time.get_ticks_usec() - profile_%d)"
					% [i, i, i]
				)
			)
		process_source = "\n".join(lines)
	source = source.substr(0, start) + process_source + source.substr(end)
	source += "\nvar stage_max := {}\n"
	var instrumented := GDScript.new()
	instrumented.source_code = source
	assert(instrumented.reload() == OK)
	scene = instrumented.new()
	scene.paused = true
	root.add_child(scene)
	scene.camera.set_process(false)
	Engine.max_fps = 60
	var frozen: Dictionary = scene.trees.snapshot()
	for view in [1, 2, 5]:
		scene._view(view)
		for variant in (
			["all", "all_repeat"]
			if compare
			else ["all", "no_low_plants", "no_plant_shadows", "all_repeat"]
		):
			await phase(view, variant)
	assert(scene.trees.snapshot() == frozen)
	if live:
		scene.paused = false
		for view in [1, 5]:
			scene._view(view)
			await phase(view, "active")
		scene.observation.selected.clear()
		await phase(5, "active_no_selection")
		scene._finish_model_work(true)
	var report := {
		"rows": rows,
		"stage_max_usec": scene.stage_max,
		"plants": scene.trees.species.size(),
		"initial_plant_hash": hash(frozen),
		"baseline": baseline,
		"same_map": same_map or baseline,
		"window": DisplayServer.window_get_size(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"model_unchanged_in_paused_phases": true
	}
	FileAccess.open(output, FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	quit()
