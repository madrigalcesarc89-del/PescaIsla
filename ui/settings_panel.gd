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
@onready var _credits_t: Label = $Center/Panel/VBox/CreditsTitle
@onready var _credits_b: Label = $Center/Panel/VBox/CreditsBody
@onready var _close_btn: Button = $Center/Panel/VBox/BtnCenter/CloseBtn


func _ready() -> void:
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
	_credits_t.text = SettingsData.t("credits_t")
	_credits_b.text = SettingsData.t("credits_body")
	_close_btn.text = SettingsData.t("close")
	_paint_lang()
	UiFit.fit_label(_title, 460.0, 1, 36, 56)
	UiFit.fit_label(_music_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_sfx_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_vib_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_lang_label, 200.0, 1, 28, 40)
	UiFit.fit_label(_credits_t, 460.0, 1, 30, 44)
	UiFit.fit_label(_credits_b, 460.0, 4, 24, 30)
	UiFit.fit_label(_close_btn, 340.0, 1, 32, 44)


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
	_switch_thumb.position = Vector2(64, 8) if SettingsData.vibration else Vector2(8, 8)


func _paint_lang() -> void:
	_btn_es.disabled = SettingsData.lang == "es"
	_btn_en.disabled = SettingsData.lang == "en"
