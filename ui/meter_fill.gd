extends Control
## 20f: relleno de la barra dentro de meter_frame (200x498, s=0.6757).
## La pista lleva las mismas esquinas redondeadas (radio 50); la zona y
## el marcador viven en el tramo recto (margen 50 arriba/abajo), asi no
## hace falta mascara: nunca tocan los arcos. Marcador = icon_paw.

var zone_center := 0.5
var zone_half := 0.15
var marker := 0.0

const TRACK := Rect2(48.0, 63.5, 103.4, 370.3)
const END_INSET := 50.0

var _paw: Texture2D
var _track_sb := StyleBoxFlat.new()


func _ready() -> void:
	_paw = load("res://assets/art/ui/icon_paw.png")
	_track_sb.bg_color = Color(0.4, 0.3, 0.19, 0.85)
	_track_sb.set_corner_radius_all(50)


func set_meter(zc: float, zh: float, m: float) -> void:
	zone_center = zc
	zone_half = zh
	marker = m
	queue_redraw()


func _draw() -> void:
	draw_style_box(_track_sb, TRACK)
	var top := TRACK.position.y + END_INSET
	var h := TRACK.size.y - END_INSET * 2.0
	var zy0 := top + (1.0 - (zone_center + zone_half)) * h
	var zy1 := top + (1.0 - (zone_center - zone_half)) * h
	draw_rect(Rect2(TRACK.position.x, zy0, TRACK.size.x, zy1 - zy0), Color(0.5, 0.85, 0.8, 0.95))
	var my := top + (1.0 - marker) * h
	if _paw != null:
		var pw := 64.0
		draw_texture_rect(_paw, Rect2(TRACK.position.x + (TRACK.size.x - pw) * 0.5, my - pw * 0.5, pw, pw), false)
