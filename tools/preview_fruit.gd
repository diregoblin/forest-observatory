extends SceneTree

## Isolated morphology view: no ecosystem model or user saves are opened.
func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.24, .32, .38)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.73, .80, .91)
	env.environment.ambient_light_energy = .65
	stage.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -25, 0)
	light.light_color = Color(1, .87, .68)
	light.light_energy = 1.4
	stage.add_child(light)
	var camera := Camera3D.new()
	stage.add_child(camera)
	camera.current = true
	camera.fov = 42
	var suffix := "after"
	var resource_dir := "res://data/plants"
	var baseline_dir := ""
	var budget_report := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fruit-label="):
			suffix = arg.trim_prefix("--fruit-label=")
		if arg.begins_with("--fruit-resources="):
			resource_dir = arg.trim_prefix("--fruit-resources=")
		if arg.begins_with("--fruit-baseline="):
			baseline_dir = arg.trim_prefix("--fruit-baseline=")
	for identity in ["rowan", "guelder_rose"]:
		var definition: ForestPlantDefinition = load("%s/%s.tres" % [resource_dir, identity])
		var plant := MeshInstance3D.new()
		plant.mesh = ForestPlantMeshBuilder.build(definition)
		var vertices: int = plant.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
		budget_report[identity] = {"vertices": vertices}
		if not baseline_dir.is_empty():
			var original: ForestPlantDefinition = load("%s/%s.tres" % [baseline_dir, identity])
			var baseline_mesh := ForestPlantMeshBuilder.build(original)
			var before: int = baseline_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
			assert(vertices <= before, "Fruit fix must not exceed the original geometry budget")
			budget_report[identity]["baseline_vertices"] = before
		var material := StandardMaterial3D.new()
		material.vertex_color_use_as_albedo = true
		material.roughness = .92
		plant.material_override = material
		stage.add_child(plant)
		var height := definition.reference_height_m
		var target := Vector3(0, height * .65, 0)
		camera.position = target + Vector3(.8, .22, 1).normalized() * height * .86
		camera.look_at(target)
		for frame in 4:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(
			"res://artifacts/fruit-%s-%s.png" % [identity, suffix]
		)
		plant.queue_free()
		await process_frame
	print("FRUIT_PREVIEW renderer=", RenderingServer.get_current_rendering_method())
	print("FRUIT_GEOMETRY_BUDGET ", JSON.stringify(budget_report))
	FileAccess.open("res://artifacts/fruit-geometry-budget.json", FileAccess.WRITE).store_string(JSON.stringify(budget_report, "  "))
	quit()
