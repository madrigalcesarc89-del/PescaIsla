extends SceneTree
## Capturas de REEL por patrón y proporción. No se commitea el uso:
## Godot --path . --script res://tools/fight_reel_audit.gd

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}
const FISH_FOR := {
	"drift": "fish_moon",
	"bounce": "fish_clownfish",
	"zigzag": "fish_pink_sardine",
	"dash": "fish_lanternfish",
	"puff": "fish_mint_puffer",
	"ghost": "fish_ghost_fish",
	"heavy": "fish_mini_whale",
	"phases": "fish_rainbow_fish",
}
const TRACK_BG := Color(0.4, 0.3, 0.19, 1.0)
const CREAM := Color("FFF1D6")
const INK := Color("5A3D2B")


func _init() -> void:
	var shot := OS.get_environment("SHOT_DIR")
	if shot == "":
		shot = "/tmp/fight_reel"
	DirAccess.make_dir_recursive_absolute(shot)
	var fail := 0
	for aspect in ASPECTS.keys():
		var wh: Vector2i = ASPECTS[aspect]
		var sv := SubViewport.new()
		sv.size = wh
		sv.own_world_3d = true
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		get_root().add_child(sv)
		var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
		sv.add_child(main)
		for _i in 10:
			await process_frame
		var fish := _find_fishing(main)
		if fish == null:
			print("NO_FISH ", aspect)
			fail += 1
			_drop(sv)
			continue
		fish._tutorial_done = true
		if fish._tutorial != null:
			fish._tutorial.visible = false
		for kind in FISH_FOR.keys():
			var ok := await _shot(sv, main, fish, wh, aspect, kind, str(FISH_FOR[kind]), shot)
			if not ok:
				fail += 1
		_drop(sv)
		await process_frame
	var fps := await _fps()
	print("FPS_REEL %.1f" % fps)
	if fps < 55.0:
		print("FPS_BAJO")
		fail += 1
	if fail == 0:
		print("REEL_AUDIT_OK")
		quit(0)
	else:
		print("REEL_AUDIT_FAIL ", fail)
		quit(1)


func _shot(sv: SubViewport, main: Node, fish: Node, wh: Vector2i, aspect: String, kind: String, fish_id: String, shot: String) -> bool:
	fish.debug_force(fish_id)
	var fight = fish._fight
	for _j in 3:
		await process_frame
	if kind in ["dash", "puff", "ghost", "phases"] and fight != null and str(fight.telegraph) == "":
		fight.telegraph = "rage" if kind == "phases" else kind
		fight.telegraph_t = 0.5
		fight.blink = 1.2
		if kind == "phases":
			fight.warn = "rage"
		if kind == "dash":
			fight.preview = clampf(float(fight.center) + 0.34, 0.2, 0.8)
			fight.preview_half = fight.half
		elif kind == "puff":
			fight.preview = fight.center
			fight.preview_half = float(fight.half) * 0.55
		await process_frame
	var img := sv.get_texture().get_image()
	var path := "%s/%s_%s.png" % [shot, kind, aspect]
	img.save_png(path)
	var bad := _check(main, fish, wh, img)
	print("%s %s %s %s" % ["OK" if bad == "" else "BAD", kind, aspect, bad])
	return bad == ""


func _check(main: Node, fish: Node, wh: Vector2i, img: Image) -> String:
	var reel := _find_named(main, "ReelBox")
	var pill := _find_named(main, "ReelPill")
	var label := _find_named(main, "ReelLabel")
	var debug := _find_named(main, "DebugFight")
	var vp := Vector2(wh)
	for node in [reel, pill, label, debug]:
		if node == null or not (node is CanvasItem):
			continue
		if not (node as CanvasItem).is_visible_in_tree():
			continue
		var r: Rect2 = (node as Control).get_global_rect()
		if r.size.x < 2.0 or r.size.y < 2.0:
			continue
		if r.position.x < -1.0 or r.position.y < -1.0 or r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
			return "fuera %s %s" % [node.name, r]
	if label != null and label is Label:
		var lab := label as Label
		var font := lab.get_theme_font("font")
		var px := lab.get_theme_font_size("font_size")
		if font != null and px > 0 and lab.text != "":
			var used := font.get_string_size(lab.text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if used > lab.size.x + 2.0:
				return "texto %s px %.0f en %.0f" % [lab.text, used, lab.size.x]
	if debug != null:
		var info := debug.find_child("Info", true, false) as Label
		if info != null and info.text != "":
			var font2 := info.get_theme_font("font")
			var px2 := info.get_theme_font_size("font_size")
			if font2 != null:
				var h := font2.get_multiline_string_size(info.text, HORIZONTAL_ALIGNMENT_LEFT, info.size.x, px2).y
				if h > info.size.y + 4.0:
					return "debug desborda"
	var c_zone := _zone_color(fish)
	var rim := _contrast(Color("FFF1D6"), TRACK_BG)
	if rim < 4.5:
		return "contraste borde %.2f" % rim
	var ink := _contrast(INK, CREAM)
	if ink < 4.5:
		return "contraste texto %.2f" % ink
	var bar := Color(0.28, 0.2, 0.14)
	for hex in ["5CC8C2", "E7A07A", "E58AA3"]:
		var lr := _contrast(Color(hex), bar)
		if lr < 4.5:
			return "contraste linea %s %.2f" % [hex, lr]
	if _contrast(c_zone, Color("111111")) < 1.2:
		return "zona invisible"
	if img.get_width() != wh.x or img.get_height() != wh.y:
		return "tamano captura"
	return ""


func _zone_color(fish: Node) -> Color:
	var fight = fish._fight
	if fight != null and fight.has_method("rarity_color"):
		return fight.rarity_color()
	return Color("7DCAA5")


func _contrast(a: Color, b: Color) -> float:
	var l1 := _lum(a)
	var l2 := _lum(b)
	var hi := maxf(l1, l2)
	var lo := minf(l1, l2)
	return (hi + 0.05) / (lo + 0.05)


func _lum(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


func _lin(u: float) -> float:
	return u / 12.92 if u <= 0.04045 else pow((u + 0.055) / 1.055, 2.4)


func _fps() -> float:
	var sv := SubViewport.new()
	sv.size = Vector2i(1080, 1920)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(sv)
	var main := (load("res://scenes/Main.tscn") as PackedScene).instantiate()
	sv.add_child(main)
	for _i in 6:
		await process_frame
	var fish := _find_fishing(main)
	fish.debug_force("fish_lanternfish")
	var frames := 0
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2000:
		await process_frame
		frames += 1
	var sec := float(Time.get_ticks_msec() - t0) / 1000.0
	_drop(sv)
	if sec <= 0.0:
		return 0.0
	return float(frames) / sec


func _find_fishing(n: Node) -> Node:
	if n.get_script() != null and str(n.get_script().resource_path).ends_with("fishing.gd"):
		return n
	for c in n.get_children():
		var hit := _find_fishing(c)
		if hit != null:
			return hit
	return null


func _find_named(n: Node, name_s: String) -> Node:
	if n.name == name_s:
		return n
	for c in n.get_children():
		var hit := _find_named(c, name_s)
		if hit != null:
			return hit
	return null


func _drop(sv: SubViewport) -> void:
	if is_instance_valid(sv) and sv.get_parent() != null:
		sv.get_parent().remove_child(sv)
	if is_instance_valid(sv):
		sv.queue_free()
