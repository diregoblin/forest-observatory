extends SceneTree

const OUTPUT := "res://art/plant-impostors"
const SIZE := Vector2i(64, 128)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	Engine.max_fps = 15
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var config: ForestSettings = load("res://data/forest.tres")
	var viewport := SubViewport.new()
	viewport.size = SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_4X
	root.add_child(viewport)
	var instance := MeshInstance3D.new()
	var camera := Camera3D.new()
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/plant_impostor_bake.gdshader")
	instance.material_override = material
	viewport.add_child(instance)
	viewport.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	var manifest := {}
	for definition in config.plants:
		var mesh := ForestPlantMeshBuilder.build(definition)
		ForestPlantMeshBuilder.set_canopy_material(definition, material)
		instance.mesh = mesh
		var bounds := mesh.get_aabb()
		var center := Vector3(0, bounds.get_center().y, 0)
		var horizontal := (
			maxf(
				maxf(absf(bounds.position.x), absf(bounds.end.x)),
				maxf(absf(bounds.position.z), absf(bounds.end.z))
			)
			* 2.1
		)
		var height := maxf(bounds.size.y * 1.05, horizontal * 2)
		camera.size = height
		var layers := []
		for pass_index in 4:
			var foliage := pass_index % 2 == 1
			var normals := pass_index >= 2
			material.set_shader_parameter("foliage_pass", foliage)
			material.set_shader_parameter("normal_pass", normals)
			var atlas := Image.create(SIZE.x * 4, SIZE.y, false, Image.FORMAT_RGBA8)
			for angle in 4:
				instance.rotation.y = angle * PI / 2
				camera.position = center + Vector3(0, 0, 20)
				camera.look_at(center)
				viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
				await RenderingServer.frame_post_draw
				var image := viewport.get_texture().get_image()
				# MSAA against transparent black returns premultiplied linear
				# RGB, stored as sRGB. Straight cutouts must not multiply it again.
				for y in image.get_height():
					for x in image.get_width():
						var pixel := image.get_pixel(x, y).srgb_to_linear()
						if pixel.a > .0001:
							pixel.r = clampf(pixel.r / pixel.a, 0, 1)
							pixel.g = clampf(pixel.g / pixel.a, 0, 1)
							pixel.b = clampf(pixel.b / pixel.a, 0, 1)
						image.set_pixel(x, y, pixel if normals else pixel.linear_to_srgb())
				# Colour/vector padding protects mip edges; alpha is unchanged.
				image.fix_alpha_edges()
				atlas.blit_rect(image, Rect2i(Vector2i.ZERO, SIZE), Vector2i(angle * SIZE.x, 0))
			var filename := (
				"%s-%s%s.png"
				% [
					definition.species_id,
					"leaf" if foliage else "stem",
					"-normal" if normals else ""
				]
			)
			assert(atlas.save_png(OUTPUT.path_join(filename)) == OK)
			layers.append(filename)
		manifest[str(definition.species_id)] = {
			"size": [height * .5, height],
			"center_y": center.y,
			"layers": layers,
			"mesh_hash": ForestPlantMeshBuilder.visual_hash(definition, mesh),
			"normal_encoding": "linear view-space XYZ, RGBA8; camera +Z, baked yaw n*pi/2"
		}
	FileAccess.open(OUTPUT.path_join("manifest.json"), FileAccess.WRITE).store_string(
		JSON.stringify(manifest, "  ")
	)
	print("IMPOSTOR_BAKE ", manifest.size(), " species, four azimuths, separate stem/leaf masks")
	quit()
