extends "res://tools/preview_herb_shadows.gd"

var caption := Label.new()


func _initialize() -> void:
	output = "res://artifacts/understory-botanical"
	super._initialize()


func _clear_plants() -> void:
	for plant in plants:
		plant.free()
	plants.clear()


func _group(names: Array) -> void:
	_clear_plants()
	for i in names.size():
		_specimen(names[i], Vector3.ZERO)
		var mesh: Mesh = plants[-1].multimesh.mesh
		var scale_v := 1.0 / mesh.get_aabb().size.y
		plants[-1].multimesh.set_instance_transform(
			0,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3.ONE * scale_v),
				Vector3((i - (names.size() - 1) * .5) * 1.12, 0, 0)
			)
		)
	caption.text = " / ".join(names) + " · высота уравнена для сравнения"
	camera.position = Vector3(0, 1.5, 4.4)
	camera.look_at(Vector3(0, .45, 0))


func _difference(a: Image, b: Image) -> Dictionary:
	var sum := 0.0
	var changed := 0
	var count := 0
	# Above-ground leaf area in the two-specimen control, no captions or shadows on ground.
	for y in range(275, 455):
		for x in range(255, 430):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			var error := (absf(ca.r - cb.r) + absf(ca.g - cb.g) + absf(ca.b - cb.b)) / 3
			sum += error
			changed += int(error > .025)
			count += 1
	return {"mean_rgb_delta": sum / count, "changed_pixels": changed, "pixels": count}


func _run() -> void:
	_setup()
	caption.position = Vector2(22, 20)
	caption.add_theme_font_size_override("font_size", 19)
	caption.add_theme_color_override("font_color", Color("182e25"))
	root.add_child(caption)
	var groups := [
		["meadowsweet", "balsam", "raspberry"],
		["male_fern", "ostrich_fern", "bracken"],
		["wood_sorrel", "wood_anemone", "lily_of_valley", "tufted_hairgrass"]
	]
	var shaders := ["foliage", "painterly_foliage", "pixel_foliage"]
	for g in groups.size():
		_group(groups[g])
		for style in 3:
			for plant in plants:
				plant.material_override.shader = load("res://shaders/%s.gdshader" % shaders[style])
			await _photo("group-%d-style-%d" % [g, style])
		camera.position = Vector3(2.5, 1.4, 3.4)
		camera.look_at(Vector3(0, .45, 0))
		await _photo("group-%d-side" % g)
	# Same exact cutouts/poses for mid LoD and seasonal rendering.
	_group(groups[0])
	for i in plants.size():
		var d: ForestPlantDefinition = load("res://data/plants/%s.tres" % groups[0][i])
		plants[i].multimesh.mesh = ForestPlantMeshBuilder.build(d, true)
	await _photo("mid-lod")
	for plant in plants:
		plant.multimesh.set_instance_custom_data(0, Color(1, .8, 1, 3))
		plant.material_override.set_shader_parameter("bloom_fraction", 0.0)
	await _photo("autumn-fruit")
	for plant in plants:
		plant.multimesh.set_instance_custom_data(0, Color(0, 1, 0, 1))
	await _photo("winter-skeleton")
	# Tiny alternating sun rotations expose shadow acne without moving any geometry.
	_clear_plants()
	_specimen("meadowsweet", Vector3(-.6, 0, 0))
	_specimen("balsam", Vector3(.5, 0, 0))
	camera.position = Vector3(0, 1.15, 2.3)
	camera.look_at(Vector3(0, .5, 0))
	caption.text = "Контроль теней · те же неподвижные листья"
	var comparison := {}
	for bias in [.1, .3]:
		atmosphere.sun.shadow_bias = bias
		var frames: Array[Image] = []
		for j in 6:
			atmosphere.sun.rotation_degrees = Vector3(-28 + (.015 if j % 2 else 0), -38, 0)
			frames.append(await _photo("bias-%02d-frame-%d" % [roundi(bias * 10), j]))
		comparison[str(bias)] = _difference(frames[0], frames[1])
	# Real shader wind, not a time-varying alpha mask.
	for j in 6:
		for plant in plants:
			plant.material_override.set_shader_parameter("wind_strength", .035)
			plant.material_override.set_shader_parameter("weather_time", j * .35)
		await _photo("wind-%d" % j)
	var report := {
		"passed": true,
		"renderer": RenderingServer.get_current_rendering_method(),
		"sun_control": comparison,
		"records": records,
		"boundary":
		"Short Forward+ equal-height fixture and shader wind; not FPS or a thermal soak."
	}
	var file := FileAccess.open(output.path_join("report.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("BOTANICAL_PREVIEW ", JSON.stringify(comparison))
	_clear_plants()
	atmosphere.rain_particles.free()
	for child in root.get_children():
		child.free()
	await process_frame
	quit()
