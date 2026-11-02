extends SceneTree

## Three-way isolated study: same species/resources, not a live-world migration.
const OLD_SHADER = preload("res://shaders/painterly_foliage.gdshader")
const STUDY_SHADER = preload("res://shaders/study_canopy.gdshader")

var output := "res://artifacts/canopy-study"
var stage := Node3D.new()
var camera := Camera3D.new()
var sun := DirectionalLight3D.new()
var caption := Label.new()
var variants := []
var report := {"passed": false, "captures": [], "meshes": {}}


func _initialize() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	_run.call_deferred()


func displacement(p: Vector3) -> float:
	return .075 * sin(p.x * 6.0 + p.y * 2.0) * sin(p.z * 7.0 - p.y * 4.0)


func lobed_sphere() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1
	sphere.height = 2
	sphere.radial_segments = 16
	sphere.rings = 8
	var arrays := sphere.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		var p := vertices[i]
		var n := normals[i]
		var factor := 1 + displacement(p)
		var gradient := Vector3(
			.45 * cos(p.x * 6 + p.y * 2) * sin(p.z * 7 - p.y * 4),
			(
				.15 * cos(p.x * 6 + p.y * 2) * sin(p.z * 7 - p.y * 4)
				- .30 * sin(p.x * 6 + p.y * 2) * cos(p.z * 7 - p.y * 4)
			),
			.525 * sin(p.x * 6 + p.y * 2) * cos(p.z * 7 - p.y * 4)
		)
		vertices[i] = p * factor
		normals[i] = (n - (gradient - n * n.dot(gradient)) / factor).normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func leaf_cloud() -> ArrayMesh:
	var body := lobed_sphere()
	var arrays := body.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices:
		surface.set_normal(normals[index])
		surface.add_vertex(vertices[index])
	var random := RandomNumberGenerator.new()
	random.seed = 20261102
	var outline := [
		Vector2(-1, 0),
		Vector2(-.4, .48),
		Vector2(.4, .40),
		Vector2(1, 0),
		Vector2(.4, -.42),
		Vector2(-.5, -.35)
	]
	for i in 96:
		var y := 1.0 - 2.0 * (i + .5) / 96.0
		var angle := i * 2.39996323
		var n := Vector3(cos(angle) * sqrt(1 - y * y), y, sin(angle) * sqrt(1 - y * y))
		var tangent := n.cross(Vector3.UP).normalized()
		var second := n.cross(tangent)
		var rotation := random.randf() * TAU
		var right := tangent * cos(rotation) + second * sin(rotation)
		var up := n.cross(right)
		var center := n * (1.03 + displacement(n))
		var size := random.randf_range(.075, .15)
		# Fixed world geometry, not a camera-facing particle. Its smooth normal
		# mostly follows the crown, so it reads as one volume rather than shards.
		var leaf_normal := (n + right * random.randf_range(-.18, .18)).normalized()
		for edge in outline.size():
			for point in [Vector2.ZERO, outline[edge], outline[(edge + 1) % outline.size()]]:
				surface.set_normal(leaf_normal)
				surface.add_vertex(center + size * (right * point.x + up * point.y))
	return ForestPlantMeshBuilder.commit_indexed(surface)


func private_variant(definition: ForestPlantDefinition, cards := true) -> ForestPlantDefinition:
	var copy: ForestPlantDefinition = definition.duplicate(true)
	for module in copy.modules:
		if module.foliage and module.mesh is SphereMesh:
			module.mesh = leaf_cloud() if cards else lobed_sphere()
	return copy


func specimen(mesh: Mesh, shader: Shader, x: float) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.position.x = x
	var material := ShaderMaterial.new()
	material.shader = shader
	if shader == OLD_SHADER:
		material.set_shader_parameter("base_color", Color.WHITE)
		material.set_shader_parameter("wind_strength", 0.0)
	node.material_override = material
	stage.add_child(node)
	return node


func label(text: String, x: float) -> void:
	var node := Label.new()
	node.text = text
	node.position = Vector2(x, 785)
	node.add_theme_font_size_override("font_size", 20)
	node.add_theme_color_override("font_color", Color("f4efd5"))
	root.add_child(node)


func photo(name: String) -> Image:
	for frame in 6:
		await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	assert(image.save_png(output.path_join(name + ".png")) == OK)
	report.captures.append(name)
	return image


func difference(a: Image, b: Image) -> float:
	var sum := 0.0
	var count := 0
	for y in range(100, 770, 4):
		for x in range(960, 1390, 4):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			sum += absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)
			count += 3
	return sum / count


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 900)
	root.msaa_3d = Viewport.MSAA_4X
	root.add_child(stage)
	Engine.max_fps = 30
	stage.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.position = Vector3(0, 20, 48)
	camera.look_at(Vector3(0, 7, 0))
	camera.far = 800
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var env := environment.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cacbb8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a6b6b1")
	env.ambient_light_energy = .55
	env.ssao_enabled = false
	env.ssao_radius = 1.5
	env.ssao_intensity = .65
	stage.add_child(environment)
	stage.add_child(sun)
	sun.light_energy = 1.25
	sun.light_color = Color("fff2d5")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 100
	sun.light_angular_distance = 2.0
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(600, 600)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color("959977")
	ground.material_override = ground_mat
	stage.add_child(ground)
	caption.position = Vector2(34, 30)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_color", Color("34463f"))
	root.add_child(caption)
	label("Текущий живописный", 65)
	label("Палитра + свет / прежняя форма", 500)
	label("Объём + листовые мазки", 980)
	var light_differences := {}
	for species in ["birch", "oak"]:
		var source: ForestPlantDefinition = load("res://data/plants/%s.tres" % species)
		var original_mesh := ForestPlantMeshBuilder.build(source)
		var original_bytes := var_to_bytes(original_mesh.surface_get_arrays(0))
		var changed := private_variant(source)
		var changed_mesh := ForestPlantMeshBuilder.build(changed)
		assert(
			(
				original_bytes
				== var_to_bytes(ForestPlantMeshBuilder.build(source).surface_get_arrays(0))
			)
		)
		for node in variants:
			node.free()
		variants = [
			specimen(original_mesh, OLD_SHADER, -16),
			specimen(original_mesh, STUDY_SHADER, 0),
			specimen(changed_mesh, STUDY_SHADER, 16)
		]
		# Tiny leaf plates receive the canopy's coarse volume shadow; they do not
		# cast hundreds of noisy pinhole shadows on their own painted support.
		variants[2].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var shadow_copy := private_variant(source, false)
		var proxy := specimen(ForestPlantMeshBuilder.build(shadow_copy), STUDY_SHADER, 16)
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		variants.append(proxy)
		report.meshes[species] = {
			"before_triangles": original_mesh.get_faces().size() / 3,
			"study_triangles": changed_mesh.get_faces().size() / 3,
			"original_unchanged": true
		}
		caption.text = "%s · этюд крон · свет слева" % source.display_name
		sun.rotation_degrees = Vector3(-35, -55, 0)
		var left := await photo("%s-01-left-light" % species)
		caption.text = "%s · тот же материал · свет справа" % source.display_name
		sun.rotation_degrees = Vector3(-35, 55, 0)
		var right := await photo("%s-02-right-light" % species)
		var change := difference(left, right)
		assert(change > .002, "New crown must respond to changed real light direction")
		variants[2].material_override.set_shader_parameter("flat_normals", true)
		caption.text = "%s · справа контроль: одинаковые нормали" % source.display_name
		var flat := await photo("%s-03-flat-normal-control" % species)
		var normal_change := difference(right, flat)
		assert(normal_change > .002, "Normals must matter, not just an albedo pattern")
		light_differences[species] = {"light_change": change, "flat_normal_control": normal_change}
		variants[2].material_override.set_shader_parameter("flat_normals", false)
		caption.text = (
			"%s · собственная интерпретация, не копия шейдера демки" % source.display_name
		)
		camera.position = Vector3(23, 18, 48)
		camera.look_at(Vector3(0, 7, 0))
		await photo("%s-04-oblique" % species)
		camera.position = Vector3(0, 20, 48)
		camera.look_at(Vector3(0, 7, 0))
	report.passed = true
	report.renderer = RenderingServer.get_current_rendering_method()
	report.light_response = light_differences
	report.boundary = (
		"Isolated specimen study only. " + "No live-world material, species data or save changed."
	)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("CANOPY_STUDY ", JSON.stringify(report))
	stage.free()
	quit()
