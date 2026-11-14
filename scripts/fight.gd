extends RefCounted
## Pelea del carrete. Los números salen de data/fight.json y del pez.
## El juego y tools/fight_sim.gd usan esta misma clase.

var center := 0.5
var half := 0.15
var marker := 0.0
var progress := 0.0
var line := 1.0
var alpha := 1.0
var elapsed := 0.0
var outcome := ""
var pattern := "drift"
var active := "drift"
var telegraph := ""
var telegraph_t := 0.0
var preview := -1.0
var preview_half := -1.0
var blink := 0.0
var warn := ""
var fight_time := 3.0
var pull := 0.8
var speed := 1.0
var zone_size := 0.3
var rarity := "common"

var _cfg: Dictionary = {}
var _pat: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _gear: Dictionary = {}
var _relaxed := false
var _dir := 1.0
var _timer := 1.0
var _mode := "go"
var _from := 0.5
var _to := 0.5
var _move_t := 0.0
var _move_dur := 0.28
var _base := 0.5
var _period := 1.9
var _phase := 0.0
var _half_scale := 1.0
var _phases: Array = []
var _phase_i := 0
var _gates: Array = []
var _shield := 0
var _lead := 0.45
var _event := 2.0
var _armed := false
var _preview_on := false
var _tele_mult := 1.0
var _drain_mult := 1.0
var _speed_mult := 1.0
var _time_mult := 1.0
var _zone_mult := 1.0
var _diff := 1.0
var _up := 0.9
var _down := 0.7
var _started := false
var _ghost_alpha := 0.12
var line_min := 1.0
var regress := 0.0


func configure(fish: Dictionary, gear: Dictionary, relaxed: bool, seed_v: int) -> void:
	_cfg = _load_cfg()
	_gear = gear
	_relaxed = relaxed
	_rng.seed = seed_v
	rarity = str(fish.get("rarity", "common"))
	var row: Dictionary = _cfg.get("by_rarity", {}).get(rarity, {})
	fight_time = float(fish.get("fight_time", row.get("fight_time", 3.0)))
	zone_size = float(fish.get("zone_size", row.get("zone_size", 0.3)))
	speed = float(fish.get("speed", row.get("speed", 1.0)))
	pull = float(fish.get("pull", row.get("pull", 0.8)))
	pattern = str(fish.get("fight", "drift"))
	if not (_cfg.get("patterns", {}) as Dictionary).has(pattern):
		pattern = "drift"
	_phases = fish.get("phases", [])
	if typeof(_phases) != TYPE_ARRAY:
		_phases = []
	_diff = float(_cfg.get("difficulty_mult", 1.0))
	var ghost_row: Dictionary = _pattern("ghost")
	_ghost_alpha = float(fish.get("ghost_alpha", ghost_row.get("alpha", 0.12)))
	_tele_mult = float(gear.get("telegraph_mult", 1.0))
	_preview_on = bool(gear.get("preview", false))
	_shield = 1 if bool(gear.get("shield", false)) else 0
	_apply_mods()
	begin()


func begin() -> void:
	outcome = ""
	progress = 0.0
	marker = 0.0
	line = 1.0
	line_min = 1.0
	regress = 0.0
	elapsed = 0.0
	alpha = 1.0
	blink = 0.0
	warn = ""
	telegraph = ""
	telegraph_t = 0.0
	preview = -1.0
	preview_half = -1.0
	_phase_i = 0
	_gates = (_pat.get("at", [0.33, 0.66]) as Array).duplicate()
	_started = true
	_boot_motion(active)
	_place_half()


func step(delta: float, holding: bool) -> void:
	if not _started or outcome != "":
		return
	var left := delta
	while left > 0.0001 and outcome == "":
		var h := minf(left, 0.05)
		_tick(h, holding)
		left -= h


func rarity_color() -> Color:
	var hex := str((_cfg.get("colors", {}) as Dictionary).get(rarity, "#7DCAA5"))
	return Color.html(hex)


func snapshot() -> Dictionary:
	return {
		"center": center,
		"half": half,
		"marker": marker,
		"progress": progress,
		"line": line,
		"alpha": alpha,
		"telegraph": telegraph,
		"preview": preview,
		"preview_half": preview_half,
		"blink": blink,
		"warn": warn,
		"pattern": pattern,
		"active": active,
		"fight_time": fight_time,
		"zone_size": zone_size * _zone_mult,
		"speed": speed * _speed_mult,
		"pull": pull,
		"rarity": rarity,
		"outcome": outcome,
	}


func _tick(dt: float, holding: bool) -> void:
	elapsed += dt
	blink += dt * 9.0
	_motion(dt)
	var up := _up * (1.0 + float(_gear.get("agility", 0.0)))
	var down := _down * (1.0 + float(_gear.get("agility", 0.0)))
	if holding:
		marker = minf(1.0, marker + up * dt)
	else:
		marker = maxf(0.0, marker - down * dt)
	var top := center + half
	var bot := center - half
	var before := progress
	if marker >= bot and marker <= top:
		progress += dt / maxf(fight_time, 0.1)
	elif marker < bot:
		var gap := bot - marker
		var far := float(_cfg.get("far_below", 0.2))
		if gap > far:
			progress -= float(_cfg.get("progress_down_far", 0.2)) * dt
		else:
			progress -= float(_cfg.get("progress_down", 0.12)) * dt
	progress = clampf(progress, 0.0, 1.0)
	if progress < before:
		regress += before - progress
	var over := float(_cfg.get("line_over", 0.05))
	if marker > top + over:
		var drain := float(_cfg.get("line_drain", 0.25)) * pull * _drain_mult
		var resist := maxf(float(_gear.get("line_strength_mult", 1.0)), 0.2)
		line -= drain / resist * dt
	else:
		line += float(_cfg.get("line_recover", 0.15)) * dt
	line = clampf(line, 0.0, 1.0)
	line_min = minf(line_min, line)
	if line <= 0.0:
		if _shield > 0:
			_shield -= 1
			line = float(_cfg.get("shield_restore", 0.4))
		else:
			outcome = "break"
			return
	if progress >= 1.0:
		outcome = "catch"
		return
	if elapsed >= float(_cfg.get("time_cap", 4.0)) * fight_time:
		outcome = "tired"
		return
	_maybe_phase()


func _apply_mods() -> void:
	_drain_mult = 1.0
	_speed_mult = _diff
	_time_mult = 1.0
	_zone_mult = float(_gear.get("zone_mult", 1.0))
	if _relaxed:
		var rel: Dictionary = _cfg.get("relaxed", {})
		_zone_mult *= float(rel.get("zone_mult", 1.3))
		_speed_mult *= float(rel.get("speed_mult", 0.8))
		_drain_mult *= float(rel.get("drain_mult", 0.7))
	active = pattern
	if pattern == "heavy":
		var h: Dictionary = _pattern("heavy")
		_zone_mult *= float(h.get("zone_mult", 1.25))
		_speed_mult *= float(h.get("speed_mult", 0.55))
		_time_mult *= float(h.get("time_mult", 1.4))
		_drain_mult *= float(h.get("drain_mult", 1.3))
		active = "drift"
	elif pattern == "phases" and _phases.size() > 0:
		active = str(_phases[0])
	_pat = _pattern(pattern)
	fight_time *= _time_mult
	_up = float(_cfg.get("marker_up", 0.9))
	_down = float(_cfg.get("marker_down", 0.7))


func _boot_motion(kind: String) -> void:
	_mode = "go"
	_half_scale = 1.0
	alpha = 1.0
	_dir = 1.0 if _rng.randf() < 0.5 else -1.0
	center = 0.5
	_base = 0.5
	_phase = _rng.randf() * TAU
	var spec := _pattern(kind if kind != "heavy" else "drift")
	_period = _rng.randf_range(float(spec.get("period_min", 1.6)), float(spec.get("period_max", 2.2)))
	_arm(kind)
	_place_half()


func _arm(kind: String) -> void:
	var spec := _pattern(kind)
	_armed = false
	telegraph = ""
	preview = -1.0
	preview_half = -1.0
	if kind == "dash":
		_event = _rng.randf_range(float(spec.get("every_min", 1.8)), float(spec.get("every_max", 3.0)))
		_lead = float(spec.get("lead", 0.45)) * _tele_mult
	elif kind == "puff":
		_event = _rng.randf_range(float(spec.get("every_min", 3.5)), float(spec.get("every_max", 5.0)))
		_lead = float(spec.get("lead", 0.5)) * _tele_mult
	elif kind == "ghost":
		_event = _rng.randf_range(float(spec.get("every_min", 4.5)), float(spec.get("every_max", 6.0)))
		_lead = float(spec.get("lead", 0.5)) * _tele_mult
	elif kind == "zigzag":
		_event = 0.0
		_start_trip(spec)
	else:
		_event = _rng.randf_range(float(spec.get("turn_min", 2.5)), float(spec.get("turn_max", 4.0)))
		_lead = 0.0


func _motion(dt: float) -> void:
	var kind := active
	if pattern == "heavy":
		kind = "drift"
	var spec := _pattern(kind)
	var sp := speed * _speed_mult
	if _mode == "pause":
		_timer -= dt
		telegraph_t = maxf(telegraph_t - dt, 0.0)
		if _timer <= 0.0:
			_mode = "go"
			warn = ""
			telegraph = ""
			preview = -1.0
			_arm(kind)
		_place_half()
		return
	if _mode == "dash":
		_move_t += dt
		var u := clampf(_move_t / maxf(_move_dur, 0.01), 0.0, 1.0)
		center = lerpf(_from, _to, u)
		if u >= 1.0:
			_mode = "go"
			telegraph = ""
			preview = -1.0
			_arm("dash")
		_place_half()
		return
	if _mode == "puff":
		_timer -= dt
		if _timer <= 0.0:
			_mode = "go"
			_half_scale = 1.0
			telegraph = ""
			_arm("puff")
		_drift(dt, float(spec.get("drift_speed", 0.18)) * sp)
		_place_half()
		return
	if _mode == "hide":
		_timer -= dt
		if _timer <= 0.0:
			_mode = "go"
			alpha = 1.0
			telegraph = ""
			_arm("ghost")
		_drift(dt, float(spec.get("drift_speed", 0.18)) * sp)
		_place_half()
		return
	if kind == "bounce":
		_phase += dt * TAU / maxf(_period, 0.2)
		_base += _dir * float(spec.get("drift_speed", 0.12)) * sp * dt
		_base = _bounce_base(_base)
		center = _base + float(spec.get("amp", 0.18)) * sin(_phase)
	elif kind == "zigzag":
		if _mode == "wait":
			_timer -= dt
			if _timer <= 0.0:
				_start_trip(spec)
		else:
			_move_t += dt
			var u2 := clampf(_move_t / maxf(_move_dur, 0.01), 0.0, 1.0)
			center = lerpf(_from, _to, u2)
			if u2 >= 1.0:
				_mode = "wait"
				_timer = _rng.randf_range(float(spec.get("pause_min", 0.25)), float(spec.get("pause_max", 0.5)))
	elif kind == "dash":
		_drift(dt, float(spec.get("drift_speed", 0.12)) * sp)
		_count_event(dt, "dash", spec)
	elif kind == "puff":
		_drift(dt, float(spec.get("drift_speed", 0.18)) * sp)
		_count_event(dt, "puff", spec)
	elif kind == "ghost":
		_drift(dt, float(spec.get("drift_speed", 0.18)) * sp)
		_count_event(dt, "ghost", spec)
	else:
		_drift(dt, float(spec.get("speed", 0.18)) * sp)
		_event -= dt
		if _event <= 0.0:
			_dir = -_dir
			_event = _rng.randf_range(float(spec.get("turn_min", 2.5)), float(spec.get("turn_max", 4.0)))
	if telegraph_t > 0.0:
		telegraph_t -= dt
		if telegraph_t <= 0.0 and _mode == "go":
			telegraph = ""
			preview = -1.0
	_place_half()


func _count_event(dt: float, kind: String, spec: Dictionary) -> void:
	_event -= dt
	if not _armed and _event <= _lead:
		_armed = true
		telegraph = kind
		telegraph_t = _lead
		if kind == "dash":
			_to = _far(float(spec.get("jump_min", 0.3)))
			if _preview_on:
				preview = _to
				preview_half = half
		elif kind == "puff" and _preview_on:
			preview = center
			preview_half = clampf(zone_size * _zone_mult * float(spec.get("scale", 0.55)) * 0.5, 0.04, 0.48)
	if _event <= 0.0:
		_fire(kind, spec)


func _fire(kind: String, spec: Dictionary) -> void:
	_armed = false
	if kind == "dash":
		_from = center
		if not _preview_on:
			_to = _far(float(spec.get("jump_min", 0.3)))
		_move_dur = float(spec.get("jump_time", 0.28))
		_move_t = 0.0
		_mode = "dash"
		telegraph = ""
		preview = -1.0
	elif kind == "puff":
		_half_scale = float(spec.get("scale", 0.55))
		_timer = float(spec.get("hold", 1.3))
		_mode = "puff"
		telegraph = ""
	elif kind == "ghost":
		alpha = _ghost_alpha
		_timer = float(spec.get("hold", 2.0))
		_mode = "hide"
		telegraph = ""


func _start_trip(spec: Dictionary) -> void:
	var dist := _rng.randf_range(float(spec.get("trip_min", 0.2)), float(spec.get("trip_max", 0.45)))
	var dir := 1.0 if _rng.randf() < 0.5 else -1.0
	_from = center
	_to = clampf(center + dir * dist, 0.05, 0.95)
	var spd := float(spec.get("speed", 0.35)) * speed * _speed_mult
	_move_dur = maxf(absf(_to - _from) / maxf(spd, 0.05), 0.05)
	_move_t = 0.0
	_mode = "go"


func _drift(dt: float, rate: float) -> void:
	# El recorte de _place_half deja el centro entre half y 1-half.
	# Si el rebote usa 0.08/0.92, la zona nunca llega y se queda pegada.
	var lo := maxf(half, 0.08)
	var hi := minf(1.0 - half, 0.92)
	if hi <= lo + 0.02:
		return
	center += _dir * rate * dt
	if center <= lo:
		center = lo
		_dir = 1.0
	elif center >= hi:
		center = hi
		_dir = -1.0


func _bounce_base(v: float) -> float:
	if v < 0.2:
		_dir = 1.0
		return 0.2
	if v > 0.8:
		_dir = -1.0
		return 0.8
	return v


func _far(min_dist: float) -> float:
	var lo := half
	var hi := 1.0 - half
	var best := center
	var best_d := 0.0
	for _i in 10:
		var p := _rng.randf_range(lo, hi)
		var d := absf(p - center)
		if d > best_d:
			best = p
			best_d = d
		if d >= min_dist:
			return p
	if absf(lo - center) >= absf(hi - center):
		return lo
	return hi


func _place_half() -> void:
	var full := zone_size * _zone_mult * _half_scale
	half = clampf(full * 0.5, 0.04, 0.48)
	var lo := half
	var hi := 1.0 - half
	if hi < lo:
		center = 0.5
		return
	center = clampf(center, lo, hi)


func _maybe_phase() -> void:
	if pattern != "phases" or _gates.is_empty() or _mode == "pause":
		return
	if progress < float(_gates[0]):
		return
	_gates.pop_front()
	_phase_i += 1
	if _phase_i < _phases.size():
		active = str(_phases[_phase_i])
	warn = "rage"
	telegraph = "rage"
	telegraph_t = float(_pat.get("lead", 0.45)) * _tele_mult
	_mode = "pause"
	_timer = float(_pat.get("pause", 1.0))
	alpha = 1.0
	_half_scale = 1.0


func _pattern(kind: String) -> Dictionary:
	var all: Dictionary = _cfg.get("patterns", {})
	var row = all.get(kind, {})
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	return row


func _load_cfg() -> Dictionary:
	if not FileAccess.file_exists("res://data/fight.json"):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/fight.json"))
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed
