class_name ForestCanopyGeometry
extends RefCounted

## Presentation-only shapes, consumed by the single plant mesh builder.
static var surfaces := {}


static func shell(mesh: Mesh, low: bool) -> Array:
	var key := Vector2i(mesh.get_instance_id(), int(low))
	if surfaces.has(key):
		return surfaces[key]
	var copy: Mesh = mesh.duplicate()
	if copy is SphereMesh:
		copy.radial_segments = 8 if low else 12
		copy.rings = 3 if low else 5
	elif copy is CylinderMesh:
		copy.radial_segments = 6 if low else 12
		copy.rings = 1 if low else 3
	var arrays := copy.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for i in vertices.size():
		var p := vertices[i]
		# A little irregularity, not a new spherical silhouette for conifers.
		var unit := p / maxf(mesh.get_aabb().size.length() * .35, .001)
		var displacement := .045 * sin(unit.x * 6 + unit.y * 2) * sin(unit.z * 7 - unit.y * 4)
		vertices[i] *= 1.0 + displacement
		# A smooth outward field; retain the primitive's proper ellipsoid/cone normals.
		normals[i] = normals[i].normalized()
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	surfaces[key] = arrays
	return arrays


static func curve(a: Vector3, b: Vector3, bend: Vector3, t: float) -> Vector3:
	return a.lerp(b, t) + bend * sin(PI * t)


static func branch(
	surface: SurfaceTool,
	a: Vector3,
	b: Vector3,
	bend: Vector3,
	radius: float,
	tip: float,
	color: Color,
	low: bool,
	component_tag := 0
) -> void:
	if a.distance_to(b) < .0001:
		return
	var steps := 3 if low else 5
	var sides := 4 if low else 6
	var rings: Array[PackedVector3Array] = []
	var ring_normals: Array[PackedVector3Array] = []
	var reference := (b - a).normalized().cross(Vector3.FORWARD).normalized()
	if reference.is_zero_approx():
		reference = Vector3.RIGHT
	for j in steps + 1:
		var t := float(j) / steps
		var center := curve(a, b, bend, t)
		var tangent := ((b - a) + bend * PI * cos(PI * t)).normalized()
		var right := (reference - tangent * tangent.dot(reference)).normalized()
		var forward := tangent.cross(right).normalized()
		var points := PackedVector3Array()
		var normals := PackedVector3Array()
		var r := lerpf(radius, tip, t)
		for k in sides:
			var angle := k * TAU / sides
			var n := right * cos(angle) + forward * sin(angle)
			points.append(center + n * r)
			normals.append((n + tangent * (radius - tip) / a.distance_to(b)).normalized())
		rings.append(points)
		ring_normals.append(normals)
	surface.set_color(color)
	surface.set_uv(Vector2(component_tag, 0))
	surface.set_uv2(Vector2.ZERO)
	for j in steps:
		for k in sides:
			var next := (k + 1) % sides
			for corner in [
				Vector2i(j, k),
				Vector2i(j + 1, k),
				Vector2i(j, next),
				Vector2i(j, next),
				Vector2i(j + 1, k),
				Vector2i(j + 1, next)
			]:
				surface.set_normal(ring_normals[corner.x][corner.y])
				surface.add_vertex(rings[corner.x][corner.y])
	# End caps avoid open tubes in a leafless or fallen tree.
	for end in [0, steps]:
		var normal := (a - b).normalized() if end == 0 else (b - a).normalized()
		for k in sides:
			var order := [k, (k + 1) % sides] if end == 0 else [(k + 1) % sides, k]
			for p in [
				curve(a, b, bend, float(end) / steps), rings[end][order[0]], rings[end][order[1]]
			]:
				surface.set_normal(normal)
				surface.add_vertex(p)
