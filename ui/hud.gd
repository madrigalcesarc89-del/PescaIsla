extends Control
## 19c: HUD definitivo (pildoras del tema, botones 9-slice, barra con marco).
## Todo vive en CanvasLayer; el area segura la aplica fishing al raiz.

signal action_pressed
signal hold_down
signal hold_up
signal album_pressed
signal shop_pressed
signal settings_pressed
signal gift_pressed

@onready var _coins_label: Label = $CoinsPill/HBox/CoinsLabel
@onready var _coins_pill: PanelContainer = $CoinsPill
@onready var _hint_label: Label = $HintPill/HintLabel
@onready var _hint_pill: PanelContainer = $HintPill
@onready var _action_btn: Button = $ActionBtn
@onready var _hold_btn: Button = $HoldBtn
@onready var _album_btn: Button = $AlbumBtn
@onready var _shop_btn: Button = $ShopBtn
@onready var _settings_btn: Button = $SettingsBtn
@onready var _reel_box: Control = $ReelBox
@onready var _meter_fill: Control = $ReelBox/MeterFill
@onready var _reel_pill: PanelContainer = $ReelPill
@onready var _reel_label: Label = $ReelPill/ReelLabel
@onready var _bubble: TextureRect = $BubbleAlert
@onready var _toast_pill: PanelContainer = $ToastPill
@onready var _toast_label: Label = $ToastPill/ToastLabel
@onready var _soon: PanelContainer = $SoonPanel
@onready var _soon_title: Label = $SoonPanel/VBox/SoonTitle
var _gift_btn: Button
var _gift_dot: Panel


func _ready() -> void:
	var th := theme
	if th != null and th.has_stylebox("panel", "PillCoins"):
		var pill: StyleBox = th.get_stylebox("panel", "PillCoins")
		for p in [_coins_pill, _hint_pill, _reel_pill, _soon, _toast_pill]:
			(p as PanelContainer).add_theme_stylebox_override("panel", pill)
		# MANTEN como pildora del tema (20f): mantiene button_down/up.
		for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
			_hold_btn.add_theme_stylebox_override(sb, pill)
		_hold_btn.add_theme_color_override("font_color", Color(1.0, 0.98, 0.94))
	resized.connect(_fit_pills)
	_action_btn.pressed.connect(func() -> void: action_pressed.emit())
	_hold_btn.button_down.connect(func() -> void: hold_down.emit())
	_hold_btn.button_up.connect(func() -> void: hold_up.emit())
	_album_btn.pressed.connect(_on_album)
	_shop_btn.pressed.connect(_on_shop)
	_settings_btn.pressed.connect(func() -> void: settings_pressed.emit())
	$SoonPanel/VBox/SoonClose.pressed.connect(_on_soon_close)
	_build_gift()
	_fit_pills()


func _on_album() -> void:
	album_pressed.emit()


func _on_shop() -> void:
	shop_pressed.emit()


func shop_button() -> Button:
	return _shop_btn


func hold_button() -> Button:
	return _hold_btn


func action_button() -> Button:
	return _action_btn


func album_button() -> Button:
	return _album_btn


func reel_box() -> Control:
	return _reel_box


func hint_panel() -> Control:
	return _hint_pill


func gift_button() -> Button:
	return _gift_btn


func bite_alert() -> CanvasItem:
	return _bubble


func _build_gift() -> void:
	_gift_btn = Button.new()
	_gift_btn.name = "GiftBtn"
	_gift_btn.focus_mode = Control.FOCUS_NONE
	_gift_btn.set_script(preload("res://ui/pressable.gd"))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("FFF1D6")
	sb.border_color = Color("5A3D2B")
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(28)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	for state_name in ["normal", "hover", "pressed", "focus", "disabled"]:
		_gift_btn.add_theme_stylebox_override(state_name, sb)
	_gift_btn.add_theme_color_override("font_color", Color("5A3D2B"))
	_gift_btn.pressed.connect(func() -> void: gift_pressed.emit())
	_gift_dot = Panel.new()
	_gift_dot.name = "GiftDot"
	_gift_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := StyleBoxFlat.new()
	dot.bg_color = Color("C4472D")
	dot.set_corner_radius_all(11)
	_gift_dot.add_theme_stylebox_override("panel", dot)
	_gift_dot.size = Vector2(22, 22)
	_gift_dot.visible = false
	_gift_btn.add_child(_gift_dot)
	add_child(_gift_btn)
	refresh_gift_label()


func refresh_gift_label() -> void:
	if _gift_btn == null:
		return
	_gift_btn.text = SettingsData.t("gift")
	UiFit.paint_light(_gift_btn, 28)
	UiFit.fit_label(_gift_btn, 220.0, 1, 18, 28)
	var ms := _gift_btn.get_combined_minimum_size()
	_gift_btn.size = Vector2(maxf(200.0, ms.x + 36.0), maxf(80.0, ms.y + 16.0))
	_place_gift()


func set_gift_ready(on: bool) -> void:
	if _gift_dot != null:
		_gift_dot.visible = on


func _place_gift() -> void:
	if _gift_btn == null:
		return
	var rw := size
	var w := _gift_btn.size.x
	var x := rw.x - 24.0 - w
	var y := 180.0
	if _settings_btn != null:
		var sr := _settings_btn.get_rect()
		x = sr.end.x - w - 6.0
		y = sr.end.y + 16.0
	x = clampf(x, 16.0, maxf(16.0, rw.x - w - 20.0))
	_gift_btn.position = Vector2(x, y)
	if _gift_dot != null:
		_gift_dot.position = Vector2(w - 14.0, -8.0)
		_gift_dot.size = Vector2(22, 22)


func close_soon() -> bool:
	if not _soon.visible:
		return false
	_soon.visible = false
	return true


func is_soon_open() -> bool:
	return _soon.visible


func _on_soon_close() -> void:
	_soon.visible = false


func show_soon(title: String, body: String) -> void:
	_soon_title.text = title
	$SoonPanel/VBox/SoonText.text = body
	$SoonPanel/VBox/BtnCenter/SoonClose.text = SettingsData.t("close")
	UiFit.fit_label(_soon_title, 460.0, 1, 36, 52)
	UiFit.fit_label($SoonPanel/VBox/SoonText, 460.0, 3, 26, 40)
	_soon.visible = true
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")


var _coin_tween: Tween = null
var _coin_target := -1


func set_coins(n: int) -> void:
	if _coin_tween != null and _coin_tween.is_valid() and _coin_tween.is_running() and _coin_target == n:
		return
	_coin_target = n
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	_coin_tween = null
	_apply_coin_text(n)


func animate_coins(from_n: int, to_n: int) -> void:
	_coin_target = to_n
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	if from_n == to_n:
		_apply_coin_text(to_n)
		_coin_tween = null
		return
	_coin_tween = create_tween()
	_coin_tween.tween_method(_tween_coins, float(from_n), float(to_n), 0.6)


func _tween_coins(v: float) -> void:
	_apply_coin_text(int(round(v)))


func _apply_coin_text(n: int) -> void:
	_coins_label.text = "%s: %d" % [SettingsData.t("coins"), n]
	_fit_pills()


func set_hint(t: String) -> void:
	_hint_label.text = t
	_fit_pills()


func show_action(t: String) -> void:
	_action_btn.visible = t != ""
	_action_btn.disabled = t == ""
	_action_btn.text = t


func show_hold(v: bool) -> void:
	_hold_btn.visible = v


func set_hold_text(t: String) -> void:
	_hold_btn.text = t


func show_reel(v: bool) -> void:
	_reel_box.visible = v
	_reel_label.visible = v
	_reel_pill.visible = v
	_album_btn.modulate = Color(1, 1, 1, 0.3 if v else 1.0)
	_shop_btn.modulate = Color(1, 1, 1, 0.3 if v else 1.0)
	_hint_pill.visible = not v
	_hint_label.visible = not v
	_fit_pills()


func set_meter(zc: float, zh: float, m: float, t: String) -> void:
	_meter_fill.set_meter(zc, zh, m)
	_reel_label.text = t
	_fit_pills()


## Burbuja de picada en coords de canvas (null la oculta).
func set_bubble(p: Vector2) -> void:
	if p.x < -9000.0:
		_bubble.visible = false
		return
	_bubble.visible = true
	_bubble.position = p + Vector2(-95.0, -200.0)


## Aviso corto que se desvanece solo a los 1.8 s (20c).
func show_toast(t: String) -> void:
	_toast_label.text = t
	var rw := size
	UiFit.fit_label(_toast_label, rw.x - 300.0, 1, 28, 40)
	var ms := _toast_label.get_combined_minimum_size()
	var w := minf(ms.x + 60.0, rw.x - 240.0)
	_toast_pill.position = Vector2((rw.x - w) * 0.5, rw.y * 0.42)
	_toast_pill.size = Vector2(w, ms.y + 24.0)
	_toast_pill.visible = true
	_toast_pill.modulate = Color(1, 1, 1, 1)
	var tw := create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(_toast_pill, "modulate:a", 0.0, 0.3)
	tw.tween_callback(_toast_pill.hide)


func _fit_pills() -> void:
	var rw := size
	if rw.x <= 0.0:
		return
	_fit_one(_coins_pill, _coins_label, Vector2(24, 24), false)
	_fit_one(_hint_pill, _hint_label, Vector2(120, -470), true)
	_fit_one(_reel_pill, _reel_label, Vector2(120, -300), true)


func _fit_one(panel: PanelContainer, lab: Label, pos: Vector2, wide: bool) -> void:
	panel.visible = lab.visible and lab.text != ""
	lab.visible = panel.visible
	if not panel.visible:
		return
	var rw := size
	var allowed := rw.x - 300.0 if wide else rw.x - 176.0
	var start_px := 44 if panel == _coins_pill else 40
	UiFit.fit_label(lab, allowed, 1, 28, start_px)
	var ms := lab.get_combined_minimum_size()
	var w: float = ms.x + 60.0
	if panel == _coins_pill:
		w += 56.0 + 12.0
	var h: float = ms.y + 24.0
	if wide:
		w = minf(w, rw.x - 240.0)
		var top := pos.y if pos.y >= 0.0 else rw.y + pos.y - h
		panel.position = Vector2((rw.x - w) * 0.5, top)
	elif pos.y < 0.0:
		panel.position = Vector2(pos.x, rw.y + pos.y - h)
	else:
		panel.position = pos
	panel.size = Vector2(w, h)
	_place_gift()
