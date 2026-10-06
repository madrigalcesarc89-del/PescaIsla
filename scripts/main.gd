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
## Muestra un contador de FPS (para pruebas en celular). Activo en compilación de prueba.
@export var show_fps: bool = true

var _fps_label: Label
var _fps_timer: float = 0.0

@onready var camera: Camera3D = $Camera3D


func _ready() -> void:
	_update_camera()
	if not Engine.is_editor_hint():
		var layer := CanvasLayer.new()
		layer.layer = 10
		add_child(layer)
		_fps_label = Label.new()
		_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_fps_label.visible = show_fps
		layer.add_child(_fps_label)
		_update_fps_text()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_update_camera()
		return
	if _fps_label != null:
		_fps_label.visible = show_fps
		if show_fps:
			_fps_timer += delta
			if _fps_timer >= 0.5:
				_fps_timer = 0.0
				_update_fps_text()


func _update_fps_text() -> void:
	if _fps_label == null:
		return
	var fps: float = float(Engine.get_frames_per_second())
	var ms: float = 1000.0 / maxf(fps, 1.0)
	_fps_label.text = "FPS: %d | %.1f ms" % [int(fps), ms]


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
