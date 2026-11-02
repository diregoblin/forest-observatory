class_name ForestHud
extends CanvasLayer

signal rain_requested
signal dam_requested
signal pause_requested
signal frame_limit_requested
signal style_requested
signal speed_requested(value: float)
signal view_requested(index: int)
signal season_requested
signal save_requested
signal load_requested
signal soil_layers_requested
signal options_toggled(open: bool)
signal bank_relief_requested(enabled: bool)
signal grass_lighting_requested(enabled: bool)
signal cloud_shadows_requested(enabled: bool)
signal volumetric_requested(enabled: bool)
signal shadow_quality_requested(quality: int)

var info: Label
var journal: Label
var notes_container: VBoxContainer
var weather_label: Label
var plant_label: Label
var rain_button: Button
var dam_button: Button
var pause_button: Button
var frame_limit_button: Button
var bank_relief_button: CheckButton
var grass_lighting_button: CheckButton
var cloud_shadows_button: CheckButton
var volumetric_button: CheckButton
var shadow_quality_selector: OptionButton
var style_button: Button
var season_button: Button
var calendar_label: Label
var speed_buttons: Dictionary = {}
var hydro_map := ForestHydrologyMap.new()
var map_legend: Label
var fungi_map := ForestFungiMap.new()
var fungi_label: Label
var notices: Array[String] = ["Исток питает ручей. Долина просыпается."]
var observation_panel := ForestObservationPanel.new()
var animal_label: Label
var soil_layers := ForestSoilLayers.new()
var options_overlay: Control
var options_tabs: TabContainer
var options_button: Button
var view_selector: MenuButton
var status_label: Label
var toast: Label
var toast_timer := Timer.new()


func configure(settings: ForestSettings, animal_definitions: Array = []) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var heading := VBoxContainer.new()
	heading.position = Vector2(28, 22)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(heading)
	_label(heading, "Тихая долина", 26, Color(.97, .96, .87))
	status_label = _label(heading, "", 14, Color(.86, .89, .79))
	options_button = _button(root, "Опции · Esc", func(): set_options_open(true))
	options_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	options_button.offset_left = -180
	options_button.offset_right = -28
	options_button.offset_top = 26
	options_button.offset_bottom = 62

	var playback := PanelContainer.new()
	root.add_child(playback)
	playback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	playback.offset_left = 28
	playback.offset_top = -64
	playback.offset_bottom = -24
	playback.add_theme_stylebox_override("panel", _panel_style(8))
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	playback.add_child(bar)
	pause_button = _button(bar, "Пауза", func(): pause_requested.emit())
	pause_button.custom_minimum_size.x = 104
	pause_button.tooltip_text = "Пауза / продолжить · Пробел"
	var speed_group := ButtonGroup.new()
	for speed in [1, 8, 60, 600]:
		var button := _button(bar, "×" + str(speed), func(): speed_requested.emit(float(speed)))
		button.toggle_mode = true
		button.button_group = speed_group
		button.tooltip_text = "Общий темп воды, суток и года ×%d" % speed
		button.add_theme_color_override("font_pressed_color", Color(.97, .96, .87))
		button.add_theme_color_override("font_hover_pressed_color", Color(.97, .96, .87))
		var selected := _panel_style(4)
		selected.bg_color = Color(.33, .43, .25, .95)
		button.add_theme_stylebox_override("pressed", selected)
		speed_buttons[float(speed)] = button
	view_selector = MenuButton.new()
	view_selector.text = "Точки наблюдения ▾"
	view_selector.focus_mode = Control.FOCUS_ALL
	view_selector.custom_minimum_size = Vector2(216, 30)
	view_selector.add_theme_font_size_override("font_size", 15)
	view_selector.add_theme_stylebox_override("normal", _panel_style(6))
	bar.add_child(view_selector)
	var labels := ["Над кронами", "У ручья", "У преграды", "Грибная поляна"]
	for definition in animal_definitions:
		labels.append(definition.get_meta(&"population_label", definition.display_name))
	for index in labels.size():
		view_selector.get_popup().add_item("%d · %s" % [index + 1, labels[index]], index + 1)
	view_selector.get_popup().id_pressed.connect(func(id: int): view_requested.emit(id))
	view_selector.tooltip_text = "Перейти к месту или животным · клавиши 1–9"

	root.add_child(observation_panel)
	observation_panel.offset_top = 82
	_scene_note_overlay(root)
	_build_options(root, settings)
	root.add_child(soil_layers)
	soil_layers.configure()
	# A notification appears briefly, not as a permanent second sidebar.
	toast = _label(root, "", 14, Color(.95, .94, .82))
	toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	toast.offset_left = -468
	toast.offset_right = -28
	toast.offset_top = -130
	toast.offset_bottom = -78
	toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.z_index = 101
	toast.hide()
	toast_timer.one_shot = true
	toast_timer.wait_time = 7
	toast_timer.timeout.connect(toast.hide)
	add_child(toast_timer)


func _panel_style(margin: int) -> StyleBoxFlat:
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(.055, .095, .08, .96)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = margin
	panel.content_margin_right = margin
	panel.content_margin_top = margin
	panel.content_margin_bottom = margin
	return panel


func _options_page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	options_tabs.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	return content


func _build_options(root: Control, settings: ForestSettings) -> void:
	options_overlay = Control.new()
	options_overlay.z_index = 100
	root.add_child(options_overlay)
	options_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(.015, .025, .02, .65)
	options_overlay.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	options_overlay.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -350
	panel.offset_right = 350
	panel.offset_top = -292
	panel.offset_bottom = 292
	panel.add_theme_stylebox_override("panel", _panel_style(22))
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := _label(header, "Опции", 26, Color(.97, .96, .87))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "Вернуться в лес · Esc", func(): set_options_open(false))
	options_tabs = TabContainer.new()
	options_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	options_tabs.add_theme_font_size_override("font_size", 16)
	options_tabs.add_theme_stylebox_override("panel", _panel_style(16))
	content.add_child(options_tabs)
	var graphics := _options_page("Вид")
	_label(graphics, "ОТРИСОВКА", 12, Color(.70, .76, .60))
	style_button = _button(graphics, "Вид · Пиксельный · F8", func(): style_requested.emit())
	frame_limit_button = _button(graphics, "Графика · 60 FPS", func(): frame_limit_requested.emit())
	frame_limit_button.tooltip_text = (
		"Лимит 30 / 60 кадров в секунду. 30 FPS могут снизить нагрузку на видеокарту."
		+ "\nПри нехватке производительности фактический темп мира может быть ниже выбранного."
	)
	bank_relief_button = CheckButton.new()
	bank_relief_button.text = "Микрорельеф берегов"
	bank_relief_button.tooltip_text = "Мелкие неровности сухого песка вблизи. Добавляет геометрию и нагрузку на GPU."
	bank_relief_button.toggled.connect(func(enabled: bool): bank_relief_requested.emit(enabled))
	graphics.add_child(bank_relief_button)
	grass_lighting_button = CheckButton.new()
	grass_lighting_button.text = "Освещение травы от земли"
	grass_lighting_button.button_pressed = true
	grass_lighting_button.tooltip_text = "Согласовать свет и тени пучков с поверхностью под ними."
	grass_lighting_button.toggled.connect(func(value: bool): grass_lighting_requested.emit(value))
	graphics.add_child(grass_lighting_button)
	cloud_shadows_button = CheckButton.new()
	cloud_shadows_button.text = "Тени облаков"
	cloud_shadows_button.button_pressed = true
	cloud_shadows_button.tooltip_text = "Движущиеся тени низких облаков на всём лесу. Добавляет нагрузку на GPU."
	cloud_shadows_button.toggled.connect(func(value: bool): cloud_shadows_requested.emit(value))
	graphics.add_child(cloud_shadows_button)
	var shadow_row := HBoxContainer.new()
	graphics.add_child(shadow_row)
	var shadow_label := _label(shadow_row, "Качество теней", 16, Color(.86, .89, .79))
	shadow_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shadow_quality_selector = OptionButton.new()
	for quality in [
		["Низкое", RenderingServer.SHADOW_QUALITY_SOFT_LOW],
		["Среднее", RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM],
		["Высокое", RenderingServer.SHADOW_QUALITY_SOFT_HIGH],
		["Максимальное", RenderingServer.SHADOW_QUALITY_SOFT_ULTRA]
	]:
		shadow_quality_selector.add_item(quality[0], quality[1])
	shadow_quality_selector.tooltip_text = "Качество мягких солнечных теней от облаков и деревьев. Выше — меньше зернистость, больше нагрузка на видеокарту."
	shadow_quality_selector.item_selected.connect(
		func(index: int): shadow_quality_requested.emit(shadow_quality_selector.get_item_id(index))
	)
	shadow_row.add_child(shadow_quality_selector)
	volumetric_button = CheckButton.new()
	volumetric_button.text = "Объёмный свет"
	volumetric_button.tooltip_text = "Солнечные лучи и объёмная дымка. Эффект заметнее среди деревьев навстречу солнцу; добавляет нагрузку на GPU."
	volumetric_button.disabled = RenderingServer.get_current_rendering_method() != "forward_plus"
	volumetric_button.toggled.connect(func(value: bool): volumetric_requested.emit(value))
	graphics.add_child(volumetric_button)
	_label(graphics, "F — скрыть или вернуть весь интерфейс", 15, Color(.79, .84, .74))

	var world := _options_page("Мир")
	_label(world, "ЭКСПЕРИМЕНТЫ", 12, Color(.70, .76, .60))
	rain_button = _button(world, "Дождь · ВЫКЛ", func(): rain_requested.emit())
	rain_button.tooltip_text = (
		"Изменить осадки до следующего погодного фронта." + " Затем вернётся динамическая погода."
	)
	dam_button = _button(world, "Преграда · НЕТ", func(): dam_requested.emit())
	season_button = _button(world, "Сезоны · T", func(): season_requested.emit())
	world.add_child(HSeparator.new())
	_label(world, "СОСТОЯНИЕ МИРА", 12, Color(.70, .76, .60))
	_button(world, "Сохранить · F5", func(): save_requested.emit())
	_button(world, "Загрузить · F9", func(): load_requested.emit())

	var data := _options_page("Наблюдения")
	var maps := HBoxContainer.new()
	data.add_child(maps)
	_button(maps, "Вода · M", func(): _show_layer(toggle_map))
	_button(maps, "Мицелий · G", func(): _show_layer(toggle_fungi_map))
	_button(maps, "Почва · V", func(): _show_layer(func(): soil_layers_requested.emit()))
	_label(
		data,
		"ЛЕСНОЙ ВОДОСБОР · %d × %d м" % [settings.extent, settings.extent],
		12,
		Color(.70, .76, .60)
	)
	calendar_label = _label(data, "", 15, Color(.85, .89, .74))
	weather_label = _label(data, "", 15, Color(.79, .84, .74))
	info = _label(data, "", 15, Color(.93, .94, .83))
	plant_label = _label(data, "", 15, Color(.79, .84, .74))
	fungi_label = _label(data, "", 15, Color(.89, .80, .61))
	animal_label = _label(data, "", 15, Color(.86, .84, .71))
	data.add_child(HSeparator.new())
	notes_container = VBoxContainer.new()
	data.add_child(notes_container)
	_label(notes_container, "ПОЛЕВЫЕ ЗАМЕТКИ", 12, Color(.85, .86, .68))
	journal = _label(notes_container, notices[0], 15, Color(.94, .94, .85))
	journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	var help := _options_page("Управление")
	_label(help, "КАМЕРА", 12, Color(.70, .76, .60))
	_label(
		help,
		"ПКМ + WASD — полёт · Q / E — высота\nShift — быстрее · 1–9 — точки наблюдения",
		16,
		Color(.93, .94, .83)
	)
	_label(
		help,
		"ЛКМ — карточка растения, гриба или животного\nC — следовать за выбранным животным",
		16,
		Color(.93, .94, .83)
	)
	help.add_child(HSeparator.new())
	_label(
		help,
		(
			"Пробел — пауза · R — дождь · B — преграда"
			+ "\nT — просмотр сезонов · M — вода · G — мицелий · V — почва"
			+ "\nF5 — сохранить · F9 — загрузить · F8 — стиль"
			+ "\nF — интерфейс · Esc — опции / вернуться в лес"
		),
		16,
		Color(.85, .89, .74)
	)
	options_overlay.hide()


func _scene_note_overlay(root: Control) -> void:
	observation_panel.close_requested.connect(func(): observation_panel.show_record({}))
	hydro_map.position = Vector2(-296, 180)
	hydro_map.anchor_left = 1
	hydro_map.anchor_right = 1
	hydro_map.size = Vector2(256, 256)
	hydro_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hydro_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hydro_map.visible = false
	root.add_child(hydro_map)
	map_legend = _label(
		root,
		(
			"ГРУНТОВАЯ ВОДА · M · север ↑"
			+ "\nЗапас 0–100%: коричневый → голубой"
			+ "\nСиний: поверхность · жёлтый: выход воды"
		),
		13,
		Color(.94, .94, .85)
	)
	map_legend.position = Vector2(-360, 450)
	map_legend.anchor_left = 1
	map_legend.anchor_right = 1
	map_legend.visible = false


func set_options_open(open: bool) -> void:
	if open:
		visible = true
	options_overlay.visible = open
	options_toggled.emit(open)
	if not open:
		get_viewport().gui_release_focus()


func _show_layer(callback: Callable) -> void:
	set_options_open(false)
	callback.call()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			set_options_open(not options_overlay.visible)
			get_viewport().set_input_as_handled()


func _unhandled_input(_event: InputEvent) -> void:
	# Keep menu keys / pointer input away from world picking and free flight.
	if visible and options_overlay.visible:
		get_viewport().set_input_as_handled()


func _label(parent: Node, s: String, size: int, c: Color) -> Label:
	var l := Label.new()
	l.text = s
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, .5))
	parent.add_child(l)
	return l


func _button(parent: Node, s: String, callback: Callable) -> Button:
	var b := Button.new()
	b.text = s
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 30
	b.add_theme_font_size_override("font_size", 15)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.16, .23, .18, .9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.set_corner_radius_all(4)
	b.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(.25, .34, .24)
	b.add_theme_stylebox_override("hover", hover)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


func refresh(
	water: ForestWatershed,
	vegetation: ForestVegetation,
	groundcover: ForestGroundcover,
	barrier_enabled: bool,
	requested_speed := 1.0,
	achieved_speed := 0.0,
	trees: ForestTrees = null,
	climate: Dictionary = {},
	preview := false
) -> void:
	info.text = (
		(
			"Вода  %02d:%02d:%02d\nПоверхность  %d м³\nВ почве  %d м³ · под ней %d м³"
			+ "\nТемп мира ×%.0f · факт ×%.1f"
		)
		% [
			int(water.clock / 3600),
			int(water.clock / 60) % 60,
			int(water.clock) % 60,
			water.volume(),
			water.soil_volume,
			water.stats.groundwater_m3,
			requested_speed,
			achieved_speed
		]
	)
	for speed in speed_buttons:
		speed_buttons[speed].set_pressed_no_signal(is_equal_approx(speed, requested_speed))
	weather_label.text = (
		"Дождь  %.0f мм/ч" % (water.config.rainfall_m_s * 3600000.0)
		if water.raining
		else "Переменная облачность"
	)
	plant_label.text = "%d деревьев · рост травы %d" % [vegetation.tree_count, groundcover.ticks]
	if trees != null:
		plant_label.text = (
			"%d живых растений · %d видов"
			% [trees.alive.count(1), trees.land.settings.plants.size()]
		)
	if not climate.is_empty():
		status_label.text = (
			"%s · %s%s\n%s · %.0f °C"
			% [
				climate.date,
				climate.time,
				" · ПРОСМОТР" if preview else "",
				climate.get("weather_title", climate.season),
				climate.temperature_c
			]
		)
		calendar_label.text = (
			"Год %d · %s · %s\n%s · %.0f °C · свет %.1f ч\nСутки %s · год %s%s"
			% [
				climate.year,
				climate.date,
				climate.time,
				climate.season,
				climate.temperature_c,
				climate.daylight_h,
				_duration(water.config.day_water_s() / requested_speed),
				_duration(water.config.year_water_s() / requested_speed),
				" · ПРОСМОТР" if preview else ""
			]
		)
		calendar_label.tooltip_text = (
			"Длительности при выбранном темпе; при нагрузке весь мир замедляется вместе."
			+ (
				"\nМножитель суток ×%.0f, биологического времени ×%.0f к водным секундам."
				% [water.config.day_speed_multiplier, water.config.year_speed_multiplier]
			)
		)
		calendar_label.text += (
			"\n%s · ветер %.1f м/с"
			% [climate.get("weather_title", "Просмотр сезона"), climate.get("wind_m_s", 0.0)]
		)
		season_button.text = "К расчёту · T" if preview else "Сезоны · T"
	hydro_map.refresh(water)

	rain_button.text = "Дождь · ВКЛ" if water.raining else "Дождь · ВЫКЛ"
	dam_button.text = "Преграда · ЕСТЬ" if barrier_enabled else "Преграда · НЕТ"


func _duration(seconds: float) -> String:
	return "%.1f мин" % (seconds / 60.0) if seconds >= 60 else "%.1f с" % seconds


func toggle_map() -> void:
	if soil_layers.visible:
		soil_layers_requested.emit()
	hydro_map.visible = not hydro_map.visible
	map_legend.visible = hydro_map.visible
	if hydro_map.visible:
		fungi_map.visible = false


func configure_fungi(fungi: ForestFungi) -> void:
	add_child(fungi_map)
	fungi_map.configure(fungi)


func toggle_fungi_map() -> void:
	if soil_layers.visible:
		soil_layers_requested.emit()
	fungi_map.visible = not fungi_map.visible
	if fungi_map.visible:
		hydro_map.visible = false
		map_legend.visible = false
		fungi_map.refresh()


func refresh_fungi(view: ForestFungiView) -> void:
	fungi_label.text = (
		"%d грибов · %d групп\nМицелий: %d участка почвы"
		% [view.body_count, view.group_count, view.model.plots.size()]
	)
	if view.model.metrics().boundary_affected:
		fungi_label.text += "\nФронт достиг границы участка"
	if fungi_map.visible:
		fungi_map.refresh()


func set_paused(paused: bool) -> void:
	pause_button.text = "Продолжить" if paused else "Пауза"


func notice(s: String) -> void:
	notices.push_front(s)
	if notices.size() > 3:
		notices.resize(3)
	if journal:
		journal.text = "\n\n".join(notices)
	if toast:
		toast.text = s
		toast.show()
		toast_timer.start()
