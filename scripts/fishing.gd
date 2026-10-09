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
## Objetivo del lanzamiento en pantalla (65 % ancho, 58 % alto):
## margenes >=12 % a cada borde en cualquier proporcion.
const CAST_SCREEN := Vector2(0.65, 0.58)
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
				Input.vibrate_handheld(200)
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
	_refresh_ui()
	state_changed.emit(state)


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


## Texto de la tabla de traducción con respaldo en fish_db.
func fish_text(fish: Dictionary, field: String) -> String:
	var fid := str(fish.get("id", ""))
	var entry = strings.get("fish", {}).get(fid, {})
	if typeof(entry) == TYPE_DICTIONARY and entry.has(field):
		return str(entry[field])
	return str(fish.get(field, ""))


func rarity_name(rarity: String) -> String:
	var entry = strings.get("rarities", {}).get(rarity, {})
	if typeof(entry) == TYPE_DICTIONARY and entry.has("es"):
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
var _ui_root: Control
var _coins_label: Label
var _hint_label: Label
var _action_btn: Button
var _hold_btn: Button
var _reel_bar: Control
var _reel_label: Label
var _card_box: CenterContainer
var _card_icon: TextureRect
var _card_title: Label
var _card_info: Label
var _bite_label: Label
var _escape_label: Label
var _bite_pulse: float = 0.0


class ReelBar:
	extends Control
	var game: Node = null

	func _draw() -> void:
		if game == null:
			return
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.1, 0.1, 0.12, 0.85))
		var zc: float = game.zone_center
		var zh: float = game.zone_half
		var zy0 := (1.0 - (zc + zh)) * size.y
		var zy1 := (1.0 - (zc - zh)) * size.y
		draw_rect(Rect2(0, zy0, size.x, zy1 - zy0), Color(0.25, 0.8, 0.35, 0.9))
		var my: float = (1.0 - float(game.marker)) * size.y
		draw_rect(Rect2(-6, my - 5, size.x + 12, 10), Color.WHITE)


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 20
	add_child(_ui_layer)
	_ui_root = Control.new()
	_ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_layer.add_child(_ui_root)
	_apply_safe_area(_ui_root)
	_coins_label = Label.new()
	_coins_label.add_theme_font_size_override("font_size", 34)
	_coins_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_coins_label.position = Vector2(24, 24)
	_coins_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_coins_label)
	_hint_label = Label.new()
	_hint_label.add_theme_font_size_override("font_size", 32)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_hint_label.position = Vector2(-400, 24)
	_hint_label.size = Vector2(800, 60)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_hint_label)
	_action_btn = Button.new()
	_action_btn.add_theme_font_size_override("font_size", 40)
	_action_btn.custom_minimum_size = Vector2(280, 110)
	_action_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_action_btn.position = Vector2(-140, -250)
	_action_btn.size = Vector2(280, 110)
	_action_btn.pressed.connect(_on_action_pressed)
	_ui_root.add_child(_action_btn)
	_hold_btn = Button.new()
	_hold_btn.add_theme_font_size_override("font_size", 36)
	_hold_btn.custom_minimum_size = Vector2(280, 128)
	_hold_btn.text = "MANTÉN"
	_hold_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_btn.position = Vector2(-140, -268)
	_hold_btn.size = Vector2(280, 128)
	_hold_btn.button_down.connect(_on_hold_down)
	_hold_btn.button_up.connect(_on_hold_up)
	_ui_root.add_child(_hold_btn)
	_reel_bar = ReelBar.new()
	_reel_bar.game = self
	_reel_bar.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_reel_bar.position = Vector2(-110, -230)
	_reel_bar.size = Vector2(60, 420)
	_reel_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_reel_bar)
	_reel_label = Label.new()
	_reel_label.add_theme_font_size_override("font_size", 32)
	_reel_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_reel_label.position = Vector2(-400, -340)
	_reel_label.size = Vector2(800, 56)
	_reel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reel_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(_reel_label)
	_card_box = CenterContainer.new()
	_card_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui_root.add_child(_card_box)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	_card_box.add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	panel.add_child(vbox)
	_card_icon = TextureRect.new()
	_card_icon.custom_minimum_size = Vector2(192, 192)
	_card_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_card_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(_card_icon)
	_card_title = Label.new()
	_card_title.add_theme_font_size_override("font_size", 46)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_card_title)
	_card_info = Label.new()
	_card_info.add_theme_font_size_override("font_size", 32)
	_card_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_card_info)
	var cont_btn := Button.new()
	cont_btn.add_theme_font_size_override("font_size", 36)
	cont_btn.custom_minimum_size = Vector2(240, 96)
	cont_btn.text = "SEGUIR"
	cont_btn.pressed.connect(_on_continue)
	var ccenter := CenterContainer.new()
	ccenter.add_child(cont_btn)
	vbox.add_child(ccenter)
	_bite_label = Label.new()
	_bite_label.add_theme_font_size_override("font_size", 110)
	_bite_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	_bite_label.add_theme_color_override("font_outline_color", Color(0.35, 0.2, 0.05))
	_bite_label.add_theme_constant_override("outline_size", 12)
	_bite_label.text = "!"
	_bite_label.size = Vector2(120, 140)
	_bite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bite_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bite_label.visible = false
	_ui_root.add_child(_bite_label)
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
	_ui_root.add_child(_escape_label)
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
	if _ui_root == null:
		return
	_coins_label.text = "Monedas: %d" % coins
	_action_btn.visible = state == State.IDLE or state == State.BITE
	_action_btn.disabled = state != State.IDLE and state != State.BITE
	if state == State.IDLE:
		_action_btn.text = "¡PESCAR!"
		_hint_label.text = "Toca para lanzar el anzuelo"
	elif state == State.CAST:
		_hint_label.text = "Lanzando..."
	elif state == State.WAIT:
		_hint_label.text = "Espera... atento al flotador"
	elif state == State.BITE:
		_action_btn.text = "¡TIRAR!"
		_hint_label.text = "¡PICÓ! ¡Tira ahora!"
	elif state == State.REEL:
		_hint_label.text = "Mantén el marcador en verde"
	else:
		_hint_label.text = ""
	_hold_btn.visible = state == State.REEL
	_reel_bar.visible = state == State.REEL
	_reel_label.visible = state == State.REEL
	_card_box.visible = state == State.CATCH or state == State.ESCAPE
	if state == State.CATCH and not current_fish.is_empty():
		_card_icon.texture = _fish_texture(current_fish)
		_card_title.text = fish_text(current_fish, "name_es")
		_card_info.text = "%s\n+%d monedas\n%s" % [rarity_name(str(current_fish.get("rarity", ""))), int(current_fish.get("value", 0)), fish_text(current_fish, "description_es")]
		_spawn_float_gain(int(current_fish.get("value", 0)))
	elif state == State.ESCAPE:
		_card_icon.texture = _make_circle_texture("556070")
		_card_title.text = "Se escapó..."
		_card_info.text = "Sin penalización.\n¡Prueba otra vez!"


func _process_ui(delta: float) -> void:
	if _ui_root == null:
		return
	if state == State.BITE:
		_bite_pulse += delta * 6.0
		var k := 0.75 + 0.25 * sin(_bite_pulse)
		_action_btn.modulate = Color(1, k, k)
		_bite_label.visible = _bobber != null and _line.points.size() >= 1
		if _bite_label.visible:
			# El final de la línea ya está en coords de canvas correctas
			# (unproject_position no coincide con el stretch en este caso).
			var bend := _line.points[_line.points.size() - 1]
			_bite_label.position = bend + Vector2(-60, -200)
			var s := 1.0 + 0.15 * sin(_bite_pulse * 1.5)
			_bite_label.scale = Vector2(s, s)
	elif _bite_label != null:
		_bite_label.visible = false
		_action_btn.modulate = Color.WHITE
	if state == State.REEL:
		_reel_bar.queue_redraw()
		_reel_label.text = "%.1f / %d s" % [reel_progress, int(reel_need)]
	if state == State.ESCAPE and _line.points.size() >= 1:
		_escape_label.visible = true
		_escape_label.position = _line.points[0] + Vector2(30, -160)
	elif _escape_label != null:
		_escape_label.visible = false


## Contador temporal de monedas: "+N" que sube y se desvanece en 2 s.
func _spawn_float_gain(amount: int) -> void:
	if _ui_root == null or amount <= 0:
		return
	var lab := Label.new()
	lab.add_theme_font_size_override("font_size", 44)
	lab.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lab.add_theme_color_override("font_outline_color", Color(0.3, 0.2, 0.05))
	lab.add_theme_constant_override("outline_size", 8)
	lab.text = "+%d" % amount
	lab.position = Vector2(150, 110)
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui_root.add_child(lab)
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
