class_name ForestAnimalMotion
extends RefCounted

## Same Blender-authored curves deform GPU vertices and observer geometry.
static var curves: Dictionary = JSON.parse_string(
	FileAccess.get_file_as_string("res://data/animation/animal_motion.json")
)


static func sample(clip: String, time: float) -> PackedFloat32Array:
	var data: Dictionary = curves.clips[clip]
	var phase: float = fposmod(time / data.duration, 1) * (data.samples.size() - 1)
	var a := int(phase)
	var b: int = mini(a + 1, data.samples.size() - 1)
	var values := PackedFloat32Array()
	for c in curves.channels.size():
		values.append(lerpf(data.samples[a][c], data.samples[b][c], phase - a))
	return values


static func deform(
	point: Vector3,
	tag: Color,
	head: Vector3,
	pose: PackedFloat32Array,
	height: float,
	wing_hinge := Vector3.ZERO
) -> Vector3:
	var pivot := Vector3(tag.r, tag.g, tag.b)
	var role := int(round(tag.a))
	if role == 2:
		point = pivot + (point - pivot).rotated(Vector3.BACK, pose[2] * signf(pivot.x))
	if role == 1 or role == 2:
		point = head + (point - head).rotated(Vector3.RIGHT, pose[1])
	elif role == 3:
		point = (
			pivot + (point - pivot).rotated(Vector3.RIGHT, pose[0] * (1.0 if pivot.x < 0 else -1.0))
		)
	elif role == 4:
		point = pivot + (point - pivot).rotated(Vector3.UP, pose[5])
	elif role == 5:
		point = pivot + (point - pivot).rotated(Vector3.BACK, pose[6] * signf(pivot.x))
	elif role in [6, 7]:
		var side := signf(pivot.x)
		var flight := pose[7]
		if role == 7:
			point = (
				pivot + (point - pivot).rotated(Vector3.UP, side * lerpf(.45, .1 + pose[8], flight))
			)
			point = pivot + (point - pivot).rotated(Vector3.BACK, side * pose[8] * flight * .5)
		var shoulder := Vector3(side * wing_hinge.x, wing_hinge.y, wing_hinge.z)
		point = shoulder + (point - shoulder).rotated(Vector3.UP, side * 1.35 * (1 - flight))
		point = shoulder + (point - shoulder).rotated(Vector3.RIGHT, -.75 * (1 - flight))
		point = (
			shoulder + (point - shoulder).rotated(Vector3.BACK, side * lerpf(-.25, pose[6], flight))
		)
	elif role == 8:
		point = (
			pivot
			+ (point - pivot).rotated(
				Vector3.RIGHT, pose[0] * (1.0 if pivot.x < 0 else -1.0) + 1.20 * pose[7]
			)
		)
	if wing_hinge.x > 0:
		var center := Vector3(0, height * .52, 0)
		point = center + (point - center).rotated(Vector3.RIGHT, .55 * pose[7])
	point.y *= 1 + pose[3]
	point.y += pose[4] * height
	return point
