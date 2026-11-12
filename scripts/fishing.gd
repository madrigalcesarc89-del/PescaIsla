extends Node
## Fase 1: pesca jugable. Máquina de estados + datos + guardado.
## Estados: IDLE -> CAST -> WAIT -> BITE -> REEL -> CATCH | ESCAPE.
## Los visuales (línea, flotador, salpicadura) y la UI viven en commits
## posteriores; esta máquina expone señales y métodos públicos para ellos.

enum State { IDLE, CAST, WAIT, BITE, REEL, CATCH, ESCAPE }

const SAVE_PATH := "user://save.json"
const DB_PATH := "res://data/fish_db.json"
const STRINGS_PATH := "res://data/strings.json"
const FishRoll = preload("res://scripts/fish_roll.gd")
const AlbumSave = preload("res://scripts/album_save.gd")
const ShopSave = preload("res://scripts/shop_save.gd")

## Índice de rareza para la zona de recogida (ancho).
const RARITY_INDEX := {"common": 0, "uncommon": 1, "rare": 2, "legendary": 3}
## Velocidad base de la zona; se multiplica por `difficulty` del pez.
const ZONE_BASE_SPEED := 0.9

## Pose del gato por estado (texturas disponibles: idle/cast/wait/catch).
## BITE/REEL/ESCAPE reutilizan poses como MARCADORES hasta tener arte propio
## (ver source/gato/: bite, reel, fail, celebrate — estilo distinto, sin integrar).
const POSE_FOR_STATE := {
	State.IDLE: "idle",
	State.CAST: "cast",
	State.WAIT: "wait",
	State.BITE: "bite",
	State.REEL: "reel",
	State.CATCH: "celebrate",
	State.ESCAPE: "fail",
}
## Vuelta a IDLE tras el aviso de ESCAPE (la tarjeta de CATCH
## permanece hasta que el jugador la toque, 20c).
const RESULT_HOLD := 1.8

@export var wait_min: float = 2.0
@export var wait_max: float = 6.0
@export var bite_window: float = 1.5
@export var cast_time: float = 0.8
@export var reel_need: float = 3.0
@export var reel_limit: float = 10.0
@export var marker_up: float = 0.9
@export var marker_down: float = 0.7
## Punto del agua donde cae el flotador (mundo).
## Reserva como fallback; en cada lanzamiento se recalcula con un rayo
## desde el punto de pantalla CAST_SCREEN contra el plano del agua (18c).
@export var bobber_pos: Vector3 = Vector3(1.8, 0.15, 2.2)
## Objetivo del lanzamiento en pantalla (68 % ancho, 87 % alto):
## agua abierta en todas las proporciones, margenes >=12 % a cada borde.
const CAST_SCREEN := Vector2(0.68, 0.87)
## Marron calido translucido de la linea (#5A3D2B al 85 %).
const LINE_COLOR := Color(0.353, 0.239, 0.169, 0.85)

## Punta de la caña por pose, en píxeles de su textura (medido).
## idle es un punto virtual fuera del lienzo que reproduce la
## alineación 17.0; celebrate no tiene caña (sin entrada = sin línea).
const ROD_TIP_PX := {
	"idle": Vector2(738, 132),
	"cast": Vector2(698, 0),
	"wait": Vector2(740, 3),
	"catch": Vector2(618, 5),
	"bite": Vector2(708, 134),
	"reel": Vector2(716, 4),
	"fail": Vector2(606, 3),
}

signal state_changed(new_state: int)

var state: int = State.IDLE
var fishes: Array = []
var _db: Dictionary = {}
var strings: Dictionary = {}
var current_fish: Dictionary = {}
var coins: int = 0
var caught: Dictionary = {}
## Primera fecha (YYYY-MM-DD) por id. Vacía si el guardado viejo no la traía.
var _first_caught: Dictionary = {}
## Premios de rareza ya cobrados. Ausente en guardados viejos = false.
var _claimed: Dictionary = {}
## Conteos ya vistos en el álbum. seen_missing: el JSON viejo no tenía la clave.
var _album_seen: Dictionary = {}
var _seen_missing: bool = true
var _claim_busy := false
## Rachas de mala suerte. Ausentes en guardados viejos: se leen como 0.
var _dry_rare: int = 0
var _dry_legend: int = 0
## Claves ajenas del JSON de guardado, para no borrarlas al reescribir.
var _save_rest: Dictionary = {}
var _shop_state: Dictionary = {}
var _cast_gear: Dictionary = {}
var _gained: int = 0

var marker: float = 0.0
var holding: bool = false
var zone_center: float = 0.5
var zone_half: float = 0.15
var zone_speed: float = 0.6
var reel_progress: float = 0.0

var _t_state: float = 0.0
var _wait_time: float = 0.0
var _zone_phase: float = 0.0

var _bobber: MeshInstance3D
var _splash: GPUParticles3D
var _line_layer: CanvasLayer
var _line: Line2D
## Punto de caida del lanzamiento actual (mundo, calculado por rayo).
var _cast_target: Vector3

@onready var _cat: Node3D = $"../Cat"
@onready var _cam: Camera3D = $"../Camera3D"


func _ready() -> void:
	SettingsData.load_all()
	SettingsData.apply_audio()
	_start_day_night()
	_load_db()
	_load_strings()
	_load_game()
	_build_visuals()
	_apply_tackle_colors()
	_build_ui()
	call_deferred("_apply_decor", "", false)
	_enter(State.IDLE)


func _build_visuals() -> void:
	_bobber = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_bobber.mesh = sphere
	var bob_shader := load("res://shaders/bobber.gdshader") as Shader
	var bmat := ShaderMaterial.new()
	bmat.shader = bob_shader
	_bobber.set_surface_override_material(0, bmat)
	_bobber.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bobber.position = bobber_pos
	_bobber.visible = false
	add_child(_bobber)
	_splash = GPUParticles3D.new()
	_splash.amount = 12
	_splash.lifetime = 0.6
	_splash.one_shot = true
	_splash.explosiveness = 0.9
	_splash.emitting = false
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, 1, 0)
	pmat.spread = 35.0
	pmat.initial_velocity_min = 1.2
	pmat.initial_velocity_max = 2.2
	pmat.gravity = Vector3(0, -6, 0)
	pmat.scale_min = 0.5
	pmat.scale_max = 1.0
	pmat.color = Color(1, 1, 1)
	_splash.process_material = pmat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var qmat := StandardMaterial3D.new()
	qmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	qmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qmat.albedo_color = Color(1, 1, 1, 0.9)
	qmat.albedo_texture = load("res://assets/textures/glow_disc.png")
	quad.material = qmat
	_splash.draw_pass_1 = quad
	_splash.position = bobber_pos
	add_child(_splash)
	_line_layer = CanvasLayer.new()
	_line_layer.layer = 5
	add_child(_line_layer)
	_line = Line2D.new()
	_line.width = 2.0
	_line.default_color = LINE_COLOR
	_line.visible = false
	_line_layer.add_child(_line)


func _apply_tackle_colors() -> void:
	if _line == null:
		return
	var rod := str(_shop_state.get("equipped_rod", "rod_bamboo"))
	var bait := str(_shop_state.get("equipped_bait", "bait_pink_worm"))
	if rod == "rod_rainbow":
		var rainbow := Gradient.new()
		rainbow.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
		rainbow.colors = PackedColorArray([
			Color(0.969, 0.631, 0.769, 0.85),
			Color(0.969, 0.718, 0.639, 0.85),
			Color(0.561, 0.796, 0.353, 0.85),
			Color(0.494, 0.714, 0.910, 0.85),
			Color(0.910, 0.757, 0.290, 0.85),
		])
		_line.gradient = rainbow
		_line.default_color = Color(1, 1, 1, 0.85)
	else:
		_line.gradient = null
		var col := Color("5A3D2B")
		if rod == "rod_coral":
			col = Color("F4A4B8")
		elif rod == "rod_cherry":
			col = Color("E86A9A")
		elif rod == "rod_moon":
			col = Color("7EB6E8")
		col.a = 0.85
		_line.default_color = col
	if _bobber == null:
		return
	var top := Color("F7A1C4")
	var bottom := Color("E07A9A")
	if bait == "bait_peach_shrimp":
		top = Color("F7B7A3")
		bottom = Color("E89A80")
	elif bait == "bait_firefly_worm":
		top = Color("D6F58A")
		bottom = Color("7CB342")
	elif bait == "bait_golden_pearl":
		top = Color("F6E27A")
		bottom = Color("C8962E")
	var mat := _bobber.get_surface_override_material(0) as ShaderMaterial
	if mat == null:
		return
	mat.set_shader_parameter("top_color", top)
	mat.set_shader_parameter("bottom_color", bottom)


func _splash_at() -> void:
	if _splash == null or _bobber == null:
		return
	_splash.global_position = _bobber.global_position
	_splash.restart()
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("splash")


func _process(delta: float) -> void:
	_t_state += delta
	match state:
		State.CAST:
			if _t_state >= cast_time:
				var wait_scale := float(_cast_gear.get("wait_mult", 1.0))
				_wait_time = randf_range(wait_min, wait_max) * wait_scale
				_enter(State.WAIT)
		State.WAIT:
			if _t_state >= _wait_time:
				_pick_fish()
				_setup_zone()
				if SettingsData.vibration:
					Input.vibrate_handheld(90)
				_enter(State.BITE)
		State.BITE:
			if _t_state >= bite_window:
				_enter(State.ESCAPE)
		State.REEL:
			_zone_phase += delta * zone_speed
			zone_center = 0.5 + 0.32 * sin(_zone_phase)
			marker = clampf(marker + (marker_up if holding else -marker_down) * delta, 0.0, 1.0)
			if absf(marker - zone_center) <= zone_half:
				reel_progress += delta
				if reel_progress >= reel_need:
					_register_catch()
					_enter(State.CATCH)
			if _t_state >= reel_limit:
				_enter(State.ESCAPE)
	if state == State.ESCAPE:
		if _t_state >= RESULT_HOLD:
			_enter(State.IDLE)
	_update_visuals(delta)
	_process_ui(delta)


## Entrada del jugador: botón ¡Pescar! (solo en IDLE).
func start_fishing() -> bool:
	if state != State.IDLE:
		return false
	_enter(State.CAST)
	return true


## Entrada del jugador: ¡Tirar! (solo en BITE, ventana de 1.5 s).
func strike() -> bool:
	if state != State.BITE:
		return false
	marker = 0.0
	reel_progress = 0.0
	_zone_phase = 0.0
	_enter(State.REEL)
	return true


## Entrada del jugador: mantener/soltar en REEL.
func set_holding(h: bool) -> void:
	holding = h


## Cierra CATCH/ESCAPE y vuelve a IDLE.
func dismiss() -> bool:
	if state != State.CATCH and state != State.ESCAPE:
		return false
	_enter(State.IDLE)
	return true


func _enter(s: int) -> void:
	var prev := state
	state = s
	_t_state = 0.0
	_apply_pose()
	if s == State.IDLE:
		_apply_tackle_colors()
	if s == State.CAST:
		_cast_target = _compute_cast_target()
		_cast_gear = ShopSave.gear(_shop_state)
		_apply_tackle_colors()
		var spent: Dictionary = ShopSave.spend(_shop_state)
		if bool(spent.get("changed", false)):
			_shop_state = spent.get("state", _shop_state)
			_sync_shop_rest()
			_save_game()
		if bool(spent.get("fallback", false)) and _hud != null:
			_hud.show_toast(SettingsData.t("shop_bait_out"))
	if _bobber != null:
		_bobber.visible = s == State.WAIT or s == State.BITE or s == State.REEL
		if _bobber.visible:
			_bobber.position = _cast_target
	if s == State.WAIT and prev == State.CAST:
		_splash_at()
	if s == State.BITE or s == State.CATCH:
		_splash_at()
	_audio_state(s)
	_refresh_ui()
	state_changed.emit(state)


## Vibracion por estado (20b): picada 90 ms, captura 60+40+60 ms.
## Nada en toques de interfaz; respeta el interruptor (on por defecto).
func _vibrate_state(s: int) -> void:
	if not SettingsData.vibration:
		return
	if s == State.CATCH:
		Input.vibrate_handheld(60)
		_catch_buzz()


func _catch_buzz() -> void:
	await get_tree().create_timer(0.1).timeout
	if SettingsData.vibration:
		Input.vibrate_handheld(60)


## Sonido del estado (19e); sin AudioManager no falla.
func _audio_state(s: int) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am == null:
		return
	if s == State.CAST:
		am.play_sfx("cast")
	elif s == State.BITE:
		am.play_sfx("bite")
	elif s == State.ESCAPE:
		am.play_sfx("fail")
	elif s == State.CATCH and not current_fish.is_empty():
		am.play_sfx("out_of_water")
		am.play_sfx("coin")
		am.play_jingle(str(current_fish.get("rarity", "common")))
	_vibrate_state(s)
	if s == State.REEL:
		am.reel_start()
	else:
		am.reel_stop()


func _update_visuals(delta: float) -> void:
	if _line == null or _cam == null:
		return
	var anchor := _rod_anchor_world()
	var has_tip := anchor.y > -50.0
	var show_line := has_tip and (state == State.WAIT or state == State.BITE or state == State.REEL or state == State.ESCAPE)
	var tip := _cam.unproject_position(anchor)
	if state == State.CAST and has_tip:
		show_line = true
		var k := clampf(_t_state / maxf(cast_time, 0.01), 0.0, 1.0)
		var target := _cam.unproject_position(_cast_target)
		_line.points = PackedVector2Array([tip, tip.lerp(target, k)])
	elif show_line and _bobber != null:
		var bp := _cast_target
		if state == State.WAIT:
			# Flote leve en espera (20g).
			bp.y += sin(_t_state * 2.5) * 0.04
		elif state == State.BITE:
			bp.y -= 0.06
			bp.x += sin(_t_state * 30.0) * 0.03
		elif state == State.REEL:
			bp.y += sin(_t_state * 9.0) * 0.015
		_bobber.position = _bobber.position.lerp(bp, minf(delta * 10.0, 1.0))
		var bend := _cam.unproject_position(_bobber.position)
		if state == State.ESCAPE:
			var mid := (tip + bend) * 0.5 + Vector2(sin(_t_state * 3.0) * 18.0, 60.0)
			_line.points = PackedVector2Array([tip, mid, bend])
		else:
			# Ligera curva: comba perpendicular del 2.5 % + vaiven suave.
			var d := bend - tip
			var n := Vector2(-d.y, d.x)
			if n.length() > 0.01:
				n = n.normalized()
			var mid2 := (tip + bend) * 0.5 + n * (d.length() * 0.025 + sin(_t_state * 2.0) * 3.0)
			_line.points = PackedVector2Array([tip, mid2, bend])
	_line.visible = show_line and not _cam.is_position_behind(anchor)


func _pose_name() -> String:
	return str(POSE_FOR_STATE.get(state, "idle"))


## Objetivo del lanzamiento: rayo desde CAST_SCREEN contra el plano del agua.
## Con stretch/expand los px de canvas son px de ventana (escala 1).
func _compute_cast_target() -> Vector3:
	if _cam == null:
		return bobber_pos
	var canvas: Vector2 = get_viewport().get_visible_rect().size
	var sp := Vector2(CAST_SCREEN.x * canvas.x, CAST_SCREEN.y * canvas.y)
	var origin := _cam.project_ray_origin(sp)
	var dir := _cam.project_ray_normal(sp)
	# Interseccion manual con el plano horizontal y=0.15 (nivel del agua).
	if absf(dir.y) < 0.0001:
		return bobber_pos
	var t := (0.15 - origin.y) / dir.y
	if t < 0.0:
		return bobber_pos
	return origin + dir * t


## Punta de la caña en el mundo SIN usar la rotación del nodo:
## el billboard la ignora al renderizar (probado: rotar el nodo no mueve nada).
## Solo traslación + escala (respiración), con offset en marco local (x der, y arriba).
func _rod_anchor_world() -> Vector3:
	if _cat == null:
		return Vector3(0.0, -100.0, 0.0)
	var spr := _cat.get_node_or_null("Sprite3D") as Sprite3D
	if spr == null or spr.texture == null:
		return Vector3(0.0, -100.0, 0.0)
	var pose := _pose_name()
	if not ROD_TIP_PX.has(pose):
		return Vector3(0.0, -100.0, 0.0)
	var tip: Vector2 = ROD_TIP_PX[pose]
	var sz := Vector2(spr.texture.get_width(), spr.texture.get_height())
	var ps := spr.pixel_size
	if ps <= 0.0:
		return Vector3(0.0, -100.0, 0.0)
	var sc: Vector3 = _cat.scale
	var local := Vector3((tip.x - sz.x * 0.5 + spr.offset.x) * ps, (sz.y * 0.5 - tip.y + spr.offset.y) * ps, 0.0)
	return spr.global_position + Vector3(local.x * sc.x, local.y * sc.y, 0.0)


func _apply_pose() -> void:
	if _cat == null or not _cat.has_method("set_pose"):
		return
	_cat.set_pose(POSE_FOR_STATE.get(state, "idle"))


func _pick_fish() -> void:
	current_fish = FishRoll.pick(fishes, caught, _dry_rare, _dry_legend, _db, randf(), _cast_gear, _phase_now())


func _phase_now() -> String:
	if _day_night != null and _day_night.has_method("phase_name"):
		return str(_day_night.call("phase_name"))
	return ""


func _setup_zone() -> void:
	var rarity := str(current_fish.get("rarity", "common"))
	var idx := int(RARITY_INDEX.get(rarity, 0))
	zone_half = (0.16 - float(idx) * 0.02) * float(_cast_gear.get("zone_mult", 1.0))
	zone_half = clampf(zone_half, 0.04, 0.42)
	zone_speed = ZONE_BASE_SPEED * float(current_fish.get("difficulty", 1.0))
	zone_center = 0.5
	_zone_phase = 0.0


## Texto de la tabla de traducción con respaldo en fish_db (idioma activo).
func fish_text(fish: Dictionary, field: String) -> String:
	var fid := str(fish.get("id", ""))
	var entry = strings.get("fish", {}).get(fid, {})
	for suffix in [SettingsData.lang, "es"]:
		if typeof(entry) == TYPE_DICTIONARY and entry.has(field + "_" + suffix):
			return str(entry[field + "_" + suffix])
	return str(fish.get(field + "_es", fish.get(field, "")))


func rarity_name(rarity: String) -> String:
	var entry = strings.get("rarities", {}).get(rarity, {})
	if typeof(entry) == TYPE_DICTIONARY:
		if entry.has(SettingsData.lang):
			return str(entry[SettingsData.lang])
		if entry.has("es"):
			return str(entry["es"])
	return rarity


func _register_catch() -> void:
	if current_fish.is_empty():
		return
	var fid := str(current_fish.get("id", ""))
	var before := int(caught.get(fid, 0))
	AlbumSave.stamp_first(_first_caught, fid, before)
	caught[fid] = before + 1
	var base_value := int(current_fish.get("value", 0))
	_gained = ShopSave.payout(base_value, _cast_gear)
	coins += _gained
	var nxt: Dictionary = FishRoll.note_catch(str(current_fish.get("rarity", "common")), _dry_rare, _dry_legend)
	_dry_rare = int(nxt.get("dry_rare", 0))
	_dry_legend = int(nxt.get("dry_legend", 0))
	_save_game()


func _load_db() -> void:
	fishes = []
	_db = {}
	if not FileAccess.file_exists(DB_PATH):
		push_warning("Fishing: falta %s" % DB_PATH)
		return
	var text := FileAccess.get_file_as_string(DB_PATH)
	var data = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		push_warning("Fishing: JSON inválido en %s" % DB_PATH)
		return
	var arr = data.get("fishes", [])
	if typeof(arr) == TYPE_ARRAY:
		fishes = arr
	_db = data


func _load_strings() -> void:
	strings = {}
	if not FileAccess.file_exists(STRINGS_PATH):
		push_warning("Fishing: falta %s" % STRINGS_PATH)
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(STRINGS_PATH))
	if typeof(data) == TYPE_DICTIONARY:
		strings = data
	else:
		push_warning("Fishing: JSON inválido en %s" % STRINGS_PATH)


func _load_game() -> void:
	coins = 0
	caught = {}
	_first_caught = {}
	_claimed = AlbumSave.empty_claimed()
	_album_seen = {}
	_seen_missing = false
	_dry_rare = 0
	_dry_legend = 0
	_save_rest = {}
	_shop_state = ShopSave.fresh_state()
	_cast_gear = ShopSave.gear(_shop_state)
	var data: Dictionary = {}
	if FileAccess.file_exists(SAVE_PATH):
		var raw = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
		if typeof(raw) == TYPE_DICTIONARY:
			data = raw
	if AlbumSave.stale_run(data):
		var fresh: Dictionary = AlbumSave.apply_fresh_run(data)
		var err := AlbumSave.atomic_write(SAVE_PATH, JSON.stringify(fresh))
		if err != OK:
			push_warning("Fishing: no se pudo reiniciar la partida (%s)" % err)
		data = fresh
		print("RUN_RESET peces 0")
	if data.is_empty():
		_sync_shop_rest()
		return
	var parsed := AlbumSave.read(data)
	coins = int(parsed.get("coins", 0))
	caught = parsed.get("caught", {})
	_first_caught = parsed.get("first_caught", {})
	_claimed = parsed.get("claimed", AlbumSave.empty_claimed())
	_album_seen = parsed.get("album_seen", {})
	_seen_missing = bool(parsed.get("seen_missing", true))
	var pity: Dictionary = parsed.get("pity", {})
	_dry_rare = maxi(0, int(pity.get("dry_rare", 0)))
	_dry_legend = maxi(0, int(pity.get("dry_legend", 0)))
	_save_rest = parsed.get("rest", {})
	_shop_state = ShopSave.normalize(_save_rest)
	_cast_gear = ShopSave.gear(_shop_state)
	_sync_shop_rest()


func _sync_shop_rest() -> void:
	ShopSave.write_into(_save_rest, _shop_state)


func _snapshot_body() -> Dictionary:
	_sync_shop_rest()
	var pity := {"dry_rare": _dry_rare, "dry_legend": _dry_legend}
	return AlbumSave.payload(coins, caught, _first_caught, _claimed, pity, _save_rest, _album_seen)


func _save_game() -> void:
	_sync_shop_rest()
	var pity := {"dry_rare": _dry_rare, "dry_legend": _dry_legend}
	var body := AlbumSave.payload(coins, caught, _first_caught, _claimed, pity, _save_rest, _album_seen)
	var err := AlbumSave.atomic_write(SAVE_PATH, JSON.stringify(body))
	if err != OK:
		push_warning("Fishing: no se pudo guardar (%s)" % err)


# ------------------------------------------------------------------
# Interfaz (CanvasLayer vertical, botones >= 64 px, área segura).
# ------------------------------------------------------------------

var _ui_layer: CanvasLayer
var _hud: Control
var _fishcard: Control
var _album: Control
var _settings: Control
var _shop: Control
var _decor: Node3D = null
var _place: Control = null
var _day_night: Node = null
var _placing := false
var _place_id := ""
var _place_x := 0.0
var _place_z := 0.0
var _place_yaw := 0.0
var _place_y := -999.0
var _place_valid := false
var _escape_label: Label


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	add_child(_ui_layer)
	_hud = load("res://scenes/ui/hud.tscn").instantiate()
	_ui_layer.add_child(_hud)
	_apply_safe_area(_hud)
	_hud.action_pressed.connect(_on_action_pressed)
	_hud.hold_down.connect(_on_hold_down)
	_hud.hold_up.connect(_on_hold_up)
	_hud.album_pressed.connect(_on_album)
	_hud.shop_pressed.connect(_on_shop_open)
	_hud.settings_pressed.connect(_on_settings_stub)
	_fishcard = load("res://scenes/ui/fish_card.tscn").instantiate()
	_ui_layer.add_child(_fishcard)
	_fishcard.continued.connect(_on_continue)
	_album = load("res://scenes/ui/album.tscn").instantiate()
	_ui_layer.add_child(_album)
	_album.claim_requested.connect(_on_album_claim)
	_album.reset_requested.connect(_on_album_reset)
	_album.unlock_requested.connect(_on_album_unlock)
	_album.repair_requested.connect(_on_album_repair)
	_album.grant_requested.connect(_on_debug_coins)
	_album.coins_set_requested.connect(_on_debug_set_coins)
	_album.shop_reset_requested.connect(_on_debug_shop_reset)
	_album.seen_committed.connect(_on_album_seen)
	_settings = load("res://scenes/ui/settings_panel.tscn").instantiate()
	_ui_layer.add_child(_settings)
	_settings.lang_changed.connect(_on_lang_changed)
	_shop = load("res://scenes/ui/shop.tscn").instantiate()
	_ui_layer.add_child(_shop)
	_shop.purchase_requested.connect(_on_shop_buy)
	_shop.equip_requested.connect(_on_shop_equip)
	_shop.place_requested.connect(_on_shop_place)
	_shop.move_requested.connect(_on_shop_move)
	_shop.remove_requested.connect(_on_shop_remove)
	_place = Control.new()
	_place.set_script(preload("res://ui/decor_place.gd"))
	_place.name = "DecorPlace"
	if _hud.theme != null:
		_place.theme = _hud.theme
	_ui_layer.add_child(_place)
	_apply_safe_area(_place)
	_place.dragged.connect(_on_place_drag)
	_place.rotate_pressed.connect(_on_place_rotate)
	_place.up_pressed.connect(_on_place_up)
	_place.down_pressed.connect(_on_place_down)
	_place.smaller_pressed.connect(_on_place_smaller)
	_place.bigger_pressed.connect(_on_place_bigger)
	_place.confirm_pressed.connect(_on_place_confirm)
	_place.cancel_pressed.connect(_on_place_cancel)
	_escape_label = Label.new()
	_escape_label.add_theme_font_size_override("font_size", 90)
	_escape_label.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
	_escape_label.add_theme_color_override("font_outline_color", Color(0.1, 0.2, 0.3))
	_escape_label.add_theme_constant_override("outline_size", 10)
	_escape_label.text = "?"
	_escape_label.size = Vector2(120, 120)
	_escape_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_escape_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_escape_label.visible = false
	_hud.add_child(_escape_label)
	_build_phase_button()
	var root := get_tree().root
	if root.has_signal("go_back_requested"):
		root.go_back_requested.connect(_on_go_back)
	_refresh_ui()


func _bind_album() -> void:
	_album.setup(fishes, caught, _first_caught, _claimed, _db, _album_seen, _seen_missing)


func _on_album_seen(seen: Dictionary) -> void:
	_album_seen = seen
	_seen_missing = false
	_save_game()


func _on_album() -> void:
	_bind_album()
	_album.open_album()


func _on_album_claim(rarity: String) -> void:
	if _claim_busy:
		return
	_claim_busy = true
	var pity := {"dry_rare": _dry_rare, "dry_legend": _dry_legend}
	var result: Dictionary = AlbumSave.commit_claim(SAVE_PATH, coins, caught, _first_caught, _claimed, pity, _save_rest, _album_seen, fishes, _db, rarity)
	if not bool(result.get("ok", false)):
		_claim_busy = false
		return
	coins = int(result["coins"])
	_claimed = result["claimed"]
	_refresh_ui()
	_bind_album()
	_album.refresh_deferred()
	_album.play_reward(int(result["added"]))
	_claim_busy = false


func _on_album_repair() -> void:
	if not OS.is_debug_build():
		return
	var pity := {"dry_rare": _dry_rare, "dry_legend": _dry_legend}
	var result: Dictionary = AlbumSave.commit_repair(SAVE_PATH, coins, caught, _first_caught, _claimed, pity, _save_rest, _album_seen, fishes, _db)
	if not bool(result.get("ok", false)):
		push_warning("Fishing: no se pudo reparar el álbum")
		return
	var extra := int(result.get("extra", 0))
	coins = int(result["coins"])
	_claimed = result["claimed"]
	print("ALBUM_REPAIR extra_coins ", extra)
	_refresh_ui()
	_bind_album()
	_album.refresh_deferred()


func _on_album_reset() -> void:
	if not OS.is_debug_build():
		return
	coins = 0
	caught = {}
	_first_caught = {}
	_claimed = AlbumSave.empty_claimed()
	_album_seen = {}
	_seen_missing = false
	_dry_rare = 0
	_dry_legend = 0
	_save_game()
	_refresh_ui()
	_album.setup(fishes, caught, _first_caught, _claimed, _db, _album_seen, _seen_missing)
	_album.open_album()


func _on_album_unlock() -> void:
	if not OS.is_debug_build():
		return
	for fish in fishes:
		var id := str(fish.get("id", ""))
		if id == "":
			continue
		if int(caught.get(id, 0)) <= 0:
			AlbumSave.stamp_first(_first_caught, id, 0)
			caught[id] = 1
	_save_game()
	_refresh_ui()
	_album.setup(fishes, caught, _first_caught, _claimed, _db, _album_seen, _seen_missing)
	_album.open_album()


func _on_go_back() -> void:
	var card_open := _fishcard != null and _fishcard.visible
	if card_open:
		return
	if _placing:
		_on_place_cancel()
		return
	var detail_open := false
	if _album != null and _album.has_method("is_detail_open"):
		detail_open = bool(_album.is_detail_open())
	var album_open := _album != null and _album.visible
	var settings_open := _settings != null and _settings.visible
	var soon_open := false
	if _hud != null and _hud.has_method("is_soon_open"):
		soon_open = bool(_hud.is_soon_open())
	var shop_confirm := false
	var shop_open := false
	if _shop != null and _shop.visible:
		shop_open = true
		if _shop.has_method("is_confirm_open"):
			shop_confirm = bool(_shop.is_confirm_open())
	var action := AlbumSave.back_action(false, detail_open, album_open, settings_open, soon_open, shop_confirm, shop_open)
	if action == "ignore":
		return
	if action == "close_detail" or action == "close_album":
		_album.consumes_back()
		return
	if action == "close_shop_confirm" or action == "close_shop":
		_shop.consumes_back()
		return
	if action == "close_settings":
		_settings.visible = false
		return
	if action == "close_soon":
		_hud.close_soon()
		return
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_on_go_back()
		get_viewport().set_input_as_handled()


func _on_shop_open() -> void:
	if _shop == null:
		return
	_shop.open_shop(coins, _shop_state)


func _on_shop_buy(id: String) -> void:
	var before := coins
	var result: Dictionary = ShopSave.buy(SAVE_PATH, _snapshot_body(), id)
	if not bool(result.get("ok", false)):
		_play_ui("deny")
		if _shop != null:
			_shop.notify(false, id, coins, _shop_state)
		return
	coins = int(result.get("coins", coins))
	_shop_state = result.get("state", _shop_state)
	_sync_shop_rest()
	_play_ui("buy")
	if _hud != null:
		_hud.animate_coins(before, coins)
	if _shop != null:
		_shop.notify(true, id, coins, _shop_state)
	if str(ShopSave.item_by_id(id).get("category", "")) == "decor":
		_start_place(id)


func _on_shop_equip(id: String) -> void:
	_shop_state = ShopSave.equip(_shop_state, id)
	_sync_shop_rest()
	_save_game()
	if state == State.IDLE:
		_apply_tackle_colors()
	if _shop != null:
		_shop.notify(true, id, coins, _shop_state)


func _on_shop_place(id: String) -> void:
	_start_place(id)


func _on_shop_move(id: String) -> void:
	_start_place(id)


func _start_place(id: String) -> void:
	if state != State.IDLE:
		if _shop != null and _shop.visible and _shop.has_method("warn"):
			_shop.warn(SettingsData.t("place_not_now"))
		return
	_ensure_decor()
	if _shop != null and _shop.visible:
		_shop.consumes_back()
	var began = _decor.call("ghost_begin", id, _shop_state)
	if typeof(began) != TYPE_DICTIONARY or not bool(began.get("ok", false)):
		if _hud != null:
			_hud.show_toast(SettingsData.t("shop_no_room"))
		return
	var info: Dictionary = began
	_placing = true
	_place_id = id
	_place_x = float(info.get("x", 0.0))
	_place_z = float(info.get("z", 0.0))
	_place_yaw = float(info.get("yaw", 0.0))
	_place_y = float(info.get("y", -999.0))
	_place_valid = bool(info.get("valid", false))
	if _place != null:
		_place.call("show_place")
		_place.call("set_status", _place_valid, str(info.get("reason", "")))
		_place.call("show_scale", float(info.get("scale", 1.0)))


func _on_place_drag(at: Vector2) -> void:
	if not _placing:
		return
	var hit := _ray_dock(at)
	if is_nan(hit.x):
		return
	_place_x = hit.x
	_place_z = hit.y
	_move_ghost()


func _on_place_rotate() -> void:
	if not _placing:
		return
	_place_yaw = fmod(_place_yaw + 45.0, 360.0)
	if _place_yaw < 0.0:
		_place_yaw += 360.0
	_move_ghost()
	_play_ui("tap")


func _on_place_up() -> void:
	if not _placing:
		return
	_step_ghost(1)
	_play_ui("tap")


func _on_place_down() -> void:
	if not _placing:
		return
	_step_ghost(-1)
	_play_ui("tap")


func _on_place_smaller() -> void:
	if not _placing:
		return
	_scale_ghost(-1)
	_play_ui("tap")


func _on_place_bigger() -> void:
	if not _placing:
		return
	_scale_ghost(1)
	_play_ui("tap")


func _scale_ghost(dir: int) -> void:
	var packed = _decor.call("ghost_scale_step", dir)
	_take_place(packed)


func _step_ghost(dir: int) -> void:
	var packed = _decor.call("ghost_step", dir)
	_take_place(packed)


func _move_ghost() -> void:
	var packed = _decor.call("ghost_move", _place_x, _place_z, _place_yaw, _place_y)
	_take_place(packed)


func _take_place(packed) -> void:
	if typeof(packed) != TYPE_DICTIONARY:
		return
	var info: Dictionary = packed
	_place_valid = bool(info.get("valid", false))
	if info.has("x"):
		_place_x = float(info["x"])
	if info.has("z"):
		_place_z = float(info["z"])
	if info.has("yaw"):
		_place_yaw = float(info["yaw"])
	if info.has("y"):
		_place_y = float(info["y"])
	if _place != null:
		_place.call("set_status", _place_valid, str(info.get("reason", "")))
		if info.has("scale"):
			_place.call("show_scale", float(info["scale"]))


func _on_place_confirm() -> void:
	if not _placing:
		return
	if not _place_valid:
		_play_ui("deny")
		return
	var pose := str(_decor.call("ghost_pose"))
	var packed = _decor.call("commit_pose", _shop_state, _place_id, pose)
	if typeof(packed) != TYPE_DICTIONARY or not bool(packed.get("ok", false)):
		_play_ui("deny")
		return
	_shop_state = packed.get("state", _shop_state)
	_sync_shop_rest()
	_save_game()
	_finish_place()
	_play_ui("tap")


func _on_place_cancel() -> void:
	if _decor != null:
		_decor.call("ghost_cancel")
	_finish_place()


func _finish_place() -> void:
	_placing = false
	_place_id = ""
	if _place != null:
		_place.visible = false


func _ray_dock(screen: Vector2) -> Vector2:
	var y := 0.68
	if _decor != null:
		y = float(_decor.call("plane_y"))
	var origin := _cam.project_ray_origin(screen)
	var dir := _cam.project_ray_normal(screen)
	if absf(dir.y) < 0.00001:
		return Vector2(NAN, NAN)
	var t := (y - origin.y) / dir.y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var p: Vector3 = origin + dir * t
	return Vector2(p.x, p.z)


func _on_shop_remove(id: String) -> void:
	if _placing and _place_id == id:
		_on_place_cancel()
	_apply_decor(id, true)
	if _shop != null:
		_shop.notify(true, id, coins, _shop_state)


func _ensure_decor() -> void:
	if _decor != null and is_instance_valid(_decor):
		return
	var node := Node3D.new()
	node.set_script(preload("res://scripts/decor_world.gd"))
	node.name = "Decoraciones"
	add_child(node)
	_decor = node


func _apply_decor(focus: String, hide_focus: bool) -> void:
	_ensure_decor()
	var before_p := JSON.stringify(_shop_state.get("decor_placed", {}))
	var before_o := JSON.stringify(_shop_state.get("decor_off", []))
	var packed = _decor.call("sync", _shop_state, focus, hide_focus)
	if typeof(packed) != TYPE_DICTIONARY:
		return
	var info: Dictionary = packed
	_shop_state = info.get("state", _shop_state)
	var after_p := JSON.stringify(_shop_state.get("decor_placed", {}))
	var after_o := JSON.stringify(_shop_state.get("decor_off", []))
	if before_p != after_p or before_o != after_o:
		_save_game()
	if bool(info.get("full", false)) and _shop != null and _shop.has_method("warn"):
		_shop.warn(SettingsData.t("shop_no_room"))


func _on_debug_coins() -> void:
	if not OS.is_debug_build():
		return
	var before := coins
	coins += 1000
	_save_game()
	if _hud != null:
		_hud.animate_coins(before, coins)
	if _shop != null and _shop.visible:
		_shop.sync_state(coins, _shop_state)


func _on_debug_set_coins(amount: int) -> void:
	if not OS.is_debug_build():
		return
	var before := coins
	coins = clampi(amount, 0, 9999999)
	_save_game()
	if _hud != null:
		_hud.animate_coins(before, coins)
	if _shop != null and _shop.visible:
		_shop.sync_state(coins, _shop_state)


func _on_debug_shop_reset() -> void:
	if not OS.is_debug_build():
		return
	_shop_state = ShopSave.fresh_state()
	_cast_gear = ShopSave.gear(_shop_state)
	_sync_shop_rest()
	_save_game()
	_apply_decor("", false)
	if state == State.IDLE:
		_apply_tackle_colors()
	if _shop != null and _shop.visible:
		_shop.sync_state(coins, _shop_state)


func _start_day_night() -> void:
	var node := Node.new()
	node.name = "DayNight"
	node.set_script(preload("res://scripts/day_night.gd"))
	add_child(node)
	_day_night = node


func _build_phase_button() -> void:
	if not OS.is_debug_build() or _hud == null:
		return
	var btn := Button.new()
	btn.name = "DebugPhase"
	btn.text = "Fase"
	btn.position = Vector2(24, 168)
	btn.custom_minimum_size = Vector2(168, 72)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 28)
	btn.pressed.connect(_on_debug_phase)
	_hud.add_child(btn)


func _on_debug_phase() -> void:
	if not OS.is_debug_build():
		return
	if _day_night != null and _day_night.has_method("skip_phase"):
		_day_night.call("skip_phase")


func _play_ui(key: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(key)


func _on_settings_stub() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")
	_settings.show_panel()


func _on_lang_changed() -> void:
	_refresh_ui()
	if _album != null and _album.visible:
		_bind_album()
		_album.reload_visible()
	if _shop != null and _shop.visible and _shop.has_method("reload_locale"):
		_shop.reload_locale()


func _apply_safe_area(c: Control) -> void:
	var vp := get_viewport().get_visible_rect().size
	var sa := DisplayServer.get_display_safe_area()
	var m := 16.0
	c.offset_left = maxf(0.0, sa.position.x) + m
	c.offset_top = maxf(0.0, sa.position.y) + m
	c.offset_right = -maxf(0.0, vp.x - sa.end.x) - m
	c.offset_bottom = -maxf(0.0, vp.y - sa.end.y) - m


func _make_circle_texture(hex_color: String, px: int = 192) -> Texture2D:
	var col := Color(hex_color)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	var r := float(px) * 0.5
	for y in range(px):
		for x in range(px):
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			if d <= r:
				var edge := clampf((r - d) / 4.0, 0.0, 1.0)
				img.set_pixel(x, y, Color(col.r, col.g, col.b, edge))
	return ImageTexture.create_from_image(img)


## Textura real del pez; círculo de color solo si falta el archivo.
func _fish_texture(fish: Dictionary) -> Texture2D:
	var tex = load(str(fish.get("texture", "")))
	if tex is Texture2D:
		return tex
	return _make_circle_texture("FFFFFF")


func _refresh_ui() -> void:
	if _hud == null:
		return
	_hud.set_coins(coins)
	_hud.set_hold_text(SettingsData.t("hold"))
	if state == State.IDLE:
		_hud.show_action(SettingsData.t("action_fish"))
		_hud.set_hint(SettingsData.t("hint_idle"))
	elif state == State.CAST:
		_hud.show_action("")
		_hud.set_hint(SettingsData.t("hint_cast"))
	elif state == State.WAIT:
		_hud.show_action("")
		_hud.set_hint(SettingsData.t("hint_wait"))
	elif state == State.BITE:
		_hud.show_action(SettingsData.t("action_strike"))
		_hud.set_hint(SettingsData.t("hint_bite"))
	elif state == State.REEL:
		_hud.show_action("")
		_hud.set_hint(SettingsData.t("hint_reel"))
	else:
		_hud.show_action("")
		_hud.set_hint("")
	_hud.show_hold(state == State.REEL)
	_hud.show_reel(state == State.REEL)
	if state == State.CATCH and not current_fish.is_empty():
		var rarity := str(current_fish.get("rarity", "common"))
		var extra := ""
		if FishRoll.more_at_night(current_fish):
			extra = SettingsData.t("fish_more_night")
		_fishcard.show_fish("frame_" + rarity, _fish_texture(current_fish),
			fish_text(current_fish, "name"), rarity_name(rarity),
			"+%d %s" % [_gained, SettingsData.t("coins").to_lower()],
			fish_text(current_fish, "description"),
			extra)
		_spawn_float_gain(_gained)
	elif state == State.ESCAPE:
		_hud.show_toast(SettingsData.t("almost"))
	else:
		_fishcard.hide_card()


func _process_ui(_delta: float) -> void:
	if _hud == null:
		return
	if state == State.BITE and _bobber != null and _line.points.size() >= 1:
		# El final de la línea ya está en coords de canvas correctas
		# (unproject_position no coincide con el stretch en este caso).
		_hud.set_bubble(_line.points[_line.points.size() - 1])
	else:
		_hud.set_bubble(Vector2(-9999.0, 0.0))
	if state == State.REEL:
		_hud.set_meter(zone_center, zone_half, marker, "%.1f / %d s" % [reel_progress, int(reel_need)])
	if state == State.ESCAPE and _line.points.size() >= 1:
		_escape_label.visible = true
		_escape_label.position = _line.points[0] + Vector2(30, -160)
	elif _escape_label != null:
		_escape_label.visible = false


## Contador temporal de monedas: "+N" que sube y se desvanece en 2 s.
func _spawn_float_gain(amount: int) -> void:
	if _hud == null or amount <= 0:
		return
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 44)
	lab.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lab.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
	lab.add_theme_constant_override("outline_size", 8)
	lab.text = "+%d" % amount
	lab.position = Vector2(150, 210)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(lab)
	UiFit.fit_label(lab, 300.0, 1, 32, 44)
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", 130.0, 2.0)
	tw.tween_property(lab, "modulate:a", 0.0, 2.0)
	tw.chain().tween_callback(lab.queue_free)


func _on_action_pressed() -> void:
	if state == State.IDLE:
		start_fishing()
	elif state == State.BITE:
		strike()


func _on_hold_down() -> void:
	set_holding(true)


func _on_hold_up() -> void:
	set_holding(false)


func _on_continue() -> void:
	dismiss()
