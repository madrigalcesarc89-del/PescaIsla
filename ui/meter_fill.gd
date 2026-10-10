extends Control
## 19c: relleno de la barra de tension dentro de meter_frame (200x498).
## Coordenadas del hueco interior reescaladas uniformemente (s=0.6757).

var zone_center := 0.5
var zone_half := 0.15
var marker := 0.0

const TRACK := Rect2(48.0, 63.5, 103.4, 370.3)


func set_meter(zc: float, zh: float, m: float) -> void:
	zone_center = zc
	zone_half = zh
	marker = m
	queue_redraw()


func _draw() -> void:
	draw_rect(TRACK, Color(0.1, 0.1, 0.12, 0.85))
	var zy0 := TRACK.position.y + (1.0 - (zone_center + zone_half)) * TRACK.size.y
	var zy1 := TRACK.position.y + (1.0 - (zone_center - zone_half)) * TRACK.size.y
	draw_rect(Rect2(TRACK.position.x, zy0, TRACK.size.x, zy1 - zy0), Color(0.25, 0.8, 0.35, 0.9))
	var my := TRACK.position.y + (1.0 - marker) * TRACK.size.y
	draw_rect(Rect2(TRACK.position.x - 6.0, my - 5.0, TRACK.size.x + 12.0, 10.0), Color.WHITE)
