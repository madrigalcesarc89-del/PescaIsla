extends Control
## Barra para arrastrar un adorno por el muelle. No toca el mundo 3D.

signal dragged(at: Vector2)
signal rotate_pressed
signal confirm_pressed
signal cancel_pressed

const CREAM := Color("FFF1D6")
const INK := Color("5A3D2B")
const PEACH := Color("F7B7A3")
const SAGE := Color("8FB996")
const LINE := Color("E3B792")

var _hint: Label
var _put: Button


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bar := PanelContainer.new()
	bar.name = "Bar"
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 36.0
	bar.offset_right = -36.0
	bar.offset_top = -440.0
	bar.offset_bottom = -28.0
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.border_color = LINE
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	bar.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	bar.add_child(col)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(0, 84)
	UiFit.paint_light(_hint, 30)
	col.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var turn := _button("Turn", SettingsData.t("place_rotate"), PEACH)
	turn.pressed.connect(func() -> void: rotate_pressed.emit())
	_put = _button("Put", SettingsData.t("place_put"), SAGE)
	_put.pressed.connect(func() -> void: confirm_pressed.emit())
	var cancel := _button("Cancel", SettingsData.t("shop_cancel"), CREAM)
	cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	row.add_child(turn)
	row.add_child(_put)
	row.add_child(cancel)
	add_child(bar)
	_hint.text = SettingsData.t("place_drag")


func show_place() -> void:
	visible = true
	_hint.text = SettingsData.t("place_drag")


func set_status(valid: bool, reason: String) -> void:
	var key := "place_ok"
	if not valid:
		if reason == "water":
			key = "place_water"
		elif reason == "clip":
			key = "place_clip"
		else:
			key = "place_busy"
	_hint.text = SettingsData.t(key)
	UiFit.fit_label(_hint, maxf(240.0, size.x - 120.0), 2, 22, 30)
	_put.disabled = not valid
	_put.modulate = Color(1, 1, 1, 1) if valid else Color(1, 1, 1, 0.45)


func _button(node_name: String, text: String, face: Color) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.custom_minimum_size = Vector2(210, 126)
	var box := StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = LINE
	box.set_border_width_all(4)
	box.set_corner_radius_all(24)
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, box)
	UiFit.paint_light(btn, 28)
	btn.add_theme_color_override("font_disabled_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", INK)
	UiFit.fit_label(btn, 180.0, 1, 18, 28)
	return btn


func _gui_input(event: InputEvent) -> void:
	var at := Vector2(-1, -1)
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		at = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		at = (event as InputEventScreenDrag).position
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			at = mb.global_position
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			at = mm.global_position
	if at.x < 0.0:
		return
	dragged.emit(at)
	accept_event()
