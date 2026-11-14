extends SceneTree
## Migración de un guardado viejo (caught como enteros, sin álbum).
## Godot --headless --path . --script res://tools/save_migrate_test.gd

const AlbumSave = preload("res://scripts/album_save.gd")
const FishVariants = preload("res://scripts/variants.gd")


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
	var meta: Dictionary = parsed["rest"]["fish_meta"]
	_expect((meta["fish_pink_sardine"]["variants_seen"] as Array).has("normal"), "sardina vieja ve normal")
	_expect(is_equal_approx(float(meta["fish_pink_sardine"]["best_weight"]), 0.0), "sardina sin récord")
	_expect((meta["fish_moon"]["variants_seen"] as Array).has("normal"), "luna vieja ve normal")
	_expect(not meta.has("fish_lanternfish"), "no inventa especies sin capturar")
	_expect(int(parsed["rest"]["records"]["coins_earned"]) == 42, "monedas ganadas heredan el saldo")
	_expect(str(parsed["rest"]["records"]["heaviest_id"]) == "", "sin récord global")
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
	_expect(AlbumSave.reward_amount(db, "common") == 80, "premio común")
	_expect(AlbumSave.reward_amount(db, "uncommon") == 150, "premio poco común")
	_expect(AlbumSave.reward_amount(db, "rare") == 350, "premio raro")
	_expect(AlbumSave.reward_amount(db, "epic") == 700, "premio épico")
	_expect(AlbumSave.reward_amount(db, "legendary") == 1200, "premio legendario")
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
	var common_ids := []
	for fish in fishes:
		if str(fish["rarity"]) == "common":
			common_ids.append(str(fish["id"]))
	var few := {}
	for id in common_ids.slice(0, 3):
		few[id] = 1
	_expect(not AlbumSave.can_claim(fishes, few, parsed["claimed"], "common"), "tres comunes ya no")
	var commons := {}
	for id in common_ids:
		commons[id] = 1
	_expect(AlbumSave.can_claim(fishes, commons, parsed["claimed"], "common"), "comunes completos sí")
	var already: Dictionary = parsed["claimed"].duplicate()
	already["group_common_v2"] = true
	_expect(not AlbumSave.can_claim(fishes, commons, already, "common"), "ya cobrado no")
	var old_paid: Dictionary = parsed["claimed"].duplicate()
	old_paid["common"] = true
	_expect(AlbumSave.can_claim(fishes, commons, old_paid, "common"), "la clave vieja no bloquea el premio nuevo")
	_expect(AlbumSave.extra_claim_coins(fishes, {}, old_paid, db) == 0, "la clave vieja no quita monedas")
	var dirty := {"coins": 500, "caught": {"fish_pink_sardine": 3, "fish_moon": 1}, "claimed": {"common": true}, "rod": "bamboo"}
	var fresh: Dictionary = AlbumSave.apply_fresh_run(dirty)
	_expect(int(fresh["coins"]) == 0, "reinicio monedas")
	_expect(fresh["caught"].is_empty(), "reinicio sin peces")
	_expect(fresh["claimed"]["common"] == false, "reinicio sin premios")
	_expect(int(fresh["run_epoch"]) == 2, "marca la partida nueva")
	_expect(str(fresh["rod"]) == "bamboo", "no borra la caña")
	var progressed := {
		"coins": 3499,
		"run_epoch": 1,
		"tutorial_done": true,
		"tutorial_rewarded": true,
		"daily_last": 10,
		"daily_streak": 3,
		"owned": ["rod_bamboo", "deco_chair"],
		"decor_placed": {"a": "deco_chair"},
		"caught": {"fish_moon": 1},
	}
	var wiped: Dictionary = AlbumSave.apply_fresh_run(progressed)
	_expect(int(wiped["coins"]) == 0 and wiped["caught"].is_empty(), "la partida vieja se vacía")
	_expect(not wiped.has("tutorial_done") and not wiped.has("owned") and not wiped.has("decor_placed"), "tutorial y tienda vuelven al inicio")
	_expect(not wiped.has("daily_last"), "el regalo diario vuelve a cero")
	_expect(not wiped.has("fish_meta") and not wiped.has("records"), "la partida nueva no hereda variantes")
	fresh["caught"] = {"fish_moon": 1}
	fresh["coins"] = 9
	var kept: Dictionary = AlbumSave.apply_fresh_run(fresh)
	_expect(int(kept["caught"]["fish_moon"]) == 1 and int(kept["coins"]) == 9, "no vuelve a borrar")
	_expect(AlbumSave.back_action(true, true, true, true, true) == "ignore", "la tarjeta no se cierra")
	_expect(AlbumSave.back_action(false, true, true, false, false) == "close_detail", "primero la ficha")
	_expect(AlbumSave.back_action(false, false, true, true, false) == "close_album", "luego el álbum")
	_expect(AlbumSave.back_action(false, false, false, false, false) == "quit", "sin paneles")
	var rw: Dictionary = db["rarity_weights"]
	_expect(int(rw["common"]) == 50 and int(rw["uncommon"]) == 28 and int(rw["rare"]) == 16 and int(rw["epic"]) == 14 and int(rw["legendary"]) == 7, "pesos 50/28/16/14/7")
	_expect(is_equal_approx(float(db["secret_chance"]), 0.03), "secreto al 3%")
	var pity: Dictionary = db["pity"]
	_expect(int(pity["discovery_mult"]) == 2 and int(pity["rare_after"]) == 25 and int(pity["legend_after"]) == 80, "bonus y mala suerte")
	var rich: Dictionary = body.duplicate(true)
	rich["fish_meta"] = {
		"fish_pink_sardine": {"best_weight": 1.25, "variants_seen": ["small", "golden"], "mastery_claimed": false},
		"fish_moon": {"best_weight": 0.2, "variants_seen": ["normal"], "mastery_claimed": true},
	}
	rich["records"] = {
		"heaviest_id": "fish_pink_sardine", "heaviest_kg": 1.25,
		"valuable_id": "fish_moon", "valuable_coins": 9,
		"streak": 3, "best_streak": 4, "perfect": 2, "coins_earned": 100,
	}
	var kept_meta: Dictionary = AlbumSave.read(rich)
	_expect(is_equal_approx(float(kept_meta["rest"]["fish_meta"]["fish_pink_sardine"]["best_weight"]), 1.25), "conserva el peso")
	_expect((kept_meta["rest"]["fish_meta"]["fish_pink_sardine"]["variants_seen"] as Array).has("golden"), "conserva dorado")
	_expect(bool(kept_meta["rest"]["fish_meta"]["fish_moon"]["mastery_claimed"]), "conserva la maestría")
	_expect(int(kept_meta["rest"]["records"]["perfect"]) == 2, "conserva perfectas")
	_expect(int(kept_meta["rest"]["records"]["coins_earned"]) == 100, "no pisa monedas ganadas")
	var written: Dictionary = AlbumSave.payload(kept_meta["coins"], kept_meta["caught"], kept_meta["first_caught"], kept_meta["claimed"], kept_meta["pity"], kept_meta["rest"], kept_meta["album_seen"])
	var again_meta: Dictionary = AlbumSave.read(written)
	_expect(is_equal_approx(float(again_meta["rest"]["fish_meta"]["fish_pink_sardine"]["best_weight"]), 1.25), "el peso sobrevive al guardar")
	var order: Array = FishVariants.ORDER.duplicate()
	var rest := {
		"fish_meta": {"fish_moon": {"best_weight": 0.4, "variants_seen": order, "mastery_claimed": false}},
		"records": FishVariants.empty_records(),
	}
	var path := "user://variant_migrate_test.json"
	var claimed: Dictionary = AlbumSave.empty_claimed()
	var pity0 := {"dry_rare": 0, "dry_legend": 0}
	var first_pay: Dictionary = AlbumSave.commit_mastery(path, 10, {"fish_moon": 2}, {"fish_moon": "2026-01-02"}, claimed, pity0, rest, {}, fishes, "fish_moon")
	var reward := FishVariants.mastery_reward("common")
	_expect(bool(first_pay.get("ok", false)), "reclama la maestría")
	_expect(int(first_pay.get("coins", 0)) == 10 + reward, "suma el premio una vez")
	_expect(bool(first_pay["rest"]["fish_meta"]["fish_moon"]["mastery_claimed"]), "marca cobrada")
	var second: Dictionary = AlbumSave.commit_mastery(path, int(first_pay["coins"]), {"fish_moon": 2}, {"fish_moon": "2026-01-02"}, claimed, pity0, first_pay["rest"], {}, fishes, "fish_moon")
	_expect(not bool(second.get("ok", false)), "no cobra dos veces")
	_expect(int(second.get("coins", 0)) == int(first_pay["coins"]), "el segundo intento no suma")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
