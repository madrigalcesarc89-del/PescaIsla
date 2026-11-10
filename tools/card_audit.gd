extends SceneTree
## Paso 23b. Mide la tarjeta con los 12 nombres en ES y EN, valores de
## 1 a 4 cifras y las 5 proporciones. Falla si un texto sale de la
## ventana interior, si el aire hasta Continuar es < 24 px, si hay
## contorno o si el contraste cae de 4.5:1.
##
##   Godot --headless --path . --script res://tools/card_audit.gd
##   SHOT_DIR=... guarda 4 capturas (una por rareza).

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const VALUES := [1, 22, 333, 4444]
const SHOTS := ["fish_pink_sardine", "fish_peach_angelfish", "fish_golden_koi", "fish_sea_dragon"]

var _fail := 0


func _init() -> void:
	print("CARD_AUDIT start")
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/strings.json"))
	var fishes: Array = db.get("fishes", [])
	var sv := SubViewport.new()
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = ASPECTS["9x16"]
	get_root().add_child(sv)
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.70, 0.76)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	sv.add_child(bg)
	var card = load("res://scenes/ui/fish_card.tscn").instantiate()
	sv.add_child(card)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.anchor_right = 1.0
	card.anchor_bottom = 1.0
	await process_frame
	var shot_dir := OS.get_environment("SHOT_DIR")
	var shots_only := OS.get_environment("SHOTS_ONLY") == "1"
	var seen_aspect := {}
	for aspect in ASPECTS.keys():
		if shots_only and aspect != "9x16":
			continue
		sv.size = ASPECTS[aspect]
		bg.size = Vector2(ASPECTS[aspect])
		card.size = Vector2(ASPECTS[aspect])
		await process_frame
		await process_frame
		for f in fishes:
			var id := str(f.get("id", ""))
			if shots_only and not (id in SHOTS):
				continue
			var rarity := str(f.get("rarity", "common"))
			var tex = load(str(f.get("texture", "")))
			if not (tex is Texture2D):
				_bad("no cargó la textura de " + id)
				continue
			for lang in ["es", "en"]:
				SettingsData.lang = lang
				var entry = strings.get("fish", {}).get(id, {})
				var name_text := str(entry.get("name_" + lang, f.get("name_" + lang, id)))
				var badge := str(strings.get("rarities", {}).get(rarity, {}).get(lang, rarity))
				for value in VALUES:
					var value_text := "+%d %s" % [value, SettingsData.t("coins").to_lower()]
					var blurb := str(entry.get("description_" + lang, f.get("description_es", "")))
					card.show_fish("frame_" + rarity, tex, name_text, badge, value_text, blurb)
					await process_frame
					var measured: Dictionary = card.measure()
					if not seen_aspect.has(aspect):
						seen_aspect[aspect] = true
						print("WIDTH %s card=%.1f%% fish=%.1f%% gap=%.1f name_px=%d contrast=%.2f" % [
							aspect,
							float(measured.card_width_frac) * 100.0,
							float(measured.fish_of_window) * 100.0,
							float(measured.gap),
							int(measured.name_px),
							_contrast(measured.name_color, Color(1.0, 0.945, 0.839)),
						])
					_check(measured, aspect, id, lang, value_text)
					if shot_dir != "" and aspect == "9x16" and lang == "es" and value == 1 and id in SHOTS:
						var real := "+%d %s" % [int(f.get("value", value)), SettingsData.t("coins").to_lower()]
						card.show_fish("frame_" + rarity, tex, name_text, badge, real)
						await process_frame
						await _save_shot(sv, shot_dir, id)
	if _fail == 0:
		print("CARD_AUDIT_OK")
		quit()
	else:
		print("CARD_AUDIT_FAIL count=%d" % _fail)
		quit(1)


func _bad(msg: String) -> void:
	_fail += 1
	print("FAIL ", msg)


func _inside(inner: Rect2, outer: Rect2) -> bool:
	const EPS := 1.5
	return inner.position.x >= outer.position.x - EPS \
		and inner.position.y >= outer.position.y - EPS \
		and inner.end.x <= outer.end.x + EPS \
		and inner.end.y <= outer.end.y + EPS


func _inside_x(inner: Rect2, outer: Rect2) -> bool:
	const EPS := 1.5
	return inner.position.x >= outer.position.x - EPS and inner.end.x <= outer.end.x + EPS


func _check(m: Dictionary, aspect: String, id: String, lang: String, value_text: String) -> void:
	var win: Rect2 = m.window
	var tag := "%s %s %s %s" % [aspect, id, lang, value_text]
	if win.size.x < 10.0 or win.size.y < 10.0:
		_bad(tag + " ventana vacía")
		return
	if not _inside(m.name, win):
		_bad(tag + " nombre fuera de la ventana " + str(m.name) + " win " + str(win))
	var frame: Rect2 = m.frame
	var safe := Rect2(frame.position.x + frame.size.x * 0.145, frame.position.y, frame.size.x * 0.71, frame.size.y)
	if not _inside_x(m.name, safe):
		_bad(tag + " nombre sobre el marco " + str(m.name) + " safe " + str(safe))
	if float(m.get("name_used_w", 0.0)) > m.name.size.x + 2.0:
		_bad(tag + " el texto del nombre no cabe (%.0f > %.0f)" % [float(m.name_used_w), m.name.size.x])
	if not _inside(m.value, win):
		_bad(tag + " valor fuera de la ventana " + str(m.value))
	if not _inside(m.badge, win):
		_bad(tag + " placa fuera de la ventana " + str(m.badge))
	if int(m.name_px) < 22:
		_bad(tag + " nombre a %d px" % int(m.name_px))
	if int(m.name_outline) != 0 or int(m.value_outline) != 0:
		_bad(tag + " hay contorno")
	if float(m.gap) < 23.5:
		_bad(tag + " aire hasta Continuar = %.1f" % float(m.gap))
	var ratio := _contrast(m.name_color, Color(1.0, 0.945, 0.839))
	if ratio < 4.5:
		_bad(tag + " contraste %.2f" % ratio)
	# El pez ocupa ~60 % del ancho de la ventana (tolerancia por el alto de la banda).
	var fish_r := float(m.fish_of_window)
	if fish_r < 0.42 or fish_r > 0.96:
		_bad(tag + " pez a %.0f%% de la ventana" % (fish_r * 100.0))


func _contrast(fg: Color, bg: Color) -> float:
	var L1 := _lum(fg)
	var L2 := _lum(bg)
	var lighter := maxf(L1, L2)
	var darker := minf(L1, L2)
	return (lighter + 0.05) / (darker + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _save_shot(sv: SubViewport, dir: String, id: String) -> void:
	await process_frame
	var tex := sv.get_texture()
	if tex == null:
		_bad("sin textura de viewport")
		return
	var img := tex.get_image()
	if img == null:
		_bad("sin imagen de captura")
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir.path_join(id + ".png")
	var err := img.save_png(path)
	if err != OK:
		_bad("no se guardó " + path)
	else:
		print("SHOT", path, img.get_width(), img.get_height())
