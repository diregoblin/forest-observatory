class_name ForestPlantMeshBuilder
extends RefCounted

static var mask_images := {}


static func build(definition: ForestPlantDefinition, low_detail := false) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_uv2(Vector2.ZERO)
	var stems: Array[Dictionary] = []
	var crowns: Array[Dictionary] = []
	for module in definition.modules:
		assert(module.mesh != null, "Plant module needs a mesh")
		if (
			(definition.branch_radius_m > 0 and module.component_kind == &"branch")
			or (definition.bark_markings > 0 and module.component_kind == &"bark_detail")
		):
			continue
		var component := module
		if low_detail:
			# Preserve every morphological module, its placement and phenotype
			# tags; reduce only primitive tessellation on a private copy.
			component = module.duplicate()
			component.mesh = _low_detail_mesh(module.mesh)
		for index in module.count * module.whorls:
			var i := index % module.count
			var whorl := Basis(Vector3.UP, (index / module.count) * module.whorl_turn)
			var angle := float(i) * module.turn
			var offset := module.offset + module.step * float(i)
			offset += (
				Vector3(cos(angle), 0, sin(angle))
				* (module.radial_offset + module.radial_step * float(i))
			)
			var scale_v := module.scale_start + module.scale_step * float(i)
			assert(scale_v.x > 0 and scale_v.y > 0 and scale_v.z > 0)
			var rotation := (
				Basis(Vector3.UP, angle) * Basis.from_euler(module.rotation_degrees * PI / 180.0)
			)
			var transform := Transform3D(whorl * rotation.scaled(scale_v), whorl * offset)
			var color := module.color
			color.a = 0.0 if module.foliage else 1.0  # Geometry tag, not transparency.
			surface.set_uv(
				Vector2(
					(
						2
						if module.component_kind == &"fruit"
						else (1 if module.component_kind == &"flower" else 0)
					),
					0
				)
			)
			if module.shape != "mesh":
				ForestBotanicalGeometry.append(surface, module, transform, color, low_detail)
			elif (
				definition.canopy_layers > 0
				and module.foliage
				and module.component_kind == &"ordinary"
			):
				_append_shells(surface, module, transform, color, definition, low_detail, index)
				crowns.append({"transform": transform, "bounds": module.mesh.get_aabb()})
			elif (
				definition.branch_radius_m > 0
				and not module.foliage
				and module.mesh is CylinderMesh
				and module.mesh.height > module.mesh.bottom_radius * 5
			):
				var a: Vector3 = transform * Vector3(0, -module.mesh.height * .5, 0)
				var b: Vector3 = transform * Vector3(0, module.mesh.height * .5, 0)
				var bend := Vector3(sin(index * 2.4), 0, cos(index * 2.4)) * a.distance_to(b) * .025
				ForestCanopyGeometry.branch(
					surface,
					a,
					b,
					bend,
					module.mesh.bottom_radius * transform.basis.x.length(),
					module.mesh.top_radius * transform.basis.x.length(),
					color,
					low_detail
				)
				stems.append({"a": a, "b": b, "bend": bend, "color": color})
			else:
				_append_cluster(surface, component, transform, color)
	if definition.branch_radius_m > 0:
		_append_scaffold(surface, stems, crowns, definition, low_detail)
	return commit_indexed(surface)


static func _low_detail_mesh(mesh: Mesh) -> Mesh:
	if mesh is CylinderMesh:
		var cylinder: CylinderMesh = mesh.duplicate()
		cylinder.radial_segments = mini(cylinder.radial_segments, 4)
		cylinder.rings = 0
		return cylinder
	if mesh is SphereMesh:
		var sphere: SphereMesh = mesh.duplicate()
		sphere.radial_segments = mini(sphere.radial_segments, 4)
		sphere.rings = 1
		return sphere
	return mesh


static func commit_indexed(surface: SurfaceTool) -> ArrayMesh:
	# Shared by plants, animals and fungi: retain every triangle and its attributes.
	surface.index()
	return surface.commit()


static func triangle_foliage(mesh: Mesh) -> PackedByteArray:
	# get_faces() expands indices. Its triangle tags must use the same order.
	var arrays := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null:
		indices = arrays[Mesh.ARRAY_INDEX]
	var corners := indices.size() if not indices.is_empty() else colors.size()
	var foliage := PackedByteArray()
	for corner in range(0, corners, 3):
		var vertex := indices[corner] if not indices.is_empty() else corner
		foliage.append(1 if colors[vertex].a < .5 else 0)
	return foliage


static func _append_cluster(
	surface: SurfaceTool, module: ForestPlantModule, transform: Transform3D, color: Color
) -> void:
	assert(module.cluster_members >= 1)
	if module.cluster_members == 1:
		_append(surface, module.mesh, transform, color)
		return
	for j in module.cluster_members:
		# A filled, shallow head, not another ring. All sampling is deterministic
		# in plant coordinates; camera motion cannot rearrange the fruit.
		var radius := sqrt((float(j) + .5) / module.cluster_members)
		var angle := float(j) * 2.39996323
		var point := Vector3(
			cos(angle) * radius * module.cluster_spread.x,
			-module.cluster_spread.y * (.25 + .75 * radius * radius),
			sin(angle) * radius * module.cluster_spread.z
		)
		var member := transform * Transform3D(Basis.IDENTITY, point)
		_append(surface, module.mesh, member, color)


static func _append(surface: SurfaceTool, mesh: Mesh, transform: Transform3D, color: Color) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_transform := transform.basis.inverse().transposed()
	surface.set_uv2(Vector2.ZERO)
	for index in indices:
		surface.set_color(color)
		surface.set_normal((normal_transform * normals[index]).normalized())
		surface.add_vertex(transform * vertices[index])


static func visual_hash(definition: ForestPlantDefinition, mesh: Mesh) -> int:
	return hash(
		[
			mesh.surface_get_arrays(0),
			definition.canopy_color,
			definition.bark_markings,
			definition.canopy_texture.get_image().get_data() if definition.canopy_texture else null
		]
	)


static func _append_shells(
	surface: SurfaceTool,
	module: ForestPlantModule,
	transform: Transform3D,
	color: Color,
	definition: ForestPlantDefinition,
	low: bool,
	seed_index: int
) -> void:
	var arrays := ForestCanopyGeometry.shell(module.mesh, low)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var normal_transform := transform.basis.inverse().transposed()
	var bounds := module.mesh.get_aabb()
	var radius := (
		(bounds.size.x * transform.basis.x.length() + bounds.size.z * transform.basis.z.length())
		* .25
	)
	var height := bounds.size.y * transform.basis.y.length() * .5
	# Average blade occupies ~8% of its tile. Integer repeats close the UV seam.
	var repeat := Vector2(
		maxf(1, roundf(TAU * radius * .08 / definition.canopy_leaf_span_m)),
		maxf(1, roundf(PI * (radius + height) * .5 * .08 / definition.canopy_leaf_span_m))
	)
	var layers := mini(2, definition.canopy_layers) if low else definition.canopy_layers
	for layer in layers:
		var depth := float(layer) / maxf(1, layers - 1)
		var radius_scale := 1.0 - .21 * depth
		var spin := (
			Basis.from_euler(Vector3(.17, .49, -.13) * layer)
			if module.mesh is SphereMesh
			else Basis(Vector3.UP, .49 * layer)
		)
		for index in indices:
			surface.set_color(color)
			surface.set_uv(Vector2(0, 1.0 + depth))
			surface.set_uv2(
				uvs[index] * repeat + Vector2(.213, .137) * seed_index + Vector2(2.37, 1.73) * depth
			)
			surface.set_normal((normal_transform * spin * normals[index]).normalized())
			surface.add_vertex(transform * (spin * vertices[index] * radius_scale))


static func _append_scaffold(
	surface: SurfaceTool,
	stems: Array[Dictionary],
	crowns: Array[Dictionary],
	definition: ForestPlantDefinition,
	low: bool
) -> void:
	if stems.is_empty():
		return
	for crown in crowns:
		var center: Vector3 = crown.transform.origin
		var nearest: Dictionary = stems[0]
		var anchor := Vector3.ZERO
		var distance := INF
		for stem in stems:
			var axis: Vector3 = stem.b - stem.a
			var t := clampf((center.y * .76 - stem.a.y) / maxf(.001, axis.y), .12, .94)
			var point := ForestCanopyGeometry.curve(stem.a, stem.b, stem.bend, t)
			if point.distance_to(center) < distance:
				nearest = stem
				anchor = point
				distance = point.distance_to(center)
		var bend := Vector3.UP * distance * .14
		var radius := minf(definition.branch_radius_m, maxf(.003, distance * .055))
		ForestCanopyGeometry.branch(
			surface, anchor, center, bend, radius, radius * .28, nearest.color, low
		)
		var fork := ForestCanopyGeometry.curve(anchor, center, bend, .7)
		for k in 3:
			var angle := k * TAU / 3 + center.y
			var local := Vector3(cos(angle) * .52, .22 - definition.branch_droop, sin(angle) * .52)
			var tip: Vector3 = crown.transform * (local * crown.bounds.size * .5)
			var twig_bend := Vector3.UP * fork.distance_to(tip) * (.12 + definition.branch_droop)
			ForestCanopyGeometry.branch(
				surface, fork, tip, twig_bend, radius * .44, radius * .055, nearest.color, low
			)


static func set_canopy_material(
	definition: ForestPlantDefinition, material: ShaderMaterial
) -> void:
	material.set_shader_parameter("canopy_enabled", definition.canopy_texture != null)
	material.set_shader_parameter("bark_markings", definition.bark_markings)
	if definition.canopy_texture != null:
		# Dummy/headless textures can return a shared Image. Mipmap generation
		# must not mutate source bytes or invalidate later species' atlas hashes.
		var image: Image = definition.canopy_texture.get_image().duplicate()
		image.generate_mipmaps()
		material.set_shader_parameter("canopy_texture", ImageTexture.create_from_image(image))
		material.set_shader_parameter("canopy_color", definition.canopy_color)


static func triangle_uvs(mesh: Mesh) -> PackedVector3Array:
	var arrays := mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var result := PackedVector3Array()
	for index in indices:
		result.append(Vector3(uv2[index].x, uv2[index].y, 1 if uv[index].y > .5 else 0))
	return result


static func mask_hit(definition: ForestPlantDefinition, uv: Vector2) -> bool:
	if definition.canopy_texture == null:
		return true
	var key := definition.canopy_texture.get_instance_id()
	if not mask_images.has(key):
		mask_images[key] = definition.canopy_texture.get_image()
	var image: Image = mask_images[key]
	# Bilinear level-zero sampling, same wrapped UVs as the near cutout shader.
	var p := (
		Vector2(fposmod(uv.x, 1), fposmod(uv.y, 1)) * Vector2(image.get_size()) - Vector2(.5, .5)
	)
	var x := floori(p.x)
	var y := floori(p.y)
	var fx := p.x - x
	var fy := p.y - y
	var a := image.get_pixel(posmod(x, image.get_width()), posmod(y, image.get_height())).a
	var b := image.get_pixel(posmod(x + 1, image.get_width()), posmod(y, image.get_height())).a
	var c := image.get_pixel(posmod(x, image.get_width()), posmod(y + 1, image.get_height())).a
	var d := image.get_pixel(posmod(x + 1, image.get_width()), posmod(y + 1, image.get_height())).a
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fy) >= .5
