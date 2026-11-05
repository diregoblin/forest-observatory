class_name ForestCloudField
extends RefCounted

## Immutable periodic cloud input, shared with the sky and precipitation view.
## Model sampling uses double precision in the native kernel.
const SOURCE := preload("res://art/clouds/weather-density.png")
const REVISION := 1
static var tile: Image
static var values := PackedFloat64Array()
static var source_hash := ""
var settings: ForestSettings
var native := ForestWeatherFieldNative.new()
var span_m := 4096.0


func _init(configuration: ForestSettings) -> void:
	settings = configuration
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
		settings.cloud_velocity_m_s
	]


func offset_at(time_s: float) -> Vector2:
	return Vector2(
		fposmod(settings.cloud_velocity_m_s.x * time_s, span_m),
		fposmod(settings.cloud_velocity_m_s.y * time_s, span_m)
	)


func grid(climate: Dictionary, uniform_liquid_m_s := 0.0) -> Dictionary:
	return native.sample_grid(
		settings.water_resolution,
		settings.extent,
		climate.get("cloud_offset_m", offset_at(climate.get("weather_time_s", 0.0))),
		climate.get("cloud_cover", .18),
		climate.get("precipitation_potential_m_s", climate.get("precipitation_m_s", 0.0)),
		uniform_liquid_m_s
	)


func weights(climate: Dictionary) -> PackedFloat64Array:
	return (
		native
		. sample_grid(
			settings.water_resolution,
			settings.extent,
			climate.get("cloud_offset_m", offset_at(climate.get("weather_time_s", 0.0))),
			climate.get("cloud_cover", .18),
			1.0,
			0.0
		)
		. rates
	)


func local_weight(position: Vector2, climate: Dictionary) -> float:
	var density: float = native.sample_density(
		position.x,
		position.y,
		settings.extent,
		climate.get("cloud_offset_m", offset_at(climate.get("weather_time_s", 0.0)))
	)
	var threshold: float = .69 - .32 * climate.get("cloud_cover", .18)
	return smoothstep(threshold + .10, threshold + .24, density)
