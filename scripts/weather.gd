class_name ForestWeather
extends RefCounted

## Seeded fronts on the shared hydrological clock, not a regional forecast.
## Uniform snow is water equivalent (m); actual liquid goes through native water.
const FRONT_S := ForestWeatherFront.INTERVAL_S
var clouds: ForestCloudField
var settings: ForestSettings
var elapsed_s := 0.0
var snow_water_m := 0.0
var precipitation_m := 0.0
var liquid_m := 0.0
var forced := -1
var forced_until_s := 0.0


func _init(configuration: ForestSettings) -> void:
	settings = configuration
	clouds = ForestCloudField.new(settings)


func sample(climate: Dictionary, at_s := -1.0) -> Dictionary:
	var t := elapsed_s if at_s < 0 else at_s
	var result := climate.duplicate()
	ForestWeatherFront.prepare(
		result,
		settings.seed,
		settings.extent,
		t,
		settings.weather_resolution,
		settings.weather_front_speed_m_s
	)
	result.front_forced = forced
	result.front_forced_until_s = forced_until_s
	result.front_rainfall_m_s = settings.rainfall_m_s
	result = ForestWeatherFront.local(result, Vector2.ONE * settings.extent * .5)
	result.cloud_offset_m = clouds.offset_at(t)
	result.gust_offset_m = clouds.wind_offset_at(t) * .7
	result.snow_water_m = snow_water_m

	return result


func step(dt: float, climate: Dictionary) -> Dictionary:
	var forcing := sample(climate, elapsed_s + dt * .5)
	var melt := 0.0
	if forcing.temperature_c > 0:
		# SI degree-day melt from the existing domain-mean snow reservoir.
		melt = minf(snow_water_m, forcing.temperature_c * 3.0 / 1000 / 86400 * dt)
	var field := clouds.grid(forcing, melt / dt)
	var amount: float = field.mean_precipitation_m_s * dt
	precipitation_m += amount
	var liquid: float = field.mean_liquid_m_s * dt + melt
	var rates: PackedFloat64Array = field.rates
	snow_water_m += amount - field.mean_liquid_m_s * dt - melt
	liquid_m += liquid
	forcing.precipitation_m_s = field.mean_precipitation_m_s
	forcing.liquid_m_s = liquid / dt
	forcing.liquid_field_m_s = rates
	forcing.snow_water_m = snow_water_m
	elapsed_s += dt
	return forcing


func toggle(raining: bool) -> void:
	forced = 0 if raining else 1
	forced_until_s = elapsed_s + FRONT_S


func snapshot() -> Dictionary:
	return {
		"version": 3,
		"cloud_configuration": clouds.configuration(),
		"seed": settings.seed,
		"elapsed_s": elapsed_s,
		"snow_water_m": snow_water_m,
		"precipitation_m": precipitation_m,
		"liquid_m": liquid_m,
		"forced": forced,
		"forced_until_s": forced_until_s
	}


func restore(state: Dictionary) -> bool:
	if (
		state.get("version") not in [1, 2, 3]
		or state.get("seed") != settings.seed
		or not _compatible_cloud_configuration(state)
	):
		return false
	for field in ["elapsed_s", "snow_water_m", "precipitation_m", "liquid_m", "forced_until_s"]:
		if not (state.get(field) is float or state.get(field) is int):
			return false
		if not is_finite(state[field]) or state[field] < 0:
			return false
	if not state.get("forced") is int or state.forced not in [-1, 0, 1]:
		return false
	if absf(state.precipitation_m - state.liquid_m - state.snow_water_m) > 1e-9:
		return false
	for field in [
		"elapsed_s", "snow_water_m", "precipitation_m", "liquid_m", "forced", "forced_until_s"
	]:
		set(field, state[field])
	return true


func _compatible_cloud_configuration(state: Dictionary) -> bool:
	if state.get("version") == 1:
		return true
	if state.get("cloud_configuration") == clouds.configuration():
		return true
	# Version 2 used a fixed cloud velocity. Preserve its water/snow ledger;
	# future transport follows the new wind-driven scenario after migration.
	var old: Variant = state.get("cloud_configuration")
	var current := clouds.configuration()
	return (
		state.get("version") == 2
		and old is Array
		and old.size() == 6
		and old[0] == 1
		and old.slice(1, 5) == current.slice(1, 5)
		and old[5] is Vector2
		and old[5].is_finite()
	)
