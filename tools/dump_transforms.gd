extends SceneTree
## Reorg: vuelca transformadas globales (origen + base) de todos los Node3D.
## Uso: Godot --headless --path . --script res://tools/dump_transforms.gd > docs/transforms_reorg_base.txt
## Formato compatible con docs/transforms_*.txt existentes.

func _init():
	var out_path := OS.get_environment("DUMP_OUT")
	var packed = load("res://scenes/Main.tscn") as PackedScene
	var root = packed.instantiate()
	get_root().add_child(root)
	for i in range(4):
		await process_frame
	var lines: Array[String] = []
	_collect(root, lines)
	lines.sort()
	var text := "\n".join(lines) + "\n"
	if out_path != "":
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			print("DUMP_SAVED=", out_path, " nodes=", lines.size())
		else:
			push_error("dump_transforms: no se pudo escribir " + out_path)
	else:
		print(text)
	quit()


func _collect(n: Node, lines: Array[String]) -> void:
	if n is Node3D:
		var gt := (n as Node3D).global_transform
		var o := gt.origin
		var x := gt.basis.x
		var y := gt.basis.y
		var z := gt.basis.z
		# /root/Main/Cat -> /Main/Cat (formato docs/transforms_*.txt).
		var p := str(n.get_path()).replace("/root", "")
		lines.append("%s | o=(%f,%f,%f) | x=(%f,%f,%f) y=(%f,%f,%f) z=(%f,%f,%f)" % [
			p, o.x, o.y, o.z, x.x, x.y, x.z, y.x, y.y, y.z, z.x, z.y, z.z])
	for c in n.get_children():
		_collect(c, lines)
