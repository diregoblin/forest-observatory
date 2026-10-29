class_name ForestHud
extends CanvasLayer

signal rain_requested
signal dam_requested
signal pause_requested
signal speed_requested(value: float)
signal view_requested(index: int)

var info: Label
var journal: Label
var weather_label: Label
var plant_label: Label
var rain_button: Button
var dam_button: Button
var pause_button: Button
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
	style.content_margin_top = 19
	style.content_margin_bottom = 19
	panel.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)
	_label(v, "НАБЛЮДЕНИЕ", 12, Color(.70, .76, .60))
	info = _label(v, "", 17, Color(.93, .94, .83))
	weather_label = _label(v, "", 14, Color(.79, .84, .74))
	plant_label = _label(v, "", 14, Color(.79, .84, .74))
	v.add_child(HSeparator.new())
	rain_button = _button(v, "Дождь · ВЫКЛ", func(): rain_requested.emit())
	dam_button = _button(v, "Преграда · НЕТ", func(): dam_requested.emit())
	pause_button = _button(v, "Пауза", func(): pause_requested.emit())
	var speeds := HBoxContainer.new()
	v.add_child(speeds)
	for s in [1, 2, 8]:
		var b := _button(speeds, "×" + str(s), func(): speed_requested.emit(float(s)))
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(HSeparator.new())
	_label(v, "ТОЧКИ НАБЛЮДЕНИЯ", 12, Color(.70, .76, .60))
	_button(v, "1   Над кронами", func(): view_requested.emit(1))
	_button(v, "2   У ручья", func(): view_requested.emit(2))
	_button(v, "3   У преграды", func(): view_requested.emit(3))
	var footer := Label.new()
	footer.text = (
		"ПКМ + WASD — полёт   ·   Q/E — высота   ·   Shift — быстрее"
		+ "   ·   R дождь   ·   B преграда   ·   F скрыть панель"
	)
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(.90, .92, .82))
	footer.anchor_top = 1
	footer.anchor_bottom = 1
	footer.offset_left = 38
	footer.offset_top = -42
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
	b.custom_minimum_size.y = 33
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
	barrier_enabled: bool
) -> void:
	info.text = "Модельное время  %05.1f\nВода в долине  %d м³" % [water.clock, water.volume()]
	weather_label.text = "Дождь идёт" if water.raining else "Переменная облачность"
	plant_label.text = "%d деревьев · рост травы %d" % [vegetation.tree_count, groundcover.ticks]

	rain_button.text = "Дождь · ВКЛ" if water.raining else "Дождь · ВЫКЛ"
	dam_button.text = "Преграда · ЕСТЬ" if barrier_enabled else "Преграда · НЕТ"


func set_paused(paused: bool) -> void:
	pause_button.text = "Продолжить" if paused else "Пауза"


func notice(s: String) -> void:
	notices.push_front(s)
	if notices.size() > 3:
		notices.resize(3)
	if journal:
		journal.text = "\n\n".join(notices)
