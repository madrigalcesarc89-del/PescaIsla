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
	_box.resized.connect(func() -> void: _box.pivot_offset = _box.size * 0.5)
	_fun_btn.pressed.connect(func() -> void: continued.emit())
	_paint_text(_name_label, 48)
	_paint_text(_value_label, 40)
	_badge_label.add_theme_font_size_override("font_size", 34)
	_badge_label.add_theme_color_override("font_color", Color(0.35, 0.22, 0.1))
	_badge_label.add_theme_constant_override("outline_size", 0)


func _paint_text(lab: Label, px: int) -> void:
	# Solo tamano: el tema (crema + contorno marron + sombra) ya lee
	# bien sobre el fondo oscurecido tras la ventana del marco.
	lab.add_theme_font_size_override("font_size", px)


func show_fish(frame_key: String, tex: Texture2D, name_text: String, badge_text: String, value_text: String) -> void:
	_setup(frame_key, tex, name_text, badge_text, value_text, HALO_MOD.has(frame_key))


func show_escape(tex: Texture2D) -> void:
	_setup("frame_common", tex, "Se escapó...", "", "Sin penalización", false)
	_coin_icon.visible = false


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
	_badge_panel.visible = badge_text != ""
	_badge_label.text = badge_text
	_coin_icon.visible = true
	var th := theme
	if th != null and th.has_stylebox("panel", "Badge" + frame_key.get_slice("_", 1).capitalize()):
		_badge_panel.add_theme_stylebox_override("panel", th.get_stylebox("panel", "Badge" + frame_key.get_slice("_", 1).capitalize()))
	for key in [["badge_rect", _badge_panel], ["fish_rect", _fish], ["name_rect", _name_label], ["value_rect", _value_box]]:
		var r: Array = fr.get(key[0], [])
		(key[1] as Control).position = Vector2(float(r[0]), float(r[1])) * DS
		(key[1] as Control).size = Vector2(float(r[2]), float(r[3])) * DS
	_halo.visible = halo
	if halo:
		_halo.modulate = HALO_MOD.get(frame_key, Color.WHITE)
		_halo.position = (_fish.position + _fish.size * 0.5) - _halo.size * 0.5
	visible = true
	_enter_fx()
	_pulse_halo(halo)


func _enter_fx() -> void:
	_box.pivot_offset = _box.size * 0.5
	_box.scale = Vector2(0.6, 0.6)
	_dim.modulate = Color(1, 1, 1, 0)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_box, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_dim, "modulate:a", 1.0, 0.2)


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
