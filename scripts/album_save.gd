extends RefCounted
## Guardado del álbum. Los JSON viejos solo traen caught como enteros:
## se rellenan first_caught y claimed sin perder monedas ni otras claves.

const RARITIES := ["common", "uncommon", "rare", "epic", "legendary", "secret"]
const REWARD_RARITIES := ["common", "uncommon", "rare", "epic", "legendary"]
const LEGACY_KEYS := ["common", "uncommon", "rare", "legendary"]
const GROUP_KEY := {
	"common": "group_common_v2",
	"uncommon": "group_uncommon_v2",
	"rare": "group_rare_v2",
	"epic": "group_epic_v2",
	"legendary": "group_legendary_v2",
}
const DEFAULT_REWARDS := {"common": 80, "uncommon": 150, "rare": 350, "epic": 700, "legendary": 1200}
const RUN_EPOCH := 1


static func claim_key(rarity: String) -> String:
	return str(GROUP_KEY.get(rarity, ""))


static func empty_claimed() -> Dictionary:
	var out := {}
	for key in LEGACY_KEYS:
		out[key] = false
	for rarity in REWARD_RARITIES:
		out[claim_key(rarity)] = false
	return out


## Lee un guardado viejo o nuevo y devuelve el modelo interno.
static func read(data: Dictionary) -> Dictionary:
	var caught := {}
	var first := {}
	var album = data.get("album", {})
	if typeof(album) == TYPE_DICTIONARY:
		for k in album.keys():
			_take(caught, first, str(k), album[k])
	var legacy = data.get("caught", {})
	if typeof(legacy) == TYPE_DICTIONARY:
		for k in legacy.keys():
			var id := str(k)
			if caught.has(id):
				var raw = legacy[k]
				if typeof(raw) == TYPE_DICTIONARY and str(first.get(id, "")) == "":
					var date := str(raw.get("first_caught", ""))
					if date != "":
						first[id] = date
				continue
			_take(caught, first, id, legacy[k])
	for id in caught.keys():
		if not first.has(id):
			first[id] = ""
	var claimed := empty_claimed()
	var src = data.get("claimed", {})
	if typeof(src) == TYPE_DICTIONARY:
		for key in claimed.keys():
			claimed[key] = bool(src.get(key, false))
	var pity_in = data.get("pity", {})
	var pity := {"dry_rare": 0, "dry_legend": 0}
	if typeof(pity_in) == TYPE_DICTIONARY:
		pity["dry_rare"] = maxi(0, int(pity_in.get("dry_rare", 0)))
		pity["dry_legend"] = maxi(0, int(pity_in.get("dry_legend", 0)))
	var rest := data.duplicate(true)
	for key in ["coins", "caught", "album", "claimed", "pity", "album_seen"]:
		rest.erase(key)
	var seen := {}
	var seen_src = data.get("album_seen", {})
	if typeof(seen_src) == TYPE_DICTIONARY:
		for k in seen_src.keys():
			seen[str(k)] = maxi(0, int(seen_src[k]))
	return {
		"coins": int(data.get("coins", 0)),
		"caught": caught,
		"first_caught": first,
		"claimed": claimed,
		"pity": pity,
		"rest": rest,
		"album_seen": seen,
		"seen_missing": not data.has("album_seen"),
	}


static func _take(caught: Dictionary, first: Dictionary, id: String, raw) -> void:
	if typeof(raw) == TYPE_DICTIONARY:
		caught[id] = maxi(0, int(raw.get("caught", 0)))
		first[id] = str(raw.get("first_caught", ""))
	else:
		caught[id] = maxi(0, int(raw))
		first[id] = ""


## Fecha solo en la primera captura. Las antiguas se quedan en blanco.
static func stamp_first(first: Dictionary, id: String, count_before: int) -> void:
	if count_before > 0:
		return
	if str(first.get(id, "")) != "":
		return
	first[id] = Time.get_date_string_from_system()


static func payload(coins: int, caught: Dictionary, first: Dictionary, claimed: Dictionary, pity: Dictionary, rest: Dictionary, seen: Dictionary = {}) -> Dictionary:
	var body: Dictionary = rest.duplicate(true)
	body["coins"] = int(coins)
	var flat := {}
	var album := {}
	for id in caught.keys():
		var n := maxi(0, int(caught[id]))
		flat[str(id)] = n
		album[str(id)] = {"caught": n, "first_caught": str(first.get(id, ""))}
	for id in first.keys():
		if album.has(str(id)):
			continue
		album[str(id)] = {"caught": 0, "first_caught": str(first[id])}
		flat[str(id)] = 0
	body["caught"] = flat
	body["album"] = album
	var cl := empty_claimed()
	for key in cl.keys():
		cl[key] = bool(claimed.get(key, false))
	body["claimed"] = cl
	body["pity"] = {
		"dry_rare": maxi(0, int(pity.get("dry_rare", 0))),
		"dry_legend": maxi(0, int(pity.get("dry_legend", 0))),
	}
	var seen_out := {}
	for id in seen.keys():
		seen_out[str(id)] = maxi(0, int(seen[id]))
	body["album_seen"] = seen_out
	return body


## La partida vieja no trae run_epoch. Solo esa se vacía una vez.
static func stale_run(data: Dictionary) -> bool:
	return int(data.get("run_epoch", 0)) < RUN_EPOCH


static func apply_fresh_run(data: Dictionary) -> Dictionary:
	if not stale_run(data):
		return data
	var parsed: Dictionary = read(data)
	var rest: Dictionary = parsed.get("rest", {})
	rest.erase("run_epoch")
	var body := payload(0, {}, {}, empty_claimed(), {"dry_rare": 0, "dry_legend": 0}, rest, {})
	body["run_epoch"] = RUN_EPOCH
	return body


static func reward_amount(db: Dictionary, rarity: String) -> int:
	var src = db.get("album_rewards", {})
	if typeof(src) == TYPE_DICTIONARY and src.has(rarity):
		return maxi(0, int(src[rarity]))
	return int(DEFAULT_REWARDS.get(rarity, 0))


static func group_ids(fishes: Array, rarity: String) -> Array:
	var ids: Array = []
	for fish in fishes:
		if typeof(fish) != TYPE_DICTIONARY:
			continue
		if str(fish.get("rarity", "")) != rarity:
			continue
		var id := str(fish.get("id", ""))
		if id == "" or ids.has(id):
			continue
		ids.append(id)
	return ids


## Un grupo está completo si el catálogo trae al menos un pez y cada uno tiene caught > 0.
static func group_complete(fishes: Array, caught: Dictionary, rarity: String) -> bool:
	var ids: Array = group_ids(fishes, rarity)
	if ids.is_empty():
		return false
	for id in ids:
		if int(caught.get(str(id), 0)) <= 0:
			return false
	return true


## Única fuente de verdad del botón Reclamar. El esquema viejo no cobra otra vez.
static func can_claim(fishes: Array, caught: Dictionary, claimed: Dictionary, rarity: String) -> bool:
	var key := claim_key(rarity)
	if key == "":
		return false
	if bool(claimed.get(key, false)):
		return false
	return group_complete(fishes, caught, rarity)


static func rarity_complete(fishes: Array, caught: Dictionary, rarity: String) -> bool:
	return group_complete(fishes, caught, rarity)


## Comprueba, suma, marca y escribe. Si el renombre falla, no cambia el estado que devuelve.
static func commit_claim(path: String, coins: int, caught: Dictionary, first: Dictionary, claimed: Dictionary, pity: Dictionary, rest: Dictionary, seen: Dictionary, fishes: Array, db: Dictionary, rarity: String) -> Dictionary:
	var same := {"ok": false, "coins": coins, "claimed": claimed, "added": 0}
	if not can_claim(fishes, caught, claimed, rarity):
		return same
	var amount := reward_amount(db, rarity)
	var new_coins := int(coins) + amount
	var new_claimed: Dictionary = claimed.duplicate(true)
	new_claimed[claim_key(rarity)] = true
	var body := payload(new_coins, caught, first, new_claimed, pity, rest, seen)
	var err := atomic_write(path, JSON.stringify(body))
	if err != OK:
		return same
	return {"ok": true, "coins": new_coins, "claimed": new_claimed, "added": amount}


static func extra_claim_coins(fishes: Array, caught: Dictionary, claimed: Dictionary, db: Dictionary) -> int:
	var extra := 0
	for rarity in REWARD_RARITIES:
		var key := claim_key(rarity)
		if bool(claimed.get(key, false)) and not group_complete(fishes, caught, rarity):
			extra += reward_amount(db, rarity)
	return extra


static func commit_repair(path: String, coins: int, caught: Dictionary, first: Dictionary, claimed: Dictionary, pity: Dictionary, rest: Dictionary, seen: Dictionary, fishes: Array, db: Dictionary) -> Dictionary:
	var extra := extra_claim_coins(fishes, caught, claimed, db)
	if extra <= 0:
		return {"ok": true, "coins": coins, "claimed": claimed, "extra": 0}
	var new_claimed: Dictionary = claimed.duplicate(true)
	for rarity in REWARD_RARITIES:
		var key := claim_key(rarity)
		if bool(new_claimed.get(key, false)) and not group_complete(fishes, caught, rarity):
			new_claimed[key] = false
	var new_coins := maxi(0, int(coins) - extra)
	var body := payload(new_coins, caught, first, new_claimed, pity, rest, seen)
	var err := atomic_write(path, JSON.stringify(body))
	if err != OK:
		return {"ok": false, "coins": coins, "claimed": claimed, "extra": 0}
	return {"ok": true, "coins": new_coins, "claimed": new_claimed, "extra": extra}


static func atomic_write(path: String, text: String) -> int:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return ERR_CANT_CREATE
	f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if write_err != OK:
		return write_err
	var base := path.get_base_dir()
	if base == "":
		base = "user://"
	var da := DirAccess.open(base)
	if da == null:
		return ERR_CANT_OPEN
	var dest := path.get_file()
	var tmp_name := tmp.get_file()
	if not da.file_exists(tmp_name):
		return ERR_FILE_NOT_FOUND
	if da.file_exists(dest):
		var bak := dest + ".bak"
		if da.file_exists(bak):
			var rm_bak := da.remove(bak)
			if rm_bak != OK:
				return rm_bak
		var moved := da.rename(dest, bak)
		if moved != OK:
			return moved
		var swapped := da.rename(tmp_name, dest)
		if swapped != OK:
			da.rename(bak, dest)
			return swapped
		da.remove(bak)
		return OK
	return da.rename(tmp_name, dest)


## Punto "Nuevo": capturado y todavía no visto en una apertura anterior.
## Si el guardado viejo no tenía album_seen, no se marcan todos como nuevos.
static func news_and_next(seen: Dictionary, caught: Dictionary, seen_missing: bool) -> Dictionary:
	var news := {}
	if not seen_missing:
		for id in caught.keys():
			if int(caught[id]) > 0 and int(seen.get(id, 0)) <= 0:
				news[str(id)] = true
	var next := {}
	for id in caught.keys():
		next[str(id)] = maxi(0, int(caught[id]))
	return {"news": news, "seen": next}


static func rarity_count(fishes: Array, caught: Dictionary, rarity: String) -> Dictionary:
	var total := 0
	var have := 0
	for fish in fishes:
		if typeof(fish) != TYPE_DICTIONARY:
			continue
		if str(fish.get("rarity", "")) != rarity:
			continue
		total += 1
		if int(caught.get(str(fish.get("id", "")), 0)) > 0:
			have += 1
	return {"total": total, "have": have}


## Tarjeta de captura > ficha > álbum > confirmación > tienda > otros paneles.
static func back_action(card_open: bool, detail_open: bool, album_open: bool, settings_open: bool, soon_open: bool, shop_confirm_open: bool = false, shop_open: bool = false) -> String:
	if card_open:
		return "ignore"
	if detail_open:
		return "close_detail"
	if album_open:
		return "close_album"
	if shop_confirm_open:
		return "close_shop_confirm"
	if shop_open:
		return "close_shop"
	if settings_open:
		return "close_settings"
	if soon_open:
		return "close_soon"
	return "quit"
