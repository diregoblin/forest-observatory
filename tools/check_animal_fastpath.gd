extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var compared := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--reference-models="):
			var reference = FileAccess.open(arg.trim_prefix("--reference-models="), FileAccess.READ)
			var candidate = FileAccess.open(
				"res://artifacts/model-stages-state.bin", FileAccess.READ
			)
			assert(reference != null and candidate != null)
			var before: Dictionary = reference.get_var()
			var after: Dictionary = candidate.get_var()
			var changed := []
			for key in before:
				if before[key] != after.get(key):
					changed.append(key)
			print("MODEL_EQUIVALENCE changed=", changed)
			assert(changed.is_empty() and before.size() == after.size())
			compared = true
	var scene = load("res://scripts/forest.gd").new()
	scene.paused = true
	root.add_child(scene)
	scene.set_process(false)
	var a = scene.animals
	var habitat = scene.habitat
	# Fixed geometry agrees with the definition, not with another cache consumer.
	var dx: float = scene.settings.extent / habitat.GRID
	for k in habitat.GRID * habitat.GRID:
		var x: float = (k % habitat.GRID + .5) * dx
		var z: float = (k / habitat.GRID + .5) * dx
		assert(habitat.center(k) == Vector3(x, scene.land.height_at(x, z), z))
		assert(habitat.insect_carbon_in_cell(k) == habitat.insect_carbon(habitat.center(k)))
	# Finite pools are live, while geometry may be indexed. Include feeding sites
	# far from their nominal cell centre, near domain edges and below the food floor.
	for k in habitat.insect_sites.size():
		habitat.pollinator_c[k] = .02 if k % 3 else 1e-12
		habitat.wood_c[k] = 0
		habitat.detritivore_c[k] = 0
		habitat.insect_sites[k] = (k * 31) % scene.trees.species.size() if k % 4 == 0 else -1
	var initial: Dictionary = a.snapshot()
	var cases := 0
	for id in a.species.size():
		var d: ForestAnimalDefinition = a.definitions[a.species[id]]
		if not d.insect_diet:
			continue
		for variant in 3:
			assert(a.restore(initial))
			place_case(a, id, variant)
			var reference_result := reference_seek(a, id, 900.0, 0.0, d)
			var expected: Dictionary = a.snapshot()
			assert(a.restore(initial))
			place_case(a, id, variant)
			a._rebuild_insect_index()
			var candidates: Array = a._nearby_insect_sites(a.positions[id], d.sense_radius_m)
			for k in habitat.insect_sites.size():
				var site: int = habitat.insect_sites[k]
				var point: Vector3 = a.plants.positions[site] if site >= 0 else habitat.center(k)
				if point.distance_to(a.positions[id]) <= d.sense_radius_m:
					assert(candidates.has(k), "Index omitted a locally reachable feeding point")
			assert(a._seek_insects(id, 900, 0, d) == reference_result)
			assert(a.snapshot() == expected, "Indexed decision must exactly match full scan")
			a._insect_index_active = false
			cases += 1
	assert(cases > 0 and a.restore(initial))
	# Out-of-step edits must be visible, without depending on cache invalidation.
	habitat.insect_sites[0] = -1
	assert(a._nearby_insect_sites(Vector3.ZERO, 1).size() == habitat.insect_sites.size())
	assert(check_threats(scene))
	var report := {
		"passed": true,
		"decision_equivalence_cases": cases,
		"full_model_trace_equivalence": compared,
		"finite_pools_uncached": true,
		"unknown_predator_and_late_ids": true
	}
	FileAccess.open("res://artifacts/animal-fastpath-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ANIMAL_FASTPATH ", JSON.stringify(report))
	scene.free()
	quit()


func place_case(a, id: int, variant: int) -> void:
	var extent: float = a.land.settings.extent
	if variant == 0:
		a.positions[id] = Vector3(1, a.land.height_at(1, 1), 1)
	elif variant == 1:
		a.positions[id] = a.plants.positions[(id * 37) % a.plants.positions.size()]
	else:
		a.positions[id] = Vector3(extent - 1, a.land.height_at(extent - 1, extent - 1), extent - 1)
	a.home_positions[id] = a.positions[id]


func reference_seek(a, id: int, dt: float, time: float, d: ForestAnimalDefinition) -> bool:
	# Frozen pre-optimization scan. It deliberately recomputes centre -> cell.
	var target := Vector3(INF, INF, INF)
	var nearest := d.sense_radius_m
	for k in a.habitat.insect_sites.size():
		var site: int = a.habitat.insect_sites[k]
		if a.habitat.insect_carbon(a.habitat.center(k)) < d.minimum_edible_carbon_kg:
			continue
		var point: Vector3 = a.plants.positions[site] if site >= 0 else a.habitat.center(k)
		var distance: float = a.positions[id].distance_to(point)
		if (
			a.habitat.cell(a.positions[id]) == k
			or point.distance_to(a.home_positions[id]) > d.home_range_m
		):
			continue
		if distance < nearest and a._dry(point, d):
			nearest = distance
			target = point
	if not target.is_finite():
		return false
	var direction: Vector3 = target - a.positions[id]
	direction.y = 0
	var moved: bool = a._move(
		id, direction.normalized(), minf(direction.length(), d.movement_m_biological_s * dt)
	)
	a._set_action(id, "seek_food" if moved else "blocked", time)
	return moved


func reference_threat(a, id: int) -> int:
	var nearest: float = a.definitions[a.species[id]].sense_radius_m
	var result := -1
	for other in a.species.size():
		if (
			not a.alive[other]
			or not a.definitions[a.species[other]].prey_species.has(
				a.definitions[a.species[id]].species_id
			)
		):
			continue
		var distance: float = a.positions[id].distance_to(a.positions[other])
		if distance < nearest:
			nearest = distance
			result = other
	return result


func check_threats(scene) -> bool:
	var animal_script = load("res://scripts/animals.gd")
	var prey: ForestAnimalDefinition = animal_script.DEFAULT.duplicate(true)
	var predator: ForestAnimalDefinition = animal_script.FOX.duplicate(true)
	var unknown: ForestAnimalDefinition = predator.duplicate(true)
	prey.initial_count = 1
	predator.initial_count = 1
	unknown.initial_count = 1
	unknown.species_id = &"unknown_hunter"
	var a = animal_script.new(
		scene.land, scene.trees, scene.water, scene.soil, [prey, predator, unknown]
	)
	a.positions[0] = Vector3(100, 1, 100)
	a.positions[1] = Vector3(200, 1, 200)
	a.positions[2] = Vector3(101, 1, 100)
	a._append_animal(1, a.positions[2])
	assert(a._nearest_threat(0) == 2, "Lowest global ID wins a cross-species tie")
	a.alive[2] = 0
	assert(a._nearest_threat(0) == 3, "Late append-only predator ID must be indexed")
	for id in a.species.size():
		assert(a._nearest_threat(id) == reference_threat(a, id))
	# Definition traits are read now, not frozen into the derived membership index.
	predator.prey_species.clear()
	assert(a._nearest_threat(0) == -1)
	return true
