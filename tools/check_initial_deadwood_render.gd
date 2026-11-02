extends SceneTree

## A few paused frames of unmodified new-world stocks, not a thermal soak.
var output := "res://artifacts/initial-deadwood-render"


func _initialize() -> void:
	create_timer(15).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	var world = load("res://scripts/forest.gd").new()
	world.paused = true
	root.add_child(world)
	world.set_process(false)
	world.camera.set_process(false)
	world.hud.visible = false
	Engine.max_fps = 30
	var frozen: Dictionary = world._world_snapshot().models
	var logs := 0
	var selected := -1
	var nearest := INF
	var clearing: Vector2 = world.settings.fungi_plot_centers[0] * world.settings.extent
	for id in world.trees.species.size():
		if not world.trees.fallen[id]:
			continue
		logs += 1
		var p: Vector3 = world.trees.positions[id]
		var distance := Vector2(p.x, p.z).distance_squared_to(clearing)
		if distance < nearest:
			nearest = distance
			selected = id
		var node: MultiMeshInstance3D = world.vegetation.batch_for(id)
		var slot: int = world.vegetation.member_slots[id]
		var pose: Transform3D = node.multimesh.get_instance_transform(slot)
		assert(pose.is_equal_approx(world.trees.fallen_transform(id)))
		assert(node.multimesh.get_instance_custom_data(slot).r == 0, "Dead logs have no leaves")
	assert(logs == 27 and selected >= 0)
	var pose: Transform3D = world.trees.fallen_transform(selected)
	var d: ForestPlantDefinition = world.settings.plants[world.trees.species[selected]]
	var center := pose * Vector3(0, d.reference_height_m * .35, 0)
	world.camera.position = center + pose.basis.x.normalized() * 7 + Vector3.UP * 5
	world.camera.look_at(center)
	world.painterly_style._process(0)
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join("initial-log.png")) == OK)
	assert(world._world_snapshot().models == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"initial_logs_in_gpu_buffers": logs,
		"photographed_id": selected,
		"position": str(world.trees.positions[selected]),
		"model_unchanged": true
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("INITIAL_DEADWOOD_RENDER ", JSON.stringify(report))
	quit()
