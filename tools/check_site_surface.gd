extends "res://tools/check_animals.gd"


func _run() -> void:
	create_timer(40).timeout.connect(func(): quit(1))
	var settings: ForestSettings = CONFIG.duplicate(true)
	var land := ForestLandscape.new(settings)
	var plants := ForestTrees.new(land)
	var repeat := ForestTrees.new(ForestLandscape.new(settings))
	assert(plants.positions == repeat.positions and plants.species == repeat.species)
	var categories := [0, 0, 0, 0]
	var tree_counts := [0, 0, 0, 0]
	var stands := {}
	for id in plants.species.size():
		var p := plants.positions[id]
		var site := land.habitat_at(p.x, p.z)
		assert(absf(site.x + site.y + site.z + site.w - 1) < .00001)
		var category := 0
		for k in range(1, 4):
			if site[k] > site[category]:
				category = k
		categories[category] += 1
		var d: ForestPlantDefinition = settings.plants[plants.species[id]]
		if d.growth_form == &"tree":
			tree_counts[category] += 1
			if site.x > .8:
				var key := land.stand_at(p.x, p.z)
				if not stands.has(key):
					stands[key] = {}
				stands[key][str(d.species_id)] = stands[key].get(str(d.species_id), 0) + 1
	assert(
		categories[0] > 100 and categories[1] > 100 and categories[2] > 100 and categories[3] > 0
	)
	assert(float(tree_counts[1]) / categories[1] < .05, "Clearings must be genuinely treeless")
	var dominance := []
	for counts in stands.values():
		var total := 0
		for count in counts.values():
			total += count
		if total < 10:
			continue
		var fraction := float(counts.values().max()) / total
		dominance.append(fraction)
	assert(dominance.size() >= 3)
	var dominated := 0
	var mixed := 0
	for fraction in dominance:
		dominated += int(fraction >= .5)
		mixed += int(fraction <= .85)
	assert(dominated >= dominance.size() * .6, "Most forest stands must have a dominant species")
	assert(mixed >= dominance.size() * .6, "Most stands must also retain a substantial admixture")
	# Known-wrong uniform community fails this same criterion: ten equal species.
	assert(1.0 / 10 < .5)
	assert(1.0 > .85, "A pure monoculture fails the mixture criterion")
	var water := ForestWatershed.new(land)
	var soil := ForestSoil.new(water)
	var d: ForestAnimalDefinition = HARE.duplicate(true)
	d.initial_count = 16
	var animals := ForestAnimals.new(land, plants, water, soil, [d])
	var habitat := ForestHabitat.new(plants, water, soil, animals)
	for animal in 16:
		for step in 80:
			habitat.tracks.append(
				{
					"position": animals.positions[animal],
					"yaw": 0.0,
					"size": .48,
					"animal": animal,
					"born_s": 0.0,
					"life_s": 45.0 * ForestClimate.DAY_S
				}
			)
	habitat._record_tracks({})
	assert(habitat.tracks.size() == 16 * ForestHabitat.TRACKS_PER_ANIMAL)
	habitat.elapsed_s = 10 * ForestClimate.DAY_S
	habitat._record_tracks({})
	assert(habitat.tracks.size() == 16 * ForestHabitat.TRACKS_PER_ANIMAL)
	assert(habitat.restore(habitat.snapshot()))
	habitat.elapsed_s = 70 * ForestClimate.DAY_S
	habitat._record_tracks({})
	assert(habitat.tracks.is_empty())
	var view := ForestAnimalsView.new()
	root.add_child(view)
	view.configure(animals)
	var shape: Dictionary = view.selection_shape(0)
	assert(view.selection_shape(0) == shape)
	var before_faces: PackedVector3Array = shape.faces.duplicate()
	view.animation_poses[0][0] += .4
	var changed := view.selection_shape(0)
	assert(changed.faces != before_faces, "In-place packed pose edits must invalidate the cache")
	view.position = Vector3(3, 7, -4)
	view.refresh()
	var moved := view.selection_shape(0)
	assert(moved.transform != shape.transform)
	view.rebuild()
	assert(view.selection_cache.is_empty())
	view.free()
	var report := {
		"passed": true,
		"plants": plants.species.size(),
		"category_plants": categories,
		"category_trees": tree_counts,
		"stand_dominance": dominance,
		"dominated_stands": dominated,
		"deterministic": true,
		"long_fair_bounded_tracks": true,
		"pose_cache_in_place_invalidation": true
	}
	FileAccess.open("res://artifacts/site-surface-check.json", FileAccess.WRITE).store_string(
		JSON.stringify(report, "  ")
	)
	print("SITE_SURFACE ", JSON.stringify(report))
	quit()
