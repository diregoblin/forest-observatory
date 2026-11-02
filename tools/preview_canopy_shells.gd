extends "res://tools/preview_canopy_study.gd"

## Data-driven specimen fixture: preserve source modules and the normal world.
const SHELL_SHADER = preload("res://shaders/study_canopy_shells.gdshader")
const RADII = [1.0, .93, .86, .79]


func shell_mesh(definition: ForestPlantDefinition) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for module in definition.modules:
		assert(module.cluster_members == 1, "This fixture only uses unclustered modules")
		var foliage: bool = module.foliage and module.mesh is SphereMesh
		var body: Mesh = lobed_sphere() if foliage else module.mesh
		var arrays := body.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for index in module.count * module.whorls:
			var i: int = index % module.count
			var whorl := Basis(Vector3.UP, (index / module.count) * module.whorl_turn)
			var angle: float = float(i) * module.turn
			var offset: Vector3 = module.offset + module.step * float(i)
			offset += (
				Vector3(cos(angle), 0, sin(angle)) * (module.radial_offset + module.radial_step * i)
			)
			var scale_v: Vector3 = module.scale_start + module.scale_step * float(i)
			var rotation := (
				Basis(Vector3.UP, angle) * Basis.from_euler(module.rotation_degrees * PI / 180.0)
			)
			var transform := Transform3D(whorl * rotation.scaled(scale_v), whorl * offset)
			var normal_transform := transform.basis.inverse().transposed()
			var color: Color = module.color
			color.a = 0.0 if foliage else 1.0
			var layers: int = RADII.size() if foliage else 1
			for layer in layers:
				var radius: float = RADII[layer] if foliage else 1.0
				# Rotate layers in 3D, not just UV, to decorrelate the cutout holes.
				var spin := (
					Basis.from_euler(Vector3(.17, .49, -.13) * layer) if foliage else Basis.IDENTITY
				)
				for corner in indices:
					surface.set_color(color)
					surface.set_uv(uvs[corner] + Vector2(.213, .137) * i)
					surface.set_uv2(Vector2(float(layer) / maxf(1, layers - 1), 0))
					surface.set_normal((normal_transform * spin * normals[corner]).normalized())
					surface.add_vertex(transform * (spin * vertices[corner] * radius))
	return ForestPlantMeshBuilder.commit_indexed(surface)


func _run() -> void:
	output = "res://artifacts/canopy-shells"
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440, 900)
	root.msaa_3d = Viewport.MSAA_4X
	root.add_child(stage)
	Engine.max_fps = 30
	stage.add_child(camera)
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 32
	camera.far = 800
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	var env := environment.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("cacbb8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("a6b6b1")
	env.ambient_light_energy = .55
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
	label("Отдельные листовые пластины", 30)
	label("Четыре вложенные оболочки", 510)
	label("Те же оболочки · вид сбоку", 990)
	var cases: Array = JSON.parse_string(
		FileAccess.get_file_as_string("res://art/canopy-study/profiles.json")
	)
	for entry in cases:
		for node in root.get_children():
			if node is Label:
				node.visible = true
		var source: ForestPlantDefinition = load(entry.source)
		var original_bytes := var_to_bytes(
			ForestPlantMeshBuilder.build(source).surface_get_arrays(0)
		)
		for node in variants:
			node.free()
		var shells := shell_mesh(source)
		variants = [
			specimen(ForestPlantMeshBuilder.build(private_variant(source)), STUDY_SHADER, -16),
			specimen(shells, SHELL_SHADER, 0),
			specimen(shells, SHELL_SHADER, 16)
		]
		variants[2].rotation.y = PI / 2
		# Retain the old plate study's coarse shadow proxy, but the new shells
		# cast their own alpha-cutout shadows. This is a full-method comparison,
		# not a controlled isolated performance or albedo comparison.
		variants[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var proxy := specimen(
			ForestPlantMeshBuilder.build(private_variant(source, false)), STUDY_SHADER, -16
		)
		proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		variants.append(proxy)
		var image := Image.load_from_file(entry.mask)
		assert(image != null)
		image.generate_mipmaps()
		var texture := ImageTexture.create_from_image(image)
		for node in [variants[1], variants[2]]:
			node.material_override.set_shader_parameter("leaf_mask", texture)
			node.material_override.set_shader_parameter(
				"leaf_repeat", Vector2(entry.repeat[0], entry.repeat[1])
			)
		camera.position = Vector3(0, 20, 48)
		camera.look_at(Vector3(0, 7, 0))
		caption.text = "%s · пластины / оболочки / оболочки сбоку" % source.display_name
		sun.rotation_degrees = Vector3(-35, -55, 0)
		var left := await photo("%s-01-left-light" % source.species_id)
		sun.rotation_degrees = Vector3(-35, 55, 0)
		var right := await photo("%s-02-right-light" % source.species_id)
		var light_change := difference(left, right)
		assert(light_change > .002)
		variants[2].material_override.set_shader_parameter("cutouts_enabled", false)
		caption.text = "%s · справа контроль: без альфа-вырезов" % source.display_name
		var solid := await photo("%s-03-solid-control" % source.species_id)
		var cutout_change := difference(right, solid)
		assert(cutout_change > .002, "Alpha mask must cut actual holes, not just color the shell")
		variants[2].material_override.set_shader_parameter("cutouts_enabled", true)
		# Close views also inspect the silhouette from an actual side camera.
		for node in root.get_children():
			if node is Label and node != caption:
				node.visible = false
		for node in [variants[0], variants[1]]:
			node.visible = false
		for angle in [0.0, PI / 2, PI]:
			camera.size = 17
			camera.position = Vector3(16 + sin(angle) * 25, 10, cos(angle) * 25)
			camera.look_at(Vector3(16, 10, 0))
			caption.text = "%s · оболочки · камера %d°" % [source.display_name, rad_to_deg(angle)]
			await photo("%s-side-%03d" % [source.species_id, rad_to_deg(angle)])
		camera.size = 32
		assert(
			(
				original_bytes
				== var_to_bytes(ForestPlantMeshBuilder.build(source).surface_get_arrays(0))
			)
		)
		report.meshes[str(source.species_id)] = {
			"shell_triangles": shells.get_faces().size() / 3,
			"plate_triangles": variants[0].mesh.get_faces().size() / 3,
			"layers": RADII,
			"original_unchanged": true,
			"mask": entry.mask,
			"mask_coverage": entry.coverage,
			"light_change": light_change,
			"cutout_control_change": cutout_change
		}
	report.passed = true
	report.renderer = RenderingServer.get_current_rendering_method()
	report.boundary = (
		"Isolated shell study. No world/model/resource/save modified. "
		+ "Own cutout shadows; old plate control retains coarse shadow proxy."
	)
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("CANOPY_SHELLS ", JSON.stringify(report))
	stage.free()
	quit()
