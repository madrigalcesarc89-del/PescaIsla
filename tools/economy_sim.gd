extends SceneTree
## 2000 capturas con el sorteo real. Ajusta precios fuera de rango.
## Godot --headless --path . --script res://tools/economy_sim.gd

const FishRoll = preload("res://scripts/fish_roll.gd")
const ShopSave = preload("res://scripts/shop_save.gd")

const CATCHES := 2000
const PER_MIN := 4.0
const SEED := 23011
const ROD_TARGET := {
	"rod_coral": 2.0,
	"rod_cherry": 6.0,
	"rod_moon": 15.0,
	"rod_rainbow": 35.0,
}
const PREMIUM := "bait_golden_pearl"


func _init() -> void:
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var base_gear: Dictionary = ShopSave.gear(ShopSave.fresh_state())
	var mean := _run(fishes, db, base_gear)
	var ipm := mean * PER_MIN
	print("ECONOMY catches %d seed %d" % [CATCHES, SEED])
	print("ECONOMY mean %.4f ipm %.4f economy_mult %.3f" % [mean, ipm, ShopSave.economy_mult()])
	var cap := 0.25 * mean
	print("ECONOMY bait_unit_cap %.4f" % cap)
	var root := ShopSave.load_catalog()
	var items: Array = root.get("items", [])
	var before: Array = []
	var changed := false
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var id := str(it.get("id", ""))
		var price := int(it.get("price", 0))
		var row := _row(id, it, price, mean, ipm)
		before.append(row)
		var new_price := price
		if ROD_TARGET.has(id) and ipm > 0.0:
			var mins := float(price) / ipm
			var target := float(ROD_TARGET[id])
			if mins < target * 0.8 or mins > target * 1.2:
				new_price = maxi(10, int(round(target * ipm / 10.0)) * 10)
		var cat := str(it.get("category", ""))
		var pack := int(it.get("pack_size", 0))
		if cat == "bait" and id != PREMIUM and pack > 0 and cap > 0.0:
			var unit := float(new_price) / float(pack)
			if unit > cap + 0.0001:
				new_price = int(floor(cap)) * pack
		if new_price != price:
			it["price"] = new_price
			changed = true
	_print_table("BEFORE", before, mean)
	if changed:
		var after: Array = []
		for it in items:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			after.append(_row(str(it.get("id", "")), it, int(it.get("price", 0)), mean, ipm))
		_print_table("AFTER", after, mean)
		var path := ProjectSettings.globalize_path("res://data/shop.json")
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			print("ECONOMY_WRITE_FAIL")
			quit(1)
			return
		f.store_string(JSON.stringify(root, "  "))
		f.flush()
		f.close()
		ShopSave.reload_catalog()
		print("ECONOMY_ADJUSTED")
	else:
		print("ECONOMY sin ajuste")
	print("ECONOMY_OK")
	quit(0)


func _row(id: String, item: Dictionary, price: int, mean: float, ipm: float) -> Dictionary:
	var cat := str(item.get("category", ""))
	var pack := int(item.get("pack_size", 0))
	var mins := 0.0 if ipm <= 0.0 else float(price) / ipm
	var unit := 0.0
	if cat == "bait" and pack > 0:
		unit = float(price) / float(pack)
	var net := 0.0
	if cat == "bait":
		var st := ShopSave.fresh_state()
		var owned: Array = st["owned"]
		if not owned.has(id):
			owned.append(id)
		st["equipped_bait"] = id
		var g: Dictionary = ShopSave.gear(st)
		var bait_mean := _run_cached(g)
		var cost := 0.0 if pack <= 0 else float(price) / float(pack)
		net = bait_mean - cost
		_bait_note(id, bait_mean)
	return {"id": id, "price": price, "minutes": mins, "unit": unit, "net": net, "cat": cat}


var _cache: Dictionary = {}
var _fishes: Array = []
var _db: Dictionary = {}


func _run(fishes: Array, db: Dictionary, gear: Dictionary) -> float:
	_fishes = fishes
	_db = db
	return _simulate(gear)


func _run_cached(gear: Dictionary) -> float:
	var key := JSON.stringify(gear)
	if _cache.has(key):
		return float(_cache[key])
	var mean := _simulate(gear)
	_cache[key] = mean
	return mean


func _simulate(gear: Dictionary) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var caught := {}
	var dry_r := 0
	var dry_l := 0
	var total := 0
	for _i in CATCHES:
		var fish: Dictionary = FishRoll.pick(_fishes, caught, dry_r, dry_l, _db, rng.randf(), gear)
		total += ShopSave.payout(int(fish.get("value", 0)), gear)
		var id := str(fish.get("id", ""))
		caught[id] = int(caught.get(id, 0)) + 1
		var nxt: Dictionary = FishRoll.note_catch(str(fish.get("rarity", "common")), dry_r, dry_l)
		dry_r = int(nxt.get("dry_rare", 0))
		dry_l = int(nxt.get("dry_legend", 0))
	return float(total) / float(CATCHES)


func _bait_note(id: String, bait_mean: float) -> void:
	print("BAIT %s mean %.4f" % [id, bait_mean])


func _print_table(title: String, rows: Array, mean: float) -> void:
	print("TABLE %s" % title)
	print("id price minutes unit net")
	for row in rows:
		var id := str(row["id"])
		var price := int(row["price"])
		var mins := float(row["minutes"])
		var unit := float(row["unit"])
		var net := float(row["net"])
		var extra := ""
		if str(row["cat"]) == "bait" and id != PREMIUM and unit > 0.25 * mean + 0.001:
			extra = " OVER_CAP"
		if id == PREMIUM:
			extra = " PREMIUM"
		print("%s %d %.2f %.2f %.2f%s" % [id, price, mins, unit, net, extra])
