extends Node3D
## Nubes: deriva lateral lenta con retorno suave.

@export_range(0.1, 2.0, 0.1) var drift_speed: float = 0.4
@export_range(5.0, 40.0, 1.0) var wrap_x: float = 16.0

var _t: float = 0.0


func _process(delta: float) -> void:
	_t += delta
	var i: int = 0
	for c in get_children():
		if not (c is Node3D):
			continue
		var dir: float = 1.0 if i % 2 == 0 else -1.0
		c.position.x += dir * drift_speed * delta * (0.7 + 0.3 * float(i) / 3.0)
		if c.position.x > wrap_x:
			c.position.x = -wrap_x
		elif c.position.x < -wrap_x:
			c.position.x = wrap_x
		i += 1
