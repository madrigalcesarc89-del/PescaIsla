extends SceneTree
## Premios del álbum. Guardado nuevo, un grupo, doble cobro y reparación.
## Godot --headless --path . --script res://tools/claim_audit.gd

const AlbumSave = preload("res://scripts/album_save.gd")

var _fail := 0


func _init() -> void:
	print("CLAIM_AUDIT start")
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	var fishes: Array = db["fishes"]
	var fresh: Dictionary = AlbumSave.read({})
	var caught: Dictionary = fresh["caught"]
	var claimed: Dictionary = fresh["claimed"]
	print("NEW coins ", fresh["coins"])
	for fish in fishes:
		var id := str(fish["id"])
		var n := int(caught.get(id, 0))
		print("caught ", id, " ", n)
		if n != 0:
			_bad("guardado nuevo con " + id)
	for rarity in AlbumSave.RARITIES:
		var yes: bool = AlbumSave.can_claim(fishes, caught, claimed, rarity)
		print("can_claim ", rarity, " ", yes)
		if yes:
			_bad("guardado nuevo reclama " + rarity)
	var sv := SubViewport.new()
	sv.size = Vector2i(1080, 1920)
	root.add_child(sv)
	var album = load("res://scenes/ui/album.tscn").instantiate()
	album.set_anchors_preset(Control.PRESET_FULL_RECT)
	album.anchor_right = 1.0
	album.anchor_bottom = 1.0
	sv.add_child(album)
	await process_frame
	await _show(album, fishes, {}, {}, db)
	if _claims(album) != 0:
		_bad("botón visible en guardado nuevo")
	var commons := {}
	for fish in fishes:
		if str(fish["rarity"]) == "common":
			commons[str(fish["id"])] = 1
	var only_three := {
		"fish_pink_sardine": 1,
		"fish_moon": 1,
		"fish_cream_carp": 1,
	}
	await _show(album, fishes, only_three, {}, db)
	if _claims(album) != 0:
		_bad("tres comunes no completan el grupo nuevo")
	await _show(album, fishes, commons, {}, db)
	var buttons := _claim_buttons(album)
	if buttons.size() != 1:
		_bad("se esperaba un Reclamar, hay " + str(buttons.size()))
	elif not str(buttons[0].text).begins_with("Reclamar +80"):
		_bad("texto " + str(buttons[0].text))
	else:
		var btn: Button = buttons[0]
		var alive := true
		btn.pressed.connect(func() -> void:
			album.refresh_deferred()
			alive = is_instance_valid(btn)
		)
		btn.pressed.emit()
		if not alive or not is_instance_valid(album):
			_bad("el botón se liberó dentro de su señal")
		await process_frame
	var path := "user://claim_audit.json"
	_wipe(path)
	var empty_claim: Dictionary = AlbumSave.empty_claimed()
	var pity := {"dry_rare": 0, "dry_legend": 0}
	var first := {}
	var rest := {}
	var seen := {}
	var step: Dictionary = AlbumSave.commit_claim(path, 0, commons, first, empty_claim, pity, rest, seen, fishes, db, "common")
	if not bool(step.get("ok", false)) or int(step["added"]) != 80 or int(step["coins"]) != 80:
		_bad("el cobro no sumó 80")
	if not bool(step["claimed"]["group_common_v2"]):
		_bad("no marcó claimed")
	if bool(step["claimed"]["common"]):
		_bad("el cobro nuevo marcó la clave vieja")
	await _show(album, fishes, commons, step["claimed"], db)
	if _claims(album) != 0:
		_bad("el botón sigue tras cobrar")
	var again: Dictionary = AlbumSave.commit_claim(path, int(step["coins"]), commons, first, step["claimed"], pity, rest, seen, fishes, db, "common")
	if bool(again.get("ok", false)) or int(again["added"]) != 0 or int(again["coins"]) != 80:
		_bad("el segundo cobro duplicó")
	var disk = JSON.parse_string(FileAccess.get_file_as_string(path))
	var reloaded: Dictionary = AlbumSave.read(disk)
	if int(reloaded["coins"]) != 80 or not bool(reloaded["claimed"]["group_common_v2"]):
		_bad("reiniciar no conservó el cobro")
	var third: Dictionary = AlbumSave.commit_claim(path, int(reloaded["coins"]), reloaded["caught"], reloaded["first_caught"], reloaded["claimed"], reloaded["pity"], reloaded["rest"], reloaded["album_seen"], fishes, db, "common")
	if int(third["coins"]) != 80 or int(third["added"]) != 0:
		_bad("tras reiniciar se duplicó")
	var rare := commons.duplicate()
	rare["fish_lanternfish"] = 1
	if AlbumSave.can_claim(fishes, rare, reloaded["claimed"], "rare"):
		_bad("un raro suelto activó el premio")
	await _show(album, fishes, rare, reloaded["claimed"], db)
	if _claims(album) != 0:
		_bad("un raro suelto mostró botón")
	var bad := "user://no_such_claim_dir/save.json"
	var failed: Dictionary = AlbumSave.commit_claim(bad, 0, commons, first, empty_claim, pity, rest, seen, fishes, db, "common")
	if bool(failed.get("ok", false)) or int(failed["coins"]) != 0 or bool(failed["claimed"]["group_common_v2"]):
		_bad("un fallo de disco marcó el premio")
	var legacy := {"common": true, "uncommon": true, "rare": true, "legendary": true}
	var legacy_extra := AlbumSave.extra_claim_coins(fishes, {}, legacy, db)
	print("legacy_extra ", legacy_extra)
	if legacy_extra != 0:
		_bad("la clave vieja no debe descontar monedas")
	var corrupt_claimed := {
		"group_common_v2": true,
		"group_uncommon_v2": true,
		"group_rare_v2": true,
		"group_epic_v2": true,
		"group_legendary_v2": true,
	}
	var extra := AlbumSave.extra_claim_coins(fishes, {}, corrupt_claimed, db)
	print("extra_coins_fixture ", extra)
	if extra != 2480:
		_bad("monedas de más del ejemplo " + str(extra))
	var repaired: Dictionary = AlbumSave.commit_repair("user://claim_audit_repair.json", 3000, {}, first, corrupt_claimed, pity, rest, seen, fishes, db)
	if int(repaired["extra"]) != 2480 or int(repaired["coins"]) != 520:
		_bad("la reparación no descontó")
	if bool(repaired["claimed"].get("group_legendary_v2", false)):
		_bad("la reparación dejó un premio falso")
	_wipe(path)
	_wipe("user://claim_audit_repair.json")
	sv.free()
	if _fail == 0:
		print("CLAIM_AUDIT_OK")
		quit(0)
		return
	print("CLAIM_AUDIT_FAIL ", _fail)
	quit(1)


func _show(album: Control, fishes: Array, caught: Dictionary, claimed: Dictionary, db: Dictionary) -> void:
	var use: Dictionary = claimed if not claimed.is_empty() else AlbumSave.empty_claimed()
	album.setup(fishes, caught, {}, use, db, {}, true)
	album.open_album()
	await process_frame
	await process_frame


func _claims(node: Node) -> int:
	return _claim_buttons(node).size()


func _claim_buttons(node: Node) -> Array:
	var out: Array = []
	if node is Button and str(node.name) == "Claim" and node.visible:
		out.append(node)
	for child in node.get_children():
		out.append_array(_claim_buttons(child))
	return out


func _wipe(path: String) -> void:
	var base := path.get_base_dir()
	var da := DirAccess.open(base)
	if da == null:
		return
	if da.file_exists(path.get_file()):
		da.remove(path.get_file())


func _bad(msg: String) -> void:
	_fail += 1
	push_error("FAIL " + msg)
