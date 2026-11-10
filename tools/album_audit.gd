extends SceneTree
## Álbum: vacío, a medias, completo y ficha, en 5 proporciones y ES/EN.
## Godot --headless --path . --script res://tools/album_audit.gd
## SHOT_DIR guarda las capturas. SHOTS_ONLY=1 solo guarda 9x16 en ES.

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const CREAM := Color(1.0, 0.945, 0.839)
const SILHOUETTE := Color(0.353, 0.239, 0.169)

var _fail := 0
var _shots := 0


func _init() -> void:
	print("ALBUM_AUDIT start")
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var half := {}
	var first_half := {}
	half[str(fishes[0]["id"])] = 2
	half[str(fishes[1]["id"])] = 1
	first_half[str(fishes[0]["id"])] = "2026-11-10"
	var all := {}
	var first_all := {}
	for fish in fishes:
		all[str(fish["id"])] = 1
		first_all[str(fish["id"])] = "2026-11-10"
	var claimed := {"common": false, "uncommon": false, "rare": false, "legendary": false}
	var states := {
		"empty": [{}, {}, ""],
		"half": [half, first_half, str(fishes[0]["id"])],
		"full": [all, first_all, ""],
		"detail": [all, first_all, str(fishes[0]["id"])],
	}
	var sv := SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = ASPECTS["9x16"]
	root.add_child(sv)
	var bg := ColorRect.new()
	bg.color = Color(0.45, 0.62, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv.add_child(bg)
	var album = load("res://scenes/ui/album.tscn").instantiate()
	album.set_anchors_preset(Control.PRESET_FULL_RECT)
	album.anchor_right = 1.0
	album.anchor_bottom = 1.0
	sv.add_child(album)
	await process_frame
	var shot_dir := OS.get_environment("SHOT_DIR")
	var shots_only := OS.get_environment("SHOTS_ONLY") == "1"
	var fps := 0.0
	for aspect in ASPECTS.keys():
		sv.size = ASPECTS[aspect]
		await process_frame
		await process_frame
		for lang in ["es", "en"]:
			SettingsData.lang = lang
			for state_name in ["empty", "half", "full", "detail"]:
				var pack: Array = states[state_name]
				album.setup(fishes, pack[0], pack[1], claimed, db)
				album.open_album()
				if str(pack[2]) != "" and state_name == "detail":
					album._show_detail(str(pack[2]))
				await process_frame
				await process_frame
				_check(album, "%s %s %s" % [aspect, lang, state_name])
				if state_name == "full" and aspect == "9x16" and lang == "es":
					var t0 := Time.get_ticks_usec()
					for _i in 120:
						await process_frame
					var dt := (Time.get_ticks_usec() - t0) / 1000000.0
					fps = 120.0 / maxf(dt, 0.0001)
				var want_shot: bool = shot_dir != "" and (not shots_only or (aspect == "9x16" and lang == "es"))
				if want_shot:
					await _save_shot(sv, shot_dir, "%s_%s_%s" % [state_name, lang, aspect])
	_check_touch(album)
	print("ALBUM_PROCESS_FPS %.1f" % fps)
	if DisplayServer.get_name() == "headless":
		print("ALBUM_FPS sin ejecutar")
	elif fps < 55.0:
		_bad("FPS %.1f" % fps)
	sv.queue_free()
	if _fail == 0:
		print("ALBUM_AUDIT_OK shots", _shots)
		quit(0)
	else:
		print("ALBUM_AUDIT_FAIL", _fail)
		quit(1)


func _check(album: Control, tag: String) -> void:
	for lab in _labels(album):
		if not lab.visible or str(lab.text) == "":
			continue
		if int(lab.get_theme_constant("outline_size")) > 0:
			_bad(tag + " contorno en " + str(lab.name))
		var fg: Color = lab.get_theme_color("font_color")
		var bg := CREAM
		if str(lab.name) == "Mark":
			bg = SILHOUETTE
		if _contrast(fg, bg) < 4.5:
			_bad(tag + " contraste %.2f en %s" % [_contrast(fg, bg), lab.name])
		var host := _host(lab, album)
		var rect := host.get_global_rect().grow(4.0)
		var lr: Rect2 = lab.get_global_rect()
		if lr.size.x < 2.0 or lr.size.y < 2.0:
			continue
		if not rect.encloses(lr):
			_bad(tag + " texto fuera: " + str(lab.text).substr(0, 28))


func _host(lab: Node, album: Control) -> Control:
	var n: Node = lab
	while n != null and n != album:
		if n is Button and n.get_parent() is GridContainer:
			return n
		if str(n.name) == "Panel":
			return n
		n = n.get_parent()
	return album


func _check_touch(album: Control) -> void:
	var grid: GridContainer = album.get_node("Center/Panel/Margin/VBox/Scroll/Grid")
	for cell in grid.get_children():
		if cell.custom_minimum_size.x < 126.0 or cell.custom_minimum_size.y < 126.0:
			_bad("casilla menor de 126")
	var close: Control = album.get_node("Center/Panel/Margin/VBox/CloseBtn")
	if close.custom_minimum_size.y < 126.0 and close.size.y < 126.0:
		_bad("volver menor de 126")


func _labels(node: Node) -> Array:
	var out: Array = []
	if node is Label or node is Button:
		out.append(node)
	for child in node.get_children():
		out.append_array(_labels(child))
	return out


func _contrast(fg: Color, bg: Color) -> float:
	var lighter := maxf(_lum(fg), _lum(bg))
	var darker := minf(_lum(fg), _lum(bg))
	return (lighter + 0.05) / (darker + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _save_shot(sv: SubViewport, dir: String, id: String) -> void:
	await process_frame
	RenderingServer.force_draw()
	var img: Image = null
	var tex: ViewportTexture = sv.get_texture()
	if tex != null:
		img = tex.get_image()
	if img == null:
		var rid := sv.get_viewport_rid()
		var trid := RenderingServer.viewport_get_texture(rid)
		img = RenderingServer.texture_2d_get(trid)
	if img == null:
		print("ALBUM_SHOT sin ejecutar", id)
		return
	DirAccess.make_dir_recursive_absolute(dir)
	var err := img.save_png(dir.path_join(id + ".png"))
	if err != OK:
		_bad("no se guardó " + id)
	else:
		_shots += 1


func _bad(msg: String) -> void:
	_fail += 1
	push_error("FAIL " + msg)
