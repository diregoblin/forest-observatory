extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")

var scene


func _initialize() -> void:
	create_timer(20).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _run() -> void:
	scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	scene.camera.set_process(false)
	var frozen: Dictionary = scene.trees.snapshot()
	# A busy model worker must not quantize the submitted wind phase. This
	# disposable sleeper owns no model writes; the main branch must still draw.
	var phase_before: float = scene.vegetation.wind_time_s
	scene.paused = false
	scene.use_model_worker = true
	scene.model_work_active = true
	assert(scene.model_thread.start(func(): OS.delay_msec(100)) == OK)
	for frame in 4:
		scene._process(.01)
		assert(scene.model_work_active, "Exercise the worker-busy early-return path")
		assert(absf(scene.vegetation.wind_time_s - phase_before - (frame + 1) * .01) < .000001)
	scene._finish_model_work(true)
	scene.paused = true
	scene._process(.01)
	assert(absf(scene.vegetation.wind_time_s - phase_before - .04) < .000001)
	assert(scene.vegetation.impostor_assets.size() == scene.settings.plants.size())
	# Building materials/mips must not mutate resources used by subsequent
	# species (several species share each source leaf mask), even on Dummy.
	scene.vegetation._rebuild_membership()
	assert(scene.vegetation.impostor_assets.size() == scene.settings.plants.size())
	scene.vegetation.refresh_trees(scene._display_climate())
	var v: ForestVegetation = scene.vegetation
	for key in v.impostor_groups:
		var near: MultiMeshInstance3D = v.tree_groups[key]
		var far: MultiMeshInstance3D = v.impostor_groups[key]
		var mid: MultiMeshInstance3D = v.mid_groups[key]
		assert(near.visibility_range_end == mid.visibility_range_begin)
		assert(mid.visibility_range_end == far.visibility_range_begin)
		assert(mid.visibility_range_end > mid.visibility_range_begin)
		assert(mid.material_override == near.material_override)
		assert(mid.multimesh.visible_instance_count == near.multimesh.visible_instance_count)
		assert(near.multimesh.visible_instance_count == far.multimesh.visible_instance_count)
		for slot in near.multimesh.visible_instance_count:
			assert(
				(
					mid.multimesh.get_instance_transform(slot)
					== near.multimesh.get_instance_transform(slot)
				)
			)
			assert(
				(
					mid.multimesh.get_instance_custom_data(slot)
					== near.multimesh.get_instance_custom_data(slot)
				)
			)
			assert(
				(
					near.multimesh.get_instance_transform(slot)
					== far.multimesh.get_instance_transform(slot)
				)
			)
			assert(
				(
					near.multimesh.get_instance_custom_data(slot)
					== far.multimesh.get_instance_custom_data(slot)
				)
			)
	# The HUD/follow bound encloses every exact posed triangle without building
	# those triangles itself. A deliberately tiny box fails the same check.
	var av: ForestAnimalsView = scene.animals_view
	for id in av.batches.size():
		var quick: AABB = av.display_shape(id).bounds.grow(.00001)
		var exact: Dictionary = av.selection_shape(id)
		for point in exact.faces:
			assert(quick.has_point(exact.transform * point))
	assert(not AABB(Vector3.ZERO, Vector3.ONE * .0001).encloses(av.display_shape(0).bounds))
	# Validate picking both the displayed billboard and its transparent padding.
	var chosen := -1
	for id in v.tree_count:
		if v.impostor_groups.has(v.member_groups[id]):
			chosen = id
			break
	assert(chosen >= 0)
	var key: Vector3i = v.member_groups[chosen]
	var center: Vector3 = v.batch_bounds[key].get_center()
	var mid: MultiMeshInstance3D = v.mid_groups[key]
	var near: MultiMeshInstance3D = v.tree_groups[key]
	var far: MultiMeshInstance3D = v.impostor_groups[key]
	scene.camera.position = (
		center + Vector3(0, 0, (near.visibility_range_end + mid.visibility_range_end) * .5)
	)
	var mid_shape: Dictionary = v.selection_shape(chosen)
	assert(mid_shape.faces == v.mid_geometry[key.x].faces)
	assert(mid_shape.faces.size() < v.selection_geometry[key.x].faces.size())
	assert(not mid_shape.has("accept_hit"), "Mid LoD is true 3D, not a billboard")
	scene.camera.position = (
		center + Vector3(0, 0, (mid.visibility_range_end + far.visibility_range_end) * .5)
	)
	var shape: Dictionary = v.selection_shape(chosen)
	assert(shape.has("accept_hit") and shape.faces.size() == 6)
	var asset: Dictionary = v.impostor_assets[key.x]
	var solid := false
	var clear := false
	for y in range(0, 128, 2):
		for x in range(0, 64, 2):
			var point := Vector3(
				((x + .5) / 64 - .5) * asset.mesh.size.x,
				(.5 - (y + .5) / 128) * asset.mesh.size.y,
				0
			)
			var hit: bool = shape.accept_hit.call(point)
			var origin: Vector3 = shape.transform * (point + Vector3.BACK)
			var ray: Vector3 = -shape.transform.basis.z.normalized()
			var distance := ForestObservation._shape_distance(shape, origin, ray, 10)
			if hit:
				assert(distance >= 0)
				solid = true
			else:
				assert(distance < 0)
				clear = true
	assert(solid and clear)
	for species in v.mid_geometry:
		assert(v.mid_geometry[species].faces.size() < v.selection_geometry[species].faces.size())
		assert(v.mid_geometry[species].foliage.has(0) and v.mid_geometry[species].foliage.has(1))
	scene.camera.position = center + Vector3(0, 0, far.visibility_range_end + 1)
	assert(v.selection_shape(chosen).is_empty())
	assert(scene.trees.snapshot() == frozen)
	if DisplayServer.get_name() != "headless":
		Engine.max_fps = 15
		for mode in 3:
			scene.painterly_style.set_mode(mode)
			scene.painterly_style._process(0)
			for distance in [
				12.0,
				(mid.visibility_range_begin + mid.visibility_range_end) * .5,
				(far.visibility_range_begin + far.visibility_range_end) * .5
			]:
				scene.camera.position = center + Vector3(0, 3, distance)
				scene.camera.look_at(center)
				for frame in 5:
					await RenderingServer.frame_post_draw
				assert(
					(
						root.get_texture().get_image().save_png(
							"res://artifacts/lod-%d-%d.png" % [mode, int(distance)]
						)
						== OK
					)
				)
	print(
		"PLANT_LOD_CHECK PASS: near/far state, alpha picking, posed display bounds, unchanged plants"
	)
	FileAccess.open("res://artifacts/plant-lod-check.json", FileAccess.WRITE).store_string(
		JSON.stringify({"passed": true, "species": v.impostor_assets.size(), "rebuilt": true})
	)
	scene.free()
	quit()
