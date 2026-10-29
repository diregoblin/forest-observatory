class_name ForestClimate
extends RefCounted

## A 365-day biological calendar. Water remains on its own SI clock.
## No leap years, automatic storms, snowpack or freeze/thaw in this first slice.
const DAY_S := 86400.0
const YEAR_S := 365.0 * DAY_S


static func sample(
	time_s: float, start_day := 135.0, latitude_deg := 60.0, hour := 12.0
) -> Dictionary:
	var day := fposmod(start_day - 1.0 + time_s / DAY_S, 365.0) + 1.0
	var temperature := 5.5 + 14.0 * cos(TAU * (day - 200.0) / 365.0)
	var declination := deg_to_rad(23.44) * sin(TAU * (day - 80.0) / 365.0)
	var daylight := (
		24.0 * acos(clampf(-tan(deg_to_rad(latitude_deg)) * tan(declination), -1, 1)) / PI
	)
	var latitude := deg_to_rad(latitude_deg)
	var hour_angle := TAU * (hour / 24.0 - 0.5)
	var elevation := asin(
		clampf(
			sin(latitude) * sin(declination) + cos(latitude) * cos(declination) * cos(hour_angle),
			-1,
			1
		)
	)
	var azimuth := (
		PI
		+ atan2(sin(hour_angle), cos(hour_angle) * sin(latitude) - tan(declination) * cos(latitude))
	)
	var evaporation := clampf((temperature + 2.0) / 22.0, 0, 1) * daylight / 16.0
	var season := "Зима"
	if day >= 60 and day < 152:
		season = "Весна"
	elif day >= 152 and day < 244:
		season = "Лето"
	elif day >= 244 and day < 335:
		season = "Осень"
	var month := 1
	var date := int(day)
	for length in [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]:
		if date <= length:
			break
		date -= length
		month += 1
	return {
		"day": day,
		"year": 1 + int((start_day - 1.0 + time_s / DAY_S) / 365.0),
		"date": "%02d.%02d" % [date, month],
		"season": season,
		"temperature_c": temperature,
		"daylight_h": daylight,
		"hour": hour,
		"time": "%02d:%02d" % [int(hour) % 24, int(hour * 60) % 60],
		"sun_elevation": elevation,
		"sun_azimuth": azimuth,
		"growth": clampf((temperature - 5.0) / 14.0, 0, 1),
		"evaporation": evaporation
	}


static func leaves(definition: ForestPlantDefinition, day: float) -> float:
	if not definition.deciduous:
		return 1.0
	return (
		smoothstep(
			definition.leaf_on_day, definition.leaf_on_day + definition.leaf_transition_days, day
		)
		* (
			1.0
			- smoothstep(
				definition.leaf_off_day,
				definition.leaf_off_day + definition.leaf_transition_days,
				day
			)
		)
	)


static func autumn(definition: ForestPlantDefinition, day: float) -> float:
	return (
		smoothstep(definition.leaf_off_day - 25.0, definition.leaf_off_day, day)
		if definition.deciduous
		else 0.0
	)
