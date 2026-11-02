class_name ForestFungiMap
extends Control

## First plot: biomass above, available carbon resource below. Read-only display.
var model: ForestFungi
var biomass_texture: ImageTexture
var resource_texture: ImageTexture
var biomass_view := TextureRect.new()
var resource_view := TextureRect.new()
var label := Label.new()
var last_tick := -1


func configure(fungi: ForestFungi) -> void:
	model = fungi
	position = Vector2(-302, 146)
	anchor_left = 1
	anchor_right = 1
	size = Vector2(264, 510)
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
	biomass_view.position.y = 64
	resource_view.position.y = 330
	visible = false
	refresh()


func refresh() -> void:
	if last_tick == model.revision:
		return
	last_tick = model.revision
	var config := model.land.settings
	var n := config.fungi_resolution
	var b: PackedFloat64Array = model.plots[0].fields.biomass
	var r: PackedFloat64Array = model.plots[0].fields.resource
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
				Color(.44, .80, .67), clampf(r[k] / config.fungus.resource_capacity_kg_m2, 0, 1)
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
		"ГРИБНОЙ УЧАСТОК 1 · G закрыть\n%.0f м · шаг %.2f м · кг C/м²\nСверху: мицелий · снизу: питание"
		% [n * config.fungi_cell_m, config.fungi_cell_m]
	)
