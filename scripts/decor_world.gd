extends Node3D
## Muestra la decoración comprada. El jugador elige el sitio.
## No mueve los nodos que ya estaban en la escena.

const ShopSave = preload("res://scripts/shop_save.gd")

const GLOW := {
	"deco_table_lamp": 0.82,
	"deco_string_lights": 0.62,
	"deco_firepit": 0.42,
}
const MAX_GLOWS := 2
const CELL := 0.06
const CAT_AT := Vector2(0.724, 0.279)
const CAT_R := 0.36
const LANTERN := Rect2(-0.70, 0.84, 0.44, 0.48)
const LIFT_STEP := 0.28
const LIFT_SNAP := 0.12
const LIFT_MAX := 2.4

var _bb := AABB()
var _bb_ok := false
var _metrics := {}
var _mask := {}
var _mask_ready := false
var _plane := 0.68
var _shown := {}
var _obs: Array = []
var _ghost: Node3D = null
var _ghost_id := ""
var _ghost_x := 0.0
var _ghost_z := 0.0
var _ghost_yaw := 0.0
var _ghost_scale := 1.0
var _ghost_sit := 0.0
var _ghost_reason := "water"
var _ghost_valid := false


func plane_y() -> float:
	_ensure_mask()
	return _plane


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
	var keep := _valid_placed(placed, off)
	nxt["decor_placed"] = keep
	nxt["decor_off"] = off
	_shown = keep.duplicate()
	_rebuild(keep, "")
	return {"state": nxt, "full": false}


func commit_pose(state: Dictionary, id: String, pose: String) -> Dictionary:
	var nxt: Dictionary = ShopSave.normalize(state)
	if not _is_decor(id) or not (nxt["owned"] as Array).has(id):
		return {"state": nxt, "ok": false}
	var parsed := _parse_pose(pose)
	if parsed.is_empty():
		return {"state": nxt, "ok": false}
	_obs = _obstacles(nxt, id)
	var prefer := -999.0
	if parsed.has("y"):
		prefer = float(parsed["y"])
	var resolved := _resolve(id, float(parsed["x"]), float(parsed["z"]), float(parsed["yaw"]), float(parsed["scale"]), prefer)
	if str(resolved.get("reason", "")) != "ok":
		return {"state": nxt, "ok": false}
	if parsed.has("y") and absf(float(resolved.get("sit", prefer)) - prefer) > 0.05:
		return {"state": nxt, "ok": false}
	var placed: Dictionary = (nxt["decor_placed"] as Dictionary).duplicate()
	placed[id] = pose
	var off: Array = (nxt["decor_off"] as Array).duplicate()
	off.erase(id)
	var keep := _valid_placed(placed, off)
	nxt["decor_placed"] = keep
	nxt["decor_off"] = off
	_free_ghost()
	_shown = keep.duplicate()
	_rebuild(keep, id)
	return {"state": nxt, "ok": true}


func ghost_begin(id: String, state: Dictionary) -> Dictionary:
	_free_ghost()
	_ensure_mask()
	if not _is_decor(id):
		return {"ok": false}
	var nxt: Dictionary = ShopSave.normalize(state)
	_obs = _obstacles(nxt, id)
	var have := _parse_any(str((nxt["decor_placed"] as Dictionary).get(id, "")), id)
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var sc := 1.0
	if not have.is_empty():
		x = float(have["x"])
		z = float(have["z"])
		yaw = float(have["yaw"])
		sc = float(have["scale"])
	else:
		var found := _search(id)
		if not bool(found.get("ok", false)):
			return {"ok": false}
		x = float(found["x"])
		z = float(found["z"])
		yaw = float(found["yaw"])
		sc = float(found["scale"])
	var prefer := -999.0
	if have.has("y"):
		prefer = float(have["y"])
	_ghost_id = id
	_ghost_scale = sc
	_ghost = _make(id)
	if _ghost == null:
		return {"ok": false}
	_hide_current(id)
	_ghost.name = "ghost_preview"
	add_child(_ghost)
	_apply_ghost(x, z, yaw, prefer)
	return {
		"ok": true,
		"x": x,
		"z": z,
		"yaw": yaw,
		"y": _ghost_sit,
		"scale": sc,
		"valid": _ghost_valid,
		"reason": _ghost_reason,
	}


func ghost_move(x: float, z: float, yaw: float, prefer_y: float = -999.0) -> Dictionary:
	if _ghost == null:
		return {"valid": false, "reason": "water", "y": _plane}
	_apply_ghost(x, z, yaw, prefer_y)
	return {"valid": _ghost_valid, "reason": _ghost_reason, "y": _ghost_sit}


func ghost_step(dir: int) -> Dictionary:
	if _ghost == null:
		return {"valid": false, "reason": "water", "y": _plane}
	var target: float = _ghost_sit + LIFT_STEP * float(dir)
	_apply_ghost(_ghost_x, _ghost_z, _ghost_yaw, target)
	return {"valid": _ghost_valid, "reason": _ghost_reason, "y": _ghost_sit}


func ghost_pose() -> String:
	return "%.3f,%.3f,%.1f,%.3f,%.3f" % [_ghost_x, _ghost_z, _ghost_yaw, _ghost_scale, _ghost_sit]


func ghost_cancel() -> void:
	_free_ghost()
	_rebuild(_shown, "")


func _apply_ghost(x: float, z: float, yaw: float, prefer_y: float = -999.0) -> void:
	_ghost_x = x
	_ghost_z = z
	_ghost_yaw = yaw
	var resolved := _resolve(_ghost_id, x, z, yaw, _ghost_scale, prefer_y)
	_ghost_reason = str(resolved.get("reason", "water"))
	_ghost_valid = _ghost_reason == "ok"
	_ghost_sit = float(resolved.get("sit", _plane))
	var y0 := float(_metrics_of(_ghost_id).get("y0", 0.0))
	_ghost.position = Vector3(x, _ghost_sit - y0 * _ghost_scale, z)
	_ghost.rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)
	_ghost.scale = Vector3.ONE * _ghost_scale


func _free_ghost() -> void:
	if _ghost != null and is_instance_valid(_ghost):
		_ghost.free()
	_ghost = null
	_ghost_id = ""


func _hide_current(id: String) -> void:
	var node := _find_placed(id)
	if node != null:
		node.visible = false


func _find_placed(id: String) -> Node:
	var want := "placed_" + id
	var props := _props()
	if props != null:
		for child in props.get_children():
			if child is Marker3D:
				var hit := (child as Node).get_node_or_null(want)
				if hit != null:
					return hit
	return get_node_or_null(want)


func _valid_placed(placed: Dictionary, off: Array) -> Dictionary:
	var markers := _markers()
	var used := {}
	var keep := {}
	for key in placed.keys():
		var id := str(key)
		if off.has(id) or not _is_decor(id):
			continue
		var raw := str(placed[key])
		if raw.begins_with("slot_"):
			if markers.has(raw) and not used.has(raw):
				keep[id] = raw
				used[raw] = id
		elif not _parse_pose(raw).is_empty():
			keep[id] = raw
	return keep


func _parse_pose(raw: String) -> Dictionary:
	var parts := raw.split(",")
	if parts.size() < 3:
		return {}
	if not parts[0].is_valid_float() or not parts[1].is_valid_float() or not parts[2].is_valid_float():
		return {}
	var sc := 1.0
	if parts.size() >= 4 and parts[3].is_valid_float():
		sc = clampf(float(parts[3]), 0.35, 1.0)
	var parsed := {
		"x": float(parts[0]),
		"z": float(parts[1]),
		"yaw": float(parts[2]),
		"scale": sc,
	}
	if parts.size() >= 5 and parts[4].is_valid_float():
		parsed["y"] = float(parts[4])
	return parsed


func _parse_any(raw: String, id: String) -> Dictionary:
	if raw.begins_with("slot_"):
		var markers := _markers()
		if not markers.has(raw):
			return {}
		var marker := markers[raw] as Marker3D
		var size := _model_size(id)
		var foot := maxf(size.x, size.z)
		var max_size := float(marker.get_meta("max_size", 0.5))
		var sc := 1.0
		if foot > 0.001:
			sc = minf(1.0, max_size / foot)
		return {"x": marker.position.x, "z": marker.position.z, "yaw": 0.0, "scale": sc, "y": marker.position.y}
	return _parse_pose(raw)


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


func _ensure_mask() -> void:
	if _mask_ready:
		return
	_mask_ready = true
	var props := _props()
	if props == null:
		return
	var muelle := props.get_node_or_null("Muelle") as Node3D
	if muelle == null:
		return
	var support := {}
	_scan_dock(muelle, Transform3D.IDENTITY, support)
	var grown := _dilate(support, 2)
	var closed := _erode(grown, 2)
	_mask = closed
	if not _mask.is_empty():
		var sum := 0.0
		for key in _mask.keys():
			sum += float(_mask[key])
		_plane = sum / float(_mask.size())


func _scan_dock(n: Node, parent: Transform3D, support: Dictionary) -> void:
	var xf: Transform3D = parent * n.transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh:
		var mesh := (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			if idx.is_empty():
				continue
			var ntri := idx.size() / 3
			for t in ntri:
				var a: Vector3 = xf * verts[idx[t * 3]]
				var b: Vector3 = xf * verts[idx[t * 3 + 1]]
				var c: Vector3 = xf * verts[idx[t * 3 + 2]]
				var cr: Vector3 = (b - a).cross(c - a)
				if cr.length() < 0.0000001 or cr.y / cr.length() < 0.65:
					continue
				var cy := (a.y + b.y + c.y) / 3.0
				if cy < 0.60 or cy > 0.82:
					continue
				_raster_tri(a, b, c, support, -999.0)
	for child in n.get_children():
		_scan_dock(child, xf, support)


func _raster_tri(a: Vector3, b: Vector3, c: Vector3, dest: Dictionary, min_y: float) -> void:
	var minx := minf(a.x, minf(b.x, c.x))
	var maxx := maxf(a.x, maxf(b.x, c.x))
	var minz := minf(a.z, minf(b.z, c.z))
	var maxz := maxf(a.z, maxf(b.z, c.z))
	var x := minx
	while x <= maxx + 0.0001:
		var z := minz
		while z <= maxz + 0.0001:
			var w := _bary(Vector2(x, z), Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z))
			if w.x >= -0.02:
				var y := a.y * w.x + b.y * w.y + c.y * w.z
				if y >= min_y:
					var key := _key_at(x, z)
					if min_y < 0.0:
						dest[key] = maxf(float(dest.get(key, y)), y)
					else:
						dest[key] = true
			z += CELL * 0.5
		x += CELL * 0.5


func _bary(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> Vector3:
	var v0 := c - a
	var v1 := b - a
	var v2 := p - a
	var den := v0.dot(v0) * v1.dot(v1) - v0.dot(v1) * v0.dot(v1)
	if absf(den) < 0.0000001:
		return Vector3(-1, 0, 0)
	var u := (v1.dot(v1) * v0.dot(v2) - v0.dot(v1) * v1.dot(v2)) / den
	var v := (v0.dot(v0) * v1.dot(v2) - v0.dot(v1) * v0.dot(v2)) / den
	var w := 1.0 - u - v
	if u < -0.02 or v < -0.02 or (u + v) > 1.02:
		return Vector3(-1, 0, 0)
	return Vector3(w, v, u)


func _dilate(src: Dictionary, radius: int) -> Dictionary:
	var out := {}
	for key in src.keys():
		var bits := str(key).split(",")
		var ix := int(bits[0])
		var iz := int(bits[1])
		var y := float(src[key])
		for dx in range(-radius, radius + 1):
			for dz in range(-radius, radius + 1):
				var nk := "%d,%d" % [ix + dx, iz + dz]
				out[nk] = maxf(float(out.get(nk, y)), y)
	return out


func _erode(src: Dictionary, radius: int) -> Dictionary:
	var out := {}
	for key in src.keys():
		var bits := str(key).split(",")
		var ix := int(bits[0])
		var iz := int(bits[1])
		var ok := true
		for dx in range(-radius, radius + 1):
			if not ok:
				break
			for dz in range(-radius, radius + 1):
				if not src.has("%d,%d" % [ix + dx, iz + dz]):
					ok = false
					break
		if ok:
			out[key] = src[key]
	return out


func _key_at(x: float, z: float) -> String:
	return "%d,%d" % [int(floor(x / CELL)), int(floor(z / CELL))]


func _search(id: String) -> Dictionary:
	var best := {}
	var best_score := -999.0
	for sc in [1.0, 0.85, 0.7, 0.55]:
		var step := 0
		for key in _mask.keys():
			step += 1
			if step % 3 != 0:
				continue
			var bits := str(key).split(",")
			var x := (float(bits[0]) + 0.5) * CELL
			var z := (float(bits[1]) + 0.5) * CELL
			for yaw in [0.0, 90.0]:
				if _probe(id, x, z, yaw, sc) != "ok":
					continue
				var score := z - absf(x) * 0.2
				if score > best_score:
					best_score = score
					best = {"ok": true, "x": x, "z": z, "yaw": yaw, "scale": sc}
		if not best.is_empty():
			return best
	return {"ok": false}


func _probe(id: String, x: float, z: float, yaw: float, scale: float) -> String:
	return str(_resolve(id, x, z, yaw, scale, -999.0).get("reason", "water"))


func _resolve(id: String, x: float, z: float, yaw: float, scale: float, prefer_y: float) -> Dictionary:
	_ensure_mask()
	var pts := _samples(id, x, z, yaw, scale)
	if pts.is_empty():
		return {"reason": "water", "sit": _plane}
	var supports := _supports(id, pts)
	if supports.is_empty():
		var span := _span(pts)
		if span < 0.0:
			return {"reason": "water", "sit": _plane}
		if span > 0.09:
			return {"reason": "clip", "sit": _plane}
		return {"reason": "water", "sit": _plane}
	var floor := _lowest(supports)
	var sit := floor
	if prefer_y >= -100.0:
		sit = clampf(prefer_y, floor, floor + LIFT_MAX)
		var near := _near_support(supports, sit)
		if near > -100.0:
			sit = near
	if _hits(id, x, z, yaw, scale, sit, pts):
		return {"reason": "busy", "sit": sit}
	if not _resting(supports, sit):
		return {"reason": "air", "sit": sit}
	return {"reason": "ok", "sit": sit}


func _supports(id: String, pts: PackedVector2Array) -> Array:
	var found: Array = []
	var dock := _dock_sit(pts)
	if dock >= 0.0:
		found.append(dock)
	for item in _obs:
		if str(item.get("id", "")) == id:
			continue
		if _fully_on(pts, item["origin"], float(item["yaw"]), item["center"], float(item["hx"]), float(item["hz"])):
			found.append(float(item["top"]))
	return found


func _lowest(supports: Array) -> float:
	var sit := float(supports[0])
	for s in supports:
		sit = minf(sit, float(s))
	return sit


func _near_support(supports: Array, sit: float) -> float:
	var best := -9999.0
	var best_d := LIFT_SNAP
	for s in supports:
		var h := float(s)
		var d := absf(sit - h)
		if d <= best_d:
			best_d = d
			best = h
	return best


func _resting(supports: Array, sit: float) -> bool:
	for s in supports:
		if absf(sit - float(s)) <= 0.04:
			return true
	return false


func _dock_sit(pts: PackedVector2Array) -> float:
	var hi := -999.0
	var lo := 999.0
	for i in pts.size():
		var p: Vector2 = pts[i]
		var key := _key_at(p.x, p.y)
		if not _mask.has(key):
			return -1.0
		var sy := float(_mask[key])
		hi = maxf(hi, sy)
		lo = minf(lo, sy)
	if hi - lo > 0.09:
		return -1.0
	return hi


func _span(pts: PackedVector2Array) -> float:
	var hi := -999.0
	var lo := 999.0
	var any := false
	for i in pts.size():
		var key := _key_at(pts[i].x, pts[i].y)
		if not _mask.has(key):
			return -1.0
		var sy := float(_mask[key])
		hi = maxf(hi, sy)
		lo = minf(lo, sy)
		any = true
	if not any:
		return -1.0
	return hi - lo


func _hits(id: String, x: float, z: float, yaw: float, scale: float, sit: float, pts: PackedVector2Array) -> bool:
	if _covers(id, x, z, yaw, scale, CAT_AT) or _near(pts, CAT_AT, CAT_R):
		return true
	var lamp := LANTERN.position + LANTERN.size * 0.5
	if _covers(id, x, z, yaw, scale, lamp) or _in_rect(pts, LANTERN):
		return true
	var height := float(_metrics_of(id)["size"].y) * scale
	var top := sit + height
	for item in _obs:
		if str(item.get("id", "")) == id:
			continue
		if not _overlaps_xz(pts, item):
			continue
		var other_top := float(item["top"])
		var other_bot := float(item["bottom"])
		if absf(sit - other_top) <= 0.03:
			continue
		if sit < other_top - 0.02 and top > other_bot + 0.02:
			return true
	return false


func _overlaps_xz(pts: PackedVector2Array, item: Dictionary) -> bool:
	return _covers_item(pts, item["origin"], float(item["yaw"]), item["center"], float(item["hx"]), float(item["hz"]))


func _fully_on(pts: PackedVector2Array, origin: Vector2, yaw: float, center: Vector2, hx: float, hz: float) -> bool:
	if pts.is_empty() or hx < 0.05 or hz < 0.05:
		return false
	var inv := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0)).inverse()
	for i in pts.size():
		var local: Vector3 = inv * Vector3(pts[i].x - origin.x, 0.0, pts[i].y - origin.y)
		if absf(local.x - center.x) > hx - 0.03 or absf(local.z - center.y) > hz - 0.03:
			return false
	return true


func _sit_y(id: String, x: float, z: float, yaw: float, scale: float) -> float:
	var pts := _samples(id, x, z, yaw, scale)
	var hi := _plane
	var any := false
	for i in pts.size():
		var p: Vector2 = pts[i]
		var key := _key_at(p.x, p.y)
		if not _mask.has(key):
			continue
		var sy := float(_mask[key])
		if not any:
			hi = sy
			any = true
		else:
			hi = maxf(hi, sy)
	return hi


func _near(pts: PackedVector2Array, at: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	for i in pts.size():
		if pts[i].distance_squared_to(at) <= r2:
			return true
	return false


func _in_rect(pts: PackedVector2Array, box: Rect2) -> bool:
	for i in pts.size():
		if box.has_point(pts[i]):
			return true
	return false


func _covers(id: String, x: float, z: float, yaw: float, scale: float, at: Vector2) -> bool:
	var m: Dictionary = _metrics_of(id)
	var local: Vector3 = _basis(yaw, scale).inverse() * Vector3(at.x - x, 0.0, at.y - z)
	var c: Vector2 = m["center"]
	var h: Vector2 = m["half"]
	return absf(local.x - c.x) <= h.x + 0.05 and absf(local.z - c.y) <= h.y + 0.05


func _covers_item(pts: PackedVector2Array, origin: Vector2, yaw: float, center: Vector2, hx: float, hz: float) -> bool:
	var rot := Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0))
	var inv := rot.inverse()
	for i in pts.size():
		var local: Vector3 = inv * Vector3(pts[i].x - origin.x, 0.0, pts[i].y - origin.y)
		if absf(local.x - center.x) <= hx + 0.04 and absf(local.z - center.y) <= hz + 0.04:
			return true
	return false


func _basis(yaw: float, scale: float) -> Basis:
	return Basis.from_euler(Vector3(0.0, deg_to_rad(yaw), 0.0)).scaled(Vector3(scale, scale, scale))


func _samples(id: String, x: float, z: float, yaw: float, scale: float) -> PackedVector2Array:
	var m: Dictionary = _metrics_of(id)
	var b := _basis(yaw, scale)
	var out := PackedVector2Array()
	var x0 := float(m["minx"])
	var x1 := float(m["maxx"])
	var z0 := float(m["minz"])
	var z1 := float(m["maxz"])
	var step := 0.08 / maxf(scale, 0.35)
	var lx := x0
	while lx <= x1 + 0.0001:
		var lz := z0
		while lz <= z1 + 0.0001:
			var w: Vector3 = b * Vector3(lx, 0.0, lz)
			out.append(Vector2(x + w.x, z + w.z))
			lz += step
		lx += step
	return out


func _obstacles(state: Dictionary, ignore: String) -> Array:
	_ensure_mask()
	var list: Array = []
	var placed: Dictionary = state.get("decor_placed", {})
	for key in placed.keys():
		var id := str(key)
		if id == ignore or not _is_decor(id):
			continue
		var pose := _parse_any(str(placed[key]), id)
		if pose.is_empty():
			continue
		var m: Dictionary = _metrics_of(id)
		var sc := float(pose["scale"])
		var center: Vector2 = m["center"]
		var half: Vector2 = m["half"]
		var bottom := _sit_y(id, float(pose["x"]), float(pose["z"]), float(pose["yaw"]), sc)
		if pose.has("y"):
			bottom = float(pose["y"])
		var tall: Vector3 = m["size"]
		list.append({
			"id": id,
			"origin": Vector2(float(pose["x"]), float(pose["z"])),
			"yaw": float(pose["yaw"]),
			"scale": sc,
			"center": Vector2(center.x * sc, center.y * sc),
			"hx": half.x * sc,
			"hz": half.y * sc,
			"bottom": bottom,
			"top": bottom + tall.y * sc,
		})
	return list


func _metrics_of(id: String) -> Dictionary:
	if _metrics.has(id):
		return _metrics[id]
	var size := _model_size(id)
	var y0 := 0.0
	var minx := -size.x * 0.5
	var minz := -size.z * 0.5
	if _bb_ok:
		y0 = _bb.position.y
		minx = _bb.position.x
		minz = _bb.position.z
	var info := {
		"size": size,
		"y0": y0,
		"minx": minx,
		"maxx": minx + size.x,
		"minz": minz,
		"maxz": minz + size.z,
		"center": Vector2(minx + size.x * 0.5, minz + size.z * 0.5),
		"half": Vector2(size.x * 0.5, size.z * 0.5),
	}
	_metrics[id] = info
	return info


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
		var kids: Array = marker.get_children()
		for child in kids:
			if str(child.name).begins_with("placed_"):
				child.free()
	var own: Array = get_children()
	for child in own:
		if str(child.name).begins_with("placed_"):
			child.free()
	var glows := 0
	var ids: Array = placed.keys()
	ids.sort()
	_obs = _obstacles({"decor_placed": placed}, "")
	for id in ids:
		var raw := str(placed[id])
		var inst := _make(str(id))
		if inst == null:
			continue
		inst.name = "placed_" + str(id)
		var pose := _parse_pose(raw)
		if raw.begins_with("slot_") and markers.has(raw):
			var marker := markers[raw] as Marker3D
			var size := _model_size(str(id))
			var foot := maxf(size.x, size.z)
			var max_size := float(marker.get_meta("max_size", 0.5))
			var sc := 1.0
			if foot > 0.001:
				sc = minf(1.0, max_size / foot)
			var y0 := float(_metrics_of(str(id)).get("y0", 0.0))
			inst.scale = Vector3.ONE * sc
			inst.position = Vector3(0.0, -y0 * sc, 0.0)
			marker.add_child(inst)
			glows = _glow(inst, str(id), size.y, glows)
			_bounce(inst, str(id) == bounce_id)
		elif not pose.is_empty():
			var sc2 := float(pose["scale"])
			var px := float(pose["x"])
			var pz := float(pose["z"])
			var yaw := float(pose["yaw"])
			var prefer := -999.0
			if pose.has("y"):
				prefer = float(pose["y"])
			var resolved := _resolve(str(id), px, pz, yaw, sc2, prefer)
			var sit := float(resolved.get("sit", _sit_y(str(id), px, pz, yaw, sc2)))
			if str(resolved.get("reason", "")) != "ok":
				sit = _sit_y(str(id), px, pz, yaw, sc2)
			var y0b := float(_metrics_of(str(id)).get("y0", 0.0))
			inst.scale = Vector3.ONE * sc2
			inst.rotation = Vector3(0.0, deg_to_rad(yaw), 0.0)
			inst.position = Vector3(px, sit - y0b * sc2, pz)
			var tall: Vector3 = _metrics_of(str(id))["size"]
			add_child(inst)
			glows = _glow(inst, str(id), tall.y, glows)
			_bounce(inst, str(id) == bounce_id)
		else:
			inst.free()


func _make(id: String) -> Node3D:
	var path := str(ShopSave.item_by_id(id).get("model", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var inst := packed.instantiate() as Node3D
	if inst == null:
		return null
	_quiet(inst)
	return inst


func _glow(inst: Node3D, id: String, height: float, glows: int) -> int:
	if not GLOW.has(id) or glows >= MAX_GLOWS:
		return glows
	var light := OmniLight3D.new()
	light.name = "placed_glow"
	light.shadow_enabled = false
	light.omni_range = 1.6
	light.light_energy = 0.55
	light.light_color = Color(1.0, 0.75, 0.42)
	light.position = Vector3(0.0, height * float(GLOW[id]), 0.0)
	inst.add_child(light)
	return glows + 1


func _bounce(inst: Node3D, on: bool) -> void:
	if not on:
		return
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
