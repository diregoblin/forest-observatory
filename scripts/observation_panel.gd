class_name ForestObservationPanel
extends PanelContainer

## One small field-guide panel for any selected individual/cohort.
signal close_requested
signal follow_requested(enabled: bool)
var title: Label
var distinctions: Label
var subtitle: Label
var state_label: Label
var description: Label
var details: Label
var details_toggle: CheckButton
var follow_toggle: CheckButton
var content: VBoxContainer
var scroll: ScrollContainer
var heading: HBoxContainer
var displayed_identity := ""


func _ready() -> void:
	anchor_left = 1
	anchor_right = 1
	offset_left = -380
	offset_right = -24
	offset_top = 28
	var style := StyleBoxFlat.new()
	style.bg_color = Color(.055, .095, .08, .96)
	style.set_corner_radius_all(9)
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	add_theme_stylebox_override("panel", style)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 8)
	add_child(shell)
	heading = HBoxContainer.new()
	shell.add_child(heading)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(scroll)
	var box := VBoxContainer.new()
	content = box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)
	scroll.add_child(box)
	title = _label(heading, 23, Color(.97, .96, .87))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "×"
	close.tooltip_text = "Закрыть карточку"
	close.pressed.connect(func(): close_requested.emit())
	heading.add_child(close)
	distinctions = _label(box, 15, Color(.90, .77, .46))
	distinctions.visible = false
	subtitle = _label(box, 14, Color(.76, .83, .68))
	state_label = _label(box, 15, Color(.92, .92, .80))
	box.add_child(HSeparator.new())
	description = _label(box, 15, Color(.84, .88, .78))
	follow_toggle = CheckButton.new()
	follow_toggle.text = "Следить"
	follow_toggle.tooltip_text = "Сохраняет ракурс относительно животного. Движение камеры отменяет слежение."
	follow_toggle.toggled.connect(func(value: bool): follow_requested.emit(value))
	box.add_child(follow_toggle)
	var more := CheckButton.new()
	details_toggle = more
	more.text = "Условия и состояние"
	more.toggled.connect(
		func(value: bool):
			details.visible = value
			_fit_content.call_deferred()
	)
	box.add_child(more)
	details = _label(box, 13, Color(.75, .82, .72))
	details.visible = false
	visible = false
	get_viewport().size_changed.connect(func(): _fit_content.call_deferred())


func _fit_content() -> void:
	# Grow only as much as this record needs; long records scroll within the card.
	var available := maxf(140, get_viewport_rect().size.y - offset_top - 100)
	size.y = minf(
		available,
		content.get_combined_minimum_size().y + heading.get_combined_minimum_size().y + 40
	)


func _label(parent: Node, size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 260
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label


func show_record(record: Dictionary, following := false) -> void:
	visible = not record.is_empty()
	if not visible:
		return
	var record_key := "%s:%s" % [record.get("kind", ""), record.get("id", -1)]
	if record_key != displayed_identity:
		details_toggle.set_pressed_no_signal(false)
		details.hide()
		scroll.scroll_vertical = 0
		displayed_identity = record_key
	follow_toggle.visible = record.get("kind") == &"animal" and record.get("alive", false)
	follow_toggle.set_pressed_no_signal(following and follow_toggle.visible)
	title.text = str(
		record.get("title", record.get("display_name", record.get("name", "Наблюдение")))
	)
	var names: Array[String] = []
	var reasons: Array[String] = []
	for distinction in record.get("distinctions", []):
		names.append(distinction.title)
		reasons.append("%s: %s" % [distinction.title, distinction.reason])
	distinctions.visible = not names.is_empty()
	distinctions.text = " · ".join(names)
	distinctions.tooltip_text = "\n".join(reasons)
	subtitle.text = str(record.get("subtitle", record.get("latin_name", "")))
	var age: float = record.get("age_years", 0.0)
	var age_text := "%.1f года" % age if age >= 1 else "%.0f дней" % (age * 365)
	var animal: bool = record.get("kind") == &"animal"
	details_toggle.text = "Сведения об особи" if animal else "Условия и состояние"
	if animal:
		# Identity/age and current state have separate jobs. A dead individual
		# has one terminal status, not a life stage + action + generic suffix.
		var sex: String = record.get("sex_label", "")
		var identity := "%s · %s" % [sex.capitalize(), age_text] if not sex.is_empty() else age_text
		var status: String = record.get("stage", "")
		if record.get("alive", false):
			var action: String = record.get(
				"action_label", record.get("details", {}).get("Действие", "")
			)
			if not action.is_empty():
				status += " · " + action
		state_label.text = identity + "\n" + status.left(1).to_upper() + status.substr(1)
	else:
		state_label.text = (
			str(record.get("stage", ""))
			if record.get("kind") == &"fungus"
			else "%s · %s" % [record.get("stage", ""), age_text]
		)
		if record.get("initial_age", false):
			state_label.text += "\nНачальный возраст задан сценарием"
		# Plant/fungus stage already describes death when supplied by its model.
		if not record.get("alive", true) and "погиб" not in state_label.text.to_lower():
			state_label.text += " · погибло"
	description.text = str(record.get("description", ""))
	var lines: Array[String] = []
	for key in record.get("details", {}):
		if animal:
			if key == "Действие":
				continue  # Already visible above, including the single death status.
			if (
				not record.get("alive", false)
				and key not in ["Возраст", "Пол", "Родители", "Удачные охоты", "Останки"]
			):
				continue  # No current hunger, routine, alarm or expected litter after death.
		lines.append("%s: %s" % [key, record.details[key]])
	if record.has("source_url") and not str(record.source_url).is_empty():
		lines.append("Справка: %s" % record.source_url)
	details.text = "\n".join(lines)
	_fit_content.call_deferred()
