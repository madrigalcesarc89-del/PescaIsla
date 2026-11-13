extends Control
## Tabla de 7 días. El premio sube cada día. El toque no pasa al juego.

signal claimed
signal dismissed

const INK := Color("5A3D2B")
const CREAM := Color("FFF1D6")
const PEACH := Color("F7B7A3")
const SAGE := Color("8FB996")
const GOLD := Color("E2A84B")

var _dim: ColorRect
var _panel: PanelContainer
var _title: Label
var _sub: Label
var _rows: VBoxContainer
var _claim: Button
var _later: Button
var _note: Label
var _can := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.color = Color(0.16, 0.09, 0.06, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.gui_input.connect(_on_dim)
	add_child(_dim)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.border_color = INK
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(36)
	sb.shadow_color = Color(0.22, 0.12, 0.06, 0.28)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 8)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 26
	sb.content_margin_bottom = 22
	_panel.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 8)
	_note = Label.new()
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_claim = Button.new()
	_claim.focus_mode = Control.FOCUS_NONE
	_claim.custom_minimum_size = Vector2(0, 84)
	_style_btn(_claim, true)
	_claim.pressed.connect(func() -> void:
		if _can:
			claimed.emit()
	)
	_later = Button.new()
	_later.focus_mode = Control.FOCUS_NONE
	_later.custom_minimum_size = Vector2(0, 72)
	_style_btn(_later, false)
	_later.pressed.connect(func() -> void: dismissed.emit())
	box.add_child(_title)
	box.add_child(_sub)
	box.add_child(_rows)
	box.add_child(_note)
	box.add_child(_claim)
	box.add_child(_later)
	_panel.add_child(box)
	add_child(_panel)
	visible = false
	resized.connect(_place)


func show_board(amounts: Array, streak: int, can_claim: bool, reason: String) -> void:
	_can = can_claim
	visible = true
	_title.text = SettingsData.t("gift_title")
	_sub.text = SettingsData.t("gift_sub")
	_later.text = SettingsData.t("gift_close")
	if reason == "clock":
		_note.text = SettingsData.t("gift_clock")
		_claim.visible = false
	elif not can_claim:
		_note.text = SettingsData.t("gift_wait")
		_claim.visible = false
	else:
		_note.text = ""
		_claim.visible = true
		_claim.text = SettingsData.t("gift_claim")
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.free()
	var max_coins := 1
	for raw in amounts:
		max_coins = maxi(max_coins, int(raw))
	var idx := clampi(streak, 0, maxi(amounts.size() - 1, 0))
	for i in amounts.size():
		_rows.add_child(_make_row(i, int(amounts[i]), max_coins, idx, can_claim))
	_fit()
	_place()
	call_deferred("_fit")
	call_deferred("_place")


func hide_board() -> void:
	visible = false


func _on_dim(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if not Rect2(_panel.position, _panel.size).has_point(event.position):
			dismissed.emit()
			_dim.accept_event()


func _make_row(i: int, coins: int, max_coins: int, streak: int, can_claim: bool) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var today := i == streak
	var done := i < streak
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 0.97, 0.92, 1)
	sb.set_corner_radius_all(18)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	if today:
		sb.bg_color = Color("FFE7C4")
		sb.border_color = Color("C45A32")
		sb.set_border_width_all(4)
	elif done:
		sb.bg_color = Color(0.90, 0.95, 0.90, 1)
	row.add_theme_stylebox_override("panel", sb)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var day := Label.new()
	day.text = SettingsData.t("gift_day") % [i + 1]
	day.custom_minimum_size = Vector2(118, 0)
	day.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = SAGE.lerp(GOLD, float(coins) / float(max_coins))
	fill.set_corner_radius_all(9)
	bar.add_theme_stylebox_override("panel", fill)
	bar.custom_minimum_size = Vector2(48.0 + 220.0 * float(coins) / float(max_coins), 22.0)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gap.custom_minimum_size = Vector2(8, 0)
	var amount := Label.new()
	amount.text = str(coins)
	amount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	amount.custom_minimum_size = Vector2(92, 0)
	amount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var state := Label.new()
	state.custom_minimum_size = Vector2(120, 0)
	state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if done:
		state.text = SettingsData.t("gift_got")
	elif today and can_claim:
		state.text = SettingsData.t("gift_today")
	elif today:
		state.text = SettingsData.t("gift_next")
	else:
		state.text = ""
	for lab in [day, amount, state]:
		UiFit.paint_light(lab, 28)
	box.add_child(day)
	box.add_child(bar)
	box.add_child(gap)
	box.add_child(amount)
	box.add_child(state)
	row.add_child(box)
	return row


func _fit() -> void:
	var wide := minf(680.0, size.x - 120.0)
	if wide < 200.0:
		wide = 520.0
	UiFit.paint_light(_title, 48)
	UiFit.fit_label(_title, wide - 40.0, 1, 28, 48)
	UiFit.paint_light(_sub, 26)
	UiFit.fit_label(_sub, wide - 40.0, 3, 18, 26)
	UiFit.paint_light(_note, 24)
	UiFit.fit_label(_note, wide - 40.0, 3, 16, 24)
	if _claim.visible:
		UiFit.paint_light(_claim, 32)
		UiFit.fit_label(_claim, wide - 80.0, 1, 20, 32)
	UiFit.paint_light(_later, 26)
	UiFit.fit_label(_later, wide - 80.0, 1, 18, 26)
	for row in _rows.get_children():
		for lab in row.find_children("*", "Label", true, false):
			UiFit.paint_light(lab, 26)
			UiFit.fit_label(lab, 160.0, 1, 16, 26)


func _place() -> void:
	if _panel == null:
		return
	var rw := size
	if rw.x < 20.0:
		return
	var w := minf(760.0, rw.x - 48.0)
	var h := minf(rw.y - 48.0, _panel.get_combined_minimum_size().y)
	if h < 200.0:
		h = minf(rw.y - 48.0, 980.0)
	_panel.size = Vector2(w, h)
	_panel.position = Vector2((rw.x - w) * 0.5, maxf(24.0, (rw.y - h) * 0.5))


func _style_btn(node: Button, primary: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PEACH if primary else CREAM
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(24)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	for state_name in ["normal", "hover", "pressed", "focus"]:
		node.add_theme_stylebox_override(state_name, sb)
	node.add_theme_color_override("font_color", INK)
	node.add_theme_color_override("font_hover_color", INK)
	node.add_theme_color_override("font_pressed_color", INK)
