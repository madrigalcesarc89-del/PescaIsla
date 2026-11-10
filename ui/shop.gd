extends Control
## Tienda anclada como el álbum. No toca el mundo 3D.

const ShopSave = preload("res://scripts/shop_save.gd")

signal purchase_requested(id: String)
signal equip_requested(id: String)
signal place_requested(id: String)
signal closed

const CREAM := Color("FFF1D6")
const PAPER := Color("FFF6E8")
const INK := Color("5A3D2B")
const MUTED := Color("6B4A38")
const PEACH := Color("F7B7A3")
const LINE := Color("E3B792")
const MARGIN := 48.0

var _coins := 0
var _state: Dictionary = {}
var _tab := "rod"
var _col_w := 912.0
var _locked := false
var _pending_id := ""
var _laying := false
var _pointer_down := false
var _last_drag_y := 0.0
var _last_drag_ms := 0
var _scroll_vel := 0.0
var _coin_tw: Tween = null

var _confirm: Control
var _confirm_box: Panel
var _confirm_title: Label
var _confirm_cost: Label
var _yes_btn: Button
var _no_btn: Button

@onready var _panel: Panel = $Panel
@onready var _vbox: VBoxContainer = $Panel/VBox
@onready var _title: Label = $Panel/VBox/Header/Title
@onready var _coins_label: Label = $Panel/VBox/Header/CoinPill/CoinBox/Coins
@onready var _coin_pill: PanelContainer = $Panel/VBox/Header/CoinPill
@onready var _close: Button = $Panel/VBox/Header/CloseBtn
@onready var _tabs: HBoxContainer = $Panel/VBox/Tabs
@onready var _scroll: ScrollContainer = $Panel/VBox/Scroll
@onready var _list: VBoxContainer = $Panel/VBox/Scroll/List


func _ready() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = CREAM
	bg.set_corner_radius_all(36)
	_panel.add_theme_stylebox_override("panel", bg)
	var pill := _box(PAPER, LINE, 3, 28)
	pill.content_margin_left = 16
	pill.content_margin_right = 16
	_coin_pill.add_theme_stylebox_override("panel", pill)
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		_close.add_theme_stylebox_override(state_name, StyleBoxEmpty.new())
	_close.pressed.connect(_on_close)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.scroll_deadzone = 8
	_hide_bar(_scroll.get_v_scroll_bar())
	_hide_bar(_scroll.get_h_scroll_bar())
	_build_tabs()
	_build_confirm()
	resized.connect(_on_resized)
	_apply_margin()
	_paint(_title, 64)
	_paint(_coins_label, 32)
	visible = false


func _process(delta: float) -> void:
	if not visible or _pointer_down or (_confirm != null and _confirm.visible):
		return
	if absf(_scroll_vel) < 30.0:
		_scroll_vel = 0.0
		return
	_scroll.scroll_vertical = int(float(_scroll.scroll_vertical) + _scroll_vel * delta)
	_scroll_vel *= exp(-3.2 * delta)


func _input(event: InputEvent) -> void:
	if not visible or _confirm == null or _confirm.visible:
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


func open_shop(coins: int, state: Dictionary) -> void:
	_coins = coins
	_state = state
	_pending_id = ""
	visible = true
	_hide_confirm()
	_laying = true
	_apply_margin()
	_rebuild()
	_layout_confirm()
	_laying = false
	_scroll.scroll_vertical = 0
	_play("open")


func sync_state(coins: int, state: Dictionary) -> void:
	var frm := _coins
	_coins = coins
	_state = state
	_animate_coins(frm, coins)
	if visible:
		_rebuild()


func notify(ok: bool, id: String, new_coins: int, state: Dictionary) -> void:
	if not ok:
		return
	var frm := _coins
	_coins = new_coins
	_state = state
	_animate_coins(frm, new_coins)
	var card := _list.find_child(id, false, false) as Control
	if card != null:
		_flash(card)


func is_confirm_open() -> bool:
	return visible and _confirm != null and _confirm.visible


func consumes_back() -> bool:
	if not visible:
		return false
	if _confirm != null and _confirm.visible:
		_hide_confirm()
		_play("close")
		return true
	_hide_shop()
	return true


func reload_locale() -> void:
	if not visible:
		return
	_rebuild()
	if _confirm != null and _confirm.visible and _pending_id != "":
		var item := ShopSave.item_by_id(_pending_id)
		if not item.is_empty():
			_fill_confirm(item)


func _on_close() -> void:
	consumes_back()


func _hide_shop() -> void:
	_hide_confirm()
	visible = false
	_pointer_down = false
	closed.emit()
	_play("close")


func _on_resized() -> void:
	if _laying or not is_node_ready():
		return
	_laying = true
	_apply_margin()
	if visible:
		_rebuild()
	_layout_confirm()
	_laying = false


func _margins() -> Vector4:
	var left := MARGIN
	var top := MARGIN
	var right := MARGIN
	var bottom := MARGIN
	var sa := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x > 1 and win.y > 1 and size.x > 1.0:
		var sx := size.x / float(win.x)
		var sy := size.y / float(win.y)
		var side: float = maxf(maxf(0.0, float(sa.position.x)) * sx, maxf(0.0, float(win.x) - float(sa.end.x)) * sx)
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
	var available := maxf(240.0, size.x - m.x - m.z)
	if size.x < 64.0:
		available = 1080.0 - MARGIN * 2.0
	_col_w = minf(available, 912.0)
	var half_l := floorf(_col_w * 0.5)
	var half_r := _col_w - half_l
	_vbox.anchor_left = 0.5
	_vbox.anchor_right = 0.5
	_vbox.anchor_top = 0.0
	_vbox.anchor_bottom = 1.0
	_vbox.offset_left = -half_l
	_vbox.offset_top = 8.0
	_vbox.offset_right = half_r
	_vbox.offset_bottom = -8.0
	_vbox.custom_minimum_size = Vector2.ZERO


func _rebuild() -> void:
	_title.text = SettingsData.t("shop")
	_paint(_title, 64)
	UiFit.fit_label(_title, maxf(80.0, _col_w - 420.0), 1, 40, 64)
	_paint_coins(_coins)
	_style_tabs()
	for child in _list.get_children():
		child.free()
	var items: Array = ShopSave.items_in(_tab)
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var card := _make_card(it)
		_list.add_child(card)
		_fit_card(card)


func _make_card(item: Dictionary) -> Control:
	var id := str(item.get("id", ""))
	var cat := str(item.get("category", ""))
	var owned := (_state.get("owned", []) as Array).has(id)
	var card := PanelContainer.new()
	card.name = id
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, 150)
	card.add_theme_stylebox_override("panel", _box(PAPER, LINE, 4, 28))
	var row := HBoxContainer.new()
	row.name = "Row"
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.custom_minimum_size = Vector2(126, 126)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _tex(str(item.get("icon", "")))
	row.add_child(icon)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	row.add_child(info)
	var name_lab := Label.new()
	name_lab.name = "Name"
	name_lab.text = SettingsData.t(str(item.get("name", "")))
	_paint(name_lab, 32)
	info.add_child(name_lab)
	var effect := Label.new()
	effect.name = "Effect"
	effect.text = ShopSave.effect_line(item)
	_paint(effect, 26)
	info.add_child(effect)
	var price_row := HBoxContainer.new()
	price_row.add_theme_constant_override("separation", 6)
	info.add_child(price_row)
	var coin := TextureRect.new()
	coin.custom_minimum_size = Vector2(36, 36)
	coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin.texture = _tex("res://assets/art/ui/icon_coin.png")
	price_row.add_child(coin)
	var price := Label.new()
	price.name = "Price"
	price.text = str(int(item.get("price", 0)))
	price.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var poor: bool = (not owned) and _coins < int(item.get("price", 0))
	if cat == "bait" and int(item.get("pack_size", 0)) > 0:
		poor = _coins < int(item.get("price", 0))
	_paint(price, 28)
	if poor:
		price.add_theme_color_override("font_color", MUTED)
	price_row.add_child(price)
	if cat == "bait":
		var qty := Label.new()
		qty.name = "Qty"
		qty.text = _qty_text(item, owned)
		qty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_paint(qty, 26)
		price_row.add_child(qty)
	_add_actions(row, item, owned, cat)
	return card


func _fit_card(card: Control) -> void:
	var name_lab := card.find_child("Name", true, false) as Label
	var effect := card.find_child("Effect", true, false) as Label
	var price := card.find_child("Price", true, false) as Label
	var qty := card.find_child("Qty", true, false) as Label
	var actions := card.find_child("Actions", true, false) as Control
	var actions_w := 0.0
	if actions != null:
		actions_w = actions.get_combined_minimum_size().x
	var text_w := maxf(80.0, _col_w - 126.0 - actions_w - 80.0)
	if name_lab != null:
		UiFit.fit_label(name_lab, text_w, 1, 20, 32)
	if effect != null:
		UiFit.fit_label(effect, text_w, 1, 18, 26)
	if price != null:
		UiFit.fit_label(price, text_w * 0.5, 1, 18, 28)
	if qty != null:
		UiFit.fit_label(qty, text_w * 0.4, 1, 16, 26)
	if actions == null:
		return
	for child in actions.get_children():
		if child is Button:
			var bw: float = (child as Control).custom_minimum_size.x
			UiFit.fit_label(child, maxf(80.0, bw - 28.0), 1, 16, 28)


func _add_actions(row: HBoxContainer, item: Dictionary, owned: bool, cat: String) -> float:
	var id := str(item.get("id", ""))
	var box := HBoxContainer.new()
	box.name = "Actions"
	box.add_theme_constant_override("separation", 8)
	box.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(box)
	var count := 0
	if cat == "rod" and owned:
		var equipped := str(_state.get("equipped_rod", "")) == id
		box.add_child(_action_button("Equip", equipped, SettingsData.t("shop_equipped_f") if equipped else SettingsData.t("shop_equip"), id, "equip"))
		count += 1
	elif cat == "bait" and (owned or ShopSave.is_infinite(id)):
		var equipped_b := str(_state.get("equipped_bait", "")) == id
		var have: bool = ShopSave.is_infinite(id) or int((_state.get("bait_qty", {}) as Dictionary).get(id, 0)) > 0
		if have:
			box.add_child(_action_button("Equip", equipped_b, SettingsData.t("shop_equipped_m") if equipped_b else SettingsData.t("shop_equip"), id, "equip"))
			count += 1
	elif cat == "decor" and owned:
		var placed := (_state.get("decor_placed", {}) as Dictionary).has(id)
		box.add_child(_action_button("Place", placed, SettingsData.t("shop_placed") if placed else SettingsData.t("shop_place"), id, "place"))
		count += 1
	var show_buy: bool = false
	if cat == "bait":
		show_buy = int(item.get("pack_size", 0)) > 0
	elif not owned:
		show_buy = true
	if show_buy:
		box.add_child(_action_button("Buy", false, SettingsData.t("shop_buy"), id, "buy"))
		count += 1
	var bw := 168.0 if count > 1 else 220.0
	for child in box.get_children():
		(child as Control).custom_minimum_size = Vector2(bw, 126)
	return bw * float(count) + 8.0 * float(maxi(0, count - 1))


func _action_button(node_name: String, done: bool, text: String, id: String, kind: String) -> Button:
	var btn := Button.new()
	btn.name = node_name
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = text
	btn.clip_contents = true
	var face := PAPER if done or kind != "buy" else PEACH
	var border := Color("5CC8C2") if done else LINE
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state_name, _box(face, border, 4, 28))
	_paint(btn, 28)
	btn.add_theme_color_override("font_disabled_color", INK)
	btn.add_theme_color_override("font_hover_color", INK)
	btn.add_theme_color_override("font_pressed_color", INK)
	UiFit.fit_label(btn, 150.0 if kind == "buy" else 190.0, 1, 16, 28)
	if kind == "buy":
		btn.pressed.connect(func() -> void: _on_buy(id, btn))
	elif kind == "equip":
		btn.pressed.connect(func() -> void: _on_equip(id, btn))
	else:
		btn.pressed.connect(func() -> void: _on_place(id, btn))
	return btn


func _on_buy(id: String, btn: Button) -> void:
	if _locked:
		return
	var item := ShopSave.item_by_id(id)
	var price := int(item.get("price", 0))
	if not ShopSave.can_buy(_coins, _state, id):
		_play("deny")
		_arm_lock(btn, false)
		return
	if price >= 500:
		_pending_id = id
		_show_confirm(item)
		return
	_arm_lock(btn, true)
	purchase_requested.emit(id)


func _on_equip(id: String, btn: Button) -> void:
	if _locked:
		return
	var cat := str(ShopSave.item_by_id(id).get("category", ""))
	var current := str(_state.get("equipped_rod", "")) if cat == "rod" else str(_state.get("equipped_bait", ""))
	if current == id:
		return
	_arm_lock(btn, true)
	_play("tap")
	equip_requested.emit(id)


func _on_place(id: String, btn: Button) -> void:
	if _locked:
		return
	if (_state.get("decor_placed", {}) as Dictionary).has(id):
		return
	_arm_lock(btn, true)
	_play("tap")
	place_requested.emit(id)


func _on_confirm_yes() -> void:
	if _locked:
		return
	var id := _pending_id
	if id == "" or not ShopSave.can_buy(_coins, _state, id):
		_play("deny")
		_hide_confirm()
		return
	_arm_lock(_yes_btn, true)
	_hide_confirm()
	purchase_requested.emit(id)


func _arm_lock(btn: Button, rebuild_after: bool) -> void:
	_locked = true
	if btn != null and is_instance_valid(btn):
		btn.disabled = true
	var tw := create_tween()
	tw.tween_interval(0.4)
	tw.tween_callback(func() -> void:
		_locked = false
		if btn != null and is_instance_valid(btn):
			btn.disabled = false
		if rebuild_after and is_inside_tree():
			_rebuild()
	)


func _qty_text(item: Dictionary, _owned: bool) -> String:
	var id := str(item.get("id", ""))
	if ShopSave.is_infinite(id):
		return SettingsData.t("shop_infinite")
	var n := int((_state.get("bait_qty", {}) as Dictionary).get(id, 0))
	return SettingsData.t("shop_qty") % n


func _build_tabs() -> void:
	_add_tab("rod", "res://assets/art/shop/rod_bamboo.png")
	_add_tab("bait", "res://assets/art/shop/bait_pink_worm.png")
	_add_tab("decor", "res://assets/art/shop/deco_plant.png")


func _add_tab(cat: String, icon_path: String) -> void:
	var btn := Button.new()
	btn.name = "Tab_" + cat
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = ""
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.custom_minimum_size = Vector2(160, 126)
	btn.clip_contents = true
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8.0
	box.offset_top = 10.0
	box.offset_right = -8.0
	box.offset_bottom = -10.0
	btn.add_child(box)
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(48, 48)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = _tex(icon_path)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var lab := Label.new()
	lab.name = "TabText"
	lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(lab)
	btn.pressed.connect(func() -> void: _select_tab(cat))
	_tabs.add_child(btn)


func _select_tab(cat: String) -> void:
	if _locked or _tab == cat:
		_style_tabs()
		return
	_tab = cat
	_scroll.scroll_vertical = 0
	_play("tap")
	_rebuild()


func _style_tabs() -> void:
	var labels := {"rod": "shop_tab_rod", "bait": "shop_tab_bait", "decor": "shop_tab_decor"}
	for cat in labels.keys():
		var btn := _tabs.get_node_or_null("Tab_" + cat) as Button
		if btn == null:
			continue
		var on: bool = str(cat) == _tab
		var face: Color = PEACH if on else PAPER
		for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
			btn.add_theme_stylebox_override(state_name, _box(face, LINE, 4, 28))
		var lab := btn.find_child("TabText", true, false) as Label
		if lab == null:
			continue
		lab.text = SettingsData.t(str(labels[cat]))
		_paint(lab, 28)
		UiFit.fit_label(lab, maxf(80.0, _col_w / 3.0 - 36.0), 1, 16, 28)


func _build_confirm() -> void:
	_confirm = Control.new()
	_confirm.name = "Confirm"
	_confirm.visible = false
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_confirm)
	var dim := ColorRect.new()
	dim.color = Color(0.22, 0.14, 0.1, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm.add_child(dim)
	_confirm_box = Panel.new()
	_confirm_box.name = "Box"
	var panel_bg := _box(CREAM, LINE, 4, 32)
	_confirm_box.add_theme_stylebox_override("panel", panel_bg)
	_confirm.add_child(_confirm_box)
	var col := VBoxContainer.new()
	col.name = "Col"
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 28.0
	col.offset_top = 28.0
	col.offset_right = -28.0
	col.offset_bottom = -28.0
	col.add_theme_constant_override("separation", 16)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_confirm_box.add_child(col)
	_confirm_title = Label.new()
	_confirm_title.name = "ConfirmTitle"
	_confirm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint(_confirm_title, 40)
	col.add_child(_confirm_title)
	_confirm_cost = Label.new()
	_confirm_cost.name = "ConfirmCost"
	_confirm_cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_paint(_confirm_cost, 28)
	col.add_child(_confirm_cost)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	_yes_btn = Button.new()
	_yes_btn.name = "ConfirmYes"
	_yes_btn.focus_mode = Control.FOCUS_NONE
	_yes_btn.custom_minimum_size = Vector2(240, 126)
	_yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		_yes_btn.add_theme_stylebox_override(state_name, _box(PEACH, LINE, 4, 28))
	_paint(_yes_btn, 28)
	_yes_btn.add_theme_color_override("font_disabled_color", INK)
	_yes_btn.pressed.connect(_on_confirm_yes)
	buttons.add_child(_yes_btn)
	_no_btn = Button.new()
	_no_btn.name = "ConfirmNo"
	_no_btn.focus_mode = Control.FOCUS_NONE
	_no_btn.custom_minimum_size = Vector2(240, 126)
	_no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		_no_btn.add_theme_stylebox_override(state_name, _box(PAPER, LINE, 4, 28))
	_paint(_no_btn, 28)
	_no_btn.pressed.connect(func() -> void:
		_hide_confirm()
		_play("close")
	)
	buttons.add_child(_no_btn)


func _show_confirm(item: Dictionary) -> void:
	_fill_confirm(item)
	_layout_confirm()
	_confirm.visible = true
	_confirm.mouse_filter = Control.MOUSE_FILTER_STOP
	_play("open")


func _fill_confirm(item: Dictionary) -> void:
	var label := SettingsData.t(str(item.get("name", "")))
	_confirm_title.text = SettingsData.t("shop_confirm") % label
	_confirm_cost.text = SettingsData.t("shop_confirm_cost") % int(item.get("price", 0))
	_yes_btn.text = SettingsData.t("shop_buy")
	_no_btn.text = SettingsData.t("shop_cancel")
	_paint(_confirm_title, 40)
	_paint(_confirm_cost, 28)
	_paint(_yes_btn, 28)
	_paint(_no_btn, 28)
	var inner := maxf(120.0, minf(720.0, size.x - 160.0) - 80.0)
	UiFit.fit_label(_confirm_title, inner, 2, 24, 40)
	UiFit.fit_label(_confirm_cost, inner, 2, 20, 28)
	UiFit.fit_label(_yes_btn, 220.0, 1, 18, 28)
	UiFit.fit_label(_no_btn, 220.0, 1, 18, 28)


func _hide_confirm() -> void:
	_pending_id = ""
	if _confirm != null:
		_confirm.visible = false
		_confirm.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout_confirm() -> void:
	if _confirm_box == null:
		return
	var box_w := minf(760.0, maxf(560.0, size.x - 96.0))
	if size.x > 64.0:
		box_w = minf(box_w, size.x - 96.0)
	var box_h := 460.0
	_confirm_box.anchor_left = 0.5
	_confirm_box.anchor_right = 0.5
	_confirm_box.anchor_top = 0.5
	_confirm_box.anchor_bottom = 0.5
	_confirm_box.offset_left = -box_w * 0.5
	_confirm_box.offset_right = box_w * 0.5
	_confirm_box.offset_top = -box_h * 0.5
	_confirm_box.offset_bottom = box_h * 0.5


func _animate_coins(from_n: int, to_n: int) -> void:
	if _coin_tw != null and _coin_tw.is_valid():
		_coin_tw.kill()
	_coin_tw = null
	if from_n == to_n:
		_paint_coins(to_n)
		return
	_coin_tw = create_tween()
	_coin_tw.tween_method(_tween_coins, float(from_n), float(to_n), 0.55)


func _tween_coins(v: float) -> void:
	_paint_coins(int(round(v)))


func _paint_coins(n: int) -> void:
	_coins_label.text = "%s: %d" % [SettingsData.t("coins"), n]
	_paint(_coins_label, 32)
	UiFit.fit_label(_coins_label, 240.0, 1, 18, 32)


func _flash(card: Control) -> void:
	var fx := ColorRect.new()
	fx.color = Color(1.0, 0.96, 0.82, 1.0)
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	fx.modulate.a = 0.0
	card.add_child(fx)
	var tw := fx.create_tween()
	tw.tween_property(fx, "modulate:a", 0.72, 0.08)
	tw.tween_property(fx, "modulate:a", 0.0, 0.28)
	tw.tween_callback(func() -> void:
		if is_instance_valid(fx):
			fx.queue_free()
	)


func _box(bg: Color, border: Color, width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style


func _paint(node: Control, px: int) -> void:
	UiFit.paint_light(node, px)
	node.add_theme_font_size_override("font_size", px)


func _hide_bar(bar: ScrollBar) -> void:
	if bar == null:
		return
	bar.custom_minimum_size = Vector2.ZERO
	bar.modulate.a = 0.0
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _tex(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var res := load(path)
	if res is Texture2D:
		return res
	return null


func _play(key: String) -> void:
	var am := get_node_or_null("/root/AudioManager")
	if am != null and am.has_method("play_sfx"):
		am.play_sfx(key)
