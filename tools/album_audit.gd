extends SceneTree
## Álbum anclado: 0, 6 y 12 descubiertos, un grupo reclamable,
## ES/EN y las 5 proporciones. Imprime viewport y el rect del panel.
## Godot --headless --path . --script res://tools/album_audit.gd

const AlbumSave = preload("res://scripts/album_save.gd")

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const CREAM := Color(1.0, 0.945098, 0.839216, 1)
const INK := Color(0.353, 0.239, 0.169, 1)

var _fail := 0
var _shots := 0


func _init() -> void:
	print("ALBUM_AUDIT start")
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var six := {}
	var first_six := {}
	for i in range(6):
		var id := str(fishes[i]["id"])
		six[id] = 2 if i == 4 else 1
		first_six[id] = "2026-11-10"
	var all := {}
	var first_all := {}
	for fish in fishes:
		all[str(fish["id"])] = 1
		first_all[str(fish["id"])] = "2026-11-10"
	var common_only := {}
	var first_common := {}
	for fish in fishes:
		if str(fish["rarity"]) == "common":
			common_only[str(fish["id"])] = 1
			first_common[str(fish["id"])] = "2026-11-10"
	var open_claimed := {"common": false, "uncommon": false, "rare": false, "legendary": false}
	var common_claimed := {"common": true, "uncommon": false, "rare": false, "legendary": false}
	var states := {
		"empty": [{}, {}, open_claimed],
		"six": [six, first_six, open_claimed],
		"full": [all, first_all, open_claimed],
		"claimable": [common_only, first_common, open_claimed],
		"claimed": [common_only, first_common, common_claimed],
	}
	var sv := SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = ASPECTS["9x16"]
	root.add_child(sv)
	var album = load("res://scenes/ui/album.tscn").instantiate()
	album.set_anchors_preset(Control.PRESET_FULL_RECT)
	album.anchor_right = 1.0
	album.anchor_bottom = 1.0
	sv.add_child(album)
	await process_frame
	await process_frame
	var fps := 0.0
	for aspect in ASPECTS.keys():
		sv.size = ASPECTS[aspect]
		await process_frame
		await process_frame
		for lang in ["es", "en"]:
			SettingsData.lang = lang
			for state_name in ["empty", "six", "full", "claimable", "claimed"]:
				var pack: Array = states[state_name]
				album.setup(fishes, pack[0], pack[1], pack[2], db, {}, false)
				album.open_album()
				await process_frame
				await process_frame
				var tag := "%s %s %s" % [aspect, lang, state_name]
				_check_layout(album, sv.size, tag)
				_check_state(album, state_name, lang, tag)
				if state_name == "full" and aspect == "9x16" and lang == "es":
					var t0 := Time.get_ticks_usec()
					for _i in 120:
						await process_frame
					var dt := (Time.get_ticks_usec() - t0) / 1000000.0
					fps = 120.0 / maxf(dt, 0.0001)
	await _check_behavior(album, fishes, db, six, first_six)
	print("ALBUM_PROCESS_FPS %.1f" % fps)
	if DisplayServer.get_name() == "headless":
		print("ALBUM_FPS sin ejecutar")
		print("ALBUM_SHOT sin ejecutar")
	elif fps < 55.0:
		_bad("FPS %.1f" % fps)
	sv.free()
	if _fail == 0:
		print("ALBUM_AUDIT_OK shots", _shots)
		quit(0)
	else:
		print("ALBUM_AUDIT_FAIL", _fail)
		quit(1)


func _check_layout(album: Control, vp: Vector2i, tag: String) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(vp))
	var panel: Control = album.get_node("Panel")
	var prect := panel.get_global_rect()
	print("ASPECT ", tag)
	print("  viewport ", vp, " album ", album.size)
	print("  panel ", prect, " end ", prect.position + prect.size)
	print("  panel_right_overflow ", (prect.position.x + prect.size.x) - float(vp.x))
	print("  panel anchors ", panel.anchor_left, panel.anchor_top, panel.anchor_right, panel.anchor_bottom)
	if prect.position.x < 47.0 or prect.position.y < 47.0:
		_bad(tag + " margen del panel")
	if prect.end.x > float(vp.x) - 47.0 or prect.end.y > float(vp.y) - 47.0:
		_bad(tag + " panel fuera del viewport")
	if not view.encloses(prect.grow(-1.0)):
		_bad(tag + " panel no cabe")
	var scroll: ScrollContainer = album.get_node("Panel/VBox/Scroll")
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_bad(tag + " scroll horizontal activo")
	if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		_bad(tag + " scroll vertical apagado")
	var header: Control = album.get_node("Panel/VBox/Header")
	_inside(header.get_global_rect(), view, tag + " encabezado")
	var close: Control = album.get_node("Panel/VBox/Header/CloseBtn")
	_inside(close.get_global_rect(), view, tag + " cerrar")
	if close.size.x < 132.0 or close.size.y < 132.0:
		_bad(tag + " cerrar menor de 132")
	var title: Label = album.get_node("Panel/VBox/Header/Title")
	if title.get_theme_font_size("font_size") < 64:
		_bad(tag + " título no está a 64")
	if int(title.get_theme_constant("outline_size")) != 0:
		_bad(tag + " título con contorno")
	var sections: Node = album.get_node("Panel/VBox/Scroll/Sections")
	if sections.get_child_count() != 4:
		_bad(tag + " no hay 4 secciones")
	var grids := 0
	for section in sections.get_children():
		for child in section.get_children():
			if child is GridContainer:
				grids += 1
				var grid := child as GridContainer
				if grid.columns != 3:
					_bad(tag + " la cuadrícula no tiene 3 columnas")
				if grid.get_child_count() != 3:
					_bad(tag + " una sección no tiene 3 tarjetas")
				var xs := {}
				for card in grid.get_children():
					var r: Rect2 = card.get_global_rect()
					xs[str(int(r.position.x))] = true
					if r.position.x < -1.0 or r.end.x > float(vp.x) + 1.0:
						_bad(tag + " tarjeta fuera en X " + str(card.get_meta("id", "")))
					if r.size.x > 292.0 or r.size.y > 380.0:
						_bad(tag + " tarjeta mayor de 288x372")
					if absf(r.size.y / maxf(r.size.x, 1.0) - (372.0 / 288.0)) > 0.08:
						_bad(tag + " proporción de tarjeta")
					_check_card_text(card, tag)
				if xs.size() != 3:
					_bad(tag + " las tarjetas no quedan en 3 columnas (" + str(xs.size()) + ")")
	if grids != 4:
		_bad(tag + " faltan cuadrículas")
	_check_text_contrast(album.get_node("Panel"), tag)


func _check_card_text(card: Node, tag: String) -> void:
	var name_lab := card.get_node_or_null("Name") as Label
	if name_lab != null and name_lab.visible and name_lab.text != "":
		_text_inside(name_lab, card as Control, tag)
		if name_lab.get_theme_font_size("font_size") < 26:
			_bad(tag + " nombre bajo 26: " + name_lab.text)
		if int(name_lab.get_theme_constant("outline_size")) != 0:
			_bad(tag + " nombre con contorno")
	for lab_name in ["Catches", "Badge", "Mark"]:
		var lab := card.get_node_or_null(lab_name) as Label
		if lab == null:
			continue
		_text_inside(lab, card as Control, tag)


func _check_text_contrast(node: Node, tag: String) -> void:
	if node is Label or node is Button:
		var lab: Control = node
		var text := str(lab.get("text"))
		if lab.visible and text != "":
			if int(lab.get_theme_constant("outline_size")) > 0:
				_bad(tag + " contorno en " + text.substr(0, 24))
			var fg: Color = lab.get_theme_color("font_color")
			var bg := CREAM
			if str(lab.name) == "Mark":
				bg = Color(0.45, 0.345, 0.269, 1)
			if _contrast(fg, bg) < 4.5:
				_bad(tag + " contraste %.2f en %s" % [_contrast(fg, bg), text.substr(0, 24)])
	for child in node.get_children():
		_check_text_contrast(child, tag)


func _text_inside(lab: Label, host: Control, tag: String) -> void:
	if lab.text == "" or not lab.visible:
		return
	var font := lab.get_theme_font("font")
	if font == null:
		return
	var px := lab.get_theme_font_size("font_size")
	var width := maxf(lab.size.x, 1.0)
	var measured: Vector2 = font.get_multiline_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, width, px)
	if measured.x > lab.size.x + 4.0 or measured.y > lab.size.y + 6.0:
		_bad(tag + " texto sobresale: " + lab.text.substr(0, 28))
	var bounds := host.get_global_rect().grow(2.0)
	var lr := lab.get_global_rect()
	if lr.size.x > 2.0 and not bounds.encloses(lr):
		_bad(tag + " texto fuera de la tarjeta: " + lab.text.substr(0, 28))


func _check_state(album: Control, state_name: String, lang: String, tag: String) -> void:
	var count: Label = album.get_node("Panel/VBox/Header/CountBtn/CountBox/Count")
	var expect := {"empty": "0/12", "six": "6/12", "full": "12/12", "claimable": "3/12", "claimed": "3/12"}
	if count.text != expect[state_name]:
		_bad(tag + " contador " + count.text)
	var claims := 0
	var locks := 0
	var checks := 0
	var sections: Node = album.get_node("Panel/VBox/Scroll/Sections")
	for section in sections.get_children():
		var head: Node = section.get_child(0)
		if head.find_child("Claim", true, false) != null:
			claims += 1
			var btn := head.find_child("Claim", true, false) as Button
			var word := "Reclamar +" if lang == "es" else "Claim +"
			if not str(btn.text).begins_with(word):
				_bad(tag + " botón " + str(btn.text))
		var icon := head.find_child("RewardIcon", true, false) as TextureRect
		if icon != null and icon.texture != null:
			var path := icon.texture.resource_path
			if path.ends_with("icon_lock.png"):
				locks += 1
			elif path.ends_with("icon_check.png"):
				checks += 1
	if state_name == "empty" and (claims != 0 or locks != 4):
		_bad(tag + " vacío debería tener 4 candados")
	if state_name == "claimable" and (claims != 1 or locks != 3):
		_bad(tag + " reclamable claims=%d locks=%d" % [claims, locks])
	if state_name == "claimed" and (claims != 0 or checks != 1 or locks != 3):
		_bad(tag + " cobrado checks=%d locks=%d claims=%d" % [checks, locks, claims])
	if state_name == "six" and claims != 2:
		_bad(tag + " seis descubiertos, grupos reclamables " + str(claims))
	if state_name == "full" and claims != 4:
		_bad(tag + " completo, grupos reclamables " + str(claims))
	if state_name == "six" or state_name == "full":
		var long_name := "Pez ángel durazno" if lang == "es" else "Peach angelfish"
		var found := false
		for lab in _labels(album.get_node("Panel")):
			if lab is Label and str(lab.text) == long_name:
				found = true
		if not found:
			_bad(tag + " falta el nombre largo")
	var back := album.find_child("Volver", true, false)
	if back != null:
		_bad(tag + " todavía existe Volver")


func _check_behavior(album: Control, fishes: Array, db: Dictionary, six: Dictionary, first_six: Dictionary) -> void:
	SettingsData.lang = "es"
	album.setup(fishes, six, first_six, {"common": false, "uncommon": false, "rare": false, "legendary": false}, db, {}, true)
	album.open_album()
	await process_frame
	if _count_new(album) != 0:
		_bad("guardado viejo marcó peces como nuevos")
	var seen_box := {"value": {}}
	album.seen_committed.connect(func(seen: Dictionary) -> void:
		seen_box["value"] = seen
	)
	album.setup(fishes, six, first_six, {"common": false, "uncommon": false, "rare": false, "legendary": false}, db, {}, false)
	album.open_album()
	await process_frame
	if _count_new(album) != 6:
		_bad("punto Nuevo esperado en 6, hay " + str(_count_new(album)))
	var remembered: Dictionary = seen_box["value"]
	if int(remembered.get("fish_peach_angelfish", 0)) <= 0:
		_bad("no se guardó lo visto")
	album.setup(fishes, six, first_six, {"common": false, "uncommon": false, "rare": false, "legendary": false}, db, remembered, false)
	album.open_album()
	await process_frame
	if _count_new(album) != 0:
		_bad("el punto Nuevo no se apagó al reabrir")
	album._on_card("fish_peach_angelfish")
	await process_frame
	if not album.is_detail_open():
		_bad("la ficha no abrió")
	var blurb := album.find_child("BlurbLabel", true, false) as Label
	var extra := album.find_child("ExtraLabel", true, false) as Label
	var value := album.find_child("ValueLabel", true, false) as Label
	if blurb == null or blurb.text.find("Elegante") < 0:
		_bad("la ficha no muestra la descripción")
	if value == null or value.text == "":
		_bad("la ficha no muestra el valor")
	if extra == null or extra.text.find("×") < 0 or extra.text.find("2026-11-10") < 0:
		_bad("la ficha no muestra capturas y fecha")
	if not album.consumes_back() or album.is_detail_open():
		_bad("atrás no cerró la ficha")
	if not album.visible:
		_bad("atrás cerró el álbum junto con la ficha")
	album._on_card("fish_cloud")
	await process_frame
	blurb = album.find_child("BlurbLabel", true, false) as Label
	if blurb == null or blurb.text != SettingsData.t("album_missing"):
		_bad("sin descubrir no dice que falta atraparlo")
	var name_lab := album.find_child("NameLabel", true, false) as Label
	if name_lab != null and name_lab.text != "":
		_bad("sin descubrir muestra el nombre")
	if not album.consumes_back():
		_bad("atrás no cerró la ficha vacía")
	if not album.consumes_back() or album.visible:
		_bad("el segundo atrás no cerró el álbum")
	album.setup(fishes, {}, {}, {"common": false, "uncommon": false, "rare": false, "legendary": false}, db, {}, false)
	album.open_album()
	var debug: Node = album.get_node_or_null("DebugPanel")
	if OS.is_debug_build():
		if debug == null:
			_bad("falta el panel de depuración en build debug")
		elif debug.visible:
			_bad("depuración visible sin 5 toques")
		else:
			for _i in 5:
				album._on_count_tap()
			if not debug.visible:
				_bad("5 toques no abren la depuración")
			for _i in 5:
				album._on_count_tap()
			if debug.visible:
				_bad("otros 5 toques no ocultan la depuración")
	elif debug != null:
		_bad("depuración existe fuera de debug")
	var card_open := true
	if AlbumSave.back_action(card_open, true, true, false, false) != "ignore":
		_bad("la tarjeta de captura no debe cerrarse con atrás")


func _count_new(album: Node) -> int:
	var n := 0
	for node in _all(album.get_node("Panel")):
		if str(node.name) == "NewDot":
			n += 1
	return n


func _labels(node: Node) -> Array:
	var out: Array = []
	if node is Label or node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _all(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _inside(rect: Rect2, view: Rect2, tag: String) -> void:
	if rect.size.x < 2.0:
		return
	if not view.encloses(rect.grow(-1.0)):
		_bad(tag + " fuera del viewport")


func _contrast(fg: Color, bg: Color) -> float:
	var lighter := maxf(_lum(fg), _lum(bg))
	var darker := minf(_lum(fg), _lum(bg))
	return (lighter + 0.05) / (darker + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _bad(msg: String) -> void:
	_fail += 1
	push_error("FAIL " + msg)
