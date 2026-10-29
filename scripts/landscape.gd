class_name ForestLandscape
extends RefCounted

var settings: ForestSettings
var noise := FastNoiseLite.new()


func _init(config: ForestSettings) -> void:
	settings = config
	noise.seed = settings.seed
	noise.frequency = 0.012
	noise.fractal_octaves = 4


func channel_x(z: float) -> float:
	var size := settings.extent
	return (
		size
		* (.48828125 + .056640625 * sin(z / size * 7.68) + .01953125 * sin(z / size * 16.384 + 1.0))
	)


func height_at(x: float, z: float) -> float:
	var d := absf(x - channel_x(z))
	var hills := noise.get_noise_2d(x, z)
	var relief := pow(d / 100.0, 1.55) * 14.0
	var banks := 2.3 * (1.0 - exp(-pow(d / 12.0, 2.0)))
	var ripples := hills * 8.0 * smoothstep(12.0, 85.0, d)
	return 7.0 + (settings.extent - z) * 0.023 + relief + banks + ripples


func ground_color(x: float, z: float) -> Color:
	var d := absf(x - channel_x(z))
	var n := (noise.get_noise_2d(x * 2.0, z * 2.0) + 1.0) * 0.5
	var grass := Color(0.31, 0.38, 0.19).lerp(Color(0.47, 0.47, 0.29), n)
	var earth := Color(0.31, 0.29, 0.21)
	return earth.lerp(grass, smoothstep(7.0, 19.0, d))


func channel_barrier() -> ForestBarrier:
	var barrier := ForestBarrier.new()
	barrier.barrier_id = &"observation_barrier"
	var dx := settings.extent / settings.water_resolution
	var z := (int(settings.dam_fraction * settings.water_resolution) + 1) * dx
	var x := channel_x(z)
	barrier.start = Vector2(x - settings.dam_width / 2, z)
	barrier.end = Vector2(x + settings.dam_width / 2, z)
	barrier.crest = height_at(x, z) + settings.dam_height
	return barrier
