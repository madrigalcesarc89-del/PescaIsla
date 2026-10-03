@tool
extends Node3D
## Rig de cámara diorama para PescaIsla.
## Ajusta el encuadre desde el Inspector sin tocar la escena.
## Ángulo por defecto ~-28° (ligeramente desde arriba).

@export var cam_target: Vector3 = Vector3(0.0, 1.5, 0.0)
@export_range(4.0, 25.0, 0.1) var cam_distance: float = 8.0
@export_range(-60.0, -10.0, 0.5) var cam_angle_deg: float = -16.0
@export_range(-5.0, 5.0, 0.1) var cam_side_offset: float = 0.0
@export_range(20.0, 50.0, 0.5) var cam_fov: float = 36.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_update_camera()


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		_update_camera()


func _update_camera() -> void:
	if camera == null:
		camera = get_node_or_null("Camera3D")
		if camera == null:
			return
	var pitch: float = deg_to_rad(cam_angle_deg)
	var h: float = cam_distance * sin(-pitch)
	var d: float = cam_distance * cos(pitch)
	camera.position = cam_target + Vector3(cam_side_offset, h, d)
	camera.look_at(cam_target, Vector3.UP)
	camera.fov = cam_fov
	camera.current = true
