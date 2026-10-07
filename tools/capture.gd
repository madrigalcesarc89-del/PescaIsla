extends SceneTree
## Reorg: captura determinista 1080x1920 de la escena principal.
## Uso: Godot --path . --fixed-fps 60 --resolution 540x960
##        --script res://tools/capture.gd
## Renderiza en un SubViewport propio (no depende del tamaño de ventana).
## Salida: DUMP_OUT o docs/previews/reorg_base.png.

const W := 1080
const H := 1920

func _init():
	var out = OS.get_environment("DUMP_OUT")
	if out == "":
		out = "res://docs/previews/reorg_base.png"
	var sv := SubViewport.new()
	sv.size = Vector2i(W, H)
	sv.own_world_3d = true
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(sv)
	var packed = load("res://scenes/Main.tscn") as PackedScene
	var main = packed.instantiate()
	sv.add_child(main)
	for i in range(100):
		await process_frame
	var img := sv.get_texture().get_image()
	var abs_out := ProjectSettings.globalize_path(out)
	var err := img.save_png(abs_out)
	if err != OK:
		push_error("capture: no se pudo guardar " + abs_out)
	else:
		print("CAPTURE_SAVED=", abs_out, " size=", img.get_size())
	quit()
