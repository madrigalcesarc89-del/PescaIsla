extends Control
## Burbuja junto al gato. Omitir vive dentro de la burbuja para no tapar botones.
## El resto de la pantalla se oscurece y una flecha marca dónde tocar.

signal skipped

const INK := Color("5A3D2B")
const CREAM := Color("FFF1D6")
const DIM_SHADER := preload("res://shaders/tutorial_dim.gdshader")

var _skip: Button
var _card: PanelContainer
var _label: Label
var _rings: Array = []
var _targets: Array = []
var _text := ""
var _anchor := Vector2(540, 900)
var _pulse := 0.0
var _fit_w := -1.0
var _avoid: Array = []
var _dim: ColorRect
var _dim_mat: ShaderMaterial
var _dim_a := 0.58
var _prefer_bottom := false
var _arrow: Node2D
var _done: PanelContainer
var _done_title: Label
var _done_body: Label
var _done_btn: Button
var _celebrating := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim = ColorRect.new()
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.color = Color(1, 1, 1, 1)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim_mat = ShaderMaterial.new()
	_dim_mat.shader = DIM_SHADER
	_dim.material = _dim_mat
	add_child(_dim)
	for _i in 3:
		var ring := Panel.new()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.visible = false
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.969, 0.718, 0.639, 0.38)
		sb.border_color = Color("C45A32")
		sb.set_border_width_all(14)
		sb.set_corner_radius_all(36)
		ring.add_theme_stylebox_override("panel", sb)
		add_child(ring)
		_rings.append(ring)
	_arrow = _make_arrow()
	add_child(_arrow)
	_card = PanelContainer.new()
	_card.name = "Bubble"
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_cream(_card)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 12)
	_label = Label.new()
	_label.name = "Text"
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_skip = Button.new()
	_skip.name = "Skip"
	_skip.focus_mode = Control.FOCUS_NONE
	_skip.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_cream(_skip)
	_skip.pressed.connect(func() -> void: skipped.emit())
	box.add_child(_label)
	box.add_child(_skip)
	_card.add_child(box)
	add_child(_card)
	_build_done()
	visible = false


func use_dim_shader(shader: Shader) -> void:
	if shader != null and _dim_mat != null:
		_dim_mat.shader = shader


func present(text: String, targets: Array, anchor: Vector2) -> void:
	var changed := text != _text
	_text = text
	_targets = targets
	_anchor = anchor
	_celebrating = false
	if _done != null:
		_done.visible = false
	visible = true
	_card.visible = true
	_dim.visible = true
	if changed:
		_fit_w = -1.0
	_layout()


func set_cat_anchor(anchor: Vector2) -> void:
	_anchor = anchor


func set_avoid(nodes: Array) -> void:
	_avoid = nodes


func set_dim(alpha: float) -> void:
	_dim_a = clampf(alpha, 0.0, 0.75)


func set_prefer_bottom(on: bool) -> void:
	_prefer_bottom = on


func show_complete(title: String, body: String, button: String) -> void:
	_celebrating = true
	_text = ""
	visible = true
	_card.visible = false
	_arrow.visible = false
	for ring in _rings:
		(ring as Panel).visible = false
	_dim.visible = true
	_done.visible = true
	_done_title.text = title
	_done_body.text = body
	_done_btn.text = button
	_fit_w = -1.0
	_layout()


func hide_tutorial() -> void:
	visible = false
	_celebrating = false
	_targets = []


func _process(delta: float) -> void:
	if not visible:
		return
	_pulse += delta
	var blink := 0.72 + 0.28 * sin(_pulse * 4.2)
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
		sb.shadow_color = Color(0.22, 0.12, 0.06, 0.22)
		sb.shadow_size = 12
		sb.shadow_offset = Vector2(0, 6)
		node.add_theme_stylebox_override("panel", sb)


func _build_done() -> void:
	_done = PanelContainer.new()
	_done.name = "Done"
	_done.visible = false
	_done.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_cream(_done)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	_done_title = Label.new()
	_done_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_body = Label.new()
	_done_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_done_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_done_btn = Button.new()
	_done_btn.focus_mode = Control.FOCUS_NONE
	_done_btn.custom_minimum_size = Vector2(0, 80)
	_style_cream(_done_btn)
	_done_btn.pressed.connect(func() -> void: hide_tutorial())
	box.add_child(_done_title)
	box.add_child(_done_body)
	box.add_child(_done_btn)
	_done.add_child(box)
	add_child(_done)


func _make_arrow() -> Node2D:
	var root := Node2D.new()
	var back := Polygon2D.new()
	back.polygon = PackedVector2Array([Vector2(-6, -6), Vector2(42, -6), Vector2(18, 40)])
	back.color = INK
	var front := Polygon2D.new()
	front.polygon = PackedVector2Array([Vector2(2, 0), Vector2(34, 0), Vector2(18, 28)])
	front.color = CREAM
	root.add_child(back)
	root.add_child(front)
	root.visible = false
	return root


func _layout() -> void:
	var rw := size
	if rw.x < 20.0 or rw.y < 20.0:
		return
	if _celebrating:
		_layout_done(rw)
		return
	var wide := minf(620.0, rw.x - 80.0)
	if absf(wide - _fit_w) > 1.0:
		_fit_w = wide
		_skip.text = SettingsData.t("tutorial_skip")
		UiFit.paint_light(_skip, 28)
		UiFit.fit_label(_skip, wide - 80.0, 1, 18, 28)
		_label.text = _text
		UiFit.paint_light(_label, 34)
		UiFit.fit_label(_label, wide - 56.0, 4, 22, 34)
		var font := _label.get_theme_font("font")
		var px := _label.get_theme_font_size("font_size")
		if font != null and px > 0:
			var measured := font.get_multiline_string_size(_text, HORIZONTAL_ALIGNMENT_CENTER, wide - 56.0, px)
			_label.custom_minimum_size = Vector2(wide - 56.0, measured.y)
		var skip_ms := _skip.get_combined_minimum_size()
		_skip.custom_minimum_size = Vector2(clampf(skip_ms.x + 28.0, 180.0, wide - 48.0), maxf(72.0, skip_ms.y + 8.0))
	var text_ms := _label.get_combined_minimum_size()
	var skip_h := maxf(72.0, _skip.custom_minimum_size.y)
	var bw := clampf(text_ms.x + 16.0, 280.0, wide)
	var bh := maxf(180.0, text_ms.y + skip_h + 28.0)
	_place_rings()
	var blocks := _blocks()
	var pos := _best_spot(bw, bh, rw, blocks)
	_card.position = pos
	_card.size = Vector2(bw, bh)
	_place_arrow()
	if _arrow.visible:
		var arrow_rect := Rect2(_arrow.position + Vector2(-8, -8), Vector2(56, 56))
		if Rect2(pos, Vector2(bw, bh)).intersects(arrow_rect):
			blocks.append(arrow_rect)
			pos = _best_spot(bw, bh, rw, blocks)
			_card.position = pos
	_paint_dim(rw)


func _layout_done(rw: Vector2) -> void:
	var wide := minf(640.0, rw.x - 80.0)
	UiFit.paint_light(_done_title, 48)
	UiFit.fit_label(_done_title, wide - 64.0, 2, 28, 48)
	UiFit.paint_light(_done_body, 32)
	UiFit.fit_label(_done_body, wide - 64.0, 3, 20, 32)
	UiFit.paint_light(_done_btn, 30)
	UiFit.fit_label(_done_btn, wide - 80.0, 1, 18, 30)
	var title_h := maxf(56.0, _done_title.get_combined_minimum_size().y)
	var body_h := maxf(48.0, _done_body.get_combined_minimum_size().y)
	_done_title.custom_minimum_size = Vector2(wide - 64.0, title_h)
	_done_body.custom_minimum_size = Vector2(wide - 64.0, body_h)
	var bh := title_h + body_h + 80.0 + 48.0
	var bw := wide
	_done.position = Vector2((rw.x - bw) * 0.5, (rw.y - bh) * 0.5)
	_done.size = Vector2(bw, bh)
	if _dim_mat != null:
		_dim_mat.set_shader_parameter("screen_px", rw)
		_dim_mat.set_shader_parameter("holes", 0)
		_dim_mat.set_shader_parameter("dim", Color(0.16, 0.09, 0.06, 0.55))


func _place_rings() -> void:
	var used := 0
	for t in _targets:
		if used >= _rings.size():
			break
		var ring: Panel = _rings[used]
		used += 1
		if t == null or not is_instance_valid(t) or not (t as CanvasItem).is_visible_in_tree():
			ring.visible = false
			continue
		var ctrl := t as Control
		if ctrl == null:
			ring.visible = false
			continue
		var gr: Rect2 = ctrl.get_global_rect()
		if gr.size.x < 8.0 or gr.size.y < 8.0:
			ring.visible = false
			continue
		var pad := 18.0
		ring.visible = true
		ring.position = gr.position - get_global_rect().position - Vector2(pad, pad)
		ring.size = gr.size + Vector2(pad * 2.0, pad * 2.0)
	for i in range(used, _rings.size()):
		(_rings[i] as Panel).visible = false


func _place_arrow() -> void:
	var ring: Panel = null
	for item in _rings:
		var panel := item as Panel
		if panel != null and panel.visible:
			ring = panel
			break
	if ring == null:
		_arrow.visible = false
		return
	_arrow.visible = true
	var bounce := sin(_pulse * 6.0) * 14.0
	var cx := ring.position.x + ring.size.x * 0.5
	var above := ring.position.y - 58.0 + bounce
	if above >= 8.0:
		_arrow.scale = Vector2(1, 1)
		_arrow.position = Vector2(cx - 18.0, above)
	else:
		_arrow.scale = Vector2(1, -1)
		_arrow.position = Vector2(cx - 18.0, ring.position.y + ring.size.y + 52.0 - bounce)


func _best_spot(bw: float, bh: float, rw: Vector2, blocks: Array) -> Vector2:
	var spots: Array[Vector2] = []
	if _prefer_bottom:
		spots = [
			Vector2((rw.x - bw) * 0.5, rw.y - bh - 36.0),
			Vector2(20.0, rw.y - bh - 36.0),
			Vector2(rw.x - bw - 20.0, rw.y - bh - 36.0),
		]
	else:
		spots = [
			_anchor + Vector2(-bw - 28.0, -bh * 0.55),
			_anchor + Vector2(40.0, -bh * 0.45),
			Vector2((rw.x - bw) * 0.5, rw.y * 0.34),
			Vector2(16.0, rw.y - bh - 36.0),
			Vector2(rw.x - bw - 16.0, 120.0),
		]
	var best := Vector2(16, 16)
	var best_area := INF
	for spot in spots:
		var p := Vector2(
			clampf(spot.x, 12.0, maxf(12.0, rw.x - bw - 12.0)),
			clampf(spot.y, 12.0, maxf(12.0, rw.y - bh - 12.0))
		)
		var area := _overlap_area(Rect2(p, Vector2(bw, bh)), blocks)
		if area < best_area:
			best_area = area
			best = p
			if area <= 0.0:
				return p
	return best


func _overlap_area(rect: Rect2, blocks: Array) -> float:
	var area := 0.0
	for block in blocks:
		var other: Rect2 = block
		if not rect.intersects(other):
			continue
		var inter := rect.intersection(other)
		area += inter.size.x * inter.size.y
	return area


func _paint_dim(rw: Vector2) -> void:
	if _dim_mat == null:
		return
	_dim_mat.set_shader_parameter("screen_px", rw)
	_dim_mat.set_shader_parameter("dim", Color(0.16, 0.09, 0.06, _dim_a))
	var holes := 0
	var packed: Array[Vector4] = []
	for item in _rings:
		var ring := item as Panel
		if ring == null or not ring.visible:
			continue
		var center := ring.position + ring.size * 0.5
		var half := ring.size * 0.5
		packed.append(Vector4(center.x, center.y, half.x, half.y))
		holes += 1
		if holes >= 2:
			break
	_dim_mat.set_shader_parameter("holes", holes)
	if holes >= 1:
		_dim_mat.set_shader_parameter("hole_a", packed[0])
	if holes >= 2:
		_dim_mat.set_shader_parameter("hole_b", packed[1])


func _blocks() -> Array:
	var out: Array = []
	for ring in _rings:
		var panel := ring as Panel
		if panel != null and panel.visible:
			out.append(Rect2(panel.position, panel.size).grow(8.0))
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
		out.append(Rect2(local, gr.size).grow(12.0))
	return out
