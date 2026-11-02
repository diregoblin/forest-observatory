extends SceneTree

const ANIMAL_DEFINITION = preload("res://scripts/animal_definition.gd")
const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	_run.call_deferred()


func world(seed_value: int, definitions: Array = []) -> ForestAnimals:
	var settings: ForestSettings = CONFIG.duplicate(true)
	settings.seed = seed_value
	var land := ForestLandscape.new(settings)
	var water := ForestWatershed.new(land)
	var soil := ForestSoil.new(water)
	var plants := ForestTrees.new(land, soil)
	var frozen := var_to_bytes(plants.snapshot())
	var animals := ForestAnimals.new(land, plants, water, soil, definitions)
	assert(var_to_bytes(plants.snapshot()) == frozen)
	return animals


func separation(groups: Array) -> float:
	var result := INF
	for i in groups.size():
		for j in i:
			var a: Vector2 = groups[i].point
			var b: Vector2 = groups[j].point
			result = minf(result, a.distance_to(b))
	return result


func inspect_spawn(animals: ForestAnimals, wide := true) -> Dictionary:
	var groups := []
	var points := []
	var totals := Vector3.ZERO
	var offset := 0
	var low := Vector2(INF, INF)
	var high := Vector2(-INF, -INF)
	for s in animals.definitions.size():
		var d: ForestAnimalDefinition = animals.definitions[s]
		totals += d.initial_elements * d.initial_count
		for i in d.initial_count:
			var id := offset + i
			var point: Vector3 = animals.positions[id]
			var xz := Vector2(point.x, point.z)
			assert(point.is_finite() and animals._founder_ground(point, d))
			assert(animals.home_positions[id] == point)
			assert(point.x >= 1 and point.z >= 1)
			assert(
				point.x < animals.land.settings.extent and point.z < animals.land.settings.extent
			)
			points.append({"id": id, "species": str(d.species_id), "x": point.x, "z": point.z})
			if i % 2 == 0:
				groups.append({"point": xz, "spacing": d.founder_pair_spacing_m})
				low = low.min(xz)
				high = high.max(xz)
			else:
				var mate: Vector3 = animals.positions[id - 1]
				assert(xz.distance_to(Vector2(mate.x, mate.z)) <= 2.3)
				assert(animals.sexes[id] != animals.sexes[id - 1])
		offset += d.initial_count
	assert((animals.element_totals() - totals).length() < .0001)
	var gap := separation(groups)
	assert(gap >= 18.0, "Founder groups must not occupy one crowded observation plot")
	var span := high - low
	assert(not wide or (
		span.x > animals.land.settings.extent * .65 and span.y > animals.land.settings.extent * .65
	))
	return {
		"seed": animals.land.settings.seed,
		"groups": groups.size(),
		"minimum_gap_m": gap,
		"span_m": span,
		"points": points
	}


func _run() -> void:
	var config: ForestSettings = CONFIG
	var results := []
	for seed_value in [config.seed, config.seed + 1, config.seed + 77]:
		var animals := world(seed_value)
		results.append(inspect_spawn(animals))
		var repeat := world(seed_value)
		assert(animals.snapshot() == repeat.snapshot(), "Founder placement must be deterministic")
	# Independent collapsed control: this exact spacing check rejects a pile.
	assert(separation([{"point": Vector2.ZERO}, {"point": Vector2.ZERO}]) < 18.0)
	var third: ForestAnimalDefinition = load("res://data/animals/hare.tres").duplicate(true)
	third.species_id = &"resource_only_third_founder"
	third.initial_count = 6
	var unknown := world(config.seed, [third])
	assert(unknown.species.size() == 6)
	inspect_spawn(unknown, false)
	var report := {
		"passed": true,
		"results": results,
		"third_species": true,
		"unchanged_plant_models": true,
		"deterministic": true
	}
	FileAccess.open("res://artifacts/animal-spawn-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("ANIMAL_SPAWN_CHECK PASS")
	quit()
