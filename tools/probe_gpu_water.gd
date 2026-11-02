extends SceneTree

## Automatically exiting GPU SPH + forest assay. Main-device timestamps only;
## no submit/sync, CPU readback, or altered solver dispatch in the timed window.
const Settings = preload("res://modules/fluid/fluid_settings.gd")
const Effect = preload("res://modules/fluid/render/water_effect.gd")
var scene: Node3D
var output := "res://artifacts/water-gpu/"
var counts := [1024, 4096, 8192, 16384, 32768, 40000]
var samples := 24
var warmup := 12
var water_mode := true
var closeup := false
var draws := 0
var draw_times := []
var last_draw := 0
var timing := false
var phase_label := ""
var compute_samples := {}
var last_query_frame := -1
var effect: CompositorEffect
var lab_compositor: Compositor
var camera: Camera3D
var rd: RenderingDevice
var patch_origin := Vector3.ZERO


func _initialize() -> void:
	_run.call_deferred()


func _summary(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var ordered := values.duplicate()
	ordered.sort()
	var total := 0.0
	for value in values:
		total += value
	return {"mean": total / values.size(), "p50": ordered[values.size() / 2],
		"p95": ordered[ceili(values.size() * .95) - 1], "max": ordered.back()}


func _queries() -> void:
	var frame := rd.get_captured_timestamps_frame()
	if frame == last_query_frame:
		return
	last_query_frame = frame
	var points := {}
	var prefix := "forest-sph/" + phase_label + "/"
	for i in rd.get_captured_timestamps_count():
		var label := rd.get_captured_timestamp_name(i)
		if label.begins_with(prefix):
			points[label] = rd.get_captured_timestamp_gpu_time(i)
	for label: String in points:
		if label.ends_with("/begin"):
			var end := label.trim_suffix("/begin") + "/end"
			if points.has(end):
				compute_samples[label] = (points[end] - points[label]) / 1000000.0


func _draw() -> void:
	draws += 1
	if timing:
		var now := Time.get_ticks_usec()
		if last_draw > 0:
			draw_times.append((now - last_draw) / 1000.0)
		last_draw = now
	_queries()


func _new_sim(count: int) -> Node3D:
	var settings := Settings.new()
	settings.room_size = Vector3(24, 24, 24)
	settings.particle_radius = .05
	settings.fluid_volume = count / (Settings.REFERENCE_DENSITY / pow(.5, 3))
	settings.gravity = 9.81
	settings.viscosity = .35
	assert(settings.validation_error().is_empty())
	var sim: Node3D = load("res://modules/fluid/fluid_simulation.tscn").instantiate()
	sim.set_script(load("res://scripts/sph_river_probe.gd"))
	sim.settings = settings
	sim.position = patch_origin - Vector3(12, 0, 12)
	scene.add_child(sim)
	assert(sim.count == count and sim.diagnostic_positions.is_valid())
	sim.get_node("MultiMeshInstance3D").visible = not water_mode
	return sim


func _tick(sim: Node3D, sample: int = -1) -> float:
	var start := Time.get_ticks_usec()
	if sim != null:
		var prefix := "forest-sph/%s/%d/" % [phase_label, sample]
		if sample >= 0:
			rd.capture_timestamp(prefix + "begin")
		sim.sim_step(1.0 / 60.0)
		if sample >= 0:
			rd.capture_timestamp(prefix + "end")
		effect.capture_simulation_state()
	return (Time.get_ticks_usec() - start) / 1000.0


func _gravity_control() -> Dictionary:
	var sim := _new_sim(512)
	sim.pressure_multiply = 0.0
	sim.viscosity_multiplier = 0.0
	var initial: PackedVector4Array = sim.positions.duplicate()
	sim.sim_step(1.0 / 60.0)
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var positions := rd.buffer_get_data(sim.diagnostic_positions).to_float32_array()
	var velocities := rd.buffer_get_data(sim.diagnostic_velocities).to_float32_array()
	var max_position_error := 0.0
	var max_velocity_error := 0.0
	var expected_v := Vector3(0, -9.81 / 60.0, 0)
	for i in initial.size():
		var point := Vector3(positions[4*i], positions[4*i+1], positions[4*i+2])
		var velocity := Vector3(velocities[4*i], velocities[4*i+1], velocities[4*i+2])
		var before := Vector3(initial[i].x, initial[i].y, initial[i].z)
		max_position_error = maxf(max_position_error, point.distance_to(before + expected_v / 60.0))
		max_velocity_error = maxf(max_velocity_error, velocity.distance_to(expected_v))
	assert(max_position_error < .00001 and max_velocity_error < .00001)
	sim.queue_free()
	await process_frame
	return {"passed": true, "particles": 512, "pressure_disabled": true,
		"viscosity_disabled": true, "max_position_error_m": max_position_error,
		"max_velocity_error_m_s": max_velocity_error,
		"boundary": "Independent CPU semi-implicit gravity control; not pressure/viscosity or continuum validation"}


func _phase(count: int, label: String) -> Dictionary:
	phase_label = label
	compute_samples.clear()
	var sim: Node3D
	var start_surface_frames: int = effect.rendered_frames
	if count > 0:
		sim = _new_sim(count)
		effect.simulation = sim
		effect.capture_simulation_state()
		effect.enabled = water_mode
	for frame in warmup:
		_tick(sim)
		await process_frame
		await RenderingServer.frame_post_draw
	var cpu := []
	var render_gpu := []
	var unavailable := 0
	var minimized := 0
	var start_draws := draws
	draw_times.clear()
	last_draw = Time.get_ticks_usec()
	timing = true
	for sample in samples:
		cpu.append(_tick(sim, sample))
		await process_frame
		await RenderingServer.frame_post_draw
		render_gpu.append(scene.painterly_style.pixel_renderer.frame_times().gpu_ms)
		unavailable += int(not DisplayServer.window_can_draw())
		minimized += int(DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED)
	timing = false
	var frames := draw_times.duplicate()
	var completed_draws := draws - start_draws
	root.get_texture().get_image().save_png(output + label + ".png")
	# Retire timestamp queries before reading state/freeing the borrowed buffer.
	for frame in 4:
		await process_frame
		await RenderingServer.frame_post_draw
	var compute := compute_samples.values()
	var row := {"phase": label, "particles": count, "samples": samples,
		"completed_draws": completed_draws, "unavailable_draws": unavailable,
		"minimized_draws": minimized, "frame_ms": _summary(frames),
		"cpu_submit_ms": _summary(cpu), "compute_gpu_ms": _summary(compute),
		"compute_query_samples": compute.size(), "render_gpu_ms": _summary(render_gpu),
		"raw_frame_ms": frames, "raw_cpu_submit_ms": cpu,
		"raw_compute_gpu_ms": compute, "raw_render_gpu_ms": render_gpu,
		"watershed_s": scene.water.clock, "water_mode": water_mode}
	if sim != null:
		row["final_state"] = sim.diagnostics()
		row["boundary_samples"] = sim.boundary_count
		row["sdf_collision"] = sim.use_collision_sdf
		row["nominal_particle_volume_m3"] = sim.settings.fluid_volume
		row["surface_rendered_frames"] = effect.rendered_frames - start_surface_frames
		row["surface_failed"] = effect.failed
		effect.enabled = false
		effect.simulation = null
		effect.state_mutex.lock()
		effect.simulation_state.clear()
		effect.state_mutex.unlock()
		for frame in 4:
			await process_frame
			await RenderingServer.frame_post_draw
		sim.queue_free()
		await process_frame
	assert(unavailable == 0 and minimized == 0 and completed_draws == samples)
	if count > 0:
		assert(compute.size() == samples, "Incomplete GPU timestamp coverage")
		assert(not row.surface_failed)
		assert(not water_mode or row.surface_rendered_frames >= samples)
	print("GPU_WATER_PHASE ", label, " ", JSON.stringify({"frame":row.frame_ms,"compute":row.compute_gpu_ms}))
	return row


func _run() -> void:
	assert(DisplayServer.get_name() != "headless")
	for arg in OS.get_cmdline_user_args():
		if arg == "--particles":
			water_mode = false
		if arg == "--closeup":
			closeup = true
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=").trim_suffix("/") + "/"
		if arg.begins_with("--samples="):
			samples = int(arg.trim_prefix("--samples="))
		if arg.begins_with("--counts="):
			counts.clear()
			for value in arg.trim_prefix("--counts=").split(","):
				counts.append(int(value))
	assert(samples >= 18 and samples <= 120)
	assert(output.begins_with("res://artifacts/") and not ".." in output)
	DirAccess.make_dir_recursive_absolute(output)
	FileAccess.open(output + ".gdignore", FileAccess.WRITE).close()
	FileAccess.open(output + ".gitignore", FileAccess.WRITE).store_string("*\n")
	root.size = Vector2i(960, 600)
	rd = RenderingServer.get_rendering_device()
	scene = load("res://main.tscn").instantiate()
	scene.paused = true
	root.add_child(scene)
	Engine.max_fps = 60
	scene.hud.visible = false
	scene.camera.view(2)
	var z: float = scene.settings.extent * .64
	var x: float = scene.land.channel_x(z)
	patch_origin = Vector3(x, scene.land.height_at(x, z) + .8, z)
	if closeup:
		scene.camera.position = patch_origin + Vector3(8, 7, 11)
		scene.camera.look_at(patch_origin + Vector3(0, .3, 0))
	camera = scene.painterly_style.pixel_renderer.render_camera
	effect = Effect.new()
	effect.low_cost = true
	effect.enabled = false
	lab_compositor = Compositor.new()
	lab_compositor.compositor_effects = [effect]
	camera.compositor = lab_compositor
	RenderingServer.frame_post_draw.connect(_draw)
	var before: Dictionary = scene.water.native.snapshot().duplicate(true)
	var gravity_control := await _gravity_control()
	var rows := []
	rows.append(await _phase(0, "mesh-baseline"))
	for count in counts:
		assert(count > 0 and count <= 40000)
		var row := await _phase(count, "gpu-%d" % count)
		rows.append(row)
		# An unstable or already slow tier is a result; do not escalate its load.
		if row.final_state.invalid > 0 or row.final_state.outside_room > 0 or row.frame_ms.mean > 33.333:
			break
	rows.append(await _phase(0, "mesh-repeat"))
	assert(scene.water.native.snapshot() == before)
	var passed := true
	for row in rows:
		if row.particles > 0:
			passed = passed and row.final_state.invalid == 0 and row.final_state.outside_room == 0
	var report := {"passed": passed, "rows": rows,
		"gravity_control": gravity_control,
		"engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(),
		"window_px": root.size, "pixel_viewport_px": scene.painterly_style.pixel_renderer.viewport.size,
		"cap_fps": Engine.max_fps, "warmup_ticks": warmup, "measured_ticks": samples,
		"physics_step_s": 1.0 / 60.0, "forest_paused": scene.paused,
		"watershed_unchanged": true, "forest_individuals": scene.trees.species.size(),
		"closeup": closeup, "water_mode": water_mode, "water_quality": "low",
		"radius_m": .05, "room_m": Vector3(24, 24, 24), "gravity_m_s2": 9.81,
		"boundary": "Unchanged Night Shift GPU SPH + screen-space water, local independent slab in paused initial forest. Count increases nominal volume at fixed particle spacing. No terrain/stream mass coupling, calibrated material refinement, aged-forest ceiling, or long-soak claim."}
	FileAccess.open(output + "rendered.json", FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print("GPU_WATER_RESULT ", output + "rendered.json")
	RenderingServer.frame_post_draw.disconnect(_draw)
	quit(0 if passed else 1)
