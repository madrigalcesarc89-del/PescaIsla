extends Node3D
## Gato chibi HD-2D: Sprite3D billboard + respiración sutil en idle.
## Texturas recortadas en assets/cat/ (originales en originals/), altura máx 768px.
## Import recomendado: filtro Lineal + mipmaps, alpha Opaque Pre-Pass.
## Ajusta cada pose a ojo con pose_scale sin tocar la escena.

@export var pose_scale: Dictionary = {
	"idle": Vector3.ONE,
	"cast": Vector3.ONE,
	"wait": Vector3.ONE,
	"catch": Vector3.ONE,
	"bite": Vector3.ONE,
	"reel": Vector3.ONE,
	"fail": Vector3.ONE,
	"celebrate": Vector3.ONE,
}
@export_range(0.5, 4.0, 0.1) var breath_speed: float = 2.0
@export_range(0.0, 0.08, 0.005) var breath_amount: float = 0.02
## Offset por pose en píxeles de textura (Sprite3D.offset): centra los pies
## (poses de pie/sentado) o el torso en X (catch/celebrate, en el aire) como idle.
## Medido sobre los PNG generados; corrección de rotación 7° incluida.
@export var pose_offset: Dictionary = {
	"idle": Vector2.ZERO,
	"wait": Vector2(1.3, 50.7),
	"cast": Vector2(21.8, 45.6),
	"bite": Vector2(20.0, 38.8),
	"reel": Vector2(-164.7, -15.2),
	"fail": Vector2(-118.3, 12.8),
	"catch": Vector2(-3.5, 0.4),
	"celebrate": Vector2(-45.1, 5.7),
}

## Textura por pose (versiones defringe, igual que la escena).
const POSE_TEXTURES := {
	"idle": "res://assets/art/cat/cat_idle.png",
	"cast": "res://assets/art/cat/cat_cast.png",
	"wait": "res://assets/art/cat/cat_wait.png",
	"catch": "res://assets/art/cat/cat_catch.png",
	"bite": "res://assets/art/cat/cat_bite.png",
	"reel": "res://assets/art/cat/cat_reel.png",
	"fail": "res://assets/art/cat/cat_fail.png",
	"celebrate": "res://assets/art/cat/cat_celebrate.png",
}

var _time: float = 0.0
var _base_scale: Vector3 = Vector3.ONE
var _current_pose: String = "idle"

@onready var sprite: Sprite3D = $Sprite3D


func _ready() -> void:
	_base_scale = Vector3.ONE * _pose_factor(_current_pose)
	_apply_pose_scale(1.0)


func _process(delta: float) -> void:
	_time += delta
	# Respiración sutil: estira Y y encoge X en contrafase.
	var s: float = sin(_time * breath_speed) * breath_amount
	var k: Vector3 = _base_scale * Vector3(1.0 - s * 0.5, 1.0 + s, 1.0)
	_apply_pose_scale(k.y / _base_scale.y if _base_scale.y != 0.0 else 1.0, k)


func set_pose(pose: String) -> void:
	if not pose_scale.has(pose):
		return
	_current_pose = pose
	_base_scale = Vector3.ONE * _pose_factor(pose)
	if sprite != null and POSE_TEXTURES.has(pose):
		var tex := load(POSE_TEXTURES[pose]) as Texture2D
		if tex != null:
			sprite.texture = tex
	if sprite != null:
		sprite.offset = pose_offset.get(pose, Vector2.ZERO)


func _pose_factor(pose: String) -> Vector3:
	var v = pose_scale.get(pose, Vector3.ONE)
	if v is Vector3:
		return v
	return Vector3.ONE


func _apply_pose_scale(y_mult: float = 1.0, full: Vector3 = Vector3.ZERO) -> void:
	if sprite == null:
		return
	if full != Vector3.ZERO:
		scale = full
	else:
		scale = _base_scale * Vector3(1.0, y_mult, 1.0)
