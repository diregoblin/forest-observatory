class_name ForestTurfCards
extends Node3D

## Camera-local, world-anchored presentation of the already submitted turf.
## No model reads, RNG, food reserves, growth or entries in world saves.
const TILE_M := 8.0
const GRID := 26
const TILE_RADIUS := 5
const VIEW_M := 36.0
const MID_M := 20.0
const FAR_M := 28.0

var terrain: ForestTerrainView
var observer: Camera3D
var vegetation: ForestVegetation
var water_view: ForestWaterView
var style: Node
var patches := {}
var tile_offsets: Array[Vector2i] = []
var card_mesh: ArrayMesh
var detail_meshes: Array[ArrayMesh] = []
var material := ShaderMaterial.new()
var cached_parameters := {}


func configure(
	t: ForestTerrainView,
	camera: Camera3D,
	plants: ForestVegetation,
	water: ForestWaterView,
	presentation: Node
) -> void:
	terrain = t
	observer = camera
	vegetation = plants
	water_view = water
	style = presentation
	material.shader = preload("res://shaders/turf_cards.gdshader")
	material.set_shader_parameter("tuft", load("res://art/ground-turf/upright-tuft.png"))
	material.set_shader_parameter("view_distance", VIEW_M)
	material.set_shader_parameter("mid_distance", MID_M)
	material.set_shader_parameter("far_distance", FAR_M)
	card_mesh = _mesh()
	detail_meshes = [card_mesh, _mesh(2), _mesh(1)]
	for z in range(-TILE_RADIUS, TILE_RADIUS + 1):
		for x in range(-TILE_RADIUS, TILE_RADIUS + 1):
			tile_offsets.append(Vector2i(x, z))
	tile_offsets.sort_custom(
		func(a: Vector2i, b: Vector2i): return a.length_squared() < b.length_squared()
	)
	process_priority = 110


static func _mesh(planes := 3) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for plane in planes:
		var angle := plane * PI / 3
		var right := Vector3(cos(angle), 0, sin(angle)) * .23
		var normal := Vector3(-sin(angle), .45, cos(angle)).normalized()
		var points := [-right, right, right + Vector3.UP * .40, -right + Vector3.UP * .40]
		var uvs := [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		for index in [0, 2, 1, 0, 3, 2]:
			surface.set_normal(normal)
			surface.set_uv(uvs[index])
			surface.set_uv2(Vector2(plane, 0))
			surface.add_vertex(points[index])
	surface.index()
	return surface.commit()


func _parameter(key: String, value: Variant) -> void:
	if cached_parameters.get(key) != value:
		cached_parameters[key] = value
		material.set_shader_parameter(key, value)


func _process(_dt: float) -> void:
	if terrain == null:
		return
	var height := terrain.data.get_height(observer.global_position)
	visible = is_finite(height) and observer.global_position.y - height < VIEW_M
	visible = visible and not terrain.material.get_shader_param("soil_layer_enabled")
	if not visible:
		return
	for key in [
		"ecology_current",
		"ecology_previous",
		"ecology_blend",
		"ecology_extent",
		"habitat_map",
		"ground_greenness",
		"traffic_map",
		"rooting_map",
		"snow_water_m"
	]:
		_parameter(key, terrain.material.get_shader_param(key))
	_parameter("depth_map", water_view.material_override.get_shader_parameter("depth_map"))
	_parameter(
		"previous_depth_map",
		water_view.material_override.get_shader_parameter("previous_depth_map")
	)
	_parameter("display_alpha", water_view.material_override.get_shader_parameter("display_alpha"))
	_parameter("weather_time", vegetation.wind_time_s)
	_parameter("weather_wind", vegetation.wind_strength_display)
	_parameter("weather_direction", vegetation.wind_direction_display)
	_parameter("presentation_style", style.mode)
	var center := Vector2i(
		floori(observer.global_position.x / TILE_M), floori(observer.global_position.z / TILE_M)
	)
	for key in patches.keys():
		var distance_sq := _tile_distance_squared(key)
		if distance_sq > VIEW_M * VIEW_M:
			patches[key].queue_free()
			patches.erase(key)
		else:
			var level := (
				2 if distance_sq >= FAR_M * FAR_M else (1 if distance_sq >= MID_M * MID_M else 0)
			)
			var mm: MultiMesh = patches[key].multimesh
			if mm.mesh != detail_meshes[level]:
				mm.mesh = detail_meshes[level]
	# Bound upload work after flying into a new area. Stable world tile seeds
	# reproduce exactly the same tufts after leaving and returning.
	var built := 0
	for offset in tile_offsets:
		var key := center + offset
		if not patches.has(key) and _tile_in_range(key):
			patches[key] = _patch(key)
			built += 1
			if built == 3:
				break


func _tile_in_range(key: Vector2i) -> bool:
	return _tile_distance_squared(key) <= VIEW_M * VIEW_M


func _tile_distance_squared(key: Vector2i) -> float:
	var camera_xz := Vector2(observer.global_position.x, observer.global_position.z)
	var tile_min := Vector2(key) * TILE_M
	var nearest := camera_xz.clamp(tile_min, tile_min + Vector2.ONE * TILE_M)
	return camera_xz.distance_squared_to(nearest)


func _patch(key: Vector2i) -> MultiMeshInstance3D:
	var node := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = card_mesh
	mm.instance_count = GRID * GRID
	var random := RandomNumberGenerator.new()
	random.seed = hash(Vector3i(key.x, key.y, 20261102))
	var bounds := AABB()
	for z in GRID:
		for x in GRID:
			var point := Vector3(
				(key.x + (x + random.randf_range(.1, .9)) / GRID) * TILE_M,
				0,
				(key.y + (z + random.randf_range(.1, .9)) / GRID) * TILE_M
			)
			point.y = terrain.data.get_height(point)
			if not is_finite(point.y):
				point.y = -1000
			var scale := Vector3(random.randf_range(.7, 1.15), random.randf_range(.65, 1.25), 1)
			var pose := Transform3D(Basis(Vector3.UP, random.randf() * TAU).scaled(scale), point)
			var slot := z * GRID + x
			mm.set_instance_transform(slot, pose)
			var shade := random.randf_range(.85, 1.12)
			mm.set_instance_color(slot, Color(shade, shade, shade, 1))
			mm.set_instance_custom_data(slot, Color(random.randf(), 0, 0, 0))
			bounds = AABB(point, Vector3.ONE * .01) if slot == 0 else bounds.expand(point)
	mm.custom_aabb = bounds.grow(.6)
	node.multimesh = mm
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = VIEW_M + TILE_M
	add_child(node)
	return node
