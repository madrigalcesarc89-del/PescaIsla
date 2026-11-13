extends Control
## Tarjeta del pez. Las zonas de data/ui_layout.json son fracciones
## del marco (0 a 1). El contenido va en contenedores anclados, así
## escala con la tarjeta (~70 % del ancho de pantalla, o menos si no
## cabe el botón con 24 px de aire).

signal continued

const HALO_MOD := {
	"frame_common": Color(1.0, 0.82, 0.62, 0.38),
	"frame_uncommon": Color(0.55, 0.9, 0.82, 0.42),
	"frame_rare": Color(0.72, 0.62, 1.0, 0.58),
	"frame_legendary": Color(1.0, 0.84, 0.38, 0.7),
	"frame_epic": Color(0.91, 0.56, 0.72, 0.65),
	"frame_secret": Color(0.23, 0.29, 0.48, 0.75),
}
const BACKING := Color(1.0, 0.945, 0.839)
const PILL := Color(1.0, 0.945, 0.88)

var _layout: Dictionary = {}
var _frame_key: String = "frame_common"
var _art_aspect: float = 1.45
var _backing_style: StyleBoxFlat
var _extra: Label = null
var _value_center: Control = null
var _pulse: Tween = null
var _aspects: Dictionary = {}
## El pulgar sigue en Mantén (anclado abajo, ~540 px). Continuar queda
## bastante más arriba, también si hay barra de gestos.
const THUMB_CLEAR := 860.0
const ARM_SEC := 0.85
var _continue_ready := false
var _arm_token := 0
var _forcing := false

@onready var _dim: ColorRect = $Dim
@onready var _center: Control = $Center
@onready var _box: VBoxContainer = $Center/CardBox
@onready var _frame_box: Control = $Center/CardBox/FrameCenter/FrameBox
@onready var _frame_rect: TextureRect = $Center/CardBox/FrameCenter/FrameBox/FrameRect
@onready var _backing: Panel = $Center/CardBox/FrameCenter/FrameBox/Backing
@onready var _window: MarginContainer = $Center/CardBox/FrameCenter/FrameBox/Window
@onready var _stage: Control = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/FishStage
@onready var _shadow: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/FishStage/Shadow
@onready var _halo: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/FishStage/HaloGlow
@onready var _fish: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/FishBand/FishStage/FishClip/FishIcon
@onready var _text_block: MarginContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock
@onready var _badge_panel: PanelContainer = $Center/CardBox/FrameCenter/FrameBox/BadgePanel
@onready var _badge_label: Label = $Center/CardBox/FrameCenter/FrameBox/BadgePanel/BadgeLabel
@onready var _name_label: Label = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/NameLabel
@onready var _rule: ColorRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/RuleCenter/Rule
@onready var _blurb: Label = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/BlurbLabel
@onready var _value_pill: PanelContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValuePill
@onready var _value_box: HBoxContainer = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValuePill/ValueBox
@onready var _coin_icon: TextureRect = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValuePill/ValueBox/CoinIcon
@onready var _value_label: Label = $Center/CardBox/FrameCenter/FrameBox/Window/WindowVBox/TextBlock/TextVBox/ValueCenter/ValuePill/ValueBox/ValueLabel
@onready var _fun_btn: Button = $Center/CardBox/FunButton


func continue_button() -> Button:
	return _fun_btn


func _ready() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	_layout = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	var bs := StyleBoxFlat.new()
	bs.bg_color = BACKING
	bs.set_corner_radius_all(80)
	_backing_style = bs
	_backing.add_theme_stylebox_override("panel", bs)
	var mat := ShaderMaterial.new()
	mat.shader = load("res://ui/card_backing.gdshader")
	_backing.material = mat
	var pill := StyleBoxFlat.new()
	pill.bg_color = PILL
	pill.set_corner_radius_all(40)
	pill.content_margin_left = 16
	pill.content_margin_right = 22
	pill.content_margin_top = 4
	pill.content_margin_bottom = 4
	pill.border_width_left = 3
	pill.border_width_top = 3
	pill.border_width_right = 3
	pill.border_width_bottom = 3
	pill.border_color = Color(0.93, 0.78, 0.62, 0.85)
	_value_pill.add_theme_stylebox_override("panel", pill)
	_shadow.modulate = Color(0.45, 0.28, 0.16, 0.32)
	_box.add_theme_constant_override("separation", int(_layout.get("continue_gap", 24)))
	_box.resized.connect(func() -> void: _box.pivot_offset = _box.size * 0.5)
	_fun_btn.pressed.connect(_on_continue_pressed)
	_fun_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_dim.gui_input.connect(_on_dim_tap)
	_fill(self)
	_fill(_dim)
	_fill(_center)
	_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_paint_text(_name_label)
	_paint_text(_value_label)
	_badge_label.add_theme_font_size_override("font_size", 34)
	UiFit.paint_light(_badge_label, 34)
	_extra = Label.new()
	_extra.name = "ExtraLabel"
	_extra.visible = false
	_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_extra.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blurb.get_parent().add_child(_extra)
	_blurb.get_parent().move_child(_extra, _blurb.get_index() + 1)
	_value_center = _value_label.get_parent().get_parent().get_parent()
	_apply_metrics()
	call_deferred("_apply_metrics")


func _process(_delta: float) -> void:
	if _forcing or not visible or _box == null:
		return
	var vp := _viewport_canvas_size()
	var mid := _box.get_global_rect().get_center().x
	if absf(mid - vp.x * 0.5) > 8.0 or size.x < vp.x * 0.92:
		_apply_metrics()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and is_node_ready() and not _forcing:
		_apply_metrics()


func _on_dim_tap(event: InputEvent) -> void:
	var press := false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		press = true
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		press = true
	if not press:
		return
	# El fondo no cierra. Si el pulgar sigue en Mantén, no se come la ficha.
	get_viewport().set_input_as_handled()


func _on_continue_pressed() -> void:
	if not _continue_ready:
		return
	continued.emit()


## El dedo que todavía está en Mantén no cierra la tarjeta.
func _arm_continue() -> void:
	_arm_token += 1
	var token := _arm_token
	_continue_ready = false
	_fun_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fun_btn.modulate.a = 0.45
	if _center != null:
		_center.mouse_filter = Control.MOUSE_FILTER_STOP
	if OS.get_environment("CARD_AUDIT") == "1":
		_continue_ready = true
		_fun_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_fun_btn.modulate.a = 1.0
		if _center != null:
			_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return
	var tw := create_tween()
	tw.tween_interval(ARM_SEC)
	tw.tween_callback(func() -> void:
		if token != _arm_token or not visible:
			return
		_continue_ready = true
		_fun_btn.mouse_filter = Control.MOUSE_FILTER_STOP
		_fun_btn.modulate.a = 1.0
		if _center != null:
			_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	)


func _paint_text(lab: Label) -> void:
	UiFit.paint_light(lab, 40)


func show_fish(frame_key: String, tex: Texture2D, name_text: String, badge_text: String, value_text: String, blurb: String = "", extra: String = "") -> void:
	_frame_key = frame_key
	var frames: Dictionary = _layout.get("frames", {})
	var fr: Dictionary = frames.get(frame_key, {})
	if fr.is_empty():
		fr = frames.get("frame_legendary", {})
	if fr.is_empty():
		return
	var load_key := frame_key
	var tint := Color.WHITE
	if not FileAccess.file_exists("res://assets/art/ui/" + frame_key + ".png"):
		if frame_key == "frame_epic":
			load_key = "frame_legendary"
			tint = Color("E88FB8")
		elif frame_key == "frame_secret":
			load_key = "frame_legendary"
			tint = Color("3B4A7A")
	var frame_tex: Texture2D = load("res://assets/art/ui/" + load_key + ".png")
	_frame_rect.texture = frame_tex
	_frame_rect.modulate = tint
	if _backing.material is ShaderMaterial:
		(_backing.material as ShaderMaterial).set_shader_parameter("frame_tex", frame_tex)
	_fish.texture = tex
	_fish.modulate = Color.WHITE
	_art_aspect = _read_art_aspect(tex)
	_name_label.text = name_text
	_blurb.text = blurb
	_blurb.visible = blurb != ""
	_rule.visible = blurb != "" or extra != ""
	if _extra != null:
		_extra.text = extra
		_extra.visible = extra != ""
	_value_label.text = value_text
	if _value_center != null:
		_value_center.visible = value_text != ""
	_fun_btn.text = SettingsData.t("continue")
	_badge_panel.visible = badge_text != ""
	_badge_label.text = badge_text
	_coin_icon.visible = true
	var slice := frame_key.get_slice("_", 1).capitalize()
	var th := theme
	if th != null and th.has_stylebox("panel", "Badge" + slice):
		_badge_panel.add_theme_stylebox_override("panel", th.get_stylebox("panel", "Badge" + slice))
	if slice == "Secret":
		_badge_label.add_theme_color_override("font_color", Color("FFF1D6"))
	else:
		UiFit.paint_light(_badge_label, 34)
	# Cubre el marco entero. El shader borra el crema del margen transparente.
	_anchor_frac(_backing, [0.0, 0.0, 1.0, 1.0])
	_anchor_frac(_window, fr.get("window", [0.1, 0.1, 0.8, 0.8]))
	_halo.visible = frame_key == "frame_rare" or frame_key == "frame_legendary" or frame_key == "frame_epic" or frame_key == "frame_secret"
	if _halo.visible:
		_halo.modulate = HALO_MOD[frame_key]
	visible = true
	_force_screen()
	_apply_metrics()
	_arm_continue()
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")
	_enter_fx()
	_pulse_halo(_halo.visible)


func hide_card() -> void:
	_arm_token += 1
	_continue_ready = false
	if _fun_btn != null:
		_fun_btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fun_btn.modulate.a = 1.0
	_kill_pulse()
	visible = false


func _screen_size() -> Vector2:
	return _viewport_canvas_size()


func _fill(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


## Tamaño del canvas, no el ancho del propio control (si la ficha no
## se estiró, size es el del marco y todo queda pegado a la izquierda).
func _viewport_canvas_size() -> Vector2:
	var vr := get_viewport().get_visible_rect().size
	var s := size
	if s.x >= 1000.0 and s.y >= 1400.0 and vr.x > s.x * 1.15:
		return s
	if vr.x >= 64.0 and vr.y >= 64.0:
		return vr
	if s.x >= 64.0 and s.y >= 64.0:
		return s
	return Vector2(1080, 1920)


func _thumb_clear() -> float:
	var extra := 0.0
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var vp := _viewport_canvas_size()
	if win.y > 8 and vp.y > 8.0 and sa.size.y > win.y * 0.5 and sa.end.y <= win.y:
		var sy := vp.y / float(win.y)
		extra = maxf(0.0, float(win.y) - float(sa.end.y)) * sy
	return THUMB_CLEAR + extra


## Cubre el viewport aunque el padre (álbum o CanvasLayer) no estire anclajes.
func _force_screen() -> void:
	if _forcing:
		return
	_forcing = true
	var vp := _viewport_canvas_size()
	top_level = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	grow_horizontal = Control.GROW_DIRECTION_END
	grow_vertical = Control.GROW_DIRECTION_END
	if global_position.distance_to(Vector2.ZERO) > 0.5 or absf(size.x - vp.x) > 1.0 or absf(size.y - vp.y) > 1.0:
		global_position = Vector2.ZERO
		size = vp
	_cover(_dim, vp)
	_cover(_center, vp)
	if _center != null:
		_center.mouse_filter = Control.MOUSE_FILTER_STOP
	_forcing = false


func _cover(c: Control, vp: Vector2) -> void:
	if c == null:
		return
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = vp.x
	c.offset_bottom = vp.y
	c.position = Vector2.ZERO
	c.size = vp


## Centra la ficha en la franja que queda por encima de Mantén.
## Continuar sigue debajo del marco, con el aire de continue_gap.
func _place_box() -> void:
	if _box == null or _frame_box == null or _fun_btn == null:
		return
	var vp := _viewport_canvas_size()
	var fz := _frame_box.custom_minimum_size
	var btn_s := _fun_btn.custom_minimum_size
	var gap := float(_layout.get("continue_gap", 24))
	var box_w := maxf(fz.x, btn_s.x)
	var box_h := fz.y + gap + btn_s.y
	var x := (vp.x - box_w) * 0.5
	var band_top := 48.0
	var band_bot := vp.y - _thumb_clear()
	var y := band_top
	if band_bot - band_top > box_h:
		y = band_top + (band_bot - band_top - box_h) * 0.5
	_box.anchor_left = 0.0
	_box.anchor_top = 0.0
	_box.anchor_right = 0.0
	_box.anchor_bottom = 0.0
	_box.grow_horizontal = Control.GROW_DIRECTION_END
	_box.grow_vertical = Control.GROW_DIRECTION_END
	_box.custom_minimum_size = Vector2(box_w, box_h)
	_box.position = Vector2(x, y)
	_box.size = Vector2(box_w, box_h)
	_box.pivot_offset = _box.size * 0.5


func _frame_pixel_size() -> Vector2:
	var vp := _screen_size()
	var fp: Array = _layout.get("frame_px", [425, 815])
	var aspect := float(fp[0]) / float(fp[1])
	var width_frac := float(_layout.get("card_screen_width", 0.70))
	var gap := float(_layout.get("continue_gap", 24))
	var btn_h := float((_layout.get("button", {}) as Dictionary).get("h", 150))
	var top := 48.0
	var clear := _thumb_clear()
	var max_w := minf(vp.x * width_frac, vp.x - 64.0)
	# Toda la ficha, botón incluido, queda por encima de Mantén.
	var max_h := maxf(280.0, vp.y - clear - top - btn_h - gap)
	var w := max_w
	var h := w / aspect
	if h > max_h:
		h = max_h
		w = h * aspect
	return Vector2(w, h)


func _apply_metrics() -> void:
	if _layout.is_empty() or _frame_box == null:
		return
	_force_screen()
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
	if _backing_style != null:
		_backing_style.set_corner_radius_all(int(clampf(fz.x * 0.12, 28.0, 90.0)))
	var fr: Dictionary = (_layout.get("frames", {}) as Dictionary).get(_frame_key, {})
	if fr.is_empty():
		_place_box()
		return
	var win: Array = fr.get("window", [0.1, 0.1, 0.8, 0.8])
	var win_w := fz.x * float(win[2])
	var win_h := fz.y * float(win[3])
	var aspect := maxf(_art_aspect, 0.45)
	var fw := win_w * 0.84
	var fh := fw / aspect
	var max_h := win_h * 0.40
	if fh > max_h:
		fh = max_h
		fw = fh * aspect
	_stage.custom_minimum_size = Vector2(maxf(fw, 120.0), maxf(fh, 80.0))
	_fit_fish_art()
	var coin := clampf(fz.x * 0.09, 44.0, 76.0)
	_coin_icon.custom_minimum_size = Vector2(coin, coin)
	# El hueco útil del marco es más estrecho que la ventana (las ondas
	# se comen los bordes). El texto vive en el 62 % central.
	var inset := maxf(16.0, fz.x * 0.08)
	_text_block.add_theme_constant_override("margin_left", int(inset))
	_text_block.add_theme_constant_override("margin_right", int(inset))
	var safe_w := maxf(40.0, win_w - inset * 2.0)
	_window.clip_contents = false
	_name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.clip_text = true
	_name_label.custom_minimum_size = Vector2(0, 0)
	var min_px := int(_layout.get("name_min_px", 22))
	var max_lines := int(_layout.get("name_max_lines", 2))
	var start := clampi(int(safe_w * 0.11), min_px + 4, 52)
	UiFit.fit_label(_name_label, safe_w, max_lines, min_px, start)
	var name_px := _name_label.get_theme_font_size("font_size")
	_name_label.clip_text = false
	_name_label.custom_minimum_size = Vector2(safe_w, name_px + 6)
	_rule.custom_minimum_size = Vector2(maxf(72.0, safe_w * 0.34), 3.0)
	_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blurb.clip_text = false
	UiFit.fit_label(_blurb, safe_w, 2, 18, 30)
	if _extra != null and _extra.visible:
		_extra.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		UiFit.fit_label(_extra, safe_w, 3, 18, 28)
		_paint_text(_extra)
	var value_room := maxf(80.0, safe_w - coin - 36.0)
	_value_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_value_label.clip_text = false
	UiFit.fit_label(_value_label, value_room, 1, min_px, mini(start, 40))
	var value_px := _value_label.get_theme_font_size("font_size")
	_value_label.custom_minimum_size = Vector2(value_room * 0.45, value_px + 4)
	_place_badge(fr, fz, safe_w)
	_paint_text(_name_label)
	_paint_text(_value_label)
	_paint_text(_blurb)
	_blurb.add_theme_color_override("font_color", Color(0.48, 0.34, 0.26))
	var brown := Color(0.353, 0.239, 0.169)
	_fun_btn.add_theme_color_override("font_color", brown)
	_fun_btn.add_theme_color_override("font_hover_color", brown)
	_fun_btn.add_theme_color_override("font_pressed_color", brown)
	_fun_btn.add_theme_constant_override("outline_size", 0)
	_place_box()
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
	_name_label.clip_text = false
	UiFit.fit_label(_name_label, safe_w, max_lines, min_px, start)
	var name_px := _name_label.get_theme_font_size("font_size")
	_name_label.custom_minimum_size = Vector2(safe_w, name_px + 6)
	_paint_text(_name_label)


func _read_art_aspect(tex: Texture2D) -> float:
	if tex == null:
		return 1.45
	var key := tex.resource_path
	if key != "" and _aspects.has(key):
		return float(_aspects[key])
	var img: Image = tex.get_image()
	if img == null or img.is_empty():
		if key.begins_with("res://"):
			img = Image.load_from_file(ProjectSettings.globalize_path(key))
	var aspect := 1.45
	if img != null and not img.is_empty():
		var used := img.get_used_rect()
		if used.size.x >= 2 and used.size.y >= 2:
			aspect = used.size.x / float(used.size.y)
	if key != "":
		_aspects[key] = aspect
	return aspect


func _fit_fish_art() -> void:
	_fish.anchor_left = 0.0
	_fish.anchor_top = 0.0
	_fish.anchor_right = 1.0
	_fish.anchor_bottom = 1.0
	_fish.offset_left = 0.0
	_fish.offset_top = 0.0
	_fish.offset_right = 0.0
	_fish.offset_bottom = 0.0
	var tex := _fish.texture
	if tex == null:
		return
	var img := tex.get_image()
	if img == null or img.is_empty():
		return
	var used := img.get_used_rect()
	var tex_size := img.get_size()
	if used.size.x < 2 or used.size.y < 2:
		return
	var content := Vector2(used.size) / Vector2(tex_size)
	var origin := Vector2(used.position) / Vector2(tex_size)
	var fill := 0.9
	var zoom := minf(fill / content.x, fill / content.y)
	var center := origin + content * 0.5
	var pos := Vector2(0.5, 0.5) - center * zoom
	_fish.anchor_left = pos.x
	_fish.anchor_top = pos.y
	_fish.anchor_right = pos.x + zoom
	_fish.anchor_bottom = pos.y + zoom


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
	var fish_r := _stage.get_global_rect()
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
