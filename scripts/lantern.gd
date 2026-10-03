extends Node3D
## Farol: parpadeo leve de luz cálida + halo aditivo. Barato para móvil (sin sombras).

@export_range(0.0, 0.3, 0.01) var flicker_amount: float = 0.08
@export_range(1.0, 15.0, 0.5) var flicker_speed: float = 7.0
@export_range(0.2, 3.0, 0.1) var base_energy: float = 1.0

var _t: float = 0.0

@onready var luz: OmniLight3D = $Luz
@onready var glow: MeshInstance3D = $Glow


func _process(delta: float) -> void:
	_t += delta
	var k: float = 1.0 + flicker_amount * (0.6 * sin(_t * flicker_speed) + 0.4 * sin(_t * flicker_speed * 1.83 + 1.7))
	if luz != null:
		luz.light_energy = base_energy * k
	if glow != null:
		var s: float = 0.95 + 0.05 * k
		glow.scale = Vector3(s, s, s)
