extends Node
## Ciclo de amanecer, día, atardecer y noche.
## Solo cambia propiedades (color, energía, alfa). No toca transforms.

const PATH := "res://data/time_of_day.json"
const FIREFLY_MAX := 60
const GLINT_BASE := 0.6
const SPARKLE_REF := 0.35

var _data: Dictionary = {}
var _order: Array[String] = []
var _elapsed := 0.0
var _ready_ok := false
var _forced := ""
var _env: Environment
var _light: DirectionalLight3D
var _water: ShaderMaterial
var _veil: ShaderMaterial
var _cat: Sprite3D
var _lantern: Node
var _bugs: GPUParticles3D
var _sky_a: TextureRect
var _sky_b: TextureRect
var _glint: StandardMaterial3D
var _decor: Node
var _bugs_ready := false
var _tex_a := ""
var _tex_b := ""


func _ready() -> void:
	process_priority = -10
	_load()
	_bind()
	if _order.is_empty():
		return
	var start := str(_data.get("start", "sunset"))
	var at := _order.find(start)
	if at < 0:
		at = 0
	_elapsed = float(at) * _span()
	_ready_ok = true
	_apply_now()


func _process(delta: float) -> void:
	if not _ready_ok or _forced != "":
		return
	if str(SettingsData.time_mode) == "clock":
		_apply_clock()
		return
	var whole := _span() * float(_order.size())
	if whole <= 0.0:
		return
	_elapsed = fposmod(_elapsed + delta, whole)
	var idx := int(_elapsed / _span()) % _order.size()
	var p := (_elapsed - float(idx) * _span()) / _span()
	_apply_phase(_order[idx], _smooth(p))


func phase_name() -> String:
	if _forced != "":
		return _forced
	if str(SettingsData.time_mode) == "clock":
		return str(clock_at(_hour_now()).get("phase", "sunset"))
	if _order.is_empty():
		return "sunset"
	return _order[int(_elapsed / _span()) % _order.size()]


func skip_phase() -> void:
	if _order.is_empty():
		return
	var cur := phase_name()
	var i := _order.find(cur)
	if i < 0:
		i = 0
	var nxt := _order[(i + 1) % _order.size()]
	if str(SettingsData.time_mode) == "clock":
		_forced = nxt
		_apply_phase(nxt, 0.0)
		return
	_forced = ""
	_elapsed = float((i + 1) % _order.size()) * _span()
	_apply_phase(_order[(i + 1) % _order.size()], 0.0)


func debug_show(phase: String, blend: float) -> void:
	_forced = phase
	_apply_phase(phase, clampf(blend, 0.0, 1.0))


func debug_place(phase: String, seconds_in: float) -> void:
	var i := _order.find(phase)
	if i < 0:
		return
	_forced = ""
	_elapsed = float(i) * _span() + clampf(seconds_in, 0.0, _span() - 0.05)
	_apply_now()


func clear_force() -> void:
	_forced = ""


func _span() -> float:
	return maxf(1.0, float(_data.get("cycle_minutes", 10.0)) * 60.0 / float(maxi(_order.size(), 1)))


func _load() -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	_data = parsed
	_order.clear()
	var raw = _data.get("order", [])
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			_order.append(str(item))


func _world() -> Node:
	var n: Node = self
	while n != null:
		if n.get_node_or_null("WorldEnvironment") != null:
			return n
		n = n.get_parent()
	return null


func _bind() -> void:
	var main := _world()
	if main == null:
		return
	var world := main.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null:
		_env = world.environment
	_light = main.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	var water := main.get_node_or_null("Water") as MeshInstance3D
	if water != null:
		_water = water.get_surface_override_material(0) as ShaderMaterial
	var veil := main.get_node_or_null("Pulido11/Vignette") as CanvasItem
	if veil != null:
		_veil = veil.material as ShaderMaterial
	_cat = main.get_node_or_null("Cat/Sprite3D") as Sprite3D
	_lantern = main.get_node_or_null("Props/Farol")
	_bugs = main.get_node_or_null("Luciernagas") as GPUParticles3D
	if _bugs != null and not _bugs_ready:
		var was := _bugs.emitting
		_bugs.emitting = false
		_bugs.amount = FIREFLY_MAX
		_bugs.emitting = was
		_bugs_ready = true
	_sky_a = main.get_node_or_null("Fondo/Cielo") as TextureRect
	_sky_b = _make_sky_b()
	var ondas := main.get_node_or_null("Ondas")
	if ondas != null:
		for child in ondas.get_children():
			if str(child.name).begins_with("Glint") and child is MeshInstance3D:
				_glint = (child as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
				break
	_decor = main.get_node_or_null("Decoraciones")


func _make_sky_b() -> TextureRect:
	if _sky_a == null:
		return null
	var have := _sky_a.get_parent().get_node_or_null("CieloB") as TextureRect
	if have != null:
		return have
	var b := TextureRect.new()
	b.name = "CieloB"
	b.mouse_filter = _sky_a.mouse_filter
	b.texture_filter = _sky_a.texture_filter
	b.expand_mode = _sky_a.expand_mode
	b.set_script(load("res://scripts/background_fit.gd"))
	b.set("camera_path", _sky_a.get("camera_path"))
	b.set("water_far", _sky_a.get("water_far"))
	b.modulate.a = 0.0
	_sky_a.get_parent().add_child(b)
	return b


func _apply_clock() -> void:
	var info := clock_at(_hour_now())
	_apply_phase(str(info.get("phase", "sunset")), _smooth(float(info.get("p", 0.0))))


func _hour_now() -> float:
	var now := Time.get_time_dict_from_system()
	return float(now.get("hour", 0)) + float(now.get("minute", 0)) / 60.0 + float(now.get("second", 0)) / 3600.0


func clock_at(hour: float) -> Dictionary:
	var h := fposmod(hour, 24.0)
	if h >= 5.0 and h < 8.0:
		return {"phase": "dawn", "p": (h - 5.0) / 3.0}
	if h >= 8.0 and h < 17.0:
		return {"phase": "day", "p": (h - 8.0) / 9.0}
	if h >= 17.0 and h < 19.5:
		return {"phase": "sunset", "p": (h - 17.0) / 2.5}
	var t := h
	if t < 5.0:
		t += 24.0
	return {"phase": "night", "p": clampf((t - 19.5) / 9.5, 0.0, 1.0)}


func _apply_now() -> void:
	if _forced != "":
		_apply_phase(_forced, 0.0)
		return
	if str(SettingsData.time_mode) == "clock":
		_apply_clock()
		return
	var idx := int(_elapsed / _span()) % _order.size()
	var p := (_elapsed - float(idx) * _span()) / _span()
	_apply_phase(_order[idx], _smooth(p))


func _apply_phase(phase: String, blend: float) -> void:
	if _order.is_empty():
		return
	var i := _order.find(phase)
	if i < 0:
		i = 0
	var nxt := _order[(i + 1) % _order.size()]
	var a := _phase(phase)
	var b := _phase(nxt)
	var t := clampf(blend, 0.0, 1.0)
	_paint(_mix(a, b, t), a, b, t)


func _paint(v: Dictionary, a: Dictionary, b: Dictionary, t: float) -> void:
	if _light != null:
		_light.light_color = v["light_color"]
		_light.light_energy = float(v["light_energy"])
	if _env != null:
		_env.ambient_light_energy = float(v["ambient_energy"])
		_env.fog_light_color = v["fog_color"]
		_env.adjustment_contrast = float(v["grade_contrast"])
		_env.adjustment_saturation = float(v["grade_saturation"])
	if _water != null:
		_water.set_shader_parameter("horizon_color", v["horizon_color"])
		_water.set_shader_parameter("sun_glint", float(v["sparkle"]))
	if _veil != null:
		_veil.set_shader_parameter("veil_color", v["vignette"])
		_veil.set_shader_parameter("edge_amount", float(v["vignette_edge"]))
	if _cat != null:
		var tint: Color = v["cat_tint"]
		_cat.modulate = Color(tint.r, tint.g, tint.b, _cat.modulate.a)
	if _lantern != null and _lantern.get("level") != null:
		_lantern.set("level", float(v["lantern"]))
	if _bugs != null:
		var ratio := clampf(float(v["fireflies"]), 0.0, 1.0)
		_bugs.amount_ratio = ratio
		var on := ratio > 0.02
		if _bugs.emitting != on:
			_bugs.emitting = on
			if on:
				_bugs.restart()
	if _glint != null:
		var col := _glint.albedo_color
		col.a = GLINT_BASE * clampf(float(v["sparkle"]) / SPARKLE_REF, 0.0, 2.0)
		_glint.albedo_color = col
	_paint_sky(a, b, t)
	_paint_audio(a, b, t)
	var decor := _decor_node()
	if decor != null and decor.has_method("set_night_glow"):
		decor.call("set_night_glow", float(v["decor_lights"]))


func _decor_node() -> Node:
	if _decor != null and is_instance_valid(_decor):
		return _decor
	var main := _world()
	if main == null:
		return null
	_decor = main.find_child("Decoraciones", true, false)
	return _decor


func _paint_sky(a: Dictionary, b: Dictionary, t: float) -> void:
	if _sky_a == null:
		return
	var path_a := str(a.get("background", ""))
	var path_b := str(b.get("background", ""))
	if path_a != _tex_a and ResourceLoader.exists(path_a):
		_sky_a.texture = load(path_a)
		_tex_a = path_a
	_sky_a.set("seam_tex_row", float(a.get("seam_row", 1397.3)))
	_sky_a.modulate.a = 1.0
	if _sky_b == null:
		return
	if path_b != _tex_b and ResourceLoader.exists(path_b):
		_sky_b.texture = load(path_b)
		_tex_b = path_b
	_sky_b.set("seam_tex_row", float(b.get("seam_row", 1397.3)))
	_sky_b.modulate.a = t
	_sky_b.visible = t > 0.004


func _paint_audio(a: Dictionary, b: Dictionary, t: float) -> void:
	var src := a if t < 0.5 else b
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("set_bed"):
		am.call("set_bed", str(src.get("music", "")), str(src.get("ambient", "")))


func _phase(id: String) -> Dictionary:
	var all: Dictionary = _data.get("phases", {})
	var src: Dictionary = {}
	if typeof(all.get(id, {})) == TYPE_DICTIONARY:
		src = all[id]
	return {
		"background": str(src.get("background", "")),
		"seam_row": float(src.get("seam_row", 1397.3)),
		"horizon_color": _col(src.get("horizon_color", [1, 1, 1])),
		"horizon_bias": _vec(src.get("horizon_bias", [0, 0, 0])),
		"light_color": _col(src.get("light_color", [1, 1, 1])),
		"light_energy": float(src.get("light_energy", 1.0)),
		"ambient_energy": float(src.get("ambient_energy", 0.6)),
		"fog_color": _col(src.get("fog_color", [1, 1, 1])),
		"grade_contrast": float(src.get("grade_contrast", 1.0)),
		"grade_saturation": float(src.get("grade_saturation", 1.0)),
		"vignette": _col(src.get("vignette", [0.3, 0.2, 0.1])),
		"vignette_edge": float(src.get("vignette_edge", 0.08)),
		"cat_tint": _col(src.get("cat_tint", [1, 1, 1])),
		"lantern": float(src.get("lantern", 0.0)),
		"fireflies": float(src.get("fireflies", 0.0)),
		"sparkle": float(src.get("sparkle", 0.35)),
		"decor_lights": float(src.get("decor_lights", 0.0)),
		"music": str(src.get("music", "")),
		"ambient": str(src.get("ambient", "")),
	}


func _mix(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var out := a.duplicate()
	var bump := 4.0 * t * (1.0 - t)
	var bias: Vector3 = a["horizon_bias"]
	out["horizon_color"] = _lift((a["horizon_color"] as Color).lerp(b["horizon_color"], t), bias, bump)
	out["light_color"] = (a["light_color"] as Color).lerp(b["light_color"], t)
	out["fog_color"] = _lift((a["fog_color"] as Color).lerp(b["fog_color"], t), bias, bump)
	out["vignette"] = (a["vignette"] as Color).lerp(b["vignette"], t)
	out["cat_tint"] = (a["cat_tint"] as Color).lerp(b["cat_tint"], t)
	for key in ["light_energy", "ambient_energy", "grade_contrast", "grade_saturation", "vignette_edge", "lantern", "fireflies", "sparkle", "decor_lights"]:
		out[key] = lerpf(float(a[key]), float(b[key]), t)
	return out


func _lift(base: Color, bias: Vector3, bump: float) -> Color:
	return Color(
		clampf(base.r + bias.x * bump, 0.0, 1.0),
		clampf(base.g + bias.y * bump, 0.0, 1.0),
		clampf(base.b + bias.z * bump, 0.0, 1.0)
	)


func _vec(raw) -> Vector3:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return Vector3.ZERO
	var arr: Array = raw
	return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))


func _col(raw) -> Color:
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() < 3:
		return Color.WHITE
	var arr: Array = raw
	return Color(float(arr[0]), float(arr[1]), float(arr[2]))


func _smooth(p: float) -> float:
	var x := clampf(p, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)
