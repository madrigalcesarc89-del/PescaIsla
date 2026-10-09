extends Camera3D
## 18a: encuadre horizontal constante en cualquier pantalla.
## Si la proporcion es mas angosta que 9:16 -> KEEP_WIDTH con el FOV
## horizontal equivalente a 36 grados verticales a 9:16
##   hfov = 2*atan(tan(18°)*9/16) = 20.72°
## (con KEEP_WIDTH, `fov` ES el FOV horizontal).
## Si es igual o mas ancha -> KEEP_HEIGHT con 36°.
## Asi el muelle mantiene su encuadre horizontal y nunca se recorta mas.
## Solo toca keep_aspect y fov; jamas el transform.

@export var base_fov := 36.0
@export var ref_aspect := 9.0 / 16.0

var _hfov := 20.72


func _ready() -> void:
	_hfov = rad_to_deg(2.0 * atan(tan(deg_to_rad(base_fov) * 0.5) * ref_aspect))
	_apply()


func _process(_delta: float) -> void:
	_apply()


func _apply() -> void:
	var vp_size := get_viewport().get_visible_rect().size
	if vp_size.y <= 0.0:
		return
	var a := vp_size.x / vp_size.y
	if a < ref_aspect - 0.0001:
		if keep_aspect != KEEP_WIDTH:
			keep_aspect = KEEP_WIDTH
		if absf(fov - _hfov) > 0.001:
			fov = _hfov
	else:
		if keep_aspect != KEEP_HEIGHT:
			keep_aspect = KEEP_HEIGHT
		if absf(fov - base_fov) > 0.001:
			fov = base_fov
