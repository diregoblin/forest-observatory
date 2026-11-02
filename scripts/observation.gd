class_name ForestObservation
extends RefCounted

## One picking/inspection path for all model-owned individuals.
## Views supply immutable selection geometry, never ecological state.
var land: ForestLandscape
var groups: Dictionary = {}
var bins: Dictionary = {}
var records: Array[Dictionary] = []
var selected: Dictionary = {}
var bin_m := 16.0


func _init(landscape: ForestLandscape) -> void:
	land = landscape


func register_group(
	kind: StringName,
	model: RefCounted,
	shape: Callable,
	visible_ids := Callable(),
	display_shape := Callable()
) -> void:
	groups[kind] = {
		"model": model,
		"shape": shape,
		"visible_ids": visible_ids,
		"display_shape": display_shape if display_shape.is_valid() else shape
	}


func rebuild() -> void:
	bins.clear()
	records.clear()
	for kind in groups:
		var group: Dictionary = groups[kind]
		var ids: Variant = (
			group.visible_ids.call()
			if group.visible_ids.is_valid()
			else range(group.model.positions.size())
		)
		for id in ids:
			var shape: Dictionary = group.shape.call(id)
			if shape.is_empty():
				continue
			var bounds: AABB = shape.bounds
			var index := records.size()
			records.append({"kind": kind, "id": id, "shape": shape})
			var low := Vector2i(
				floori(bounds.position.x / bin_m), floori(bounds.position.z / bin_m)
			)
			var high := Vector2i(floori(bounds.end.x / bin_m), floori(bounds.end.z / bin_m))
			for z in range(low.y, high.y + 1):
				for x in range(low.x, high.x + 1):
					var key := Vector2i(x, z)
					if not bins.has(key):
						bins[key] = []
					bins[key].append(index)


func pick(origin: Vector3, direction: Vector3, maximum_m := 1200.0) -> Dictionary:
	direction = direction.normalized()
	var maximum := _terrain_distance(origin, direction, maximum_m)
	var tested: Dictionary = {}
	var best: Dictionary = {}
	var nearest := maximum
	# Spatial traversal only supplies candidates; closest actual mesh hit wins.
	var key := Vector2i(floori(origin.x / bin_m), floori(origin.z / bin_m))
	var step_x := 1 if direction.x > 0 else -1
	var step_z := 1 if direction.z > 0 else -1
	var delta_x := absf(bin_m / direction.x) if direction.x != 0 else INF
	var delta_z := absf(bin_m / direction.z) if direction.z != 0 else INF
	var next_x := (
		((key.x + (1 if step_x > 0 else 0)) * bin_m - origin.x) / direction.x
		if direction.x != 0
		else INF
	)
	var next_z := (
		((key.y + (1 if step_z > 0 else 0)) * bin_m - origin.z) / direction.z
		if direction.z != 0
		else INF
	)
	var distance := 0.0
	while distance <= nearest:
		for index in bins.get(key, []):
			if tested.has(index):
				continue
			tested[index] = true
			var record: Dictionary = records[index]
			var hit := _shape_distance(record.shape, origin, direction, nearest)
			if hit >= 0 and hit < nearest:
				nearest = hit
				best = {"kind": record.kind, "id": record.id}
		# Exact 2D grid traversal: a short corner crossing cannot be skipped.
		distance = minf(next_x, next_z)
		if not is_finite(distance):
			break
		if next_x <= next_z:
			key.x += step_x
			next_x += delta_x
		else:
			key.y += step_z
			next_z += delta_z
	selected = best
	return selected.duplicate()


func valid_selection(selection: Dictionary) -> bool:
	if selection.is_empty():
		return true
	return (
		selection.size() == 2
		and selection.get("kind") in groups
		and selection.get("id") is int
		and selection.id >= 0
		and selection.id < groups[selection.kind].model.positions.size()
	)


func describe() -> Dictionary:
	if selected.is_empty() or not valid_selection(selected):
		selected.clear()
		return {}
	var model = groups[selected.kind].model
	if (
		selected.id < 0
		or selected.id >= model.positions.size()
		or groups[selected.kind].display_shape.call(selected.id).is_empty()
	):
		selected.clear()
		return {}
	var result: Dictionary = model.inspect(selected.id).duplicate(true)
	result["kind"] = selected.kind
	result["id"] = selected.id
	result["position"] = model.positions[selected.id]
	return result


func bounds() -> AABB:
	if selected.is_empty() or not valid_selection(selected):
		return AABB()
	var shape: Dictionary = groups[selected.kind].display_shape.call(selected.id)
	return shape.get("bounds", AABB())


func _terrain_distance(origin: Vector3, direction: Vector3, maximum: float) -> float:
	var distance := 0.0
	while distance <= maximum:
		var p := origin + direction * distance
		if p.x >= 0 and p.z >= 0 and p.x < land.settings.extent and p.z < land.settings.extent:
			if p.y < land.height_at(p.x, p.z):
				var low := maxf(0, distance - .5)
				var high := distance
				for iteration in 20:
					var middle := (low + high) * .5
					var sample := origin + direction * middle
					if sample.y < land.height_at(sample.x, sample.z):
						high = middle
					else:
						low = middle
				return high
		distance += .5
	return maximum


static func _shape_distance(
	shape: Dictionary, origin: Vector3, direction: Vector3, maximum: float
) -> float:
	var box: AABB = shape.bounds
	if box.intersects_ray(origin, direction) == null:
		return -1.0
	if shape.has("parts"):
		var closest_part := maximum
		var found_part := false
		for part in shape.parts:
			var distance := _shape_distance(part, origin, direction, closest_part)
			if distance >= 0 and distance < closest_part:
				closest_part = distance
				found_part = true
		return closest_part if found_part else -1.0
	var transform: Transform3D = shape.transform
	var inverse := transform.affine_inverse()
	var local_origin := inverse * origin
	var local_direction := inverse.basis * direction
	var vertices: PackedVector3Array = shape.get("faces", PackedVector3Array())
	if vertices.is_empty():
		var hit: Variant = box.intersects_ray(origin, direction)
		return origin.distance_to(hit) if hit is Vector3 else -1.0
	var foliage: PackedByteArray = shape.get("foliage", PackedByteArray())
	var leaves: float = shape.get("leaves", 1.0)
	var closest := maximum
	var found := false
	for j in range(0, vertices.size(), 3):
		if foliage.size() > j / 3 and foliage[j / 3] == 1 and leaves < .001:
			continue
		var point: Variant = Geometry3D.ray_intersects_triangle(
			local_origin, local_direction, vertices[j], vertices[j + 1], vertices[j + 2]
		)
		if point is Vector3:
			var triangle_accept: Callable = shape.get("accept_triangle_hit", Callable())
			if triangle_accept.is_valid():
				var uvs: PackedVector3Array = shape.uvs
				var bary := _barycentric(point, vertices[j], vertices[j + 1], vertices[j + 2])
				var value: Vector3 = uvs[j] * bary.x + uvs[j + 1] * bary.y + uvs[j + 2] * bary.z
				if not triangle_accept.call(Vector2(value.x, value.y), value.z > .5):
					continue
			var accept: Callable = shape.get("accept_hit", Callable())
			if accept.is_valid() and not accept.call(point):
				continue
			var distance := origin.distance_to(transform * point)
			if distance < closest:
				closest = distance
				found = true
	return closest if found else -1.0


static func _barycentric(p: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Vector3:
	var v0 := b - a
	var v1 := c - a
	var v2 := p - a
	var denom := v0.dot(v0) * v1.dot(v1) - v0.dot(v1) * v0.dot(v1)
	if absf(denom) < .000000000001:
		return Vector3(1, 0, 0)
	var y := (v1.dot(v1) * v2.dot(v0) - v0.dot(v1) * v2.dot(v1)) / denom
	var z := (v0.dot(v0) * v2.dot(v1) - v0.dot(v1) * v2.dot(v0)) / denom
	return Vector3(1 - y - z, y, z)
