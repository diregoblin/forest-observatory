class_name ForestEcologyClock
extends RefCounted

## Fixed-step ecosystem time, independent of hydrological throughput/speed.
## Day/night and annual phenology have independently configurable periods.
var settings: ForestSettings
var elapsed_s := 0.0
var pending_s := 0.0
var ticks := 0


func _init(configuration: ForestSettings) -> void:
	settings = configuration


func request(dt: float) -> void:
	assert(is_finite(dt) and dt >= 0)
	pending_s += dt


func step() -> bool:
	if pending_s + 1e-10 < settings.ecology_step_s:
		return false
	pending_s = maxf(0, pending_s - settings.ecology_step_s)
	ticks += 1
	elapsed_s = ticks * settings.ecology_step_s
	return true


func biological_step_s() -> float:
	return settings.ecology_step_s * ForestClimate.YEAR_S / settings.ecology_year_s


func sample() -> Dictionary:
	return _sample_at(elapsed_s)


func presentation_sample() -> Dictionary:
	# Interpolate the last completed interval, one fixed tick behind the model.
	# Never extrapolate through unserved simulation debt or mutate model time.
	var display_s := maxf(
		0.0, elapsed_s - settings.ecology_step_s + minf(pending_s, settings.ecology_step_s)
	)
	return _sample_at(display_s)


func _sample_at(time_s: float) -> Dictionary:
	var hour := fposmod(settings.start_hour + 24.0 * time_s / settings.ecology_day_s, 24.0)
	return ForestClimate.sample(
		time_s * ForestClimate.YEAR_S / settings.ecology_year_s,
		settings.start_day,
		settings.latitude_deg,
		hour
	)


func snapshot() -> Dictionary:
	return {
		"version": 1,
		"configuration":
		[
			settings.ecology_day_s,
			settings.ecology_year_s,
			settings.ecology_step_s,
			settings.start_day,
			settings.start_hour,
			settings.latitude_deg
		],
		"ticks": ticks,
		"pending_s": pending_s
	}


func restore(state: Dictionary) -> bool:
	if state.get("version") != 1 or state.get("configuration") != snapshot().configuration:
		return false
	if not state.get("ticks") is int or state.ticks < 0:
		return false
	var pending: Variant = state.get("pending_s")
	if not (pending is float or pending is int) or not is_finite(pending) or pending < 0:
		return false
	ticks = state.ticks
	pending_s = pending
	elapsed_s = ticks * settings.ecology_step_s
	return true
