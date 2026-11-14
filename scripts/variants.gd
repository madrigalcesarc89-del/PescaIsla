extends RefCounted
## Tamaño, color, peso y maestría. Los números viven en data/variants.json.

const PATH := "res://data/variants.json"
const ORDER := ["small", "normal", "large", "giant", "golden", "albino"]
const SIZE_IDS := ["small", "normal", "large", "giant"]
const COLOR_IDS := ["normal", "golden", "albino"]

static var _cache: Dictionary = {}


static func data() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) == TYPE_DICTIONARY:
		_cache = parsed
	return _cache


static func reload() -> void:
	_cache = {}
	data()


static func roll(seen: Array, rng: RandomNumberGenerator) -> Dictionary:
	return {
		"size": _weighted(SIZE_IDS, data().get("sizes", {}), seen, rng, true),
		"color": _weighted(COLOR_IDS, data().get("colors", {}), seen, rng, false),
	}


static func sample_weight(fish: Dictionary, size_id: String, rng: RandomNumberGenerator) -> float:
	var classes: Dictionary = data().get("weight_classes", {})
	var span: Dictionary = classes.get(str(fish.get("weight_class", "small")), {})
	var a := float(span.get("min", 0.2))
	var b := float(span.get("max", 1.0))
	if b < a:
		var swap := a
		a = b
		b = swap
	var mid := (a + b) * 0.5
	var span_w := b - a
	var x := a
	if span_w > 0.0001:
		var u := rng.randf()
		if u < 0.5:
			x = a + sqrt(u * span_w * maxf(mid - a, 0.0001))
		else:
			x = b - sqrt((1.0 - u) * span_w * maxf(b - mid, 0.0001))
	var sizes: Dictionary = data().get("sizes", {})
	var row: Dictionary = sizes.get(size_id, {})
	var kg: float = snapped(x * float(row.get("weight", 1.0)), 0.01)
	return maxf(0.01, kg)


static func coin_value(base: int, size_id: String, color_id: String) -> int:
	var sizes: Dictionary = data().get("sizes", {})
	var colors: Dictionary = data().get("colors", {})
	var sm := float((sizes.get(size_id, {}) as Dictionary).get("value", 1.0))
	var cm := float((colors.get(color_id, {}) as Dictionary).get("value", 1.0))
	var n := int(round(float(base) * sm * cm))
	if base > 0:
		return maxi(1, n)
	return maxi(0, n)


static func apply_fight(fish: Dictionary, size_id: String) -> void:
	var sizes: Dictionary = data().get("sizes", {})
	var row: Dictionary = sizes.get(size_id, {})
	fish["fight_time"] = float(fish.get("fight_time", 3.0)) * float(row.get("fight_time", 1.0))
	fish["pull"] = float(fish.get("pull", 1.0)) * float(row.get("pull", 1.0))


static func scale_of(size_id: String) -> float:
	var sizes: Dictionary = data().get("sizes", {})
	return float((sizes.get(size_id, {}) as Dictionary).get("scale", 1.0))


static func shader_variant(color_id: String) -> int:
	if color_id == "golden":
		return 1
	if color_id == "albino":
		return 2
	return 0


static func format_weight(kg: float) -> String:
	var w: float = snapped(kg, 0.01)
	if w < 1.0:
		return "%d g" % int(round(w * 1000.0))
	var txt := "%.2f" % w
	while txt.ends_with("0"):
		txt = txt.trim_suffix("0")
	if txt.ends_with("."):
		txt = txt.trim_suffix(".")
	return txt + " kg"


static func discover(seen: Array, size_id: String, color_id: String) -> Dictionary:
	var next: Array = seen.duplicate()
	var fresh := false
	var add: Array = [size_id]
	if color_id == "golden" or color_id == "albino":
		add.append(color_id)
	for id in add:
		var key := str(id)
		if not ORDER.has(key) or next.has(key):
			continue
		next.append(key)
		fresh = true
	return {"seen": next, "fresh": fresh}


static func mastery_ready(seen: Array) -> bool:
	for id in ORDER:
		if not seen.has(id):
			return false
	return true


static func mastery_reward(rarity: String) -> int:
	var src: Dictionary = data().get("mastery_rewards", {})
	return maxi(0, int(src.get(rarity, 0)))


static func is_perfect(line_min: float, regress: float) -> bool:
	var rules: Dictionary = data().get("perfect", {})
	var need := float(rules.get("line_min", 0.7))
	var cap := float(rules.get("regress_max", 0.05))
	return line_min + 0.0001 >= need and regress <= cap + 0.0001


static func empty_records() -> Dictionary:
	return {
		"heaviest_id": "",
		"heaviest_kg": 0.0,
		"valuable_id": "",
		"valuable_coins": 0,
		"streak": 0,
		"best_streak": 0,
		"perfect": 0,
		"coins_earned": 0,
	}


static func normalize_records(src, coins_fallback: int) -> Dictionary:
	var out := empty_records()
	if typeof(src) != TYPE_DICTIONARY:
		out["coins_earned"] = maxi(0, coins_fallback)
		return out
	var raw: Dictionary = src
	out["heaviest_id"] = str(raw.get("heaviest_id", ""))
	out["heaviest_kg"] = maxf(0.0, float(raw.get("heaviest_kg", 0.0)))
	out["valuable_id"] = str(raw.get("valuable_id", ""))
	out["valuable_coins"] = maxi(0, int(raw.get("valuable_coins", 0)))
	out["streak"] = maxi(0, int(raw.get("streak", 0)))
	out["best_streak"] = maxi(int(out["streak"]), int(raw.get("best_streak", 0)))
	out["perfect"] = maxi(0, int(raw.get("perfect", 0)))
	if raw.has("coins_earned"):
		out["coins_earned"] = maxi(0, int(raw.get("coins_earned", 0)))
	else:
		out["coins_earned"] = maxi(0, coins_fallback)
	return out


static func empty_meta(migrated: bool) -> Dictionary:
	return {
		"best_weight": 0.0,
		"variants_seen": ["normal"] if migrated else [],
		"mastery_claimed": false,
	}


static func normalize_meta(raw, migrated: bool) -> Dictionary:
	var seen: Array = []
	var best := 0.0
	var claimed := false
	if typeof(raw) == TYPE_DICTIONARY:
		var row: Dictionary = raw
		var list = row.get("variants_seen", [])
		if typeof(list) == TYPE_ARRAY:
			for item in list:
				var id := str(item)
				if ORDER.has(id) and not seen.has(id):
					seen.append(id)
		best = maxf(0.0, float(row.get("best_weight", 0.0)))
		claimed = bool(row.get("mastery_claimed", false))
	elif migrated:
		return empty_meta(true)
	if migrated and seen.is_empty():
		seen = ["normal"]
		best = 0.0
	return {"best_weight": best, "variants_seen": seen, "mastery_claimed": claimed}


static func _weighted(ids: Array, table: Dictionary, seen: Array, rng: RandomNumberGenerator, size_axis: bool) -> String:
	var bonus := float(data().get("mastery_bonus", 2.0))
	var total := 0.0
	var weights: Array = []
	for id in ids:
		var row: Dictionary = table.get(id, {})
		var w := float(row.get("chance", 0.0))
		var boost := false
		if size_axis:
			boost = not seen.has(str(id))
		else:
			boost = str(id) != "normal" and not seen.has(str(id))
		if boost:
			w *= bonus
		weights.append(w)
		total += w
	if total <= 0.0:
		return str(ids[0])
	var ticket := rng.randf() * total
	var acc := 0.0
	for i in ids.size():
		acc += float(weights[i])
		if ticket <= acc:
			return str(ids[i])
	return str(ids[ids.size() - 1])
