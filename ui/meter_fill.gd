extends Control
## Barra del carrete: zona, marcador, fuerza de la línea y aviso.

var zone_center := 0.5
var zone_half := 0.15
var marker := 0.0
var zone_alpha := 1.0
var zone_tint := Color(0.5, 0.85, 0.8, 1.0)
var blinking := false
var blink := 0.0
var line_amt := 1.0
var icon := ""
var preview := -1.0
var preview_half := -1.0

const TRACK := Rect2(48.0, 63.5, 103.4, 370.3)
const END_INSET := 50.0

var _paw: Texture2D
var _track_sb := StyleBoxFlat.new()


func _ready() -> void:
	_paw = load("res://assets/art/ui/icon_paw.png")
	_track_sb.bg_color = Color(0.4, 0.3, 0.19, 0.85)
	_track_sb.set_corner_radius_all(50)


func set_meter(zc: float, zh: float, m: float) -> void:
	set_fight(zc, zh, m, {})


func set_fight(zc: float, zh: float, m: float, extra: Dictionary) -> void:
	zone_center = zc
	zone_half = zh
	marker = m
	zone_alpha = float(extra.get("alpha", 1.0))
	blinking = str(extra.get("telegraph", "")) != ""
	blink = float(extra.get("blink", 0.0))
	line_amt = float(extra.get("line", 1.0))
	icon = str(extra.get("telegraph", ""))
	preview = float(extra.get("preview", -1.0))
	preview_half = float(extra.get("preview_half", -1.0))
	var col = extra.get("color", Color(0.5, 0.85, 0.8))
	if col is Color:
		zone_tint = col
	queue_redraw()


func _draw() -> void:
	draw_style_box(_track_sb, TRACK)
	var top := TRACK.position.y + END_INSET
	var h := TRACK.size.y - END_INSET * 2.0
	if preview >= 0.0:
		var ph := preview_half if preview_half > 0.0 else zone_half
		var py0 := top + (1.0 - (preview + ph)) * h
		var py1 := top + (1.0 - (preview - ph)) * h
		draw_rect(Rect2(TRACK.position.x + 6.0, py0, TRACK.size.x - 12.0, maxf(py1 - py0, 4.0)), Color(1, 1, 1, 0.28), false, 3.0)
	var zy0 := top + (1.0 - (zone_center + zone_half)) * h
	var zy1 := top + (1.0 - (zone_center - zone_half)) * h
	var col := Color(0.45, 0.82, 0.74, 0.95)
	if blinking:
		var k := 0.45 + 0.55 * absf(sin(blink))
		col = Color(0.45, 0.82, 0.74).lerp(zone_tint, k)
		col.a = 0.95
	col.a *= clampf(zone_alpha, 0.0, 1.0)
	var zone_rect := Rect2(TRACK.position.x, zy0, TRACK.size.x, maxf(zy1 - zy0, 4.0))
	draw_rect(zone_rect, col)
	var rim := Color("FFF1D6")
	rim.a = col.a
	draw_rect(zone_rect, rim, false, 4.0)
	_draw_line(top, h)
	var my := top + (1.0 - marker) * h
	if _paw != null:
		var pw := 64.0
		draw_texture_rect(_paw, Rect2(TRACK.position.x + (TRACK.size.x - pw) * 0.5, my - pw * 0.5, pw, pw), false)
	_draw_icon()


func _draw_line(top: float, h: float) -> void:
	var bar := Rect2(TRACK.position.x - 16.0, top, 10.0, h)
	draw_rect(bar, Color(0.28, 0.2, 0.14, 0.9))
	var fill_h := h * clampf(line_amt, 0.0, 1.0)
	var teal := Color("5CC8C2")
	var peach := Color("E7A07A")
	var pink := Color("E58AA3")
	var c := teal
	if line_amt > 0.55:
		c = peach.lerp(teal, (line_amt - 0.55) / 0.45)
	else:
		c = pink.lerp(peach, line_amt / 0.55)
	draw_rect(Rect2(bar.position.x, bar.position.y + h - fill_h, bar.size.x, fill_h), c)


func _draw_icon() -> void:
	if icon == "" or icon == "rage":
		return
	var c := TRACK.position + Vector2(TRACK.size.x * 0.5, 28.0)
	var col := zone_tint
	col.a = 0.95
	if icon == "dash":
		var pts := PackedVector2Array([c + Vector2(-16, 10), c + Vector2(0, -14), c + Vector2(16, 10)])
		draw_colored_polygon(pts, col)
	elif icon == "puff":
		draw_arc(c, 16.0, 0.0, TAU, 24, col, 4.0)
	elif icon == "ghost":
		var wave := PackedVector2Array()
		for i in 13:
			var x := c.x - 22.0 + float(i) * 3.6
			var y := c.y + sin(float(i) * 0.9 + blink) * 8.0
			wave.append(Vector2(x, y))
		draw_polyline(wave, col, 4.0)