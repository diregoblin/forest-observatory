class_name ForestFungi
extends RefCounted

## Independent, always-active isolated observation plots, NOT a tiled whole forest.
## Carbon pools are authoritative in native float64. Water is read-only forcing.
var land: ForestLandscape
var soil: ForestSoil
var plots: Array[Dictionary] = []
var positions := PackedVector3Array()  # Fixed cell centres for the common observer.
var elapsed_s := 0.0
var ticks := 0
var step_usec := 0
var revision := 0  # Display invalidation only; not a biological state variable.


func _init(water: ForestWatershed, shared_soil: ForestSoil = null) -> void:
	land = water.landscape
	soil = shared_soil
	var config := land.settings
	var n := config.fungi_resolution
	var dx := config.fungi_cell_m
	var size := n * dx
	for index in config.fungi_plot_centers.size():
		var definition := config.fungus_for_plot(index)
		var center := config.fungi_plot_centers[index] * config.extent
		var origin := Vector2(
			clampf(center.x - size / 2, 0, config.extent - size),
			clampf(center.y - size / 2, 0, config.extent - size)
		)
		if soil != null:
			origin = (origin / dx).round() * dx
		var b := PackedFloat64Array()
		var r := PackedFloat64Array()
		var litter := PackedFloat64Array()
		b.resize(n * n)
		r.resize(n * n)
		litter.resize(n * n)
		for y in n:
			for x in n:
				var k := y * n + x
				var px := origin.x + (x + .5) * dx
				var pz := origin.y + (y + .5) * dx
				positions.append(Vector3(px, land.height_at(px, pz), pz))
				var local := Vector2((x + .5 - n / 2.0) * dx, (y + .5 - n / 2.0) * dx)
				var seeded := local.length() < .6
				if index == 1:
					seeded = absf(local.y) < .4 and absf(local.x) < 3.0
				elif index == 2:
					seeded = (
						(local - Vector2(-3, -2)).length() < .6
						or (local - Vector2(3, 2)).length() < .6
					)
				b[k] = definition.resource_capacity_kg_m2 * .5 if seeded else 0.0
				r[k] = definition.resource_capacity_kg_m2 * (.25 if seeded else 1.0)
				litter[k] = definition.initial_litter_kg_m2
		# Established colonies: explicit homogeneous, paper-model prehistory, not hand-drawn rings.
		var core := ForestFungiNative.new()
		_require(core.configure(n, dx, definition.options(false, false), b, r, litter))
		_require(core.advance(config.fungi_initial_age_s))
		var mature: Dictionary = core.fields()
		_require(
			core.configure(n, dx, definition.options(), mature.biomass, mature.resource, litter)
		)
		_require(
			core.set_environment(
				water.soil,
				water.depth,
				water.resolution,
				water.cell_size,
				origin.x,
				origin.y,
				ForestClimate.sample(0, config.start_day).temperature_c
			)
		)
		# Seeded initial fruit is charged to the pre-existing mycelium, not created carbon.
		var initial: Dictionary = core.snapshot()
		for k in n * n:
			var transfer: float = (
				maxf(0, initial.biomass[k] - definition.fruit_threshold_kg_m2)
				* definition.initial_fruit_fraction
				* initial.fruit_suitability[k]
			)
			initial.biomass[k] -= transfer
			initial.fruit[k] += transfer
		_require(core.restore(initial))
		if soil != null:
			var patch: int = soil.native.add_patch(n, dx, origin.x, origin.y)
			_require(patch >= 0)
			_require(core.bind_soil(soil.native, patch))
		plots.append(
			{
				"origin": origin,
				"definition": definition,
				"native": core,
				"fields": core.fields(),
				"metrics": core.metrics()
			}
		)


func step(dt: float, water: ForestWatershed, climate: Dictionary) -> void:
	assert(dt > 0)
	var started := Time.get_ticks_usec()
	for plot in plots:
		_require(
			plot.native.set_environment(
				water.soil,
				water.depth,
				water.resolution,
				water.cell_size,
				plot.origin.x,
				plot.origin.y,
				climate.temperature_c
			)
		)
		_require(plot.native.advance(dt))
	elapsed_s += dt
	ticks += 1
	revision += 1
	step_usec += Time.get_ticks_usec() - started


func sync_fields() -> void:
	for plot in plots:
		plot.fields = plot.native.fields()
		plot.metrics = plot.native.metrics()


func snapshot() -> Dictionary:
	var states: Array[Dictionary] = []
	for plot in plots:
		states.append({"origin": plot.origin, "state": plot.native.snapshot()})
	return {
		"version": 2,
		"configuration": _configuration(),
		"elapsed_s": elapsed_s,
		"ticks": ticks,
		"plots": states
	}


# Explicit rejection guards keep untrusted checkpoint validation atomic and readable.
# gdlint: disable=max-returns
func restore(state: Dictionary) -> bool:
	if state.get("version") != 2 or state.get("configuration") != _configuration():
		return false
	if not state.get("plots") is Array or state.plots.size() != plots.size():
		return false
	if not state.get("ticks") is int or state.ticks < 0:
		return false
	var seconds: Variant = state.get("elapsed_s")
	if not (seconds is float or seconds is int) or not is_finite(seconds) or seconds < 0:
		return false
	var candidates: Array[Dictionary] = []
	for i in plots.size():
		var saved: Variant = state.plots[i]
		if not saved is Dictionary or saved.get("origin") != plots[i].origin:
			return false
		if not saved.get("state") is Dictionary:
			return false
		var s: Dictionary = saved.state
		if (
			s.get("n") != land.settings.fungi_resolution
			or s.get("dx") != land.settings.fungi_cell_m
			or s.get("options") != land.settings.fungus_for_plot(i).options()
		):
			return false
		if absf(float(s.get("time_s", -1.0)) - seconds) > 1e-10 * maxf(1.0, seconds):
			return false
		var core := ForestFungiNative.new()
		if not core.restore(s):
			return false
		if soil != null and not core.bind_soil(soil.native, int(s.get("soil_patch", -1)), false):
			return false
		if bool(s.get("coupled", false)) != (soil != null):
			return false
		candidates.append(
			{
				"origin": saved.origin,
				"definition": land.settings.fungus_for_plot(i),
				"native": core,
				"fields": core.fields(),
				"metrics": core.metrics()
			}
		)
	plots = candidates
	elapsed_s = seconds
	ticks = state.ticks
	revision += 1
	return true


# gdlint: enable=max-returns
func _configuration() -> Array:
	var c := land.settings
	return [
		c.fungi_resolution,
		c.fungi_cell_m,
		c.fungi_plot_centers,
		c.fungus.options(),
		_fungal_configuration(),
		c.ecology_step_s,
		c.year_speed_multiplier,
		soil != null
	]


func _fungal_configuration() -> Array:
	var result := []
	for index in land.settings.fungi_plot_centers.size():
		var d := land.settings.fungus_for_plot(index)
		result.append([d.species_id, d.trophic_type, d.exchange_radius_m, d.options()])
	return result


func trade(
	position: Vector3, nitrogen: float, phosphorus: float, carbon: float
) -> PackedFloat64Array:
	var result := PackedFloat64Array([0, 0, 0])
	for plot in plots:
		var d: ForestFungusDefinition = plot.definition
		if d.trophic_type != &"ectomycorrhizal" or carbon <= result[0]:
			continue
		var supplied: PackedFloat64Array = plot.native.trade(
			position,
			maxf(0, nitrogen - result[1]),
			maxf(0, phosphorus - result[2]),
			carbon - result[0],
			d.exchange_radius_m
		)
		for element in 3:
			result[element] += supplied[element]
	return result


static func _require(ok: bool) -> void:
	# Evaluate native mutations even in exported builds where assertions are disabled.
	if not ok:
		push_error("Fungal model rejected configuration, forcing or state")
	assert(ok)


func metrics() -> Dictionary:
	var carbon := 0.0
	var nitrogen := 0.0
	var phosphorus := 0.0
	var respired := 0.0
	var error := 0.0
	var edge := 0.0
	var boundary_affected := false
	for plot in plots:
		var m: Dictionary = plot.native.metrics()
		carbon += m.carbon_kg
		nitrogen += m.nitrogen_kg
		phosphorus += m.phosphorus_kg
		respired += m.respired_kg_c
		error += absf(m.balance_error_kg)
		edge += m.edge_biomass_kg
		boundary_affected = boundary_affected or m.boundary_affected
	return {
		"plots": plots.size(),
		"cells": plots.size() * land.settings.fungi_resolution * land.settings.fungi_resolution,
		"cell_m": land.settings.fungi_cell_m,
		"carbon_kg": carbon,
		"nitrogen_kg": nitrogen,
		"phosphorus_kg": phosphorus,
		"respired_kg_c": respired,
		"soil_pools_excluded": soil != null,
		"carbon_error_kg": error,
		"edge_biomass_kg": edge,
		"boundary_affected": boundary_affected,
		"elapsed_s": elapsed_s,
		"mean_step_ms": float(step_usec) / maxf(ticks, 1) / 1000.0
	}


func observation_center() -> Vector2:
	return (
		plots[0].origin
		+ Vector2.ONE * land.settings.fungi_resolution * land.settings.fungi_cell_m / 2.0
	)


func element_totals() -> Vector3:
	var m := metrics()
	return Vector3(m.carbon_kg, m.nitrogen_kg, m.phosphorus_kg)


func inspect(id: int) -> Dictionary:
	if id < 0 or id >= positions.size():
		return {}
	var cells := land.settings.fungi_resolution * land.settings.fungi_resolution
	var plot: Dictionary = plots[id / cells]
	var k := id % cells
	var d: ForestFungusDefinition = plot.definition
	var area := land.settings.fungi_cell_m * land.settings.fungi_cell_m
	return {
		"kind": "fungus",
		"title": d.display_name,
		"subtitle": d.latin_name,
		"description":
		"Плодовые тела показывают запас общей ячейки мицелия. Картинка может представлять одиночный гриб или группу, не отдельный организм с собственной массой.",
		"source_url": d.source_url,
		"alive": plot.fields.fruit[k] > 0,
		"stage": "Плодовые тела · ячейка %d" % k,
		"details":
		{
			"Питание": "Сапротроф" if d.trophic_type == &"saprotroph" else "Эктомикориза",
			"Мицелий": "%.3f г C в ячейке" % (plot.fields.biomass[k] * area * 1000),
			"Плодовые тела": "%.3f г C в ячейке" % (plot.fields.fruit[k] * area * 1000),
			"Область": "%d · ячейка %.2f м" % [id / cells + 1, land.settings.fungi_cell_m],
			"Учёт": "Последний снимок полей; общие запасы модели, не масса нарисованной шляпки"
		}
	}
