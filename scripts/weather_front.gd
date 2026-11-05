class_name ForestWeatherFront
extends RefCounted

## Prescribed translating air masses. Relative humidity is a scenario forcing;
## no prognostic vapour reservoir, pressure solver or condensation feedback.
const INTERVAL_S := 85.0
const GRID_N := 16
const SPEED_M_S := 8.0


static func regime(seed_value: int, index: int) -> Vector4:
	if index <= 0:
		return Vector4(.18, 0, 2.0, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + index * 104729 + 9031
	var u := rng.randf()
	if u < .27:
		return Vector4(.12, 0, rng.randf_range(.5, 3), 3.0)
	if u < .52:
		return Vector4(.62, .06, rng.randf_range(2, 6), -.8)
	if u < .91:
		return Vector4(.94, rng.randf_range(.35, .8), rng.randf_range(3, 9), -2.5)
	return Vector4(1, 1, rng.randf_range(18, 24), -4)


static func direction(index: int) -> Vector2:
	# Incoming air masses span the full compass, with a smooth wind turn.
	return Vector2.from_angle(.4 + index * .71)


static func prepare(
	climate: Dictionary,
	seed_value: int,
	extent: float,
	time_s: float,
	resolution := GRID_N,
	speed_m_s := SPEED_M_S
) -> void:
	climate.front_extent_m = extent
	climate.front_speed_m_s = speed_m_s
	climate.front_resolution = resolution
	climate.front_temperature_c = climate.temperature_c
	climate.front_evaporation = climate.evaporation
	climate.weather_time_s = time_s
	var lag := extent * sqrt(2.0) * .5 / speed_m_s
	var first := maxi(0, floori((time_s - lag) / INTERVAL_S))
	var last := maxi(0, floori((time_s + lag) / INTERVAL_S)) + 1
	climate.front_first = first
	climate.front_last = last
	for index in range(first, last + 1):
		var value := regime(seed_value, index)
		climate["front_%d_cloud_rain" % index] = Vector2(value.x, value.y)
		climate["front_%d_wind_temp" % index] = Vector2(value.z, value.w)


static func local(climate: Dictionary, position: Vector2, compact := false) -> Dictionary:
	if not climate.has("front_extent_m"):
		return climate
	var first: int = climate.front_first
	var cloud_rain: Vector2 = climate["front_%d_cloud_rain" % first]
	var wind_temp: Vector2 = climate["front_%d_wind_temp" % first]
	var wind := direction(first) * wind_temp.x
	for index in range(first, climate.front_last):
		var lag: float = (
			(position - Vector2.ONE * climate.front_extent_m * .5).dot(direction(index + 1))
			/ climate.front_speed_m_s
		)
		var phase := smoothstep(
			.12, .82, (climate.weather_time_s - lag - index * INTERVAL_S) / INTERVAL_S
		)
		var target: Vector2 = climate["front_%d_cloud_rain" % (index + 1)]
		var target_wind: Vector2 = climate["front_%d_wind_temp" % (index + 1)]
		cloud_rain = cloud_rain.lerp(target, phase)
		wind_temp = wind_temp.lerp(target_wind, phase)
		wind = wind.lerp(direction(index + 1) * target_wind.x, phase)
	if (
		climate.get("front_forced", -1) >= 0
		and climate.weather_time_s < climate.front_forced_until_s
	):
		cloud_rain = Vector2(.96, 1) if climate.front_forced == 1 else Vector2(.16, 0)
	var result := {} if compact else climate.duplicate()
	result.day = climate.get("day", 150.0)
	result.snow_water_m = climate.get("snow_water_m", 0.0)
	result.temperature_c = climate.front_temperature_c + wind_temp.y
	result.cloud_cover = cloud_rain.x
	result.relative_humidity = clampf(.42 + .34 * cloud_rain.x + .20 * cloud_rain.y, 0, 1)
	result.wind_m_s = wind.length()
	result.wind_direction = wind.normalized() if wind.length_squared() > 0 else direction(0)
	result.evaporation = (
		climate.front_evaporation
		* (1 - .6 * cloud_rain.x)
		* (1 + wind.length() * .035)
		* (1 - .35 * result.relative_humidity)
	)
	result.growth = clampf((result.temperature_c - 5) / 14.0, 0, 1) * (1 - .28 * cloud_rain.x)
	result.precipitation_potential_m_s = cloud_rain.y * climate.front_rainfall_m_s
	result.precipitation_m_s = result.precipitation_potential_m_s
	result.rain_fraction = cloud_rain.y if result.temperature_c > 0 else 0.0
	if not compact:
		result.weather_title = (
			"Снег"
			if cloud_rain.y > .08 and result.temperature_c <= 0
			else (
				"Ливень"
				if cloud_rain.y > .78
				else (
					"Дождь" if cloud_rain.y > .12 else ("Облачно" if cloud_rain.x > .5 else "Ясно")
				)
			)
		)
		if result.wind_m_s >= 14:
			result.weather_title = "Шторм · " + result.weather_title
	return result


static func grid(climate: Dictionary, extent: float) -> Dictionary:
	var n: int = climate.get("front_resolution", GRID_N)
	var fields := {"resolution": n}
	for key in [
		"cloud_cover",
		"precipitation_potential_m_s",
		"temperature_c",
		"relative_humidity",
		"wind_x",
		"wind_z",
		"evaporation",
		"growth"
	]:
		var data := PackedFloat64Array()
		data.resize(n * n)
		fields[key] = data
	for z in n:
		for x in n:
			var local_climate := local(
				climate, (Vector2(x, z) + Vector2.ONE * .5) * extent / n, true
			)
			var index := z * n + x
			for key in [
				"cloud_cover",
				"precipitation_potential_m_s",
				"temperature_c",
				"relative_humidity",
				"evaporation",
				"growth"
			]:
				fields[key][index] = local_climate.get(
					key, .5 if key == "relative_humidity" else 0.0
				)
			var wind: Vector2 = (
				local_climate.get("wind_direction", Vector2.RIGHT)
				* local_climate.get("wind_m_s", 0.0)
			)
			fields.wind_x[index] = wind.x
			fields.wind_z[index] = wind.y
	return fields


static func value(data: PackedFloat64Array, position: Vector2, extent: float) -> float:
	var n := roundi(sqrt(data.size()))
	var p := (position / extent).clamp(Vector2.ZERO, Vector2.ONE) * n - Vector2.ONE * .5
	var x := floori(p.x)
	var z := floori(p.y)
	var a := clampi(z, 0, n - 1) * n
	var b := clampi(z + 1, 0, n - 1) * n
	var left := clampi(x, 0, n - 1)
	var right := clampi(x + 1, 0, n - 1)
	return lerpf(
		lerpf(data[a + left], data[a + right], p.x - x),
		lerpf(data[b + left], data[b + right], p.x - x),
		p.y - z
	)


static func gust_envelope(p: Vector2) -> float:
	# Compact, staggered packets with a broad transverse envelope. Transport
	# uses the accumulated wind displacement, so a weather turn cannot teleport
	# an entire field as absolute_time * new_direction would.
	var a := pow(maxf(0.0, cos(p.x * .061 + p.y * .027)), 4)
	var b := pow(maxf(0.0, cos(p.x * -.019 + p.y * .043)), 2)
	return .48 + 1.25 * a * (.35 + .65 * b) + .18 * b
