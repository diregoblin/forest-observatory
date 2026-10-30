class_name ForestFungi
extends RefCounted

## Independent, always-active isolated observation plots, NOT a tiled whole forest.
## Carbon pools are authoritative in native float64. Water is read-only forcing.
var land: ForestLandscape
var plots: Array[Dictionary] = []
var elapsed_s := 0.0
var ticks := 0
var step_usec := 0
var revision := 0  # Display invalidation only; not a biological state variable.


func _init(water: ForestWatershed) -> void:
	land = water.landscape
	var config := land.settings
	var n := config.fungi_resolution
	var dx := config.fungi_cell_m
	var size := n * dx
	var definition := config.fungus
	for index in config.fungi_plot_centers.size():
		var center := config.fungi_plot_centers[index] * config.extent
		var origin := Vector2(
			clampf(center.x - size / 2, 0, config.extent - size),
			clampf(center.y - size / 2, 0, config.extent - size)
		)
		var b := PackedFloat64Array()
		var r := PackedFloat64Array()
		var litter := PackedFloat64Array()
		b.resize(n * n)
		r.resize(n * n)
		litter.resize(n * n)
		for y in n:
			for x in n:
				var k := y * n + x
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
		plots.append(
			{"origin": origin, "native": core, "fields": core.fields(), "metrics": core.metrics()}
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
		"version": 1,
		"configuration": _configuration(),
		"elapsed_s": elapsed_s,
		"ticks": ticks,
		"plots": states
	}


# Explicit rejection guards keep untrusted checkpoint validation atomic and readable.
# gdlint: disable=max-returns
func restore(state: Dictionary) -> bool:
	if state.get("version") != 1 or state.get("configuration") != _configuration():
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
			or s.get("options") != land.settings.fungus.options()
		):
			return false
		if absf(float(s.get("time_s", -1.0)) - seconds) > 1e-10 * maxf(1.0, seconds):
			return false
		var core := ForestFungiNative.new()
		if not core.restore(s):
			return false
		candidates.append(
			{
				"origin": saved.origin,
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
		c.ecology_step_s,
		c.ecology_year_s
	]


static func _require(ok: bool) -> void:
	# Evaluate native mutations even in exported builds where assertions are disabled.
	if not ok:
		push_error("Fungal model rejected configuration, forcing or state")
	assert(ok)


func metrics() -> Dictionary:
	var carbon := 0.0
	var error := 0.0
	var edge := 0.0
	var boundary_affected := false
	for plot in plots:
		var m: Dictionary = plot.native.metrics()
		carbon += m.carbon_kg
		error += absf(m.balance_error_kg)
		edge += m.edge_biomass_kg
		boundary_affected = boundary_affected or m.boundary_affected
	return {
		"plots": plots.size(),
		"cells": plots.size() * land.settings.fungi_resolution * land.settings.fungi_resolution,
		"cell_m": land.settings.fungi_cell_m,
		"carbon_kg": carbon,
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
