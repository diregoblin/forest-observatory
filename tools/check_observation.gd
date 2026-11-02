extends SceneTree

## Independent geometry fixtures: expected intersections are specified directly,
## not computed by another bin marcher or another terrain-ray implementation.
const CONFIG = preload("res://data/forest.tres")


class FlatLand:
	extends ForestLandscape

	func height_at(_x: float, _z: float) -> float:
		return 0


class Individuals:
	extends RefCounted
	var positions := PackedVector3Array()
	var shapes: Array[Dictionary] = []

	func inspect(id: int) -> Dictionary:
		return {"title": "Fixture #%d" % id, "alive": true, "age_years": 1.0}

	func selection_shape(id: int) -> Dictionary:
		return shapes[id]

	func add_shape(transform: Transform3D, scale := Vector3.ONE) -> void:
		var faces := PackedVector3Array(
			[Vector3(-1, -1, 0) * scale, Vector3(1, -1, 0) * scale, Vector3(0, 1, 0) * scale]
		)
		var local_bounds := AABB(
			Vector3(-scale.x, -scale.y, -.001), Vector3(scale.x * 2, scale.y * 2, .002)
		)
		positions.append(transform.origin)
		shapes.append({"transform": transform, "faces": faces, "bounds": transform * local_bounds})


class CounterModel:
	extends RefCounted
	var value := 0

	func snapshot() -> Dictionary:
		return {"value": value}

	func restore(state: Dictionary) -> bool:
		if not state.get("value") is int or state.value < 0:
			return false
		value = state.value
		return true


func _initialize() -> void:
	call_deferred("_run")


func _observer(model: Individuals, kind: StringName = &"plant") -> ForestObservation:
	var observer := ForestObservation.new(FlatLand.new(CONFIG))
	observer.register_group(kind, model, model.selection_shape)
	observer.rebuild()
	return observer


func _run() -> void:
	var checks := {}
	var near_and_far := Individuals.new()
	near_and_far.add_shape(Transform3D(Basis.IDENTITY, Vector3(32, 3, 24)))
	near_and_far.add_shape(Transform3D(Basis.IDENTITY, Vector3(32, 3, 28)))
	var observer := _observer(near_and_far)
	checks.closest_actual_hit = (
		observer.pick(Vector3(32, 3, 32), Vector3.FORWARD) == {"kind": &"plant", "id": 1}
	)
	checks.describes_stable_id = observer.describe().title == "Fixture #1"
	# A ray through this triangle's AABB corner misses the triangle itself.
	checks.triangle_not_aabb = observer.pick(Vector3(32.9, 3, 32), Vector3.FORWARD).is_empty()
	var another := Individuals.new()
	another.add_shape(Transform3D(Basis.IDENTITY, Vector3(32, 3, 30)))
	observer.register_group(&"animal", another, another.selection_shape)
	observer.rebuild()
	checks.same_id_different_groups = (
		observer.pick(Vector3(32, 3, 32), Vector3.FORWARD) == {"kind": &"animal", "id": 0}
	)
	var below_ground := Individuals.new()
	below_ground.add_shape(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(40, -1, 40)))
	checks.terrain_occludes = (
		_observer(below_ground).pick(Vector3(40, 3, 40), Vector3.DOWN).is_empty()
	)
	# Small herb 10 cm above soil: analytically ray t=1.16, ground t=1.26.
	# A conservative whole .5m cell cutoff must not hide this visible triangle.
	var short_herb := Individuals.new()
	short_herb.add_shape(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(48, .1, 48)))
	checks.visible_low_plant = (
		_observer(short_herb).pick(Vector3(48, 1.26, 48), Vector3.DOWN)
		== {"kind": &"plant", "id": 0}
	)
	# This narrow object occupies bin (0,1). The diagonal ray enters it at
	# analytically t=sqrt(.5²+.5²), before entering bin (1,1). Sampling every
	# four meters skips the whole intersected (0,1) cell.
	var corner := Individuals.new()
	corner.add_shape(Transform3D(Basis.IDENTITY, Vector3(15.3, 3, 16.4)), Vector3(.25, .5, 1))
	var ray_origin := Vector3(14.8, 3, 15.9)
	var ray_direction := Vector3(1, 0, 1).normalized()
	var expected_hit := ForestObservation._shape_distance(
		corner.shapes[0], ray_origin, ray_direction, 10
	)
	assert(expected_hit > 0 and expected_hit < 1, "Fixture must really intersect the actual mesh")
	checks.bin_corner_traversal = (
		_observer(corner).pick(ray_origin, ray_direction, 10) == {"kind": &"plant", "id": 0}
	)
	checks.shared_save_registry_and_rollback = _check_registry()
	if DisplayServer.get_name() != "headless":
		checks.selection_matches_submitted_view_and_waits_for_refresh = _check_displayed_state()
	var passed := true
	for name in checks:
		passed = passed and checks[name]
	var report := {
		"passed": passed,
		"checks": checks,
		"view_test":
		(
			"real rendering backend"
			if DisplayServer.get_name() != "headless"
			else "skipped: Dummy MultiMesh getters have no submitted buffers"
		),
		"boundary":
		"Analytical geometry fixtures and actual save registry; not physical mouse input"
	}
	if OS.get_cmdline_user_args().has("--hare-scenario"):
		report["hare_scenario"] = _hare_scenario()
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var file := FileAccess.open("res://artifacts/observation-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	if report.has("hare_scenario"):
		var scenario_file := FileAccess.open(
			"res://artifacts/hare-scenario-check.json", FileAccess.WRITE
		)
		scenario_file.store_string(JSON.stringify(report.hare_scenario, "  "))
	if DisplayServer.get_name() != "headless":
		var render_file := FileAccess.open(
			"res://artifacts/observation-render-check.json", FileAccess.WRITE
		)
		render_file.store_string(JSON.stringify(report, "  "))
	print("OBSERVATION_CHECK ", JSON.stringify(report))
	quit(0 if passed else 1)


func _check_registry() -> bool:
	var first := CounterModel.new()
	var second := CounterModel.new()
	first.value = 3
	second.value = 4
	var models := {"first": first, "second": second}
	var config := {"fixture": 1}
	var scene := {"selection": {"kind": &"plant", "id": 1}}
	var saved := ForestWorldState.capture(models, config, scene)
	first.value = 8
	second.value = 9
	var before := ForestWorldState.capture(models, config, scene)
	var bad := saved.duplicate(true)
	bad.models.second.value = -1
	if ForestWorldState.restore(models, config, bad):
		return false
	if ForestWorldState.capture(models, config, scene) != before:
		return false
	if not ForestWorldState.restore(models, config, saved) or first.value != 3 or second.value != 4:
		return false
	var path := "res://artifacts/observation-registry-fixture.bin"
	if ForestWorldState.write(path, saved) != OK:
		return false
	return ForestWorldState.read(path) == saved


func _check_displayed_state() -> bool:
	# Check the actual view-submitted MultiMesh, not a reconstruction from model
	# transforms (the latter was precisely the previous implementation bug).
	var settings: ForestSettings = CONFIG.duplicate(true)
	settings.tree_attempts = 0
	settings.water_resolution = 4
	settings.headwater_length = settings.extent
	settings.headwater_width = settings.extent
	settings.plants = [CONFIG.plants[1].duplicate(true)]
	var land := FlatLand.new(settings)
	var water := ForestWatershed.new(land)
	var plants := ForestTrees.new(land)
	plants._append(0, Vector3(64, 0, 64), 1, 10)
	var cover := ForestGroundcover.new(water)
	var view := ForestVegetation.new()
	root.add_child(view)
	view.build(land, water, cover, plants)
	var climate := ForestClimate.sample(0, 200)
	view.refresh_trees(climate)
	var shape := view.selection_shape(0).duplicate(true)
	var submitted: Transform3D = view.batch_for(0).multimesh.get_instance_transform(0)
	var submitted_leaf: float = view.batch_for(0).multimesh.get_instance_custom_data(0).r
	var mesh_bounds: AABB = view.batch_for(0).multimesh.mesh.get_aabb()
	var okay: bool = shape.transform == submitted and shape.bounds == submitted * mesh_bounds
	okay = okay and is_equal_approx(shape.leaves, submitted_leaf)
	# Mutate the model as a growth/death tick would, without calling the view.
	plants.size[0] = 2
	plants.positions[0] += Vector3(3, 0, 0)
	plants.alive[0] = 0
	plants.stress[0] = 1
	plants.ticks += 1
	okay = okay and view.selection_shape(0) == shape
	okay = okay and view.batch_for(0).multimesh.get_instance_transform(0) == submitted
	view.refresh_trees(climate)
	var refreshed := view.selection_shape(0)
	var next_transform: Transform3D = view.batch_for(0).multimesh.get_instance_transform(0)
	okay = okay and refreshed.transform == next_transform and next_transform != submitted
	okay = okay and refreshed.bounds == next_transform * mesh_bounds
	okay = okay and refreshed.leaves == 0
	okay = okay and view.batch_for(0).multimesh.get_instance_custom_data(0).r == 0
	var new_id := plants._append(0, Vector3(66, 0, 65), .2, 0)
	okay = okay and view.selection_shape(new_id).is_empty()
	view.refresh_trees(climate)
	okay = okay and not view.selection_shape(new_id).is_empty()
	# A partial smooth update must keep both changed and not-yet-visited picks
	# aligned with the actual submitted geometry, including appended seedlings.
	for index in 300:
		plants._append(0, Vector3(70 + index % 20, 0, 70 + index / 20), .3, 1)
	view.refresh_trees(climate)
	for id in plants.size.size():
		plants.size[id] *= .5
	view.advance_display(.025, climate)
	okay = okay and view.last_batch_count > 0 and view.last_batch_count <= 128
	for id in plants.size.size():
		var multi: MultiMesh = view.batch_for(id).multimesh
		var actual := multi.get_instance_transform(view.member_slots[id])
		var shown := view.selection_shape(id)
		okay = okay and shown.transform == actual and shown.bounds == actual * mesh_bounds
	var soil := ForestSoil.new(water)
	var animals := ForestAnimals.new(land, plants, water, soil)
	var animal_view := ForestAnimalsView.new()
	root.add_child(animal_view)
	animal_view.configure(animals)
	var animal_shape := animal_view.selection_shape(0).duplicate(true)
	var animal_mm: MultiMesh = animal_view.batches[0].multimesh
	var animal_submitted := animal_mm.get_instance_transform(0)
	okay = okay and animal_shape.transform == animal_submitted
	okay = okay and animal_shape.bounds == animal_submitted * animal_mm.mesh.get_aabb()
	animals.positions[0] += Vector3(1, 0, 0)
	animals.alive[0] = 0
	okay = okay and animal_view.selection_shape(0) == animal_shape
	animal_view.refresh()
	var animal_next := animal_view.selection_shape(0)
	okay = okay and animal_next.transform == animal_mm.get_instance_transform(0)
	okay = okay and animal_next.bounds == animal_next.transform * animal_mm.mesh.get_aabb()
	okay = okay and animal_next.transform != animal_submitted
	animal_view.free()
	view.free()
	return okay


func _hare_scenario() -> Dictionary:
	# Opt-in bounded ecological assay: exact shipped seed/resources/step/order,
	# isolated memory only. Never resets, replenishes or relocates the hare.
	var settings: ForestSettings = CONFIG.duplicate(true)
	var land := ForestLandscape.new(settings)
	var clock := ForestEcologyClock.new(settings)
	var water := ForestWatershed.new(land)
	var soil := ForestSoil.new(water)
	var plants := ForestTrees.new(land, soil)
	var fungi := ForestFungi.new(water, soil)
	plants.mycorrhiza = fungi
	var animals := ForestAnimals.new(land, plants, water, soil)
	var start_position: Vector3 = animals.positions[0]
	var initial_local_food := 0.0
	for id in animals._nearby(start_position, animals.definitions[0].sense_radius_m):
		var definition: ForestPlantDefinition = settings.plants[plants.species[id]]
		initial_local_food += plants.biomass_c[id] * definition.edible_fraction
	var observed := {}
	var daily := []
	var next_day := 1
	var started := Time.get_ticks_msec()
	while animals.elapsed_s < 20 * ForestClimate.DAY_S:
		clock.request(settings.ecology_step_s)
		assert(clock.step())
		var climate := clock.sample()
		water.native.set_evaporation(settings.evaporation_m_s * climate.evaporation)
		water.step(settings.ecology_step_s, false)
		water.sync_fields()
		var dt := clock.biological_step_s()
		soil.step(dt, water)
		plants.step(dt, water, maxf(0, water.clock - plants.water_elapsed_s))
		fungi.step(dt, water, climate)
		animals.step(dt)
		observed[animals.actions[0]] = true
		for event in animals.histories[0]:
			observed[event.action] = true
		if animals.elapsed_s / ForestClimate.DAY_S >= next_day:
			daily.append(
				{
					"day": animals.elapsed_s / ForestClimate.DAY_S,
					"alive": bool(animals.alive[0]),
					"energy_kj": animals.energy_kj[0],
					"consumed_c_kg": animals.consumed_cnp.x,
					"distance_m": animals.total_distance_m,
					"action": animals.actions[0]
				}
			)
			next_day += 1
	return {
		"alive_after_20_days": bool(animals.alive[0]),
		"elapsed_days": animals.elapsed_s / ForestClimate.DAY_S,
		"initial_position": start_position,
		"final_position": animals.positions[0],
		"initial_local_edible_c_kg": initial_local_food,
		"consumed_c_kg": animals.consumed_cnp.x,
		"distance_m": animals.total_distance_m,
		"observed_actions": observed.keys(),
		"daily": daily,
		"wall_seconds": (Time.get_ticks_msec() - started) / 1000.0,
		"boundary":
		"Shipped seed and coupled fixed ticks, no reset; not multiple-seed viability or mouse observation"
	}
