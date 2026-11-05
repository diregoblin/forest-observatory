extends "res://tools/preview_ground_turf.gd"


func _initialize() -> void:
	output = "res://artifacts/spatial-wind"
	super._initialize()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(960, 600)
	Engine.max_fps = 20
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.capture_dir = ""
	scene._finish_model_work(true)
	scene.set_process(false)
	scene.camera.set_process(false)
	scene.hud.visible = false
	scene.atmosphere.rain_particles.emitting = false
	var frozen := model_bytes()
	var wind: ForestWindField = scene.vegetation.wind
	for step in 15:
		wind.advance(.1, Vector2(8, 2))
	for material in scene.vegetation.tree_materials.values():
		wind.apply(material)
	wind.apply(scene.turf_cards.material)
	# Sample the actual GPU helper, not a separate shader reimplementation.
	var probe := SubViewport.new()
	probe.size = Vector2i(16, 16)
	probe.disable_3d = true
	probe.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	probe.use_hdr_2d = true
	root.add_child(probe)
	var rect := ColorRect.new()
	rect.size = Vector2(16, 16)
	var material := ShaderMaterial.new()
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
#include "res://shaders/forest_wind.gdshaderinc"
uniform vec2 probe_position;
uniform float probe_height;
uniform bool deform_probe = false;
uniform mat4 probe_pose;
uniform vec3 probe_point;
void fragment() {
	vec2 v = forest_wind_velocity(vec3(probe_position.x,0,probe_position.y),probe_height);
	COLOR = vec4(v/10.0 + vec2(.5),0,1);
	if (deform_probe) {
		vec3 delta = forest_wind_vertex(probe_point,probe_pose,.035,1.0) - probe_point;
		COLOR = vec4(delta.xz*.5+vec2(.5),0,1);
	}
}
"""
	material.shader = shader
	wind.apply(material)
	rect.material = material
	probe.add_child(rect)
	var max_error := 0.0
	for test in [
		Vector3(0, 0, 0), Vector3(256, 1.5, 256), Vector3(177.3, 22, 288.1), Vector3(512, 0, 512)
	]:
		material.set_shader_parameter("probe_position", Vector2(test.x, test.z))
		material.set_shader_parameter("probe_height", test.y)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var pixel := probe.get_texture().get_image().get_pixel(8, 8)
		var measured := (Vector2(pixel.r, pixel.g) - Vector2.ONE * .5) * 30.0
		var expected := wind.sample_at(Vector2(test.x, test.z), test.y)
		max_error = maxf(max_error, measured.distance_to(expected))
		print(
			"WIND_GPU_PROBE ",
			test,
			" pixel=",
			pixel,
			" expected=",
			expected,
			" measured=",
			measured
		)
		assert(measured.distance_to(expected) < .04, "GPU / CPU field and shelter must agree")
	var max_bend_error := 0.0
	material.set_shader_parameter("deform_probe", true)
	for scale in [.5, 1.0, 1.8]:
		var pose := Transform3D(
			Basis(Vector3.UP, .73).scaled(Vector3.ONE * scale), Vector3(177.3, 0, 288.1)
		)
		var tip := Vector3(0, 14, 0)
		material.set_shader_parameter("probe_pose", pose)
		material.set_shader_parameter("probe_point", tip)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var pixel := probe.get_texture().get_image().get_pixel(8, 8)
		var measured := (Vector2(pixel.r, pixel.g) - Vector2.ONE * .5) * 2.0
		var delta := wind.deform(tip, pose, .035, 1.0) - tip
		max_bend_error = maxf(max_bend_error, measured.distance_to(Vector2(delta.x, delta.z)))
	assert(max_bend_error < .004, "GPU deformation must match CPU picking")
	probe.queue_free()
	var point := Vector3(0, 0, 0)
	var best := -INF
	for id in scene.trees.species.size():
		var d: ForestPlantDefinition = scene.settings.plants[scene.trees.species[id]]
		if d.growth_form != &"tree" or not scene.trees.alive[id]:
			continue
		var p: Vector3 = scene.trees.positions[id]
		var score: float = (
			scene.land.habitat_at(p.x, p.z).x - Vector2(p.x - 220, p.z - 230).length() * .002
		)
		if score > best:
			best = score
			point = p
	scene.camera.position = point + Vector3(10, 2.0, 13)
	scene.camera.look_at(point + Vector3(0, 4.5, 0))
	for frame in 30:
		await RenderingServer.frame_post_draw
	var changes := []
	for mode in 3:
		scene.painterly_style.set_mode(mode)
		for mat in scene.vegetation.tree_materials.values():
			mat.set_shader_parameter("spatial_wind_enabled", false)
		scene.turf_cards.material.set_shader_parameter("spatial_wind_enabled", false)
		await photo("style-%d-old" % mode, true)
		for mat in scene.vegetation.tree_materials.values():
			mat.set_shader_parameter("spatial_wind_enabled", true)
		scene.turf_cards.material.set_shader_parameter("spatial_wind_enabled", true)
		var first := await photo("style-%d-gust-0" % mode, true)
		for step in 40:
			wind.advance(.1, Vector2(8, 2))
		for mat in scene.vegetation.tree_materials.values():
			wind.apply(mat)
		wind.apply(scene.turf_cards.material)
		var second := await photo("style-%d-gust-4" % mode, true)
		var change := difference(first, second)
		assert(change > .00005, "A passing gust must visibly change plants with models frozen")
		changes.append(change)
	# A short fixed-camera sequence shows the movement, rather than relying on
	# two selected stills. All ecology remains paused throughout the assay.
	scene.painterly_style.set_mode(2)
	scene.camera.position = point + Vector3(5, 1.6, 9)
	scene.camera.look_at(point + Vector3(0, 1.2, 0))
	for step in 40:
		wind.advance(.1, Vector2(8, 2))
		for mat in scene.vegetation.tree_materials.values():
			wind.apply(mat)
		wind.apply(scene.turf_cards.material)
		for frame in 2:
			await RenderingServer.frame_post_draw
		assert(
			root.get_texture().get_image().save_png(output.path_join("frame-%03d.png" % step)) == OK
		)
	assert(model_bytes() == frozen)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"gpu_cpu_max_error_m_s": max_error,
		"gpu_cpu_bend_error_m": max_bend_error,
		"visible_change": changes,
		"unchanged_models": true,
		"camera_tree": point,
		"phases": phases,
		"boundary":
		(
			"Short paused Forward+ scene at 960x600; world plus composition GPU time. "
			+ "No user saves or running windows changed."
		)
	}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SPATIAL_WIND_RENDER ", JSON.stringify(report))
	scene.free()
	quit()
