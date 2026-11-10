extends RefCounted
## Sorteo único de peces. Lo usan scripts/fishing.gd y tools/fish_audit.gd.
## Un diccionario opcional solo escala el cubo de cada rareza, después
## del bonus de descubrimiento y de la protección contra mala suerte.
## Ningún filtro saca a un id de la bolsa.

const RARITIES := ["common", "uncommon", "rare", "legendary"]
const RARE_PLUS := ["rare", "legendary"]


static func rarity_weights(db: Dictionary) -> Dictionary:
	var src: Dictionary = db.get("rarity_weights", {})
	return {
		"common": float(src.get("common", 55.0)),
		"uncommon": float(src.get("uncommon", 28.0)),
		"rare": float(src.get("rare", 13.0)),
		"legendary": float(src.get("legendary", 4.0)),
	}


static func pity_rules(db: Dictionary) -> Dictionary:
	var src: Dictionary = db.get("pity", {})
	return {
		"rare_after": int(src.get("rare_after", 25)),
		"legend_after": int(src.get("legend_after", 80)),
		"legend_mult": float(src.get("legend_mult", 3.0)),
		"discovery_mult": float(src.get("discovery_mult", 2.0)),
	}


## true si esta tirada está obligada a raro o mejor.
static func forces_rare(dry_rare: int, db: Dictionary) -> bool:
	return dry_rare >= int(pity_rules(db).rare_after)


## true si los legendarios van con el multiplicador de mala suerte.
static func legend_boosted(dry_legend: int, db: Dictionary) -> bool:
	return dry_legend >= int(pity_rules(db).legend_after)


## Pesos efectivos. Un pez que el jugador aún no tiene pesa el doble
## dentro de su rareza (el total de la rareza no cambia).
static func effective(fishes: Array, caught: Dictionary, dry_rare: int, dry_legend: int, db: Dictionary, gear: Dictionary = {}) -> Array:
	var rules := pity_rules(db)
	var rw := rarity_weights(db)
	if legend_boosted(dry_legend, db):
		rw["legendary"] = float(rw["legendary"]) * float(rules.legend_mult)
	var gear_w: Dictionary = {}
	var raw_w = gear.get("weight_mult", {})
	if typeof(raw_w) == TYPE_DICTIONARY:
		gear_w = raw_w
	var allowed: Array = RARE_PLUS if forces_rare(dry_rare, db) else RARITIES
	var groups := {}
	for f in fishes:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		var rarity := str(f.get("rarity", "common"))
		if not groups.has(rarity):
			groups[rarity] = []
		groups[rarity].append(f)
	var out: Array = []
	for rarity in allowed:
		if not groups.has(rarity):
			continue
		var members: Array = groups[rarity]
		var scaled: Array = []
		var sum_w := 0.0
		for f in members:
			var owned := int(caught.get(str(f.get("id", "")), 0)) > 0
			var mult := 1.0 if owned else float(rules.discovery_mult)
			var w := maxf(0.0, float(f.get("weight", 1.0))) * mult
			scaled.append([f, w])
			sum_w += w
		if sum_w <= 0.0:
			continue
		var bucket := float(rw.get(rarity, 0.0)) * float(gear_w.get(rarity, 1.0))
		for pair in scaled:
			out.append({"fish": pair[0], "w": bucket * float(pair[1]) / sum_w})
	return out


## roll en [0, 1). Devuelve el diccionario del pez, o {} si no hay bolsa.
static func pick(fishes: Array, caught: Dictionary, dry_rare: int, dry_legend: int, db: Dictionary, roll: float, gear: Dictionary = {}) -> Dictionary:
	return _pick_entries(effective(fishes, caught, dry_rare, dry_legend, db, gear), roll)


## Sorteo anterior al paso 23: weight absoluto, sin rareza ni pity.
## Sirve para la tabla "antes". No lo usa el juego.
static func pick_legacy(fishes: Array, roll: float) -> Dictionary:
	var entries: Array = []
	for f in fishes:
		if typeof(f) != TYPE_DICTIONARY:
			continue
		entries.append({"fish": f, "w": float(f.get("weight", 1.0))})
	return _pick_entries(entries, roll)


static func _pick_entries(entries: Array, roll: float) -> Dictionary:
	var total := 0.0
	for e in entries:
		total += float(e.get("w", 0.0))
	if total <= 0.0 or entries.is_empty():
		return {}
	var x := clampf(roll, 0.0, 0.999999) * total
	for e in entries:
		x -= float(e.get("w", 0.0))
		if x <= 0.0:
			return e.get("fish", {})
	return entries[entries.size() - 1].get("fish", {})


## Contadores tras una captura (no tras un escape).
static func note_catch(rarity: String, dry_rare: int, dry_legend: int) -> Dictionary:
	if rarity == "legendary":
		return {"dry_rare": 0, "dry_legend": 0}
	if rarity == "rare":
		return {"dry_rare": 0, "dry_legend": dry_legend + 1}
	return {"dry_rare": dry_rare + 1, "dry_legend": dry_legend + 1}
