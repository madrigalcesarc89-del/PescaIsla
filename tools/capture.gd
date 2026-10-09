extends SceneTree
## Reorg/18.0: captura determinista de la escena principal en varias proporciones.
## Uso: Godot --path . --fixed-fps 60 --resolution 540x960
##        --script res://tools/capture.gd   (ASPECT=9x16 por defecto)
## ASPECT: 9x16=1080x1920, 18x9=1080x2160, 19.5x9=1080x2340, 20x9=1080x2400,
##         3x4=1440x1920 (ancha).
## Renderiza en un SubViewport propio (no depende del tamaño de ventana).
## Salida: DUMP_OUT o docs/previews/reorg_base.png.

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"18x9": Vector2i(1080, 2160),
	"19.5x9": Vector2i(1080, 2340),
	"20x9": Vector2i(1080, 2400),
	"3x4": Vector2i(1440, 1920),
}

func _init():
	var out = OS.get_environment("DUMP_OUT")
	var aspect := OS.get_environment("ASPECT")
	if not ASPECTS.has(aspect):
		aspect = "9x16"
	if out == "":
		out = "res://docs/previews/reorg_base.png"
	var wh: Vector2i = ASPECTS[aspect]
	var sv := SubViewport.new()
	sv.size = wh
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
