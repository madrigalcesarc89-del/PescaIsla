extends Node3D
## Coloca en las ranuras del muelle lo que la tienda ya compró.
## No mueve los nodos que ya estaban en la escena.

const ShopSave = preload("res://scripts/shop_save.gd")

const GLOW := {
	"deco_table_lamp": 0.82,
	"deco_string_lights": 0.62,
	"deco_firepit": 0.42,
}
const MAX_GLOWS := 2

var _bb := AABB()
var _bb_ok := false


func sync(state: Dictionary, focus: String, hide_focus: bool) -> Dictionary:
	var nxt: Dictionary = ShopSave.normalize(state)
	var placed: Dictionary = (nxt["decor_placed"] as Dictionary).duplicate()
	var off: Array = (nxt["decor_off"] as Array).duplicate()
	if hide_focus and focus != "":
		if not off.has(focus):
			off.append(focus)
		placed.erase(focus)
	elif focus != "":
		off.erase(focus)
	var markers := _markers()
	var used := {}
	var keep := {}
	for key in placed.keys():
		var id := str(key)
		var slot_name := str(placed[key])
		if not markers.has(slot_name) or used.has(slot_name):
			continue
		if off.has(id):
			continue
		used[slot_name] = id
		keep[id] = slot_name
	var was_kept := keep.has(focus)
	for entry in nxt["owned"]:
		var owned_id := str(entry)
		if not _is_decor(owned_id) or keep.has(owned_id) or off.has(owned_id):
			continue
		var slot_name := _best_slot(owned_id, markers, used)
		if slot_name == "":
			continue
		keep[owned_id] = slot_name
		used[slot_name] = owned_id
	nxt["decor_placed"] = keep
	nxt["decor_off"] = off
	var bounce := focus if (focus != "" and not hide_focus and not was_kept and keep.has(focus)) else ""
	_rebuild(keep, bounce)
	var full := focus != "" and not hide_focus and _is_decor(focus) and not keep.has(focus)
	return {"state": nxt, "full": full}


func _is_decor(id: String) -> bool:
	var item := ShopSave.item_by_id(id)
	return str(item.get("category", "")) == "decor" and bool(item.get("enabled", true))


func _props() -> Node:
	var n: Node = self
	while n != null:
		var found := n.get_node_or_null("Props")
		if found != null:
			return found
		n = n.get_parent()
	return null


func _markers() -> Dictionary:
	var found := {}
	var props := _props()
	if props == null:
		return found
	for child in props.get_children():
		if child is Marker3D and str(child.name).begins_with("slot_"):
			found[str(child.name)] = child
	return found


func _best_slot(id: String, markers: Dictionary, used: Dictionary) -> String:
	var size := _model_size(id)
	var foot := maxf(size.x, size.z)
	var types: Array = []
	var raw = ShopSave.item_by_id(id).get("slot_types", [])
	if typeof(raw) == TYPE_ARRAY:
		types = raw
	var best_name := ""
	var best_score := -1.0
	for slot_name in markers.keys():
		if used.has(slot_name):
			continue
		var marker := markers[slot_name] as Marker3D
		var max_size := float(marker.get_meta("max_size", 0.5))
		var sc := 1.0
		if foot > 0.001:
			sc = minf(1.0, max_size / foot)
		var bonus := 0.0
		if types.has(str(marker.get_meta("slot_type", ""))):
			bonus = 0.03
		var score := sc + bonus + marker.position.z * 0.01
		if score > best_score:
			best_score = score
			best_name = str(slot_name)
	return best_name


func _model_size(id: String) -> Vector3:
	var path := str(ShopSave.item_by_id(id).get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return Vector3.ONE
	var packed := load(path) as PackedScene
	if packed == null:
		return Vector3.ONE
	var inst := packed.instantiate()
	_bb_ok = false
	_acc(inst, Transform3D.IDENTITY)
	inst.free()
	if not _bb_ok:
		return Vector3.ONE
	return _bb.size


func _rebuild(placed: Dictionary, bounce_id: String) -> void:
	var markers := _markers()
	for slot_name in markers.keys():
		var marker := markers[slot_name] as Node
		for child in marker.get_children():
			if str(child.name).begins_with("placed_"):
				child.free()
	var glows := 0
	var ids: Array = placed.keys()
	ids.sort()
	for id in ids:
		var slot_name := str(placed[id])
		if not markers.has(slot_name):
			continue
		var marker := markers[slot_name] as Marker3D
		var path := str(ShopSave.item_by_id(str(id)).get("model", ""))
		if path == "" or not ResourceLoader.exists(path):
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate()
		inst.name = "placed_" + str(id)
		_quiet(inst)
		var size := _model_size(str(id))
		var foot := maxf(size.x, size.z)
		var max_size := float(marker.get_meta("max_size", 0.5))
		var sc := 1.0
		if foot > 0.001:
			sc = minf(1.0, max_size / foot)
		_bb_ok = false
		_acc(inst, Transform3D.IDENTITY)
		var bottom := 0.0
		if _bb_ok:
			bottom = _bb.position.y
		inst.scale = Vector3.ONE * sc
		inst.position = Vector3(0.0, -bottom * sc, 0.0)
		marker.add_child(inst)
		if GLOW.has(str(id)) and glows < MAX_GLOWS:
			var light := OmniLight3D.new()
			light.name = "placed_glow"
			light.shadow_enabled = false
			light.omni_range = 1.6
			light.light_energy = 0.55
			light.light_color = Color(1.0, 0.75, 0.42)
			light.position = Vector3(0.0, size.y * float(GLOW[str(id)]), 0.0)
			inst.add_child(light)
			glows += 1
		if str(id) == bounce_id:
			var target: Vector3 = inst.scale
			inst.scale = target * 0.2
			var tw := create_tween()
			tw.tween_property(inst, "scale", target, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _quiet(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in n.get_children():
		_quiet(child)


func _acc(n: Node, parent_xf: Transform3D) -> void:
	var xf: Transform3D = parent_xf * n.transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var local := (n as MeshInstance3D).mesh.get_aabb()
		for i in 8:
			var p: Vector3 = xf * local.get_endpoint(i)
			if not _bb_ok:
				_bb = AABB(p, Vector3.ZERO)
				_bb_ok = true
			else:
				_bb = _bb.expand(p)
	for child in n.get_children():
		_acc(child, xf)
