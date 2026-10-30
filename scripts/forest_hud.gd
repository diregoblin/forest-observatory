class_name ForestHud
extends CanvasLayer

signal rain_requested
signal dam_requested
signal pause_requested
signal speed_requested(value: float)
signal view_requested(index: int)
signal season_requested

var info: Label
var journal: Label
var weather_label: Label
var plant_label: Label
var rain_button: Button
var dam_button: Button
var pause_button: Button
var season_button: Button
var calendar_label: Label
var hydro_map := ForestHydrologyMap.new()
var map_legend: Label
var fungi_map := ForestFungiMap.new()
var fungi_label: Label
var notices: Array[String] = ["Исток питает ручей. Долина просыпается."]


func configure(settings: ForestSettings) -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_left", 38)
	top.add_theme_constant_override("margin_top", 28)
	root.add_child(top)
	var box := VBoxContainer.new()
	top.add_child(box)
	_label(box, "ПОЛЕВАЯ СТАНЦИЯ   /   01", 14, Color(.85, .86, .68))
	_label(box, "Тихая долина", 38, Color(.97, .96, .87))
	_label(
		box,
		"Лесной водосбор · %d × %d м" % [settings.extent, settings.extent],
		15,
		Color(.85, .89, .82)
	)
	var panel := PanelContainer.new()
	panel.position = Vector2(36, 156)
	panel.custom_minimum_size = Vector2(268, 0)
	root.add_child(panel)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.055, .095, .08, .88)
	style.set_corner_radius_all(7)
	style.content_margin_left = 19
	style.content_margin_right = 19
	style.content_margin_top = 14
	style.content_margin_bottom = 14
	panel.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	panel.add_child(v)
	_label(v, "НАБЛЮДЕНИЕ", 12, Color(.70, .76, .60))
	info = _label(v, "", 15, Color(.93, .94, .83))
	calendar_label = _label(v, "", 14, Color(.85, .89, .74))
	weather_label = _label(v, "", 14, Color(.79, .84, .74))
	plant_label = _label(v, "", 14, Color(.79, .84, .74))
	fungi_label = _label(v, "", 14, Color(.89, .80, .61))
	v.add_child(HSeparator.new())
	rain_button = _button(v, "Дождь · ВЫКЛ", func(): rain_requested.emit())
	dam_button = _button(v, "Преграда · НЕТ", func(): dam_requested.emit())
	pause_button = _button(v, "Пауза", func(): pause_requested.emit())
	var speeds := HBoxContainer.new()
	v.add_child(speeds)
	for s in [1, 8, 60, 600]:
		var b := _button(speeds, "×" + str(s), func(): speed_requested.emit(float(s)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var diagnostics := HBoxContainer.new()
	v.add_child(diagnostics)
	season_button = _button(diagnostics, "Сезоны · T", func(): season_requested.emit())
	_button(diagnostics, "Вода · M", toggle_map)
	_button(v, "Мицелий / питание · G", toggle_fungi_map)
	v.add_child(HSeparator.new())
	_label(v, "ТОЧКИ НАБЛЮДЕНИЯ", 12, Color(.70, .76, .60))
	_button(v, "1   Над кронами", func(): view_requested.emit(1))
	_button(v, "2   У ручья", func(): view_requested.emit(2))
	_button(v, "3   У преграды", func(): view_requested.emit(3))
	_button(v, "4   Грибная поляна", func(): view_requested.emit(4))
	var footer := Label.new()
	footer.text = (
		"ПКМ + WASD — полёт   ·   Q/E — высота   ·   Shift — быстрее"
		+ "\nR дождь · B преграда · T сезоны · M вода · G мицелий · 4 грибы · F панель"
	)
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(.90, .92, .82))
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.offset_left = 38
	footer.offset_top = -55
	footer.offset_bottom = -16
	root.add_child(footer)
	var right := VBoxContainer.new()
	right.anchor_left = 1
	right.anchor_right = 1
	right.offset_left = -390
	right.offset_right = -38
	right.offset_top = 42
	right.custom_minimum_size = Vector2(340, 0)
	root.add_child(right)
	_label(right, "ПОЛЕВЫЕ ЗАМЕТКИ", 12, Color(.85, .86, .68))
	journal = _label(right, notices[0], 15, Color(.94, .94, .85))
	journal.custom_minimum_size.x = 320
	journal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hydro_map.position = Vector2(-296, 340)
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
			"ГРУНТОВАЯ ВОДА · север ↑\nКоричневый → голубой: запас 0–100%"
			+ "\nСиний: поверхность · жёлтый: выход воды"
		),
		13,
		Color(.94, .94, .85)
	)
	map_legend.position = Vector2(-360, 610)
	map_legend.anchor_left = 1
	map_legend.anchor_right = 1
	map_legend.visible = false


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
	requested_speed := 2.0,
	achieved_speed := 0.0,
	trees: ForestTrees = null,
	climate: Dictionary = {},
	preview := false
) -> void:
	info.text = (
		(
			"Вода  %02d:%02d:%02d\nПоверхность  %d м³\nВ почве  %d м³ · под ней %d м³"
			+ "\nТемп воды ×%.0f · факт ×%.1f"
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
	weather_label.text = (
		"Дождь  %.0f мм/ч" % (water.config.rainfall_m_s * 3600000.0)
		if water.raining
		else "Переменная облачность"
	)
	plant_label.text = "%d деревьев · рост травы %d" % [vegetation.tree_count, groundcover.ticks]
	if trees != null:
		plant_label.text = "%d живых деревьев · %d сухостой" % [trees.alive.count(1), trees.deaths]
	if not climate.is_empty():
		calendar_label.text = (
			"Год %d · %s · %s\n%s · %.0f °C · свет %.1f ч\nСутки %.0f с · год %.0f мин%s"
			% [
				climate.year,
				climate.date,
				climate.time,
				climate.season,
				climate.temperature_c,
				climate.daylight_h,
				water.config.ecology_day_s,
				water.config.ecology_year_s / 60.0,
				" · ПРОСМОТР" if preview else ""
			]
		)
		season_button.text = "К расчёту · T" if preview else "Сезоны · T"
	hydro_map.refresh(water)

	rain_button.text = "Дождь · ВКЛ" if water.raining else "Дождь · ВЫКЛ"
	dam_button.text = "Преграда · ЕСТЬ" if barrier_enabled else "Преграда · НЕТ"


func toggle_map() -> void:
	hydro_map.visible = not hydro_map.visible
	map_legend.visible = hydro_map.visible
	if hydro_map.visible:
		fungi_map.visible = false


func configure_fungi(fungi: ForestFungi) -> void:
	add_child(fungi_map)
	fungi_map.configure(fungi)


func toggle_fungi_map() -> void:
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
