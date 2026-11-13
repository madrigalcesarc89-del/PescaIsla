extends SceneTree
## Diagnóstico del álbum actual: viewport contra el rectángulo del panel.

const ASPECTS := {
	"9x16": Vector2i(1080, 1920),
	"3x4": Vector2i(1440, 1920),
}

func _init() -> void:
	SettingsData.load_all()
	var db = JSON.parse_string(FileAccess.get_file_as_string("res://data/fish_db.json"))
	for aspect in ASPECTS.keys():
		var sv := SubViewport.new()
		sv.size = ASPECTS[aspect]
		sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(sv)
		var album = load("res://scenes/ui/album.tscn").instantiate()
		album.set_anchors_preset(Control.PRESET_FULL_RECT)
		album.anchor_right = 1.0
		album.anchor_bottom = 1.0
		sv.add_child(album)
		await process_frame
		album.setup(db["fishes"], {}, {}, {"common": false, "uncommon": false, "rare": false, "legendary": false}, db)
		album.open_album()
		await process_frame
		await process_frame
		var panel: Control = album.get_node("Center/Panel")
		var scroll: ScrollContainer = album.get_node("Center/Panel/Margin/VBox/Scroll")
		var grid: GridContainer = album.get_node("Center/Panel/Margin/VBox/Scroll/Grid")
		var prect := panel.get_global_rect()
		var grect := grid.get_global_rect()
		print("ASPECT ", aspect)
		print("  viewport ", sv.size, " album ", album.size)
		print("  panel ", prect, " end ", prect.position + prect.size)
		print("  panel_right_overflow ", (prect.position.x + prect.size.x) - sv.size.x)
		print("  scroll ", scroll.size, " h_mode ", scroll.horizontal_scroll_mode, " v_mode ", scroll.vertical_scroll_mode)
		print("  grid ", grid.size, " columns ", grid.columns, " children ", grid.get_child_count(), " min ", grid.get_combined_minimum_size())
		var xs := {}
		var ys := {}
		for c in grid.get_children():
			var r: Rect2 = c.get_global_rect()
			xs[str(int(r.position.x))] = true
			ys[str(int(r.position.y))] = true
			print("  cell ", c.get_meta("id", "?"), " ", r.size, " x ", r.position.x)
		print("  distinct_x ", xs.size(), " distinct_y ", ys.size())
		print("  panel anchors ", panel.anchor_left, panel.anchor_top, panel.anchor_right, panel.anchor_bottom, " custom_min ", panel.custom_minimum_size)
		sv.queue_free()
		await process_frame
	print("ALBUM_DIAG_OK")
	quit(0)
