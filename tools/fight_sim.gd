extends SceneTree
## 2000 peleas por pez con un bot de reacción 180 ms ±60 y error de pulso.
## Misma clase que el juego. Caña base, y otra pasada en modo relajado.

const Fight = preload("res://scripts/fight.gd")
const N := 2000
const DT := 0.05


func _init() -> void:
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var gear := {
		"zone_mult": 1.0,
		"agility": 0.0,
		"line_strength_mult": 1.0,
		"telegraph_mult": 1.0,
		"preview": false,
		"shield": false,
	}
	print("ANTES  difficulty_mult=1  caña base")
	_table(fishes, gear, false, 1)
	print("RELAJADO")
	_table(fishes, gear, true, 100000)
	quit()


func _table(fishes: Array, gear: Dictionary, relaxed: bool, salt: int) -> void:
	var goals := {
		"common": 0.95, "uncommon": 0.90, "rare": 0.80,
		"epic": 0.70, "legendary": 0.55, "secret": 0.60,
	}
	if relaxed:
		for k in goals.keys():
			goals[k] = minf(float(goals[k]) + 0.15, 0.99)
	var by := {}
	for fish in fishes:
		var id := str(fish["id"])
		var catch_n := 0
		var break_n := 0
		var times: Array[float] = []
		for i in N:
			var fight = Fight.new()
			fight.configure(fish, gear, relaxed, salt + i * 17 + id.hash())
			var rng := RandomNumberGenerator.new()
			rng.seed = salt + i * 91
			var hold := false
			var seen := 0.5
			var acc := 0.0
			var react := rng.randf_range(0.12, 0.24)
			var guard := 0
			while fight.outcome == "" and guard < 4000:
				guard += 1
				acc += DT
				if acc >= react:
					acc = 0.0
					react = rng.randf_range(0.12, 0.24)
					if fight.alpha >= 0.2:
						seen = fight.center
					var aim := seen + rng.randf_range(-0.05, 0.05)
					hold = fight.marker < aim
				fight.step(DT, hold)
			if fight.outcome == "catch":
				catch_n += 1
				times.append(fight.elapsed)
			elif fight.outcome == "break":
				break_n += 1
		times.sort()
		var mean := 0.0
		for t in times:
			mean += t
		if times.size() > 0:
			mean /= float(times.size())
		var p95 := 0.0
		if times.size() > 0:
			p95 = times[mini(times.size() - 1, int(float(times.size()) * 0.95))]
		var rate := float(catch_n) / float(N)
		var rare := str(fish["rarity"])
		var ok := rate + 0.0001 >= float(goals[rare])
		if not by.has(rare):
			by[rare] = {"n": 0, "rate": 0.0, "bad": 0}
		by[rare]["n"] += 1
		by[rare]["rate"] += rate
		if not ok:
			by[rare]["bad"] += 1
		print("%-22s %-10s %s %5.1f%%  media %5.1fs  p95 %5.1fs  rotura %4.1f%%  %s" % [
			id, rare, str(fish["fight"]), rate * 100.0, mean, p95,
			float(break_n) / float(N) * 100.0, "OK" if ok else "BAJO"])
	for rare in ["common", "uncommon", "rare", "epic", "legendary", "secret"]:
		if not by.has(rare):
			continue
		var avg := float(by[rare]["rate"]) / float(by[rare]["n"])
		print("GRUPO %-12s media %5.1f%%  objetivo %5.1f%%  fuera %d" % [
			rare, avg * 100.0, float(goals[rare]) * 100.0, int(by[rare]["bad"])])
