class_name ForestHabitat
extends RefCounted

## Finite insects/carrion, pollination, transported seeds, wet tracks and trails.
## Insect guilds are aggregate pools, not independently simulated individual bugs.
const GRID := 16
const TRACK_LIMIT := 4096
const TRACKS_PER_ANIMAL := 48
const GUILDS := ["pollinator", "wood", "detritivore"]
var plants: ForestTrees
var water: ForestWatershed
var soil: ForestSoil
var animals: ForestAnimals
var elapsed_s := 0.0
var insect_sites := PackedInt32Array()
var cell_centers := PackedVector3Array()  # Fixed landscape geometry, never food reserves.
var pollinator_c := PackedFloat64Array()
var pollinator_n := PackedFloat64Array()
var pollinator_p := PackedFloat64Array()
var wood_c := PackedFloat64Array()
var wood_n := PackedFloat64Array()
var wood_p := PackedFloat64Array()
var detritivore_c := PackedFloat64Array()
var detritivore_n := PackedFloat64Array()
var detritivore_p := PackedFloat64Array()
var respired_kg_c := 0.0
var seed_carriers: Array = []
var tracks: Array = []
var last_track_positions := PackedVector3Array()
var rng := RandomNumberGenerator.new()
var weather := {}
var seed_drops := 0
var transported_recruits := 0
var flooded_homes := 0
var traffic := PackedFloat64Array()  # Dimensionless accumulated trampling on the water grid.
var rooting := PackedFloat64Array()  # Disturbed ground fraction, not an extra C/N/P stock.
var traffic_last_tick := 0
var carcasses: Array = []  # Owner of remaining dead animal C/N/P, not an animal copy.


func _init(p: ForestTrees, w: ForestWatershed, s: ForestSoil, a: ForestAnimals) -> void:
	plants = p
	water = w
	soil = s
	animals = a
	rng.seed = plants.land.settings.seed + 33829
	traffic.resize(water.resolution * water.resolution)
	rooting.resize(traffic.size())
	insect_sites.resize(GRID * GRID)
	insect_sites.fill(-1)
	var dx := plants.land.settings.extent / GRID
	for k in GRID * GRID:
		var x := (k % GRID + .5) * dx
		var z := (k / GRID + .5) * dx
		cell_centers.append(Vector3(x, plants.land.height_at(x, z), z))
	for field in [
		"pollinator_c",
		"pollinator_n",
		"pollinator_p",
		"wood_c",
		"wood_n",
		"wood_p",
		"detritivore_c",
		"detritivore_n",
		"detritivore_p"
	]:
		var pool := PackedFloat64Array()
		pool.resize(GRID * GRID)
		set(field, pool)


func cell(point: Vector3) -> int:
	var dx := plants.land.settings.extent / GRID
	return clampi(int(point.z / dx), 0, GRID - 1) * GRID + clampi(int(point.x / dx), 0, GRID - 1)


func center(k: int) -> Vector3:
	return cell_centers[k]


func pollination_at(point: Vector3) -> float:
	# Baseline self/wind pollination is deliberately retained, never an absolute gate.
	return clampf(.12 + pollinator_c[cell(point)] / .0003, .12, 1)


func insect_carbon(point: Vector3) -> float:
	return insect_carbon_in_cell(cell(point))


func insect_carbon_in_cell(k: int) -> float:
	return pollinator_c[k] + wood_c[k] + detritivore_c[k]


func step(dt: float, climate: Dictionary) -> void:
	weather = climate.duplicate()
	var activity := clampf((float(climate.temperature_c) - 5) / 15, 0, 1)
	activity *= clampf(1 - climate.get("wind_m_s", 0.0) / 15, 0, 1)
	activity *= 1 - clampf(climate.get("rain_fraction", 0.0), 0, 1)
	for i in plants.species.size():
		var d: ForestPlantDefinition = plants.land.settings.plants[plants.species[i]]
		var k := cell(plants.positions[i])
		if plants.alive[i] and d.insect_pollinated:
			var bloom := ForestTrees.flower_fraction(d, climate.day)
			if bloom * activity > 0:
				var meal := plants.harvest_nectar(
					i, .00005 * dt / ForestClimate.DAY_S * bloom * activity
				)
				_add_insect(k, meal, "pollinator")
				if meal.x > 0:
					insect_sites[k] = i
		elif plants.fallen[i] and plants.dead_c[i] > .01:
			var moisture := water.soil[plants.root_cells[i]]
			var request := (
				plants.dead_c[i]
				* .003
				* dt
				/ ForestClimate.YEAR_S
				* clampf(moisture, 0, 1)
				* activity
			)
			_add_insect(k, plants.harvest_dead(i, request), "wood")
			if request > 0:
				insect_sites[k] = i
	var turnover := 1 - exp(-dt / (25 * ForestClimate.DAY_S))
	for k in GRID * GRID:
		# Ground larvae/other detritivores consume real organic matter. This food
		# channel stays available between blooms, but not without litter/warmth/moisture.
		var point := center(k)
		var ground := soil.sample(point)
		var hydro := water.index_at(point.x, point.z)
		var ground_activity := (
			clampf((float(climate.temperature_c) - 2) / 13, 0, 1)
			* clampf(water.soil[hydro] * 1.5, 0, 1)
		)
		if water.depth[hydro] < .02 and ground.organic_c_kg_m2 > 0 and ground_activity > 0:
			var request := minf(
				(
					.004
					* dt
					/ ForestClimate.DAY_S
					* ground_activity
					* clampf(ground.surface_litter_c_kg_m2 / .1, 0, 1)
				),
				ground.surface_litter_c_kg_m2 * ground.area
			)
			var amount := (
				Vector3(
					request,
					request * ground.organic_n_kg_m2 / ground.organic_c_kg_m2,
					request * ground.organic_p_kg_m2 / ground.organic_c_kg_m2
				)
				* .9999998
			)
			var meal := soil.withdraw(point, amount, true)
			respired_kg_c += meal.x * .5
			meal.x *= .5
			_add_insect(k, meal, "detritivore")
		for guild in GUILDS:
			var c: PackedFloat64Array = get(guild + "_c")
			var n: PackedFloat64Array = get(guild + "_n")
			var p: PackedFloat64Array = get(guild + "_p")
			var loss_c := c[k] * turnover
			var loss_n := n[k] * turnover
			var loss_p := p[k] * turnover
			c[k] -= loss_c
			n[k] -= loss_n
			p[k] -= loss_p
			set(guild + "_c", c)
			set(guild + "_n", n)
			set(guild + "_p", p)
			if loss_c + loss_n + loss_p > 0:
				respired_kg_c += loss_c * .5
				soil.deposit_elements(center(k), loss_c * .5, loss_n, loss_p)
	elapsed_s += dt
	for j in range(seed_carriers.size() - 1, -1, -1):
		var cargo: Dictionary = seed_carriers[j]
		if cargo.due_s <= elapsed_s or not animals.alive[cargo.animal]:
			var point := animals.positions[cargo.animal]
			if plants.drop_seed(cargo.source, cargo.carbon, point, water):
				transported_recruits += 1
			seed_drops += 1
			seed_carriers.remove_at(j)
	_record_tracks(climate, dt)
	_record_traffic(dt, climate)
	for body in carcasses:
		var fraction := (
			1
			- exp(
				(
					-dt
					/ (12 * ForestClimate.DAY_S)
					* clampf((float(climate.temperature_c) + 3) / 18, 0, 1.5)
				)
			)
		)
		var c: float = body.c * fraction
		var n: float = body.n * fraction
		var p: float = body.p * fraction
		body.c -= c
		body.n -= n
		body.p -= p
		respired_kg_c += c * .5
		soil.deposit_elements(body.position, c * .5, n, p)
	carcasses = carcasses.filter(func(body): return body.c + body.n + body.p > 0)


func add_carcass(source: int, point: Vector3, amount: Vector3) -> void:
	if amount.x + amount.y + amount.z <= 0:
		return
	if carcasses.size() >= 512:
		var oldest: Dictionary = carcasses.pop_front()
		soil.deposit_elements(oldest.position, oldest.c, oldest.n, oldest.p)
	carcasses.append(
		{
			"source": source,
			"position": point,
			"c": float(amount.x),
			"n": float(amount.y),
			"p": float(amount.z),
			"born_s": elapsed_s
		}
	)


func carcass_carbon(source: int) -> float:
	for body in carcasses:
		if body.source == source:
			return body.c
	return 0.0


func harvest_carcass(source: int, request: float) -> Vector3:
	for body in carcasses:
		if body.source != source or body.c <= 0:
			continue
		var fraction: float = minf(1, maxf(0, request) / body.c)
		var meal := Vector3(body.c * fraction, body.n * fraction, body.p * fraction) * .9999998
		if meal.x <= 0 or meal.x > body.c or meal.y > body.n or meal.z > body.p:
			return Vector3.ZERO
		body.c -= meal.x
		body.n -= meal.y
		body.p -= meal.z
		return meal
	return Vector3.ZERO


func _add_insect(k: int, meal: Vector3, prefix: String) -> void:
	for e in 3:
		var key: String = prefix + ["_c", "_n", "_p"][e]
		var pool: PackedFloat64Array = get(key)
		pool[k] += meal[e]
		set(key, pool)


func harvest_insects(point: Vector3, request: float) -> Vector3:
	var k := cell(point)
	var food := Vector3.ZERO
	for prefix in GUILDS:
		var c: PackedFloat64Array = get(prefix + "_c")
		var n: PackedFloat64Array = get(prefix + "_n")
		var p: PackedFloat64Array = get(prefix + "_p")
		if c[k] <= 0:
			continue
		var fraction := minf(1, maxf(0, request - food.x) / c[k])
		var meal := Vector3(c[k] * fraction, n[k] * fraction, p[k] * fraction) * .9999998
		# Vector3 is float32. At subnormal magnitudes, rounding can exceed a
		# float64 source despite the normal-range margin. Leave such dust in situ.
		if meal.x <= 0 or meal.x > c[k] or meal.y > n[k] or meal.z > p[k]:
			continue
		c[k] -= meal.x
		n[k] -= meal.y
		p[k] -= meal.z
		set(prefix + "_c", c)
		set(prefix + "_n", n)
		set(prefix + "_p", p)
		food += meal
	return food


func carry_seed(animal: int, source: int) -> void:
	for cargo in seed_carriers:
		if cargo.animal == animal:
			return
	var c := plants.reserve_seed(source)
	if c > 0:
		seed_carriers.append(
			{
				"animal": animal,
				"source": source,
				"carbon": c,
				"due_s": elapsed_s + 2.5 * ForestClimate.DAY_S
			}
		)


func _record_tracks(climate: Dictionary, dt := 0.0) -> void:
	# Subsequent rain erodes old prints too, not only ones made in a shower.
	for track in tracks:
		track.life_s = maxf(
			.0001, track.life_s - dt * clampf(climate.get("rain_fraction", 0.0), 0, 1) * 2.0
		)
	var old_count := last_track_positions.size()
	last_track_positions.resize(animals.positions.size())
	for id in animals.positions.size():
		var point := animals.positions[id]
		if id >= old_count:
			last_track_positions[id] = point
		if not animals.alive[id] or animals.definitions[animals.species[id]].flight_height_m > 0:
			continue
		if point.distance_squared_to(last_track_positions[id]) < .35:
			continue
		last_track_positions[id] = point
		var k := water.index_at(point.x, point.z)
		if water.soil[k] > .5 and water.depth[k] < .02:
			tracks.append(
				{
					"position": point,
					"yaw": animals.yaw[id],
					"animal": id,
					"size": animals.definitions[animals.species[id]].selection_radius_m,
					"born_s": elapsed_s,
					"life_s":
					ForestClimate.DAY_S * (10 if climate.get("rain_fraction", 0.0) > .3 else 45)
				}
			)
	# Keep a bounded recent path per individual, not three prints after every
	# animal in the valley competes for the same tiny FIFO. Linear compaction.
	var counts := {}
	var retained := []
	for index in range(tracks.size() - 1, -1, -1):
		var track: Dictionary = tracks[index]
		if elapsed_s - track.born_s >= track.life_s:
			continue
		var count: int = counts.get(track.animal, 0)
		if count >= TRACKS_PER_ANIMAL:
			continue
		counts[track.animal] = count + 1
		retained.append(track)
		if retained.size() >= TRACK_LIMIT:
			break
	retained.reverse()
	tracks = retained


func _record_traffic(dt: float, climate: Dictionary) -> void:
	# Model paths are consumed once, with one coupled-tick latency. No camera trails.
	var recovery := exp(-dt / (45 * ForestClimate.DAY_S) * (.15 + climate.get("growth", 0.0)))
	var rooting_recovery := exp(
		-dt / (90 * ForestClimate.DAY_S) * (.15 + climate.get("growth", 0.0))
	)
	for k in traffic.size():
		traffic[k] *= recovery
		rooting[k] *= rooting_recovery
	if animals.ticks <= traffic_last_tick:
		return
	var fresh := PackedFloat64Array()
	fresh.resize(traffic.size())
	for id in animals.species.size():
		var d: ForestAnimalDefinition = animals.definitions[animals.species[id]]
		if d.flight_height_m > 0:
			continue
		var path: Dictionary = animals.path_history[id]
		for j in range(1, path.points.size()):
			var a: Vector3 = path.points[j - 1]
			var b: Vector3 = path.points[j]
			var distance := Vector2(b.x - a.x, b.z - a.z).length()
			if distance < .0001:
				continue
			var samples := maxi(1, ceili(distance / (water.cell_size * .5)))
			var pressure := (
				distance
				/ samples
				* maxf(.05, d.selection_radius_m * .4)
				/ (water.cell_size * water.cell_size)
			)
			for sample_id in samples:
				var point := a.lerp(b, (sample_id + .5) / samples)
				var k := water.index_at(point.x, point.z)
				if water.depth[k] < .02:
					fresh[k] += pressure
	traffic_last_tick = animals.ticks
	for k in traffic.size():
		traffic[k] = clampf(traffic[k] + fresh[k], 0, 1)
	for i in plants.species.size():
		if fresh[plants.root_cells[i]] > 0:
			plants.trample(i, fresh[plants.root_cells[i]])


func root_at(point: Vector3, pressure: float) -> bool:
	# Rooting disturbs the local vegetation owner; trample transfers damaged C/N/P
	# to the shared soil. It never harvests soil carbon as food or invents roots.
	var k := water.index_at(point.x, point.z)
	if not is_finite(pressure) or pressure <= 0 or water.depth[k] >= .02:
		return false
	var disturbance := 1 - exp(-pressure)
	rooting[k] = 1 - (1 - rooting[k]) * (1 - disturbance)
	for i in animals._nearby(point, water.cell_size * 1.5):
		if plants.root_cells[i] == k:
			plants.trample(i, disturbance)
	return true


func metrics() -> Dictionary:
	var total := Vector3.ZERO
	# Float64 sums stay separate until this presentation/metrics boundary.
	var values := [0.0, 0.0, 0.0]
	for prefix in GUILDS:
		for e in 3:
			for v in get(prefix + ["_c", "_n", "_p"][e]):
				values[e] += v
	for body in carcasses:
		values[0] += body.c
		values[1] += body.n
		values[2] += body.p
	return {
		"carbon_kg": values[0],
		"nitrogen_kg": values[1],
		"phosphorus_kg": values[2],
		"respired_kg_c": respired_kg_c,
		"seed_drops": seed_drops,
		"transported_recruits": transported_recruits,
		"carcasses": carcasses.size()
	}


func snapshot() -> Dictionary:
	var result := {"version": 4, "seed": plants.land.settings.seed, "rng_state": rng.state}
	for key in _fields():
		var value: Variant = get(key)
		result[key] = (
			value.duplicate(true)
			if value is Array or value is Dictionary
			else (
				value.duplicate()
				if (
					value is PackedFloat64Array
					or value is PackedVector3Array
					or value is PackedInt32Array
				)
				else value
			)
		)
	return result


func _fields() -> Array:
	return [
		"insect_sites",
		"pollinator_c",
		"pollinator_n",
		"pollinator_p",
		"wood_c",
		"wood_n",
		"wood_p",
		"detritivore_c",
		"detritivore_n",
		"detritivore_p",
		"elapsed_s",
		"respired_kg_c",
		"seed_carriers",
		"tracks",
		"last_track_positions",
		"weather",
		"seed_drops",
		"transported_recruits",
		"flooded_homes",
		"carcasses",
		"traffic",
		"rooting",
		"traffic_last_tick"
	]


func restore(state: Dictionary) -> bool:
	if (
		state.get("version") != 4
		or state.get("seed") != plants.land.settings.seed
		or not state.get("rng_state") is int
	):
		return false
	for key in _fields():
		if typeof(state.get(key)) != typeof(get(key)):
			return false
	if (
		state.traffic.size() != water.resolution * water.resolution
		or state.rooting.size() != water.resolution * water.resolution
		or state.traffic_last_tick < 0
		or state.traffic_last_tick > animals.ticks
	):
		return false
	for value in state.traffic:
		if not is_finite(value) or value < 0 or value > 1:
			return false
	for value in state.rooting:
		if not is_finite(value) or value < 0 or value > 1:
			return false
	if state.insect_sites.size() != GRID * GRID:
		return false
	for site in state.insect_sites:
		if site < -1 or site >= plants.species.size():
			return false
	for prefix in GUILDS:
		for suffix in ["_c", "_n", "_p"]:
			var pool: PackedFloat64Array = state[prefix + suffix]
			if pool.size() != GRID * GRID:
				return false
			for v in pool:
				if not is_finite(v) or v < 0:
					return false
	for key in [
		"elapsed_s", "respired_kg_c", "seed_drops", "transported_recruits", "flooded_homes"
	]:
		if not is_finite(state[key]) or state[key] < 0:
			return false
	if state.tracks.size() > TRACK_LIMIT or state.seed_carriers.size() > animals.species.size():
		return false
	if state.carcasses.size() > 512:
		return false
	var sources := {}
	for body in state.carcasses:
		if (
			not body is Dictionary
			or not body.get("source") is int
			or body.source < 0
			or body.source >= animals.species.size()
			or animals.alive[body.source]
			or sources.has(body.source)
		):
			return false
		if (
			not body.get("position") is Vector3
			or not body.position.is_finite()
			or body.position.x < 0
			or body.position.z < 0
			or body.position.x >= plants.land.settings.extent
			or body.position.z >= plants.land.settings.extent
		):
			return false
		for key in ["c", "n", "p", "born_s"]:
			if not body.get(key) is float or not is_finite(body[key]) or body[key] < 0:
				return false
		if body.born_s > state.elapsed_s:
			return false
		sources[body.source] = true
	if not valid_weather(state.weather):
		return false
	if state.last_track_positions.size() > animals.species.size():
		return false
	var reserved := PackedFloat64Array()
	reserved.resize(plants.species.size())
	var carrying := {}
	for cargo in state.seed_carriers:
		if (
			not cargo is Dictionary
			or not cargo.get("animal") is int
			or not cargo.get("source") is int
		):
			return false
		if (
			cargo.animal < 0
			or cargo.animal >= animals.species.size()
			or cargo.source < 0
			or cargo.source >= plants.species.size()
			or carrying.has(cargo.animal)
		):
			return false
		if (
			not cargo.get("carbon") is float
			or not is_finite(cargo.carbon)
			or cargo.carbon <= 0
			or not cargo.get("due_s") is float
			or not is_finite(cargo.due_s)
			or cargo.due_s <= state.elapsed_s
		):
			return false
		reserved[cargo.source] += cargo.carbon
		carrying[cargo.animal] = true
	for i in reserved.size():
		if absf(reserved[i] - plants.reserved_seed_c[i]) > 1e-9:
			return false
	for track in state.tracks:
		if (
			not track is Dictionary
			or not track.get("position") is Vector3
			or not track.position.is_finite()
			or not track.get("animal") is int
			or track.animal < 0
			or track.animal >= animals.species.size()
		):
			return false
		for key in ["yaw", "size", "born_s", "life_s"]:
			if (
				not track.get(key) is float
				or not is_finite(track[key])
				or (key != "yaw" and track[key] < 0)
			):
				return false
	for point in state.last_track_positions:
		if not point.is_finite():
			return false
	for key in _fields():
		set(
			key,
			(
				state[key].duplicate(true)
				if state[key] is Array or state[key] is Dictionary
				else (
					state[key].duplicate()
					if (
						state[key] is PackedFloat64Array
						or state[key] is PackedVector3Array
						or state[key] is PackedInt32Array
					)
					else state[key]
				)
			)
		)
	rng.state = state.rng_state
	return true


static func valid_weather(state: Dictionary) -> bool:
	for key in state:
		var value: Variant = state[key]
		if value is float or value is int:
			if not is_finite(value):
				return false
		elif value is Vector2:
			if not value.is_finite():
				return false
		elif not value is String:
			return false
	for key in ["wind_m_s", "rain_fraction", "temperature_c", "day", "hour", "weather_time_s"]:
		if not state.is_empty() and not (state.get(key) is float or state.get(key) is int):
			return false
	return true
