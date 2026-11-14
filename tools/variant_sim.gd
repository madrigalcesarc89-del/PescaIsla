extends SceneTree
## 200 000 capturas: tamaños, colores y peso. Maestría aparte, promedio ≤ 80.
## Godot --headless --path . --script res://tools/variant_sim.gd

const FishVariants = preload("res://scripts/variants.gd")

const CATCHES := 200000
const TRIALS := 4000
const SEED := 90210


func _init() -> void:
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var sizes := {"small": 0, "normal": 0, "large": 0, "giant": 0}
	var colors := {"normal": 0, "golden": 0, "albino": 0}
	var stats := {}
	var seen_all := {}
	for _i in CATCHES:
		var fish: Dictionary = fishes[rng.randi() % fishes.size()]
		var id := str(fish.get("id", ""))
		var known: Array = seen_all.get(id, [])
		var roll := FishVariants.roll(known, rng)
		var found: Dictionary = FishVariants.discover(known, str(roll.get("size", "normal")), str(roll.get("color", "normal")))
		seen_all[id] = found.get("seen", known)
		var size_id := str(roll.get("size", "normal"))
		var color_id := str(roll.get("color", "normal"))
		sizes[size_id] = int(sizes.get(size_id, 0)) + 1
		colors[color_id] = int(colors.get(color_id, 0)) + 1
		var kg := FishVariants.sample_weight(fish, size_id, rng)
		var row: Dictionary = stats.get(id, {"n": 0, "sum": 0.0, "min": 999.0, "max": 0.0})
		row["n"] = int(row["n"]) + 1
		row["sum"] = float(row["sum"]) + kg
		row["min"] = minf(float(row["min"]), kg)
		row["max"] = maxf(float(row["max"]), kg)
		stats[id] = row
	print("VARIANT_SIM catches %d seed %d" % [CATCHES, SEED])
	for id in FishVariants.SIZE_IDS:
		print("SIZE %s %d %.4f" % [id, int(sizes[id]), float(sizes[id]) / float(CATCHES)])
	for id in FishVariants.COLOR_IDS:
		print("COLOR %s %d %.4f" % [id, int(colors[id]), float(colors[id]) / float(CATCHES)])
	for fish in fishes:
		var id := str(fish.get("id", ""))
		var row: Dictionary = stats.get(id, {})
		var n := int(row.get("n", 0))
		if n <= 0:
			print("WEIGHT %s %s n=0" % [id, str(fish.get("weight_class", ""))])
			continue
		print("WEIGHT %s %s n=%d min=%.2f mean=%.2f max=%.2f" % [
			id, str(fish.get("weight_class", "")), n,
			float(row["min"]), float(row["sum"]) / float(n), float(row["max"]),
		])
	var total := 0
	var worst := 0
	for _t in TRIALS:
		var seen: Array = []
		var pulls := 0
		while not FishVariants.mastery_ready(seen) and pulls < 500:
			var roll := FishVariants.roll(seen, rng)
			var found: Dictionary = FishVariants.discover(seen, str(roll.get("size", "")), str(roll.get("color", "")))
			seen = found.get("seen", seen)
			pulls += 1
		total += pulls
		worst = maxi(worst, pulls)
	var mean := float(total) / float(TRIALS)
	print("MASTERY trials %d mean %.2f worst %d" % [TRIALS, mean, worst])
	var sample: Dictionary = fishes[0].duplicate(true)
	var base_time := float(sample.get("fight_time", 1.0))
	var base_pull := float(sample.get("pull", 1.0))
	FishVariants.apply_fight(sample, "giant")
	print("FIGHT giant time %.3f pull %.3f" % [float(sample["fight_time"]) / base_time, float(sample["pull"]) / base_pull])
	sample = fishes[0].duplicate(true)
	base_time = float(sample.get("fight_time", 1.0))
	base_pull = float(sample.get("pull", 1.0))
	FishVariants.apply_fight(sample, "small")
	print("FIGHT small time %.3f pull %.3f" % [float(sample["fight_time"]) / base_time, float(sample["pull"]) / base_pull])
	if mean <= 80.0:
		print("VARIANT_SIM_OK")
		quit(0)
	else:
		print("VARIANT_SIM_SLOW")
		quit(1)
