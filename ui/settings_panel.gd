extends Control
## 19f: panel de ajustes (musica, efectos, vibracion, idioma, creditos).
## Guarda en user://settings.json y aplica al momento.

signal lang_changed

@onready var _title: Label = $Center/Panel/VBox/Title
@onready var _music_label: Label = $Center/Panel/VBox/MusicRow/MusicLabel
@onready var _music_slider: HSlider = $Center/Panel/VBox/MusicRow/MusicSlider
@onready var _sfx_label: Label = $Center/Panel/VBox/SfxRow/SfxLabel
@onready var _sfx_slider: HSlider = $Center/Panel/VBox/SfxRow/SfxSlider
@onready var _vib_label: Label = $Center/Panel/VBox/VibRow/VibLabel
@onready var _switch: Button = $Center/Panel/VBox/VibRow/Switch
@onready var _switch_track: Panel = $Center/Panel/VBox/VibRow/Switch/Track
@onready var _switch_thumb: Panel = $Center/Panel/VBox/VibRow/Switch/Thumb
@onready var _lang_label: Label = $Center/Panel/VBox/LangRow/LangLabel
@onready var _btn_es: Button = $Center/Panel/VBox/LangRow/LangBtns/BtnES
@onready var _btn_en: Button = $Center/Panel/VBox/LangRow/LangBtns/BtnEN
@onready var _credits_b: Label = $Center/Panel/VBox/CreditsBody
@onready var _close_btn: Button = $Center/Panel/VBox/BtnCenter/CloseBtn

var _time_label: Label
var _btn_cycle: Button
var _btn_clock: Button


func _ready() -> void:
	_build_time_row()
	for sb in ["normal", "hover", "pressed", "focus", "disabled"]:
		_switch.add_theme_stylebox_override(sb, StyleBoxEmpty.new())
	var th := theme
	if th != null and th.has_stylebox("grabber_area", "HSlider"):
		_switch_thumb.add_theme_stylebox_override("panel", th.get_stylebox("grabber_area", "HSlider"))
	_switch.pressed.connect(_on_switch)
	_music_slider.value_changed.connect(_on_music)
	_sfx_slider.value_changed.connect(_on_sfx)
	_btn_es.pressed.connect(_on_lang.bind("es"))
	_btn_en.pressed.connect(_on_lang.bind("en"))
	_close_btn.pressed.connect(_on_close)
	visible = false


func show_panel() -> void:
	refresh_texts()
	_music_slider.set_value_no_signal(SettingsData.music)
	_sfx_slider.set_value_no_signal(SettingsData.sfx)
	_paint_switch()
	_paint_lang()
	visible = true


func refresh_texts() -> void:
	_title.text = SettingsData.t("settings")
	_music_label.text = SettingsData.t("music")
	_sfx_label.text = SettingsData.t("sfx")
	_vib_label.text = SettingsData.t("vibration")
	_lang_label.text = SettingsData.t("language")
	_credits_b.text = "Cesar Madrigal Castro"
	_close_btn.text = SettingsData.t("close")
	if _time_label != null:
		_time_label.text = SettingsData.t("settings_time")
	if _btn_cycle != null:
		_btn_cycle.text = SettingsData.t("settings_time_cycle")
	if _btn_clock != null:
		_btn_clock.text = SettingsData.t("settings_time_clock")
	_paint_lang()
	_paint_time()
	for l in [_title, _music_label, _sfx_label, _vib_label, _lang_label, _credits_b]:
		UiFit.paint_light(l, 40)
	if _time_label != null:
		UiFit.paint_light(_time_label, 40)
	UiFit.fit_label(_title, 460.0, 1, 36, 56)
	UiFit.fit_label(_music_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_sfx_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_vib_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_lang_label, 200.0, 1, 28, 40)
	if _time_label != null:
		UiFit.fit_label(_time_label, 220.0, 2, 22, 36)
	UiFit.fit_label(_credits_b, 460.0, 1, 22, 26)
	UiFit.fit_label(_close_btn, 340.0, 1, 32, 44)
	if _btn_cycle != null:
		UiFit.fit_label(_btn_cycle, 140.0, 1, 22, 32)
	if _btn_clock != null:
		UiFit.fit_label(_btn_clock, 140.0, 1, 22, 32)


func _on_music(v: float) -> void:
	SettingsData.music = v
	SettingsData.apply_audio()
	SettingsData.save_all()


func _on_sfx(v: float) -> void:
	SettingsData.sfx = v
	SettingsData.apply_audio()
	SettingsData.save_all()


func _on_switch() -> void:
	SettingsData.vibration = not SettingsData.vibration
	SettingsData.save_all()
	_paint_switch()


func _on_lang(l: String) -> void:
	if SettingsData.lang == l:
		return
	SettingsData.lang = l
	SettingsData.save_all()
	refresh_texts()
	lang_changed.emit()


func _on_close() -> void:
	SettingsData.save_all()
	visible = false


func _paint_switch() -> void:
	var th := theme
	var key := "SwitchOn" if SettingsData.vibration else "SwitchOff"
	if th != null and th.has_stylebox("panel", key):
		_switch_track.add_theme_stylebox_override("panel", th.get_stylebox("panel", key))
	_switch_thumb.position = Vector2(68, 10) if SettingsData.vibration else Vector2(8, 10)


func _paint_lang() -> void:
	# Activo resaltado (durazno), inactivo neutro (gris) sin deshabilitar.
	var th := theme
	var gray: StyleBox = null
	if th != null and th.has_stylebox("disabled", "Button"):
		gray = th.get_stylebox("disabled", "Button")
	for b in [_btn_es, _btn_en]:
		(b as Button).disabled = false
	var active := _btn_es if SettingsData.lang == "es" else _btn_en
	var idle := _btn_en if SettingsData.lang == "es" else _btn_es
	(active as Button).remove_theme_stylebox_override("normal")
	if gray != null:
		(idle as Button).add_theme_stylebox_override("normal", gray)


func _build_time_row() -> void:
	var vbox := _credits_b.get_parent()
	var row := HBoxContainer.new()
	row.name = "TimeRow"
	row.add_theme_constant_override("separation", 16)
	_time_label = Label.new()
	_time_label.custom_minimum_size = Vector2(220, 0)
	_time_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	var press := load("res://ui/pressable.gd")
	_btn_cycle = Button.new()
	_btn_cycle.custom_minimum_size = Vector2(160, 132)
	_btn_cycle.focus_mode = Control.FOCUS_NONE
	_btn_cycle.set_script(press)
	_btn_clock = Button.new()
	_btn_clock.custom_minimum_size = Vector2(160, 132)
	_btn_clock.focus_mode = Control.FOCUS_NONE
	_btn_clock.set_script(press)
	box.add_child(_btn_cycle)
	box.add_child(_btn_clock)
	row.add_child(_time_label)
	row.add_child(box)
	vbox.add_child(row)
	vbox.move_child(row, _credits_b.get_index())
	_btn_cycle.pressed.connect(_on_time.bind("cycle"))
	_btn_clock.pressed.connect(_on_time.bind("clock"))


func _on_time(mode: String) -> void:
	if SettingsData.time_mode == mode:
		_paint_time()
		return
	SettingsData.time_mode = mode
	SettingsData.save_all()
	_paint_time()


func _paint_time() -> void:
	if _btn_cycle == null or _btn_clock == null:
		return
	var th := theme
	var gray: StyleBox = null
	if th != null and th.has_stylebox("disabled", "Button"):
		gray = th.get_stylebox("disabled", "Button")
	for b in [_btn_cycle, _btn_clock]:
		(b as Button).disabled = false
	var active := _btn_cycle if SettingsData.time_mode != "clock" else _btn_clock
	var idle := _btn_clock if SettingsData.time_mode != "clock" else _btn_cycle
	(active as Button).remove_theme_stylebox_override("normal")
	if gray != null:
		(idle as Button).add_theme_stylebox_override("normal", gray)
