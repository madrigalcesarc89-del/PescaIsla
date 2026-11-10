extends SceneTree
## Compra atómica y maquetación de la tienda.
## Godot --headless --path . --script res://tools/shop_audit.gd

const ShopSave = preload("res://scripts/shop_save.gd")
const AlbumSave = preload("res://scripts/album_save.gd")
const FishRoll = preload("res://scripts/fish_roll.gd")

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const CREAM := Color("FFF1D6")
const INK := Color(0.353, 0.239, 0.169, 1)
const PATH := "user://shop_audit_buy.json"

var _fail := 0


func _init() -> void:
	print("SHOP_AUDIT start")
	SettingsData.load_all()
	SettingsData.lang = "es"
	_logic()
	await _layout()
	if DisplayServer.get_name() == "headless":
		print("SHOP_FPS sin ejecutar")
		print("SHOP_SHOT sin ejecutar")
	if _fail == 0:
		print("SHOP_AUDIT_OK")
		quit(0)
		return
	print("SHOP_AUDIT_FAIL", _fail)
	quit(1)


func _logic() -> void:
	var coral := ShopSave.item_by_id("rod_coral")
	_expect(ShopSave.effect_line(coral) == "Espera −15 %", "efecto coral " + ShopSave.effect_line(coral))
	SettingsData.lang = "en"
	_expect(ShopSave.effect_line(coral) == "Wait −15 %", "efecto coral en")
	SettingsData.lang = "es"
	_expect(ShopSave.effect_line(ShopSave.item_by_id("rod_bamboo")) == "Equipo inicial", "bambú inicial")
	var st := ShopSave.fresh_state()
	_expect(str(st["equipped_rod"]) == "rod_bamboo" and str(st["equipped_bait"]) == "bait_pink_worm", "equipo inicial")
	var owned0: Array = st["owned"]
	_expect(owned0.has("rod_bamboo") and owned0.has("bait_pink_worm"), "de serie")
	var rich := {
		"coins": 80,
		"caught": {"fish_moon": 2},
		"rod": "bamboo",
		"run_epoch": 1,
		"claimed": {"common": true},
	}
	var parsed: Dictionary = AlbumSave.read(rich)
	var kept := ShopSave.normalize(parsed["rest"])
	_expect(str(kept["equipped_rod"]) == "rod_bamboo", "guardado viejo equipa bambú")
	var body: Dictionary = AlbumSave.payload(int(parsed["coins"]), parsed["caught"], parsed["first_caught"], parsed["claimed"], parsed["pity"], parsed["rest"], {})
	ShopSave.write_into(body, kept)
	_expect(int(body["coins"]) == 80, "no pierde monedas")
	_expect(int(body["caught"]["fish_moon"]) == 2, "no pierde peces")
	_expect(str(body["rod"]) == "bamboo", "no borra la clave vieja")
	_expect(int(body["run_epoch"]) == 1, "conserva la partida")
	var broke := body.duplicate(true)
	broke["coins"] = 0
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var denied: Dictionary = ShopSave.buy(PATH, broke, "rod_coral")
	_expect(not bool(denied["ok"]), "sin monedas no compra")
	_expect(int(broke["coins"]) == 0, "el cuerpo original no cambia")
	_expect(not FileAccess.file_exists(PATH), "sin monedas no escribe")
	var price := int(coral.get("price", 0))
	var pay := body.duplicate(true)
	pay["coins"] = 5000
	var once: Dictionary = ShopSave.buy(PATH, pay, "rod_coral")
	_expect(bool(once["ok"]), "primera compra")
	_expect(int(once["coins"]) == 5000 - price, "descuenta una vez")
	var twice: Dictionary = ShopSave.buy(PATH, pay, "rod_coral")
	_expect(not bool(twice["ok"]), "la segunda no cobra")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	_expect(typeof(disk) == TYPE_DICTIONARY, "reabre el archivo")
	var again: Dictionary = disk
	_expect(int(again["coins"]) == 5000 - price, "al reabrir el precio es uno")
	var owned: Array = again["owned"]
	var copies := 0
	for entry in owned:
		if str(entry) == "rod_coral":
			copies += 1
	_expect(copies == 1, "no duplica la caña")
	var third: Dictionary = ShopSave.buy(PATH, again, "rod_coral")
	_expect(not bool(third["ok"]), "reabierta no vuelve a comprar")
	var bad: Dictionary = ShopSave.buy("user://no_such_shop_dir/nested/save.json", pay, "rod_cherry")
	_expect(not bool(bad["ok"]), "si el disco falla no compra")
	_expect(int(pay["coins"]) == 5000, "el fallo no resta en memoria")
	var gear_state := ShopSave.fresh_state()
	(gear_state["owned"] as Array).append("rod_coral")
	gear_state["equipped_rod"] = "rod_coral"
	var g: Dictionary = ShopSave.gear(gear_state)
	_expect(absf(float(g["wait_mult"]) - 0.85) < 0.001, "espera de coral")
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var plain := _bucket(FishRoll.effective(fishes, {}, 0, 0, db), "legendary")
	var boosted := _bucket(FishRoll.effective(fishes, {}, 0, 0, db, {"weight_mult": {"legendary": 2.0}}), "legendary")
	_expect(absf(boosted / maxf(plain, 0.001) - 2.0) < 0.05, "peso sobre el sorteo")
	var pity := _bucket(FishRoll.effective(fishes, {}, 0, 80, db, {"weight_mult": {"legendary": 2.0}}), "legendary")
	_expect(absf(pity / maxf(plain, 0.001) - 6.0) < 0.2, "peso sobre la mala suerte")
	var ids := {}
	for entry in FishRoll.effective(fishes, {}, 0, 0, db, g):
		ids[str(entry["fish"]["id"])] = true
	_expect(ids.size() == 12, "el peso no saca peces")
	var bait := ShopSave.fresh_state()
	(bait["owned"] as Array).append("bait_peach_shrimp")
	bait["equipped_bait"] = "bait_peach_shrimp"
	(bait["bait_qty"] as Dictionary)["bait_peach_shrimp"] = 1
	var spent: Dictionary = ShopSave.spend(bait)
	var next: Dictionary = spent["state"]
	_expect(bool(spent["fallback"]), "el último cebo avisa")
	_expect(str(next["equipped_bait"]) == "bait_pink_worm", "vuelve a la lombriz")
	var placed := ShopSave.place(ShopSave.fresh_state(), "deco_plant")
	_expect(not (placed["decor_placed"] as Dictionary).has("deco_plant"), "no coloca sin comprar")
	var buyer: Dictionary = body.duplicate(true)
	buyer["coins"] = 5000
	var deco_path := "user://shop_audit_deco.json"
	if FileAccess.file_exists(deco_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(deco_path))
	var got: Dictionary = ShopSave.buy(deco_path, buyer, "deco_plant")
	_expect(bool(got["ok"]), "compra la planta")
	var put := ShopSave.place(got["state"], "deco_plant")
	_expect(str((put["decor_placed"] as Dictionary).get("deco_plant", "")) == "shore", "guarda el hueco")
	_expect(AlbumSave.back_action(false, false, false, false, false, true, true) == "close_shop_confirm", "atrás cierra la confirmación")
	_expect(AlbumSave.back_action(false, false, false, false, false, false, true) == "close_shop", "luego la tienda")
	_expect(AlbumSave.back_action(true, false, false, false, false, true, true) == "ignore", "la tarjeta sigue ignorada")


func _bucket(entries: Array, rarity: String) -> float:
	var sum := 0.0
	for entry in entries:
		if str(entry["fish"]["rarity"]) == rarity:
			sum += float(entry["w"])
	return sum


func _layout() -> void:
	var sv := SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = ASPECTS["9x16"]
	root.add_child(sv)
	var shop = load("res://scenes/ui/shop.tscn").instantiate()
	shop.set_anchors_preset(Control.PRESET_FULL_RECT)
	shop.anchor_right = 1.0
	shop.anchor_bottom = 1.0
	sv.add_child(shop)
	await process_frame
	await process_frame
	var hits := {"n": 0}
	shop.purchase_requested.connect(func(_id: String) -> void: hits.n += 1)
	var state := ShopSave.fresh_state()
	for aspect in ASPECTS.keys():
		sv.size = ASPECTS[aspect]
		await process_frame
		for lang in ["es", "en"]:
			SettingsData.lang = lang
			for cat in ["rod", "bait", "decor"]:
				shop.open_shop(30, state)
				var tab := shop.get_node("Panel/VBox/Tabs/Tab_" + cat) as Button
				tab.pressed.emit()
				await process_frame
				await process_frame
				var tag := "%s %s %s" % [aspect, lang, cat]
				_check_layout(shop, sv.size, tag, cat)
	shop.open_shop(30, state)
	var bait_tab := shop.get_node("Panel/VBox/Tabs/Tab_bait") as Button
	bait_tab.pressed.emit()
	await process_frame
	var shrimp := shop.get_node("Panel/VBox/Scroll/List/bait_peach_shrimp/Row/Actions/Buy") as Button
	shrimp.pressed.emit()
	shrimp.pressed.emit()
	_expect(hits.n == 1, "doble toque cobra una")
	await create_timer(0.5).timeout
	shrimp = shop.get_node_or_null("Panel/VBox/Scroll/List/bait_peach_shrimp/Row/Actions/Buy") as Button
	if shrimp != null:
		shrimp.pressed.emit()
	_expect(hits.n == 2, "tras 0,4 s se puede comprar otra vez")
	await create_timer(0.5).timeout
	shop.open_shop(5000, state)
	var rod_tab := shop.get_node_or_null("Panel/VBox/Tabs/Tab_rod") as Button
	_expect(rod_tab != null, "hay pestaña de cañas")
	if rod_tab != null:
		rod_tab.pressed.emit()
	await process_frame
	await process_frame
	var moon := shop.get_node_or_null("Panel/VBox/Scroll/List/rod_moon/Row/Actions/Buy") as Button
	_expect(moon != null, "hay botón de la luna")
	if moon != null:
		moon.pressed.emit()
	_expect(shop.is_confirm_open(), "confirma desde 500")
	_walk(shop.get_node("Confirm"), Rect2(Vector2.ZERO, Vector2(sv.size)), "confirm")
	_expect(shop.consumes_back(), "atrás de la confirmación")
	_expect(not shop.is_confirm_open() and shop.visible, "la tienda sigue")
	_expect(shop.consumes_back() and not shop.visible, "el segundo atrás cierra la tienda")
	var t0 := Time.get_ticks_usec()
	for _i in 60:
		await process_frame
	var fps := 60.0 / maxf((Time.get_ticks_usec() - t0) / 1000000.0, 0.0001)
	print("SHOP_PROCESS_FPS %.1f" % fps)
	sv.free()


func _check_layout(shop: Control, vp: Vector2i, tag: String, cat: String) -> void:
	var view := Rect2(Vector2.ZERO, Vector2(vp))
	var panel: Control = shop.get_node("Panel")
	var prect := panel.get_global_rect()
	var panel_l := prect.position.x
	var panel_r := float(vp.x) - prect.end.x
	print("ASPECT ", tag, " margin L ", panel_l, " R ", panel_r)
	if absf(panel_l - panel_r) > 1.0:
		_bad(tag + " margen L %.1f R %.1f" % [panel_l, panel_r])
	if prect.position.y + 1.0 < 48.0 or prect.position.x + 1.0 < 48.0:
		_bad(tag + " margen mínimo")
	if not view.encloses(prect.grow(-1.0)):
		_bad(tag + " panel fuera")
	var scroll: ScrollContainer = shop.get_node("Panel/VBox/Scroll")
	if scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_bad(tag + " scroll horizontal")
	if scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
		_bad(tag + " scroll vertical apagado")
	var bar := scroll.get_v_scroll_bar()
	if bar.visible and bar.size.x > 1.0:
		_bad(tag + " la barra reserva ancho")
	var title: Label = shop.get_node("Panel/VBox/Header/Title")
	var want := "Tienda" if tag.find(" es ") >= 0 else "Shop"
	if title.text != want:
		_bad(tag + " título " + title.text)
	if int(title.get_theme_constant("outline_size")) != 0:
		_bad(tag + " título con contorno")
	var close: Control = shop.get_node("Panel/VBox/Header/CloseBtn")
	if close.size.x < 126.0 or close.size.y < 126.0:
		_bad(tag + " cerrar pequeño")
	var list: Node = shop.get_node("Panel/VBox/Scroll/List")
	var expect := {"rod": 5, "bait": 4, "decor": 3}
	if list.get_child_count() != int(expect[cat]):
		_bad(tag + " tarjetas " + str(list.get_child_count()))
	var header: Control = shop.get_node("Panel/VBox/Header")
	if list.get_child_count() > 0:
		var card := list.get_child(0) as Control
		if absf(card.get_global_rect().position.x - header.get_global_rect().position.x) > 2.0:
			_bad(tag + " la tarjeta no alinea con el encabezado")
	_walk(shop, view, tag)
	if cat == "rod":
		var lab := shop.find_child("rod_coral", true, false)
		if lab != null:
			var p := lab.find_child("Price", true, false) as Label
			if p != null and _contrast(p.get_theme_color("font_color"), CREAM) < 4.5:
				_bad(tag + " precio sin contraste")
			if p != null:
				var pr := p.get_theme_color("font_color").r
				if pr < 0.39 or pr > 0.48:
					_bad(tag + " el precio caro no está apagado")


func _walk(node: Node, view: Rect2, tag: String) -> void:
	if node is Control:
		var c := node as Control
		if c.is_visible_in_tree() and c.size.x > 2.0 and c.size.y > 2.0:
			var rect := c.get_global_rect()
			if rect.size.x > 2.0 and not view.encloses(rect.grow(-1.0)):
				if not (node is ScrollBar):
					_bad(tag + " fuera " + str(node.name))
			if node is Button and (c.size.x < 126.0 or c.size.y < 126.0):
				_bad(tag + " toque " + str(node.name) + " " + str(c.size))
	if node is Label or node is Button:
		var lab := node as Control
		var text := str(lab.get("text"))
		if lab.is_visible_in_tree() and text != "":
			if int(lab.get_theme_constant("outline_size")) > 0:
				_bad(tag + " contorno " + text.substr(0, 24))
			var fg: Color = lab.get_theme_color("font_color")
			var bg := CREAM
			if node is Button:
				var sb := (node as Button).get_theme_stylebox("normal")
				if sb is StyleBoxFlat:
					bg = (sb as StyleBoxFlat).bg_color
			if _contrast(fg, bg) < 4.5:
				_bad(tag + " contraste %.2f %s" % [_contrast(fg, bg), text.substr(0, 24)])
	for child in node.get_children():
		_walk(child, view, tag)


func _contrast(fg: Color, bg: Color) -> float:
	var lighter := maxf(_lum(fg), _lum(bg))
	var darker := minf(_lum(fg), _lum(bg))
	return (lighter + 0.05) / (darker + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_bad(msg)


func _bad(msg: String) -> void:
	_fail += 1
	push_error("FAIL " + msg)
