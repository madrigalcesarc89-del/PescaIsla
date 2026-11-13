extends SceneTree
## Paso 23a. 100 000 lanzamientos con el sorteo real (FishRoll) y con
## el sorteo anterior. Comprueba texturas, nombres de archivo, rareza
## y que ningún filtro (cebo, hora, caña) ni lista vieja excluya un id.
##
##   Godot --headless --path . --script res://tools/fish_audit.gd

const DB_PATH := "res://data/fish_db.json"
const N := 100000
const EXPECTED := {
	"fish_pink_sardine": "common",
	"fish_moon": "common",
	"fish_silver_minnow": "common",
	"fish_sunny_perch": "common",
	"fish_cinnamon_gudgeon": "common",
	"fish_cream_carp": "common",
	"fish_clownfish": "common",
	"fish_mint_puffer": "uncommon",
	"fish_bubble_fish": "uncommon",
	"fish_peach_angelfish": "uncommon",
	"fish_jellyfish": "uncommon",
	"fish_lanternfish": "rare",
	"fish_pastel_ray": "rare",
	"fish_golden_koi": "rare",
	"fish_seahorse": "rare",
	"fish_cotton_fish": "epic",
	"fish_cloud": "epic",
	"fish_comet_fish": "epic",
	"fish_mini_whale": "epic",
	"fish_ghost_fish": "epic",
	"fish_electric_eel": "legendary",
	"fish_rainbow_fish": "legendary",
	"fish_sea_dragon": "legendary",
	"fish_kitty_fish": "secret",
}
const OLD_IDS := ["payaso", "sardina", "pez_payaso", "fish_payaso"]

var _fail := 0


func _init() -> void:
	var FishRoll = load("res://scripts/fish_roll.gd")
	var db := _read_json(DB_PATH)
	var fishes: Array = db.get("fishes", [])
	print("FISH_AUDIT n=%d" % N)
	_check_identity(fishes)
	_check_filters()
	_check_textures(fishes)
	var before := _simulate(FishRoll, fishes, db, true)
	var after := _simulate(FishRoll, fishes, db, false)
	var secret := _simulate_secret(FishRoll, fishes, db)
	_print_table(fishes, before, after, secret)
	_check_rules(FishRoll, fishes, db)
	if _fail == 0:
		print("AUDIT_OK")
	else:
		print("AUDIT_FAIL count=%d" % _fail)
		quit(1)
		return
	quit()


func _read_json(path: String) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		_bad("JSON inválido: " + path)
		return {}
	return data


func _bad(msg: String) -> void:
	_fail += 1
	print("FAIL ", msg)


func _check_identity(fishes: Array) -> void:
	var seen := {}
	if fishes.size() != 24:
		_bad("fish_db tiene %d peces, se esperaban 24" % fishes.size())
	for f in fishes:
		var id := str(f.get("id", ""))
		seen[id] = true
		var rarity := str(f.get("rarity", ""))
		if not EXPECTED.has(id):
			_bad("id inesperado en la bolsa: " + id)
		elif EXPECTED[id] != rarity:
			_bad("rareza de %s es %s, se esperaba %s" % [id, rarity, EXPECTED[id]])
		var tex := str(f.get("texture", ""))
		var base := tex.get_file().get_basename()
		if base != id:
			_bad("el archivo de %s no coincide con el id (%s)" % [id, tex])
		if not tex.ends_with("/" + id + ".png"):
			_bad("ruta de textura inesperada para " + id + ": " + tex)
		if id in OLD_IDS:
			_bad("lista vieja todavía en la bolsa: " + id)
	for id in EXPECTED.keys():
		if not seen.has(id):
			_bad("el id no entra en el sorteo: " + id)
	for old in OLD_IDS:
		if seen.has(old):
			_bad("id viejo presente: " + old)
	var files := {}
	var dir := DirAccess.open("res://assets/art/fish")
	if dir == null:
		_bad("no se pudo abrir assets/art/fish")
	else:
		dir.list_dir_begin()
		var name := dir.get_next()
		while name != "":
			if name.ends_with(".png"):
				files[name.get_basename()] = true
			name = dir.get_next()
		dir.list_dir_end()
	for id in EXPECTED.keys():
		if not files.has(id):
			_bad("falta el png de " + id)
	for id in files.keys():
		if not EXPECTED.has(id):
			_bad("png sin ficha en fish_db: " + id)


func _check_filters() -> void:
	var roll := _code_only(FileAccess.get_file_as_string("res://scripts/fish_roll.gd"))
	var fishing := _code_only(FileAccess.get_file_as_string("res://scripts/fishing.gd"))
	if roll.find("func pick(") < 0:
		_bad("no está el sorteo real FishRoll.pick")
	if fishing.find("FishRoll.pick(") < 0:
		_bad("fishing.gd no usa el sorteo real")
	# El código (sin comentarios) no nombra cebo, hora ni caña.
	for word in ["bait", "cebo", "hour", "hora", "rod_"]:
		if roll.find(word) >= 0:
			_bad("fish_roll.gd menciona un filtro posible: " + word)
	print("FILTERS bait/hour/rod = none")
	print("POOL = 23 ids en el sorteo normal; el secreto queda fuera")


func _code_only(src: String) -> String:
	var out := ""
	for line in src.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("#"):
			continue
		out += line + "\n"
	return out


func _check_textures(fishes: Array) -> void:
	for f in fishes:
		var id := str(f.get("id", ""))
		var path := str(f.get("texture", ""))
		var exists := FileAccess.file_exists(path)
		var img := Image.new()
		var err := img.load(ProjectSettings.globalize_path(path))
		var loads := err == OK and img.get_width() > 0
		print("TEX %s exists=%s loads=%s %dx%d" % [id, exists, loads, img.get_width(), img.get_height()])
		if not exists or not loads:
			_bad("textura de %s no existe o no carga (%s)" % [id, path])


func _simulate(FishRoll, fishes: Array, db: Dictionary, legacy: bool) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var counts := {}
	for f in fishes:
		counts[str(f.get("id", ""))] = 0
	for _i in N:
		var fish: Dictionary = FishRoll.pick_legacy(fishes, rng.randf()) if legacy else FishRoll.pick(fishes, {}, 0, 0, db, rng.randf())
		var id := str(fish.get("id", ""))
		if not counts.has(id):
			counts[id] = 0
			_bad("el sorteo devolvió un id fuera de la bolsa: " + id)
		counts[id] = int(counts[id]) + 1
	return counts


func _simulate_secret(FishRoll, fishes: Array, db: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var caught := {}
	var n_known := 0
	for f in fishes:
		if str(f.get("rarity", "")) == "secret":
			continue
		if n_known >= 20:
			break
		caught[str(f.get("id", ""))] = 1
		n_known += 1
	var hits := 0
	for _i in N:
		var fish: Dictionary = FishRoll.pick(fishes, caught, 0, 0, db, rng.randf(), {}, "night")
		if str(fish.get("id", "")) == "fish_kitty_fish":
			hits += 1
	return {"hits": hits, "known": n_known}


func _print_table(fishes: Array, before: Dictionary, after: Dictionary, secret: Dictionary) -> void:
	print("TABLE id | rarity | p_antes | capturas_antes | p_despues | capturas_despues | n_antes | n_despues")
	for f in fishes:
		var id := str(f.get("id", ""))
		var nb := int(before.get(id, 0))
		var na := int(after.get(id, 0))
		var pb := float(nb) / float(N)
		var pa := float(na) / float(N)
		var cb := 1.0 / pb if pb > 0.0 else -1.0
		var ca := 1.0 / pa if pa > 0.0 else -1.0
		print("ROW %s %s %.4f%% %.1f %.4f%% %.1f %d %d" % [
			id, str(f.get("rarity", "")), pb * 100.0, cb, pa * 100.0, ca, nb, na])
		if str(f.get("rarity", "")) == "secret":
			if na != 0:
				_bad("el secreto entró en el sorteo normal")
			continue
		if nb == 0 or na == 0:
			_bad(id + " salió 0 veces en 100000")
	var hits := int(secret.get("hits", 0))
	var ps := float(hits) / float(N)
	var cs := 1.0 / ps if ps > 0.0 else -1.0
	print("SECRET_ROW fish_kitty_fish night+20 %.4f%% %.1f %d known=%d" % [ps * 100.0, cs, hits, int(secret.get("known", 0))])
	if hits < 2200 or hits > 3800:
		_bad("el secreto de noche no está cerca del 3 %% (%d)" % hits)


func _check_rules(FishRoll, fishes: Array, db: Dictionary) -> void:
	var rw: Dictionary = FishRoll.rarity_weights(db)
	var want_w := {"common": 50.0, "uncommon": 28.0, "rare": 16.0, "epic": 14.0, "legendary": 7.0}
	for key in want_w.keys():
		var want := float(want_w[key])
		if not is_equal_approx(float(rw[key]), want):
			_bad("peso de %s es %s, se esperaba %s" % [key, rw[key], want])
	# Tras 25 capturas sin raro, la bolsa solo tiene raro o legendario.
	var forced: Array = FishRoll.effective(fishes, {}, 25, 0, db)
	if forced.is_empty():
		_bad("la protección de 25 capturas dejó la bolsa vacía")
	for e in forced:
		var rarity := str(e.fish.get("rarity", ""))
		if rarity != "rare" and rarity != "epic" and rarity != "legendary":
			_bad("pity de raro dejó entrar " + rarity)
	# A las 80 sin legendario, el cubo legendario se triplica.
	var plain := _bucket(FishRoll.effective(fishes, {}, 0, 0, db), "legendary")
	var boosted := _bucket(FishRoll.effective(fishes, {}, 0, 80, db), "legendary")
	if plain <= 0.0 or not is_equal_approx(boosted / plain, 3.0):
		_bad("el peso legendario no se triplicó (%.3f -> %.3f)" % [plain, boosted])
	# Descubrimiento: el pez que falta pesa el doble DENTRO de su rareza.
	var fresh: Array = FishRoll.effective(fishes, {}, 0, 0, db)
	var owned := {"fish_pink_sardine": 1}
	var partial: Array = FishRoll.effective(fishes, owned, 0, 0, db)
	var ratio_fresh := _w(fresh, "fish_moon") / _w(fresh, "fish_pink_sardine")
	var ratio_partial := _w(partial, "fish_moon") / _w(partial, "fish_pink_sardine")
	if not is_equal_approx(ratio_fresh, 1.0):
		_bad("pesos relativos comunes alterados: %.3f" % ratio_fresh)
	if not is_equal_approx(ratio_partial, 2.0):
		_bad("el bonus de descubrimiento no duplica dentro de la rareza: %.3f" % ratio_partial)
	var common_sum := 0.0
	for e in fresh:
		if str(e.fish.get("rarity", "")) == "common":
			common_sum += float(e.w)
	var common_sum2 := 0.0
	for e in partial:
		if str(e.fish.get("rarity", "")) == "common":
			common_sum2 += float(e.w)
	if not is_equal_approx(common_sum, common_sum2):
		_bad("el bonus de descubrimiento cambió el total de la rareza")
	var night: Array = FishRoll.effective(fishes, {}, 0, 0, db, {}, "night")
	var day: Array = FishRoll.effective(fishes, {}, 0, 0, db, {}, "day")
	if not is_equal_approx(_w(night, "fish_moon") / _w(night, "fish_pink_sardine"), 2.0):
		_bad("de noche la luna no pesa el doble")
	if not is_equal_approx(_w(day, "fish_sunny_perch") / _w(day, "fish_pink_sardine"), 1.5):
		_bad("de día la perca no pesa 1.5")
	var ids := {}
	for e in fresh:
		ids[str(e.fish.get("id", ""))] = true
		if str(e.fish.get("rarity", "")) == "secret":
			_bad("el secreto está en el cubo normal")
	if ids.size() != 23:
		_bad("el sorteo normal no tiene 23 peces")
	var early: Dictionary = FishRoll.pick(fishes, {}, 0, 0, db, 0.0, {}, "night")
	if str(early.get("rarity", "")) == "secret":
		_bad("el secreto salió sin conocer 20 especies")
	print("PITY rare_after=25 forces rare+epic+legendary ; legend_after=80 triples legendary bucket")
	print("DISCOVERY undiscovered x2 inside rarity, rarity total unchanged")
	print("SECRET 3% only at night after 20 species")


func _bucket(entries: Array, rarity: String) -> float:
	var s := 0.0
	for e in entries:
		if str(e.fish.get("rarity", "")) == rarity:
			s += float(e.w)
	return s


func _w(entries: Array, id: String) -> float:
	for e in entries:
		if str(e.fish.get("id", "")) == id:
			return float(e.w)
	return 0.0
