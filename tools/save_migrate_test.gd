extends SceneTree
## Migración de un guardado viejo (caught como enteros, sin álbum).
## Godot --headless --path . --script res://tools/save_migrate_test.gd

const AlbumSave = preload("res://scripts/album_save.gd")


func _init() -> void:
	print("SAVE_MIGRATE start")
	var old := {
		"coins": 42,
		"caught": {"fish_pink_sardine": 2, "fish_moon": 1},
		"pity": {"dry_rare": 4, "dry_legend": 1},
		"rod": "bamboo",
	}
	var parsed: Dictionary = AlbumSave.read(old)
	_expect(int(parsed["coins"]) == 42, "monedas")
	_expect(int(parsed["caught"]["fish_pink_sardine"]) == 2, "cantidad sardina")
	_expect(int(parsed["caught"]["fish_moon"]) == 1, "cantidad luna")
	_expect(str(parsed["first_caught"]["fish_pink_sardine"]) == "", "fecha vacía en guardado viejo")
	_expect(parsed["claimed"]["common"] == false, "premio sin reclamar")
	_expect(int(parsed["pity"]["dry_rare"]) == 4, "pity raro")
	_expect(str(parsed["rest"].get("rod", "")) == "bamboo", "clave ajena")
	_expect(bool(parsed["seen_missing"]), "guardado viejo sin album_seen")
	_expect(parsed["album_seen"].is_empty(), "visto vacío en guardado viejo")
	var hidden: Dictionary = AlbumSave.news_and_next({}, parsed["caught"], true)
	_expect((hidden["news"] as Dictionary).is_empty(), "no marcar todo como nuevo")
	var shown: Dictionary = AlbumSave.news_and_next({}, parsed["caught"], false)
	_expect(bool((shown["news"] as Dictionary).get("fish_pink_sardine", false)), "sardina nueva")
	var seen_body: Dictionary = AlbumSave.payload(parsed["coins"], parsed["caught"], parsed["first_caught"], parsed["claimed"], parsed["pity"], parsed["rest"], {"fish_pink_sardine": 2})
	_expect(int(seen_body["album_seen"]["fish_pink_sardine"]) == 2, "album_seen al escribir")
	var seen_again: Dictionary = AlbumSave.read(seen_body)
	_expect(not bool(seen_again["seen_missing"]), "album_seen presente")
	_expect(int(seen_again["album_seen"]["fish_pink_sardine"]) == 2, "album_seen al leer")
	var body: Dictionary = AlbumSave.payload(parsed["coins"], parsed["caught"], parsed["first_caught"], parsed["claimed"], parsed["pity"], parsed["rest"])
	_expect(int(body["coins"]) == 42, "monedas al escribir")
	_expect(int(body["caught"]["fish_pink_sardine"]) == 2, "espejo de cantidades")
	_expect(int(body["album"]["fish_pink_sardine"]["caught"]) == 2, "álbum cantidad")
	_expect(str(body["album"]["fish_pink_sardine"]["first_caught"]) == "", "álbum fecha")
	_expect(str(body["rod"]) == "bamboo", "clave ajena al escribir")
	var again: Dictionary = AlbumSave.read(body)
	_expect(int(again["coins"]) == 42, "segunda lectura monedas")
	_expect(int(again["caught"]["fish_moon"]) == 1, "segunda lectura luna")
	var bare: Dictionary = AlbumSave.read({})
	_expect(int(bare["coins"]) == 0, "vacío monedas")
	_expect(bare["claimed"]["legendary"] == false, "vacío premio")
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	_expect(AlbumSave.reward_amount(db, "common") == 50, "premio común")
	_expect(AlbumSave.reward_amount(db, "uncommon") == 120, "premio poco común")
	_expect(AlbumSave.reward_amount(db, "rare") == 300, "premio raro")
	_expect(AlbumSave.reward_amount(db, "legendary") == 800, "premio legendario")
	var fishes: Array = db["fishes"]
	var none := {}
	_expect(not AlbumSave.rarity_complete(fishes, none, "common"), "común incompleto")
	var all := {}
	for fish in fishes:
		all[str(fish["id"])] = 1
	_expect(AlbumSave.rarity_complete(fishes, all, "legendary"), "legendario completo")
	_expect(not AlbumSave.can_claim(fishes, none, parsed["claimed"], "common"), "nuevo no reclama común")
	var one := {"fish_lanternfish": 1}
	_expect(not AlbumSave.can_claim(fishes, one, parsed["claimed"], "rare"), "un raro no reclama")
	var only: Array = [fishes[6]]
	_expect(not AlbumSave.can_claim(only, one, parsed["claimed"], "rare"), "lista de un pez no reclama")
	var common_ids := ["fish_pink_sardine", "fish_moon", "fish_cream_carp"]
	var commons := {}
	for id in common_ids:
		commons[id] = 1
	_expect(AlbumSave.can_claim(fishes, commons, parsed["claimed"], "common"), "tres comunes sí")
	var already: Dictionary = parsed["claimed"].duplicate()
	already["common"] = true
	_expect(not AlbumSave.can_claim(fishes, commons, already, "common"), "ya cobrado no")
	_expect(AlbumSave.back_action(true, true, true, true, true) == "ignore", "la tarjeta no se cierra")
	_expect(AlbumSave.back_action(false, true, true, false, false) == "close_detail", "primero la ficha")
	_expect(AlbumSave.back_action(false, false, true, true, false) == "close_album", "luego el álbum")
	_expect(AlbumSave.back_action(false, false, false, false, false) == "quit", "sin paneles")
	var rw: Dictionary = db["rarity_weights"]
	_expect(int(rw["common"]) == 55 and int(rw["uncommon"]) == 28 and int(rw["rare"]) == 13 and int(rw["legendary"]) == 4, "pesos 55/28/13/4")
	var pity: Dictionary = db["pity"]
	_expect(int(pity["discovery_mult"]) == 2 and int(pity["rare_after"]) == 25 and int(pity["legend_after"]) == 80, "bonus y mala suerte")
	if _fail == 0:
		print("SAVE_MIGRATE_OK")
		quit(0)
	else:
		print("SAVE_MIGRATE_FAIL", _fail)
		quit(1)


var _fail := 0


func _expect(ok: bool, msg: String) -> void:
	if not ok:
		_fail += 1
		push_error("FAIL " + msg)
