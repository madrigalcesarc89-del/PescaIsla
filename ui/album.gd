extends Control
## Álbum de peces. Solo interfaz: vive en el CanvasLayer del HUD.
## La versión de prueba muestra reiniciar y desbloquear; un export
## release (OS.is_debug_build() == false) no los crea.

const AlbumSave = preload("res://scripts/album_save.gd")

signal closed
signal claim_requested(rarity: String)
signal reset_requested
signal unlock_requested

const SILHOUETTE := Color(0.353, 0.239, 0.169, 0.85)
const CREAM := Color(1.0, 0.945, 0.839)
const FRAME_FOR := {
	"common": "res://assets/art/ui/frame_common.png",
	"uncommon": "res://assets/art/ui/frame_uncommon.png",
	"rare": "res://assets/art/ui/frame_rare.png",
	"legendary": "res://assets/art/ui/frame_legendary.png",
}

var _fishes: Array = []
var _caught: Dictionary = {}
var _first: Dictionary = {}
var _claimed: Dictionary = {}
var _db: Dictionary = {}
var _strings: Dictionary = {}
var _open_id: String = ""

@onready var _panel: PanelContainer = $Center/Panel
@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _counter: Label = $Center/Panel/Margin/VBox/Counter
@onready var _scroll: ScrollContainer = $Center/Panel/Margin/VBox/Scroll
@onready var _grid: GridContainer = $Center/Panel/Margin/VBox/Scroll/Grid
@onready var _rewards: HBoxContainer = $Center/Panel/Margin/VBox/Rewards
@onready var _close: Button = $Center/Panel/Margin/VBox/CloseBtn
@onready var _detail: Control = $Detail
@onready var _detail_panel: PanelContainer = $Detail/Center/Panel
@onready var _d_title: Label = $Detail/Center/Panel/Margin/VBox/Title
@onready var _d_rarity: Label = $Detail/Center/Panel/Margin/VBox/Rarity
@onready var _d_body: Label = $Detail/Center/Panel/Margin/VBox/Body
@onready var _d_value_row: HBoxContainer = $Detail/Center/Panel/Margin/VBox/ValueRow
@onready var _d_value: Label = $Detail/Center/Panel/Margin/VBox/ValueRow/Value
@onready var _d_since: Label = $Detail/Center/Panel/Margin/VBox/Since
@onready var _d_close: Button = $Detail/Center/Panel/Margin/VBox/CloseBtn
@onready var _debug: HBoxContainer = $DebugRow


func _ready() -> void:
	_load_strings()
	_close.pressed.connect(_hide_album)
	_d_close.pressed.connect(_hide_detail)
	$DebugRow/ResetBtn.pressed.connect(func() -> void: reset_requested.emit())
	$DebugRow/UnlockBtn.pressed.connect(func() -> void: unlock_requested.emit())
	resized.connect(_layout)
	_scroll.scroll_deadzone = 12
	visible = false
	_detail.visible = false
	_debug.visible = OS.is_debug_build()


func setup(fishes: Array, caught: Dictionary, first: Dictionary, claimed: Dictionary, db: Dictionary) -> void:
	_fishes = fishes
	_caught = caught
	_first = first
	_claimed = claimed
	_db = db
	_load_strings()
	if is_node_ready() and visible:
		_rebuild()


func open_album() -> void:
	visible = true
	_detail.visible = false
	_open_id = ""
	_rebuild()
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx("open")


func _hide_album() -> void:
	_detail.visible = false
	visible = false
	closed.emit()


func _hide_detail() -> void:
	_detail.visible = false
	_open_id = ""


func is_detail_open() -> bool:
	return visible and _detail.visible


## Atrás: primero la ficha, después el álbum. Devuelve true si consumió el evento.
func consumes_back() -> bool:
	if not visible:
		return false
	if _detail.visible:
		_hide_detail()
		return true
	_hide_album()
	return true


func play_reward(amount: int) -> void:
	var lab := Label.new()
	lab.text = "+%d" % amount
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(lab)
	_paint(lab)
	UiFit.fit_label(lab, _panel.size.x * 0.6, 1, 28, 48)
	lab.position = Vector2(_panel.size.x * 0.5 - 80.0, _panel.size.y * 0.72)
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", lab.position.y - 80.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(lab.queue_free)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx("coin")


func _layout() -> void:
	if not is_node_ready():
		return
	var vp := size
	if vp.x < 64.0:
		vp = get_viewport_rect().size
	var w := vp.x * 0.92
	var h := vp.y * (0.78 if _debug.visible else 0.88)
	_panel.custom_minimum_size = Vector2(w, h)
	_detail_panel.custom_minimum_size = Vector2(minf(w, 760.0), 0)
	_fit_cells()
	_fit_chrome()


func _rebuild() -> void:
	if not is_node_ready():
		return
	_layout()
	for child in _grid.get_children():
		child.queue_free()
	for fish in _fishes:
		if typeof(fish) != TYPE_DICTIONARY:
			continue
		_grid.add_child(_make_cell(fish))
	_rebuild_rewards()
	_fit_chrome()
	call_deferred("_fit_cells")


func _make_cell(fish: Dictionary) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.set_meta("id", str(fish.get("id", "")))
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	var rarity := str(fish.get("rarity", "common"))
	var frame := TextureRect.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame.stretch_mode = TextureRect.STRETCH_SCALE
	frame.texture = load(FRAME_FOR.get(rarity, FRAME_FOR["common"]))
	_fill(frame)
	btn.add_child(frame)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(str(fish.get("texture", "")))
	icon.anchor_left = 0.16
	icon.anchor_top = 0.14
	icon.anchor_right = 0.84
	icon.anchor_bottom = 0.5
	_zero_offsets(icon)
	btn.add_child(icon)
	var mark := Label.new()
	mark.name = "Mark"
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.text = "?"
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.anchor_left = 0.3
	mark.anchor_top = 0.22
	mark.anchor_right = 0.7
	mark.anchor_bottom = 0.46
	_zero_offsets(mark)
	btn.add_child(mark)
	var name_lab := Label.new()
	name_lab.name = "Name"
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lab.anchor_left = 0.1
	name_lab.anchor_top = 0.54
	name_lab.anchor_right = 0.9
	name_lab.anchor_bottom = 0.74
	_zero_offsets(name_lab)
	btn.add_child(name_lab)
	var meta := Label.new()
	meta.name = "Meta"
	meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
	meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.anchor_left = 0.08
	meta.anchor_top = 0.74
	meta.anchor_right = 0.92
	meta.anchor_bottom = 0.9
	_zero_offsets(meta)
	btn.add_child(meta)
	_paint_cell(btn, fish)
	btn.pressed.connect(_on_cell.bind(str(fish.get("id", ""))))
	return btn


func _paint_cell(btn: Button, fish: Dictionary) -> void:
	var id := str(fish.get("id", ""))
	var owned := int(_caught.get(id, 0)) > 0
	var icon := btn.get_node("Icon") as TextureRect
	var mark := btn.get_node("Mark") as Label
	var name_lab := btn.get_node("Name") as Label
	var meta := btn.get_node("Meta") as Label
	icon.modulate = Color.WHITE if owned else SILHOUETTE
	mark.visible = not owned
	name_lab.visible = owned
	meta.visible = owned
	if owned:
		name_lab.text = _fish_field(id, "name")
		meta.text = "%s  %s" % [_rarity_name(str(fish.get("rarity", "common"))), SettingsData.t("album_catches") % int(_caught.get(id, 0))]
		_paint(name_lab)
		_paint(meta)
	else:
		name_lab.text = ""
		meta.text = ""
		mark.add_theme_color_override("font_color", CREAM)
		mark.add_theme_constant_override("outline_size", 0)
		mark.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0))


func _fit_cells() -> void:
	if not is_node_ready():
		return
	var scroll_w := _scroll.size.x
	if scroll_w < 64.0:
		scroll_w = maxf(380.0, size.x * 0.72)
	var col_w := maxf(126.0, floor((scroll_w - 20.0) / 3.0))
	var col_h := maxf(168.0, col_w * 815.0 / 425.0)
	for btn in _grid.get_children():
		if not btn is Button:
			continue
		btn.custom_minimum_size = Vector2(col_w, col_h)
		var name_lab := btn.get_node_or_null("Name") as Label
		var meta := btn.get_node_or_null("Meta") as Label
		var mark := btn.get_node_or_null("Mark") as Label
		if name_lab != null and name_lab.visible:
			_paint(name_lab)
			UiFit.fit_label(name_lab, col_w * 0.78, 2, 14, 22)
		if meta != null and meta.visible:
			_paint(meta)
			UiFit.fit_label(meta, col_w * 0.8, 1, 13, 18)
		if mark != null and mark.visible:
			mark.add_theme_font_size_override("font_size", int(clampf(col_w * 0.28, 28, 64)))


func _rebuild_rewards() -> void:
	for child in _rewards.get_children():
		child.queue_free()
	var any := false
	for rarity in AlbumSave.RARITIES:
		if not AlbumSave.rarity_complete(_fishes, _caught, rarity):
			continue
		if bool(_claimed.get(rarity, false)):
			continue
		any = true
		var amount := AlbumSave.reward_amount(_db, rarity)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(126, 126)
		btn.text = "%s\n%s" % [_rarity_name(rarity), SettingsData.t("album_claim") % amount]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_paint(btn)
		btn.pressed.connect(_on_claim.bind(rarity))
		_rewards.add_child(btn)
	_rewards.visible = any


func _fit_chrome() -> void:
	if not is_node_ready():
		return
	var owned := 0
	for fish in _fishes:
		if int(_caught.get(str(fish.get("id", "")), 0)) > 0:
			owned += 1
	_title.text = SettingsData.t("album")
	_counter.text = "%d/12" % owned
	_close.text = SettingsData.t("album_back")
	_d_close.text = SettingsData.t("album_back")
	var width := maxf(200.0, _panel.size.x - 80.0)
	for lab in [_title, _counter, _close, _d_close]:
		_paint(lab)
	UiFit.fit_label(_title, width, 1, 28, 56)
	UiFit.fit_label(_counter, width, 1, 22, 36)
	UiFit.fit_label(_close, width, 1, 22, 40)
	UiFit.fit_label(_d_close, width, 1, 22, 40)
	if _debug.visible:
		$DebugRow/ResetBtn.text = SettingsData.t("album_reset")
		$DebugRow/UnlockBtn.text = SettingsData.t("album_unlock")
		_paint($DebugRow/ResetBtn)
		_paint($DebugRow/UnlockBtn)
	if _detail.visible and _open_id != "":
		_show_detail(_open_id)


func _on_cell(id: String) -> void:
	_show_detail(id)


func _show_detail(id: String) -> void:
	_open_id = id
	_detail.visible = true
	var fish := _fish_by_id(id)
	var owned := int(_caught.get(id, 0)) > 0
	var width := maxf(220.0, _detail_panel.size.x - 120.0)
	if _detail_panel.size.x < 64.0:
		width = minf(640.0, size.x * 0.8)
	if not owned:
		_d_title.text = ""
		_d_title.visible = false
		_d_rarity.visible = false
		_d_value_row.visible = false
		_d_since.visible = false
		_d_body.visible = true
		_d_body.text = SettingsData.t("album_missing")
		_paint(_d_body)
		UiFit.fit_label(_d_body, width, 3, 22, 36)
		return
	_d_title.visible = true
	_d_rarity.visible = true
	_d_body.visible = true
	_d_value_row.visible = true
	_d_title.text = _fish_field(id, "name")
	_d_rarity.text = _rarity_name(str(fish.get("rarity", "common")))
	_d_body.text = _fish_field(id, "description")
	_d_value.text = "+%d %s" % [int(fish.get("value", 0)), SettingsData.t("coins").to_lower()]
	var since := str(_first.get(id, ""))
	_d_since.visible = since != ""
	_d_since.text = SettingsData.t("album_since") % since
	for lab in [_d_title, _d_rarity, _d_body, _d_value, _d_since]:
		_paint(lab)
	UiFit.fit_label(_d_title, width, 2, 22, 48)
	UiFit.fit_label(_d_rarity, width, 1, 18, 28)
	UiFit.fit_label(_d_body, width, 4, 18, 30)
	UiFit.fit_label(_d_value, width * 0.7, 1, 18, 32)
	UiFit.fit_label(_d_since, width, 1, 16, 24)


func _on_claim(rarity: String) -> void:
	claim_requested.emit(rarity)


func _fish_by_id(id: String) -> Dictionary:
	for fish in _fishes:
		if str(fish.get("id", "")) == id:
			return fish
	return {}


func _fish_field(id: String, field: String) -> String:
	var entry = _strings.get("fish", {}).get(id, {})
	if typeof(entry) != TYPE_DICTIONARY:
		entry = {}
	for suffix in [SettingsData.lang, "es"]:
		if entry.has(field + "_" + suffix):
			return str(entry[field + "_" + suffix])
	var fish := _fish_by_id(id)
	return str(fish.get(field + "_es", fish.get(field, "")))


func _rarity_name(rarity: String) -> String:
	var entry = _strings.get("rarities", {}).get(rarity, {})
	if typeof(entry) == TYPE_DICTIONARY:
		if entry.has(SettingsData.lang):
			return str(entry[SettingsData.lang])
		if entry.has("es"):
			return str(entry["es"])
	return rarity


func _load_strings() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/strings.json"))
	_strings = data if typeof(data) == TYPE_DICTIONARY else {}


func _paint(node: Control) -> void:
	UiFit.paint_light(node, 32)


func _fill(node: Control) -> void:
	node.set_anchors_preset(Control.PRESET_FULL_RECT)
	_zero_offsets(node)


func _zero_offsets(node: Control) -> void:
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0
