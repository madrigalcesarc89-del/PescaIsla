extends Control
## Álbum anclado a la pantalla. Cuatro secciones, cuadrícula de 3 columnas.
## El panel no usa tamaño fijo: los márgenes son 48 px más el área segura.

const AlbumSave = preload("res://scripts/album_save.gd")
const FishRoll = preload("res://scripts/fish_roll.gd")

signal closed
signal claim_requested(rarity: String)
signal reset_requested
signal unlock_requested
signal repair_requested
signal grant_requested
signal coins_set_requested(amount: int)
signal shop_reset_requested
signal seen_committed(seen: Dictionary)

const CREAM := Color("FFF1D6")
const RARITY_COLOR := {
	"common": Color("E3B792"),
	"uncommon": Color("5CC8C2"),
	"rare": Color("B8A6E0"),
	"legendary": Color("E8C14A"),
}
const CARD_W := 288.0
const CARD_H := 372.0
const GAP := 24.0
const MARGIN := 48.0

var _fishes: Array = []
var _caught: Dictionary = {}
var _first: Dictionary = {}
var _claimed: Dictionary = {}
var _db: Dictionary = {}
var _seen: Dictionary = {}
var _seen_missing: bool = true
var _news: Dictionary = {}
var _strings: Dictionary = {}
var _card_w := CARD_W
var _card_h := CARD_H
var _tap_count := 0
var _tap_at := 0
var _debug: Control = null
var _laying := false
var _pointer_down := false
var _last_drag_y := 0.0
var _last_drag_ms := 0
var _scroll_vel := 0.0

@onready var _panel: Panel = $Panel
@onready var _vbox: VBoxContainer = $Panel/VBox
@onready var _title: Label = $Panel/VBox/Header/Title
@onready var _count_btn: Button = $Panel/VBox/Header/CountBtn
@onready var _count: Label = $Panel/VBox/Header/CountBtn/CountBox/Count
@onready var _close: Button = $Panel/VBox/Header/CloseBtn
@onready var _scroll: ScrollContainer = $Panel/VBox/Scroll
@onready var _sections: VBoxContainer = $Panel/VBox/Scroll/Sections
@onready var _inspect: Control = $Inspect


func _ready() -> void:
	_fill_rect(self)
	_fill_rect(_inspect)
	_inspect.mouse_filter = Control.MOUSE_FILTER_STOP
	_load_strings()
	var bg := StyleBoxFlat.new()
	bg.bg_color = CREAM
	bg.set_corner_radius_all(36)
	_panel.add_theme_stylebox_override("panel", bg)
	var pill := StyleBoxFlat.new()
	pill.bg_color = Color("FFF6E8")
	pill.set_corner_radius_all(32)
	pill.set_border_width_all(3)
	pill.border_color = Color("E3B792")
	pill.content_margin_left = 16
	pill.content_margin_right = 16
	for state_name in ["normal", "hover", "pressed", "focus"]:
		_count_btn.add_theme_stylebox_override(state_name, pill)
		_close.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	_close.pressed.connect(_hide_album)
	_count_btn.pressed.connect(_on_count_tap)
	_inspect.continued.connect(_hide_detail)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.scroll_deadzone = 8
	var vbar := _scroll.get_v_scroll_bar()
	vbar.custom_minimum_size = Vector2.ZERO
	vbar.modulate.a = 0.0
	vbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hbar := _scroll.get_h_scroll_bar()
	hbar.custom_minimum_size = Vector2.ZERO
	hbar.modulate.a = 0.0
	hbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_on_resized)
	_apply_margin()
	if OS.is_debug_build():
		_build_debug()
	visible = false


func _process(delta: float) -> void:
	if not visible or _pointer_down or _inspect == null or _inspect.visible:
		return
	if absf(_scroll_vel) < 30.0:
		_scroll_vel = 0.0
		return
	_scroll.scroll_vertical = int(float(_scroll.scroll_vertical) + _scroll_vel * delta)
	_scroll_vel *= exp(-3.2 * delta)


func _input(event: InputEvent) -> void:
	if not visible or _inspect == null or _inspect.visible:
		_pointer_down = false
		return
	var pos := Vector2.ZERO
	var is_press := false
	var went_down := false
	var moving := false
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT:
			return
		pos = mb.position
		is_press = true
		went_down = mb.pressed
	elif event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		pos = touch.position
		is_press = true
		went_down = touch.pressed
	elif event is InputEventMouseMotion and _pointer_down:
		pos = (event as InputEventMouseMotion).position
		moving = true
	elif event is InputEventScreenDrag and _pointer_down:
		pos = (event as InputEventScreenDrag).position
		moving = true
	else:
		return
	if is_press and went_down and not _scroll.get_global_rect().has_point(pos):
		return
	if is_press:
		_pointer_down = went_down
		_last_drag_y = pos.y
		_last_drag_ms = Time.get_ticks_msec()
		if went_down:
			_scroll_vel = 0.0
		return
	if moving:
		var now := Time.get_ticks_msec()
		var dt := maxi(1, now - _last_drag_ms)
		_scroll_vel = (_last_drag_y - pos.y) / float(dt) * 1000.0
		_last_drag_y = pos.y
		_last_drag_ms = now


func setup(fishes: Array, caught: Dictionary, first: Dictionary, claimed: Dictionary, db: Dictionary, seen: Dictionary = {}, seen_missing: bool = true) -> void:
	_fishes = fishes
	_caught = caught
	_first = first
	_claimed = claimed
	_db = db
	_seen = seen
	_seen_missing = seen_missing
	_load_strings()


func reload_visible() -> void:
	if is_node_ready() and visible:
		_rebuild()


func refresh_deferred() -> void:
	call_deferred("_rebuild")


func open_album() -> void:
	_force_full()
	var step: Dictionary = AlbumSave.news_and_next(_seen, _caught, _seen_missing)
	_news = step.get("news", {})
	_seen = step.get("seen", {})
	_seen_missing = false
	seen_committed.emit(_seen)
	visible = true
	_hide_detail()
	_rebuild()
	call_deferred("_relayout_open")
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx("open")


func is_detail_open() -> bool:
	return visible and _inspect != null and _inspect.visible


func consumes_back() -> bool:
	if not visible:
		return false
	if _inspect.visible:
		_hide_detail()
		return true
	_hide_album()
	return true


func play_reward(amount: int) -> void:
	var lab := Label.new()
	lab.text = "+%d" % amount
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(lab)
	_paint(lab)
	UiFit.fit_label(lab, 280.0, 1, 28, 48)
	lab.position = Vector2(_panel.size.x * 0.5 - 60.0, 160.0)
	var tw := lab.create_tween().set_parallel(true)
	tw.tween_property(lab, "position:y", 80.0, 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(lab, "modulate:a", 0.0, 0.7)
	tw.chain().tween_callback(func() -> void:
		if is_instance_valid(lab):
			lab.queue_free()
	)
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx("coin")


func _relayout_open() -> void:
	if not visible or not is_node_ready():
		return
	_force_full()
	var prev := _card_w
	_apply_margin()
	if absf(_card_w - prev) >= 0.5 or _sections.get_child_count() == 0:
		_rebuild()


func _force_full() -> void:
	var vr := get_viewport().get_visible_rect().size
	if vr.x < 64.0 or vr.y < 64.0:
		return
	_fill_rect(self)
	if size.x < vr.x * 0.92 or size.y < vr.y * 0.92:
		global_position = Vector2.ZERO
		size = vr


func _view_size() -> Vector2:
	var vp := get_viewport().get_visible_rect().size
	var s := size
	if s.x < 64.0 or s.y < 64.0:
		s = vp
	if vp.x >= 64.0 and s.x > vp.x + 1.0:
		s.x = vp.x
	if vp.y >= 64.0 and s.y > vp.y + 1.0:
		s.y = vp.y
	if s.x < 64.0 or s.y < 64.0:
		s = Vector2(1080, 1920)
	return s


func _fill_rect(c: Control) -> void:
	if c == null:
		return
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.grow_horizontal = Control.GROW_DIRECTION_BOTH
	c.grow_vertical = Control.GROW_DIRECTION_BOTH


func _on_resized() -> void:
	if _laying or not visible or not is_node_ready():
		return
	var prev := _card_w
	_apply_margin()
	if absf(_card_w - prev) < 0.5 and _sections.get_child_count() > 0:
		return
	_rebuild()


func _margins() -> Vector4:
	var left := MARGIN
	var top := MARGIN
	var right := MARGIN
	var bottom := MARGIN
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	var view := _view_size()
	if win.x > 1 and win.y > 1 and view.x > 1.0:
		var sx := view.x / float(win.x)
		var sy := view.y / float(win.y)
		var safe_left := maxf(0.0, float(sa.position.x)) * sx
		var safe_right := maxf(0.0, float(win.x) - float(sa.end.x)) * sx
		var side := maxf(safe_left, safe_right)
		left += side
		right += side
		top += maxf(0.0, float(sa.position.y)) * sy
		bottom += maxf(0.0, float(win.y) - float(sa.end.y)) * sy
	return Vector4(left, top, right, bottom)


func _apply_margin() -> void:
	var m := _margins()
	_panel.anchor_left = 0.0
	_panel.anchor_top = 0.0
	_panel.anchor_right = 1.0
	_panel.anchor_bottom = 1.0
	_panel.offset_left = m.x
	_panel.offset_top = m.y
	_panel.offset_right = -m.z
	_panel.offset_bottom = -m.w
	_panel.custom_minimum_size = Vector2.ZERO
	var view := _view_size()
	var available := maxf(240.0, view.x - m.x - m.z)
	if _panel.size.x >= 64.0:
		available = minf(available, _panel.size.x)
	available = minf(available, maxf(240.0, view.x - MARGIN * 2.0))
	var cap := minf(available, CARD_W * 3.0 + GAP * 2.0)
	var card := floorf((cap - GAP * 2.0) / 3.0)
	_card_w = clampf(card, 96.0, CARD_W)
	_card_h = _card_w * CARD_H / CARD_W
	var col := _card_w * 3.0 + GAP * 2.0
	var half_l := floorf(col * 0.5)
	var half_r := col - half_l
	_vbox.anchor_left = 0.5
	_vbox.anchor_right = 0.5
	_vbox.anchor_top = 0.0
	_vbox.anchor_bottom = 1.0
	_vbox.offset_left = -half_l
	_vbox.offset_right = half_r
	_vbox.offset_top = 8.0
	_vbox.offset_bottom = -8.0
	_vbox.custom_minimum_size = Vector2.ZERO
	_sections.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_sections.custom_minimum_size = Vector2(col, 0)


func _content_width() -> float:
	return _card_w * 3.0 + GAP * 2.0


func _rebuild() -> void:
	if not is_node_ready():
		return
	_laying = true
	_apply_margin()
	for child in _sections.get_children():
		_sections.remove_child(child)
		child.free()
	var owned := 0
	for fish in _fishes:
		if int(_caught.get(str(fish.get("id", "")), 0)) > 0:
			owned += 1
	_title.text = SettingsData.t("album")
	_count.text = "%d/12" % owned
	_paint(_title)
	_paint(_count)
	var title_room := maxf(80.0, _content_width() - 132.0 - 180.0)
	UiFit.fit_label(_title, title_room, 1, 32, 64)
	UiFit.fit_label(_count, 120.0, 1, 22, 32)
	_measure_cards()
	for rarity in AlbumSave.RARITIES:
		_sections.add_child(_make_section(rarity))
	_sections.custom_minimum_size = Vector2(_content_width(), 0)
	_laying = false


func _measure_cards() -> void:
	var inner := _content_width()
	var card_w := minf(CARD_W, floorf((inner - GAP * 2.0) / 3.0))
	_card_w = maxf(96.0, card_w)
	_card_h = _card_w * CARD_H / CARD_W


func _make_section(rarity: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.clip_contents = true
	box.add_child(_make_section_head(rarity))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", int(GAP))
	grid.add_theme_constant_override("v_separation", int(GAP))
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for fish in _fishes:
		if typeof(fish) != TYPE_DICTIONARY:
			continue
		if str(fish.get("rarity", "")) != rarity:
			continue
		grid.add_child(_make_card(fish))
	box.add_child(grid)
	return box


func _make_section_head(rarity: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(28, 28)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ds := StyleBoxFlat.new()
	ds.bg_color = RARITY_COLOR[rarity]
	ds.set_corner_radius_all(8)
	dot.add_theme_stylebox_override("panel", ds)
	row.add_child(dot)
	var info := rarity_count_safe(rarity)
	var clip := Control.new()
	clip.clip_contents = true
	clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clip.custom_minimum_size = Vector2(48, 44)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var name_lab := Label.new()
	name_lab.name = "RarityName"
	name_lab.set_anchors_preset(Control.PRESET_FULL_RECT)
	name_lab.anchor_right = 1.0
	name_lab.anchor_bottom = 1.0
	name_lab.text = _rarity_name(rarity)
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lab.clip_text = true
	name_lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint(name_lab)
	name_lab.add_theme_font_size_override("font_size", 32)
	clip.add_child(name_lab)
	clip.resized.connect(func() -> void:
		if clip.size.x > 24.0:
			UiFit.fit_label(name_lab, clip.size.x, 1, 22, 32)
	)
	row.add_child(clip)
	var prog := Label.new()
	prog.name = "Progress"
	prog.text = "%d/%d" % [int(info["have"]), int(info["total"])]
	prog.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_paint(prog)
	prog.add_theme_font_size_override("font_size", 28)
	row.add_child(prog)
	row.add_child(_make_reward(rarity))
	return row


func rarity_count_safe(rarity: String) -> Dictionary:
	return AlbumSave.rarity_count(_fishes, _caught, rarity)


func _make_reward(rarity: String) -> Control:
	var amount := AlbumSave.reward_amount(_db, rarity)
	if AlbumSave.can_claim(_fishes, _caught, _claimed, rarity):
		var btn := Button.new()
		btn.name = "Claim"
		btn.text = SettingsData.t("album_claim") % amount
		btn.custom_minimum_size = Vector2(200, 88)
		btn.focus_mode = Control.FOCUS_NONE
		btn.clip_text = true
		var style := _reward_style(RARITY_COLOR[rarity])
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state_name, style)
		_paint(btn)
		UiFit.fit_label(btn, 168.0, 2, 16, 24)
		btn.pressed.connect(_on_claim.bind(rarity))
		return btn
	var box := HBoxContainer.new()
	box.name = "Reward"
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_END
	var icon := TextureRect.new()
	icon.name = "RewardIcon"
	icon.custom_minimum_size = Vector2(40, 40)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var done := AlbumSave.group_complete(_fishes, _caught, rarity) and bool(_claimed.get(rarity, false))
	var path := "res://assets/art/ui/icon_check.png" if done else "res://assets/art/ui/icon_lock.png"
	icon.texture = load(path)
	box.add_child(icon)
	if not done:
		var lab := Label.new()
		lab.name = "RewardAmount"
		lab.text = "+%d" % amount
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_paint(lab)
		lab.add_theme_font_size_override("font_size", 24)
		box.add_child(lab)
	return box


func _reward_style(border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = border
	style.set_border_width_all(4)
	style.set_corner_radius_all(18)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style


func _make_card(fish: Dictionary) -> Button:
	var id := str(fish.get("id", ""))
	var rarity := str(fish.get("rarity", "common"))
	var owned := int(_caught.get(id, 0)) > 0
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_NONE
	btn.clip_contents = true
	btn.custom_minimum_size = Vector2(_card_w, _card_h)
	btn.set_meta("id", id)
	var style := StyleBoxFlat.new()
	style.bg_color = CREAM
	style.border_color = RARITY_COLOR[rarity]
	style.set_border_width_all(4)
	style.set_corner_radius_all(int(clampf(_card_w * 0.08, 16, 28)))
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = load(str(fish.get("texture", "")))
	icon.modulate = Color.WHITE if owned else Color(0, 0, 0, 1)
	_place(icon, 0.08, 0.06, 0.92, 0.06 + 170.0 / CARD_H)
	btn.add_child(icon)
	if owned and bool(_news.get(id, false)):
		icon.modulate = Color(0, 0, 0, 1)
		var tw := icon.create_tween()
		tw.tween_property(icon, "modulate", Color(1.75, 1.7, 1.35, 1.0), 0.14)
		tw.tween_property(icon, "modulate", Color.WHITE, 0.24)
	var name_lab := Label.new()
	name_lab.name = "Name"
	name_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(name_lab, 0.06, 0.56, 0.94, 0.78)
	btn.add_child(name_lab)
	_paint(name_lab)
	if not owned:
		name_lab.text = "???"
		UiFit.fit_label(name_lab, _card_w * 0.86, 1, 26, 32)
	else:
		name_lab.text = _fish_field(id, "name")
		UiFit.fit_label(name_lab, _card_w * 0.86, 2, 26, 32)
		var meta := HBoxContainer.new()
		meta.name = "Meta"
		meta.mouse_filter = Control.MOUSE_FILTER_IGNORE
		meta.alignment = BoxContainer.ALIGNMENT_CENTER
		meta.add_theme_constant_override("separation", 8)
		_place(meta, 0.06, 0.78, 0.94, 0.94)
		var catches := Label.new()
		catches.name = "Catches"
		catches.text = SettingsData.t("album_catches") % int(_caught.get(id, 0))
		catches.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		catches.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_paint(catches)
		UiFit.fit_label(catches, _card_w * 0.28, 1, 16, 22)
		var pip := ColorRect.new()
		pip.custom_minimum_size = Vector2(16, 16)
		pip.color = RARITY_COLOR[rarity]
		pip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var badge := Label.new()
		badge.name = "Badge"
		badge.text = _rarity_name(rarity)
		badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		badge.clip_text = true
		badge.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_paint(badge)
		UiFit.fit_label(badge, _card_w * 0.46, 1, 16, 22)
		meta.add_child(catches)
		meta.add_child(pip)
		meta.add_child(badge)
		btn.add_child(meta)
		if bool(_news.get(id, false)):
			var dot := ColorRect.new()
			dot.name = "NewDot"
			dot.color = Color("E25B45")
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_place(dot, 0.84, 0.05, 0.94, 0.13)
			btn.add_child(dot)
	btn.pressed.connect(_on_card.bind(id))
	return btn


func _on_card(id: String) -> void:
	var fish := _fish_by_id(id)
	var owned := int(_caught.get(id, 0)) > 0
	var rarity := str(fish.get("rarity", "common"))
	var tex: Texture2D = load(str(fish.get("texture", "")))
	if not owned:
		_inspect.show_fish("frame_" + rarity, tex, "", "", "", SettingsData.t("album_missing"), _night_line(fish))
	else:
		var extra := SettingsData.t("album_catches") % int(_caught.get(id, 0))
		var since := str(_first.get(id, ""))
		if since != "":
			extra += "\n" + (SettingsData.t("album_since") % since)
		var night := _night_line(fish)
		if night != "":
			extra += "\n" + night
		_inspect.show_fish(
			"frame_" + rarity,
			tex,
			_fish_field(id, "name"),
			_rarity_name(rarity),
			"+%d %s" % [int(fish.get("value", 0)), SettingsData.t("coins").to_lower()],
			_fish_field(id, "description"),
			extra
		)
	var icon := _inspect.find_child("FishIcon", true, false) as CanvasItem
	if icon != null:
		icon.modulate = Color.WHITE if owned else Color(0, 0, 0, 1)


func _night_line(fish: Dictionary) -> String:
	if FishRoll.more_at_night(fish):
		return SettingsData.t("fish_more_night")
	return ""


func _on_claim(rarity: String) -> void:
	claim_requested.emit(rarity)


func _on_count_tap() -> void:
	if not OS.is_debug_build() or _debug == null:
		return
	var now := Time.get_ticks_msec()
	if now - _tap_at > 1200:
		_tap_count = 0
	_tap_at = now
	_tap_count += 1
	if _tap_count >= 5:
		_tap_count = 0
		_debug.visible = not _debug.visible


func _build_debug() -> void:
	var panel := PanelContainer.new()
	panel.name = "DebugPanel"
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -248.0
	panel.offset_right = 248.0
	panel.offset_top = -980.0
	panel.offset_bottom = -36.0
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 16)
	var reset := Button.new()
	reset.text = SettingsData.t("album_reset")
	reset.custom_minimum_size = Vector2(200, 88)
	reset.pressed.connect(func() -> void: reset_requested.emit())
	var unlock := Button.new()
	unlock.text = SettingsData.t("album_unlock")
	unlock.custom_minimum_size = Vector2(200, 88)
	unlock.pressed.connect(func() -> void: unlock_requested.emit())
	var repair := Button.new()
	repair.name = "Repair"
	repair.text = SettingsData.t("album_repair")
	repair.custom_minimum_size = Vector2(416, 80)
	repair.pressed.connect(func() -> void: repair_requested.emit())
	_paint(reset)
	_paint(unlock)
	_paint(repair)
	var grant := Button.new()
	grant.text = SettingsData.t("shop_debug_coins")
	grant.custom_minimum_size = Vector2(416, 80)
	grant.pressed.connect(func() -> void: grant_requested.emit())
	var shop_reset := Button.new()
	shop_reset.text = SettingsData.t("shop_debug_reset")
	shop_reset.custom_minimum_size = Vector2(416, 80)
	shop_reset.pressed.connect(func() -> void: shop_reset_requested.emit())
	_paint(grant)
	_paint(shop_reset)
	var title := Label.new()
	title.text = SettingsData.t("shop_debug_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint(title)
	var field := LineEdit.new()
	field.name = "CoinField"
	field.placeholder_text = SettingsData.t("shop_debug_amount")
	field.alignment = HORIZONTAL_ALIGNMENT_CENTER
	field.max_length = 7
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.custom_minimum_size = Vector2(416, 88)
	field.add_theme_font_size_override("font_size", 32)
	field.add_theme_color_override("font_color", Color("5A3D2B"))
	field.add_theme_color_override("font_placeholder_color", Color("6B4A38"))
	field.add_theme_constant_override("outline_size", 0)
	var field_box := StyleBoxFlat.new()
	field_box.bg_color = Color("FFF1D6")
	field_box.border_color = Color("E3B792")
	field_box.set_border_width_all(3)
	field_box.set_corner_radius_all(18)
	field_box.content_margin_left = 16
	field_box.content_margin_right = 16
	field.add_theme_stylebox_override("normal", field_box)
	var set_coins := Button.new()
	set_coins.name = "SetCoins"
	set_coins.text = SettingsData.t("shop_debug_set")
	set_coins.custom_minimum_size = Vector2(416, 88)
	set_coins.pressed.connect(func() -> void:
		var raw := field.text.strip_edges()
		if not raw.is_valid_int():
			return
		var n := int(raw)
		if n < 0:
			return
		if n > 9999999:
			n = 9999999
		coins_set_requested.emit(n)
	)
	_paint(set_coins)
	row.add_child(reset)
	row.add_child(unlock)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.add_child(title)
	col.add_child(field)
	col.add_child(set_coins)
	col.add_child(row)
	col.add_child(repair)
	col.add_child(grant)
	col.add_child(shop_reset)
	panel.add_child(col)
	add_child(panel)
	_debug = panel


func _hide_album() -> void:
	_hide_detail()
	visible = false
	if _debug != null:
		_debug.visible = false
	closed.emit()


func _hide_detail() -> void:
	if _inspect != null:
		_inspect.hide_card()


func _place(node: Control, left: float, top: float, right: float, bottom: float) -> void:
	node.anchor_left = left
	node.anchor_top = top
	node.anchor_right = right
	node.anchor_bottom = bottom
	node.offset_left = 0.0
	node.offset_top = 0.0
	node.offset_right = 0.0
	node.offset_bottom = 0.0


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
