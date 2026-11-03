extends ForestAnimals

# Frozen f6e8992 hash-index methods; test/benchmark only, never a production switch.
var bins := {}
var _insect_site_bins := {}


func _rebuild_bins() -> void:
	_insect_index_active = false
	species_members.clear()
	for _definition in definitions:
		species_members.append([])
	for id in species.size():
		species_members[species[id]].append(id)
	bins.clear()
	for id in plants.positions.size():
		if not plants.alive[id]:
			continue
		var key := _bin(plants.positions[id])
		if not bins.has(key):
			bins[key] = []
		bins[key].append(id)


func _nearby(point: Vector3, radius: float) -> Array:
	var result := []
	var center := _bin(point)
	var count := ceili(radius / BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			for id in bins.get(Vector2i(x, z), []):
				var offset: Vector3 = plants.positions[id] - point
				if Vector2(offset.x, offset.z).length_squared() <= radius * radius:
					result.append(id)
	return result


func _rebuild_insect_index() -> void:
	_insect_index_active = false
	_insect_site_bins.clear()
	if habitat == null:
		return
	# Sites/plant positions stay fixed during our step; finite food pools do not.
	# Index actual feeding points, not habitat-cell centres: a site can be off-centre.
	for k in habitat.insect_sites.size():
		var site: int = habitat.insect_sites[k]
		var point: Vector3 = plants.positions[site] if site >= 0 else habitat.center(k)
		var key := _bin(point)
		if not _insect_site_bins.has(key):
			_insect_site_bins[key] = []
		_insect_site_bins[key].append(k)
	_insect_index_active = true


func _nearby_insect_sites(point: Vector3, radius: float) -> Array:
	# Public/direct decisions outside a coupled step see fresh data without a cache.
	if not _insect_index_active:
		return range(habitat.insect_sites.size())
	var result := []
	var center := _bin(point)
	var count := ceili(radius / BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			result.append_array(_insect_site_bins.get(Vector2i(x, z), []))
	# The reference scans habitat IDs ascending; retain its exact equal-score tie.
	result.sort()
	return result
