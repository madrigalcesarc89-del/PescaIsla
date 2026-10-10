extends Button
## 19b: boton con pulsacion (escala 0.94 con rebote) + sonido de interfaz.
## El sonido usa AudioManager si existe (llega en 19e); sin el, no falla.

var _tween: Tween


func _ready() -> void:
	pressed.connect(_on_pressed_fx)
	button_down.connect(_on_down_fx)
	button_up.connect(_on_up_fx)
	resized.connect(_on_resized_fx)
	_on_resized_fx()


func _on_resized_fx() -> void:
	pivot_offset = size * 0.5


func _on_down_fx() -> void:
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(0.94, 0.94), 0.08)


func _on_up_fx() -> void:
	_kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_pressed_fx() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx("ui_tap")


func _kill() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
