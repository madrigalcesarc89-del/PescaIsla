extends Control
## 19c: HUD definitivo (pildoras del tema, botones 9-slice, barra con marco).
## Todo vive en CanvasLayer; el area segura la aplica fishing al raiz.

signal action_pressed
signal hold_down
signal hold_up
signal album_pressed
signal shop_pressed
signal settings_pressed

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


func _ready() -> void:
	var th := theme
	if th != null and th.has_stylebox("panel", "PillCoins"):
		var pill: StyleBox = th.get_stylebox("panel", "PillCoins")
		for p in [_coins_pill, _hint_pill, _reel_pill, _soon, _toast_pill]:
			(p as PanelContainer).add_theme_stylebox_override("panel", pill)
	resized.connect(_fit_pills)
	_action_btn.pressed.connect(func() -> void: action_pressed.emit())
	_hold_btn.button_down.connect(func() -> void: hold_down.emit())
	_hold_btn.button_up.connect(func() -> void: hold_up.emit())
	_album_btn.pressed.connect(_on_album)
	_shop_btn.pressed.connect(_on_shop)
	_settings_btn.pressed.connect(func() -> void: settings_pressed.emit())
	$SoonPanel/VBox/SoonClose.pressed.connect(_on_soon_close)
	_fit_pills()


func _on_album() -> void:
	album_pressed.emit()


func _on_shop() -> void:
	shop_pressed.emit()


func _on_soon_close() -> void:
	_soon.visible = false


func show_soon(title: String, body: String) -> void:
	_soon_title.text = title
	$SoonPanel/VBox/SoonText.text = body
	$SoonPanel/VBox/BtnCenter/SoonClose.text = SettingsData.t("close")
	_soon.visible = true
	var am := get_node_or_null("/root/AudioManager")
	if am != null:
		am.play_sfx("open")


func set_coins(n: int) -> void:
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
	_fit_one(_hint_pill, _hint_label, Vector2(120, 110), true)
	_fit_one(_reel_pill, _reel_label, Vector2(120, -300), true)


func _fit_one(panel: PanelContainer, lab: Label, pos: Vector2, wide: bool) -> void:
	panel.visible = lab.visible and lab.text != ""
	lab.visible = panel.visible
	if not panel.visible:
		return
	var rw := size
	var ms := lab.get_combined_minimum_size()
	var w: float = ms.x + 60.0
	if panel == _coins_pill:
		w += 56.0 + 12.0
	var h: float = ms.y + 24.0
	if wide:
		w = minf(w, rw.x - 240.0)
		panel.position = Vector2((rw.x - w) * 0.5, pos.y)
	elif pos.y < 0.0:
		panel.position = Vector2(pos.x, rw.y + pos.y - h)
	else:
		panel.position = pos
	panel.size = Vector2(w, h)
