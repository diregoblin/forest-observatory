class_name ForestWeather
extends RefCounted

## Seeded fronts on the shared hydrological clock, not a regional forecast.
## Uniform snow is water equivalent (m); actual liquid goes through native water.
const FRONT_S := 85.0
var settings: ForestSettings
var elapsed_s := 0.0
var snow_water_m := 0.0
var precipitation_m := 0.0
var liquid_m := 0.0
var forced := -1
var forced_until_s := 0.0


func _init(configuration: ForestSettings) -> void:
	settings = configuration


func _front(index: int) -> Vector4:
	if index <= 0:
		return Vector4(.18, 0, 2.0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed + index * 104729 + 9031
	var u := rng.randf()
	if u < .27:
		return Vector4(.12, 0, rng.randf_range(.5, 3), 3.0)  # dry spell
	if u < .52:
		return Vector4(.62, .06, rng.randf_range(2, 6), -.8)
	if u < .91:
		return Vector4(.94, rng.randf_range(.35, .8), rng.randf_range(3, 9), -2.5)
	return Vector4(1, 1, rng.randf_range(15, 22), -4)  # rare storm


func sample(climate: Dictionary, at_s := -1.0) -> Dictionary:
	var t := elapsed_s if at_s < 0 else at_s
	var index := int(t / FRONT_S)
	var a := _front(index)
	var b := _front(index + 1)
	var phase := smoothstep(.12, .82, fposmod(t, FRONT_S) / FRONT_S)
	var front := a.lerp(b, phase)
	var rain := front.y
	if forced >= 0 and t < forced_until_s:
		rain = float(forced)
		front.x = .96 if forced == 1 else .16
	var result := climate.duplicate()
	result.temperature_c += front.w
	result.growth = clampf((result.temperature_c - 5.0) / 14.0, 0, 1) * (1 - .28 * front.x)
	result.evaporation *= (1 - .6 * front.x) * (1 + front.z * .035)
	result.cloud_cover = front.x
	result.wind_m_s = front.z
	result.wind_direction = Vector2(cos(index * .71 + .4), sin(index * .71 + .4))
	result.precipitation_m_s = rain * settings.rainfall_m_s
	result.rain_fraction = rain if result.temperature_c > 0 else 0.0
	result.snow_water_m = snow_water_m
	result.weather_time_s = t
	result.weather_title = (
		"Снег"
		if rain > .08 and result.temperature_c <= 0
		else (
			"Ливень"
			if rain > .78
			else ("Дождь" if rain > .12 else ("Облачно" if front.x > .5 else "Ясно"))
		)
	)
	if front.z >= 14:
		result.weather_title = "Шторм · " + result.weather_title
	return result


func step(dt: float, climate: Dictionary) -> Dictionary:
	var forcing := sample(climate, elapsed_s + dt * .5)
	var amount: float = forcing.precipitation_m_s * dt
	precipitation_m += amount
	var liquid := amount
	if forcing.temperature_c <= 0:
		snow_water_m += amount
		liquid = 0
	else:
		# Scenario degree-day melt, in SI water time, not accelerated year time.
		var melt := minf(snow_water_m, forcing.temperature_c * 3.0 / 1000 / 86400 * dt)
		snow_water_m -= melt
		liquid += melt
	liquid_m += liquid
	forcing.liquid_m_s = liquid / dt
	forcing.snow_water_m = snow_water_m
	elapsed_s += dt
	return forcing


func toggle(raining: bool) -> void:
	forced = 0 if raining else 1
	forced_until_s = elapsed_s + FRONT_S


func snapshot() -> Dictionary:
	return {
		"version": 1,
		"seed": settings.seed,
		"elapsed_s": elapsed_s,
		"snow_water_m": snow_water_m,
		"precipitation_m": precipitation_m,
		"liquid_m": liquid_m,
		"forced": forced,
		"forced_until_s": forced_until_s
	}


func restore(state: Dictionary) -> bool:
	if state.get("version") != 1 or state.get("seed") != settings.seed:
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
