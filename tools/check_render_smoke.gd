extends SceneTree

## A few paused Forward+ frames, not a performance or thermal-soak benchmark.
var output_dir := (
	"/run/media/pavel/Storage/Yandex.Disk/OpenClaw-workspace/" + "output/forest-gpu-guard-20261101"
)


func _initialize() -> void:
	create_timer(8).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	var world = load("res://scripts/forest.gd").new()
	world.paused = true
	root.add_child(world)
	world.set_process(false)
	Engine.max_fps = 30
	var before: Dictionary = world.trees.snapshot()
	var water_clock: float = world.water.clock
	var checked := 0
	for id in world.trees.species.size():
		var node: MultiMeshInstance3D = world.vegetation.batch_for(id)
		var slot: int = world.vegetation.member_slots[id]
		var shape: Dictionary = world.vegetation.selection_shape(id)
		assert(shape.transform.is_equal_approx(node.multimesh.get_instance_transform(slot)))
		assert(shape.foliage.size() * 3 == shape.faces.size())
		assert(is_equal_approx(shape.leaves, node.multimesh.get_instance_custom_data(slot).r))
		assert(node.multimesh.custom_aabb.encloses(shape.bounds.grow(-.0001)))
		checked += 1
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(
		root.get_texture().get_image().save_png(output_dir.path_join("optimized-valley.png")) == OK
	)
	world.camera.view(2)
	for frame in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(
		root.get_texture().get_image().save_png(output_dir.path_join("optimized-creek.png")) == OK
	)
	assert(world.trees.snapshot() == before and world.water.clock == water_clock)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"individuals_checked_against_gpu_buffers": checked,
		"spatial_batches": world.vegetation.tree_groups.size(),
		"model_unchanged": true,
		"viewport_timings_ms": world.painterly_style.pixel_renderer.frame_times(),
		"boundary": "Few paused Xvfb Forward+ frames; no watt/FPS/thermal-stability claim"
	}
	FileAccess.open(output_dir.path_join("render-smoke.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("RENDER_SMOKE ", JSON.stringify(report))
	quit()
