@tool
extends EditorPlugin

var _pack: EditorExportPlugin


func _enter_tree() -> void:
	_pack = preload("res://addons/pesca_cycle_pack/export_plugin.gd").new()
	add_export_plugin(_pack)


func _exit_tree() -> void:
	if _pack != null:
		remove_export_plugin(_pack)
		_pack = null
