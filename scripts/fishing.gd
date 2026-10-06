extends Node
## Fase 1: pesca jugable. Máquina de estados + datos + guardado.
## Estados: IDLE -> CAST -> WAIT -> BITE -> REEL -> CATCH | ESCAPE.
## Los visuales (línea, flotador, salpicadura) y la UI viven en commits
## posteriores; esta máquina expone señales y métodos públicos para ellos.

enum State { IDLE, CAST, WAIT, BITE, REEL, CATCH, ESCAPE }

const SAVE_PATH := "user://save.json"
const DB_PATH := "res://data/fish_db.json"

## Pose del gato por estado (texturas: idle/cast/wait/catch).
const POSE_FOR_STATE := {
	State.IDLE: "idle",
	State.CAST: "cast",
	State.WAIT: "wait",
	State.BITE: "wait",
	State.REEL: "cast",
	State.CATCH: "catch",
	State.ESCAPE: "idle",
}

@export var wait_min: float = 2.0
@export var wait_max: float = 6.0
@export var bite_window: float = 1.5
@export var cast_time: float = 0.8
@export var reel_need: float = 3.0
@export var reel_limit: float = 10.0
@export var marker_up: float = 0.9
@export var marker_down: float = 0.7
## Punto del agua donde cae el flotador (mundo).
@export var bobber_pos: Vector3 = Vector3(1.8, 0.15, 2.2)
## Punta de la caña (mundo, aprox. sobre el sprite).
@export var rod_tip: Vector3 = Vector3(1.2, 1.55, 0.28)

signal state_changed(new_state: int)

var state: int = State.IDLE
var fishes: Array = []
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

@onready var _cat: Node3D = $"../Cat"
@onready var _cam: Camera3D = $"../Camera3D"


func _ready() -> void:
	_load_db()
	_load_game()
	_enter(State.IDLE)


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
	state = s
	_t_state = 0.0
	_apply_pose()
	state_changed.emit(state)


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
	var rarity := int(current_fish.get("rarity", 0))
	zone_half = 0.16 - float(rarity) * 0.02
	zone_speed = 0.5 + float(rarity) * 0.45
	zone_center = 0.5
	_zone_phase = 0.0


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
