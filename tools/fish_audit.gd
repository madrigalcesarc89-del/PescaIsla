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
	"fish_cream_carp": "common",
	"fish_mint_puffer": "uncommon",
	"fish_peach_angelfish": "uncommon",
	"fish_jellyfish": "uncommon",
	"fish_lanternfish": "rare",
	"fish_golden_koi": "rare",
	"fish_seahorse": "rare",
	"fish_cloud": "legendary",
	"fish_mini_whale": "legendary",
	"fish_sea_dragon": "legendary",
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
	_print_table(fishes, before, after)
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
	if fishes.size() != 12:
		_bad("fish_db tiene %d peces, se esperaban 12" % fishes.size())
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
	print("POOL = 12 ids, lista vieja (payaso) ausente")


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


func _print_table(fishes: Array, before: Dictionary, after: Dictionary) -> void:
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
		if nb == 0 or na == 0:
			_bad(id + " salió 0 veces en 100000")


func _check_rules(FishRoll, fishes: Array, db: Dictionary) -> void:
	var rw: Dictionary = FishRoll.rarity_weights(db)
	var want_w := {"common": 55.0, "uncommon": 28.0, "rare": 13.0, "legendary": 4.0}
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
		if rarity != "rare" and rarity != "legendary":
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
	# 20/25 sin descubrir; al tener la sardina, la luna pesa el doble relativo: (20*2)/(25*1) = 1.6
	if not is_equal_approx(ratio_fresh, 20.0 / 25.0):
		_bad("pesos relativos comunes alterados: %.3f" % ratio_fresh)
	if not is_equal_approx(ratio_partial, (20.0 * 2.0) / 25.0):
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
	print("PITY rare_after=25 forces rare+ ; legend_after=80 triples legendary bucket")
	print("DISCOVERY undiscovered x2 inside rarity, rarity total unchanged")


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
