extends Node
## 19e: AudioManager (autoload). Todo el audio se sintetiza en codigo
## (sin archivos en el repo): SFX, bucle de carrete, jingles por rareza,
## musica y ambiente en bucle. Buses Master/Music/SFX/Ambient.
## La musica baja 6 dB mientras suena un jingle.

const SR := 22050

var _sfx: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool_i := 0
var _reel_player: AudioStreamPlayer
var _jingle_player: AudioStreamPlayer
var _music_player: AudioStreamPlayer
var _ambient_player: AudioStreamPlayer
var _jingle_len := {"common": 0.5, "uncommon": 0.7, "rare": 1.1, "legendary": 1.6}


func _ready() -> void:
	_make_buses()
	_build_sfx()
	_build_players()
	_music_player.play()
	_ambient_player.play()


func _make_buses() -> void:
	for b in ["Music", "SFX", "Ambient"]:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, b)
			AudioServer.set_bus_send(AudioServer.get_bus_index(b), "Master")
	set_music_volume(0.7)
	set_sfx_volume(0.9)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Ambient"), -20.0)


func set_music_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(clampf(v, 0.01, 1.0)) - 14.0)


func set_sfx_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), linear_to_db(clampf(v, 0.01, 1.0)) - 6.0)


## SFX con variacion de tono +-5 %.
func play_sfx(sfx_name: String) -> void:
	if _pool.is_empty() or not _sfx.has(sfx_name):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	p.stream = _sfx[sfx_name]
	p.pitch_scale = randf_range(0.95, 1.05)
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
	var key := "jingle_" + rarity
	if not _sfx.has(key):
		key = "jingle_common"
	_jingle_player.stream = _sfx[key]
	_jingle_player.play()
	_duck_music(float(_jingle_len.get(rarity, 0.6)))


func _duck_music(dur: float) -> void:
	var bi := AudioServer.get_bus_index("Music")
	var base := AudioServer.get_bus_volume_db(bi)
	AudioServer.set_bus_volume_db(bi, base - 6.0)
	var tw := create_tween()
	tw.tween_interval(dur)
	tw.tween_method(_set_bus_db.bind(bi), base - 6.0, base, 0.4)


func _set_bus_db(v: float, bi: int) -> void:
	AudioServer.set_bus_volume_db(bi, v)


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
	_music_player.stream = _sfx["music_loop"]
	add_child(_music_player)
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = "Ambient"
	_ambient_player.stream = _sfx["ambient_loop"]
	add_child(_ambient_player)


# ------------------------------------------------------------------
# Sintesis (mono 16-bit): tonos con envolvente + ruido filtrado.
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


func _noise(dur: float, vol: float, smooth: float, sweep := 0.0) -> PackedFloat32Array:
	var n := int(dur * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var last := 0.0
	for i in range(n):
		var k := float(i) / maxf(float(n - 1), 1.0)
		var sm := clampf(smooth + sweep * k, 0.0, 0.999)
		last = last * sm + randf_range(-1.0, 1.0) * (1.0 - sm)
		var env := minf(float(i) / (0.02 * SR), 1.0) * pow(1.0 - k, 1.4)
		s[i] = last * vol * env * 2.0
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


func _build_sfx() -> void:
	_sfx["ui_tap"] = _pcm(_tone(880.0, 660.0, 0.07, 0.5))
	_sfx["coin"] = _pcm(_mix([_tone(990.0, 990.0, 0.09, 0.5), _at(_tone(1320.0, 1320.0, 0.28, 0.5), 0.08)]))
	_sfx["cast"] = _pcm(_noise(0.35, 0.5, 0.92, -0.25))
	_sfx["splash"] = _pcm(_mix([_noise(0.4, 0.55, 0.96), _tone(400.0, 120.0, 0.25, 0.4)]))
	_sfx["bite"] = _pcm(_mix([_tone(660.0, 990.0, 0.12, 0.5, 0.3), _at(_tone(660.0, 990.0, 0.12, 0.5, 0.3), 0.14)]))
	_sfx["out_of_water"] = _pcm(_mix([_tone(300.0, 900.0, 0.12, 0.5), _noise(0.1, 0.25, 0.8)]))
	_sfx["fail"] = _pcm(_tone(300.0, 150.0, 0.4, 0.5, 0.4))
	_sfx["reel_loop"] = _pcm(_reel_ticks())
	_sfx["jingle_common"] = _pcm(_melody([523.0, 659.0], 0.13, 0.45))
	_sfx["jingle_uncommon"] = _pcm(_melody([523.0, 659.0, 784.0], 0.13, 0.45))
	_sfx["jingle_rare"] = _pcm(_melody([523.0, 659.0, 784.0, 1047.0], 0.14, 0.45))
	_sfx["jingle_legendary"] = _pcm(_mix([_melody([392.0, 523.0, 659.0, 784.0, 1047.0, 1319.0], 0.13, 0.45), _at(_tone(2093.0, 2093.0, 0.8, 0.2), 0.5)]))
	_sfx["music_loop"] = _pcm(_music_pad())
	_sfx["ambient_loop"] = _pcm(_ambient_waves())


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


## Colchon I-IV-V-I de 8 s; frecuencias a multiplos de 0.5 Hz (bucle limpio).
func _music_pad() -> PackedFloat32Array:
	var chords := [[261.5, 329.5, 392.0], [349.0, 440.0, 523.0], [392.0, 494.0, 587.5], [261.5, 329.5, 392.0]]
	var parts: Array = []
	for c in range(4):
		for f in chords[c]:
			parts.append(_at(_pad_note(float(f)), float(c) * 2.0))
	parts.append(_at(_tone(523.0, 523.0, 0.4, 0.15), 0.0))
	parts.append(_at(_tone(659.0, 659.0, 0.4, 0.15), 2.0))
	parts.append(_at(_tone(784.0, 784.0, 0.4, 0.15), 4.0))
	parts.append(_at(_tone(1047.0, 1047.0, 0.8, 0.15), 6.0))
	return _mix(parts)


func _pad_note(freq: float) -> PackedFloat32Array:
	var n := int(2.0 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var ph1 := 0.0
	var ph2 := 0.0
	for i in range(n):
		var k := float(i) / float(n - 1)
		ph1 += TAU * freq / SR
		ph2 += TAU * freq * 2.0 / SR
		var env := sin(PI * k)
		s[i] = (sin(ph1) * 0.7 + sin(ph2) * 0.2) * 0.14 * env
	return s


## Oleaje de 4 s (2 ciclos de 0.5 Hz = bucle limpio).
func _ambient_waves() -> PackedFloat32Array:
	var n := int(4.0 * SR)
	var s := PackedFloat32Array()
	s.resize(n)
	var last := 0.0
	for i in range(n):
		var k := float(i) / float(n - 1)
		last = last * 0.985 + randf_range(-1.0, 1.0) * 0.015
		var swell := 0.5 + 0.5 * sin(TAU * 2.0 * k)
		s[i] = last * swell * 0.5
	return s
