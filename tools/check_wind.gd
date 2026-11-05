extends SceneTree

const CONFIG = preload("res://data/forest.tres")
var result := {"passed": false}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var field := ForestWindField.new()
	field.configure(CONFIG)
	var repeat := ForestWindField.new()
	repeat.configure(CONFIG)
	assert(field.seed_phase == repeat.seed_phase)
	var changed: ForestSettings = CONFIG.duplicate(true)
	changed.seed += 1
	var other := ForestWindField.new()
	other.configure(changed)
	assert(field.seed_phase != other.seed_phase)
	# Check transport independently: the same packet reaches a point two grid
	# cells downwind after the offset increases by that exact distance.
	var cell := field.extent / field.resolution
	var velocity := Vector2(6, 0)
	var a := field._image(Vector2.ZERO, velocity)
	var b := field._image(Vector2(cell * 2, 0), velocity)
	var backward := field._image(Vector2(-cell * 2, 0), velocity)
	var low := INF
	var high := -INF
	var wrong_error := 0.0
	for z in field.resolution:
		for x in range(field.resolution - 2):
			var value := a.get_pixel(x, z).r
			assert(absf(value - b.get_pixel(x + 2, z).r) < .00001)
			wrong_error += absf(value - backward.get_pixel(x + 2, z).r)
			low = minf(low, value)
			high = maxf(high, value)
	assert(high - low > 3, "Spatially uniform wind must fail the packet criterion")
	assert(wrong_error > 100, "Transport in the opposite direction must fail")
	result.packet_speed_range_m_s = [low, high]
	# GPU normalized texel centres vs CPU bilinear, including all clamped edges.
	var ramp := Image.create(4, 4, false, Image.FORMAT_RGF)
	for z in 4:
		for x in 4:
			ramp.set_pixel(x, z, Color(x, z, 0))
	assert(ForestWindField.bilinear(ramp, Vector2(.5, .5)).is_equal_approx(Vector2(1.5, 1.5)))
	assert(ForestWindField.bilinear(ramp, Vector2(-1, -1)) == Vector2.ZERO)
	assert(ForestWindField.bilinear(ramp, Vector2(2, 2)) == Vector2(3, 3))
	assert(ForestWindField.bilinear(ramp, Vector2(.375, .625)) == Vector2(1, 2))
	var point := (
		Vector2.ONE * (CONFIG.extent * .5 + CONFIG.extent / CONFIG.wind_shelter_resolution * .5)
	)
	for id in 12:
		field.submit_canopy(id, point, 4.0, 14.0, 1.0)
	field.flush_shelter()
	field.previous = a
	field.current = a
	field.blend = 1.0
	var sheltered := field.sample_at(point, 1.5).length()
	var crown := field.sample_at(point, 14).length()
	assert(sheltered < crown * .5 and sheltered > crown * .19)
	var no_leaves := []
	for id in 12:
		field.submit_canopy(id, point, 4.0, 14.0, .15)
	field.flush_shelter()
	var bare := field.sample_at(point, 1.5).length()
	assert(bare > sheltered)
	for id in 12:
		field.submit_canopy(id, point, 4.0, 14.0, 0)
	field.flush_shelter()
	assert(absf(field.sample_at(point, 1.5).length() - crown) < .00001)
	assert(field.canopy.is_empty())
	result.shelter_m_s = {"leafy": sheltered, "bare": bare, "above_canopy": crown}
	# Zero forcing must remain zero even under a gust envelope.
	var calm := field._image(Vector2(12, 7), Vector2.ZERO)
	for z in calm.get_height():
		for x in calm.get_width():
			assert(calm.get_pixel(x, z).r == 0 and calm.get_pixel(x, z).g == 0)
	var timings := []
	for step in 60:
		field.advance(.1, velocity)
		timings.append(field.last_update_usec)
	var frozen := var_to_bytes(
		[
			field.elapsed_s,
			field.phase,
			field.blend,
			field.current.get_data(),
			field.previous.get_data()
		]
	)
	field.advance(0, Vector2(22, 0))
	assert(
		(
			frozen
			== var_to_bytes(
				[
					field.elapsed_s,
					field.phase,
					field.blend,
					field.current.get_data(),
					field.previous.get_data()
				]
			)
		)
	)
	timings.sort()
	result.field_update_usec = {"median": timings[30], "p95": timings[57], "max": timings[-1]}
	# Deformation is bounded in world units, including scaled and yawed plants;
	# roots and fallen plants must remain anchored.
	for scale in [.5, 1.0, 2.0]:
		var pose := Transform3D(
			Basis(Vector3.UP, .73).scaled(Vector3.ONE * scale), Vector3(point.x, 0, point.y)
		)
		assert(field.deform(Vector3.ZERO, pose, .03, 1) == Vector3.ZERO)
		var tip := Vector3(0, 20, 0)
		assert(field.deform(tip, pose, .03, 0) == tip)
		assert(
			(
				(pose.basis * (field.deform(tip, pose, .8, 1) - tip)).length()
				<= ForestWindField.MAX_BEND_M + .00001
			)
		)
	# A synthetic triangle verifies that picking tests the displaced shape,
	# rather than accepting its original silhouette by accident.
	var shape := {
		"bounds": AABB(Vector3(-2, -2, -1), Vector3(4, 4, 2)),
		"transform": Transform3D.IDENTITY,
		"faces": PackedVector3Array([Vector3(-.1, -.1, 0), Vector3(.1, -.1, 0), Vector3(0, .1, 0)]),
		"deform_vertex": func(p: Vector3): return p + Vector3.RIGHT
	}
	assert(ForestObservation._shape_distance(shape, Vector3(1, 0, 1), Vector3.FORWARD, 2) > 0)
	shape.erase("deform_vertex")
	assert(ForestObservation._shape_distance(shape, Vector3(1, 0, 1), Vector3.FORWARD, 2) < 0)
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.capture_dir = ""
	scene.set_process(false)
	scene.camera.set_process(false)
	var snapshots := {}
	for key in scene._world_models():
		snapshots[key] = scene._world_models()[key].snapshot()
	snapshots.erase("clock")  # The root legitimately queues wall-time requests while busy.
	var bytes := var_to_bytes(snapshots)
	var noise: AudioStreamWAV = ForestWindAudio.noise
	assert(noise.loop_mode == AudioStreamWAV.LOOP_FORWARD and noise.loop_end == noise.mix_rate * 3)
	var energy := 0.0
	var dc := 0.0
	var peak := 0.0
	for i in noise.data.size() / 2:
		var value := noise.data.decode_s16(i * 2) / 32768.0
		energy += value * value
		dc += value
		peak = maxf(peak, absf(value))
	var rms := sqrt(energy / (noise.data.size() / 2))
	print("WIND_AUDIO_CHECK rms=", rms, " peak=", peak, " dc=", dc / (noise.data.size() / 2))
	assert(rms > .1 and rms < .5 and peak < .999 and absf(dc / (noise.data.size() / 2)) < .01)
	result.noise = {"rms": rms, "peak": peak, "loop_seconds": noise.get_length()}
	var wind: ForestWindField = scene.vegetation.wind
	var before := wind.elapsed_s
	# Real worker-busy early return, with models deliberately inaccessible to
	# the vegetation view. Wind and audio may read only committed display state.
	scene.paused = false
	scene.use_model_worker = true
	scene.model_work_active = true
	assert(scene.model_thread.start(func(): OS.delay_msec(300)) == OK)
	var model = scene.vegetation.trees
	scene.vegetation.trees = null
	for frame in 3:
		scene._process(.04)
		assert(scene.model_work_active)
	assert(absf(wind.elapsed_s - before - .12) < .000001)
	var ear: Vector3 = scene.camera.global_position
	var ground: float = scene.terrain.data.get_surface_height(ear)
	var expected_speed := wind.sample_at(Vector2(ear.x, ear.z), maxf(0, ear.y - ground)).length()
	assert(absf(scene.wind_audio.local_speed_m_s - expected_speed) < .00001)
	scene.vegetation.trees = model
	scene._finish_model_work(true)
	scene.paused = true
	var phase := wind.phase
	scene._process(.1)
	assert(wind.phase == phase and scene.wind_audio.stream_paused)
	snapshots.clear()
	for key in scene._world_models():
		snapshots[key] = scene._world_models()[key].snapshot()
	assert(snapshots.clock.ticks == 0 and is_equal_approx(snapshots.clock.pending_s, .12))
	snapshots.erase("clock")
	assert(var_to_bytes(snapshots) == bytes)
	result.committed_canopies = wind.canopy.size()
	assert(wind.canopy.size() > 100)
	result.worker_busy_detached = true
	result.authoritative_models_unchanged = true
	result.passed = true
	FileAccess.open("res://artifacts/wind-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(result, "  ")
	)
	print("WIND_CHECK ", JSON.stringify(result))
	scene.free()
	quit()
