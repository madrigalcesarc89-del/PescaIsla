extends SceneTree
## Tarjeta, ficha y récords en las 5 proporciones, ES y EN.
## Godot --headless --path . --script res://tools/variant_audit.gd
## SHOT_DIR=... guarda una selección de capturas.

const FishVariants = preload("res://scripts/variants.gd")
const AlbumSave = preload("res://scripts/album_save.gd")
const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const SPECIES := ["fish_pink_sardine", "fish_golden_koi", "fish_mini_whale"]

var _fail := 0


func _init() -> void:
	OS.set_environment("CARD_AUDIT", "1")
	print("VARIANT_AUDIT start")
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/strings.json"))
	var by_id := {}
	for fish in db["fishes"]:
		by_id[str(fish["id"])] = fish
	var sv := SubViewport.new()
	sv.transparent_bg = false
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = ASPECTS["9x16"]
	get_root().add_child(sv)
	var bg := ColorRect.new()
	bg.color = Color(0.42, 0.70, 0.76)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	sv.add_child(bg)
	var card = load("res://scenes/ui/fish_card.tscn").instantiate()
	sv.add_child(card)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	var album = load("res://scenes/ui/album.tscn").instantiate()
	sv.add_child(album)
	album.visible = false
	await process_frame
	var shot_dir := OS.get_environment("SHOT_DIR")
	for aspect in ASPECTS.keys():
		sv.size = ASPECTS[aspect]
		bg.size = Vector2(ASPECTS[aspect])
		card.size = Vector2(ASPECTS[aspect])
		album.size = Vector2(ASPECTS[aspect])
		await process_frame
		for id in SPECIES:
			var fish: Dictionary = by_id[id]
			var rarity := str(fish.get("rarity", "common"))
			var tex = load(str(fish.get("texture", "")))
			for lang in ["es", "en"]:
				SettingsData.lang = lang
				var entry = strings.get("fish", {}).get(id, {})
				var name_text := str(entry.get("name_" + lang, id))
				var title: String = SettingsData.t("catch_title") % name_text
				var badge := str(strings.get("rarities", {}).get(rarity, {}).get(lang, rarity))
				for size_id in FishVariants.SIZE_IDS:
					for color_id in FishVariants.COLOR_IDS:
						var tags: Array = []
						if size_id != "normal":
							tags.append(SettingsData.t("variant_" + size_id))
						if color_id != "normal":
							tags.append(SettingsData.t("variant_" + color_id))
						var spec := {
							"tags": " · ".join(tags),
							"weight": "120 g" if size_id == "small" else "4.2 kg",
							"record": size_id == "giant" or color_id != "normal",
							"fresh": size_id == "giant" or color_id != "normal",
							"color": color_id,
							"scale": FishVariants.scale_of(size_id),
						}
						card.show_fish("frame_" + rarity, tex, title, badge, "+48 monedas" if lang == "es" else "+48 coins", str(entry.get("description_" + lang, "")), "")
						card.show_catch_extras(spec)
						await process_frame
						_check_card(card, aspect, id, lang, size_id, color_id)
						if shot_dir != "" and _want_card_shot(aspect, id, lang, size_id, color_id):
							await _save(sv, shot_dir, "card_%s_%s_%s_%s_%s" % [aspect, lang, id, size_id, color_id])
		for lang in ["es", "en"]:
			SettingsData.lang = lang
			_show_sheet(card, by_id, "fish_sea_dragon", [], false, lang, strings)
			await process_frame
			_check_sheet(card, aspect, lang, "0")
			if shot_dir != "" and (aspect == "9x16" or lang == "es"):
				await _save(sv, shot_dir, "sheet_0_%s_%s" % [lang, aspect])
			_show_sheet(card, by_id, "fish_golden_koi", ["small", "normal", "golden"], true, lang, strings)
			await process_frame
			_check_sheet(card, aspect, lang, "3")
			if shot_dir != "" and (aspect == "9x16" or lang == "es"):
				await _save(sv, shot_dir, "sheet_3_%s_%s" % [lang, aspect])
			_show_sheet(card, by_id, "fish_mini_whale", FishVariants.ORDER.duplicate(), true, lang, strings)
			await process_frame
			_check_sheet(card, aspect, lang, "6")
			if shot_dir != "" and (aspect == "9x16" or lang == "es"):
				await _save(sv, shot_dir, "sheet_6_%s_%s" % [lang, aspect])
			_show_records(album, db, lang, aspect)
			await process_frame
			_check_records(album, aspect, lang)
			if shot_dir != "" and (aspect == "9x16" or lang == "es"):
				await _save(sv, shot_dir, "records_%s_%s" % [lang, aspect])
			album.visible = false
		print("ASPECT ", aspect)
	await _fps(db)
	if _fail == 0:
		print("VARIANT_AUDIT_OK")
		quit(0)
	else:
		print("VARIANT_AUDIT_FAIL", _fail)
		quit(1)


func _want_card_shot(aspect: String, id: String, lang: String, size_id: String, color_id: String) -> bool:
	if id == "fish_mini_whale" and size_id == "giant" and color_id == "albino" and lang == "es":
		return true
	if aspect != "9x16":
		return false
	if lang == "en" and id != "fish_golden_koi":
		return false
	if color_id == "normal" or size_id == "normal":
		return true
	return false


func _show_sheet(card, by_id: Dictionary, id: String, seen: Array, owned: bool, lang: String, strings) -> void:
	var fish: Dictionary = by_id[id]
	var rarity := str(fish.get("rarity", "common"))
	var tex = load(str(fish.get("texture", "")))
	var entry = strings.get("fish", {}).get(id, {})
	var name_text := "" if not owned else str(entry.get("name_" + lang, id))
	var badge := "" if not owned else str(strings.get("rarities", {}).get(rarity, {}).get(lang, rarity))
	card.show_fish("frame_" + rarity, tex, name_text, badge, "", SettingsData.t("album_missing") if not owned else str(entry.get("description_" + lang, "")), "")
	var lines: Array = [
		SettingsData.t("album_best") % ("—" if not owned else "1.2 kg"),
		SettingsData.t("album_times") % (0 if not owned else 4),
		SettingsData.t("album_first") % ("—" if not owned else "2026-11-01"),
	]
	if not owned:
		lines.push_front(SettingsData.t("album_missing"))
	var claim := ""
	if seen.size() >= 6:
		claim = SettingsData.t("album_mastery") % FishVariants.mastery_reward(rarity)
	card.show_sheet({
		"id": id,
		"seen": seen,
		"lines": lines,
		"claim": claim,
		"color": "golden" if seen.has("golden") else "normal",
		"scale": 1.1 if seen.has("large") or seen.has("giant") else 1.0,
		"selected": "golden" if seen.has("golden") else "",
	})


func _show_records(album, db, lang: String, _aspect: String) -> void:
	SettingsData.lang = lang
	var caught := {}
	var meta := {}
	var n := 0
	for fish in db["fishes"]:
		var id := str(fish["id"])
		caught[id] = 1
		var seen: Array = ["normal"]
		if n < 8:
			seen = FishVariants.ORDER.duplicate()
		meta[id] = {"best_weight": 1.5, "variants_seen": seen, "mastery_claimed": false}
		n += 1
	var records := {
		"heaviest_id": "fish_mini_whale",
		"heaviest_kg": 12.4,
		"valuable_id": "fish_sea_dragon",
		"valuable_coins": 480,
		"streak": 4,
		"best_streak": 9,
		"perfect": 3,
		"coins_earned": 2500,
	}
	album.setup(db["fishes"], caught, {"fish_mini_whale": "2026-11-02"}, AlbumSave.empty_claimed(), db, {}, false, meta, records)
	album.open_album()
	album._open_records()


func _check_card(card, aspect: String, id: String, lang: String, size_id: String, color_id: String) -> void:
	var m: Dictionary = card.measure()
	var win: Rect2 = m["window"]
	var fish: Rect2 = m["fish"]
	if not _inside(fish, win):
		_bad("%s %s %s %s/%s pez fuera de la ventana" % [aspect, lang, id, size_id, color_id])
	for key in ["name", "value", "tags", "weight", "ribbon", "new_variant"]:
		var rect: Rect2 = m[key]
		if rect.size.x < 2.0:
			continue
		if not _inside(rect, win):
			_bad("%s %s %s %s/%s %s fuera" % [aspect, lang, id, size_id, color_id, key])
	var icon := card.find_child("FishIcon", true, false) as Control
	if icon != null:
		if icon.anchor_left < -0.02 or icon.anchor_top < -0.02 or icon.anchor_right > 1.02 or icon.anchor_bottom > 1.02:
			_bad("%s %s escala fuera %s %s" % [aspect, lang, size_id, color_id])


func _check_sheet(card, aspect: String, lang: String, kind: String) -> void:
	var m: Dictionary = card.measure()
	var win: Rect2 = m["window"]
	var sheet: Rect2 = m["sheet"]
	if sheet.size.y > 2.0 and not _inside(sheet, win.grow(4.0)):
		_bad("%s %s ficha %s/6 fuera %s" % [aspect, lang, kind, sheet])
	var grid: Node = card.find_child("VariantGrid", true, false)
	if grid == null or grid.get_child_count() != 6:
		_bad("%s %s ficha %s/6 sin 6 etiquetas" % [aspect, lang, kind])


func _check_records(album, aspect: String, lang: String) -> void:
	var layer: Node = album.get_node_or_null("RecordsLayer")
	if layer == null or not layer.visible:
		_bad("%s %s sin panel de récords" % [aspect, lang])
		return
	var card := layer.get_node_or_null("RecordsCard") as Control
	if card == null:
		_bad("%s %s sin tarjeta de récords" % [aspect, lang])
		return
	var view: Rect2 = album.get_global_rect()
	if not view.grow(2.0).encloses(card.get_global_rect()):
		_bad("%s %s récords fuera %s" % [aspect, lang, card.get_global_rect()])
	var title := card.find_child("RecordsTitle", true, false) as Label
	if title == null or title.text == "":
		_bad("%s %s récords sin título" % [aspect, lang])
	var variants := false
	for lab in card.find_children("*", "Label", true, false):
		if str(lab.text).contains("/"):
			variants = true
	if not variants:
		_bad("%s %s récords sin variantes N/144" % [aspect, lang])


func _inside(inner: Rect2, outer: Rect2) -> bool:
	if inner.size.x < 2.0 or inner.size.y < 2.0:
		return true
	return inner.position.x >= outer.position.x - 2.0 \
		and inner.position.y >= outer.position.y - 2.0 \
		and inner.end.x <= outer.end.x + 2.0 \
		and inner.end.y <= outer.end.y + 2.0


func _save(sv: SubViewport, dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := sv.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(dir)
	img.save_png("%s/%s.png" % [dir, name])


func _fps(db) -> void:
	var sv := SubViewport.new()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	sv.size = Vector2i(1080, 1920)
	get_root().add_child(sv)
	var album = load("res://scenes/ui/album.tscn").instantiate()
	sv.add_child(album)
	var caught := {}
	var meta := {}
	for fish in db["fishes"]:
		var id := str(fish["id"])
		caught[id] = 1
		meta[id] = {"best_weight": 1.0, "variants_seen": ["normal", "golden"], "mastery_claimed": false}
	album.force_cell_color = "golden"
	album.setup(db["fishes"], caught, {}, AlbumSave.empty_claimed(), db, {}, false, meta, FishVariants.empty_records())
	album.open_album()
	for _i in 8:
		await process_frame
	var t0 := Time.get_ticks_msec()
	var frames := 40
	for _j in frames:
		await process_frame
	var dt := maxi(1, Time.get_ticks_msec() - t0)
	var fps := float(frames) * 1000.0 / float(dt)
	var adapter := ""
	if RenderingServer.has_method("get_video_adapter_name"):
		adapter = str(RenderingServer.get_video_adapter_name())
	print("FPS_ALBUM %.1f adapter %s" % [fps, adapter])


func _bad(msg: String) -> void:
	_fail += 1
	print("FAIL ", msg)
