extends Control
## Barra corta, arriba, para no tapar el muelle. No toca el mundo 3D.

signal dragged(at: Vector2)
signal rotate_pressed
signal up_pressed
signal down_pressed
signal confirm_pressed
signal cancel_pressed

const CREAM := Color("FFF1D6")
const INK := Color("5A3D2B")
const PEACH := Color("F7B7A3")
const SAGE := Color("8FB996")
const AQUA := Color("8FD0C8")
const LINE := Color("E3B792")

var _hint: Label
var _put: Button
var _bar: PanelContainer


func _ready() -> void:
	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_bar = PanelContainer.new()
	_bar.name = "Bar"
	_bar.anchor_left = 0.0
	_bar.anchor_right = 1.0
	_bar.anchor_top = 0.0
	_bar.anchor_bottom = 0.0
	_bar.offset_left = 20.0
	_bar.offset_right = -20.0
	_bar.offset_top = 172.0
	_bar.offset_bottom = 292.0
	_bar.mouse_filter = Control.MOUSE_FILTER_STOP
	_bar.clip_contents = true
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.border_color = LINE
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(22)
	sb.content_margin_left = 12.0
	sb.content_margin_right = 12.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_bar.add_theme_stylebox_override("panel", sb)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_bar.add_child(col)
	_hint = Label.new()
	_hint.name = "Hint"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	_hint.custom_minimum_size = Vector2(0, 28)
	_hint.clip_contents = true
	UiFit.paint_light(_hint, 22)
	col.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(row)
	var up := _button("Up", SettingsData.t("place_up"), AQUA)
	up.pressed.connect(func() -> void: up_pressed.emit())
	var down := _button("Down", SettingsData.t("place_down"), AQUA)
	down.pressed.connect(func() -> void: down_pressed.emit())
	var turn := _button("Turn", SettingsData.t("place_rotate"), PEACH)
	turn.pressed.connect(func() -> void: rotate_pressed.emit())
	_put = _button("Put", SettingsData.t("place_put"), SAGE)
	_put.pressed.connect(func() -> void: confirm_pressed.emit())
	var cancel := _button("Cancel", SettingsData.t("shop_cancel"), CREAM)
	cancel.pressed.connect(func() -> void: cancel_pressed.emit())
	row.add_child(up)
	row.add_child(down)
	row.add_child(turn)
	row.add_child(_put)
	row.add_child(cancel)
	add_child(_bar)
	_hint.text = SettingsData.t("place_drag")


func show_place() -> void:
	visible = true
	_hint.text = SettingsData.t("place_drag")


func set_status(valid: bool, reason: String) -> void:
	var key := "place_ok"
	if reason == "air":
		key = "place_air"
	elif reason == "water":
		key = "place_water"
	elif reason == "clip":
		key = "place_clip"
	elif reason == "busy":
		key = "place_busy"
	_hint.text = SettingsData.t(key)
	var wide := 640.0
	if _bar != null:
		wide = maxf(280.0, _bar.size.x - 48.0)
	UiFit.fit_label(_hint, wide, 1, 16, 22)
	_put.disabled = not valid
	_put.modulate = Color(1, 1, 1, 1) if valid else Color(1, 1, 1, 0.45)


func _button(node_name: String, text: String, face: Color) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(0, 64)
	var box := StyleBoxFlat.new()
	box.bg_color = face
	box.border_color = LINE
	box.set_border_width_all(3)
	box.set_corner_radius_all(18)
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, box)
	UiFit.paint_light(btn, 22)
	btn.add_theme_color_override("font_disabled_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", INK)
	UiFit.fit_label(btn, 150.0, 1, 15, 22)
	return btn


func _pointer(event: InputEvent) -> Vector2:
	if event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		return get_global_transform_with_canvas() * (event as InputEventScreenTouch).position
	if event is InputEventScreenDrag:
		return get_global_transform_with_canvas() * (event as InputEventScreenDrag).position
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			return mb.global_position
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
			return mm.global_position
	return Vector2(-1, -1)


func _gui_input(event: InputEvent) -> void:
	var at := _pointer(event)
	if at.x < 0.0:
		return
	if _bar != null and _bar.get_global_rect().has_point(at):
		accept_event()
		return
	dragged.emit(at)
	accept_event()
