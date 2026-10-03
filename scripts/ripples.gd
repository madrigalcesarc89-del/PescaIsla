extends Node3D
## Ondas: anillos tenues con fade rápido + destellos de sol. Todo aditivo y pequeño.

@export_range(0.6, 3.0, 0.1) var ring_period: float = 1.4
@export_range(0.5, 2.5, 0.1) var ring_max: float = 1.3
@export_range(0.0, 0.8, 0.05) var ring_alpha: float = 0.25

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	var i: int = 0
	for c in get_children():
		if not (c is MeshInstance3D):
			continue
		if c.name.begins_with("Ring"):
			var ph: float = fmod(_t / ring_period + float(i) * 0.37, 1.0)
			var s: float = lerpf(0.3, ring_max, ph)
			c.scale = Vector3(s, 1.0, s)
			var m: Material = (c as MeshInstance3D).get_surface_override_material(0)
			if m is StandardMaterial3D:
				var col: Color = (m as StandardMaterial3D).albedo_color
				col.a = ring_alpha * (1.0 - ph)
				(m as StandardMaterial3D).albedo_color = col
		elif c.name.begins_with("Glint"):
			var k: float = 0.7 + 0.3 * sin(_t * 3.0 + float(i) * 1.7)
			c.scale = Vector3(k, 1.0, k)
		i += 1
