extends SceneTree

const CONFIG = preload("res://data/forest.tres")
const HARE = preload("res://data/animals/hare.tres")


class Food:
	extends RefCounted
	var positions := PackedVector3Array()
	var species := PackedInt32Array([0])
	var alive := PackedByteArray([1])
	var size := PackedFloat64Array([1])
	var biomass_c := PackedFloat64Array([8])
	var biomass_n := PackedFloat64Array([.2])
	var biomass_p := PackedFloat64Array([.016])

	func harvest(id: int, requested_c: float) -> Vector3:
		var fraction := minf(requested_c / biomass_c[id], 1) if biomass_c[id] > 0 else 0.0
		var actual := Vector3(biomass_c[id], biomass_n[id], biomass_p[id]) * fraction
		biomass_c[id] -= actual.x
		biomass_n[id] -= actual.y
		biomass_p[id] -= actual.z
		return actual

	func element_totals() -> Vector3:
		return Vector3(biomass_c[0], biomass_n[0], biomass_p[0])


class Water:
	extends RefCounted
	var depth := PackedFloat64Array([0])

	func index_at(_x: float, _z: float) -> int:
		return 0


class Soil:
	extends RefCounted
	var elements := Vector3.ZERO
	var deposits := 0

	func deposit(_position: Vector3, amount: Vector3, organic := true) -> void:
		assert(organic and amount.x >= 0 and amount.y >= 0 and amount.z >= 0)
		elements += amount
		deposits += 1


func chamber(food := true, flooding := false, extra_species := false) -> Dictionary:
	var settings: ForestSettings = CONFIG.duplicate(true)
	var edible: ForestPlantDefinition = settings.plants[0].duplicate(true)
	edible.edible_fraction = .5
	edible.reference_height_m = 2
	settings.plants = [edible]
	var land := ForestLandscape.new(settings)
	var plants := Food.new()
	var center := settings.fungi_plot_centers[0] * settings.extent
	plants.positions = PackedVector3Array(
		[Vector3(center.x, land.height_at(center.x, center.y), center.y)]
	)
	if not food:
		plants.biomass_c[0] = 0
		plants.biomass_n[0] = 0
		plants.biomass_p[0] = 0
	var water := Water.new()
	water.depth[0] = 1 if flooding else 0
	var soil := Soil.new()
	var definitions: Array = [HARE]
	if extra_species:
		var other: ForestAnimalDefinition = HARE.duplicate(true)
		other.species_id = &"resource_only_herbivore"
		definitions.append(other)
	var animals := ForestAnimals.new(land, plants, water, soil, definitions)
	return {"animals": animals, "plants": plants, "water": water, "soil": soil}


func total(world: Dictionary) -> Vector3:
	return (
		world.plants.element_totals()
		+ world.animals.element_totals()
		+ world.soil.elements
		+ Vector3(world.animals.respired_c_kg, 0, 0)
	)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_depleted_food()
	var fed := chamber()
	var starved := chamber(false)
	var flood := chamber(true, true)
	var initial := total(fed)
	var dry_initial := total(starved)
	var starting_energy: float = starved.animals.energy_kj[0]
	var flood_start: Vector3 = flood.animals.positions[0]
	var distant := chamber()
	distant.plants.positions[0] += Vector3(120, 0, 0)
	distant.animals.step(26280)
	assert(
		distant.animals.consumed_cnp == Vector3.ZERO and distant.animals.decision_checks == 0,
		"Distant food is not sensed omnisciently"
	)
	# The production tick is about 7.3 biological hours. Explicit waypoints, not
	# just the final displacement, must obey the resource's locomotion bound.
	fed.animals.step(26280)
	var track: Dictionary = fed.animals.path_history[0]
	assert(track.times[-1] == 26280 and track.points.size() > 20)
	var path_distance := 0.0
	for i in range(1, track.points.size()):
		var delta: Vector3 = track.points[i] - track.points[i - 1]
		var distance := Vector2(delta.x, delta.z).length()
		var dt: float = track.times[i] - track.times[i - 1]
		assert(distance <= HARE.movement_m_biological_s * dt + 5e-5)
		assert(distance <= HARE.maximum_segment_m + 5e-5)
		path_distance += distance
	assert(path_distance > 0 and fed.animals.consumed_cnp.x > 0)
	assert(fed.plants.biomass_c[0] < 8, "Food actually loses mass, no decorative feeding")
	assert((total(fed) - initial).length() < 3e-6)
	var frozen: Dictionary = fed.animals.snapshot()
	for alpha in [0.0, .1, .4, .8, 1.0]:
		var sampled: Vector3 = fed.animals.display_position(0, alpha)
		assert(sampled.is_finite())
	assert(fed.animals.snapshot() == frozen, "Presentation sampling cannot advance animals")
	starved.animals.step(ForestClimate.DAY_S)
	flood.animals.step(ForestClimate.DAY_S)
	assert(
		(
			starved.animals.energy_kj[0] < starting_energy
			and starved.animals.consumed_cnp == Vector3.ZERO
		)
	)
	assert(
		flood.animals.positions[0] == flood_start and flood.animals.total_distance_m == 0,
		"Deep water blocks all movement"
	)
	for day in 12:
		fed.animals.step(ForestClimate.DAY_S)
		starved.animals.step(ForestClimate.DAY_S)
	assert(fed.animals.alive[0] and not starved.animals.alive[0])
	assert(starved.animals.deaths == 1 and starved.animals.carcass_to_soil_cnp.x > 0)
	assert((total(fed) - initial).length() < 2e-5)
	assert((total(starved) - dry_initial).length() < 4e-6)
	var carcass: Vector3 = starved.animals.carcass_to_soil_cnp
	var deposited: Vector3 = starved.soil.elements
	starved.animals.step(ForestClimate.DAY_S)
	assert(
		starved.animals.carcass_to_soil_cnp == carcass and starved.soil.elements == deposited,
		"Death transfer is one-shot"
	)
	_check_continuation(fed)
	_check_restore_rejects(fed)
	var two := chamber(true, false, true)
	two.animals.step(26280)
	assert(
		(
			two.animals.species.size() == 2
			and two.animals.inspect(1).species_id == &"resource_only_herbivore"
		)
	)
	var view := ForestAnimalsView.new()
	view.configure(two.animals)
	assert(view.batches.size() == 2 and view.batches[0].multimesh.mesh.get_aabb().size.y > .8)
	var shape := view.selection_shape(1)
	assert(
		(
			shape.faces.size() > 100
			and shape.bounds.size.y > .8
			and shape.transform.origin == two.animals.positions[1]
		)
	)
	var visual_before: Dictionary = two.animals.snapshot()
	view.refresh(.5)
	assert(two.animals.snapshot() == visual_before)
	view.free()
	var report := {
		"passed": true,
		"real_food_depletion": true,
		"no_food_energy_loss_and_mortality": true,
		"flood_blocked": true,
		"cnp_ledger_closed": true,
		"death_transfer_once": true,
		"production_tick_waypoints_bounded": true,
		"continuation_exact": true,
		"corruption_atomic_rejection": true,
		"resource_only_second_species": true,
		"view_read_only": true,
		"local_sensing_only": true,
		"near_depleted_food_not_selected": true,
		"edible_threshold_resource_driven": true,
		"reproduction_implemented": false,
		"boundary":
		"Controlled food/soil/water doubles; scenario metabolism and movement, not validated physiology"
	}
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/animals-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	print("ANIMALS_CHECK ", JSON.stringify(report))
	quit()


func _check_depleted_food() -> void:
	var world := chamber()
	var definition: ForestAnimalDefinition = world.animals.definitions[0]
	var edible_fraction: float = world.animals.land.settings.plants[0].edible_fraction
	var carbon := definition.minimum_edible_carbon_kg / edible_fraction * .5
	world.plants.biomass_c[0] = carbon
	world.plants.biomass_n[0] = carbon / 40
	world.plants.biomass_p[0] = carbon / 500
	var stocks: Vector3 = world.plants.element_totals()
	var before := total(world)
	world.animals.step(26280)
	assert(world.animals.consumed_cnp == Vector3.ZERO and world.animals.targets[0] == -1)
	assert(world.animals.actions[0] != "eat" and world.plants.element_totals() == stocks)
	assert((total(world) - before).length() < 3e-6, "Ignored crumbs remain in plants, not deleted")
	# Same species identity and handlers, only a lower resource-defined threshold.
	var smaller_threshold: ForestAnimalDefinition = definition.duplicate(true)
	smaller_threshold.minimum_edible_carbon_kg *= .1
	world.animals = ForestAnimals.new(
		world.animals.land, world.plants, world.water, world.soil, [smaller_threshold]
	)
	world.animals.step(26280)
	assert(world.animals.consumed_cnp.x > 0 and world.plants.biomass_c[0] < carbon)


func _check_continuation(original: Dictionary) -> void:
	var resumed := chamber()
	var state: Dictionary = original.animals.snapshot()
	assert(resumed.animals.restore(state))
	for field in ["biomass_c", "biomass_n", "biomass_p"]:
		resumed.plants.set(field, original.plants.get(field).duplicate())
	resumed.soil.elements = original.soil.elements
	for world in [original, resumed]:
		world.animals.step(26280)
	assert(original.animals.snapshot() == resumed.animals.snapshot())
	assert(original.plants.element_totals() == resumed.plants.element_totals())
	assert(original.soil.elements == resumed.soil.elements)


func _check_restore_rejects(world: Dictionary) -> void:
	var before: Dictionary = world.animals.snapshot()
	for mode in 7:
		var corrupt := before.duplicate(true)
		match mode:
			0:
				corrupt.biomass_c[0] = -1.0
			1:
				corrupt.positions[0] = Vector3(NAN, 0, 0)
			2:
				corrupt.path_history[0].times[1] = -1
			3:
				corrupt.species[0] = 99
			4:
				corrupt.configuration.seed += 1
			5:
				corrupt.energy_kj[0] += 100
			6:
				corrupt.path_history[0].points[1] += Vector3(4, 0, 0)
		assert(not world.animals.restore(corrupt) and world.animals.snapshot() == before)
