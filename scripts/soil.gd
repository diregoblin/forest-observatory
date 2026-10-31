class_name ForestSoil
extends RefCounted

## The only owner of ecosystem soil C/N/P. Refinement moves, never copies,
## reserves out of covered coarse area. Hydrological water remains in watershed.
var land: ForestLandscape
var native := ForestSoilNative.new()


func _init(water: ForestWatershed) -> void:
	land = water.landscape
	# Illustrative scenario stocks, not measured valley chemistry.
	var ok := native.configure(
		water.resolution,
		water.cell_size,
		Vector3(2, .1, .008),
		Vector3(0, .02, .002),
		Vector3(.05, .0025, .0002)
	)
	assert(ok)


func step(dt: float, water: ForestWatershed) -> void:
	var climate := ForestClimate.sample(
		float(native.metrics().elapsed_s) + dt * .5,
		land.settings.start_day,
		land.settings.latitude_deg
	)
	var ok := native.advance(dt, water.soil, climate.temperature_c)
	assert(ok)


func deposit(position: Vector3, amount: Vector3, organic := true) -> Vector3:
	return native.deposit(position, amount, organic)


func withdraw(position: Vector3, amount: Vector3, organic := false) -> Vector3:
	return native.withdraw(position, amount, organic)


func withdraw_many(
	positions: PackedVector3Array, amounts: PackedVector3Array, organic := false
) -> PackedVector3Array:
	return native.withdraw_many(positions, amounts, organic)


func sample(position: Vector3) -> Dictionary:
	return native.sample(position)


func metrics() -> Dictionary:
	return native.metrics()


func element_totals() -> Vector3:
	var m := metrics()
	return Vector3(m.carbon_kg, m.nitrogen_kg, m.phosphorus_kg)


func snapshot() -> Dictionary:
	return native.snapshot()


func restore(state: Dictionary) -> bool:
	if (
		state.get("n") != land.settings.water_resolution
		or state.get("dx") != land.settings.extent / land.settings.water_resolution
	):
		return false
	return native.restore(state)


func deposit_elements(
	position: Vector3, carbon: float, nitrogen: float, phosphorus: float, organic := true
) -> PackedFloat64Array:
	return native.deposit_elements(position, carbon, nitrogen, phosphorus, organic)


func withdraw_nutrients(
	positions: PackedVector3Array, nitrogen: PackedFloat64Array, phosphorus: PackedFloat64Array
) -> Dictionary:
	return native.withdraw_nutrients(positions, nitrogen, phosphorus)
