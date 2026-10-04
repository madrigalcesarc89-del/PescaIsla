extends Node3D
## Farol: parpadeo leve de luz cálida + halo aditivo. Barato para móvil (sin sombras).

@export_range(0.0, 0.3, 0.01) var flicker_amount: float = 0.12
@export_range(1.0, 15.0, 0.5) var flicker_speed: float = 7.0
@export_range(0.2, 3.0, 0.1) var base_energy: float = 1.35

var _t: float = 0.0

@onready var luz: OmniLight3D = $Luz
@onready var glow: MeshInstance3D = $Glow


func _process(delta: float) -> void:
	_t += delta
	# Parpadeo orgánico: 3 senos inconmensurables (brisa + filamento).
	var k: float = 1.0 + flicker_amount * (0.5 * sin(_t * flicker_speed) + 0.3 * sin(_t * flicker_speed * 1.83 + 1.7) + 0.2 * sin(_t * 2.3 + 4.1))
	if luz != null:
		luz.light_energy = base_energy * k
	if glow != null:
		# Halo por alfa, sin tocar la escala (Paso 11: no scales).
		var m: Material = glow.get_surface_override_material(0)
		if m is StandardMaterial3D:
			var col: Color = (m as StandardMaterial3D).albedo_color
			col.a = clampf(0.9 * k, 0.0, 1.0)
			(m as StandardMaterial3D).albedo_color = col
