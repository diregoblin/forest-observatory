class_name ForestBotanicalGeometry
extends RefCounted


## All shapes are local, deterministic and species-independent. No camera axis.
static func append(
	surface: SurfaceTool, m: ForestPlantModule, pose: Transform3D, color: Color, low: bool
) -> void:
	if m.petiole_length > 0 and m.component_kind == &"flower":
		var attach := Vector3(0, pose.origin.y, 0)
		ForestCanopyGeometry.branch(
			surface,
			attach,
			pose.origin,
			Vector3.ZERO,
			.001,
			.0006,
			Color(.38, .44, .24, 1).srgb_to_linear(),
			low
		)
	match m.shape:
		"shoot":
			var end := Vector3(0, m.mesh.height, 0) + m.tip_offset
			ForestCanopyGeometry.branch(
				surface,
				pose.origin,
				pose * end,
				pose.basis * m.bend,
				m.mesh.bottom_radius * pose.basis.x.length(),
				m.mesh.top_radius * pose.basis.x.length(),
				color.srgb_to_linear(),
				low
			)
			for j in m.leaf_count:
				var t := lerpf(.22, .94, float(j) / maxf(1, m.leaf_count - 1))
				var anchor := ForestCanopyGeometry.curve(Vector3.ZERO, end, m.bend, t)
				var yaw := j * 2.39996323
				var tilt := Basis.from_euler(Vector3(-.25 + .16 * sin(j * 1.7), yaw, .08 * cos(j)))
				var size := (
					Vector3(m.leaf_size.x, m.leaf_size.y, m.leaf_size.y) * lerpf(1.12, .68, t)
				)
				_compound(
					surface,
					m,
					pose * Transform3D(tilt.scaled(size), anchor),
					Color(m.leaf_color, 0),
					low
				)
		"leaf_card":
			_compound(surface, m, pose, Color(color, 0), low)
		"star":
			for j in m.petal_count:
				var turn := Basis(Vector3.UP, TAU * j / m.petal_count)
				var p := pose * Transform3D(turn, Vector3.ZERO)
				for points in [
					[Vector3.ZERO, Vector3(-.3, .08, .52), Vector3(0, .16, 1)],
					[Vector3.ZERO, Vector3(0, .16, 1), Vector3(.3, .08, .52)]
				]:
					_triangle(surface, points, p, color, 1)
			_ball(
				surface,
				(
					pose
					* Transform3D(Basis.IDENTITY.scaled(Vector3(.22, .12, .22)), Vector3(0, .10, 0))
				),
				Color(.86, .66, .22, 0),
				1,
				low
			)
		"bell", "spur":
			_cup(surface, pose, color, low, m.shape == "spur")
		"aggregate":
			var rows := 3 if low else 4
			var sides := 5 if low else 7
			for row in rows:
				var t := float(row) / (rows - 1)
				var radius := lerpf(.58, .28, t)
				for j in sides:
					var a := TAU * j / sides + row * .45
					var center := Vector3(cos(a) * radius, -t * 1.2, sin(a) * radius)
					_bead(
						surface,
						pose * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * .30), center),
						color,
						2
					)
		"panicle":
			var count := maxi(5, m.cluster_members / (2 if low else 1))
			var tag := 1 if m.component_kind == &"flower" else 0
			for j in count:
				var t := (j + .5) / count
				var a := j * 2.39996323
				var radius := sqrt(t) * (1 - t * .6)
				var point := Vector3(cos(a) * radius, t * .65, sin(a) * radius)
				var start := Vector3(0, t * .4, 0)
				_rod(
					surface,
					pose * start,
					pose * point,
					pose.basis.x.length() * .010,
					Color(.38, .44, .22, 1),
					low
				)
				_bead(
					surface,
					pose * Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * .07), point),
					color,
					tag
				)


static func _compound(
	s: SurfaceTool, m: ForestPlantModule, pose: Transform3D, color: Color, low: bool
) -> void:
	if m.leaflet_pairs == 0:
		_card(s, pose, color, m.card_curve, m.card_fold, low)
	else:
		for j in m.leaflet_pairs:
			for sign_v in [-1, 1]:
				var t := .18 + j * .48 / maxf(1, m.leaflet_pairs)
				var basis := Basis(Vector3.UP, sign_v * 1.05).scaled(Vector3(.55, 1, .52))
				_card(
					s,
					pose * Transform3D(basis, Vector3(0, 0, t)),
					color,
					m.card_curve,
					m.card_fold,
					low
				)
		_card(
			s,
			pose * Transform3D(Basis.IDENTITY.scaled(Vector3(.65, 1, .60)), Vector3(0, 0, .55)),
			color,
			m.card_curve,
			m.card_fold,
			low
		)
	# Petiole / rachis shares the card's root and stays connected in side views.
	_rod(
		s,
		pose.origin,
		pose * Vector3(0, .003, .78),
		minf(.002, pose.basis.x.length() * .012),
		Color(.32, .42, .20, 1),
		low
	)


static func _card(
	s: SurfaceTool, pose: Transform3D, color: Color, curve: float, fold: float, low: bool
) -> void:
	var steps := 1 if low else (5 if pose.basis.z.length() > .45 else 2)
	for j in steps:
		for side in [-1, 1]:
			var a := float(j) / steps
			var b := float(j + 1) / steps
			var coords := [
				Vector2(.5, a),
				Vector2(.5 + .5 * side, a),
				Vector2(.5, b),
				Vector2(.5 + .5 * side, b)
			]
			var triangles := [[0, 2, 1], [1, 2, 3]] if side > 0 else [[0, 1, 2], [1, 3, 2]]
			for triangle in triangles:
				for k in triangle:
					var uv: Vector2 = coords[k]
					var x := uv.x - .5
					var t := uv.y
					var p := Vector3(x, curve * sin(PI * t) - absf(x) * fold, t)
					var normal := (
						Vector3(signf(x) * fold, 1, -curve * PI * cos(PI * t)).normalized()
					)
					s.set_color(color.srgb_to_linear())
					s.set_uv(Vector2(0, 3))
					s.set_uv2(Vector2(uv.x, 1 - uv.y))
					s.set_normal((pose.basis.inverse().transposed() * normal).normalized())
					s.add_vertex(pose * p)


static func _cup(s: SurfaceTool, pose: Transform3D, color: Color, low: bool, spur: bool) -> void:
	var sides := 6 if low else 10
	# Hollow lip: unlike a sphere this reads as a hanging bell or yellow trumpet.
	for j in sides:
		var a := j * TAU / sides
		var b := (j + 1) * TAU / sides
		for level in 3:
			var points := []
			for ij in [
				Vector2i(level, 0),
				Vector2i(level + 1, 0),
				Vector2i(level, 1),
				Vector2i(level + 1, 1)
			]:
				var t: float = ij.x / 3.0
				var angle := a if ij.y == 0 else b
				var radius: float = [.12, .48, .62, .45][ij.x]
				var p := Vector3(cos(angle) * radius, -t, sin(angle) * radius)
				if spur:
					p = Vector3(p.x, p.z * .7, .6 - t * 1.2)
				points.append(p)
			_triangle(s, [points[0], points[1], points[2]], pose, color, 1)
			_triangle(s, [points[2], points[1], points[3]], pose, color, 1)
	if spur:
		# A curved spur, not a second detached ball behind the blossom.
		ForestCanopyGeometry.branch(
			s,
			pose * Vector3(0, 0, -.6),
			pose * Vector3(0, -.3, -1.2),
			pose.basis * Vector3(.1, -.2, 0),
			pose.basis.x.length() * .14,
			.0003,
			color.srgb_to_linear(),
			low,
			1
		)


static func _triangle(
	s: SurfaceTool, points: Array, pose: Transform3D, color: Color, tag: int
) -> void:
	var normal: Vector3 = (points[1] - points[0]).cross(points[2] - points[0]).normalized()
	for p in points:
		s.set_color(color.srgb_to_linear())
		s.set_uv(Vector2(tag, 0))
		s.set_uv2(Vector2.ZERO)
		s.set_normal((pose.basis.inverse().transposed() * normal).normalized())
		s.add_vertex(pose * p)


static func _ball(s: SurfaceTool, pose: Transform3D, color: Color, tag: int, low: bool) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1
	mesh.height = 2
	mesh.radial_segments = 4 if low else 6
	mesh.rings = 1 if low else 2
	var arrays := mesh.surface_get_arrays(0)
	for i in arrays[Mesh.ARRAY_INDEX]:
		s.set_color(color.srgb_to_linear())
		s.set_uv(Vector2(tag, 0))
		s.set_uv2(Vector2.ZERO)
		s.set_normal(
			(pose.basis.inverse().transposed() * arrays[Mesh.ARRAY_NORMAL][i]).normalized()
		)
		s.add_vertex(pose * arrays[Mesh.ARRAY_VERTEX][i])


static func _rod(
	s: SurfaceTool, a: Vector3, b: Vector3, radius: float, color: Color, low: bool
) -> void:
	var axis := (b - a).normalized()
	var right := axis.cross(Vector3.FORWARD).normalized()
	if right.is_zero_approx():
		right = Vector3.RIGHT
	var up := axis.cross(right).normalized()
	var sides := 3 if low else 4
	for j in sides:
		var x := (right * cos(j * TAU / sides) + up * sin(j * TAU / sides)) * radius
		var y := (right * cos((j + 1) * TAU / sides) + up * sin((j + 1) * TAU / sides)) * radius
		_triangle(s, [a + x, b + x * .35, a + y], Transform3D.IDENTITY, color, 0)
		_triangle(s, [a + y, b + x * .35, b + y * .35], Transform3D.IDENTITY, color, 0)


static func _bead(s: SurfaceTool, pose: Transform3D, color: Color, tag: int) -> void:
	# Eight smoothly shaded triangles, sufficient for a tiny floret or drupelet.
	for sign_v in [-1, 1]:
		for j in 4:
			var points := [
				Vector3(0, sign_v, 0),
				Vector3(cos(j * PI / 2), 0, sin(j * PI / 2)),
				Vector3(cos((j + 1) * PI / 2), 0, sin((j + 1) * PI / 2))
			]
			for p in points:
				s.set_color(color.srgb_to_linear())
				s.set_uv(Vector2(tag, 0))
				s.set_uv2(Vector2.ZERO)
				s.set_normal((pose.basis.inverse().transposed() * p).normalized())
				s.add_vertex(pose * p)
