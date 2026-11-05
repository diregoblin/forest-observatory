class_name ForestCloudField
extends RefCounted

## Immutable periodic cloud input, shared with the sky and precipitation view.
## Model sampling uses double precision in the native kernel.
const SOURCE := preload("res://art/clouds/weather-density.png")
const REVISION := 2
static var tile: Image
static var values := PackedFloat64Array()
static var source_hash := ""
var settings: ForestSettings
var native := ForestWeatherFieldNative.new()
var span_m := 4096.0
var transport_cache: Array[Vector4] = [Vector4.ZERO]
var wind_seed_phase := Vector2.ZERO
var last_transport_time := -INF
var last_transport_state := Vector4.ZERO


func _init(configuration: ForestSettings) -> void:
	settings = configuration
	var rng := RandomNumberGenerator.new()
	rng.seed = settings.seed + 54037
	wind_seed_phase = Vector2(rng.randf_range(-500, 500), rng.randf_range(-500, 500))
	span_m = settings.extent * settings.cloud_span_factor
	if tile == null:
		tile = SOURCE.get_image().duplicate()
		assert(tile != null and tile.get_width() == tile.get_height())
		tile.convert(Image.FORMAT_L8)
		var bytes := tile.get_data()
		values.resize(bytes.size())
		for i in bytes.size():
			values[i] = bytes[i] / 255.0
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(bytes)
		source_hash = digest.finish().hex_encode()
	assert(native.configure(tile.get_width(), span_m, values))


func configuration() -> Array:
	return [
		REVISION,
		source_hash,
		settings.water_resolution,
		settings.extent,
		span_m,
		settings.weather_front_speed_m_s,
		settings.weather_resolution
	]


func _transport_velocity(time_s: float) -> Vector2:
	var index := floori(time_s / ForestWeatherFront.INTERVAL_S)
	var a := ForestWeatherFront.regime(settings.seed, index)
	var b := ForestWeatherFront.regime(settings.seed, index + 1)
	var weight := smoothstep(
		.12, .82, fposmod(time_s, ForestWeatherFront.INTERVAL_S) / ForestWeatherFront.INTERVAL_S
	)
	return (ForestWeatherFront.direction(index) * a.z).lerp(
		ForestWeatherFront.direction(index + 1) * b.z, weight
	)


func _integrate(start: Vector4, begin_s: float, end_s: float) -> Vector4:
	var state := start
	var t := begin_s
	while t < end_s:
		var dt := minf(5, end_s - t)
		var velocity := _transport_velocity(t + dt * .5)
		var phase := (Vector2(state.x, state.y) + velocity * dt * .5) * .7
		var envelope := 0.0
		# Coherent deck transport averages the same unsheltered gust function
		# over the plot. Individual cloud texels are not fluid parcels.
		for z in 3:
			for x in 3:
				var p := (Vector2(x, z) + Vector2.ONE * .5) * settings.extent / 3.0
				envelope += ForestWeatherFront.gust_envelope(p - phase + wind_seed_phase) / 9.0
		state += Vector4(velocity.x, velocity.y, velocity.x * envelope, velocity.y * envelope) * dt
		t += dt
	return state


func _transport_at(time_s: float) -> Vector4:
	var t := maxf(0, time_s)
	if t == last_transport_time:
		return last_transport_state
	var interval := ForestWeatherFront.INTERVAL_S
	var index := floori(t / interval)
	while transport_cache.size() <= index:
		var begin := (transport_cache.size() - 1) * interval
		transport_cache.append(_integrate(transport_cache[-1], begin, begin + interval))
	last_transport_time = t
	last_transport_state = _integrate(transport_cache[index], index * interval, t)
	return last_transport_state


func wind_offset_at(time_s: float) -> Vector2:
	var state := _transport_at(time_s)
	return Vector2(state.x, state.y)


func offset_at(time_s: float) -> Vector2:
	var state := _transport_at(time_s)
	return Vector2(fposmod(state.z, span_m), fposmod(state.w, span_m))


func offset(climate: Dictionary) -> Vector2:
	# Avoid evaluating a fallback on the model's cache while its worker owns it.
	return (
		climate.cloud_offset_m
		if climate.has("cloud_offset_m")
		else offset_at(climate.get("weather_time_s", 0.0))
	)


func grid(climate: Dictionary, uniform_liquid_m_s := 0.0) -> Dictionary:
	var fields := ForestWeatherFront.grid(climate, settings.extent)
	return native.sample_spatial_grid(
		settings.water_resolution,
		settings.extent,
		offset(climate),
		fields.resolution,
		fields.cloud_cover,
		fields.precipitation_potential_m_s,
		fields.temperature_c,
		uniform_liquid_m_s
	)


func weights(
	climate: Dictionary, fields: Dictionary = {}, liquid_only := false
) -> PackedFloat64Array:
	if fields.is_empty():
		fields = ForestWeatherFront.grid(climate, settings.extent)
	var potential: PackedFloat64Array = fields.precipitation_potential_m_s.duplicate()
	if climate.has("front_extent_m"):
		for i in potential.size():
			potential[i] /= maxf(1e-20, settings.rainfall_m_s)
	else:
		potential.fill(1.0)
	var temperature: PackedFloat64Array = fields.temperature_c
	if not liquid_only:
		temperature = temperature.duplicate()
		temperature.fill(20.0)
	return (
		native
		. sample_spatial_grid(
			settings.water_resolution,
			settings.extent,
			offset(climate),
			fields.resolution,
			fields.cloud_cover,
			potential,
			temperature,
			0.0
		)
		. rates
	)


func local_weight(position: Vector2, climate: Dictionary) -> float:
	var density: float = native.sample_density(
		position.x, position.y, settings.extent, offset(climate)
	)
	var local_climate := ForestWeatherFront.local(climate, position)
	var threshold: float = .69 - .32 * local_climate.get("cloud_cover", .18)
	var weight := smoothstep(threshold + .10, threshold + .24, density)
	return (
		weight * local_climate.precipitation_potential_m_s / maxf(1e-20, settings.rainfall_m_s)
		if climate.has("front_extent_m")
		else weight
	)
