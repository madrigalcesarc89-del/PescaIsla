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
}
@export_range(0.5, 4.0, 0.1) var breath_speed: float = 2.0
@export_range(0.0, 0.08, 0.005) var breath_amount: float = 0.02

## Textura por pose (versiones defringe, igual que la escena).
const POSE_TEXTURES := {
	"idle": "res://assets/cat/defringe/idle.png",
	"cast": "res://assets/cat/defringe/cast.png",
	"wait": "res://assets/cat/defringe/wait.png",
	"catch": "res://assets/cat/defringe/catch.png",
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
