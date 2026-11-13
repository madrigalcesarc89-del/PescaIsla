extends Control
## Burbuja junto al gato y resalte del control. El toque pasa al juego;
## solo Omitir se queda con el puntero.

signal skipped

const INK := Color("5A3D2B")
const CREAM := Color("FFF1D6")

var _skip: Button
var _bubble: PanelContainer
var _label: Label
var _rings: Array = []
var _targets: Array = []
var _text := ""
var _anchor := Vector2(540, 900)
var _pulse := 0.0
var _fit_w := -1.0
var _avoid: Array = []


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_cream(_skip)
	_skip.pressed.connect(func() -> void: skipped.emit())
	_bubble = PanelContainer.new()
	_bubble.name = "Bubble"
	_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_cream(_bubble)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_bubble.add_child(_label)
	for _i in 3:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.visible = false
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.969, 0.718, 0.639, 0.22)
		sb.border_color = Color("C45A32")
		sb.set_border_width_all(8)
		sb.set_corner_radius_all(32)
		ring.add_theme_stylebox_override("panel", sb)
		add_child(ring)
		_rings.append(ring)
	add_child(_bubble)
	add_child(_skip)
	visible = false


func present(text: String, targets: Array, anchor: Vector2) -> void:
	var changed := text != _text
	_text = text
	_targets = targets
	_anchor = anchor
	visible = true
	if changed:
		_fit_w = -1.0
	_layout()


func set_cat_anchor(anchor: Vector2) -> void:
	_anchor = anchor


func set_avoid(nodes: Array) -> void:
	_avoid = nodes


func hide_tutorial() -> void:
	visible = false
	_targets = []


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	var blink := 0.55 + 0.45 * sin(_pulse * 4.5)
	for ring in _rings:
		(ring as CanvasItem).modulate.a = blink
	_layout()


func _style_cream(node: Control) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.border_color = INK
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 22
	sb.content_margin_right = 22
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	if node is Button:
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			node.add_theme_stylebox_override(state_name, sb)
		node.add_theme_color_override("font_color", INK)
		node.add_theme_color_override("font_hover_color", INK)
		node.add_theme_color_override("font_pressed_color", INK)
		node.add_theme_color_override("font_focus_color", INK)
	else:
		node.add_theme_stylebox_override("panel", sb)


func _layout() -> void:
	var rw := size
	if rw.x < 20.0 or rw.y < 20.0:
		return
	var wide := minf(620.0, rw.x - 80.0)
	if absf(wide - _fit_w) > 1.0:
		_fit_w = wide
		_skip.text = SettingsData.t("tutorial_skip")
		UiFit.paint_light(_skip, 32)
		UiFit.fit_label(_skip, 260.0, 1, 22, 32)
		_label.text = _text
		UiFit.paint_light(_label, 34)
		UiFit.fit_label(_label, wide - 56.0, 4, 22, 34)
		var font := _label.get_theme_font("font")
		var px := _label.get_theme_font_size("font_size")
		if font != null and px > 0:
			var measured := font.get_multiline_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, wide - 56.0, px)
			_label.custom_minimum_size = Vector2(wide - 56.0, measured.y)
	var skip_ms := _skip.get_combined_minimum_size()
	var sw := clampf(skip_ms.x + 36.0, 200.0, rw.x - 48.0)
	var sh := maxf(72.0, skip_ms.y + 8.0)
	_skip.position = Vector2((rw.x - sw) * 0.5, 20.0)
	_skip.size = Vector2(sw, sh)
	var text_ms := _label.get_combined_minimum_size()
	var bw := clampf(text_ms.x + 8.0, 260.0, wide)
	var bh := maxf(96.0, text_ms.y + 8.0)
	var pos := _anchor + Vector2(-bw - 24.0, -bh - 120.0)
	pos.x = clampf(pos.x, 16.0, rw.x - bw - 16.0)
	var skip_bottom := _skip.position.y + sh + 12.0
	pos.y = clampf(pos.y, skip_bottom, rw.y - bh - 16.0)
	_bubble.position = pos
	_bubble.size = Vector2(bw, bh)
	var used := 0
	for t in _targets:
		if used >= _rings.size():
			break
		var ring: Panel = _rings[used]
		used += 1
		if t == null or not is_instance_valid(t) or not (t as CanvasItem).is_visible_in_tree():
			ring.visible = false
			continue
		var gr: Rect2 = (t as Control).get_global_rect()
		if gr.size.x < 8.0 or gr.size.y < 8.0:
			ring.visible = false
			continue
		var pad := 12.0
		ring.visible = true
		ring.position = gr.position - get_global_rect().position - Vector2(pad, pad)
		ring.size = gr.size + Vector2(pad * 2.0, pad * 2.0)
	for i in range(used, _rings.size()):
		(_rings[i] as Panel).visible = false
	_lift_off_obstacles(skip_bottom, rw)


func _lift_off_obstacles(skip_bottom: float, rw: Vector2) -> void:
	var bh := _bubble.size.y
	for _attempt in 4:
		var rect := Rect2(_bubble.position, _bubble.size)
		var top := rw.y
		var hit := false
		for block in _blocks():
			if rect.intersects(block):
				hit = true
				top = minf(top, block.position.y)
		if not hit:
			return
		var above := top - bh - 14.0
		if above < skip_bottom:
			return
		_bubble.position.y = above


func _blocks() -> Array:
	var out: Array = []
	for ring in _rings:
		var panel := ring as Panel
		if panel != null and panel.visible:
			out.append(Rect2(panel.position, panel.size))
	for node in _avoid:
		if node == null or not is_instance_valid(node):
			continue
		var item := node as CanvasItem
		var ctrl := node as Control
		if item == null or ctrl == null or not item.is_visible_in_tree():
			continue
		var gr := ctrl.get_global_rect()
		if gr.size.x < 8.0 or gr.size.y < 8.0:
			continue
		var local := gr.position - get_global_rect().position
		out.append(Rect2(local, gr.size).grow(10.0))
	return out
