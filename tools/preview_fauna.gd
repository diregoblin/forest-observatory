extends "res://tools/check_fauna_geometry.gd"

var output := "res://artifacts/fauna-models"
var camera := Camera3D.new()
var specimens := []
var atmosphere := ForestAtmosphere.new()
var labels: Array[Label3D] = []


func _initialize() -> void:
	create_timer(55).timeout.connect(func(): quit(1))
	_run.call_deferred()


func photo(label: String) -> void:
	for frame in 3:
		await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(label + ".png")) == OK)


func _run() -> void:
	assert(RenderingServer.get_current_rendering_method() == "forward_plus")
	Engine.max_fps = 20
	root.size = Vector2i(1440, 900)
	DirAccess.make_dir_recursive_absolute(output)
	root.add_child(atmosphere)
	atmosphere.configure()
	atmosphere.world_env.background_mode = Environment.BG_COLOR
	atmosphere.world_env.background_color = Color("a9b6a6")
	atmosphere.world_env.fog_enabled = false
	atmosphere.world_env.glow_enabled = false
	atmosphere.world_env.ssao_radius = .4
	atmosphere.sun.rotation_degrees = Vector3(-35, -28, 0)
	atmosphere.sun.light_color = Color("fff0d0")
	root.add_child(camera)
	camera.current = true
	camera.fov = 35
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(100, 100)
	floor_node.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("778369")
	floor_mat.roughness = 1
	floor_node.material_override = floor_mat
	root.add_child(floor_node)
	var records := []
	for i in FAUNA.size():
		var s := specimen(FAUNA[i])
		var height: float = s.view.batches[0].multimesh.mesh.get_aabb().end.y
		s.view.scale = Vector3.ONE / height
		s.view.position.x = (i - 2) * 1.65
		s.view.refresh()
		s["frozen"] = s.model.snapshot()
		specimens.append(s)
		var label := Label3D.new()
		label.text = s.definition.display_name
		label.font_size = 38
		label.pixel_size = .0025
		label.position = Vector3((i - 2) * 1.65, -.015, .65)
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		root.add_child(label)
		labels.append(label)
		records.append(
			{
				"species": FAUNA[i],
				"triangles": s.view.mesh_faces[0].size() / 3,
				"scale": "equal height gallery"
			}
		)
	camera.position = Vector3(2.8, 2.5, 9)
	camera.look_at(Vector3(0, .48, 0))
	await photo("gallery-idle")
	for clip in ["walk", "hop", "feed", "alert", "sleep", "fly", "swim"]:
		for s in specimens:
			s.view._animate(0, clip, .27)
			assert(not s.view.selection_shape(0).is_empty())
		await photo("gallery-" + clip)
	for i in specimens.size():
		for j in specimens.size():
			specimens[j].view.visible = i == j
			labels[j].visible = i == j
		var s: Dictionary = specimens[i]
		s.view._animate(0, "idle", 0)
		var at: Vector3 = s.view.position + Vector3.UP * .5
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = maxf(
			1.7, s.view.batches[0].multimesh.mesh.get_aabb().size.z * s.view.scale.z * .9
		)
		camera.position = at + Vector3(1.45, .55, 2.4)
		camera.look_at(at)
		await photo(FAUNA[i] + "-front")
		camera.position = at + Vector3(-1.75, .35, -.5)
		camera.look_at(at)
		await photo(FAUNA[i] + "-side")
		assert(s.model.snapshot() == s.frozen)
	var report := {
		"passed": true,
		"renderer": "forward_plus",
		"all_eight_clips_rendered": true,
		"model_unchanged": true,
		"records": records,
		"boundary":
		"Equal-height paused specimens, not the real animal size ratios or an FPS measurement."
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FAUNA_PREVIEW PASS ", JSON.stringify(report))
	atmosphere.rain_particles.free()
	for child in root.get_children():
		child.free()
	await process_frame
	quit()
