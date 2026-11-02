class_name ForestAnimalGeometry
extends RefCounted


## Unit-size anatomical volumes, shared by resource recipes, never species IDs.
## Local +Z is forward; leaf tips point +Y. All surfaces are closed volumes.
static func build(shape: String) -> ArrayMesh:
	var profile: Array[Vector4] = []  # axis position, X radius, other radius, bend
	var vertical := shape == "leaf"
	match shape:
		"barrel":
			profile = [
				Vector4(-.5, 0, 0, 0),
				Vector4(-.4, .32, .34, 0),
				Vector4(-.2, .49, .48, 0),
				Vector4(.1, .5, .5, .015),
				Vector4(.35, .35, .4, .02),
				Vector4(.5, 0, 0, .02)
			]
		"taper":
			profile = [
				Vector4(-.5, .33, .34, 0),
				Vector4(-.3, .5, .5, 0),
				Vector4(.15, .32, .32, -.04),
				Vector4(.5, .13, .19, -.07)
			]
		"leaf":
			profile = [
				Vector4(-.5, .12, .22, 0),
				Vector4(-.3, .4, .4, 0),
				Vector4(-.05, .5, .5, .015),
				Vector4(.2, .37, .36, .04),
				Vector4(.4, .14, .16, .07),
				Vector4(.5, 0, 0, .09)
			]
		"plume":
			profile = [
				Vector4(-.5, 0, 0, -.13),
				Vector4(-.34, .29, .3, -.1),
				Vector4(-.1, .5, .5, -.03),
				Vector4(.16, .44, .44, .04),
				Vector4(.36, .25, .27, .09),
				Vector4(.5, .1, .12, .1)
			]
		"feather":
			profile = [
				Vector4(-.5, 0, 0, 0),
				Vector4(-.33, .35, .35, 0),
				Vector4(-.03, .5, .5, .03),
				Vector4(.3, .3, .35, .04),
				Vector4(.5, .12, .15, .04)
			]
	assert(not profile.is_empty())
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(0)
	var sides := 8
	for j in range(profile.size() - 1):
		for i in sides:
			var a := _point(profile[j], i, sides, vertical)
			var b := _point(profile[j], i + 1, sides, vertical)
			var c := _point(profile[j + 1], i, sides, vertical)
			var d := _point(profile[j + 1], i + 1, sides, vertical)
			if vertical:
				_triangle(surface, a, c, b)
				_triangle(surface, b, c, d)
			else:
				_triangle(surface, a, b, c)
				_triangle(surface, b, d, c)
	for end in [0, profile.size() - 1]:
		var p: Vector4 = profile[end]
		var center := Vector3(0, p.x, p.w) if vertical else Vector3(0, p.w, p.x)
		for i in sides:
			var a := _point(p, i, sides, vertical)
			var b := _point(p, i + 1, sides, vertical)
			if (end == 0) != vertical:
				_triangle(surface, center, b, a)
			else:
				_triangle(surface, center, a, b)
	surface.generate_normals()
	surface.index()
	return surface.commit()


static func _point(p: Vector4, i: int, sides: int, vertical: bool) -> Vector3:
	var angle := TAU * i / sides
	if vertical:
		return Vector3(cos(angle) * p.y, p.x, sin(angle) * p.z + p.w)
	return Vector3(cos(angle) * p.y, sin(angle) * p.z + p.w, p.x)


static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	if (b - a).cross(c - a).length_squared() < 1e-14:
		return
	# Godot/Redot fronts are clockwise (SurfaceTool normals follow that winding).
	for point in [a, c, b]:
		surface.set_uv(Vector2.ZERO)
		surface.add_vertex(point)
