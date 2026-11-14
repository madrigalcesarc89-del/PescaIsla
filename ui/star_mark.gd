extends Control
## Estrella de maestría. No hay icono de trofeo: se dibuja aquí.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var c := size * 0.5
	var radius := minf(size.x, size.y) * 0.46
	if radius < 1.0:
		return
	var inner := radius * 0.4
	var pts := PackedVector2Array()
	for i in 10:
		var ang := -PI * 0.5 + float(i) * PI / 5.0
		var reach := radius if i % 2 == 0 else inner
		pts.append(c + Vector2(cos(ang), sin(ang)) * reach)
	draw_colored_polygon(pts, Color("E8C14A"))
