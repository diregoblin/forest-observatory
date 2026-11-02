extends "res://tools/check_animals.gd"


func population(food := true, predator := false) -> Dictionary:
	var world := chamber(food)
	var hare: ForestAnimalDefinition = HARE.duplicate(true)
	hare.initial_count = 2
	hare.sleep_duration_h = 0 # Isolate reproduction; circadian checks have their own assay.
	hare.gestation_days = 2  # Bounded assay, not the shipped gestation period.
	hare.movement_m_biological_s = 0
	if not food:
		hare.initial_elements = Vector3(1.0, .1, .01)
	var definitions: Array = [hare]
	if predator:
		var fox: ForestAnimalDefinition = ForestAnimals.FOX.duplicate(true)
		fox.initial_count = 1
		fox.sleep_duration_h = 0
		definitions.append(fox)
	world.animals = ForestAnimals.new(
		world.animals.land, world.plants, world.water, world.soil, definitions
	)
	return world


func _run() -> void:
	_check_hunting_cycle()
	_check_small_herbivore()
	var world := population()
	var initial := total(world)
	world.animals.step(ForestClimate.DAY_S)
	assert(world.animals.gestation_c[0] > 0 and world.animals.births == 0)
	assert((total(world) - initial).length() < 5e-6)
	var frozen: Dictionary = world.animals.snapshot()
	var clone := population()
	assert(clone.animals.restore(frozen))
	clone.plants.biomass_c = world.plants.biomass_c.duplicate()
	clone.plants.biomass_n = world.plants.biomass_n.duplicate()
	clone.plants.biomass_p = world.plants.biomass_p.duplicate()
	clone.soil.elements = world.soil.elements
	for day in 4:
		world.animals.step(ForestClimate.DAY_S)
		clone.animals.step(ForestClimate.DAY_S)
		assert(world.animals.snapshot() == clone.animals.snapshot())
	assert(world.animals.births == 2 and world.animals.species.size() == 4)
	assert((total(world) - initial).length() < 1e-5)
	for id in [2, 3]:
		assert(world.animals.mothers[id] == 0 and world.animals.fathers[id] == 1)
		assert(world.animals.age_years[id] < .1 and world.animals.inspect(id).stage == "детёныш")
		for key in world.animals.phenotypes[id]:
			var mean: float = (
				(world.animals.phenotypes[0][key] + world.animals.phenotypes[1][key]) * .5
			)
			assert(absf(world.animals.phenotypes[id][key] - mean) <= .13001)
	assert(world.animals.restore(world.animals.snapshot()))
	var valid: Dictionary = world.animals.snapshot()
	for field in ["future_parent", "bad_gene", "negative_escrow", "wrong_species"]:
		var corrupt: Dictionary = valid.duplicate(true)
		match field:
			"future_parent":
				corrupt.mothers[2] = 3
			"bad_gene":
				corrupt.phenotypes[0].ears = NAN
			"negative_escrow":
				corrupt.gestation_c[0] = -1.0
			"wrong_species":
				corrupt.species[0] = 99
		assert(not world.animals.restore(corrupt))
		assert(world.animals.snapshot() == valid)
	var lean := population(false)
	var lean_initial := total(lean)
	lean.animals.step(12 * ForestClimate.DAY_S)
	assert(lean.animals.births == 0 and lean.animals.alive.count(1) == 0)
	assert((total(lean) - lean_initial).length() < 1e-5)
	var hunt := population(true, true)
	hunt.animals.step(900)
	var prey_mass: float = hunt.animals.biomass_c[0] + hunt.animals.gestation_c[0]
	hunt.animals.positions[2] = hunt.animals.positions[0] + Vector3(.2, 0, 0)
	var hunt_initial := total(hunt)
	hunt.animals.step(900)
	assert(
		(
			not hunt.animals.alive[0]
			and hunt.animals.kills[2] == 1
			and hunt.animals.predation_deaths == 1
		)
	)
	assert(hunt.animals.consumed_cnp.x >= prey_mass * .99)  # Prey metabolizes before capture.
	assert(hunt.animals.gestation_c[0] == 0)
	assert((total(hunt) - hunt_initial).length() < 1e-5)
	assert(hunt.animals.restore(hunt.animals.snapshot()))
	var escape := population(true, true)
	escape.animals.definitions[0].movement_m_biological_s = .00015
	escape.animals.positions[2] = escape.animals.positions[0] + Vector3(5, 0, 0)
	var start: Vector3 = escape.animals.positions[0]
	escape.animals.step(1800)
	assert(
		escape.animals.actions[0] == "flee" and escape.animals.positions[0].distance_to(start) > 0
	)
	assert(escape.animals.actions[2] == "hunt")
	var distant := population(true, true)
	distant.animals.positions[2] = distant.animals.positions[0] + Vector3(100, 0, 0)
	distant.animals.step(900)
	assert(distant.animals.prey_targets[2] == -1 and distant.animals.kills[2] == 0)
	var fox_only := population()
	fox_only.animals = ForestAnimals.new(
		fox_only.animals.land, fox_only.plants, fox_only.water, fox_only.soil, [ForestAnimals.FOX]
	)
	var plant_mass: float = fox_only.plants.biomass_c[0]
	fox_only.animals.step(90 * ForestClimate.DAY_S)
	assert(fox_only.animals.alive.count(1) == 0 and fox_only.plants.biomass_c[0] == plant_mass)
	# Regression: a float32 cumulative feeding vector drifted far enough over
	# long coupled trajectories to reject the model's own valid save.
	var accounting := population()
	var expected_food := 0.0
	var tiny_bite := Vector3(.0001, .00001, .000001)
	for bite in 100000:
		accounting.animals._record_consumed(tiny_bite)
		expected_food += tiny_bite.x
	assert(absf(accounting.animals.consumed_totals[0] - expected_food) < 1e-10)
	assert(accounting.animals.restore(accounting.animals.snapshot()))
	var view := ForestAnimalsView.new()
	view.configure(world.animals)
	assert(view.batches.size() == 4)
	assert(view.mesh_faces[0] != view.mesh_faces[1], "Founders are not one cloned silhouette")
	assert(view.selection_shape(2).bounds.size.y < view.selection_shape(0).bounds.size.y)
	var before_view: Dictionary = world.animals.snapshot()
	view.refresh(.4)
	assert(world.animals.snapshot() == before_view)
	view.free()
	var report := {
		"passed": true,
		"births": world.animals.births,
		"ledger_residual": str(total(world) - initial),
		"funded_gestation": true,
		"long_feeding_counter_float64": true,
		"gestation_continuation_exact": true,
		"birth_parentage_and_heritable_appearance": true,
		"low_resource_no_birth_control": true,
		"predation_including_escrow_conserved": true,
		"prey_flees": true,
		"distant_prey_not_sensed": true,
		"no_prey_predator_starves": true,
		"predator_hunting_and_recovery_cycle": true,
		"longer_reserve_still_finite": true,
		"vole_real_plant_food_funded_birth_and_fox_prey": true,
		"corrupt_state_atomic_rejection": true,
		"distinct_meshes_and_smaller_juveniles": true,
		"scope": "Controlled short-gestation chambers, not long-term population validation."
	}
	FileAccess.open("res://artifacts/population-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("POPULATION_CHECK ", JSON.stringify(report))
	quit()


func _check_hunting_cycle() -> void:
	var w := population(true, true)
	var animals: ForestAnimals = w.animals
	var fox: ForestAnimalDefinition = animals.definitions[1]
	# A close catch followed by another visible prey cannot cause immediate
	# repeated kills. Check the definition-derived recovery boundary explicitly.
	animals.positions[2] = animals.positions[0] + Vector3(.2, 0, 0)
	animals._hunt(2, 900, 0)
	assert(animals.kills[2] == 1 and animals.routines[2] == "recover")
	animals.positions[1] = animals.positions[2] + Vector3(.2, 0, 0)
	animals.biomass_c[2] = (
		fox.minimum_body_carbon_kg + .4 * (fox.maximum_body_carbon_kg - fox.minimum_body_carbon_kg)
	)
	animals._metabolize(2, 1)
	animals._hunt(2, fox.hunting_rest_s - 1, 1)
	assert(animals.actions[2] == "rest" and animals.kills[2] == 1)
	var state: Dictionary = animals.snapshot()
	# Direct calls above are a boundary fixture, not an elapsed-time save.
	assert(state.routine_time[2] == fox.hunting_rest_s - 1)
	animals._hunt(2, 1, fox.hunting_rest_s)
	assert(animals.kills[2] == 2)
	# A real stepped no-prey run lives past the former death window, yet loses
	# energy and still dies later. Real rest is not free energy or immunity.
	var empty := population()
	var solo: ForestAnimalDefinition = ForestAnimals.FOX.duplicate(true)
	solo.initial_count = 1
	empty.animals = ForestAnimals.new(
		empty.animals.land, empty.plants, empty.water, empty.soil, [solo]
	)
	var initial := total(empty)
	var energy: float = empty.animals.energy_kj[0]
	empty.animals.step(25 * ForestClimate.DAY_S)
	assert(empty.animals.alive[0] and empty.animals.energy_kj[0] < energy)
	assert(empty.animals.life_records[0].rested_s > 0)
	assert(empty.animals.restore(empty.animals.snapshot()))
	empty.animals.step(65 * ForestClimate.DAY_S)
	assert(not empty.animals.alive[0])
	assert((total(empty) - initial).length() < 5e-5)


func _check_small_herbivore() -> void:
	var w := chamber()
	var vole: ForestAnimalDefinition = ForestAnimals.VOLE.duplicate(true)
	vole.initial_count = 2
	vole.sleep_duration_h = 0
	vole.movement_m_biological_s = 0
	var fox: ForestAnimalDefinition = ForestAnimals.FOX.duplicate(true)
	fox.initial_count = 1
	w.animals = ForestAnimals.new(w.animals.land, w.plants, w.water, w.soil, [vole, fox])
	w.animals.positions[0] = w.plants.positions[0]
	w.animals.positions[1] = w.plants.positions[0]
	# Keep the predator genuinely out of sensing range for the feeding/birth assay.
	w.animals.positions[2] += Vector3(120, 0, 0)
	var initial := total(w)
	var plant_carbon: float = w.plants.biomass_c[0]
	w.animals.step(22 * ForestClimate.DAY_S)
	assert(w.animals.births == 4 and w.plants.biomass_c[0] < plant_carbon)
	assert(w.animals.gestation_c[0] == 0)
	assert(w.animals.restore(w.animals.snapshot()))
	assert((total(w) - initial).length() < 5e-5)
	# The same small herbivore is edible through the generic prey interface.
	w.animals.positions[2] = w.animals.positions[0] + Vector3(.1, 0, 0)
	w.animals.routines[2] = "forage"
	w.animals.routine_time[2] = 0
	w.animals._hunt(2, 900, w.animals.elapsed_s)
	assert(not w.animals.alive[0] and w.animals.kills[2] == 1)
	assert((total(w) - initial).length() < 5e-5)
