class_name PauseMenu
extends Control
## In-voyage pause overlay: Resume, Restart level, Settings (embedded SettingsPanel), Quit to map.
##
##   var pm := PauseMenu.new(); pm.set_level(level_def)   # optional subtitle
##   pm.resume_pressed.connect(...); pm.restart_pressed.connect(...); pm.quit_pressed.connect(...)
##   host.add_child(pm)            # full-rect, blocks input underneath, works while the tree is paused
## Esc / `cancel` emits resume_pressed (the host should then free or hide the menu). Restart and Quit ask
## for confirmation first, so `restart_pressed` / `quit_pressed` are already confirmed.
## Re-showing a hidden PauseMenu replays its entrance.

signal resume_pressed
signal restart_pressed
signal quit_pressed

var _backdrop: ColorRect
var _card: PanelContainer
var _settings: SettingsPanel
var _subtitle: Label
var _resume_btn: Button
var _opened_ms: int = 0
var _in_settings: bool = false
var _busy: bool = false
var _center: CenterContainer


func _init() -> void:
	theme = UITheme.build()
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 120
	_backdrop = OvUtil.make_backdrop(0.6)
	add_child(_backdrop)
	_center = CenterContainer.new()
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_center)
	_card = UIKit.card()
	_card.custom_minimum_size = Vector2(560, 0)
	_center.add_child(_card)
	var v := UIKit.vbox(12)
	_card.add_child(UIKit.with_margin(v, 16))
	var head := UIKit.hbox(12)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(UIKit.title_label("Paused"))
	v.add_child(head)
	_subtitle = UIKit.small_label("")
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_subtitle)
	v.add_child(UIKit.v_spacer(4))
	_resume_btn = _big_button("Resume", UIKit.primary_button(""))
	_resume_btn.pressed.connect(func() -> void: resume_pressed.emit())
	v.add_child(_resume_btn)
	var restart := _big_button("Restart level", UIKit.secondary_button(""))
	restart.pressed.connect(_ask_restart)
	v.add_child(restart)
	var sets := _big_button("Settings", UIKit.secondary_button(""))
	sets.pressed.connect(_show_settings)
	v.add_child(sets)
	var quit := _big_button("Quit to map", UIKit.danger_button(""))
	quit.pressed.connect(_ask_quit)
	v.add_child(quit)
	var tip := UIKit.small_label("Esc to resume")
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tip)
	visibility_changed.connect(func() -> void:
		if visible and is_inside_tree() and not _busy:
			open())


func set_level(level: LevelDef) -> void:
	if level == null:
		_subtitle.text = ""
		return
	_subtitle.text = "Level %d  -  %s" % [level.campaign_index, level.display_name]


func _big_button(text: String, b: Button) -> Button:
	b.text = text
	b.custom_minimum_size = Vector2(0, 68)
	OvUtil.focusable(b)
	return b


func _ready() -> void:
	open()


func open() -> void:
	_busy = true
	_in_settings = false
	_opened_ms = Time.get_ticks_msec()
	if _settings != null:
		_settings.visible = false
	_card.visible = true
	_backdrop.modulate.a = 0.0
	_card.pivot_offset = _card.size * 0.5
	_card.scale = Vector2(0.88, 0.88)
	_card.modulate.a = 0.0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_backdrop, "modulate:a", 1.0, 0.18)
	tw.tween_property(_card, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_card, "modulate:a", 1.0, 0.16)
	tw.chain().tween_callback(func() -> void: _busy = false)
	_resume_btn.call_deferred("grab_focus")


func _show_settings() -> void:
	if _settings == null:
		_settings = SettingsPanel.new()
		_settings.back_text = "Back to pause menu"
		_settings.closed.connect(_show_main)
		_center.add_child(_settings)
	_in_settings = true
	_card.visible = false
	_settings.visible = true
	_settings.show_tab(0)
	_settings.modulate.a = 0.0
	_settings.pivot_offset = _settings.size * 0.5
	_settings.scale = Vector2(0.94, 0.94)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(_settings, "modulate:a", 1.0, 0.18)
	tw.tween_property(_settings, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_settings.call_deferred("focus_first")


func _show_main() -> void:
	_in_settings = false
	_opened_ms = Time.get_ticks_msec()
	if _settings != null:
		_settings.visible = false
	_card.visible = true
	_card.modulate.a = 0.0
	create_tween().tween_property(_card, "modulate:a", 1.0, 0.16)
	_resume_btn.call_deferred("grab_focus")


func _ask_restart() -> void:
	var d := ConfirmDialog.present(self, "Restart this voyage?",
			"You will go back to the port with a fresh budget. Progress on this voyage is lost.",
			"Restart", "Keep sailing", false)
	d.confirmed.connect(func(ok: bool) -> void:
		if ok:
			restart_pressed.emit()
		else:
			_resume_btn.grab_focus())


func _ask_quit() -> void:
	var d := ConfirmDialog.present(self, "Quit to the map?",
			"This voyage will be abandoned and no stars will be awarded.",
			"Quit to map", "Keep sailing", true)
	d.confirmed.connect(func(ok: bool) -> void:
		if ok:
			quit_pressed.emit()
		else:
			_resume_btn.grab_focus())


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _in_settings or event is InputEventMouseButton:
		return
	if Time.get_ticks_msec() - _opened_ms < 150:
		return
	if event.is_action_pressed(&"cancel") or event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_pressed.emit()
