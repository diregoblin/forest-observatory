class_name ForestVegetation
extends Node3D

# Presentation-only subdivision; field/model resolution is unchanged.
const BATCH_GRID := 8
const LOW_BATCH_GRID := 16

var rock_batch: MultiMeshInstance3D
var land: ForestLandscape
var water: ForestWatershed
var groundcover: ForestGroundcover
var rng := RandomNumberGenerator.new()
var tree_count := 0
var trees: ForestTrees
var tree_groups := {}
var tree_members := {}
var tree_materials := {}
var batch_bounds := {}
var displayed_tick := -1
var displayed_day := -1.0
var membership_count := -1
var selection_geometry: Dictionary = {}
var displayed_shapes: Dictionary = {}
var member_slots := PackedInt32Array()
var member_groups: Array[Vector3i] = []
var display_cursor := 0
var display_elapsed := 0.0
var last_batch_count := 0
var material_revision := 0
var impostor_groups := {}
var impostor_assets := {}
var impostor_manifest := {}
var mid_groups := {}
var mid_geometry := {}
var observer: Camera3D
var wind_time_s := 0.0
var wind_strength_display := 1.0
var wind_strength_target := 1.0
var wind_direction_display := Vector2.RIGHT
var wind_direction_target := Vector2.RIGHT


func build(
	l: ForestLandscape,
	w: ForestWatershed,
	plants: ForestGroundcover,
	model: ForestTrees,
	height_sampler := Callable()
) -> void:
	land = l
	water = w
	groundcover = plants
	trees = model
	var settings := land.settings
	rng.seed = land.settings.seed + 71
	var manifest_path := "res://art/plant-impostors/manifest.json"
	if FileAccess.file_exists(manifest_path):
		impostor_manifest = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	_rebuild_membership()
	var rocks: Array[Transform3D] = []
	for i in 550:
		var z := rng.randf_range(10, settings.extent - 10)
		var x := (
			land.channel_x(z) + rng.randf_range(-19, 19)
			if i < 400
			else rng.randf_range(15, settings.extent - 15)
		)
		var size := rng.randf_range(.3, 1.5)
		# Preserve RNG consumption, but orient the oval around the terrain normal.
		var tilt_x := rng.randf() * .18
		var yaw := rng.randf() * TAU
		var tilt_z := rng.randf() * .18
		var normal := (
			Vector3(
				land.height_at(x - .25, z) - land.height_at(x + .25, z),
				.5,
				land.height_at(x, z - .25) - land.height_at(x, z + .25)
			)
			. normalized()
		)
		var align := Basis(Quaternion(Vector3.UP, normal))
		var basis := (
			align
			* Basis.from_euler(Vector3(tilt_x, yaw, tilt_z))
			* Basis.from_scale(Vector3(size * 1.5, size * .75, size))
		)
		var center_y := INF
		# Bury the entire equatorial rim below the actual rendered bank. A centre
		# height alone leaves the downhill edge floating over a sloping surface.
		for k in 32:
			var angle := k * TAU / 32.0
			var rim := basis * Vector3(cos(angle), 0, sin(angle))
			var p := Vector3(x + rim.x, 0, z + rim.z)
			var height: float = (
				height_sampler.call(p) if height_sampler.is_valid() else land.height_at(p.x, p.z)
			)
			center_y = minf(center_y, height - rim.y - .06)
		rocks.append(Transform3D(basis, Vector3(x, center_y, z)))
	var rock := SphereMesh.new()
	rock.radial_segments = 16
	rock.rings = 8
	rock.radius = 1
	rock.height = 2
	rock.is_hemisphere = false
	rock_batch = _instance_group(rock, rocks, Color(.42, .43, .36), 0)


func _rebuild_membership() -> void:
	material_revision += 1
	for node in tree_groups.values():
		node.queue_free()
	for node in impostor_groups.values():
		node.queue_free()
	for node in mid_groups.values():
		node.queue_free()
	mid_groups.clear()
	mid_geometry.clear()
	impostor_groups.clear()
	impostor_assets.clear()
	displayed_shapes.clear()
	tree_groups.clear()
	tree_members.clear()
	tree_materials.clear()
	batch_bounds.clear()
	selection_geometry.clear()
	tree_count = 0
	member_slots.resize(trees.species.size())
	member_groups.resize(trees.species.size())
	for s in land.settings.plants.size():
		var definition: ForestPlantDefinition = land.settings.plants[s]
		var mesh := ForestPlantMeshBuilder.build(definition)
		selection_geometry[s] = {
			"mesh": mesh,
			"faces": mesh.get_faces(),
			"foliage": ForestPlantMeshBuilder.triangle_foliage(mesh),
			"bounds": mesh.get_aabb(),
			"uvs": ForestPlantMeshBuilder.triangle_uvs(mesh),
			"visual_hash": ForestPlantMeshBuilder.visual_hash(definition, mesh)
		}
		var mid_mesh := ForestPlantMeshBuilder.build(definition, true)
		mid_geometry[s] = {
			"mesh": mid_mesh,
			"faces": mid_mesh.get_faces(),
			"foliage": ForestPlantMeshBuilder.triangle_foliage(mid_mesh),
			"bounds": mid_mesh.get_aabb(),
			"uvs": ForestPlantMeshBuilder.triangle_uvs(mid_mesh)
		}
		for i in trees.species.size():
			if trees.species[i] != s:
				continue
			_append_to_batch(i)
	membership_count = trees.species.size()
	tree_count = membership_count
	displayed_tick = -1


func _batch_key(species: int, position: Vector3) -> Vector3i:
	var definition: ForestPlantDefinition = land.settings.plants[species]
	var grid := BATCH_GRID if definition.growth_form == &"tree" else LOW_BATCH_GRID
	var span := land.settings.extent / grid
	return Vector3i(species, floori(position.x / span), floori(position.z / span))


func batch_for(id: int) -> MultiMeshInstance3D:
	return tree_groups[member_groups[id]]


func _append_to_batch(id: int) -> void:
	var species := trees.species[id]
	var key := _batch_key(species, trees.positions[id])
	if not tree_groups.has(key):
		var definition: ForestPlantDefinition = land.settings.plants[species]
		var spots: Array[Transform3D] = []
		var node := _instance_group(
			selection_geometry[species].mesh, spots, Color.WHITE, definition.wind_strength, true
		)
		if tree_materials.has(species):
			node.material_override = tree_materials[species]
		else:
			node.material_override.set_shader_parameter("autumn_color", definition.autumn_color)
			ForestPlantMeshBuilder.set_canopy_material(definition, node.material_override)
			tree_materials[species] = node.material_override
		tree_groups[key] = node
		tree_members[key] = []
		# Full meshes nearby, existing model-driven groundcover at distance.
		# Small tiles let RenderingServer reject geometry AND shadow work;
		# discarding fragments in a shader would still process every vertex.
		_create_impostor(species, key, node)
		material_revision += 1
	var mm: MultiMesh = tree_groups[key].multimesh
	var slot: int = tree_members[key].size()
	if slot >= mm.instance_count:
		var buffer := mm.buffer
		mm.instance_count = maxi(16, mm.instance_count * 2)
		buffer.resize(mm.instance_count * 20)
		mm.buffer = buffer
	member_groups[id] = key
	member_slots[id] = slot
	tree_members[key].append(id)
	var shade := rng.randf_range(.75, 1.22)
	mm.set_instance_color(slot, Color(shade, shade, shade, 1))
	var transform := Transform3D(
		Basis(Vector3.UP, trees.yaw[id]).scaled(Vector3.ONE * trees.size[id]), trees.positions[id]
	)
	mm.set_instance_transform(slot, transform)
	mm.visible_instance_count = slot + 1
	for groups in [mid_groups, impostor_groups]:
		if not groups.has(key):
			continue
		var proxy: MultiMesh = groups[key].multimesh
		if proxy.instance_count != mm.instance_count:
			var buffer := proxy.buffer
			proxy.instance_count = mm.instance_count
			buffer.resize(proxy.instance_count * 20)
			proxy.buffer = buffer
		proxy.set_instance_transform(slot, transform)
		proxy.set_instance_color(slot, Color(shade, shade, shade, 1))
		proxy.visible_instance_count = slot + 1
	_include_bounds(key, transform * selection_geometry[species].bounds)


func _create_impostor(species: int, key: Vector3i, near: MultiMeshInstance3D) -> void:
	var definition: ForestPlantDefinition = land.settings.plants[species]
	var record: Dictionary = impostor_manifest.get(str(definition.species_id), {})
	# Missing/stale assets fall back to the complete mesh, never missing plants.
	if record.is_empty() or int(record.mesh_hash) != selection_geometry[species].visual_hash:
		return
	if not impostor_assets.has(species):
		var quad := QuadMesh.new()
		quad.size = Vector2(record.size[0], record.size[1])
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/plant_impostor.gdshader")
		var images := []
		for layer in 2:
			var texture: Texture2D = load("res://art/plant-impostors/" + record.layers[layer])
			var image: Image = texture.get_image().duplicate()
			images.append(image.duplicate())
			image.generate_mipmaps()
			mat.set_shader_parameter(
				"stem_atlas" if layer == 0 else "leaf_atlas", ImageTexture.create_from_image(image)
			)
		if record.layers.size() >= 4:
			for layer in 2:
				var normal_texture: Texture2D = load(
					"res://art/plant-impostors/" + record.layers[layer + 2]
				)
				var normal_image: Image = normal_texture.get_image().duplicate()
				normal_image.generate_mipmaps()
				mat.set_shader_parameter(
					"stem_normals" if layer == 0 else "leaf_normals",
					ImageTexture.create_from_image(normal_image)
				)
			mat.set_shader_parameter("normal_atlas_enabled", true)
		mat.set_shader_parameter("autumn_color", definition.autumn_color)
		mat.set_shader_parameter("center_y", record.center_y)
		mat.set_shader_parameter("canopy_enabled", definition.canopy_layers > 0)
		mat.set_shader_parameter("botanical_cards", definition.modules.any(func(m): return m.shape != "mesh"))
		impostor_assets[species] = {
			"mesh": quad, "material": mat, "images": images, "center_y": record.center_y
		}
	var asset: Dictionary = impostor_assets[species]
	var far := MultiMeshInstance3D.new()
	far.set_meta(&"plant_impostor", true)
	far.multimesh = MultiMesh.new()
	far.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	far.multimesh.use_colors = true
	far.multimesh.use_custom_data = true
	far.multimesh.mesh = asset.mesh
	far.material_override = asset.material
	# Full mesh -> low-tessellation 3D -> cutout. All three carry the exact
	# same finite plant IDs, poses, phenology and shared near/mid material.
	near.visibility_range_end = clampf(
		definition.reference_height_m * (8 if definition.growth_form == &"tree" else 25), 45, 110
	)
	var mid := _instance_group(mid_geometry[species].mesh, [], Color.WHITE, 0, true)
	mid.material_override = near.material_override
	mid.visibility_range_begin = near.visibility_range_end
	mid.visibility_range_end = minf(
		near.visibility_range_end * 2.5, clampf(definition.reference_height_m * 160, 220, 600) * .75
	)
	mid_groups[key] = mid
	far.visibility_range_begin = mid.visibility_range_end
	far.visibility_range_end = clampf(definition.reference_height_m * 160, 220, 600)
	far.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	far.extra_cull_margin = 3
	add_child(far)
	impostor_groups[key] = far


func _include_bounds(key: Vector3i, bounds: AABB) -> void:
	# Capacity slots contain zero transforms. Never let those invisible slots
	# drag every chunk's auto-AABB back to the world origin. Grow conservatively
	# with actual submitted geometry, including growth and fixture motion.
	var merged: AABB = batch_bounds[key].merge(bounds) if batch_bounds.has(key) else bounds
	if not batch_bounds.has(key) or merged != batch_bounds[key]:
		batch_bounds[key] = merged
		tree_groups[key].multimesh.custom_aabb = merged
		if mid_groups.has(key):
			mid_groups[key].multimesh.custom_aabb = merged
		if impostor_groups.has(key):
			impostor_groups[key].multimesh.custom_aabb = merged.grow(1)


func _instance_group(
	mesh: Mesh, spots: Array[Transform3D], tint: Color, wind: float, tree_enabled := false
) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = tree_enabled
	mm.mesh = mesh
	mm.instance_count = spots.size()
	if tree_enabled:
		mm.instance_count = maxi(16, spots.size() * 2)
		mm.visible_instance_count = spots.size()
	for i in spots.size():
		mm.set_instance_transform(i, spots[i])
		var shade := rng.randf_range(.75, 1.22)
		mm.set_instance_color(i, Color(shade, shade, shade, 1))
	node.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("base_color", tint)
	mat.set_shader_parameter("wind_strength", wind)
	mat.set_shader_parameter("tree_enabled", tree_enabled)
	node.material_override = mat
	node.extra_cull_margin = 3
	add_child(node)
	return node


func refresh_trees(climate: Dictionary) -> void:
	_sync_membership()
	if displayed_tick == trees.ticks and is_equal_approx(displayed_day, climate.day):
		return
	displayed_tick = trees.ticks
	displayed_day = climate.day
	for key in tree_groups:
		var definition: ForestPlantDefinition = land.settings.plants[key.x]
		var node: MultiMeshInstance3D = tree_groups[key]
		var members: Array = tree_members[key]
		var leaf := ForestClimate.leaves(definition, climate.day)
		var autumn := ForestClimate.autumn(definition, climate.day)
		for j in members.size():
			var i: int = members[j]
			_submit(i, node, j, leaf, autumn, 1.0)


func _sync_membership() -> void:
	if membership_count < 0:
		_rebuild_membership()
	var changed := membership_count != trees.species.size()
	# Stable append-only IDs: a seedling does not rebuild every species mesh.
	member_slots.resize(trees.species.size())
	member_groups.resize(trees.species.size())
	for i in range(membership_count, trees.species.size()):
		_append_to_batch(i)
	membership_count = trees.species.size()
	tree_count = membership_count
	if changed:
		displayed_tick = -1


func advance_display(dt: float, climate: Dictionary) -> void:
	display_elapsed += dt
	_sync_membership()
	var started := Time.get_ticks_usec()
	var leaves := PackedFloat64Array()
	var autumn := PackedFloat64Array()
	for definition in land.settings.plants:
		leaves.append(ForestClimate.leaves(definition, climate.day))
		autumn.append(ForestClimate.autumn(definition, climate.day))
	last_batch_count = 0
	# Bounded round-robin work, rather than all individuals on one half-second frame.
	while last_batch_count < mini(128, tree_count):
		var i := display_cursor % tree_count
		var s := trees.species[i]
		var previous: Dictionary = displayed_shapes.get(i, {})
		var weight := 1.0
		if not previous.is_empty():
			weight = 1.0 - exp(-(display_elapsed - previous.updated_at) / .25)
		_submit(i, batch_for(i), member_slots[i], leaves[s], autumn[s], weight)
		display_cursor = (i + 1) % tree_count
		last_batch_count += 1
		if Time.get_ticks_usec() - started >= 1200:
			break


func _submit(
	i: int, node: MultiMeshInstance3D, slot: int, leaf: float, autumn: float, weight: float
) -> void:
	leaf *= (1.0 - trees.stress[i] * .7) if trees.alive[i] else 0.0
	var d: ForestPlantDefinition = land.settings.plants[trees.species[i]]
	var fruit_fill := clampf(
		trees.fruit_c[i] / maxf(.000001, d.biomass_kg_c * pow(trees.size[i], 3) * .004), 0, 1
	)
	var state := Color(leaf, 1.0 - trees.stress[i], autumn, trees.alive[i] + fruit_fill * 2)
	var submitted := Transform3D(
		Basis(Vector3.UP, trees.yaw[i]).scaled(Vector3.ONE * trees.size[i]), trees.positions[i]
	)
	if trees.fallen[i]:
		submitted = trees.fallen_transform(i)
	if weight < 1.0:
		submitted = node.multimesh.get_instance_transform(slot).interpolate_with(submitted, weight)
		state = node.multimesh.get_instance_custom_data(slot).lerp(state, weight)
	node.multimesh.set_instance_transform(slot, submitted)
	node.multimesh.set_instance_custom_data(slot, state)
	for groups in [mid_groups, impostor_groups]:
		if groups.has(member_groups[i]):
			var proxy: MultiMesh = groups[member_groups[i]].multimesh
			proxy.set_instance_transform(slot, submitted)
			proxy.set_instance_custom_data(slot, state)
	var geometry: Dictionary = selection_geometry[trees.species[i]]
	_include_bounds(member_groups[i], submitted * geometry.bounds)
	displayed_shapes[i] = {
		"transform": submitted,
		"faces": geometry.faces,
		"foliage": geometry.foliage,
		"leaves": state.r,
		"uvs": geometry.uvs,
		"accept_triangle_hit": _canopy_hit.bind(trees.species[i]),
		"bounds": submitted * geometry.bounds,
		"updated_at": display_elapsed
	}


func selection_shape(id: int) -> Dictionary:
	# Pick exactly the last submitted MultiMesh state, never future model growth.
	var shape: Dictionary = displayed_shapes.get(id, {})
	if shape.is_empty() or observer == null or not impostor_groups.has(member_groups[id]):
		return shape
	var key := member_groups[id]
	var near: MultiMeshInstance3D = tree_groups[key]
	var distance := observer.global_position.distance_to(
		global_transform * batch_bounds[key].get_center()
	)
	if distance < near.visibility_range_end:
		return shape
	if distance < mid_groups[key].visibility_range_end:
		var geometry: Dictionary = mid_geometry[key.x]
		var result := shape.duplicate()
		result.faces = geometry.faces
		result.foliage = geometry.foliage
		result.uvs = geometry.uvs
		result.bounds = global_transform * shape.transform * geometry.bounds
		return result
	if distance > impostor_groups[key].visibility_range_end:
		return {}
	var asset: Dictionary = impostor_assets[key.x]
	var submitted: Transform3D = global_transform * shape.transform
	var to_camera := observer.global_position - submitted.origin
	var local_camera := submitted.basis.inverse() * to_camera
	var angle := posmod(roundi(-atan2(local_camera.x, local_camera.z) / (PI / 2)), 4)
	var scale := submitted.basis.y.length()
	var right := Vector3(to_camera.z, 0, -to_camera.x).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var basis := Basis(right, Vector3.UP, right.cross(Vector3.UP)).scaled(Vector3.ONE * scale)
	var pose := Transform3D(basis, submitted.origin + Vector3.UP * asset.center_y * scale)
	return {
		"transform": pose,
		"bounds": pose * asset.mesh.get_aabb().grow(.001),
		"faces": asset.mesh.get_faces(),
		"accept_hit": _impostor_hit.bind(asset, angle, shape.leaves)
	}


func _impostor_hit(point: Vector3, asset: Dictionary, angle: int, leaves: float) -> bool:
	var size: Vector2 = asset.mesh.size
	var uv := Vector2(point.x / size.x + .5, .5 - point.y / size.y)
	var image: Image = asset.images[0]
	var x := (
		clampi(int(uv.x * image.get_width() / 4), 0, image.get_width() / 4 - 1)
		+ angle * image.get_width() / 4
	)
	var y := clampi(int(uv.y * image.get_height()), 0, image.get_height() - 1)
	return (
		image.get_pixel(x, y).a > .35
		or (leaves >= .001 and asset.images[1].get_pixel(x, y).a > .35)
	)


func set_weather(climate: Dictionary) -> void:
	# Targets are submitted only while the composition root owns the models.
	wind_strength_target = clampf(climate.get("wind_m_s", 2.0) / 3, 0, 5)
	wind_direction_target = climate.get("wind_direction", Vector2.RIGHT)
	for species in tree_materials:
		var mat: ShaderMaterial = tree_materials[species]
		mat.set_shader_parameter(
			"snow_load", ForestTrees.snow_load_index(land.settings.plants[species], climate)
		)
		mat.set_shader_parameter(
			"bloom_fraction",
			ForestTrees.flower_fraction(land.settings.plants[species], climate.day)
		)
	for species in impostor_assets:
		impostor_assets[species].material.set_shader_parameter(
			"snow_load", ForestTrees.snow_load_index(land.settings.plants[species], climate)
		)


func advance_weather(dt: float) -> void:
	# Wind sway is presentation, not biological time. Never freeze it while
	# a worker owns the models, or advance it in half-second coupled-tick jumps.
	# Real-time phase also avoids ×600 turning a breeze into a stroboscope.
	wind_time_s += dt
	var weight := 1.0 - exp(-dt / .35)
	wind_strength_display = lerpf(wind_strength_display, wind_strength_target, weight)
	wind_direction_display = wind_direction_display.lerp(wind_direction_target, weight)
	for mat in tree_materials.values():
		mat.set_shader_parameter("weather_time", wind_time_s)
		mat.set_shader_parameter("weather_wind", wind_strength_display)
		mat.set_shader_parameter("weather_direction", wind_direction_display)


func _canopy_hit(uv: Vector2, shell: bool, species: int) -> bool:
	if not shell:
		return true
	return ForestPlantMeshBuilder.mask_hit(land.settings.plants[species], uv)
