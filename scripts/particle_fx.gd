extends Node
## Emisores leídos de data/particles.json. No toca nodos del mundo.

const DATA := "res://data/particles.json"

var _emitters: Dictionary = {}


func _ready() -> void:
	if not FileAccess.file_exists(DATA):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var tex: Texture2D = load(str(parsed.get("texture", "")))
	var presets: Dictionary = parsed.get("presets", {})
	for id in presets.keys():
		var row = presets[id]
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_emitters[str(id)] = _make(str(id), row, tex)


func play(id: String, at: Vector3, tint: Color = Color(0, 0, 0, 0)) -> void:
	var p := _node(id)
	if p == null:
		return
	p.global_position = at
	var mat := p.process_material as ParticleProcessMaterial
	if mat != null:
		var base: Color = p.get_meta("base_color")
		if tint.a > 0.01:
			var c := tint
			c.a = base.a
			mat.color = c
		else:
			mat.color = base
	if bool(p.get_meta("looping")):
		if not p.emitting:
			p.emitting = true
		return
	p.restart()


func follow(id: String, at: Vector3) -> void:
	var p := _node(id)
	if p == null or not p.emitting:
		return
	p.global_position = at


func stop(id: String) -> void:
	var p := _node(id)
	if p == null:
		return
	p.emitting = false


func preset_amount(id: String) -> int:
	var p := _node(id)
	if p == null:
		return -1
	return p.amount


func _node(id: String) -> GPUParticles3D:
	var found = _emitters.get(id)
	if found is GPUParticles3D:
		return found
	return null


func _make(id: String, row: Dictionary, tex: Texture2D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = id
	p.amount = int(row.get("amount", 8))
	p.lifetime = float(row.get("lifetime", 0.6))
	p.one_shot = bool(row.get("one_shot", true))
	p.explosiveness = float(row.get("explosiveness", 0.8))
	p.emitting = false
	p.visibility_aabb = AABB(Vector3(-1.5, -1.5, -1.5), Vector3(3, 3, 3))
	p.set_meta("looping", not p.one_shot)
	var mat := ParticleProcessMaterial.new()
	var direction: Array = row.get("direction", [0, 1, 0])
	var gravity: Array = row.get("gravity", [0, -3, 0])
	mat.direction = Vector3(float(direction[0]), float(direction[1]), float(direction[2]))
	mat.spread = float(row.get("spread", 30))
	mat.initial_velocity_min = float(row.get("velocity_min", 0.4))
	mat.initial_velocity_max = float(row.get("velocity_max", 1.0))
	mat.gravity = Vector3(float(gravity[0]), float(gravity[1]), float(gravity[2]))
	mat.scale_min = float(row.get("scale_min", 0.2))
	mat.scale_max = float(row.get("scale_max", 0.6))
	mat.damping_min = float(row.get("damping_min", 0.0))
	mat.damping_max = float(row.get("damping_max", 0.0))
	var col := Color.html(str(row.get("color", "#FFFFFF")))
	mat.color = col
	p.set_meta("base_color", col)
	p.process_material = mat
	var quad := QuadMesh.new()
	var q := float(row.get("quad", 0.08))
	quad.size = Vector2(q, q)
	var skin := StandardMaterial3D.new()
	skin.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	skin.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	skin.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	skin.albedo_color = Color(1, 1, 1, 0.92)
	if tex != null:
		skin.albedo_texture = tex
	quad.material = skin
	p.draw_pass_1 = quad
	add_child(p)
	return p
