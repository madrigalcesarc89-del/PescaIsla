extends RefCounted
## Tienda: catálogo, equipo y compra atómica. No instancia nodos 3D.

const AlbumSave = preload("res://scripts/album_save.gd")

const STARTER_ROD := "rod_bamboo"
const STARTER_BAIT := "bait_pink_worm"
const RARITIES := ["common", "uncommon", "rare", "legendary"]
const SHOP_KEYS := ["owned", "equipped_rod", "equipped_bait", "bait_qty", "decor_placed"]

static var _ready_cat := false
static var _root: Dictionary = {}
static var _items: Dictionary = {}


static func load_catalog() -> Dictionary:
	if _ready_cat:
		return _root
	_ready_cat = true
	_root = {"economy_mult": 1.0, "items": []}
	_items = {}
	if not FileAccess.file_exists("res://data/shop.json"):
		return _root
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/shop.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return _root
	_root = parsed
	var arr = parsed.get("items", [])
	if typeof(arr) == TYPE_ARRAY:
		for it in arr:
			if typeof(it) != TYPE_DICTIONARY:
				continue
			_items[str(it.get("id", ""))] = it
	return _root


static func reload_catalog() -> Dictionary:
	_ready_cat = false
	return load_catalog()


static func economy_mult() -> float:
	var root := load_catalog()
	return maxf(0.0, float(root.get("economy_mult", 1.0)))


static func item_by_id(id: String) -> Dictionary:
	load_catalog()
	var found = _items.get(id, {})
	if typeof(found) != TYPE_DICTIONARY:
		return {}
	return found


static func items_in(category: String) -> Array:
	load_catalog()
	var out: Array = []
	var arr = _root.get("items", [])
	if typeof(arr) != TYPE_ARRAY:
		return out
	for it in arr:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		if str(it.get("category", "")) != category:
			continue
		if not bool(it.get("enabled", true)):
			continue
		out.append(it)
	return out


static func is_infinite(id: String) -> bool:
	var item := item_by_id(id)
	return str(item.get("category", "")) == "bait" and int(item.get("pack_size", 0)) <= 0


static func fresh_state() -> Dictionary:
	return normalize({})


static func normalize(src: Dictionary) -> Dictionary:
	var owned: Array = []
	var raw_owned = src.get("owned", [])
	if typeof(raw_owned) == TYPE_ARRAY:
		for entry in raw_owned:
			var sid := str(entry)
			if sid != "" and not owned.has(sid):
				owned.append(sid)
	if not owned.has(STARTER_ROD):
		owned.append(STARTER_ROD)
	if not owned.has(STARTER_BAIT):
		owned.append(STARTER_BAIT)
	var rod := str(src.get("equipped_rod", STARTER_ROD))
	if not owned.has(rod) or _category(rod) != "rod":
		rod = STARTER_ROD
	var bait := str(src.get("equipped_bait", STARTER_BAIT))
	if not owned.has(bait) or _category(bait) != "bait":
		bait = STARTER_BAIT
	var qty := {}
	var raw_qty = src.get("bait_qty", {})
	if typeof(raw_qty) == TYPE_DICTIONARY:
		for k in raw_qty.keys():
			qty[str(k)] = maxi(0, int(raw_qty[k]))
	var placed := {}
	var raw_placed = src.get("decor_placed", {})
	if typeof(raw_placed) == TYPE_DICTIONARY:
		for k in raw_placed.keys():
			placed[str(k)] = str(raw_placed[k])
	return {
		"owned": owned,
		"equipped_rod": rod,
		"equipped_bait": bait,
		"bait_qty": qty,
		"decor_placed": placed,
	}


static func write_into(body: Dictionary, state: Dictionary) -> void:
	var s := normalize(state)
	body["owned"] = (s["owned"] as Array).duplicate()
	body["equipped_rod"] = str(s["equipped_rod"])
	body["equipped_bait"] = str(s["equipped_bait"])
	body["bait_qty"] = (s["bait_qty"] as Dictionary).duplicate(true)
	body["decor_placed"] = (s["decor_placed"] as Dictionary).duplicate(true)


static func can_buy(coins: int, state: Dictionary, id: String) -> bool:
	var item := item_by_id(id)
	if item.is_empty() or not bool(item.get("enabled", true)):
		return false
	var price := int(item.get("price", 0))
	if price < 0 or int(coins) < price:
		return false
	var cat := str(item.get("category", ""))
	var owned: Array = state.get("owned", [])
	if cat == "rod" or cat == "decor":
		return not owned.has(id)
	if cat == "bait":
		return int(item.get("pack_size", 0)) > 0
	return false


## Una sola compra: comprueba, descuenta, añade y renombra. Si falla, no toca el estado devuelto.
static func buy(path: String, body: Dictionary, id: String) -> Dictionary:
	var coins := int(body.get("coins", 0))
	var state := normalize(body)
	var unchanged := {"ok": false, "coins": coins, "state": _copy_state(state), "price": 0}
	if FileAccess.file_exists(path):
		var disk = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(disk) == TYPE_DICTIONARY:
			var disk_state := normalize(disk)
			var cat := str(item_by_id(id).get("category", ""))
			if (cat == "rod" or cat == "decor") and (disk_state["owned"] as Array).has(id):
				return {"ok": false, "coins": int(disk.get("coins", coins)), "state": disk_state, "price": 0}
	if not can_buy(coins, state, id):
		return unchanged
	var item := item_by_id(id)
	var price := int(item.get("price", 0))
	var new_coins := coins - price
	var new_state := _copy_state(state)
	var owned: Array = new_state["owned"]
	if not owned.has(id):
		owned.append(id)
	if str(item.get("category", "")) == "bait":
		var add := maxi(0, int(item.get("pack_size", 0)))
		var qty: Dictionary = new_state["bait_qty"]
		qty[id] = int(qty.get(id, 0)) + add
	var written: Dictionary = body.duplicate(true)
	written["coins"] = new_coins
	write_into(written, new_state)
	var err := AlbumSave.atomic_write(path, JSON.stringify(written))
	if err != OK:
		return unchanged
	return {"ok": true, "coins": new_coins, "state": new_state, "price": price}


static func equip(state: Dictionary, id: String) -> Dictionary:
	var cur := normalize(state)
	if not (cur["owned"] as Array).has(id):
		return cur
	var item := item_by_id(id)
	if item.is_empty():
		return cur
	var cat := str(item.get("category", ""))
	var nxt := _copy_state(cur)
	if cat == "rod":
		nxt["equipped_rod"] = id
		return nxt
	if cat != "bait":
		return cur
	if not is_infinite(id) and int((cur["bait_qty"] as Dictionary).get(id, 0)) <= 0:
		return cur
	nxt["equipped_bait"] = id
	return nxt


## Solo guarda el hueco. No mueve ni crea nodos del mundo.
static func place(state: Dictionary, id: String) -> Dictionary:
	var cur := normalize(state)
	var item := item_by_id(id)
	if item.is_empty() or str(item.get("category", "")) != "decor":
		return cur
	if not (cur["owned"] as Array).has(id):
		return cur
	var nxt := _copy_state(cur)
	var slot := "shore"
	var slots = item.get("slot_types", [])
	if typeof(slots) == TYPE_ARRAY and not slots.is_empty():
		slot = str(slots[0])
	(nxt["decor_placed"] as Dictionary)[id] = slot
	return nxt


## Gasta 1 del cebo equipado. Si era el último, vuelve a la lombriz.
static func spend(state: Dictionary) -> Dictionary:
	var cur := normalize(state)
	var id := str(cur["equipped_bait"])
	if is_infinite(id):
		return {"state": cur, "changed": false, "fallback": false}
	var qty := int((cur["bait_qty"] as Dictionary).get(id, 0))
	if qty <= 0:
		var back := _copy_state(cur)
		back["equipped_bait"] = STARTER_BAIT
		var moved := id != STARTER_BAIT
		return {"state": back, "changed": moved, "fallback": true}
	var nxt := _copy_state(cur)
	qty -= 1
	(nxt["bait_qty"] as Dictionary)[id] = qty
	var fallback := qty <= 0
	if fallback:
		nxt["equipped_bait"] = STARTER_BAIT
	return {"state": nxt, "changed": true, "fallback": fallback}


static func gear(state: Dictionary) -> Dictionary:
	var cur := normalize(state)
	var rod := _fx(str(cur["equipped_rod"]))
	var bait := _fx(str(cur["equipped_bait"]))
	var wm := {}
	for rarity in RARITIES:
		wm[rarity] = clampf(float(rod["w"][rarity]) * float(bait["w"][rarity]), 0.2, 5.0)
	return {
		"wait_mult": clampf(float(rod["wait"]) * float(bait["wait"]), 0.45, 1.6),
		"zone_mult": clampf(float(rod["zone"]) * float(bait["zone"]), 0.5, 1.8),
		"value_mult": clampf(float(rod["value"]) * float(bait["value"]) * economy_mult(), 0.5, 4.0),
		"weight_mult": wm,
	}


static func payout(base_value: int, g: Dictionary) -> int:
	var mult := float(g.get("value_mult", 1.0))
	var n := int(round(float(base_value) * mult))
	if base_value > 0:
		return maxi(1, n)
	return maxi(0, n)


static func effect_line(item: Dictionary) -> String:
	var fx: Dictionary = {}
	if typeof(item.get("effects", {})) == TYPE_DICTIONARY:
		fx = item["effects"]
	var wait := float(fx.get("wait_mult", 1.0))
	var zone := float(fx.get("zone_mult", 1.0))
	var value := float(fx.get("value_mult", 1.0))
	if absf(wait - 1.0) >= 0.005:
		return SettingsData.t("shop_fx_wait") % _pct(wait)
	if absf(zone - 1.0) >= 0.005:
		return SettingsData.t("shop_fx_zone") % _pct(zone)
	var wm = fx.get("weight_mult", {})
	var best_r := ""
	var best_d := 0.0
	var best_m := 1.0
	if typeof(wm) == TYPE_DICTIONARY:
		for rarity in RARITIES:
			var m := float(wm.get(rarity, 1.0))
			var d := absf(m - 1.0)
			if d > best_d + 0.001:
				best_d = d
				best_r = rarity
				best_m = m
	if best_r != "" and best_d >= 0.005:
		return SettingsData.t("shop_fx_" + best_r) % _pct(best_m)
	if absf(value - 1.0) >= 0.005:
		return SettingsData.t("shop_fx_value") % _pct(value)
	if str(item.get("category", "")) == "decor":
		var slot := "shore"
		var slots = item.get("slot_types", [])
		if typeof(slots) == TYPE_ARRAY and not slots.is_empty():
			slot = str(slots[0])
		var key := "shop_slot_" + slot
		var label := SettingsData.t(key)
		if label == key:
			return slot
		return label
	return SettingsData.t("shop_fx_starter")


static func _pct(mult: float) -> String:
	var pct := int(round((mult - 1.0) * 100.0))
	if pct < 0:
		return "−%d %%" % absi(pct)
	return "+%d %%" % pct


static func _category(id: String) -> String:
	return str(item_by_id(id).get("category", ""))


static func _fx(id: String) -> Dictionary:
	var item := item_by_id(id)
	var fx: Dictionary = {}
	if typeof(item.get("effects", {})) == TYPE_DICTIONARY:
		fx = item["effects"]
	var wm = fx.get("weight_mult", {})
	var weights := {}
	for rarity in RARITIES:
		var m := 1.0
		if typeof(wm) == TYPE_DICTIONARY:
			m = float(wm.get(rarity, 1.0))
		weights[rarity] = m
	return {
		"wait": float(fx.get("wait_mult", 1.0)),
		"zone": float(fx.get("zone_mult", 1.0)),
		"value": float(fx.get("value_mult", 1.0)),
		"w": weights,
	}


static func _copy_state(state: Dictionary) -> Dictionary:
	return {
		"owned": (state["owned"] as Array).duplicate(),
		"equipped_rod": str(state["equipped_rod"]),
		"equipped_bait": str(state["equipped_bait"]),
		"bait_qty": (state["bait_qty"] as Dictionary).duplicate(true),
		"decor_placed": (state["decor_placed"] as Dictionary).duplicate(true),
	}
