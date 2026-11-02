class_name ForestSoilLayers
extends PanelContainer

## Read-only presentation. Refresh only after the composition root joins its worker.
## Water is an equivalent water column; chemistry is element stock per ground area,
## NOT solution concentration. Limits are fixed, never normalized to each frame.
signal layer_requested(index: int)
signal cover_requested

const LAYERS := [
	{"title": "Вода · верхний слой", "water": "top_water_m", "capacity": "top_depth_m"},
	{"title": "Вода · корневой слой", "water": "root_water_m", "capacity": "root_depth_m"},
	{"title": "Вода · грунтовый запас", "water": "ground_water_m", "capacity": "aquifer_depth_m"},
	{"title": "Органический C", "field": 0, "limit": 5000.0, "key": "organic_c"},
	{"title": "Органический N", "field": 1, "limit": 250.0, "key": "organic_n"},
	{"title": "Органический P", "field": 2, "limit": 20.0, "key": "organic_p"},
	{"title": "Лабильный C", "field": 3, "limit": 150.0, "key": "labile_c"},
	{"title": "Лабильный N", "field": 4, "limit": 10.0, "key": "labile_n"},
	{"title": "Лабильный P", "field": 5, "limit": 1.0, "key": "labile_p"},
	{"title": "Минеральный N", "field": 6, "limit": 60.0, "key": "mineral_n"},
	{"title": "Минеральный P", "field": 7, "limit": 6.0, "key": "mineral_p"},
	{"title": "Свежий опад · C", "field": 8, "limit": 500.0, "key": "surface_c"},
	{"title": "Поверхностная вода", "water": "depth", "limit": 1000.0},
	{"title": "Выход грунтовой воды", "rate": "seepage_m_s", "limit": 10.0, "units": "мм/ч"},
	{"title": "Источники воды", "sources": true, "limit": 250.0, "units": "л/с"},
]
const SURFACE_WATER := 12
const SEEPAGE := 13
const SOURCES := 14
const LOW := Color(.075, .09, .23)
const MID := Color(.06, .60, .57)
const HIGH := Color(.98, .86, .22)

var selected := SURFACE_WATER
var values := PackedFloat64Array()
var limit := 1.0
var units := "мм"
var resolution := 0
var cell_size := 0.0
var fine_patches: Array = []
var background_values := PackedFloat64Array()
var fine_texture: ImageTexture
var fine_layout: ImageTexture
var map_material := ShaderMaterial.new()
var hovered_point := Vector2(-1, -1)
var field_texture: ImageTexture
var selector := OptionButton.new()
var hide_cover := CheckBox.new()
var map := TextureRect.new()
var scale_label := Label.new()
var range_label := Label.new()
var sample_label := Label.new()
var stamp_label := Label.new()
var hovered_cell := -1


func configure() -> void:
	anchor_left = 1
	anchor_right = 1
	offset_left = -390
	offset_right = -38
	offset_top = 46
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.035, .06, .07, .96)
	style.set_corner_radius_all(7)
	style.set_content_margin_all(14)
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)
	var title := Label.new()
	title.text = "СЛОИ ВОДЫ И ПОЧВЫ · V закрыть"
	box.add_child(title)
	for layer in LAYERS:
		selector.add_item(layer.title)
	selector.select(selected)
	selector.item_selected.connect(func(index: int): layer_requested.emit(index))
	box.add_child(selector)
	hide_cover.text = "Скрыть лес и поверхностную воду"
	hide_cover.button_pressed = true
	hide_cover.toggled.connect(func(_value: bool): cover_requested.emit())
	box.add_child(hide_cover)
	var caption := Label.new()
	caption.text = "Север ↑ · вся долина · наведи на карту"
	caption.add_theme_font_size_override("font_size", 13)
	box.add_child(caption)
	map_material.shader = preload("res://shaders/soil_diagnostic_map.gdshader")
	map.material = map_material
	map.custom_minimum_size = Vector2(256, 256)
	map.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	map.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	map.mouse_filter = Control.MOUSE_FILTER_STOP
	map.gui_input.connect(_map_input)
	map.mouse_exited.connect(
		func():
			hovered_cell = -1
			hovered_point = Vector2(-1, -1)
			_show_sample()
	)
	box.add_child(map)
	var ramp := TextureRect.new()
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0, .5, 1])
	gradient.colors = PackedColorArray([LOW, MID, HIGH])
	var ramp_texture := GradientTexture1D.new()
	ramp_texture.gradient = gradient
	ramp.texture = ramp_texture
	ramp.custom_minimum_size = Vector2(0, 12)
	box.add_child(ramp)
	for label in [scale_label, range_label, sample_label, stamp_label]:
		label.add_theme_font_size_override("font_size", 13)
		box.add_child(label)
	var note := Label.new()
	note.text = (
		"Вода: эквивалентный слой, не влажность.\n"
		+ "C/N/P: запас элемента, не концентрация.\n"
		+ "Опад — часть органического C.\n"
		+ "Источники: заданный приток извне.\n"
		+ "Выход грунтовой воды: расчётный поток.\n"
		+ "Цвет обрезан по шкале; числа — нет."
	)
	note.add_theme_font_size_override("font_size", 13)
	box.add_child(note)
	visible = false


static func field_values(
	index: int, soil: ForestSoil, water: ForestWatershed
) -> PackedFloat64Array:
	var layer: Dictionary = LAYERS[index]
	var field: PackedFloat64Array
	var factor := 1000.0  # Water m→mm, stocks kg/m²→g/m², source m³/s→L/s.
	if layer.has("water"):
		field = water.get(layer.water).duplicate()
	elif layer.has("rate"):
		field = water.get(layer.rate).duplicate()
		factor = 3600000.0  # m/s → mm/h.
	elif layer.has("sources"):
		field = water.source_flow_m3_s.duplicate()
	else:
		field = soil.native.diagnostic_field(layer.field)
	# Explicitly detach packed arrays before converting public water snapshots.
	for k in field.size():
		field[k] *= factor
	return field


static func scale_limit(index: int, profile: ForestSoilProfile) -> float:
	var layer: Dictionary = LAYERS[index]
	if layer.has("capacity"):
		var fraction := profile.specific_yield if index == 2 else profile.porosity
		return profile.get(layer.capacity) * fraction * 1000.0
	return layer.limit


static func color_for(value: float, ceiling: float) -> Color:
	var t := clampf(value / ceiling, 0, 1)
	return LOW.lerp(MID, t * 2) if t <= .5 else MID.lerp(HIGH, (t - .5) * 2)


func refresh(soil: ForestSoil, water: ForestWatershed) -> void:
	if not visible:
		return
	values = field_values(selected, soil, water)
	resolution = water.resolution
	cell_size = water.cell_size
	limit = scale_limit(selected, water.config.soil_profile)
	units = LAYERS[selected].get("units", "мм" if LAYERS[selected].has("water") else "г/м²")
	var image := Image.create(resolution, resolution, false, Image.FORMAT_RGBA8)
	var minimum := INF
	var maximum := -INF
	background_values = values
	var background_areas := PackedFloat64Array()
	if LAYERS[selected].has("field"):
		var background: Dictionary = soil.native.diagnostic_background(LAYERS[selected].field)
		background_values = background.values
		background_areas = background.area
		for k in background_values.size():
			background_values[k] *= 1000.0
	for k in values.size():
		if background_areas.is_empty() or background_areas[k] > 0:
			minimum = minf(minimum, background_values[k])
			maximum = maxf(maximum, background_values[k])
		image.set_pixel(k % resolution, int(k / resolution), color_for(background_values[k], limit))
	if field_texture == null:
		field_texture = ImageTexture.create_from_image(image)
		map.texture = field_texture
	else:
		field_texture.update(image)
	_refresh_fine(soil)
	for patch in fine_patches:
		for value in patch.values:
			minimum = minf(minimum, value)
			maximum = maxf(maximum, value)
	map_material.set_shader_parameter("soil_extent", water.landscape.settings.extent)
	var parameters := display_parameters()
	for key in parameters:
		map_material.set_shader_parameter(key, parameters[key])
	scale_label.text = (
		"0                  %.2f                  %.2f %s" % [limit * .5, limit, units]
	)
	range_label.text = "В долине: %.3f–%.3f %s" % [minimum, maximum, units]
	stamp_label.text = (
		"Сетка %.2f м%s\nВода t = %.1f с"
		% [
			cell_size,
			" / %.2f м под грибами" % fine_patches[0].dx if not fine_patches.is_empty() else "",
			water.clock
		]
	)
	_show_sample()


func _refresh_fine(soil: ForestSoil) -> void:
	fine_patches = []
	if not LAYERS[selected].has("field"):
		return  # Water remains on its own coarse grid, even underneath fungi.
	fine_patches = soil.native.diagnostic_patches(LAYERS[selected].field)
	if fine_patches.is_empty():
		return
	var width := 0
	var height := 0
	for patch in fine_patches:
		width = maxi(width, patch.n)
		height += patch.n
	var atlas := Image.create(width, height, false, Image.FORMAT_RGBA8)
	var layout := Image.create(2, fine_patches.size(), false, Image.FORMAT_RGBAF)
	var row := 0
	for index in fine_patches.size():
		var patch: Dictionary = fine_patches[index]
		var field: PackedFloat64Array = patch.values
		for k in field.size():
			field[k] *= 1000.0
			atlas.set_pixel(k % patch.n, row + int(k / patch.n), color_for(field[k], limit))
		patch.values = field
		layout.set_pixel(0, index, Color(patch.origin.x, patch.origin.y, patch.n * patch.dx, row))
		layout.set_pixel(1, index, Color(patch.n, patch.dx, 0, 0))
		row += patch.n
	if fine_texture == null:
		fine_texture = ImageTexture.create_from_image(atlas)
		fine_layout = ImageTexture.create_from_image(layout)
	else:
		fine_texture.set_image(atlas)
		fine_layout.set_image(layout)


func display_parameters() -> Dictionary:
	return {
		"soil_layer_map": field_texture,
		"soil_fine_map": fine_texture,
		"soil_fine_layout": fine_layout,
		"soil_fine_count": fine_patches.size(),
		"soil_base_cell_m": cell_size,
		"soil_grid_enabled": LAYERS[selected].has("field")
	}


func sample_at(point: Vector2) -> Dictionary:
	for patch in fine_patches:
		var local: Vector2 = (point - patch.origin) / patch.dx
		if local.x >= 0 and local.y >= 0 and local.x < patch.n and local.y < patch.n:
			var cell := Vector2i(local.floor())
			return {"value": patch.values[cell.y * patch.n + cell.x], "dx": patch.dx}
	var cell := Vector2i((point / cell_size).floor())
	cell = cell.clamp(Vector2i.ZERO, Vector2i.ONE * (resolution - 1))
	return {"value": background_values[cell.y * resolution + cell.x], "dx": cell_size}


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and resolution > 0:
		hovered_point = event.position / map.size * resolution * cell_size
		var cell := Vector2i(hovered_point / cell_size)
		hovered_cell = (
			clampi(cell.y, 0, resolution - 1) * resolution + clampi(cell.x, 0, resolution - 1)
		)
		_show_sample()


func _show_sample() -> void:
	if hovered_cell < 0 or hovered_cell >= values.size():
		sample_label.text = "Ячейка: наведи курсор на карту"
		return
	var point := hovered_point
	if point.x < 0:
		point = (
			Vector2(hovered_cell % resolution + .5, int(hovered_cell / resolution) + .5) * cell_size
		)
	var sample := sample_at(point)
	sample_label.text = (
		"x %.2f · z %.2f м: %.3f %s\nЯчейка %.2f × %.2f м"
		% [point.x, point.y, sample.value, units, sample.dx, sample.dx]
	)
