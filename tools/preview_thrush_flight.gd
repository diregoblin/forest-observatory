extends "res://tools/check_fauna_geometry.gd"

var output := "res://artifacts/thrush-flight"
var camera := Camera3D.new()


func _initialize() -> void:
	create_timer(70).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	Engine.max_fps = 60
	root.size = Vector2i(1100, 720)
	DirAccess.make_dir_recursive_absolute(output.path_join("frames"))
	var atmosphere := ForestAtmosphere.new()
	root.add_child(atmosphere)
	atmosphere.configure()
	atmosphere.world_env.background_mode = Environment.BG_COLOR
	atmosphere.world_env.background_color = Color("a9b6a6")
	atmosphere.world_env.fog_enabled = false
	atmosphere.world_env.glow_enabled = false
	atmosphere.world_env.ssao_radius = .15
	atmosphere.sun.rotation_degrees = Vector3(-35, -28, 0)
	atmosphere.sun.light_color = Color("fff0d0")
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10, 10)
	floor_node.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("778369")
	mat.roughness = 1
	floor_node.material_override = mat
	root.add_child(floor_node)
	root.add_child(camera)
	camera.current = true
	camera.fov = 35
	camera.position = Vector3(.65, .55, 1.1)
	camera.look_at(Vector3(0, .30, 0))
	var s := specimen("thrush")
	var frozen: Dictionary = s.model.snapshot()
	var view: ForestAnimalsView = s.view
	var label := Label.new()
	label.position = Vector2(20, 16)
	label.add_theme_font_size_override("font_size", 22)
	root.add_child(label)
	for frame in 120:
		var t := frame / 30.0
		var flying := t >= .5 and t < 3.2
		view._animate(0, "fly" if flying else "idle", t)
		# Labelled rig fixture only: no fabricated points enter the animal model.
		view.position.y = .19 * smoothstep(.5, .9, t) * (1 - smoothstep(3.15, 3.55, t))
		view.displayed_transforms[0] = view.global_transform * view.submitted_transforms[0]
		label.text = "Дрозд · стенд анимации · " + ("полёт" if flying else "сложенные крылья")
		for wait_frame in 2:
			await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		assert(image.save_png(output.path_join("frames/%04d.png" % frame)) == OK)
		if frame in [6, 40, 43, 46, 49, 96, 116]:
			assert(image.save_png(output.path_join("pose-%03d.png" % frame)) == OK)
		var bounds: AABB = view.display_shape(0).bounds
		var shape := view.selection_shape(0)
		for i in range(0, shape.faces.size(), 31):
			assert(bounds.grow(.00001).has_point(shape.transform * shape.faces[i]))
	assert(s.model.snapshot() == frozen)
	var report := {
		"passed": true,
		"frames": 120,
		"fps": 30,
		"model_unchanged": true,
		"posed_selection_enclosed": true,
		"boundary": "Rig fixture with labelled presentation-only elevation, not a model trajectory."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("THRUSH_FLIGHT_PREVIEW PASS ", JSON.stringify(report))
	atmosphere.rain_particles.free()
	for child in root.get_children():
		child.free()
	await process_frame
	quit()
