class_name ForestFungiMap
extends Control

## Nearest plot in XZ: only committed display copies are read while the worker runs.
var model: ForestFungi
var biomass_texture: ImageTexture
var resource_texture: ImageTexture
var biomass_view := TextureRect.new()
var resource_view := TextureRect.new()
var label := Label.new()
var observer: Node3D
var display_plots: Array[Dictionary] = []
var selected_plot := -1
var resolution := 0
var cell_size := 0.0


func configure(fungi: ForestFungi, camera: Node3D) -> void:
	model = fungi
	observer = camera
	resolution = model.land.settings.fungi_resolution
	cell_size = model.land.settings.fungi_cell_m
	position = Vector2(-302, 146)
	anchor_left = 1
	anchor_right = 1
	size = Vector2(264, 610)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_outline_size", 3)
	for view in [biomass_view, resource_view]:
		add_child(view)
		view.size = Vector2(256, 256)
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	biomass_view.position.y = 88
	resource_view.position.y = 354
	visible = false
	refresh()


func refresh() -> void:
	# Called only after the composition root joins its worker. Packed fields are
	# submitted copies, never native solver memory; camera motion reads these only.
	display_plots.clear()
	for plot in model.plots:
		display_plots.append(
			{"origin": plot.origin, "definition": plot.definition, "fields": plot.fields}
		)
	selected_plot = -1
	_refresh_nearest()


func _process(_dt: float) -> void:
	if visible:
		_refresh_nearest()


func _refresh_nearest() -> void:
	if display_plots.is_empty():
		return
	var point := Vector2(observer.global_position.x, observer.global_position.z)
	var nearest := 0
	var distance := INF
	for index in display_plots.size():
		var center: Vector2 = (
			display_plots[index].origin + Vector2.ONE * resolution * cell_size * .5
		)
		var candidate := point.distance_squared_to(center)
		if candidate < distance:
			distance = candidate
			nearest = index
	if selected_plot == nearest:
		return
	selected_plot = nearest
	var plot := display_plots[selected_plot]
	var n := resolution
	var b: PackedFloat64Array = plot.fields.biomass
	var r: PackedFloat64Array = plot.fields.resource
	var images: Array[Image] = [
		Image.create(n, n, false, Image.FORMAT_RGB8), Image.create(n, n, false, Image.FORMAT_RGB8)
	]
	for k in n * n:
		images[0].set_pixel(
			k % n,
			int(k / n),
			Color(.035, .06, .07).lerp(Color(.95, .73, .30), clampf(b[k] / .025, 0, 1))
		)
		images[1].set_pixel(
			k % n,
			int(k / n),
			Color(.12, .055, .025).lerp(
				Color(.44, .80, .67), clampf(r[k] / plot.definition.resource_capacity_kg_m2, 0, 1)
			)
		)
	if biomass_texture == null:
		biomass_texture = ImageTexture.create_from_image(images[0])
		resource_texture = ImageTexture.create_from_image(images[1])
		biomass_view.texture = biomass_texture
		resource_view.texture = resource_texture
	else:
		biomass_texture.update(images[0])
		resource_texture.update(images[1])
	label.text = (
		"УЧАСТОК %d · G закрыть\n%s\n%.0f м · шаг %.2f м · кг C/м²\n↑ мицелий · ↓ доступный C"
		% [selected_plot + 1, plot.definition.display_name, n * cell_size, cell_size]
	)
