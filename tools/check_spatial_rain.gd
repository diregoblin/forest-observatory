extends SceneTree

const CONFIG = preload("res://data/forest.tres")


func _initialize() -> void:
	create_timer(30).timeout.connect(func(): quit(1))
	_run.call_deferred()


func independent_density(clouds: ForestCloudField, p: Vector2, offset: Vector2) -> float:
	var n := ForestCloudField.tile.get_width()
	var qx: float = (
		(.5 + (float(p.x) - clouds.settings.extent * .5 - offset.x) / clouds.span_m) * n - .5
	)
	var qz: float = (
		(.5 + (float(p.y) - clouds.settings.extent * .5 - offset.y) / clouds.span_m) * n - .5
	)
	var base := Vector2i(floor(qx), floor(qz))
	var fx: float = qx - floor(qx)
	var fz: float = qz - floor(qz)
	var total := 0.0
	for z in 2:
		for x in 2:
			var at := Vector2i(posmod(base.x + x, n), posmod(base.y + z, n))
			var w: float = (1 - fx if x == 0 else fx) * (1 - fz if z == 0 else fz)
			total += ForestCloudField.tile.get_pixelv(at).r * w
	return total


func _run() -> void:
	var settings: ForestSettings = CONFIG.duplicate(true)
	var weather := ForestWeather.new(settings)
	weather.toggle(false)
	var climate := ForestClimate.sample(0, 200)
	var forcing := weather.step(.5, climate)
	var field: PackedFloat64Array = forcing.liquid_field_m_s
	var total := 0.0
	var dry := 0
	var wet := 0
	var maximum_error := 0.0
	var dx := settings.extent / settings.water_resolution
	for z in settings.water_resolution:
		for x in settings.water_resolution:
			var p := Vector2((x + .5) * dx, (z + .5) * dx)
			var d := independent_density(weather.clouds, p, forcing.cloud_offset_m)
			var threshold: float = .69 - .32 * forcing.cloud_cover
			var expected: float = (
				smoothstep(threshold + .10, threshold + .24, d) * settings.rainfall_m_s
			)
			var v := field[z * settings.water_resolution + x]
			maximum_error = maxf(maximum_error, absf(v - expected))
			total += v
			dry += int(v == 0)
			wet += int(v > 1e-8)
	print("INDEPENDENT_RAIN_ERROR ", maximum_error)
	assert(maximum_error < 1e-11, "Independent image interpolation and rain threshold")
	assert(dry > 0 and wet > 0, "Forced rain has both dry gaps and wet cores")
	assert(absf(total / field.size() * .5 - weather.liquid_m) < 1e-14)
	# Feed the actual field into the real wrapper; known source volume is separate.
	settings.tree_attempts = 0
	var water := ForestWatershed.new(ForestLandscape.new(settings))
	var input_before: float = water.native.metrics().input_m3
	water.step(.5, false, forcing.liquid_m_s, field)
	var actual: float = water.native.metrics().input_m3 - input_before
	var expected_volume: float = total * dx * dx * .5
	var sources: float = (settings.headwater_m3_s + settings.spring_flow_m3_s) * .5
	assert(absf(actual - expected_volume - sources) < 1e-8, "Local rain sum reaches water ledger")
	var saved := weather.snapshot()
	var copy := ForestWeather.new(settings)
	assert(copy.restore(saved))
	for tick in 100:
		assert(copy.step(.5, climate) == weather.step(.5, climate))
	assert(copy.snapshot() == weather.snapshot(), "Exact spatial continuation")
	var before := copy.snapshot()
	var bad := saved.duplicate(true)
	bad.cloud_configuration[1] = "wrong-source"
	assert(not copy.restore(bad) and copy.snapshot() == before)
	var legacy := saved.duplicate(true)
	legacy.version = 1
	legacy.erase("cloud_configuration")
	assert(copy.restore(legacy), "Legacy mean-snow weather migrates")
	var winter := ForestWeather.new(settings)
	winter.toggle(false)
	var snowfall := winter.step(.5, ForestClimate.sample(0, 20))
	assert(winter.snow_water_m > 0 and snowfall.liquid_field_m_s.count(0) == field.size())
	winter.toggle(true)
	var melt := winter.step(.5, climate)
	for rate in melt.liquid_field_m_s:
		assert(rate == melt.liquid_field_m_s[0], "Uniform mean snowmelt")
	assert(absf(winter.precipitation_m - winter.liquid_m - winter.snow_water_m) < 1e-12)
	var moved := forcing.duplicate()
	moved.cloud_offset_m += Vector2(37, -19)
	var start := Vector2(123.4, 278.9)
	assert(
		(
			absf(
				(
					weather.clouds.local_weight(start, forcing)
					- weather.clouds.local_weight(start + Vector2(37, -19), moved)
				)
			)
			< 1e-6
		),
		"Rain and cloud density translate together"
	)
	var dry_climate := forcing.duplicate()
	dry_climate.precipitation_potential_m_s = 0.0
	assert(weather.clouds.grid(dry_climate).rates.count(0) == field.size())
	var report := {
		"passed": true,
		"dry_cells": dry,
		"wet_cells": wet,
		"max_independent_rate_error_m_s": maximum_error,
		"rain_volume_m3": expected_volume,
		"water_input_m3": actual,
		"cloud_velocity_m_s": str(settings.cloud_velocity_m_s),
		"save_continuation_ticks": 100
	}
	var file := FileAccess.open("res://artifacts/spatial-rain-check.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("SPATIAL_RAIN_CHECK ", JSON.stringify(report))
	quit()
