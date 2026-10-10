extends Node
## Fase 1: pesca jugable. Máquina de estados + datos + guardado.
## Estados: IDLE -> CAST -> WAIT -> BITE -> REEL -> CATCH | ESCAPE.
## Los visuales (línea, flotador, salpicadura) y la UI viven en commits
## posteriores; esta máquina expone señales y métodos públicos para ellos.

enum State { IDLE, CAST, WAIT, BITE, REEL, CATCH, ESCAPE }

const SAVE_PATH := "user://save.json"
const DB_PATH := "res://data/fish_db.json"
const STRINGS_PATH := "res://data/strings.json"

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
## Vuelta a IDLE tras mostrar CATCH/ESCAPE.
const RESULT_HOLD := 1.5

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
var strings: Dictionary = {}
var current_fish: Dictionary = {}
var coins: int = 0
var caught: Dictionary = {}

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
	_load_db()
	_load_strings()
	_load_game()
	_build_visuals()
	_build_ui()
	_enter(State.IDLE)


func _build_visuals() -> void:
	_bobber = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	_bobber.mesh = sphere
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.9, 0.2, 0.2)
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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
				_wait_time = randf_range(wait_min, wait_max)
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
	if state == State.CATCH or state == State.ESCAPE:
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
	if s == State.CAST:
		_cast_target = _compute_cast_target()
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
		if state == State.BITE:
			bp.y -= 0.06
			bp.x += sin(_t_state * 30.0) * 0.03
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
	current_fish = {}
	var total := 0.0
	for f in fishes:
		total += float(f.get("weight", 1))
	var roll := randf() * total
	for f in fishes:
		roll -= float(f.get("weight", 1))
		if roll <= 0.0:
			current_fish = f
			return
	if not fishes.is_empty():
		current_fish = fishes[0]


func _setup_zone() -> void:
	var rarity := str(current_fish.get("rarity", "common"))
	var idx := int(RARITY_INDEX.get(rarity, 0))
	zone_half = 0.16 - float(idx) * 0.02
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
	var fid := str(current_fish.get("id", "sardina"))
	caught[fid] = int(caught.get(fid, 0)) + 1
	coins += int(current_fish.get("value", 0))
	_save_game()


func _load_db() -> void:
	fishes = []
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
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if typeof(data) != TYPE_DICTIONARY:
		return
	coins = int(data.get("coins", 0))
	var c = data.get("caught", {})
	if typeof(c) == TYPE_DICTIONARY:
		for k in c.keys():
			caught[str(k)] = int(c[k])


func _save_game() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Fishing: no se pudo guardar")
		return
	f.store_string(JSON.stringify({"coins": coins, "caught": caught}))


# ------------------------------------------------------------------
# Interfaz (CanvasLayer vertical, botones >= 64 px, área segura).
# ------------------------------------------------------------------

var _ui_layer: CanvasLayer
var _hud: Control
var _fishcard: Control
var _settings: Control
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
	_hud.album_pressed.connect(_on_album_stub)
	_hud.shop_pressed.connect(_on_shop_stub)
	_hud.settings_pressed.connect(_on_settings_stub)
	_fishcard = load("res://scenes/ui/fish_card.tscn").instantiate()
	_ui_layer.add_child(_fishcard)
	_fishcard.continued.connect(_on_continue)
	_settings = load("res://scenes/ui/settings_panel.tscn").instantiate()
	_ui_layer.add_child(_settings)
	_settings.lang_changed.connect(_on_lang_changed)
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
	_refresh_ui()


## Panel "Proximamente" para album/tienda hasta su fase.
func _on_album_stub() -> void:
	_hud.show_soon(SettingsData.t("album"), SettingsData.t("soon_body"))


func _on_shop_stub() -> void:
	_hud.show_soon(SettingsData.t("shop"), SettingsData.t("soon_body"))


func _on_settings_stub() -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")
	_settings.show_panel()


func _on_lang_changed() -> void:
	_refresh_ui()


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
		_fishcard.show_fish("frame_" + rarity, _fish_texture(current_fish),
			fish_text(current_fish, "name"), rarity_name(rarity),
			"+%d %s" % [int(current_fish.get("value", 0)), SettingsData.t("coins").to_lower()])
		_spawn_float_gain(int(current_fish.get("value", 0)))
	elif state == State.ESCAPE:
		_fishcard.show_escape(_make_circle_texture("556070"))
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
	lab.position = Vector2(150, 110)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.add_child(lab)
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", 30.0, 2.0)
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
