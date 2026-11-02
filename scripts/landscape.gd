class_name ForestLandscape
extends RefCounted

var settings: ForestSettings
var noise := FastNoiseLite.new()
var habitat_noise := FastNoiseLite.new()


func _init(config: ForestSettings) -> void:
	settings = config
	noise.seed = settings.seed
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	habitat_noise.seed = settings.seed + 2153
	habitat_noise.frequency = 3.8 / settings.extent
	habitat_noise.fractal_octaves = 2


func habitat_at(x: float, z: float) -> Vector4:
	# Shared continuous site mosaic, never a camera-dependent biome switch.
	var distance := absf(x - channel_x(z))
	# Broad forest stands on the slopes, with smaller genuine openings between.
	var opening := 1.0 - smoothstep(-.32, -.03, habitat_noise.get_noise_2d(x, z))
	var clearing_center := settings.fungi_plot_centers[0] * settings.extent
	opening = maxf(opening, 1.0 - smoothstep(22, 42, Vector2(x, z).distance_to(clearing_center)))
	var shore_patch := smoothstep(-.18, .16, habitat_noise.get_noise_2d(x + 781, z * 1.8))
	var sand := (1.0 - smoothstep(7, 23, distance)) * shore_patch
	var meadow := (1.0 - smoothstep(25, 55, distance)) * (1.0 - sand)
	var forest := (1.0 - sand - meadow) * (1.0 - opening)
	return Vector4(forest, maxf(0, 1.0 - forest - meadow - sand), meadow, sand)


func stand_at(x: float, z: float) -> float:
	# Jittered Voronoi stands, about 90 m across. One stable selection variate
	# per stand; species/resources interpret it, landscape knows no species IDs.
	var span := settings.extent / 5.5
	var grid := Vector2i(floori(x / span), floori(z / span))
	var best := INF
	var value := 0.0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := grid + Vector2i(dx, dz)
			var code := hash(Vector3i(key.x, key.y, settings.seed)) & 0x7fffffff
			var center := (
				(
					Vector2(key)
					+ Vector2(.2 + .6 * (code % 997) / 997.0, .2 + .6 * (code % 991) / 991.0)
				)
				* span
			)
			var distance := Vector2(x, z).distance_squared_to(center)
			if distance < best:
				best = distance
				value = float(code % 65521) / 65521.0
	return value


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
