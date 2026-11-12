@tool
extends EditorExportPlugin
## El ciclo lee este json con FileAccess. No es un recurso de escena,
## así que “exportar la escena y dependencias” lo deja fuera y el juego
## se queda en el atardecer pintado en Main.


func _get_name() -> String:
	return "pesca_cycle_pack"


func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	var res := "res://data/time_of_day.json"
	var bytes := FileAccess.get_file_as_bytes(res)
	if bytes.is_empty():
		push_warning("pesca_cycle_pack: no pude leer " + res)
		return
	add_file(res, bytes, false)


func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# all_resources ya lo copia. Sin esto el paquete queda con el json dos veces.
	if path.ends_with("data/time_of_day.json"):
		skip()
