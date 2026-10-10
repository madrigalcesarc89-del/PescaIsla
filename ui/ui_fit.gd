class_name UiFit
extends RefCounted
## 20d: encoge la fuente hasta que el texto quepa (ancho y lineas).
## Mide con la fuente (sin depender del layout); ajuste de linea
## activado y recorte solo como ultimo recurso.

static func fit_label(lab: Control, max_width: float, max_lines: int, min_size: int, start_px := 40) -> void:
	if lab == null or max_width <= 0.0:
		return
	if lab is Label:
		# Una sola linea: sin ajuste (el minimo es el texto entero y los
		# contenedores no colapsan). Varias: ajuste por palabras.
		(lab as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if max_lines > 1 else TextServer.AUTOWRAP_OFF
	elif lab is Button:
		(lab as Button).text_overrun_behavior = TextServer.OVERRUN_TRIM_CHAR
	var px := start_px
	var font := lab.get_theme_font("font")
	if font == null:
		return
	while px > min_size:
		lab.add_theme_font_size_override("font_size", px)
		if _fits(font, str(lab.get("text")), max_width, maxi(max_lines, 1), px):
			break
		px -= 2


static func _fits(font: Font, text: String, max_width: float, max_lines: int, px: int) -> bool:
	if max_lines <= 1:
		return font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_width
	var words := text.split(" ", false)
	var lines := 1
	var cur := ""
	for w in words:
		var trial := w if cur == "" else cur + " " + w
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= max_width:
			cur = trial
		else:
			if cur != "" and font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x > max_width:
				return false
			lines += 1
			cur = w
			if lines > max_lines:
				return false
	return lines <= max_lines
