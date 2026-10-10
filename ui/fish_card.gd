extends Control
## 19d: modal de tarjeta del pez (marco por rareza, halo, rebote de entrada).
## Zonas medidas en data/ui_layout.json (px de textura, escala DS=0.9412).

signal continued

const DS := 0.9412
const DARKS := {
	"frame_common": "frame_common", "frame_uncommon": "frame_uncommon",
	"frame_rare": "frame_rare", "frame_legendary": "frame_legendary",
}
const HALO_MOD := {
	"frame_rare": Color(0.7, 0.6, 1.0, 0.55),
	"frame_legendary": Color(1.0, 0.85, 0.4, 0.6),
}

var _layout: Dictionary = {}
var _pulse: Tween = null

@onready var _dim: ColorRect = $Dim
@onready var _box: VBoxContainer = $Center/CardBox
@onready var _frame_rect: TextureRect = $Center/CardBox/FrameCenter/FrameBox/FrameRect
@onready var _backing: Panel = $Center/CardBox/FrameCenter/FrameBox/Backing
@onready var _halo: TextureRect = $Center/CardBox/FrameCenter/FrameBox/HaloGlow
@onready var _fish: TextureRect = $Center/CardBox/FrameCenter/FrameBox/FishIcon
@onready var _badge_panel: PanelContainer = $Center/CardBox/FrameCenter/FrameBox/BadgePanel
@onready var _badge_label: Label = $Center/CardBox/FrameCenter/FrameBox/BadgePanel/BadgeLabel
@onready var _name_label: Label = $Center/CardBox/FrameCenter/FrameBox/NameLabel
@onready var _value_box: HBoxContainer = $Center/CardBox/FrameCenter/FrameBox/ValueBox
@onready var _coin_icon: TextureRect = $Center/CardBox/FrameCenter/FrameBox/ValueBox/CoinIcon
@onready var _value_label: Label = $Center/CardBox/FrameCenter/FrameBox/ValueBox/ValueLabel
@onready var _fun_btn: Button = $Center/CardBox/FunButton


func _ready() -> void:
	_layout = JSON.parse_string(FileAccess.get_file_as_string("res://data/ui_layout.json"))
	var bs := StyleBoxFlat.new()
	bs.bg_color = Color(1.0, 0.945, 0.839)
	bs.set_corner_radius_all(54)
	_backing.add_theme_stylebox_override("panel", bs)
	_box.resized.connect(func() -> void: _box.pivot_offset = _box.size * 0.5)
	_fun_btn.pressed.connect(func() -> void: continued.emit())
	_dim.gui_input.connect(_on_dim_tap)
	_paint_text(_name_label, 48)
	_paint_text(_value_label, 40)
	_badge_label.add_theme_font_size_override("font_size", 34)
	UiFit.paint_light(_badge_label, 34)


func _on_dim_tap(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		continued.emit()
	elif event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed:
		continued.emit()


func _paint_text(lab: Label, px: int) -> void:
	UiFit.paint_light(lab, px)
	lab.add_theme_font_size_override("font_size", px)


func show_fish(frame_key: String, tex: Texture2D, name_text: String, badge_text: String, value_text: String) -> void:
	_setup(frame_key, tex, name_text, badge_text, value_text, HALO_MOD.has(frame_key))


func hide_card() -> void:
	_kill_pulse()
	visible = false


func _setup(frame_key: String, tex: Texture2D, name_text: String, badge_text: String, value_text: String, halo: bool) -> void:
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
	var th := theme
	if th != null and th.has_stylebox("panel", "Badge" + frame_key.get_slice("_", 1).capitalize()):
		_badge_panel.add_theme_stylebox_override("panel", th.get_stylebox("panel", "Badge" + frame_key.get_slice("_", 1).capitalize()))
	var w: Array = fr.get("window", [0, 0, 425, 815])
	var wx := float(w[0]) * DS
	var ww := float(w[2]) * DS
	# Relleno redondeado 6 px mayor que la ventana, detras del marco (21c).
	_backing.position = Vector2(wx - 6.0, float(fr.get("backing_rect", [0, 77, 310, 675])[1]) * DS - 6.0)
	_backing.size = Vector2(ww + 12.0, float(fr.get("backing_rect", [0, 77, 310, 675])[3]) * DS + 12.0)
	# Contenido al 84 % del ancho, centrado.
	var cw := ww * 0.84
	var cx0 := wx + (ww - cw) * 0.5
	var win_cx := wx + ww * 0.5
	for key in [["fish_rect", _fish], ["name_rect", _name_label]]:
		var r: Array = fr.get(key[0], [])
		(key[1] as Control).position = Vector2(cx0, float(r[1]) * DS)
		(key[1] as Control).size = Vector2(cw, float(r[3]) * DS)
	UiFit.fit_label(_name_label, cw, 1, 26, 48)
	_fit_value(fr, win_cx, cw)
	_grow_badge(fr, win_cx)
	_halo.visible = halo
	if halo:
		_halo.modulate = HALO_MOD.get(frame_key, Color.WHITE)
		_halo.position = (_fish.position + _fish.size * 0.5) - _halo.size * 0.5
	visible = true
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")
	_enter_fx()
	_pulse_halo(halo)


func _enter_fx() -> void:
	_box.pivot_offset = _box.size * 0.5
	_box.scale = Vector2(0.6, 0.6)
	_dim.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)


func _fit_value(fr: Dictionary, win_cx: float, cw: float) -> void:
	# Ancho real icono + texto con 12 px de margen por lado (21c).
	var vr: Array = fr.get("value_rect", [0, 682, 290, 52])
	var allowed := cw - 24.0 - 58.0
	UiFit.fit_label(_value_label, allowed, 1, 26, 40)
	var tw := _value_label.get_combined_minimum_size().x
	var bw := minf(cw, tw + 58.0 + 24.0)
	_value_box.position = Vector2(win_cx - bw * 0.5, float(vr[1]) * DS)
	_value_box.size = Vector2(bw, float(vr[3]) * DS)


func _grow_badge(fr: Dictionary, win_cx: float) -> void:
	var font := _badge_label.get_theme_font("font")
	var tw := 84.0
	if font != null:
		tw = font.get_string_size(_badge_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x + 56.0
	var bw := maxf(132.0 * DS, tw)
	_badge_panel.size = Vector2(bw, 44.0 * DS)
	_badge_panel.position = Vector2(win_cx - bw * 0.5, float(fr.get("badge_rect", [0, 80, 140, 44])[1]) * DS)
	UiFit.fit_label(_badge_label, bw - 48.0, 1, 20, 34)


func _pulse_halo(on: bool) -> void:
	_kill_pulse()
	if not on:
		return
	_halo.pivot_offset = _halo.size * 0.5
	_pulse = create_tween().set_loops()
	_pulse.tween_property(_halo, "scale", Vector2(1.15, 1.15), 0.8)
	_pulse.tween_property(_halo, "scale", Vector2.ONE, 0.8)


func _kill_pulse() -> void:
	if _pulse != null and _pulse.is_valid():
		_pulse.kill()
	_pulse = null
