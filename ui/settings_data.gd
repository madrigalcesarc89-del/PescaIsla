class_name SettingsData
extends RefCounted
## Preferencias en user://settings.json (musica, efectos, vibracion, idioma, hora).

const PATH := "user://settings.json"

static var music := 0.7
static var sfx := 0.9
static var vibration := true
static var lang := "es"
static var time_mode := "cycle"
static var relaxed := false

static var _strings: Dictionary = {}


static func load_all() -> void:
	_strings = JSON.parse_string(FileAccess.get_file_as_string("res://data/strings.json"))
	if typeof(_strings) != TYPE_DICTIONARY:
		_strings = {}
	if not FileAccess.file_exists(PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if typeof(d) != TYPE_DICTIONARY:
		return
	music = clampf(float(d.get("music", music)), 0.0, 1.0)
	sfx = clampf(float(d.get("sfx", sfx)), 0.0, 1.0)
	vibration = bool(d.get("vibration", vibration))
	var l := str(d.get("lang", lang))
	lang = l if l in ["es", "en"] else "es"
	var mode := str(d.get("time_mode", "cycle"))
	time_mode = mode if mode in ["cycle", "clock"] else "cycle"
	relaxed = bool(d.get("relaxed", false))


static func save_all() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"music": music,
		"sfx": sfx,
		"vibration": vibration,
		"lang": lang,
		"time_mode": time_mode,
		"relaxed": relaxed,
	}))


static func apply_audio() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var am = tree.root.get_node_or_null("AudioManager")
	if am == null:
		return
	am.set_music_volume(music)
	am.set_sfx_volume(sfx)


## Texto UI con respaldo en espanol.
static func t(key: String) -> String:
	var e = (_strings.get("ui", {}) as Dictionary).get(key, {})
	if typeof(e) == TYPE_DICTIONARY:
		if (e as Dictionary).has(lang):
			return str((e as Dictionary)[lang])
		if (e as Dictionary).has("es"):
			return str((e as Dictionary)["es"])
	return key
