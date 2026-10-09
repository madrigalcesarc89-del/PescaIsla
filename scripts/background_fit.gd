extends TextureRect
## 18b: la banda del mar pintado queda siempre bajo la linea del agua 3D.
## Cada fotograma calcula la fila del borde lejano del agua desde la camara
## (unproject_position corregido con la transformacion del viewport:
## canvas_px = ventana_px * canvas / viewport, que vale 1 sin stretch) y
## coloca el TextureRect en modo "cubrir" (escala uniforme maxima, sin
## deformar ni dejar huecos sobre la linea del agua) de forma que la fila
## de textura probada (la que coincide con el fundido lejano del agua)
## caiga justo en esa fila. Solo toca offsets en tiempo de ejecucion;
## jamas el transform de ningun nodo.

@export var water_far := Vector3(0.0, 0.1, -100.0)
@export var seam_tex_row := 1397.3
@export var camera_path := NodePath("../../Camera3D")


func _ready() -> void:
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var vp := get_viewport()
	if vp == null:
		return
	var canvas: Vector2 = vp.get_visible_rect().size
	if canvas.y <= 0.0:
		return
	var w := canvas.y * 0.11
	var cam := get_node_or_null(camera_path) as Camera3D
	if cam != null and not cam.is_position_behind(water_far):
		var vw: Vector2 = vp.size
		var k := Vector2.ONE
		if vw.x > 0.0 and vw.y > 0.0:
			k = canvas / vw
		w = cam.unproject_position(water_far).y * k.y
	var tex := texture
	if tex == null:
		return
	var ts := tex.get_size()
	if ts.x <= 0.0 or ts.y <= 0.0:
		return
	var s := maxf(canvas.x / ts.x, canvas.y / ts.y)
	var rw := ts.x * s
	var rh := ts.y * s
	offset_left = (canvas.x - rw) * 0.5
	offset_right = offset_left + rw
	offset_top = w - seam_tex_row * s
	offset_bottom = offset_top + rh
