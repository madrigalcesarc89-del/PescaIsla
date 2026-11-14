extends Node
## 20a: AudioManager (autoload) con archivos reales + sintetizador de respaldo.
## Causa del corte de musica (19e): los WAV sintetizados no tenian
## loop_mode (LOOP_DISABLED por defecto) y los OGG venian con loop=false:
## la musica (8 s) se apagaba a los segundos. Ahora todo lo que va en
## bucle tiene loop activado. Buses Master/Music/SFX/Ambient.
## La musica baja 6 dB con cada jingle y siempre vuelve a su base.
## Pausa al minimizar (foco/APP) y reanuda al volver.

const SR := 22050
const A := "res://assets/audio/"
const FILES := {
	"music_day": A + "music/mus_sunset.ogg",
	"ambient_day": A + "ambient/amb_day.ogg",
	"cast": A + "sfx/sfx_cast.wav",
	"splash": A + "sfx/sfx_splash.wav",
	"bite": A + "sfx/sfx_bite.wav",
	"out_of_water": A + "sfx/sfx_fish_out.wav",
	"fail": A + "sfx/sfx_fail.wav",
	"coin": A + "ui/ui_coin.wav",
	"buy": A + "ui/ui_buy.wav",
	"deny": A + "ui/ui_deny.wav",
	"tap": A + "ui/ui_tap.wav",
	"open": A + "ui/ui_open.wav",
	"close": A + "ui/ui_close.wav",
	"catch_common": A + "sfx/sfx_catch.wav",
	"catch_rare": A + "sfx/sfx_catch_rare.wav",
	"catch_legendary": A + "sfx/sfx_catch_legend.wav",
	"reel_tense": A + "sfx/sfx_reel_tense.wav",
}

var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _reel_player: AudioStreamPlayer
var _jingle_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _music_spare: AudioStreamPlayer
var _ambient_spare: AudioStreamPlayer
var _music_i := 0
var _amb_i := 0
var _music_path := ""
var _amb_path := ""
var _music_tw: Tween = null
var _amb_tw: Tween = null
var _music_base_db := -14.0
var _duck_tw: Tween = null
const FADE_SEC := 4.0


func _ready() -> void:
	_make_buses()
	_load_files()
	_build_players()
	_music_player.play()
	_ambient_player.play()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_set_paused(true)
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_IN or what == NOTIFICATION_APPLICATION_RESUMED:
		_set_paused(false)


func _set_paused(p: bool) -> void:
	for pl in [_music_player, _music_spare, _ambient_player, _ambient_spare, _reel_player, _jingle_player] + _pool:
		if pl != null:
			(pl as AudioStreamPlayer).stream_paused = p


func _make_buses() -> void:
	for b in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.get_bus_index(b), "Master")
	set_music_volume(0.7)
	set_sfx_volume(0.9)
	_set_bus_db_safe("Ambient", -20.0)


func set_music_volume(v: float) -> void:
	_music_base_db = linear_to_db(clampf(v, 0.01, 1.0)) - 14.0
	_set_bus_db_safe("Music", _music_base_db)


func set_sfx_volume(v: float) -> void:
	_set_bus_db_safe("SFX", linear_to_db(clampf(v, 0.01, 1.0)) - 6.0)


func _set_bus_db_safe(bus_name: String, db: float) -> void:
	var bi := AudioServer.get_bus_index(bus_name)
	if bi < 0:
		return
	AudioServer.set_bus_volume_db(bi, db)


## SFX con variacion de tono +-5 %.
func play_sfx(sfx_name: String) -> void:
	if _pool.is_empty() or not _sfx.has(sfx_name):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[sfx_name]
	p.pitch_scale = randf_range(0.95, 1.05)
	p.volume_db = 0.0
	p.play()


## Tic corto y más bajo, para el aviso de un movimiento.
func play_tick() -> void:
	if _pool.is_empty() or not _sfx.has("tap"):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx["tap"]
	p.pitch_scale = 1.35
	p.volume_db = -8.0
	p.play()


func reel_start() -> void:
	if _reel_player == null or _reel_player.playing:
		return
	_reel_player.play()


func reel_stop() -> void:
	if _reel_player == null:
		return
	_reel_player.stop()


func play_jingle(rarity: String) -> void:
	if _jingle_player == null or _sfx.is_empty():
		return
	var key := "catch_" + rarity
	if not _sfx.has(key):
		if rarity == "epic":
			key = "catch_rare"
		elif rarity == "secret":
			key = "catch_legendary"
		else:
			key = "catch_common"
	if not _sfx.has(key):
		key = "catch_common"
	_jingle_player.stream = _sfx[key]
	_jingle_player.pitch_scale = 1.0
	_jingle_player.play()
	_duck_music((_sfx[key] as AudioStream).get_length())


func _duck_music(dur: float) -> void:
	if _duck_tw != null and _duck_tw.is_valid():
		_duck_tw.kill()
	_duck_tw = null
	var bi := AudioServer.get_bus_index("Music")
	if bi < 0:
		return
	AudioServer.set_bus_volume_db(bi, _music_base_db - 6.0)
	_duck_tw = create_tween()
	_duck_tw.tween_interval(dur)
	_duck_tw.tween_method(_set_bus_db.bind(bi), _music_base_db - 6.0, _music_base_db, 0.4)


func _set_bus_db(v: float, bi: int) -> void:
	AudioServer.set_bus_volume_db(bi, v)


func _load_files() -> void:
	for key in FILES.keys():
		var path: String = FILES[key]
		if ResourceLoader.exists(path):
			_sfx[key] = load(path)
		else:
			push_warning("AudioManager: falta " + path)
	# Respaldo sintetizado solo para lo que no tiene archivo.
	if not _sfx.has("catch_uncommon"):
		_sfx["catch_uncommon"] = _pcm(_melody([523.0, 659.0, 784.0], 0.13, 0.45))
	if not _sfx.has("reel_loop"):
		var w := _pcm(_reel_ticks())
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.get_data().size() / 2
		_sfx["reel_loop"] = w


func _build_players() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	_reel_player = AudioStreamPlayer.new()
	_reel_player.bus = "SFX"
	_reel_player.stream = _sfx["reel_loop"]
	add_child(_reel_player)
	_jingle_player = AudioStreamPlayer.new()
	_jingle_player.bus = "SFX"
	add_child(_jingle_player)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.stream = _sfx["music_day"]
	add_child(_music_player)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.stream = _sfx["ambient_day"]
	add_child(_ambient_player)
	_music_spare = AudioStreamPlayer.new()
	_music_spare.bus = "Music"
	_music_spare.volume_db = -40.0
	add_child(_music_spare)
	_ambient_spare = AudioStreamPlayer.new()
	_ambient_spare.bus = "Ambient"
	_ambient_spare.volume_db = -40.0
	add_child(_ambient_spare)
	_music_path = FILES["music_day"]
	_amb_path = FILES["ambient_day"]


## Fundido de 4 s entre camas. No toca el bus: el volumen de ajustes
## y la bajada del jingle siguen mandando.
func set_bed(music_path: String, amb_path: String) -> void:
	if music_path != "" and music_path != _music_path:
		_music_path = music_path
		_music_i = _fade(_music_player, _music_spare, _music_i, _music_tw, music_path)
	if amb_path != "" and amb_path != _amb_path:
		_amb_path = amb_path
		_amb_i = _fade(_ambient_player, _ambient_spare, _amb_i, _amb_tw, amb_path)


func _fade(a: AudioStreamPlayer, b: AudioStreamPlayer, idx: int, tw: Tween, path: String) -> int:
	if a == null or b == null:
		return idx
	if not ResourceLoader.exists(path):
		return idx
	var cur := a if idx == 0 else b
	var nxt := b if idx == 0 else a
	var stream := load(path)
	if stream == null:
		return idx
	if tw != null and tw.is_valid():
		tw.kill()
	var from_cur := db_to_linear(cur.volume_db) if cur.playing else 0.0
	var from_nxt := db_to_linear(nxt.volume_db) if nxt.playing else 0.0
	var same := nxt.stream == stream and nxt.playing
	if not same:
		nxt.stop()
		nxt.stream = stream
		from_nxt = 0.0
		nxt.volume_db = linear_to_db(0.0001)
		nxt.play()
	var fade := create_tween()
	fade.tween_method(_apply_fade.bind(cur, nxt, from_cur, from_nxt), 0.0, 1.0, FADE_SEC)
	fade.tween_callback(_stop_if_quiet.bind(cur))
	if a == _music_player:
		_music_tw = fade
	else:
		_amb_tw = fade
	return 1 - idx


func _apply_fade(u: float, cur: AudioStreamPlayer, nxt: AudioStreamPlayer, from_cur: float, from_nxt: float) -> void:
	if cur != null:
		cur.volume_db = linear_to_db(maxf(lerpf(from_cur, 0.0, u), 0.0001))
	if nxt != null:
		nxt.volume_db = linear_to_db(maxf(lerpf(from_nxt, 1.0, u), 0.0001))


func _stop_if_quiet(player: AudioStreamPlayer) -> void:
	if player != null and player.volume_db < -30.0:
		player.stop()


# ------------------------------------------------------------------
# Respaldo sintetizado (mono 16-bit). Solo jingle_uncommon y reel_loop.
# ------------------------------------------------------------------

func _pcm(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		data[i * 2] = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = data
	return w


func _tone(f0: float, f1: float, dur: float, vol: float, harm := 0.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / SR
		var k := float(i) / maxf(float(n - 1), 1.0)
		var f := lerpf(f0, f1, k)
		phase += TAU * f / SR
		var env := minf(float(i) / (0.01 * SR), 1.0) * pow(1.0 - k, 1.6)
		s[i] = (sin(phase) + harm * sin(phase * 2.0)) * vol * env
	return s


func _mix(parts: Array) -> PackedFloat32Array:
	var total := 0
	for p in parts:
		total = maxi(total, (p as PackedFloat32Array).size())
	var s := PackedFloat32Array()
	s.resize(total)
	for p in parts:
		var a := p as PackedFloat32Array
		for i in range(a.size()):
			s[i] += a[i]
	var peak := 0.001
	for i in range(total):
		peak = maxf(peak, absf(s[i]))
	if peak > 0.95:
		for i in range(total):
			s[i] *= 0.95 / peak
	return s


func _at(part: PackedFloat32Array, delay: float) -> PackedFloat32Array:
	var s := PackedFloat32Array()
	s.resize(int(delay * SR) + part.size())
	for i in range(part.size()):
		s[int(delay * SR) + i] = part[i]
	return s


func _reel_ticks() -> PackedFloat32Array:
	var parts: Array = []
	for i in range(8):
		parts.append(_at(_tone(2000.0, 1400.0, 0.03, 0.3), float(i) * 0.125))
	return _mix(parts)


func _melody(freqs: Array, step: float, vol: float) -> PackedFloat32Array:
	var parts: Array = []
	for i in range(freqs.size()):
		parts.append(_at(_tone(float(freqs[i]), float(freqs[i]), 0.3, vol, 0.25), float(i) * step))
	return _mix(parts)
