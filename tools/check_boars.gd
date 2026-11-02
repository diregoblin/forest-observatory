extends RefCounted


static func place(a: ForestAnimals, id: int, point: Vector3) -> void:
	a.positions[id] = point
	a.previous_positions[id] = point
	a.home_positions[id] = point
	a.path_history[id] = {"times": PackedFloat64Array([0]), "points": PackedVector3Array([point])}


static func check_budget(w, before: PackedFloat64Array) -> void:
	for e in 3:
		assert(absf(w._ecosystem_budget()[e] - before[e]) < 1e-5, "Boar transfers conserve C/N/P")


static func run(w) -> void:
	w.paused = true
	var a: ForestAnimals = w.animals
	var initial: Dictionary = w._world_snapshot()
	var budget: PackedFloat64Array = w._ecosystem_budget()
	var ids := []
	for i in a.species.size():
		if a.definitions[a.species[i]].rooting_pressure_day > 0:
			ids.append(i)
	assert(ids.size() == 4)
	var id: int = ids[0]
	var species: int = a.species[id]
	var original: ForestAnimalDefinition = a.definitions[species]
	var key := InputEventKey.new()
	key.physical_keycode = KEY_9
	key.pressed = true
	w._unhandled_input(key)
	assert(
		w.observation.selected.kind == &"animal" and a.species[w.observation.selected.id] == species
	)
	w.hud.view_requested.emit(9)
	assert(w.observation.selected.id != id and a.species[w.observation.selected.id] == species)
	assert(w._restore_world(initial))
	# Disable alternate food/sleep only in this labelled plant-feeding fixture.
	var d: ForestAnimalDefinition = original.duplicate(true)
	d.insect_diet = false
	d.scavenges = false
	d.sleep_duration_h = 0
	a.definitions[species] = d
	var plant := -1
	for i in w.trees.species.size():
		var p: ForestPlantDefinition = w.settings.plants[w.trees.species[i]]
		if (
			p.growth_form != &"tree"
			and w.trees._height(i) < 1.2
			and a._edible(i, d)
			and w.water.depth[w.trees.root_cells[i]] < .02
		):
			plant = i
			break
	assert(plant >= 0)
	var point: Vector3 = w.trees.positions[plant]
	place(a, id, point)
	var k: int = w.water.index_at(point.x, point.z)
	var before: float = w.trees.biomass_c[plant]
	a._act(id, 900, 0)
	assert(a.actions[id] == "root" and a.life_records[id].consumed_c_kg > 0)
	assert(w.trees.biomass_c[plant] < before and w.habitat.rooting[k] > 0)
	check_budget(w, budget)
	# No useful food: searching must neither manufacture food nor dig a food scar.
	a.definitions[species] = original
	assert(w._restore_world(initial))
	a.definitions[species] = d
	d.minimum_edible_carbon_kg = 1e9
	place(a, id, point)
	a._act(id, 900, 0)
	assert(a.life_records[id].consumed_c_kg == 0 and w.habitat.rooting[k] == 0)
	check_budget(w, budget)
	# A non-rooting feeder still eats but does not leave a poroi field.
	d.minimum_edible_carbon_kg = original.minimum_edible_carbon_kg
	d.rooting_pressure_day = 0
	place(a, id, point)
	a._act(id, 900, 0)
	assert(a.life_records[id].consumed_c_kg > 0 and w.habitat.rooting[k] == 0)
	check_budget(w, budget)
	a.definitions[species] = original
	assert(w._restore_world(initial))
	# Insects through the genuine omnivore decision path (no body/plant substitute).
	var climate := ForestClimate.sample(0, 160)
	climate.wind_m_s = 2.0
	climate.rain_fraction = 0.0
	w.habitat.step(ForestClimate.DAY_S, climate)
	# The real stock must meet the feeder's threshold, not merely be nonzero.
	var feeding_point := point
	for cell in w.habitat.insect_sites.size():
		var candidate: Vector3 = w.habitat.center(cell)
		if (
			w.habitat.insect_carbon(candidate) >= original.minimum_edible_carbon_kg
			and w.water.depth[w.water.index_at(candidate.x, candidate.z)] < .02
		):
			feeding_point = candidate
			break
	place(a, id, feeding_point)
	assert(w.habitat.insect_carbon(feeding_point) >= original.minimum_edible_carbon_kg)
	var insects: float = w.habitat.insect_carbon(feeding_point)
	a._act(id, 900, 0)
	assert(a.actions[id] == "root" and w.habitat.insect_carbon(feeding_point) < insects)
	check_budget(w, budget)
	# Field-specific rejection is atomic, and natural recovery does not create mass.
	# Direct _act fixtures above don't advance the coupled clock/lifetime ledger;
	# return to a valid synchronized world before testing saved continuations.
	assert(w._restore_world(initial))
	assert(w.habitat.root_at(point, 1))
	var saved: Dictionary = w._world_snapshot()
	var bad := saved.duplicate(true)
	bad.models.habitat.rooting[k] = NAN
	assert(not w._restore_world(bad) and w._world_snapshot() == saved)
	var rooted: float = w.habitat.rooting[k]
	w.habitat._record_traffic(ForestClimate.DAY_S, climate)
	assert(w.habitat.rooting[k] < rooted and w.habitat.rooting[k] > 0)
	assert(w._restore_world(saved))
	for tick in 40:
		w._advance_world(w.settings.ecology_step_s)
	var next: Dictionary = w._world_snapshot()
	assert(w._restore_world(saved))
	for tick in 40:
		w._advance_world(w.settings.ecology_step_s)
	assert(w._world_snapshot().models == next.models, "Boars and poroi continue exactly")
	check_budget(w, budget)
	assert(w._restore_world(initial))
	# Existing reproduction escrow pays for the actual configured boar litter.
	place(a, ids[1], a.positions[id])
	a._reproduce(id, 0, 0)
	assert(a.gestation_remaining[id] > 0)
	check_budget(w, budget)
	a._reproduce(
		id,
		original.gestation_days * ForestClimate.DAY_S,
		original.gestation_days * ForestClimate.DAY_S
	)
	assert(a.births == original.litter_size)
	check_budget(w, budget)
	assert(w._restore_world(initial))
	var report := {
		"passed": true,
		"keyboard_9_and_hud_cycle": true,
		"founders": ids.size(),
		"real_plant_and_insect_food": true,
		"empty_and_nonrooter_controls": true,
		"cnp_conserved": true,
		"paid_litter": true,
		"corrupt_rooting_rejected_atomically": true,
		"rooting_recovers": true,
		"exact_continuation_ticks": 40
	}
	FileAccess.open("res://artifacts/boars-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("BOARS_CHECK ", JSON.stringify(report))
