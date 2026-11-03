extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")
const REFERENCE_BIN_M := 8.0
var reference_bins := {}
var reference_insects := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	var a = scene.animals
	var cases := 0
	for phase in 3:
		if phase == 1:
			for i in range(0, scene.trees.alive.size(), 7):
				scene.trees.alive[i] = 0
		elif phase == 2:
			# Appended IDs and multiple IDs in one bin retain their exact order.
			for i in 6:
				scene.trees._append(0, Vector3(8.01, 0, 8.01), .1, 0)
		a._rebuild_bins()
		rebuild_reference(a)
		for point in [
			Vector3(-9, 0, -9),
			Vector3.ZERO,
			Vector3(8, 0, 8),
			Vector3(511.99, 0, 511.99),
			Vector3(520, 0, 520)
		]:
			for radius in [0., 1.8, 7., 16., 22., 48.]:
				assert(a._nearby(point, radius) == nearby_reference(a, point, radius))
				cases += 1
		for id in a.positions.size():
			var radius: float = a.definitions[a.species[id]].sense_radius_m
			assert(
				a._nearby(a.positions[id], radius) == nearby_reference(a, a.positions[id], radius)
			)
			cases += 1
	# Exercise off-centre sites, bin boundaries and current step order separately.
	for k in scene.habitat.insect_sites.size():
		scene.habitat.insect_sites[k] = k * 17 % scene.trees.species.size() if k % 3 == 0 else -1
	a._rebuild_insect_index()
	rebuild_insects_reference(a)
	for id in a.positions.size():
		for radius in [1.8, 7., 16., 22., 48.]:
			assert(
				(
					a._nearby_insect_sites(a.positions[id], radius)
					== insects_reference(a, a.positions[id], radius)
				)
			)
			cases += 1
	var lifecycle_cases := check_domain_lifecycle(scene)
	var report := {
		"passed": true, "ordered_query_cases": cases, "domain_lifecycle_cases": lifecycle_cases
	}
	if OS.get_cmdline_user_args().has("--benchmark"):
		var samples := []
		for repeat_id in 9:
			var sample := {}
			# Alternate which side runs first to limit scheduler/order bias.
			for variant in ["flat", "hash"] if repeat_id % 2 else ["hash", "flat"]:
				var mark := Time.get_ticks_usec()
				for repetition in 10:
					for id in a.positions.size():
						var point: Vector3 = a.positions[id]
						var radius: float = a.definitions[a.species[id]].sense_radius_m
						if variant == "flat":
							a._nearby(point, radius)
							a._nearby_insect_sites(point, radius)
						else:
							nearby_reference(a, point, radius)
							insects_reference(a, point, radius)
				sample[variant] = Time.get_ticks_usec() - mark
			if repeat_id > 0:
				samples.append(sample)
		report["samples_us"] = samples
		report["queries_per_sample"] = 2 * 10 * a.positions.size()
		var build_samples := []
		for repeat_id in 5:
			var sample := {}
			for variant in ["flat", "hash"] if repeat_id % 2 else ["hash", "flat"]:
				var mark := Time.get_ticks_usec()
				for repetition in 10:
					if variant == "flat":
						a._rebuild_bins()
						a._rebuild_insect_index()
					else:
						rebuild_reference(a)
						rebuild_insects_reference(a)
				sample[variant] = Time.get_ticks_usec() - mark
			if repeat_id > 0:
				build_samples.append(sample)
		report["build_samples_us"] = build_samples
		report["builds_per_sample"] = 10
	FileAccess.open("res://artifacts/dense-bins-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("DENSE_BINS ", JSON.stringify(report))
	scene.free()
	quit()


func check_domain_lifecycle(scene) -> int:
	# Only exercise the derived spatial index here; do not advance a world with
	# remapped geometry. Actual coupled state/restore is checked by the other assays.
	var a = scene.animals
	var plants = scene.trees
	var habitat = scene.habitat
	var saved_positions: PackedVector3Array = plants.positions.duplicate()
	var saved_alive: PackedByteArray = plants.alive.duplicate()
	var saved_centers: PackedVector3Array = habitat.cell_centers.duplicate()
	var saved_sites: PackedInt32Array = habitat.insect_sites.duplicate()
	var extent: float = scene.settings.extent
	var cases := 0
	# Fractional last bins, one-bin world, shrink then regrow reused arrays.
	for test_extent in [509.5, 7.5, 520.25, extent]:
		scene.settings.extent = test_extent
		for id in plants.positions.size():
			plants.positions[id] = saved_positions[id] * (test_extent / extent)
		plants.positions[0] = Vector3.ZERO
		plants.positions[1] = Vector3(test_extent - .001, 0, test_extent - .001)
		for k in habitat.cell_centers.size():
			habitat.cell_centers[k] = saved_centers[k] * (test_extent / extent)
		habitat.insect_sites[0] = 0
		habitat.insect_sites[1] = 1
		for phase in 3:
			if phase == 0:
				plants.alive = saved_alive.duplicate()
			elif phase == 1:
				plants.alive.fill(0)
			else:
				plants.alive.fill(1)
			a._rebuild_bins()
			assert(not a._insect_index_active)
			a._rebuild_insect_index()
			rebuild_reference(a)
			rebuild_insects_reference(a)
			for point in [
				Vector3(-9, 0, -9),
				Vector3.ZERO,
				Vector3(8, 0, 8),
				Vector3(test_extent - .001, 0, test_extent - .001),
				Vector3(test_extent, 0, test_extent),
				Vector3(test_extent + 9, 0, test_extent + 9)
			]:
				for radius in [0., 1.8, 8., 48.]:
					assert(a._nearby(point, radius) == nearby_reference(a, point, radius))
					assert(
						a._nearby_insect_sites(point, radius) == insects_reference(a, point, radius)
					)
					cases += 2
	# Empty populations must not expose stale links after a reused index shrinks.
	plants.positions = PackedVector3Array()
	plants.alive = PackedByteArray()
	a._rebuild_bins()
	assert(a._nearby(Vector3.ZERO, extent).is_empty() and a._bin_next.is_empty())
	a.habitat = null
	a._rebuild_insect_index()
	assert(not a._insect_index_active)
	cases += 2
	scene.settings.extent = extent
	plants.positions = saved_positions
	plants.alive = saved_alive
	habitat.cell_centers = saved_centers
	habitat.insect_sites = saved_sites
	a.habitat = habitat
	a._rebuild_bins()
	a._rebuild_insect_index()
	rebuild_reference(a)
	rebuild_insects_reference(a)
	return cases


func rebuild_reference(a) -> void:
	reference_bins.clear()
	var plants = a.plants
	for id in plants.positions.size():
		if not plants.alive[id]:
			continue
		var key: Vector2i = bin_reference(plants.positions[id])
		if not reference_bins.has(key):
			reference_bins[key] = []
		reference_bins[key].append(id)


func rebuild_insects_reference(a) -> void:
	reference_insects.clear()
	var habitat = a.habitat
	var plants = a.plants
	for k in habitat.insect_sites.size():
		var site: int = habitat.insect_sites[k]
		var point: Vector3 = plants.positions[site] if site >= 0 else habitat.center(k)
		var key: Vector2i = bin_reference(point)
		if not reference_insects.has(key):
			reference_insects[key] = []
		reference_insects[key].append(k)


func nearby_reference(a, point: Vector3, radius: float) -> Array:
	var result := []
	var plants = a.plants
	var center := bin_reference(point)
	var count: int = ceili(radius / REFERENCE_BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			for id in reference_bins.get(Vector2i(x, z), []):
				var offset: Vector3 = plants.positions[id] - point
				if Vector2(offset.x, offset.z).length_squared() <= radius * radius:
					result.append(id)
	return result


func insects_reference(_a, point: Vector3, radius: float) -> Array:
	var result := []
	var center := bin_reference(point)
	var count: int = ceili(radius / REFERENCE_BIN_M)
	for z in range(center.y - count, center.y + count + 1):
		for x in range(center.x - count, center.x + count + 1):
			result.append_array(reference_insects.get(Vector2i(x, z), []))
	result.sort()
	return result


func bin_reference(point: Vector3) -> Vector2i:
	return Vector2i(floori(point.x / REFERENCE_BIN_M), floori(point.z / REFERENCE_BIN_M))
