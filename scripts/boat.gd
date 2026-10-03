extends Node3D
## Bote amarrado: mecida suave (subida/bajada ~3 cm, giro leve, ciclo ~4 s).

@export_range(0.0, 0.1, 0.005) var bob_height: float = 0.03
@export_range(0.0, 8.0, 0.5) var rock_deg: float = 2.0
@export_range(1.0, 10.0, 0.5) var period: float = 4.0

var _t: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y


func _process(delta: float) -> void:
	_t += delta
	var ph: float = _t * TAU / period
	position.y = _base_y + sin(ph) * bob_height
	rotation.z = deg_to_rad(rock_deg) * sin(ph + 0.7)
	rotation.x = deg_to_rad(rock_deg * 0.6) * sin(ph * 0.5)
