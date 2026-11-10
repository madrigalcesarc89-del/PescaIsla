extends RefCounted
## Guardado del álbum. Los JSON viejos solo traen caught como enteros:
## se rellenan first_caught y claimed sin perder monedas ni otras claves.

const RARITIES := ["common", "uncommon", "rare", "legendary"]
const DEFAULT_REWARDS := {"common": 50, "uncommon": 120, "rare": 300, "legendary": 800}


static func empty_claimed() -> Dictionary:
	return {"common": false, "uncommon": false, "rare": false, "legendary": false}


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
		for rarity in RARITIES:
			claimed[rarity] = bool(src.get(rarity, false))
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
	for rarity in RARITIES:
		cl[rarity] = bool(claimed.get(rarity, false))
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


static func reward_amount(db: Dictionary, rarity: String) -> int:
	var src = db.get("album_rewards", {})
	if typeof(src) == TYPE_DICTIONARY and src.has(rarity):
		return maxi(0, int(src[rarity]))
	return int(DEFAULT_REWARDS.get(rarity, 0))


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


static func rarity_complete(fishes: Array, caught: Dictionary, rarity: String) -> bool:
	var info := rarity_count(fishes, caught, rarity)
	return int(info["total"]) > 0 and int(info["have"]) == int(info["total"])


## Tarjeta de captura > ficha > álbum > otros paneles. La tarjeta no se cierra.
static func back_action(card_open: bool, detail_open: bool, album_open: bool, settings_open: bool, soon_open: bool) -> String:
	if card_open:
		return "ignore"
	if detail_open:
		return "close_detail"
	if album_open:
		return "close_album"
	if settings_open:
		return "close_settings"
	if soon_open:
		return "close_soon"
	return "quit"
