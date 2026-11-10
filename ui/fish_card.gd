extends Control
## Tarjeta del pez. Las zonas de data/ui_layout.json son fracciones
## del marco (0 a 1). El contenido va en contenedores anclados, así
## escala con la tarjeta (~70 % del ancho de pantalla, o menos si no
## cabe el botón con 24 px de aire).

signal continued

const HALO_MOD := {
	"frame_rare": Color(0.7, 0.6, 1.0, 0.55),
	"frame_legendary": Color(1.0, 0.85, 0.4, 0.6),
}
const BACKING := Color(1.0, 0.945, 0.839)

var _layout: Dictionary = {}
var _frame_key: String = "frame_common"
var _pulse: Tween = null

@onready var _dim: ColorRect = $Dim
@onready var _box: VBoxContainer = $Center/CardBox
@onready var _frame_box: Control = $Center/CardBox/FrameCenter/FrameBox
@onready var _frame_rect: TextureRect = $Center/CardBox/FrameCenter/FrameBox/FrameRect
@onready var _backing: Panel = $Center/CardBox/FrameCenter/FrameBox/Backing
@onready var _window: MarginContainer = $Center/CardBox/FrameCenter/FrameBox/Window
@onready var _fish_band: CenterContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand
@onready var _halo: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/HaloGlow
@onready var _fish: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/FishIcon
@onready var _text_block: MarginContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock
@onready var _badge_panel: PanelContainer = $Center/CardBox/FrameCenter/FrameBox/BadgePanel
@onready var _badge_label: Label = $Center/CardBox/FrameCenter/FrameBox/BadgePanel/BadgeLabel
@onready var _name_label: Label = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/NameLabel
@onready var _value_box: HBoxContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValueBox
@onready var _coin_icon: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValueBox/CoinIcon
@onready var _value_label: Label = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValueBox/ValueLabel
@onready var _fun_btn: Button = $Center/CardBox/FunButton


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	_layout = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var bs := StyleBoxFlat.new()
	bs.bg_color = BACKING
	bs.set_corner_radius_all(54)
	_backing.add_theme_stylebox_override("panel", bs)
	_box.add_theme_constant_override("separation", int(_layout.get("continue_gap", 24)))
	_box.resized.connect(func() -> void: _box.pivot_offset = _box.size * 0.5)
	_fun_btn.pressed.connect(func() -> void: continued.emit())
	_dim.gui_input.connect(_on_dim_tap)
	_paint_text(_name_label)
	_paint_text(_value_label)
	_badge_label.add_theme_font_size_override("font_size", 34)
	UiFit.paint_light(_badge_label, 34)
	_apply_metrics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready():
		_apply_metrics()


func _on_dim_tap(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		continued.emit()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		continued.emit()


func _paint_text(lab: Label) -> void:
	UiFit.paint_light(lab, 40)


func show_fish(frame_key: String, tex: Texture2D, name_text: String, badge_text: String, value_text: String) -> void:
	_frame_key = frame_key
	var fr: Dictionary = (_layout.get("frames", {}) as Dictionary).get(frame_key, {})
	if fr.is_empty():
		return
	_frame_rect.texture = load("res://assets/art/ui/" + frame_key + ".png")
	_fish.texture = tex
	_name_label.text = name_text
	_value_label.text = value_text
	_fun_btn.text = SettingsData.t("continue")
	_badge_panel.visible = badge_text != ""
	_badge_label.text = badge_text
	_coin_icon.visible = true
	var slice := frame_key.get_slice("_", 1).capitalize()
	var th := theme
	if th != null and th.has_stylebox("panel", "Badge" + slice):
		_badge_panel.add_theme_stylebox_override("panel", th.get_stylebox("panel", "Badge" + slice))
	_anchor_frac(_backing, fr.get("backing_rect", [0.1, 0.1, 0.8, 0.8]))
	_anchor_frac(_window, fr.get("window", [0.1, 0.1, 0.8, 0.8]))
	_halo.visible = HALO_MOD.has(frame_key)
	if _halo.visible:
		_halo.modulate = HALO_MOD[frame_key]
	visible = true
	_apply_metrics()
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")
	_enter_fx()
	_pulse_halo(_halo.visible)


func hide_card() -> void:
	_kill_pulse()
	visible = false


func _screen_size() -> Vector2:
	# El control ya está anclado a toda la pantalla: su size está en las
	# mismas unidades que el layout. get_viewport_rect() con stretch
	# canvas_items a veces devuelve los píxeles de la ventana y la
	# tarjeta se quedaba al tamaño nativo del marco (~36 %).
	var s := size
	if s.x < 64.0 or s.y < 64.0:
		s = get_viewport_rect().size
	if s.x < 64.0 or s.y < 64.0:
		s = Vector2(1080, 1920)
	return s


func _frame_pixel_size() -> Vector2:
	var vp := _screen_size()
	var fp: Array = _layout.get("frame_px", [425, 815])
	var aspect := float(fp[0]) / float(fp[1])
	var width_frac := float(_layout.get("card_screen_width", 0.70))
	var gap := float(_layout.get("continue_gap", 24))
	var btn_h := float((_layout.get("button", {}) as Dictionary).get("h", 150))
	var margin := 32.0
	var max_w := vp.x * width_frac
	var max_h := maxf(240.0, vp.y - btn_h - gap - margin)
	var w := max_w
	var h := w / aspect
	if h > max_h:
		h = max_h
		w = h * aspect
	return Vector2(w, h)


func _apply_metrics() -> void:
	if _layout.is_empty() or _frame_box == null:
		return
	var fz := _frame_pixel_size()
	_frame_box.custom_minimum_size = fz
	_frame_box.size = fz
	var gap := int(_layout.get("continue_gap", 24))
	_box.add_theme_constant_override("separation", gap)
	var btn: Dictionary = _layout.get("button", {})
	var btn_w := float(btn.get("w", 420))
	var btn_h := float(btn.get("h", 150))
	if btn_w > fz.x * 0.86:
		var k := (fz.x * 0.86) / btn_w
		btn_w *= k
		btn_h *= k
	_fun_btn.custom_minimum_size = Vector2(btn_w, btn_h)
	var fr: Dictionary = (_layout.get("frames", {}) as Dictionary).get(_frame_key, {})
	if fr.is_empty():
		return
	var win: Array = fr.get("window", [0.1, 0.1, 0.8, 0.8])
	var win_w := fz.x * float(win[2])
	var win_h := fz.y * float(win[3])
	var fish_of := float(_layout.get("fish_of_window", 0.60))
	var band := float(_layout.get("fish_band", 0.60))
	var side := win_w * fish_of
	side = minf(side, win_h * band * 0.96)
	_fish.custom_minimum_size = Vector2(side, side)
	_halo.custom_minimum_size = Vector2(side, side) * 1.35
	# El hueco útil del marco es más estrecho que la ventana (las ondas
	# se comen los bordes). El texto vive en el 62 % central.
	var inset := maxf(16.0, fz.x * 0.08)
	_text_block.add_theme_constant_override("margin_left", int(inset))
	_text_block.add_theme_constant_override("margin_right", int(inset))
	var safe_w := maxf(40.0, win_w - inset * 2.0)
	_window.clip_contents = true
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.custom_minimum_size = Vector2(0, 0)
	var min_px := int(_layout.get("name_min_px", 22))
	var max_lines := int(_layout.get("name_max_lines", 2))
	var start := clampi(int(safe_w * 0.12), min_px + 4, 48)
	UiFit.fit_label(_name_label, safe_w, max_lines, min_px, start)
	var value_room := maxf(40.0, safe_w - 58.0)
	_value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_value_label.clip_text = true
	UiFit.fit_label(_value_label, value_room, 1, min_px, mini(start, 40))
	_place_badge(fr, fz, safe_w)
	_paint_text(_name_label)
	_paint_text(_value_label)
	call_deferred("_refit_name", safe_w, max_lines, min_px, start)


## Segunda pasada cuando el contenedor ya tiene ancho real.
func _refit_name(safe_w: float, max_lines: int, min_px: int, start: int) -> void:
	if _name_label == null:
		return
	var w := _name_label.size.x
	# Ignora un ancho colapsado (aún sin layout): encogería la fuente al mínimo.
	if w > safe_w * 0.55:
		safe_w = minf(safe_w, w)
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.clip_text = true
	UiFit.fit_label(_name_label, safe_w, max_lines, min_px, start)
	_paint_text(_name_label)


func _place_badge(fr: Dictionary, fz: Vector2, win_w: float) -> void:
	var b: Array = fr.get("badge_rect", [0.33, 0.1, 0.33, 0.05])
	var win: Array = fr.get("window", [0.1, 0.1, 0.8, 0.8])
	var win_cx := float(win[0]) + float(win[2]) * 0.5
	var font := _badge_label.get_theme_font("font")
	var px := 34
	var tw := 120.0
	if font != null:
		tw = font.get_string_size(_badge_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x + 48.0
	var bw := clampf(tw, fz.x * float(b[2]), win_w * 0.92)
	UiFit.fit_label(_badge_label, bw - 36.0, 1, 18, px)
	var left := win_cx - (bw / fz.x) * 0.5
	var top := float(b[1])
	var bh := float(b[3])
	_badge_panel.anchor_left = left
	_badge_panel.anchor_top = top
	_badge_panel.anchor_right = left + bw / fz.x
	_badge_panel.anchor_bottom = top + bh
	_badge_panel.offset_left = 0.0
	_badge_panel.offset_top = 0.0
	_badge_panel.offset_right = 0.0
	_badge_panel.offset_bottom = 0.0


func _anchor_frac(c: Control, r: Array) -> void:
	c.anchor_left = float(r[0])
	c.anchor_top = float(r[1])
	c.anchor_right = float(r[0]) + float(r[2])
	c.anchor_bottom = float(r[1]) + float(r[3])
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func _enter_fx() -> void:
	if OS.get_environment("CARD_AUDIT") == "1":
		_box.scale = Vector2.ONE
		_dim.modulate = Color.WHITE
		return
	_box.pivot_offset = _box.size * 0.5
	_box.scale = Vector2(0.6, 0.6)
	_dim.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)


func _pulse_halo(on: bool) -> void:
	_kill_pulse()
	if not on or OS.get_environment("CARD_AUDIT") == "1":
		return
	_halo.pivot_offset = _halo.size * 0.5
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_halo, "scale", Vector2(1.15, 1.15), 0.8)
	_pulse.tween_property(_halo, "scale", Vector2.ONE, 0.8)


func _kill_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
	if _halo != null:
		_halo.scale = Vector2.ONE


## Rectángulos reales, para tools/card_audit.gd.
func measure() -> Dictionary:
	var win := _window.get_global_rect()
	var name_r := _name_label.get_global_rect()
	var value_r := _value_box.get_global_rect()
	var badge_r := _badge_panel.get_global_rect()
	var frame_r := _frame_box.get_global_rect()
	var btn_r := _fun_btn.get_global_rect()
	var fish_r := _fish.get_global_rect()
	var name_used := name_r.size.x
	var font := _name_label.get_theme_font("font")
	if font != null:
		var px := _name_label.get_theme_font_size("font_size")
		name_used = font.get_multiline_string_size(_name_label.text, HORIZONTAL_ALIGNMENT_CENTER, maxf(_name_label.size.x, 1.0), px).x
	return {
		"window": win,
		"name": name_r,
		"value": value_r,
		"badge": badge_r,
		"frame": frame_r,
		"button": btn_r,
		"fish": fish_r,
		"gap": btn_r.position.y - frame_r.end.y,
		"name_px": _name_label.get_theme_font_size("font_size"),
		"value_px": _value_label.get_theme_font_size("font_size"),
		"name_outline": _name_label.get_theme_constant("outline_size"),
		"value_outline": _value_label.get_theme_constant("outline_size"),
		"name_color": _name_label.get_theme_color("font_color"),
		"name_used_w": name_used,
		"card_width_frac": frame_r.size.x / maxf(get_viewport_rect().size.x, 1.0),
		"fish_of_window": fish_r.size.x / maxf(win.size.x, 1.0),
	}
