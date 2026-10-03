extends SceneTree
## TEMPORAL: captura docs/<nombre> a 1080x1920 vía SubViewport y sale.
## Uso: --script res://scripts/_tmp_preview.gd -- <nombre.png>
## Borrar tras usar.

var _frames: int = 0
var _out: String = "preview_tmp.png"
var _svp: SubViewport


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() > 0:
		_out = args[0]
	_svp = SubViewport.new()
	_svp.size = Vector2i(1080, 1920)
	_svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_svp.own_world_3d = true
	root.add_child(_svp)
	var packed: PackedScene = load("res://scenes/Main.tscn")
	_svp.add_child(packed.instantiate())


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames >= 15:
		var img: Image = _svp.get_texture().get_image()
		var err: int = img.save_png("res://docs/" + _out)
		print("PREVIEW_SAVE file=", _out, " err=", err, " size=", img.get_size())
		return true
	return false
