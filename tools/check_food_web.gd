extends RefCounted


static func run(w) -> void:
	w.paused = true
	var initial: Dictionary = w._world_snapshot()
	var budget: PackedFloat64Array = w._ecosystem_budget()
	var fox := -1
	var prey := -1
	for id in w.animals.species.size():
		var d: ForestAnimalDefinition = w.animals.definitions[w.animals.species[id]]
		if d.scavenges and d.trophic_role == &"predator":
			fox = id
		elif ForestAnimals.FOX.prey_species.has(d.species_id):
			prey = id
	assert(fox >= 0 and prey >= 0)
	assert(w.habitat.harvest_carcass(prey, 1) == Vector3.ZERO, "No body means no food")
	var before_soil: float = w.soil.metrics().carbon_kg
	w.animals._die(prey)
	assert(
		(
			w.habitat.carcass_carbon(prey) > 0
			and absf(w.soil.metrics().carbon_kg - before_soil) < 1e-10
		),
		"Death transfers to one finite corpse, not an immediate duplicate in soil"
	)
	var body: float = w.habitat.carcass_carbon(prey)
	w.animals.positions[fox] = w.animals.positions[prey]
	w.animals.previous_positions[fox] = w.animals.positions[fox]
	w.animals.path_history[fox] = {
		"times": PackedFloat64Array([0]), "points": PackedVector3Array([w.animals.positions[fox]])
	}
	w.animals.home_positions[fox] = w.animals.positions[prey]
	var before_eaten: float = w.animals.life_records[fox].consumed_c_kg
	assert(w.animals._scavenge(fox, 900, 0, w.animals.definitions[w.animals.species[fox]]))
	w.animals._metabolize(fox, 0)
	assert(
		(
			w.habitat.carcass_carbon(prey) < body
			and w.animals.life_records[fox].consumed_c_kg > before_eaten
		)
	)
	assert(w.animals.known_food_sites[fox].size() == 1)
	w.animals._remember_food(fox, "carcass", prey, w.animals.positions[prey], 0, true)
	assert(w.animals._remembered_empty(fox, "carcass", prey, ForestClimate.DAY_S))
	assert(
		not w.animals._remembered_empty(fox, "carcass", prey, 3 * ForestClimate.DAY_S),
		"Empty memory expires, not permanent starvation"
	)
	for i in 6:
		w.animals._remember_food(fox, "plant", i, w.trees.positions[i], 0)
	assert(w.animals.known_food_sites[fox].size() == 4, "Bounded memory")
	var saved: Dictionary = w._world_snapshot()
	var corrupt := saved.duplicate(true)
	corrupt.models.habitat.carcasses[0].c = -1.0
	assert(not w._restore_world(corrupt) and w._world_snapshot() == saved)
	corrupt = saved.duplicate(true)
	corrupt.models.animals.known_food_sites[fox][0].position = Vector3(NAN, 0, 0)
	assert(not w._restore_world(corrupt) and w._world_snapshot() == saved)
	for e in 3:
		assert(absf(w._ecosystem_budget()[e] - budget[e]) < 1e-5)
	# Advance real production ticks: decay, food choices and restoration interact.
	for i in 40:
		w._advance_world(w.settings.ecology_step_s)
	var next: Dictionary = w._world_snapshot()
	assert(w._restore_world(saved))
	for i in 40:
		w._advance_world(w.settings.ecology_step_s)
	assert(w._world_snapshot().models == next.models, "Food web continues exactly")
	for e in 3:
		assert(absf(w._ecosystem_budget()[e] - budget[e]) < 1e-5)
	assert(w._restore_world(initial))
	# Species-driven omnivory through the actual decision path, not free food.
	var climate := ForestClimate.sample(0, 160)
	climate.wind_m_s = 2.0
	climate.rain_fraction = 0.0
	w.habitat.step(ForestClimate.DAY_S, climate)
	# Community placement must not determine whether this local feeding assay
	# happens to start in an insect-rich cell. Move to an existing finite pool.
	var insect_site := -1
	for k in ForestHabitat.GRID * ForestHabitat.GRID:
		var point: Vector3 = w.habitat.center(k)
		if (
			(
				w.habitat.insect_carbon(point)
				>= w.animals.definitions[w.animals.species[fox]].minimum_edible_carbon_kg
			)
			and w.animals._dry(point, w.animals.definitions[w.animals.species[fox]])
		):
			insect_site = k
			break
	assert(insect_site >= 0, "The world must contain an actual finite insect pool")
	w.animals.positions[fox] = w.habitat.center(insect_site)
	var before_insects: float = w.animals.life_records[fox].consumed_c_kg
	w.animals._act(fox, 900, 0)
	assert(
		(
			w.animals.life_records[fox].consumed_c_kg > before_insects
			and w.animals.known_food_sites[fox][-1].kind == "insects"
		)
	)
	assert(w._restore_world(initial))
	var species: int = w.animals.species[fox]
	var original_d: ForestAnimalDefinition = w.animals.definitions[species]
	var fruit_d: ForestAnimalDefinition = original_d.duplicate(true)
	fruit_d.insect_diet = false
	fruit_d.scavenges = false
	fruit_d.sleep_duration_h = 0
	w.animals.definitions[species] = fruit_d
	var fruit := -1
	for i in w.trees.species.size():
		if (
			w.settings.plants[w.trees.species[i]].fruit_bearing
			and w.trees.biomass_c[i] > .01
			and w.animals._dry(w.trees.positions[i], fruit_d)
		):
			fruit = i
			break
	assert(fruit >= 0)
	var plant_d: ForestPlantDefinition = w.settings.plants[w.trees.species[fruit]]
	var crop: float = minf(.02, w.trees.biomass_c[fruit] * .1)
	w.trees.biomass_c[fruit] -= crop
	w.trees.biomass_n[fruit] -= crop / plant_d.cn_ratio
	w.trees.biomass_p[fruit] -= crop / plant_d.cp_ratio
	w.trees.leaf_carbon[fruit] = minf(w.trees.leaf_carbon[fruit], w.trees.biomass_c[fruit])
	w.trees.seed_c[fruit] += crop
	w.trees.seed_n[fruit] += crop / plant_d.cn_ratio
	w.trees.seed_p[fruit] += crop / plant_d.cp_ratio
	w.trees.fruit_c[fruit] = crop
	w.animals.positions[fox] = w.trees.positions[fruit]
	w.animals.home_positions[fox] = w.trees.positions[fruit]
	w.animals._act(fox, 900, 0)
	assert(
		w.trees.fruit_c[fruit] < crop and w.animals.life_records[fox].consumed_c_kg > 0,
		"Fox consumes a finite ripe crop when it is the local food"
	)
	w.animals.definitions[species] = original_d
	for e in 3:
		assert(absf(w._ecosystem_budget()[e] - budget[e]) < 1e-5)
	assert(w._restore_world(initial))
	var report := {
		"passed": true,
		"finite_carcass_and_empty_control": true,
		"scavenging_uses_real_food": true,
		"fox_insects_and_fruit_from_real_stocks": true,
		"bounded_food_memory_and_expiry": true,
		"corrupt_carcass_memory_atomic": true,
		"cnp_conserved": true,
		"exact_continuation": true,
		"coupled_ticks": 40
	}
	FileAccess.open("res://artifacts/food-web-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("FOOD_WEB_CHECK ", JSON.stringify(report))
