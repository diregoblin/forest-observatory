class_name ForestEcologyClock
extends RefCounted

## Fixed hydrological ticks shared with the scene's water/ecology scheduler.
## Solar and biological seconds are configured multiples of completed water time.
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
	return settings.ecology_step_s * settings.year_speed_multiplier


func cancel_excess_request() -> float:
	# Retain the current interpolation phase when cancelling old speed demand.
	var retained := minf(pending_s, settings.ecology_step_s)
	var cancelled := pending_s - retained
	pending_s = retained
	return cancelled


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
	var hour := fposmod(settings.start_hour + time_s * settings.day_speed_multiplier / 3600.0, 24.0)
	return ForestClimate.sample(
		time_s * settings.year_speed_multiplier, settings.start_day, settings.latitude_deg, hour
	)


func snapshot() -> Dictionary:
	return {
		"version": 2,
		"configuration":
		[
			settings.day_speed_multiplier,
			settings.year_speed_multiplier,
			settings.ecology_step_s,
			settings.start_day,
			settings.start_hour,
			settings.latitude_deg
		],
		"ticks": ticks,
		"pending_s": pending_s
	}


func restore(state: Dictionary) -> bool:
	if state.get("version") != 2 or state.get("configuration") != snapshot().configuration:
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
